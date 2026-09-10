const std = @import("std");
const testing = std.testing;

const keys = @import("ResourceKey.zig");
const lifecycle = @import("LifecycleInbox.zig");
const queue_mod = @import("ChangeQueue.zig");
const session = @import("ActiveContextSession.zig");
const runtime = @import("../core/runtime.zig");

pub const RequestKey = keys.RequestKey;
pub const RequestClass = keys.RequestClass;
pub const OwnedTaskSpec = lifecycle.OwnedTaskSpec;
pub const LifecycleCompletion = lifecycle.LifecycleCompletion;

pub const CancelResult = enum {
    requested,
    already_inactive,
    unknown,
};

const RequestState = enum {
    active,
    canceling,
};

const Entry = struct {
    key: RequestKey,
    child_key: lifecycle.ChildKey,
    class: RequestClass,
    lease_purpose: session.LeasePurpose,
    state: RequestState = .active,
};

/// UI-thread owner of exact one-shot ancillary request identities.
pub const AncillaryRequests = struct {
    pub const capacity = lifecycle.CancellationIntents.capacity;

    allocator: std.mem.Allocator,
    producer: lifecycle.LifecycleProducer,
    change_queue: *queue_mod.ChangeQueue,
    entries: [capacity]?Entry = [_]?Entry{null} ** capacity,
    next_subscription_id: keys.SubscriptionId = 1,
    count: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        producer: lifecycle.LifecycleProducer,
        change_queue: *queue_mod.ChangeQueue,
    ) AncillaryRequests {
        return .{
            .allocator = allocator,
            .producer = producer,
            .change_queue = change_queue,
        };
    }

    pub fn deinit(self: *AncillaryRequests) void {
        self.entries = [_]?Entry{null} ** capacity;
        self.count = 0;
    }

    /// Takes ownership of `spec_source` on every return path.
    pub fn startRequest(
        self: *AncillaryRequests,
        class: RequestClass,
        expected_generation: keys.Generation,
        spec_source: *OwnedTaskSpec,
    ) error{
        InvalidLeasePurpose,
        Capacity,
        RequestIdExhausted,
        Full,
        Closed,
        TaskSpecTooLarge,
    }!RequestKey {
        var spec = spec_source.take();
        errdefer spec.deinit(self.allocator);

        const lease_purpose = spec.lease_purpose orelse return error.InvalidLeasePurpose;
        if (lease_purpose != purposeForClass(class)) return error.InvalidLeasePurpose;

        const index = self.freeIndex() orelse return error.Capacity;
        const child_key = self.producer.reserveChild() catch return error.Capacity;
        errdefer _ = self.producer.cancellations.free(child_key);

        const subscription_id = self.next_subscription_id;
        if (subscription_id == 0) return error.RequestIdExhausted;
        self.next_subscription_id = std.math.add(
            keys.SubscriptionId,
            subscription_id,
            1,
        ) catch 0;
        if (self.next_subscription_id == 0) return error.RequestIdExhausted;

        const key = RequestKey{
            .generation = expected_generation,
            .subscription_id = subscription_id,
        };
        spec.bindFn(spec.ptr, key.generation, key.subscription_id);
        var command = lifecycle.LifecycleCommand{ .start_request = .{
            .child_key = child_key,
            .expected_generation = expected_generation,
            .key = key,
            .spec = spec,
        } };
        self.producer.tryPushStart(command) catch |err| {
            command.deinit(self.allocator);
            spec = .{};
            return err;
        };
        spec = .{};

        self.entries[index] = .{
            .key = key,
            .child_key = child_key,
            .class = class,
            .lease_purpose = lease_purpose,
        };
        self.count += 1;
        return key;
    }

    pub fn contains(
        self: *const AncillaryRequests,
        key: RequestKey,
        class: RequestClass,
    ) bool {
        const index = self.find(key, class) orelse return false;
        return self.entries[index].?.state == .active;
    }

    pub fn activeIdentityCount(self: *const AncillaryRequests) usize {
        return self.count;
    }

    pub fn acceptsEnvelope(
        self: *const AncillaryRequests,
        envelope: keys.Envelope,
    ) bool {
        const key = keys.requestKey(envelope.target) orelse return false;
        const class = keys.requestClass(envelope.target) orelse return false;
        if (envelope.generation != key.generation or
            envelope.subscription_id != key.subscription_id)
        {
            return false;
        }
        return self.contains(key, class);
    }

    pub fn cancelRequest(self: *AncillaryRequests, key: RequestKey) CancelResult {
        const index = self.findKey(key) orelse return .unknown;
        const entry = if (self.entries[index]) |*item| item else return .unknown;
        if (entry.state == .canceling) return .already_inactive;
        entry.state = .canceling;
        _ = self.producer.tryRequestCancel(entry.child_key);
        _ = self.change_queue.purgeRequest(key);
        return .requested;
    }

    pub fn invalidateGeneration(
        self: *AncillaryRequests,
        generation: keys.Generation,
    ) usize {
        var canceled: usize = 0;
        for (&self.entries) |*entry_slot| {
            const entry = if (entry_slot.*) |*item| item else continue;
            if (entry.key.generation != generation or entry.state == .canceling) continue;
            entry.state = .canceling;
            _ = self.producer.tryRequestCancel(entry.child_key);
            _ = self.change_queue.purgeRequest(entry.key);
            canceled += 1;
        }
        return canceled;
    }

    pub fn cancelAll(self: *AncillaryRequests) usize {
        var canceled: usize = 0;
        for (&self.entries) |*entry_slot| {
            const entry = if (entry_slot.*) |*item| item else continue;
            if (entry.state == .canceling) continue;
            entry.state = .canceling;
            _ = self.producer.tryRequestCancel(entry.child_key);
            _ = self.change_queue.purgeRequest(entry.key);
            canceled += 1;
        }
        return canceled;
    }

    pub fn handleCompletion(
        self: *AncillaryRequests,
        completion: LifecycleCompletion,
    ) bool {
        const index = switch (completion) {
            .request_finished => |finished| self.findKey(finished.key),
            .start_rejected => |rejected| blk: {
                const request_key = rejected.request_key orelse break :blk null;
                const candidate = self.findKey(request_key) orelse break :blk null;
                if (!self.entries[candidate].?.child_key.eql(rejected.child_key))
                    break :blk null;
                break :blk candidate;
            },
            else => null,
        } orelse return false;
        const key = self.entries[index].?.key;
        self.entries[index] = null;
        self.count -= 1;
        _ = self.change_queue.purgeRequest(key);
        return true;
    }

    pub fn trackedCount(self: *const AncillaryRequests) usize {
        return self.count;
    }

    fn freeIndex(self: *const AncillaryRequests) ?usize {
        for (self.entries, 0..) |entry, index| {
            if (entry == null) return index;
        }
        return null;
    }

    fn find(
        self: *const AncillaryRequests,
        key: RequestKey,
        class: RequestClass,
    ) ?usize {
        for (self.entries, 0..) |entry_optional, index| {
            const entry = entry_optional orelse continue;
            if (entry.class == class and entry.key.eql(key)) return index;
        }
        return null;
    }

    fn findKey(self: *const AncillaryRequests, key: RequestKey) ?usize {
        for (self.entries, 0..) |entry_optional, index| {
            const entry = entry_optional orelse continue;
            if (entry.key.eql(key)) return index;
        }
        return null;
    }
};

