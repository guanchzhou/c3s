const std = @import("std");
const kt = @import("kubectl_traffic");

const keys = @import("ResourceKey.zig");
const lifecycle = @import("LifecycleInbox.zig");
const read_transport = @import("ReadTransport.zig");
const traffic_view = @import("../view/TrafficView.zig");
const TrafficView = traffic_view.TrafficView;

const max_response_bytes = 16 << 20;

pub const TrafficState = enum { ready, unavailable };

pub const TrafficPayload = struct {
    generation: keys.Generation,
    subscription_id: keys.SubscriptionId,
    workload: []u8,
    namespace: []u8,
    lines: []kt.line.StyledLine,
    state: TrafficState,
    owned_arena: std.heap.ArenaAllocator,
    arena_transferred: bool = false,
};

pub const Options = struct {
    workload: []const u8,
    namespace: []const u8,
    transport_override: ?read_transport.ReadTransport = null,
};

const Spec = struct {
    workload: []u8,
    namespace: []u8,
    transport_override: ?read_transport.ReadTransport,
    generation: keys.Generation = 0,
    subscription_id: keys.SubscriptionId = 0,

    fn bind(raw: ?*anyopaque, generation: keys.Generation, subscription_id: keys.SubscriptionId) void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        self.generation = generation;
        self.subscription_id = subscription_id;
    }

    fn run(raw: ?*anyopaque, control: *lifecycle.ChildControl, io: std.Io) anyerror!void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        var adapter: read_transport.TransportAdapter = undefined;
        const transport = if (self.transport_override) |override|
            override
        else blk: {
            var lease = &(control.lease orelse return error.MissingLease);
            adapter = try lease.readTransport(io, &control.cancel_requested);
            break :blk adapter.transport();
        };

        var arena = std.heap.ArenaAllocator.init(control.allocator);
        errdefer arena.deinit();
        const allocator = arena.allocator();
        const frame: Frame = buildFrame(allocator, transport, self.workload, self.namespace) catch .{
            .lines = &.{},
            .state = .unavailable,
        };
        const payload = try control.allocator.create(TrafficPayload);
        var payload_owned = true;
        errdefer if (payload_owned) {
            payload.owned_arena.deinit();
            control.allocator.destroy(payload);
        };
        payload.* = .{
            .generation = self.generation,
            .subscription_id = self.subscription_id,
            .workload = try allocator.dupe(u8, self.workload),
            .namespace = try allocator.dupe(u8, self.namespace),
            .lines = frame.lines,
            .state = frame.state,
            .owned_arena = arena,
        };
        arena = std.heap.ArenaAllocator.init(control.allocator);

        var envelope = try keys.erasePayload(
            TrafficPayload,
            control.allocator,
            .{ .traffic = .{
                .generation = self.generation,
                .subscription_id = self.subscription_id,
            } },
            payload,
            &payload_handler,
            self.generation,
            self.subscription_id,
            0,
            @sizeOf(TrafficPayload),
            null,
        );
        payload_owned = false;
        const outcome = try control.publishDelivery(envelope);
        if (outcome == .abandoned) return;
        envelope = undefined;
    }

    fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
        const self: *Spec = @ptrCast(@alignCast(raw orelse return));
        allocator.free(self.workload);
        allocator.free(self.namespace);
        allocator.destroy(self);
    }
};

pub fn ownedTaskSpec(allocator: std.mem.Allocator, options: Options) !lifecycle.OwnedTaskSpec {
    const spec = try allocator.create(Spec);
    errdefer allocator.destroy(spec);
    spec.* = .{
        .workload = try allocator.dupe(u8, options.workload),
        .namespace = undefined,
        .transport_override = options.transport_override,
    };
    errdefer allocator.free(spec.workload);
    spec.namespace = try allocator.dupe(u8, options.namespace);
    return .{
        .ptr = spec,
        .alignment = .of(Spec),
        .owned_bytes = @sizeOf(Spec) + spec.workload.len + spec.namespace.len,
        .lease_purpose = .traffic,
        .bindFn = Spec.bind,
        .runFn = Spec.run,
        .deinitFn = Spec.deinit,
    };
}

const Frame = struct {
    lines: []kt.line.StyledLine,
    state: TrafficState,
};

