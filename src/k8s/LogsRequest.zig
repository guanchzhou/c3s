const std = @import("std");

const keys = @import("ResourceKey.zig");
const lifecycle = @import("LifecycleInbox.zig");
const read_transport = @import("ReadTransport.zig");
const K8sService = @import("../services/K8sService.zig").K8sService;
const LogsView = @import("../view/LogsView.zig").LogsView;
const ViewManager = @import("../viewmodel/ViewManager.zig").ViewManager;

const max_response_bytes = 32 << 20;

pub const LogsPayload = struct {
    generation: keys.Generation,
    subscription_id: keys.SubscriptionId,
    serial: u64,
    pod_name: []u8,
    previous: bool,
    body: []u8,
};

pub const UiTarget = struct {
    view: *LogsView,
    view_manager: *ViewManager,
    active_key: keys.RequestKey,
    active_serial: u64,
    dirty: *bool,
};

pub const Options = struct {
    serial: u64,
    pod_name: []const u8,
    namespace: []const u8,
    previous: bool,
    transport_override: ?read_transport.ReadTransport = null,
};

const Spec = struct {
    serial: u64,
    pod_name: []u8,
    namespace: []u8,
    previous: bool,
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

        const body = try fetchLogs(
            control.allocator,
            transport,
            self.pod_name,
            self.namespace,
            self.previous,
        );
        var body_owned = true;
        errdefer if (body_owned) control.allocator.free(body);
        const pod_name = try control.allocator.dupe(u8, self.pod_name);
        var pod_name_owned = true;
        errdefer if (pod_name_owned) control.allocator.free(pod_name);
        const payload = try control.allocator.create(LogsPayload);
        var payload_owned = true;
        errdefer if (payload_owned) {
            payloadDeinit(payload, control.allocator);
            control.allocator.destroy(payload);
        };
        payload.* = .{
            .generation = self.generation,
            .subscription_id = self.subscription_id,
            .serial = self.serial,
            .pod_name = pod_name,
            .previous = self.previous,
            .body = body,
        };
        body_owned = false;
        pod_name_owned = false;
        const key = keys.RequestKey{
            .generation = self.generation,
            .subscription_id = self.subscription_id,
        };
        var envelope = try keys.erasePayload(
            LogsPayload,
            control.allocator,
            .{ .logs = key },
            payload,
            &payload_handler,
            self.generation,
            self.subscription_id,
            self.serial,
            @sizeOf(LogsPayload) + pod_name.len + body.len,
            null,
        );
        payload_owned = false;
        const outcome = try control.publishDelivery(envelope);
        if (outcome == .abandoned) return;
        envelope = undefined;
        control.finish(.{ .request_finished = .{ .key = key } });
    }

    fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
        const self: *Spec = @ptrCast(@alignCast(raw orelse return));
        allocator.free(self.pod_name);
        allocator.free(self.namespace);
        allocator.destroy(self);
    }
};

pub fn ownedTaskSpec(allocator: std.mem.Allocator, options: Options) !lifecycle.OwnedTaskSpec {
    const spec = try allocator.create(Spec);
    errdefer allocator.destroy(spec);
    spec.* = .{
        .serial = options.serial,
        .pod_name = try allocator.dupe(u8, options.pod_name),
        .namespace = undefined,
        .previous = options.previous,
        .transport_override = options.transport_override,
    };
    errdefer allocator.free(spec.pod_name);
    spec.namespace = try allocator.dupe(u8, options.namespace);
    return .{
        .ptr = spec,
        .alignment = .of(Spec),
        .owned_bytes = @sizeOf(Spec) + spec.pod_name.len + spec.namespace.len,
        .lease_purpose = .logs,
        .bindFn = Spec.bind,
        .runFn = Spec.run,
        .deinitFn = Spec.deinit,
    };
}

const Response = struct {
    status: std.http.Status,
    body: []u8,

    fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
        self.* = undefined;
    }
};