pub fn purposeForClass(class: RequestClass) session.LeasePurpose {
    return switch (class) {
        .header_metrics => .header_metrics,
        .traffic => .traffic,
        .detail => .detail,
        .yaml => .yaml,
        .logs => .logs,
        .authorization => .authorization,
    };
}

fn expectChildPublishesOnlyThroughQueue(source: []const u8) !void {
    const run_start = std.mem.indexOf(u8, source, "    fn run(") orelse return error.MissingRunBody;
    const run_end = std.mem.indexOfPos(u8, source, run_start, "\n    fn deinit(") orelse
        return error.MissingRunEnd;
    const body = source[run_start..run_end];
    try testing.expect(std.mem.indexOf(u8, body, "control.publishDelivery") != null);
    inline for (.{ "syncProjection", "table.items", "payloadCommit(", ".view." }) |forbidden| {
        try testing.expect(std.mem.indexOf(u8, body, forbidden) == null);
    }
}

pub fn runTask14SourceAuditGate() !void {
    inline for (.{
        @embedFile("HeaderMetricsRequest.zig"),
        @embedFile("TrafficRequest.zig"),
        @embedFile("DetailRequest.zig"),
        @embedFile("LogsRequest.zig"),
        @embedFile("AuthorizationRequest.zig"),
    }) |source| try expectChildPublishesOnlyThroughQueue(source);

    const service_source = @embedFile("../services/K8sService.zig");
    const check_start = std.mem.indexOf(u8, service_source, "    pub fn checkAccess(") orelse
        return error.MissingCheckAccess;
    const check_end = std.mem.indexOfPos(u8, service_source, check_start + 1, "\n    pub fn ") orelse
        return error.MissingCheckAccessEnd;
    const check_body = service_source[check_start..check_end];
    try testing.expect(std.mem.indexOf(u8, check_body, ".POST") != null);
    try testing.expect(std.mem.indexOf(u8, check_body, "enforceWritable") == null);
    try testing.expect(std.mem.indexOf(u8, check_body, "requireWritable") == null);
}