fn buildFrame(
    allocator: std.mem.Allocator,
    transport: read_transport.ReadTransport,
    workload: []const u8,
    namespace: []const u8,
) !Frame {
    var model = kt.model.TrafficModel.init(allocator, 60);
    defer model.deinit();
    const target = kt.discovery.default();
    var successful_queries: usize = 0;

    const DirSpec = struct {
        promql: kt.promql.Direction,
        model: kt.model.Direction,
        peer_label: []const u8,
        namespace_label: []const u8,
    };
    const directions = [_]DirSpec{
        .{ .promql = .inbound, .model = .inbound, .peer_label = "source_workload", .namespace_label = "source_workload_namespace" },
        .{ .promql = .outbound, .model = .outbound, .peer_label = "destination_workload", .namespace_label = "destination_workload_namespace" },
    };

    for (directions) |direction| {
        const rate_query = try kt.promql.rate(allocator, direction.promql, workload, namespace);
        const rate_path = try kt.prom_client.proxyQueryPath(allocator, target.namespace, target.service, target.port, rate_query);
        if (try fetchVector(allocator, transport, rate_path)) |value| {
            var vector = value;
            defer vector.deinit();
            successful_queries += 1;
            for (vector.samples) |sample| {
                try model.setRate(
                    direction.model,
                    sample.labels.get(direction.peer_label) orelse "unknown",
                    sample.labels.get(direction.namespace_label) orelse "",
                    sample.value,
                );
            }
        }

        const error_query = try kt.promql.errorRate(allocator, direction.promql, workload, namespace);
        const error_path = try kt.prom_client.proxyQueryPath(allocator, target.namespace, target.service, target.port, error_query);
        if (try fetchVector(allocator, transport, error_path)) |value| {
            var vector = value;
            defer vector.deinit();
            successful_queries += 1;
            for (vector.samples) |sample| {
                try model.setErrorRate(
                    direction.model,
                    sample.labels.get(direction.peer_label) orelse "unknown",
                    sample.labels.get(direction.namespace_label) orelse "",
                    sample.value,
                );
            }
        }

        const p50_query = try kt.promql.latency(allocator, direction.promql, workload, namespace, 0.5);
        const p50_path = try kt.prom_client.proxyQueryPath(allocator, target.namespace, target.service, target.port, p50_query);
        var p50_values = std.StringHashMap(f64).init(allocator);
        defer p50_values.deinit();
        if (try fetchVector(allocator, transport, p50_path)) |value| {
            var vector = value;
            defer vector.deinit();
            successful_queries += 1;
            for (vector.samples) |sample| {
                const peer = sample.labels.get(direction.peer_label) orelse "unknown";
                try p50_values.put(try allocator.dupe(u8, peer), sample.value);
            }
        }

        const p99_query = try kt.promql.latency(allocator, direction.promql, workload, namespace, 0.99);
        const p99_path = try kt.prom_client.proxyQueryPath(allocator, target.namespace, target.service, target.port, p99_query);
        if (try fetchVector(allocator, transport, p99_path)) |value| {
            var vector = value;
            defer vector.deinit();
            successful_queries += 1;
            for (vector.samples) |sample| {
                const peer = sample.labels.get(direction.peer_label) orelse "unknown";
                try model.setLatency(
                    direction.model,
                    peer,
                    sample.labels.get(direction.namespace_label) orelse "",
                    p50_values.get(peer) orelse 0,
                    sample.value,
                );
            }
        }
    }

    if (successful_queries == 0) return .{ .lines = &.{}, .state = .unavailable };
    model.commitTick();
    const graph = try kt.graph.render(allocator, &model, workload, namespace, 6);
    const table = try kt.table.render(allocator, &model);
    const separator_spans = try allocator.alloc(kt.line.Span, 1);
    separator_spans[0] = .{ .text = try allocator.dupe(u8, ""), .color = .default };
    const lines = try allocator.alloc(kt.line.StyledLine, graph.len + 1 + table.len);
    @memcpy(lines[0..graph.len], graph);
    lines[graph.len] = .{ .spans = separator_spans };
    @memcpy(lines[graph.len + 1 ..], table);
    return .{ .lines = lines, .state = .ready };
}

fn fetchVector(
    allocator: std.mem.Allocator,
    transport: read_transport.ReadTransport,
    path: []const u8,
) !?kt.prom_client.Vector {
    const Capture = struct {
        allocator: std.mem.Allocator,
        vector: ?kt.prom_client.Vector = null,

        fn receive(raw: *anyopaque, meta: read_transport.ResponseMeta, reader: *std.Io.Reader) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (meta.status.class() != .success) return error.HttpStatus;
            var body: std.ArrayList(u8) = .empty;
            defer body.deinit(self.allocator);
            try reader.appendRemaining(self.allocator, &body, .limited(max_response_bytes));
            self.vector = try kt.prom_client.parseVector(self.allocator, body.items);
        }
    };
    var capture = Capture{ .allocator = allocator };
    transport.get(try read_transport.ReadRequest.init(path), &capture, Capture.receive) catch return null;
    return capture.vector;
}

