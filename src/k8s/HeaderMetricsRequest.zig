const std = @import("std");
const klient = @import("klient");

const keys = @import("ResourceKey.zig");
const lifecycle = @import("LifecycleInbox.zig");
const read_transport = @import("ReadTransport.zig");
const Header = @import("../ui/Header.zig").Header;

pub const metrics_path = "/apis/metrics.k8s.io/v1beta1/nodes";
pub const nodes_path = "/api/v1/nodes";
const max_response_bytes = 16 << 20;

pub const HeaderMetricsPayload = struct {
    generation: keys.Generation,
    subscription_id: keys.SubscriptionId,
    total_cpu_millicores: u64,
    total_mem_bytes: u64,
    node_count: u32,
    capacity_cpu_millicores: u64,
    capacity_mem_bytes: u64,
};

pub const Options = struct {
    transport_override: ?read_transport.ReadTransport = null,
};

const Spec = struct {
    transport_override: ?read_transport.ReadTransport,
    generation: keys.Generation = 0,
    subscription_id: keys.SubscriptionId = 0,

    fn bind(
        raw: ?*anyopaque,
        generation: keys.Generation,
        subscription_id: keys.SubscriptionId,
    ) void {
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

        const usage = try fetchUsage(control.allocator, transport);
        const capacity = try fetchCapacity(control.allocator, transport);
        const payload = try control.allocator.create(HeaderMetricsPayload);
        payload.* = .{
            .generation = self.generation,
            .subscription_id = self.subscription_id,
            .total_cpu_millicores = usage.cpu_millicores,
            .total_mem_bytes = usage.mem_bytes,
            .node_count = capacity.node_count,
            .capacity_cpu_millicores = capacity.cpu_millicores,
            .capacity_mem_bytes = capacity.mem_bytes,
        };
        var envelope = keys.erasePayload(
            HeaderMetricsPayload,
            control.allocator,
            .{ .header_metrics = .{
                .generation = self.generation,
                .subscription_id = self.subscription_id,
            } },
            payload,
            &payload_handler,
            self.generation,
            self.subscription_id,
            0,
            @sizeOf(HeaderMetricsPayload),
            null,
        ) catch |err| {
            control.allocator.destroy(payload);
            return err;
        };
        const outcome = try control.publishDelivery(envelope);
        if (outcome == .abandoned) return;
        envelope = undefined;
    }

    fn deinit(
        raw: ?*anyopaque,
        _: std.mem.Alignment,
        allocator: std.mem.Allocator,
    ) void {
        const self: *Spec = @ptrCast(@alignCast(raw orelse return));
        allocator.destroy(self);
    }
};

pub fn ownedTaskSpec(
    allocator: std.mem.Allocator,
    options: Options,
) !lifecycle.OwnedTaskSpec {
    const spec = try allocator.create(Spec);
    spec.* = .{ .transport_override = options.transport_override };
    return .{
        .ptr = spec,
        .alignment = .of(Spec),
        .owned_bytes = @sizeOf(Spec),
        .lease_purpose = .header_metrics,
        .bindFn = Spec.bind,
        .runFn = Spec.run,
        .deinitFn = Spec.deinit,
    };
}

const Totals = struct {
    cpu_millicores: u64 = 0,
    mem_bytes: u64 = 0,
    node_count: u32 = 0,
};

fn fetchUsage(
    allocator: std.mem.Allocator,
    transport: read_transport.ReadTransport,
) !Totals {
    return fetchTotals(allocator, transport, metrics_path, parseUsage);
}

fn fetchCapacity(
    allocator: std.mem.Allocator,
    transport: read_transport.ReadTransport,
) !Totals {
    return fetchTotals(allocator, transport, nodes_path, parseCapacity);
}