const Harness = struct {
    event: std.Io.Event = .unset,
    inbox: lifecycle.LifecycleInbox,
    cancellations: lifecycle.CancellationIntents = lifecycle.CancellationIntents.init(),
    producer: lifecycle.LifecycleProducer,
    queue: queue_mod.ChangeQueue,
    requests: AncillaryRequests,

    fn init(self: *Harness) void {
        const io = runtime.io();
        self.event = .unset;
        self.inbox = lifecycle.LifecycleInbox.init(io, &self.event);
        self.cancellations = lifecycle.CancellationIntents.init();
        self.producer = lifecycle.LifecycleProducer.init(
            &self.inbox,
            &self.cancellations,
            testing.allocator,
        );
        self.queue = queue_mod.ChangeQueue.init(
            io,
            testing.allocator,
            keys.Limits.default,
            &self.event,
            null,
        );
        self.requests = AncillaryRequests.init(
            testing.allocator,
            self.producer,
            &self.queue,
        );
    }

    fn deinit(self: *Harness) void {
        while (self.inbox.tryPop()) |value| {
            var command = value;
            command.deinit(testing.allocator);
        }
        self.requests.count = 0;
        self.requests.deinit();
        self.queue.deinit();
        self.inbox.deinit(testing.allocator);
    }
};

fn startEmpty(
    requests: *AncillaryRequests,
    class: RequestClass,
    generation: keys.Generation,
) !RequestKey {
    var spec = lifecycle.emptyTaskSpec();
    spec.lease_purpose = purposeForClass(class);
    defer spec.deinit(testing.allocator);
    return requests.startRequest(class, generation, &spec);
}

fn requestEnvelope(
    allocator: std.mem.Allocator,
    key: RequestKey,
    class: RequestClass,
) !keys.Envelope {
    const payload = try allocator.create(u8);
    payload.* = 1;
    const target: keys.EnvelopeTarget = switch (class) {
        .header_metrics => .{ .header_metrics = key },
        .traffic => .{ .traffic = key },
        .detail => .{ .detail = key },
        .yaml => .{ .yaml = key },
        .logs => .{ .logs = key },
        .authorization => .{ .authorization = key },
    };
    return keys.erasePayload(
        u8,
        allocator,
        target,
        payload,
        &keys.test_noop_u8_handler,
        key.generation,
        key.subscription_id,
        0,
        1,
        null,
    );
}

pub fn runTask14AncillaryIdentityGate() !void {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    const classes = [_]RequestClass{
        .header_metrics,
        .traffic,
        .detail,
        .yaml,
        .logs,
        .authorization,
    };
    var keys_by_class: [classes.len]RequestKey = undefined;
    for (classes, 0..) |class, index| {
        const key = try startEmpty(&harness.requests, class, 9);
        keys_by_class[index] = key;
        try testing.expectEqual(@as(keys.SubscriptionId, @intCast(index + 1)), key.subscription_id);
        var exact = try requestEnvelope(testing.allocator, key, class);
        defer exact.deinit(testing.allocator);
        try testing.expect(harness.requests.acceptsEnvelope(exact));
        exact.subscription_id += 1;
        try testing.expect(!harness.requests.acceptsEnvelope(exact));
    }

    const first_detail = keys_by_class[2];
    try testing.expectEqual(CancelResult.requested, harness.requests.cancelRequest(first_detail));
    const replacement = try startEmpty(&harness.requests, .detail, 9);
    try testing.expect(replacement.subscription_id > first_detail.subscription_id);
    try testing.expect(!harness.requests.contains(first_detail, .detail));
    try testing.expect(harness.requests.contains(replacement, .detail));
    try testing.expectEqual(@as(usize, classes.len), harness.requests.cancelAll());
    try testing.expectEqual(@as(usize, classes.len + 1), harness.requests.trackedCount());
}