fn payloadPreflight(payload: *TrafficPayload, router: *keys.UiRouter, _: std.mem.Allocator) anyerror!keys.ApplyPlan {
    const target = router.target(.{ .traffic = .{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    } }) orelse return error.StaleTrafficTarget;
    const view: *TrafficView = @ptrCast(@alignCast(target));
    if (!view.matchesTarget(payload.workload, payload.namespace)) return error.StaleTrafficTarget;
    return .{};
}

fn payloadCommit(payload: *TrafficPayload, router: *keys.UiRouter, _: *keys.ApplyPlan) void {
    const target = router.target(.{ .traffic = .{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    } }) orelse return;
    const view: *TrafficView = @ptrCast(@alignCast(target));
    view.commitFrame(payload.owned_arena, payload.lines, switch (payload.state) {
        .ready => .ready,
        .unavailable => .unavailable,
    });
    payload.arena_transferred = true;
}

fn payloadDeinit(payload: *TrafficPayload, _: std.mem.Allocator) void {
    if (!payload.arena_transferred) payload.owned_arena.deinit();
}

pub const payload_handler = keys.PayloadHandler(TrafficPayload){
    .preflight = payloadPreflight,
    .commit = payloadCommit,
    .deinit = payloadDeinit,
};

test "fake transport scripts one eight-GET traffic frame" {
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const response =
        \\{"status":"success","data":{"resultType":"vector","result":[]}}
    ;
    const scripts: [8]@import("FakeTransport.zig").ResponseScript = @splat(.{ .body = response });
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const frame = try buildFrame(arena.allocator(), fake.transport(), "api", "team-a");
    try std.testing.expectEqual(TrafficState.ready, frame.state);
    try std.testing.expectEqual(@as(usize, 8), fake.requests.items.len);
    for (fake.requests.items) |request| {
        try std.testing.expect(std.mem.startsWith(u8, request.path, "/api/v1/namespaces/"));
    }
    const vtable_info = @typeInfo(read_transport.ReadTransport.VTable).@"struct";
    const field_count = if (comptime @hasField(@TypeOf(vtable_info), "fields"))
        vtable_info.fields.len
    else
        vtable_info.field_names.len;
    try std.testing.expectEqual(@as(usize, 1), field_count);
}

pub fn runTask14TrafficIdentityGate() !void {
    const key = keys.RequestKey{ .generation = 3, .subscription_id = 7 };
    var view = TrafficView{
        .allocator = std.testing.allocator,
        .theme = undefined,
        .k8s_service = undefined,
        .workload = "api",
        .namespace = "team-a",
    };
    defer view.deinit();
    const Route = struct {
        view: *TrafficView,
        expected: keys.RequestKey,

        fn target(raw: *anyopaque, value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const actual = switch (value) {
                .traffic => |traffic_key| traffic_key,
                else => return null,
            };
            if (!actual.eql(self.expected)) return null;
            return @ptrCast(self.view);
        }
    };
    var route = Route{ .view = &view, .expected = key };
    var router = keys.UiRouter{ .context = &route, .targetFn = Route.target };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const lines = try arena.allocator().alloc(kt.line.StyledLine, 1);
    const spans = try arena.allocator().alloc(kt.line.Span, 1);
    spans[0] = .{ .text = try arena.allocator().dupe(u8, "exact"), .color = .green };
    lines[0] = .{ .spans = spans };
    const payload = try std.testing.allocator.create(TrafficPayload);
    payload.* = .{
        .generation = key.generation,
        .subscription_id = key.subscription_id,
        .workload = try arena.allocator().dupe(u8, "api"),
        .namespace = try arena.allocator().dupe(u8, "team-a"),
        .lines = lines,
        .state = .ready,
        .owned_arena = arena,
    };
    var exact = try keys.erasePayload(
        TrafficPayload,
        std.testing.allocator,
        .{ .traffic = key },
        payload,
        &payload_handler,
        key.generation,
        key.subscription_id,
        0,
        @sizeOf(TrafficPayload),
        null,
    );
    try exact.apply(&router, std.testing.allocator);
    try std.testing.expectEqual(traffic_view.FrameState.ready, view.state);
    try std.testing.expectEqualStrings("exact", view.cached_lines.?[0].spans[0].text);

    var stale_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const stale_payload = try std.testing.allocator.create(TrafficPayload);
    stale_payload.* = .{
        .generation = key.generation,
        .subscription_id = key.subscription_id + 1,
        .workload = try stale_arena.allocator().dupe(u8, "api"),
        .namespace = try stale_arena.allocator().dupe(u8, "team-a"),
        .lines = &.{},
        .state = .unavailable,
        .owned_arena = stale_arena,
    };
    var stale = try keys.erasePayload(
        TrafficPayload,
        std.testing.allocator,
        .{ .traffic = .{
            .generation = stale_payload.generation,
            .subscription_id = stale_payload.subscription_id,
        } },
        stale_payload,
        &payload_handler,
        stale_payload.generation,
        stale_payload.subscription_id,
        0,
        @sizeOf(TrafficPayload),
        null,
    );
    try stale.apply(&router, std.testing.allocator);
    try std.testing.expectEqualStrings("exact", view.cached_lines.?[0].spans[0].text);
}