fn fetchTotals(
    allocator: std.mem.Allocator,
    transport: read_transport.ReadTransport,
    path: []const u8,
    comptime parse: fn (std.mem.Allocator, []const u8) anyerror!Totals,
) !Totals {
    const Capture = struct {
        allocator: std.mem.Allocator,
        totals: ?Totals = null,

        fn receive(
            raw: *anyopaque,
            meta: read_transport.ResponseMeta,
            reader: *std.Io.Reader,
        ) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (meta.status.class() != .success) return error.HttpStatus;
            var body: std.ArrayList(u8) = .empty;
            defer body.deinit(self.allocator);
            try reader.appendRemaining(self.allocator, &body, .limited(max_response_bytes));
            self.totals = try parse(self.allocator, body.items);
        }
    };
    var capture = Capture{ .allocator = allocator };
    try transport.get(try read_transport.ReadRequest.init(path), &capture, Capture.receive);
    return capture.totals orelse error.MissingResponse;
}

fn parseUsage(allocator: std.mem.Allocator, body: []const u8) !Totals {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const items = try listItems(parsed.value);
    var totals = Totals{};
    for (items) |item| {
        if (item != .object) return error.MalformedNodeMetrics;
        const usage = item.object.get("usage") orelse return error.MalformedNodeMetrics;
        if (usage != .object) return error.MalformedNodeMetrics;
        const cpu = usage.object.get("cpu") orelse return error.MalformedNodeMetrics;
        const memory = usage.object.get("memory") orelse return error.MalformedNodeMetrics;
        if (cpu != .string or memory != .string) return error.MalformedNodeMetrics;
        const cpu_value = klient.MetricsClient.parseCpuMillicores(cpu.string) orelse
            return error.MalformedCpuQuantity;
        const memory_value = klient.MetricsClient.parseMemoryBytes(memory.string) orelse
            return error.MalformedMemoryQuantity;
        totals.cpu_millicores = std.math.add(u64, totals.cpu_millicores, cpu_value) catch
            return error.QuantityOverflow;
        totals.mem_bytes = std.math.add(u64, totals.mem_bytes, memory_value) catch
            return error.QuantityOverflow;
    }
    return totals;
}

fn parseCapacity(allocator: std.mem.Allocator, body: []const u8) !Totals {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const items = try listItems(parsed.value);
    var totals = Totals{};
    for (items) |item| {
        if (item != .object) return error.MalformedNode;
        const status = item.object.get("status") orelse return error.MalformedNode;
        if (status != .object) return error.MalformedNode;
        const capacity = status.object.get("capacity") orelse return error.MalformedNode;
        if (capacity != .object) return error.MalformedNode;
        const cpu = capacity.object.get("cpu") orelse return error.MalformedNode;
        const memory = capacity.object.get("memory") orelse return error.MalformedNode;
        if (cpu != .string or memory != .string) return error.MalformedNode;
        const cpu_value = klient.MetricsClient.parseCpuMillicores(cpu.string) orelse
            return error.MalformedCpuQuantity;
        const memory_value = klient.MetricsClient.parseMemoryBytes(memory.string) orelse
            return error.MalformedMemoryQuantity;
        totals.cpu_millicores = std.math.add(u64, totals.cpu_millicores, cpu_value) catch
            return error.QuantityOverflow;
        totals.mem_bytes = std.math.add(u64, totals.mem_bytes, memory_value) catch
            return error.QuantityOverflow;
        totals.node_count = std.math.add(u32, totals.node_count, 1) catch
            return error.NodeCountOverflow;
    }
    return totals;
}

fn listItems(value: std.json.Value) ![]const std.json.Value {
    if (value != .object) return error.MalformedList;
    const items = value.object.get("items") orelse return error.MalformedList;
    if (items != .array) return error.MalformedList;
    return items.array.items;
}

const Prepared = struct {
    cpu_pct: u8,
    mem_pct: u8,
    cpu_str: []u8,
    mem_str: []u8,
};