fn get(
    allocator: std.mem.Allocator,
    transport: read_transport.ReadTransport,
    path: []const u8,
) !Response {
    const Capture = struct {
        allocator: std.mem.Allocator,
        response: ?Response = null,

        fn receive(
            raw: *anyopaque,
            meta: read_transport.ResponseMeta,
            reader: *std.Io.Reader,
        ) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            var body: std.ArrayList(u8) = .empty;
            defer body.deinit(self.allocator);
            try reader.appendRemaining(self.allocator, &body, .limited(max_response_bytes));
            self.response = .{
                .status = meta.status,
                .body = try body.toOwnedSlice(self.allocator),
            };
        }
    };
    var capture = Capture{ .allocator = allocator };
    errdefer if (capture.response) |*response| response.deinit(allocator);
    try transport.get(try read_transport.ReadRequest.init(path), &capture, Capture.receive);
    return capture.response orelse error.MissingResponse;
}

fn fetchLogs(
    allocator: std.mem.Allocator,
    transport: read_transport.ReadTransport,
    pod_name: []const u8,
    namespace: []const u8,
    previous: bool,
) ![]u8 {
    const initial_path = try logPath(allocator, pod_name, namespace, previous, null);
    defer allocator.free(initial_path);
    var initial = try get(allocator, transport, initial_path);
    if (initial.status.class() == .success) return initial.body;
    defer initial.deinit(allocator);
    if (!isAmbiguousContainer(initial.status, initial.body)) return error.HttpStatus;

    const pod_path = try podPath(allocator, pod_name, namespace);
    defer allocator.free(pod_path);
    var pod = try get(allocator, transport, pod_path);
    defer pod.deinit(allocator);
    if (pod.status.class() != .success) return error.HttpStatus;
    const container = try firstContainerName(allocator, pod.body);
    defer allocator.free(container);

    const retry_path = try logPath(allocator, pod_name, namespace, previous, container);
    defer allocator.free(retry_path);
    var retry = try get(allocator, transport, retry_path);
    if (retry.status.class() == .success) return retry.body;
    defer retry.deinit(allocator);
    return error.HttpStatus;
}

pub fn podPath(
    allocator: std.mem.Allocator,
    pod_name: []const u8,
    namespace: []const u8,
) ![]u8 {
    if (!read_transport.validPathSegment(pod_name) or
        !read_transport.validPathSegment(namespace))
        return error.InvalidReadPath;
    return std.fmt.allocPrint(
        allocator,
        "/api/v1/namespaces/{s}/pods/{s}",
        .{ namespace, pod_name },
    );
}

pub fn logPath(
    allocator: std.mem.Allocator,
    pod_name: []const u8,
    namespace: []const u8,
    previous: bool,
    container: ?[]const u8,
) ![]u8 {
    if (!read_transport.validPathSegment(pod_name) or
        !read_transport.validPathSegment(namespace))
        return error.InvalidReadPath;
    if (container) |value| {
        if (!read_transport.validQueryValue(value)) return error.InvalidReadPath;
    }
    const query = try K8sService.logQuery(allocator, previous, container);
    defer allocator.free(query);
    return std.fmt.allocPrint(
        allocator,
        "/api/v1/namespaces/{s}/pods/{s}/log?{s}",
        .{ namespace, pod_name, query },
    );
}

fn isAmbiguousContainer(status: std.http.Status, body: []const u8) bool {
    if (status != .bad_request) return false;
    return std.mem.indexOf(u8, body, "container name must be specified") != null or
        std.mem.indexOf(u8, body, "choose one of:") != null;
}

fn firstContainerName(allocator: std.mem.Allocator, body: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.UnexpectedResponse;
    const spec = parsed.value.object.get("spec") orelse return error.UnexpectedResponse;
    if (spec != .object) return error.UnexpectedResponse;
    const containers = spec.object.get("containers") orelse return error.UnexpectedResponse;
    if (containers != .array or containers.array.items.len == 0)
        return error.UnexpectedResponse;
    const first = containers.array.items[0];
    if (first != .object) return error.UnexpectedResponse;
    const name = first.object.get("name") orelse return error.UnexpectedResponse;
    if (name != .string) return error.UnexpectedResponse;
    return allocator.dupe(u8, name.string);
}