pub fn runTask14ProductionShutdownGate() !void {
    const klient = @import("klient");
    const slot_mod = @import("ActiveSessionSlot.zig");
    const supervisor_mod = @import("LifecycleSupervisor.zig");
    const data_plane_mod = @import("DataPlane.zig");
    const fake_mod = @import("FakeTransport.zig");
    const header_mod = @import("HeaderMetricsRequest.zig");
    const traffic_mod = @import("TrafficRequest.zig");
    const detail_mod = @import("DetailRequest.zig");
    const logs_mod = @import("LogsRequest.zig");
    const authorization_mod = @import("AuthorizationRequest.zig");
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const io = runtime.io();

    var event: std.Io.Event = .unset;
    var inbox = lifecycle.LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = lifecycle.CancellationIntents.init();
    var slot = slot_mod.ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = queue_mod.ChangeQueue.init(
        io,
        testing.allocator,
        keys.Limits.default,
        &event,
        null,
    );
    defer queue.deinit();

    const client = try testing.allocator.create(klient.K8sClient);
    client.* = try klient.K8sClient.init(testing.allocator, io, .{
        .server = "http://127.0.0.1",
        .namespace = "default",
    });
    const active_session = try session.ActiveContextSession.adopt(
        testing.allocator,
        io,
        1,
        .{
            .context_name = "task-14",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
        .{
            .shared_event = &event,
            .client = client,
            .cluster_name = "local",
            .user_name = "test",
            .readiness_verified = true,
        },
    );
    _ = try slot.commit(active_session);
    var supervisor = try supervisor_mod.LifecycleSupervisor.init(
        testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        session.SessionFactory.production(),
        active_session,
    );
    var producer = lifecycle.LifecycleProducer.init(&inbox, &cancellations, testing.allocator);
    var plane = data_plane_mod.DataPlane.init(testing.allocator, producer, &queue);
    var requests = AncillaryRequests.init(testing.allocator, producer, &queue);
    defer requests.deinit();

    const header_scripts = [_]fake_mod.ResponseScript{
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
    };
    var header_fake = fake_mod.FakeTransport.init(testing.allocator, &header_scripts);
    defer header_fake.deinit();
    const traffic_response =
        \\{"status":"success","data":{"resultType":"vector","result":[]}}
    ;
    const traffic_scripts = [_]fake_mod.ResponseScript{.{ .body = traffic_response }} ** 8;
    var traffic_fake = fake_mod.FakeTransport.init(testing.allocator, &traffic_scripts);
    defer traffic_fake.deinit();
    const detail_scripts = [_]fake_mod.ResponseScript{
        .{ .body = "{\"kind\":\"Pod\",\"metadata\":{\"name\":\"pod-a\"}}" },
        .{ .body = "{\"kind\":\"Pod\",\"metadata\":{\"name\":\"pod-a\"}}" },
    };
    var detail_fake = fake_mod.FakeTransport.init(testing.allocator, &detail_scripts);
    defer detail_fake.deinit();
    const logs_scripts = [_]fake_mod.ResponseScript{.{ .body = "line one" }};
    var logs_fake = fake_mod.FakeTransport.init(testing.allocator, &logs_scripts);
    defer logs_fake.deinit();
    var service = try K8sService.init(testing.allocator);
    defer service.deinit();
    const Auth = struct {
        fn connected(_: *anyopaque) bool {
            return true;
        }
        fn check(_: *anyopaque, _: []const u8, _: []const u8, _: []const u8, _: []const u8) !K8sService.AccessCheckResult {
            return .{ .allowed = true, .conditional = false, .condition_count = 0 };
        }
        fn conditional(_: *anyopaque) !bool {
            return false;
        }
        fn policies(_: *anyopaque) ![]K8sService.PolicyInfo {
            return error.Unused;
        }
        fn cedar(_: *anyopaque) !bool {
            return false;
        }
        fn conditions(_: *anyopaque, _: []const u8, _: []const u8, _: []const u8) ![]K8sService.ConditionInfo {
            return error.Unused;
        }
    };
    var auth_context: u8 = 0;
    const auth_backend = authorization_mod.Backend{
        .context = &auth_context,
        .isConnectedFn = Auth.connected,
        .checkAccessFn = Auth.check,
        .detectConditionalFn = Auth.conditional,
        .listRbacFn = Auth.policies,
        .detectCedarFn = Auth.cedar,
        .listCedarFn = Auth.policies,
        .conditionsFn = Auth.conditions,
    };

    var specs = [_]lifecycle.OwnedTaskSpec{
        try header_mod.ownedTaskSpec(testing.allocator, .{ .transport_override = header_fake.transport() }),
        try traffic_mod.ownedTaskSpec(testing.allocator, .{
            .workload = "api",
            .namespace = "default",
            .transport_override = traffic_fake.transport(),
        }),
        try detail_mod.ownedTaskSpec(testing.allocator, .{
            .serial = 1,
            .kind = .describe,
            .resource_type = .pods,
            .name = "pod-a",
            .namespace = "default",
            .transport_override = detail_fake.transport(),
        }),
        try detail_mod.ownedTaskSpec(testing.allocator, .{
            .serial = 1,
            .kind = .yaml,
            .resource_type = .pods,
            .name = "pod-a",
            .namespace = "default",
            .transport_override = detail_fake.transport(),
        }),
        try logs_mod.ownedTaskSpec(testing.allocator, .{
            .serial = 1,
            .pod_name = "pod-a",
            .namespace = "default",
            .previous = false,
            .transport_override = logs_fake.transport(),
        }),
        try authorization_mod.ownedTaskSpec(testing.allocator, .{
            .serial = 1,
            .tab = .access_review,
            .service = &service,
            .namespace = "default",
            .backend_override = auth_backend,
        }),
    };
    defer for (&specs) |*spec| spec.deinit(testing.allocator);
    const classes = [_]RequestClass{
        .header_metrics,
        .traffic,
        .detail,
        .yaml,
        .logs,
        .authorization,
    };
    for (classes, &specs) |class, *spec| _ = try requests.startRequest(class, 1, spec);

    var shutdown_enqueued = false;
    var root_awaited = false;
    try supervisor.startRoot();
    defer {
        if (!shutdown_enqueued) producer.enqueueShutdown() catch {};
        if (!root_awaited) {
            // Children block pushing into a full queue, so keep draining until the
            // root terminates; awaiting first would deadlock shutdownToCompletion.
            var drains: usize = 0;
            while (!inbox.isRootTerminated() and drains < 20_000) : (drains += 1) {
                while (queue.pop()) |value| {
                    var envelope = value;
                    envelope.deinit(testing.allocator);
                }
                if (inbox.isRootTerminated()) break;
                io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake) catch {};
            }
            _ = supervisor.awaitRoot();
        }
        while (queue.pop()) |value| {
            var envelope = value;
            envelope.deinit(testing.allocator);
        }
    }

    const Route = struct {
        plane: *data_plane_mod.DataPlane,
        requests: *AncillaryRequests,
        fn target(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return if (target_value == .lifecycle) @ptrCast(self.plane) else null;
        }
        fn observe(raw: *anyopaque, payload: *anyopaque, _: ?keys.ResourceIdentity) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const completion: *LifecycleCompletion = @ptrCast(@alignCast(payload));
            _ = self.requests.handleCompletion(completion.*);
        }
    };
    var route = Route{ .plane = &plane, .requests = &requests };
    var router = keys.UiRouter{
        .context = &route,
        .targetFn = Route.target,
        .lifecycleFn = Route.observe,
    };
    var attempts: usize = 0;
    while (requests.trackedCount() != 0 and attempts < 20_000) : (attempts += 1) {
        while (queue.pop()) |value| {
            var envelope = value;
            if (envelope.target == .lifecycle) {
                try envelope.apply(&router, testing.allocator);
            } else {
                envelope.deinit(testing.allocator);
            }
        }
        if (requests.trackedCount() != 0)
            try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    try producer.enqueueShutdown();
    shutdown_enqueued = true;
    _ = supervisor.awaitRoot();
    root_awaited = true;
    while (queue.pop()) |value| {
        var envelope = value;
        if (envelope.target == .lifecycle)
            try envelope.apply(&router, testing.allocator)
        else
            envelope.deinit(testing.allocator);
    }
    try testing.expectEqual(@as(usize, 0), requests.trackedCount());
    try testing.expectEqual(@as(usize, 0), supervisor.liveChildren());
    try testing.expectEqual(supervisor.metrics.launched, supervisor.metrics.reaped);
    try testing.expectEqual(@as(usize, 0), active_session.leaseCount());
}