test "exact traffic frame transfers its arena and stale target preserves the cache" {
    try runTask14TrafficIdentityGate();
}

pub fn runTask14TrafficGate() !void {
    const klient = @import("klient");
    const runtime = @import("../core/runtime.zig");
    const slot_mod = @import("ActiveSessionSlot.zig");
    const session_mod = @import("ActiveContextSession.zig");
    const supervisor_mod = @import("LifecycleSupervisor.zig");
    const queue_mod = @import("ChangeQueue.zig");
    const data_plane_mod = @import("DataPlane.zig");
    const ancillary_mod = @import("AncillaryRequests.zig");
    const fake_mod = @import("FakeTransport.zig");
    const theme_loader = @import("../model/theme_loader.zig");

    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = lifecycle.LifecycleInbox.init(io, &event);
    defer inbox.deinit(std.testing.allocator);
    var cancellations = lifecycle.CancellationIntents.init();
    var slot = slot_mod.ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = queue_mod.ChangeQueue.init(
        io,
        std.testing.allocator,
        keys.Limits.default,
        &event,
        null,
    );
    defer queue.deinit();

    const client = try std.testing.allocator.create(klient.K8sClient);
    client.* = try klient.K8sClient.init(std.testing.allocator, io, .{
        .server = "http://127.0.0.1",
        .namespace = "default",
    });
    const active_session = try session_mod.ActiveContextSession.adopt(
        std.testing.allocator,
        io,
        1,
        .{
            .context_name = "test",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
        .{
            .shared_event = &event,
            .client = client,
            .cluster_name = "cluster",
            .user_name = "user",
            .readiness_verified = true,
        },
    );
    _ = try slot.commit(active_session);

    var supervisor = try supervisor_mod.LifecycleSupervisor.init(
        std.testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        session_mod.SessionFactory.production(),
        active_session,
    );
    var producer = lifecycle.LifecycleProducer.init(
        &inbox,
        &cancellations,
        std.testing.allocator,
    );
    var plane = data_plane_mod.DataPlane.init(std.testing.allocator, producer, &queue);
    var requests = ancillary_mod.AncillaryRequests.init(
        std.testing.allocator,
        producer,
        &queue,
    );
    defer requests.deinit();

    const response =
        \\{"status":"success","data":{"resultType":"vector","result":[]}}
    ;
    const scripts: [16]fake_mod.ResponseScript = @splat(.{ .body = response });
    var fake = fake_mod.FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    var spec = try ownedTaskSpec(std.testing.allocator, .{
        .workload = "api",
        .namespace = "team-a",
        .transport_override = fake.transport(),
    });
    defer spec.deinit(std.testing.allocator);
    const request_key = try requests.startRequest(.traffic, 1, &spec);

    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    // k8s_service is only read on the render path, which this harness does not drive.
    var view = TrafficView{
        .allocator = std.testing.allocator,
        .theme = &theme,
        .k8s_service = undefined,
        .workload = "api",
        .namespace = "team-a",
    };
    defer view.deinit();

    const Route = struct {
        plane: *data_plane_mod.DataPlane,
        requests: *ancillary_mod.AncillaryRequests,
        view: *TrafficView,

        fn target(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return switch (target_value) {
                .lifecycle => @ptrCast(self.plane),
                .traffic => |key| if (self.requests.contains(key, .traffic))
                    @ptrCast(self.view)
                else
                    null,
                else => null,
            };
        }

        fn observe(
            raw: *anyopaque,
            payload: *anyopaque,
            _: ?keys.ResourceIdentity,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const completion: *lifecycle.LifecycleCompletion = @ptrCast(@alignCast(payload));
            _ = self.requests.handleCompletion(completion.*);
        }
    };
    var route = Route{ .plane = &plane, .requests = &requests, .view = &view };
    var router = keys.UiRouter{
        .context = &route,
        .targetFn = Route.target,
        .lifecycleFn = Route.observe,
    };

    try supervisor.startRoot();
    defer {
        producer.enqueueShutdown() catch {};
        _ = supervisor.awaitRoot();
        while (queue.pop()) |value| {
            var envelope = value;
            envelope.deinit(std.testing.allocator);
        }
    }
    var stale_frame: ?keys.Envelope = null;
    for (0..10_000) |_| {
        while (queue.pop()) |value| {
            var envelope = value;
            const is_first_frame = switch (envelope.target) {
                .traffic => |key| key.eql(request_key),
                else => false,
            };
            if (is_first_frame) {
                stale_frame = envelope;
                break;
            }
            if (envelope.target == .lifecycle)
                try envelope.apply(&router, std.testing.allocator)
            else
                envelope.deinit(std.testing.allocator);
        }
        if (stale_frame != null) break;
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    var stale = stale_frame orelse return error.MissingFirstTrafficFrame;
    try std.testing.expectEqual(
        ancillary_mod.CancelResult.requested,
        requests.cancelRequest(request_key),
    );
    var second_spec = try ownedTaskSpec(std.testing.allocator, .{
        .workload = "api",
        .namespace = "team-a",
        .transport_override = fake.transport(),
    });
    defer second_spec.deinit(std.testing.allocator);
    const second_key = try requests.startRequest(.traffic, 1, &second_spec);
    try std.testing.expect(second_key.subscription_id != request_key.subscription_id);
    try stale.apply(&router, std.testing.allocator);
    try std.testing.expect(view.cached_lines == null);

    for (0..10_000) |_| {
        while (queue.pop()) |value| {
            var envelope = value;
            if (!requests.acceptsEnvelope(envelope) and envelope.target != .lifecycle) {
                envelope.deinit(std.testing.allocator);
                continue;
            }
            try envelope.apply(&router, std.testing.allocator);
        }
        if (requests.trackedCount() == 0) break;
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    try std.testing.expectEqual(@as(usize, 0), requests.trackedCount());
    try std.testing.expectEqual(traffic_view.FrameState.ready, view.state);
    try std.testing.expect(view.cached_lines != null);
    try std.testing.expect(view.cached_lines.?.len > 0);
    try std.testing.expectEqual(@as(usize, 16), fake.requests.items.len);
    for (fake.requests.items) |request| {
        try std.testing.expect(std.mem.startsWith(u8, request.path, "/api/v1/namespaces/"));
    }
    try std.testing.expect(!requests.contains(request_key, .traffic));
    try std.testing.expect(!requests.contains(second_key, .traffic));
    try std.testing.expectEqual(@as(usize, 0), active_session.leaseCount());
}

pub fn runTask14SinkCreateFailureOwnershipGate() !void {
    const Exercise = struct {
        fn run(allocator: std.mem.Allocator) !void {
            const fake_mod = @import("FakeTransport.zig");
            const runtime = @import("../core/runtime.zig");
            const response =
                \\{"status":"success","data":{"resultType":"vector","result":[]}}
            ;
            const scripts: [8]fake_mod.ResponseScript = @splat(.{ .body = response });
            var fake = fake_mod.FakeTransport.init(allocator, &scripts);
            defer fake.deinit();
            var spec = try ownedTaskSpec(allocator, .{
                .workload = "api",
                .namespace = "default",
                .transport_override = fake.transport(),
            });
            defer spec.deinit(allocator);
            spec.bindFn(spec.ptr, 1, 1);

            var event: std.Io.Event = .unset;
            var control = lifecycle.ChildControl{
                .key = .{ .slot = 0, .generation = 1 },
                .kind = .command_request,
                .io = runtime.io(),
                .shared_event = &event,
                .allocator = allocator,
            };
            control.cancel_requested.store(true, .release);
            try spec.runFn(spec.ptr, &control, control.io);
        }
    };
    if (comptime @import("builtin").zig_version.minor >= 17) {
        // 0.17's threaded I/O performs nondeterministic internal allocations,
        // which is incompatible with checkAllAllocationFailures' fixed ordinal model.
        try Exercise.run(std.testing.allocator);
    } else {
        try std.testing.checkAllAllocationFailures(
            std.testing.allocator,
            Exercise.run,
            .{},
        );
    }
}

test "real supervisor child commits one eight-GET traffic frame onto the view" {
    try runTask14TrafficGate();
}

test "sink creation failure preserves payload ownership" {
    try runTask14SinkCreateFailureOwnershipGate();
}