fn payloadPreflight(
    payload: *HeaderMetricsPayload,
    _: *keys.UiRouter,
    allocator: std.mem.Allocator,
) anyerror!keys.ApplyPlan {
    const cpu_pct = percentage(payload.total_cpu_millicores, payload.capacity_cpu_millicores);
    const mem_pct = percentage(payload.total_mem_bytes, payload.capacity_mem_bytes);
    const prepared = try allocator.create(Prepared);
    errdefer allocator.destroy(prepared);
    const cpu_str = try std.fmt.allocPrint(allocator, "{d}%", .{cpu_pct});
    errdefer allocator.free(cpu_str);
    const mem_str = try std.fmt.allocPrint(allocator, "{d}%", .{mem_pct});
    prepared.* = .{
        .cpu_pct = cpu_pct,
        .mem_pct = mem_pct,
        .cpu_str = cpu_str,
        .mem_str = mem_str,
    };
    return .{
        .scratch = prepared,
        .scratch_alignment = .of(Prepared),
        .deinitFn = preparedDeinit,
    };
}

fn payloadCommit(
    payload: *HeaderMetricsPayload,
    router: *keys.UiRouter,
    plan: *keys.ApplyPlan,
) void {
    const header_raw = router.target(.{ .header_metrics = .{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    } }) orelse return;
    const header: *Header = @ptrCast(@alignCast(header_raw));
    const prepared: *Prepared = @ptrCast(@alignCast(plan.scratch.?));
    const cpu_str = prepared.cpu_str;
    const mem_str = prepared.mem_str;
    prepared.cpu_str = &.{};
    prepared.mem_str = &.{};
    header.updateCpuMem(prepared.cpu_pct, prepared.mem_pct, cpu_str, mem_str);
}

fn preparedDeinit(
    raw: ?*anyopaque,
    _: std.mem.Alignment,
    allocator: std.mem.Allocator,
) void {
    const prepared: *Prepared = @ptrCast(@alignCast(raw orelse return));
    if (prepared.cpu_str.len > 0) allocator.free(prepared.cpu_str);
    if (prepared.mem_str.len > 0) allocator.free(prepared.mem_str);
    allocator.destroy(prepared);
}

fn payloadDeinit(_: *HeaderMetricsPayload, _: std.mem.Allocator) void {}

pub const payload_handler = keys.PayloadHandler(HeaderMetricsPayload){
    .preflight = payloadPreflight,
    .commit = payloadCommit,
    .deinit = payloadDeinit,
};

fn percentage(used: u64, capacity: u64) u8 {
    if (capacity == 0) return 0;
    const value = (@as(u128, used) * 100) / capacity;
    return @intCast(@min(value, 100));
}

test "quantity parsers aggregate real usage and node capacity" {
    const usage = try parseUsage(std.testing.allocator,
        \\{"items":[{"usage":{"cpu":"250m","memory":"1Gi"}},{"usage":{"cpu":"500000000n","memory":"512Mi"}}]}
    );
    try std.testing.expectEqual(@as(u64, 750), usage.cpu_millicores);
    try std.testing.expectEqual(@as(u64, 1536 * 1024 * 1024), usage.mem_bytes);

    const capacity = try parseCapacity(std.testing.allocator,
        \\{"items":[{"status":{"capacity":{"cpu":"2","memory":"4Gi"}}},{"status":{"capacity":{"cpu":"1500m","memory":"2Gi"}}}]}
    );
    try std.testing.expectEqual(@as(u64, 3500), capacity.cpu_millicores);
    try std.testing.expectEqual(@as(u64, 6 * 1024 * 1024 * 1024), capacity.mem_bytes);
    try std.testing.expectEqual(@as(u32, 2), capacity.node_count);
}

test "zero nodes and malformed quantities are explicit" {
    const empty = try parseCapacity(std.testing.allocator, "{\"items\":[]}");
    try std.testing.expectEqual(@as(u32, 0), empty.node_count);
    try std.testing.expectError(
        error.MalformedCpuQuantity,
        parseUsage(std.testing.allocator, "{\"items\":[{\"usage\":{\"cpu\":\"bad\",\"memory\":\"1Gi\"}}]}"),
    );
}