test "all ancillary classes share one exact monotonic identity allocator" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    const traffic = try startEmpty(&harness.requests, .traffic, 7);
    const authorization = try startEmpty(&harness.requests, .authorization, 7);
    try testing.expectEqual(@as(keys.SubscriptionId, 1), traffic.subscription_id);
    try testing.expectEqual(@as(keys.SubscriptionId, 2), authorization.subscription_id);
    try testing.expect(harness.requests.contains(traffic, .traffic));
    try testing.expect(!harness.requests.contains(traffic, .authorization));

    var first = harness.inbox.tryPop() orelse return error.MissingStart;
    defer first.deinit(testing.allocator);
    try testing.expectEqual(traffic, first.start_request.key);
    try testing.expectEqual(traffic.generation, first.start_request.expected_generation);
}

test "purpose mismatch is rejected before enqueue and destroys spec once" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    var destroyed: usize = 0;
    const Owned = struct {
        count: *usize,

        fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.count.* += 1;
            allocator.destroy(self);
        }
    };
    const owned = try testing.allocator.create(Owned);
    owned.* = .{ .count = &destroyed };
    var spec = OwnedTaskSpec{
        .ptr = owned,
        .alignment = .of(Owned),
        .lease_purpose = .command,
        .deinitFn = Owned.deinit,
    };
    defer spec.deinit(testing.allocator);
    try testing.expectError(
        error.InvalidLeasePurpose,
        harness.requests.startRequest(.header_metrics, 1, &spec),
    );
    try testing.expectEqual(@as(usize, 1), destroyed);
    try testing.expect(harness.inbox.tryPop() == null);
}