fn payloadPreflight(
    payload: *LogsPayload,
    router: *keys.UiRouter,
    allocator: std.mem.Allocator,
) anyerror!keys.ApplyPlan {
    const key = keys.RequestKey{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    };
    const target_raw = router.target(.{ .logs = key }) orelse return error.StaleLogsTarget;
    const target: *UiTarget = @ptrCast(@alignCast(target_raw));
    if (!target.active_key.eql(key) or target.active_serial != payload.serial)
        return error.StaleLogsTarget;
    try target.view_manager.view_ptrs.ensureUnusedCapacity(allocator, 1);
    try target.view_manager.view_vtables.ensureUnusedCapacity(allocator, 1);
    return .{};
}

fn payloadCommit(
    payload: *LogsPayload,
    router: *keys.UiRouter,
    _: *keys.ApplyPlan,
) void {
    const key = keys.RequestKey{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    };
    const target_raw = router.target(.{ .logs = key }) orelse return;
    const target: *UiTarget = @ptrCast(@alignCast(target_raw));
    if (!target.active_key.eql(key) or target.active_serial != payload.serial) return;
    target.view.setContent(payload.body, payload.pod_name) catch return;
    target.view_manager.pushView(target.view.createView()) catch return;
    target.dirty.* = true;
}

fn payloadDeinit(payload: *LogsPayload, allocator: std.mem.Allocator) void {
    allocator.free(payload.pod_name);
    allocator.free(payload.body);
}

pub const payload_handler = keys.PayloadHandler(LogsPayload){
    .preflight = payloadPreflight,
    .commit = payloadCommit,
    .deinit = payloadDeinit,
};