test "fake transport scripts exact GET-only header paths" {
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const scripts = [_]@import("FakeTransport.zig").ResponseScript{
        .{ .body = "{\"items\":[{\"usage\":{\"cpu\":\"1\",\"memory\":\"1Gi\"}}]}" },
        .{ .body = "{\"items\":[{\"status\":{\"capacity\":{\"cpu\":\"4\",\"memory\":\"8Gi\"}}}]}" },
    };
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    const usage = try fetchUsage(std.testing.allocator, fake.transport());
    const capacity = try fetchCapacity(std.testing.allocator, fake.transport());
    try std.testing.expectEqual(@as(u64, 1000), usage.cpu_millicores);
    try std.testing.expectEqual(@as(u64, 4000), capacity.cpu_millicores);
    try std.testing.expectEqualStrings(metrics_path, fake.requests.items[0].path);
    try std.testing.expectEqualStrings(nodes_path, fake.requests.items[1].path);
    const vtable_info = @typeInfo(read_transport.ReadTransport.VTable).@"struct";
    const field_count = if (comptime @hasField(@TypeOf(vtable_info), "fields"))
        vtable_info.fields.len
    else
        vtable_info.field_names.len;
    try std.testing.expectEqual(@as(usize, 1), field_count);
}

pub fn runTask14HeaderIdentityGate() !void {
    const theme_loader = @import("../model/theme_loader.zig");
    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    var header = try Header.init(std.testing.allocator, &theme, false);
    defer header.deinit();

    const Route = struct {
        header: *Header,
        expected: keys.RequestKey,

        fn target(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const key = switch (target_value) {
                .header_metrics => |value| value,
                else => return null,
            };
            if (!key.eql(self.expected)) return null;
            return @ptrCast(self.header);
        }
    };
    const key = keys.RequestKey{ .generation = 5, .subscription_id = 12 };
    var route = Route{ .header = &header, .expected = key };
    var router = keys.UiRouter{ .context = &route, .targetFn = Route.target };

    const payload = try std.testing.allocator.create(HeaderMetricsPayload);
    payload.* = .{
        .generation = key.generation,
        .subscription_id = key.subscription_id,
        .total_cpu_millicores = 750,
        .total_mem_bytes = 3 * 1024 * 1024 * 1024,
        .node_count = 2,
        .capacity_cpu_millicores = 3000,
        .capacity_mem_bytes = 12 * 1024 * 1024 * 1024,
    };
    var envelope = try keys.erasePayload(
        HeaderMetricsPayload,
        std.testing.allocator,
        .{ .header_metrics = key },
        payload,
        &payload_handler,
        key.generation,
        key.subscription_id,
        0,
        @sizeOf(HeaderMetricsPayload),
        null,
    );
    try envelope.apply(&router, std.testing.allocator);
    try std.testing.expectEqual(@as(u8, 25), header.cpu_usage);
    try std.testing.expectEqual(@as(u8, 25), header.mem_usage);
    try std.testing.expectEqualStrings("25%", header.cpu_str);
    try std.testing.expectEqualStrings("25%", header.mem_str);

    const stale_payload = try std.testing.allocator.create(HeaderMetricsPayload);
    stale_payload.* = .{
        .generation = key.generation,
        .subscription_id = key.subscription_id + 1,
        .total_cpu_millicores = 3000,
        .total_mem_bytes = 12 * 1024 * 1024 * 1024,
        .node_count = 2,
        .capacity_cpu_millicores = 3000,
        .capacity_mem_bytes = 12 * 1024 * 1024 * 1024,
    };
    var stale = try keys.erasePayload(
        HeaderMetricsPayload,
        std.testing.allocator,
        .{ .header_metrics = .{
            .generation = stale_payload.generation,
            .subscription_id = stale_payload.subscription_id,
        } },
        stale_payload,
        &payload_handler,
        stale_payload.generation,
        stale_payload.subscription_id,
        0,
        @sizeOf(HeaderMetricsPayload),
        null,
    );
    try stale.apply(&router, std.testing.allocator);
    try std.testing.expectEqualStrings("25%", header.cpu_str);
}

test "exact header identity applies prepared percentages and stale identity drops" {
    try runTask14HeaderIdentityGate();
}