test "failed enqueue consumes its request id and never publishes an entry" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    var i: usize = 0;
    while (i < lifecycle.LifecycleInbox.normal_capacity) : (i += 1) {
        try harness.inbox.tryPush(.{ .start_subscription = .{
            .child_key = .{ .slot = 0, .generation = 1 },
            .expected_generation = 1,
            .key = .{ .generation = 1, .subscription_id = 99 },
            .spec = lifecycle.emptyTaskSpec(),
        } });
    }
    var failed = lifecycle.emptyTaskSpec();
    failed.lease_purpose = .traffic;
    try testing.expectError(
        error.Full,
        harness.requests.startRequest(.traffic, 1, &failed),
    );
    try testing.expectEqual(@as(keys.SubscriptionId, 2), harness.requests.next_subscription_id);
    try testing.expectEqual(@as(usize, 0), harness.requests.trackedCount());
}

test "request id exhaustion is permanent and does not bind or enqueue" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();
    harness.requests.next_subscription_id = std.math.maxInt(keys.SubscriptionId);

    var first = lifecycle.emptyTaskSpec();
    first.lease_purpose = .logs;
    try testing.expectError(
        error.RequestIdExhausted,
        harness.requests.startRequest(.logs, 1, &first),
    );
    try testing.expectEqual(@as(keys.SubscriptionId, 0), harness.requests.next_subscription_id);
    var second = lifecycle.emptyTaskSpec();
    second.lease_purpose = .logs;
    try testing.expectError(
        error.RequestIdExhausted,
        harness.requests.startRequest(.logs, 1, &second),
    );
}

test "envelope acceptance requires class key and duplicate top-level identity" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();
    const key = try startEmpty(&harness.requests, .header_metrics, 4);

    var exact = try requestEnvelope(testing.allocator, key, .header_metrics);
    defer exact.deinit(testing.allocator);
    try testing.expect(harness.requests.acceptsEnvelope(exact));

    var wrong_class = try requestEnvelope(testing.allocator, key, .traffic);
    defer wrong_class.deinit(testing.allocator);
    try testing.expect(!harness.requests.acceptsEnvelope(wrong_class));

    var mismatch = try requestEnvelope(testing.allocator, key, .header_metrics);
    defer mismatch.deinit(testing.allocator);
    mismatch.subscription_id += 1;
    try testing.expect(!harness.requests.acceptsEnvelope(mismatch));
}

test "cancel and exact completion preserve replacement identity" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();
    const old = try startEmpty(&harness.requests, .detail, 3);
    try testing.expectEqual(CancelResult.requested, harness.requests.cancelRequest(old));
    try testing.expectEqual(CancelResult.already_inactive, harness.requests.cancelRequest(old));
    const replacement = try startEmpty(&harness.requests, .detail, 3);
    try testing.expect(replacement.subscription_id > old.subscription_id);
    try testing.expect(harness.requests.handleCompletion(.{
        .request_finished = .{ .key = old },
    }));
    try testing.expect(harness.requests.contains(replacement, .detail));
    try testing.expect(!harness.requests.handleCompletion(.{
        .request_finished = .{ .key = old },
    }));
}