test "current previous and fallback log paths use only GET-safe requests" {
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const scripts = [_]@import("FakeTransport.zig").ResponseScript{
        .{ .body = "current" },
        .{
            .status = .bad_request,
            .body = "a container name must be specified for pod",
        },
        .{ .body = "{\"spec\":{\"containers\":[{\"name\":\"app\"}]}}" },
        .{ .body = "previous" },
    };
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    const current = try fetchLogs(
        std.testing.allocator,
        fake.transport(),
        "pod-a",
        "team-a",
        false,
    );
    defer std.testing.allocator.free(current);
    const previous = try fetchLogs(
        std.testing.allocator,
        fake.transport(),
        "pod-a",
        "team-a",
        true,
    );
    defer std.testing.allocator.free(previous);
    try std.testing.expectEqualStrings("current", current);
    try std.testing.expectEqualStrings("previous", previous);
    try std.testing.expectEqual(@as(usize, 4), fake.requests.items.len);
    try std.testing.expect(std.mem.indexOf(u8, fake.requests.items[0].path, "/log?") != null);
    try std.testing.expect(std.mem.indexOf(u8, fake.requests.items[1].path, "previous=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, fake.requests.items[3].path, "container=app") != null);
    for (fake.requests.items) |request| _ = try read_transport.ReadRequest.init(request.path);
    try std.testing.expectEqual(
        @as(usize, 1),
        @typeInfo(read_transport.ReadTransport.VTable).@"struct".fields.len,
    );
}

test "failed fallback publishes no replacement body" {
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const scripts = [_]@import("FakeTransport.zig").ResponseScript{
        .{
            .status = .bad_request,
            .body = "a container name must be specified for pod",
        },
        .{ .status = .forbidden, .body = "forbidden" },
    };
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    try std.testing.expectError(
        error.HttpStatus,
        fetchLogs(std.testing.allocator, fake.transport(), "pod-a", "team-a", false),
    );
}

pub fn runTask14LogsIdentityGate() !void {
    const theme_loader = @import("../model/theme_loader.zig");
    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    var view = try LogsView.init(std.testing.allocator, &theme);
    defer view.deinit();
    try view.setContent("existing", "pod-a");
    var manager = try ViewManager.init(std.testing.allocator);
    defer manager.deinit();
    var dirty = false;
    const key = keys.RequestKey{ .generation = 4, .subscription_id = 9 };
    var target = UiTarget{
        .view = &view,
        .view_manager = &manager,
        .active_key = key,
        .active_serial = 2,
        .dirty = &dirty,
    };
    const Route = struct {
        fn route(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *UiTarget = @ptrCast(@alignCast(raw));
            const actual = keys.requestKey(target_value) orelse return null;
            if (!actual.eql(self.active_key)) return null;
            return raw;
        }
    };
    var router = keys.UiRouter{ .context = &target, .targetFn = Route.route };

    const stale = try std.testing.allocator.create(LogsPayload);
    stale.* = .{
        .generation = key.generation,
        .subscription_id = key.subscription_id,
        .serial = 1,
        .pod_name = try std.testing.allocator.dupe(u8, "pod-a"),
        .previous = false,
        .body = try std.testing.allocator.dupe(u8, "stale"),
    };
    var stale_envelope = try keys.erasePayload(
        LogsPayload,
        std.testing.allocator,
        .{ .logs = key },
        stale,
        &payload_handler,
        key.generation,
        key.subscription_id,
        1,
        @sizeOf(LogsPayload),
        null,
    );
    try std.testing.expectError(
        error.StaleLogsTarget,
        stale_envelope.apply(&router, std.testing.allocator),
    );
    stale_envelope.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("existing", view.lines.items[0]);

    const latest = try std.testing.allocator.create(LogsPayload);
    latest.* = .{
        .generation = key.generation,
        .subscription_id = key.subscription_id,
        .serial = 2,
        .pod_name = try std.testing.allocator.dupe(u8, "pod-a"),
        .previous = true,
        .body = try std.testing.allocator.dupe(u8, "latest"),
    };
    var latest_envelope = try keys.erasePayload(
        LogsPayload,
        std.testing.allocator,
        .{ .logs = key },
        latest,
        &payload_handler,
        key.generation,
        key.subscription_id,
        2,
        @sizeOf(LogsPayload),
        null,
    );
    try latest_envelope.apply(&router, std.testing.allocator);
    try std.testing.expectEqualStrings("latest", view.lines.items[0]);
    try std.testing.expect(dirty);
    _ = manager.popView();
}

test "exact latest logs serial commits and stale delivery preserves content" {
    try runTask14LogsIdentityGate();
}

pub fn runTask14DetailLogsGate() !void {
    const klient = @import("klient");
    const runtime = @import("../core/runtime.zig");
    const slot_mod = @import("ActiveSessionSlot.zig");
    const session_mod = @import("ActiveContextSession.zig");
    const supervisor_mod = @import("LifecycleSupervisor.zig");
    const queue_mod = @import("ChangeQueue.zig");
    const plane_mod = @import("DataPlane.zig");
    const ancillary_mod = @import("AncillaryRequests.zig");
    const fake_mod = @import("FakeTransport.zig");
    const detail_mod = @import("DetailRequest.zig");
    const DetailViewType = @import("../view/DetailView.zig").DetailView;
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
    var plane = plane_mod.DataPlane.init(std.testing.allocator, producer, &queue);
    var requests = ancillary_mod.AncillaryRequests.init(
        std.testing.allocator,
        producer,
        &queue,
    );
    defer requests.deinit();

    const detail_scripts = [_]fake_mod.ResponseScript{
        .{ .body = "{\"kind\":\"Pod\",\"metadata\":{\"name\":\"pod-a\"}}" },
        .{ .body = "{\"kind\":\"Pod\",\"metadata\":{\"name\":\"pod-a\"}}" },
        .{ .body = "{\"kind\":\"Pod\",\"metadata\":{\"name\":\"pod-b\"}}" },
        .{ .body = "{\"kind\":\"Pod\",\"metadata\":{\"name\":\"pod-b\"}}" },
    };
    var detail_fake = fake_mod.FakeTransport.init(std.testing.allocator, &detail_scripts);
    defer detail_fake.deinit();
    const log_scripts = [_]fake_mod.ResponseScript{
        .{ .body = "stale line" },
        .{ .body = "line one\nline two" },
    };
    var log_fake = fake_mod.FakeTransport.init(std.testing.allocator, &log_scripts);
    defer log_fake.deinit();
    var detail_spec = try detail_mod.ownedTaskSpec(std.testing.allocator, .{
        .serial = 1,
        .kind = .describe,
        .resource_type = .pods,
        .name = "pod-a",
        .namespace = "default",
        .transport_override = detail_fake.transport(),
    });
    defer detail_spec.deinit(std.testing.allocator);
    const detail_key = try requests.startRequest(.detail, 1, &detail_spec);
    var yaml_spec = try detail_mod.ownedTaskSpec(std.testing.allocator, .{
        .serial = 1,
        .kind = .yaml,
        .resource_type = .pods,
        .name = "pod-a",
        .namespace = "default",
        .transport_override = detail_fake.transport(),
    });
    defer yaml_spec.deinit(std.testing.allocator);
    const yaml_key = try requests.startRequest(.yaml, 1, &yaml_spec);
    var log_spec = try ownedTaskSpec(std.testing.allocator, .{
        .serial = 1,
        .pod_name = "pod-a",
        .namespace = "default",
        .previous = false,
        .transport_override = log_fake.transport(),
    });
    defer log_spec.deinit(std.testing.allocator);
    const log_key = try requests.startRequest(.logs, 1, &log_spec);

    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    var detail_view = try DetailViewType.init(std.testing.allocator, &theme);
    defer detail_view.deinit();
    var yaml_view = try DetailViewType.init(std.testing.allocator, &theme);
    defer yaml_view.deinit();
    var logs_view = try LogsView.init(std.testing.allocator, &theme);
    defer logs_view.deinit();
    var manager = try ViewManager.init(std.testing.allocator);
    defer manager.deinit();
    var dirty = false;
    var detail_target = detail_mod.UiTarget{
        .view = &detail_view,
        .view_manager = &manager,
        .active_key = detail_key,
        .active_serial = 1,
        .dirty = &dirty,
    };
    var yaml_target = detail_mod.UiTarget{
        .view = &yaml_view,
        .view_manager = &manager,
        .active_key = yaml_key,
        .active_serial = 1,
        .dirty = &dirty,
    };
    var logs_target = UiTarget{
        .view = &logs_view,
        .view_manager = &manager,
        .active_key = log_key,
        .active_serial = 1,
        .dirty = &dirty,
    };
    const Route = struct {
        plane: *plane_mod.DataPlane,
        requests: *ancillary_mod.AncillaryRequests,
        detail: *detail_mod.UiTarget,
        yaml: *detail_mod.UiTarget,
        logs: *UiTarget,

        fn target(raw: *anyopaque, value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return switch (value) {
                .lifecycle => @ptrCast(self.plane),
                .detail => |key| if (self.requests.contains(key, .detail))
                    @ptrCast(self.detail)
                else
                    null,
                .yaml => |key| if (self.requests.contains(key, .yaml))
                    @ptrCast(self.yaml)
                else
                    null,
                .logs => |key| if (self.requests.contains(key, .logs))
                    @ptrCast(self.logs)
                else
                    null,
                else => null,
            };
        }

        fn observe(raw: *anyopaque, payload: *anyopaque, _: ?keys.ResourceIdentity) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const completion: *lifecycle.LifecycleCompletion = @ptrCast(@alignCast(payload));
            _ = self.requests.handleCompletion(completion.*);
        }
    };
    var route = Route{
        .plane = &plane,
        .requests = &requests,
        .detail = &detail_target,
        .yaml = &yaml_target,
        .logs = &logs_target,
    };
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
    var stale_detail: ?keys.Envelope = null;
    var stale_yaml: ?keys.Envelope = null;
    var stale_logs: ?keys.Envelope = null;
    var deferred_lifecycle = [_]?keys.Envelope{null} ** 3;
    var deferred_count: usize = 0;
    defer for (&deferred_lifecycle) |*envelope| {
        if (envelope.*) |*value| value.deinit(std.testing.allocator);
    };
    for (0..10_000) |_| {
        while (queue.pop()) |value| {
            var envelope = value;
            switch (envelope.target) {
                .detail => |key| if (key.eql(detail_key)) {
                    stale_detail = envelope;
                    continue;
                },
                .yaml => |key| if (key.eql(yaml_key)) {
                    stale_yaml = envelope;
                    continue;
                },
                .logs => |key| if (key.eql(log_key)) {
                    stale_logs = envelope;
                    continue;
                },
                else => {},
            }
            if (envelope.target == .lifecycle) {
                if (deferred_count >= deferred_lifecycle.len)
                    return error.TooManyDeferredCompletions;
                deferred_lifecycle[deferred_count] = envelope;
                deferred_count += 1;
            } else {
                envelope.deinit(std.testing.allocator);
            }
        }
        if (stale_detail != null and stale_yaml != null and stale_logs != null) break;
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    try std.testing.expectEqual(ancillary_mod.CancelResult.requested, requests.cancelRequest(detail_key));
    try std.testing.expectEqual(ancillary_mod.CancelResult.requested, requests.cancelRequest(yaml_key));
    try std.testing.expectEqual(ancillary_mod.CancelResult.requested, requests.cancelRequest(log_key));

    var replacement_detail_spec = try detail_mod.ownedTaskSpec(std.testing.allocator, .{
        .serial = 2,
        .kind = .describe,
        .resource_type = .pods,
        .name = "pod-b",
        .namespace = "default",
        .transport_override = detail_fake.transport(),
    });
    defer replacement_detail_spec.deinit(std.testing.allocator);
    const replacement_detail_key = try requests.startRequest(.detail, 1, &replacement_detail_spec);
    var replacement_yaml_spec = try detail_mod.ownedTaskSpec(std.testing.allocator, .{
        .serial = 2,
        .kind = .yaml,
        .resource_type = .pods,
        .name = "pod-b",
        .namespace = "default",
        .transport_override = detail_fake.transport(),
    });
    defer replacement_yaml_spec.deinit(std.testing.allocator);
    const replacement_yaml_key = try requests.startRequest(.yaml, 1, &replacement_yaml_spec);
    var replacement_log_spec = try ownedTaskSpec(std.testing.allocator, .{
        .serial = 2,
        .pod_name = "pod-b",
        .namespace = "default",
        .previous = false,
        .transport_override = log_fake.transport(),
    });
    defer replacement_log_spec.deinit(std.testing.allocator);
    const replacement_log_key = try requests.startRequest(.logs, 1, &replacement_log_spec);
    detail_target.active_key = replacement_detail_key;
    detail_target.active_serial = 2;
    yaml_target.active_key = replacement_yaml_key;
    yaml_target.active_serial = 2;
    logs_target.active_key = replacement_log_key;
    logs_target.active_serial = 2;

    var old_detail = stale_detail orelse return error.MissingStaleDetail;
    var old_yaml = stale_yaml orelse return error.MissingStaleYaml;
    var old_logs = stale_logs orelse return error.MissingStaleLogs;
    try old_detail.apply(&router, std.testing.allocator);
    try old_yaml.apply(&router, std.testing.allocator);
    try old_logs.apply(&router, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), detail_view.lines.items.len);
    try std.testing.expectEqual(@as(usize, 0), yaml_view.lines.items.len);
    try std.testing.expectEqual(@as(usize, 0), logs_view.lines.items.len);
    for (deferred_lifecycle[0..deferred_count]) |*envelope| {
        if (envelope.*) |*value| try value.apply(&router, std.testing.allocator);
        envelope.* = null;
    }

    for (0..10_000) |_| {
        while (queue.pop()) |value| {
            var envelope = value;
            if (envelope.target != .lifecycle and !requests.acceptsEnvelope(envelope)) {
                envelope.deinit(std.testing.allocator);
                continue;
            }
            try envelope.apply(&router, std.testing.allocator);
        }
        if (requests.trackedCount() == 0) break;
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    try std.testing.expectEqual(@as(usize, 0), requests.trackedCount());
    try std.testing.expect(detail_view.lines.items.len > 0);
    try std.testing.expect(yaml_view.lines.items.len > 0);
    try std.testing.expectEqualStrings("line one", logs_view.lines.items[0]);
    try std.testing.expectEqual(@as(usize, 4), detail_fake.requests.items.len);
    try std.testing.expectEqual(@as(usize, 2), log_fake.requests.items.len);
    try std.testing.expectEqual(@as(usize, 0), active_session.leaseCount());
}

test "real supervisor applies detail and logs through ChangeQueue" {
    try runTask14DetailLogsGate();
}