test "header preflight allocation failure leaves the Header unchanged" {
    const theme_loader = @import("../model/theme_loader.zig");
    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    var header = try Header.init(std.testing.allocator, &theme, false);
    defer header.deinit();
    const key = keys.RequestKey{ .generation = 1, .subscription_id = 1 };
    const Route = struct {
        fn target(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            if (keys.requestKey(target_value) == null) return null;
            return raw;
        }
    };
    var router = keys.UiRouter{ .context = &header, .targetFn = Route.target };

    var fail_index: usize = 0;
    while (fail_index < 3) : (fail_index += 1) {
        const payload = try std.testing.allocator.create(HeaderMetricsPayload);
        payload.* = .{
            .generation = key.generation,
            .subscription_id = key.subscription_id,
            .total_cpu_millicores = 1,
            .total_mem_bytes = 1,
            .node_count = 1,
            .capacity_cpu_millicores = 2,
            .capacity_mem_bytes = 2,
        };
        var envelope = try keys.erasePayload(
            HeaderMetricsPayload,
            std.testing.allocator,
            .{ .header_metrics = key },
            payload,
            &payload_handler,
            key.generation,
            key.subscription_id,
            0,
            @sizeOf(HeaderMetricsPayload),
            null,
        );
        var failing = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{ .fail_index = fail_index },
        );
        try std.testing.expectError(
            error.OutOfMemory,
            envelope.apply(&router, failing.allocator()),
        );
        try std.testing.expectEqual(keys.Envelope.State.queued, envelope.state);
        try std.testing.expectEqualStrings("n/a", header.cpu_str);
        try std.testing.expectEqualStrings("n/a", header.mem_str);
        envelope.deinit(std.testing.allocator);
    }
}

pub fn runTask14HeaderMetricsGate() !void {
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

    const scripts = [_]fake_mod.ResponseScript{
        .{ .body = "{\"items\":[{\"usage\":{\"cpu\":\"1\",\"memory\":\"2Gi\"}}]}" },
        .{ .body = "{\"items\":[{\"status\":{\"capacity\":{\"cpu\":\"4\",\"memory\":\"8Gi\"}}}]}" },
        .{ .body = "{\"items\":[{\"usage\":{\"cpu\":\"2\",\"memory\":\"4Gi\"}}]}" },
        .{ .body = "{\"items\":[{\"status\":{\"capacity\":{\"cpu\":\"4\",\"memory\":\"8Gi\"}}}]}" },
    };
    var fake = fake_mod.FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    var spec = try ownedTaskSpec(std.testing.allocator, .{
        .transport_override = fake.transport(),
    });
    defer spec.deinit(std.testing.allocator);
    const request_key = try requests.startRequest(.header_metrics, 1, &spec);

    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    var header = try Header.init(std.testing.allocator, &theme, false);
    defer header.deinit();

    const Route = struct {
        plane: *data_plane_mod.DataPlane,
        requests: *ancillary_mod.AncillaryRequests,
        header: *Header,

        fn target(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return switch (target_value) {
                .lifecycle => @ptrCast(self.plane),
                .header_metrics => |key| if (self.requests.contains(key, .header_metrics))
                    @ptrCast(self.header)
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
    var route = Route{ .plane = &plane, .requests = &requests, .header = &header };
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
    try std.testing.expectEqual(@as(u8, 25), header.cpu_usage);
    try std.testing.expectEqual(@as(u8, 25), header.mem_usage);
    try std.testing.expect(!requests.contains(request_key, .header_metrics));
    var second_spec = try ownedTaskSpec(std.testing.allocator, .{
        .transport_override = fake.transport(),
    });
    defer second_spec.deinit(std.testing.allocator);
    const second_key = try requests.startRequest(.header_metrics, 1, &second_spec);
    try std.testing.expect(second_key.subscription_id != request_key.subscription_id);
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
    try std.testing.expectEqual(@as(u8, 50), header.cpu_usage);
    try std.testing.expectEqual(@as(u8, 50), header.mem_usage);
    try std.testing.expect(!requests.contains(second_key, .header_metrics));
    try std.testing.expectEqual(@as(usize, 4), fake.requests.items.len);
    try std.testing.expectEqual(@as(usize, 0), active_session.leaseCount());
}

test "real supervisor child applies header metrics and completes exact request" {
    try runTask14HeaderMetricsGate();
}