test "start rejection requires both exact request and child keys" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();
    const key = try startEmpty(&harness.requests, .authorization, 8);
    var command = harness.inbox.tryPop() orelse return error.MissingStart;
    defer command.deinit(testing.allocator);
    const child = command.start_request.child_key;

    try testing.expect(!harness.requests.handleCompletion(.{
        .start_rejected = .{
            .child_key = .{ .slot = child.slot, .generation = child.generation + 1 },
            .request_key = key,
            .code = .capacity,
        },
    }));
    try testing.expect(!harness.requests.handleCompletion(.{
        .start_rejected = .{
            .child_key = child,
            .request_key = .{
                .generation = key.generation,
                .subscription_id = key.subscription_id + 1,
            },
            .code = .stale_generation,
        },
    }));
    try testing.expect(harness.requests.contains(key, .authorization));
    try testing.expect(harness.requests.handleCompletion(.{
        .start_rejected = .{
            .child_key = child,
            .request_key = key,
            .code = .shutting_down,
        },
    }));
    try testing.expectEqual(@as(usize, 0), harness.requests.trackedCount());
}

test "generation invalidation keeps the process-long counter" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();
    const old = try startEmpty(&harness.requests, .traffic, 1);
    try testing.expectEqual(@as(usize, 1), harness.requests.invalidateGeneration(1));
    try testing.expect(!harness.requests.contains(old, .traffic));
    const current = try startEmpty(&harness.requests, .traffic, 2);
    try testing.expect(current.subscription_id > old.subscription_id);
    try testing.expect(harness.requests.contains(current, .traffic));
    try testing.expectEqual(@as(usize, 0), harness.requests.invalidateGeneration(3));
}

test "cancel before entry during IO and delivery backpressure releases one tombstone" {
    const klient = @import("klient");
    const slot_mod = @import("ActiveSessionSlot.zig");
    const supervisor_mod = @import("LifecycleSupervisor.zig");
    const data_plane_mod = @import("DataPlane.zig");

    const Mode = enum { before_entry, io, delivery_backpressure };
    const Probe = struct {
        mode: Mode,
        entered: *std.atomic.Value(bool),
        destroyed: *usize,
        generation: keys.Generation = 0,
        subscription_id: keys.SubscriptionId = 0,

        fn bind(raw: ?*anyopaque, generation: keys.Generation, subscription_id: keys.SubscriptionId) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.generation = generation;
            self.subscription_id = subscription_id;
        }

        fn run(raw: ?*anyopaque, control: *lifecycle.ChildControl, io: std.Io) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.entered.store(true, .release);
            switch (self.mode) {
                .before_entry => return error.UnexpectedEntry,
                .io => {
                    while (!control.cancel_requested.load(.acquire)) {
                        io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake) catch return;
                    }
                },
                .delivery_backpressure => {
                    const payload = try control.allocator.create(u8);
                    payload.* = 1;
                    var envelope = keys.erasePayload(
                        u8,
                        control.allocator,
                        .{ .traffic = .{
                            .generation = self.generation,
                            .subscription_id = self.subscription_id,
                        } },
                        payload,
                        &keys.test_noop_u8_handler,
                        self.generation,
                        self.subscription_id,
                        0,
                        1,
                        null,
                    ) catch |err| {
                        control.allocator.destroy(payload);
                        return err;
                    };
                    const outcome = try control.publishDelivery(envelope);
                    if (outcome == .abandoned) return;
                    envelope = undefined;
                },
            }
        }

        fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(raw orelse return));
            self.destroyed.* += 1;
            allocator.destroy(self);
        }
    };
    const Route = struct {
        plane: *data_plane_mod.DataPlane,
        requests: *AncillaryRequests,

        fn target(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return switch (target_value) {
                .lifecycle => @ptrCast(self.plane),
                else => null,
            };
        }

        fn observe(raw: *anyopaque, payload: *anyopaque, _: ?keys.ResourceIdentity) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const completion: *LifecycleCompletion = @ptrCast(@alignCast(payload));
            _ = self.requests.handleCompletion(completion.*);
        }
    };

    inline for (.{ Mode.before_entry, Mode.io, Mode.delivery_backpressure }) |mode| {
        const io = runtime.io();
        var event: std.Io.Event = .unset;
        var inbox = lifecycle.LifecycleInbox.init(io, &event);
        defer inbox.deinit(testing.allocator);
        var cancellations = lifecycle.CancellationIntents.init();
        var slot = slot_mod.ActiveSessionSlot.init(io, &event);
        defer slot.deinit();
        var queue = queue_mod.ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
        defer queue.deinit();

        const client = try testing.allocator.create(klient.K8sClient);
        client.* = try klient.K8sClient.init(testing.allocator, io, .{
            .server = "http://127.0.0.1",
            .namespace = "default",
        });
        const active_session = try session.ActiveContextSession.adopt(
            testing.allocator,
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
            testing.allocator,
            io,
            &event,
            &inbox,
            &cancellations,
            &slot,
            &queue,
            session.SessionFactory.production(),
            active_session,
        );
        var producer = lifecycle.LifecycleProducer.init(&inbox, &cancellations, testing.allocator);
        var plane = data_plane_mod.DataPlane.init(testing.allocator, producer, &queue);
        var requests = AncillaryRequests.init(testing.allocator, producer, &queue);
        defer requests.deinit();
        var entered: std.atomic.Value(bool) = .init(false);
        var destroyed: usize = 0;
        const probe = try testing.allocator.create(Probe);
        probe.* = .{ .mode = mode, .entered = &entered, .destroyed = &destroyed };
        var spec = OwnedTaskSpec{
            .ptr = probe,
            .alignment = .of(Probe),
            .lease_purpose = .traffic,
            .bindFn = Probe.bind,
            .runFn = Probe.run,
            .deinitFn = Probe.deinit,
        };
        const key = try requests.startRequest(.traffic, 1, &spec);
        const child_key = requests.entries[requests.findKey(key).?].?.child_key;

        if (mode == .delivery_backpressure) {
            for (0..60) |index| {
                try queue.tryPush(try requestEnvelope(testing.allocator, .{
                    .generation = 99,
                    .subscription_id = @intCast(index + 1),
                }, .header_metrics));
            }
        }
        if (mode == .before_entry) {
            try testing.expectEqual(CancelResult.requested, requests.cancelRequest(key));
        }
        try supervisor.startRoot();
        if (mode != .before_entry) {
            for (0..10_000) |_| {
                if (entered.load(.acquire)) break;
                try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
            }
            try testing.expect(entered.load(.acquire));
            try testing.expectEqual(CancelResult.requested, requests.cancelRequest(key));
        }

        var route = Route{ .plane = &plane, .requests = &requests };
        var router = keys.UiRouter{
            .context = &route,
            .targetFn = Route.target,
            .lifecycleFn = Route.observe,
        };
        for (0..20_000) |_| {
            while (queue.pop()) |value| {
                var envelope = value;
                if (envelope.target == .lifecycle) {
                    try envelope.apply(&router, testing.allocator);
                } else {
                    envelope.deinit(testing.allocator);
                }
            }
            if (requests.trackedCount() == 0) break;
            try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
        }
        try testing.expectEqual(@as(usize, 0), requests.trackedCount());
        try testing.expectEqual(@as(usize, 1), destroyed);
        try testing.expectEqual(@as(usize, 0), active_session.leaseCount());
        try testing.expect(!requests.handleCompletion(.{ .request_finished = .{ .key = key } }));

        // Exactly one tombstone, asserted on the cell rather than inferred from
        // supervisor cleanup. The completion envelope can reach the UI loop before
        // the supervisor reaps the node, so wait for the release it owes.
        for (0..10_000) |_| {
            const observed: lifecycle.CancellationWord =
                @bitCast(cancellations.cells[child_key.slot].load(.acquire));
            if (observed.state == .free) break;
            try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
        }
        const cell: lifecycle.CancellationWord =
            @bitCast(cancellations.cells[child_key.slot].load(.acquire));
        try testing.expectEqual(lifecycle.CancellationCellState.free, cell.state);
        try testing.expectEqual(child_key.generation, cell.generation);
        try testing.expect(!cell.cancel_requested);
        try testing.expectEqual(
            lifecycle.CancellationIntents.ClaimResult.none,
            cancellations.claimRequested(child_key),
        );
        // A redundant release is a no-op, so the one release above is the only one
        // the slot saw: the generation is still the child's and the state is free.
        try testing.expect(cancellations.free(child_key));
        const settled: lifecycle.CancellationWord =
            @bitCast(cancellations.cells[child_key.slot].load(.acquire));
        try testing.expectEqual(lifecycle.CancellationCellState.free, settled.state);
        try testing.expectEqual(child_key.generation, settled.generation);

        try producer.enqueueShutdown();
        _ = supervisor.awaitRoot();
        while (queue.pop()) |value| {
            var envelope = value;
            envelope.deinit(testing.allocator);
        }
    }
}
