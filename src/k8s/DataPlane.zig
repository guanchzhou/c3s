const std = @import("std");
const testing = std.testing;

const inbox_mod = @import("LifecycleInbox.zig");
const queue_mod = @import("ChangeQueue.zig");
const keys = @import("ResourceKey.zig");
const runtime = @import("../core/runtime.zig");

pub const LifecycleProducer = inbox_mod.LifecycleProducer;
pub const LifecycleCompletion = inbox_mod.LifecycleCompletion;
pub const OwnedTaskSpec = inbox_mod.OwnedTaskSpec;
pub const ChildKey = inbox_mod.ChildKey;
pub const SubscriptionKey = inbox_mod.SubscriptionKey;
pub const Generation = inbox_mod.Generation;
pub const SubscriptionId = inbox_mod.SubscriptionId;
pub const Envelope = keys.Envelope;

pub const CancelResult = enum {
    requested,
    already_inactive,
    unknown,
};

const SubscriptionState = enum {
    active,
    canceling,
};

const Subscription = struct {
    key: SubscriptionKey,
    child_key: ChildKey,
    state: SubscriptionState = .active,
};

/// UI-thread facade for resource subscription lifecycle.
///
/// The facade owns only bounded identities. Task specs transfer to the
/// LifecycleSupervisor through LifecycleProducer; Future handles never cross
/// this boundary.
pub const DataPlane = struct {
    pub const capacity = inbox_mod.CancellationIntents.capacity;

    allocator: std.mem.Allocator,
    producer: LifecycleProducer,
    change_queue: *queue_mod.ChangeQueue,
    subscriptions: [capacity]?Subscription = @splat(null),
    next_subscription_id: SubscriptionId = 1,
    count: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        producer: LifecycleProducer,
        change_queue: *queue_mod.ChangeQueue,
    ) DataPlane {
        return .{
            .allocator = allocator,
            .producer = producer,
            .change_queue = change_queue,
        };
    }

    /// Takes ownership of `spec` on every return path.
    pub fn startSubscription(
        self: *DataPlane,
        expected_generation: Generation,
        spec_source: *OwnedTaskSpec,
    ) error{
        Capacity,
        SubscriptionIdExhausted,
        Full,
        Closed,
        TaskSpecTooLarge,
    }!SubscriptionKey {
        var spec = spec_source.take();
        errdefer spec.deinit(self.allocator);

        const index = self.freeIndex() orelse return error.Capacity;
        if (self.next_subscription_id == 0) return error.SubscriptionIdExhausted;

        const child_key = self.producer.reserveChild() catch return error.Capacity;
        const key = SubscriptionKey{
            .generation = expected_generation,
            .subscription_id = self.next_subscription_id,
        };
        spec.bindFn(spec.ptr, key.generation, key.subscription_id);
        var command = inbox_mod.LifecycleCommand{ .start_subscription = .{
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

        self.subscriptions[index] = .{
            .key = key,
            .child_key = child_key,
        };
        self.count += 1;
        self.next_subscription_id = std.math.add(
            SubscriptionId,
            self.next_subscription_id,
            1,
        ) catch 0;
        return key;
    }

    /// Cancellation is idempotent and does not consume LifecycleInbox space.
    pub fn cancelSubscription(
        self: *DataPlane,
        key: SubscriptionKey,
    ) CancelResult {
        const index = self.findBySubscription(key) orelse return .unknown;
        const subscription = if (self.subscriptions[index]) |*item| item else return .unknown;
        if (subscription.state == .canceling) return .already_inactive;

        subscription.state = .canceling;
        _ = self.producer.tryRequestCancel(subscription.child_key);
        _ = self.change_queue.purgeSubscription(key);
        return .requested;
    }

    /// Invalidates only subscriptions from `generation`.
    pub fn invalidateGeneration(
        self: *DataPlane,
        generation: Generation,
    ) usize {
        var canceled: usize = 0;
        for (&self.subscriptions) |*entry| {
            const subscription = if (entry.*) |*item| item else continue;
            if (subscription.key.generation != generation or
                subscription.state == .canceling)
            {
                continue;
            }
            subscription.state = .canceling;
            _ = self.producer.tryRequestCancel(subscription.child_key);
            _ = self.change_queue.purgeSubscription(subscription.key);
            canceled += 1;
        }
        return canceled;
    }

    /// Removes terminal identities after the UI receives their lifecycle
    /// completion from ChangeQueue.
    pub fn handleCompletion(
        self: *DataPlane,
        completion: LifecycleCompletion,
    ) bool {
        const index = self.indexForCompletion(completion) orelse return false;
        const key = self.subscriptions[index].?.key;
        self.subscriptions[index] = null;
        self.count -= 1;
        _ = self.change_queue.purgeSubscription(key);
        return true;
    }

    pub fn keyForCompletion(
        self: *const DataPlane,
        completion: LifecycleCompletion,
    ) ?SubscriptionKey {
        const index = self.indexForCompletion(completion) orelse return null;
        return self.subscriptions[index].?.key;
    }

    /// Resource envelopes are accepted only while their exact generation and
    /// subscription identity is active. This closes the race where a delivery
    /// is queued immediately after an invalidation purge.
    pub fn acceptsEnvelope(self: *const DataPlane, envelope: Envelope) bool {
        const resource = switch (envelope.target) {
            .resource => |resource| resource,
            else => return true,
        };
        const index = self.findBySubscription(.{
            .generation = resource.generation,
            .subscription_id = resource.subscription_id,
        }) orelse return false;
        return self.subscriptions[index].?.state == .active;
    }

    pub fn resourceTarget(
        self: *const DataPlane,
        target: keys.EnvelopeTarget,
        active: ?SubscriptionKey,
        projection: *anyopaque,
    ) ?*anyopaque {
        const identity = switch (target) {
            .resource => |value| value,
            else => return null,
        };
        const active_key = active orelse return null;
        if (active_key.generation != identity.generation or
            active_key.subscription_id != identity.subscription_id)
        {
            return null;
        }
        const index = self.findBySubscription(active_key) orelse return null;
        if (self.subscriptions[index].?.state != .active) return null;
        return projection;
    }

    pub fn activeCount(self: *const DataPlane) usize {
        var active: usize = 0;
        for (self.subscriptions) |entry| {
            const subscription = entry orelse continue;
            if (subscription.state == .active) active += 1;
        }
        return active;
    }

    pub fn trackedCount(self: *const DataPlane) usize {
        return self.count;
    }

    fn freeIndex(self: *const DataPlane) ?usize {
        for (self.subscriptions, 0..) |entry, index| {
            if (entry == null) return index;
        }
        return null;
    }

    fn findBySubscription(
        self: *const DataPlane,
        key: SubscriptionKey,
    ) ?usize {
        for (self.subscriptions, 0..) |entry, index| {
            const subscription = entry orelse continue;
            if (subscription.key.generation == key.generation and
                subscription.key.subscription_id == key.subscription_id)
            {
                return index;
            }
        }
        return null;
    }

    fn findByChild(self: *const DataPlane, key: ChildKey) ?usize {
        for (self.subscriptions, 0..) |entry, index| {
            const subscription = entry orelse continue;
            if (subscription.child_key.eql(key)) return index;
        }
        return null;
    }

    fn indexForCompletion(
        self: *const DataPlane,
        completion: LifecycleCompletion,
    ) ?usize {
        return switch (completion) {
            .subscription_stopped => |stopped| self.findBySubscription(stopped.key),
            .start_rejected => |rejected| self.findByChild(rejected.child_key),
            else => null,
        };
    }
};

const Harness = struct {
    event: std.Io.Event = .unset,
    inbox: inbox_mod.LifecycleInbox,
    cancellations: inbox_mod.CancellationIntents = inbox_mod.CancellationIntents.init(),
    producer: LifecycleProducer,
    queue: queue_mod.ChangeQueue,
    plane: DataPlane,

    fn init(self: *Harness) void {
        const io = runtime.io();
        self.event = .unset;
        self.inbox = inbox_mod.LifecycleInbox.init(io, &self.event);
        self.cancellations = inbox_mod.CancellationIntents.init();
        self.producer = LifecycleProducer.init(
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
        self.plane = DataPlane.init(
            testing.allocator,
            self.producer,
            &self.queue,
        );
    }

    fn deinit(self: *Harness) void {
        self.inbox.deinit(testing.allocator);
        self.queue.deinit();
    }
};

fn testEnvelope(
    allocator: std.mem.Allocator,
    key: SubscriptionKey,
) !Envelope {
    const payload = try allocator.create(u8);
    payload.* = 1;
    return keys.erasePayload(
        u8,
        allocator,
        .{ .resource = .{
            .generation = key.generation,
            .subscription_id = key.subscription_id,
        } },
        payload,
        &keys.test_noop_u8_handler,
        key.generation,
        key.subscription_id,
        1,
        1,
        null,
    );
}

fn startEmpty(plane: *DataPlane, generation: Generation) !SubscriptionKey {
    var spec = inbox_mod.emptyTaskSpec();
    defer spec.deinit(testing.allocator);
    return plane.startSubscription(generation, &spec);
}

test "start transfers task ownership and records bounded identity" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    const key = try startEmpty(&harness.plane, 7);
    try testing.expectEqual(@as(Generation, 7), key.generation);
    try testing.expectEqual(@as(SubscriptionId, 1), key.subscription_id);
    try testing.expectEqual(@as(usize, 1), harness.plane.activeCount());

    var command = harness.inbox.tryPop() orelse return error.MissingStart;
    defer command.deinit(testing.allocator);
    const start = command.start_subscription;
    try testing.expectEqual(@as(Generation, 7), start.expected_generation);
    try testing.expectEqual(key, start.key);
}

test "stale generation rejection completion releases identity" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    _ = try startEmpty(&harness.plane, 9);
    var command = harness.inbox.tryPop() orelse return error.MissingStart;
    const child_key = command.start_subscription.child_key;
    command.deinit(testing.allocator);

    try testing.expect(harness.plane.handleCompletion(.{
        .start_rejected = .{
            .child_key = child_key,
            .code = .stale_generation,
        },
    }));
    try testing.expectEqual(@as(usize, 0), harness.plane.trackedCount());
}

test "duplicate unknown and saturated-inbox cancellation are idempotent" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    const key = try startEmpty(&harness.plane, 1);
    while (harness.inbox.tryPop()) |value| {
        var command = value;
        command.deinit(testing.allocator);
    }
    var n: usize = 0;
    while (n < inbox_mod.LifecycleInbox.normal_capacity) : (n += 1) {
        try harness.inbox.tryPush(.{ .start_subscription = .{
            .child_key = .{ .slot = 0, .generation = 1 },
            .expected_generation = 1,
            .key = .{ .generation = 1, .subscription_id = 99 },
            .spec = inbox_mod.emptyTaskSpec(),
        } });
    }

    try testing.expectEqual(CancelResult.requested, harness.plane.cancelSubscription(key));
    try testing.expectEqual(CancelResult.already_inactive, harness.plane.cancelSubscription(key));
    try testing.expectEqual(CancelResult.unknown, harness.plane.cancelSubscription(.{
        .generation = 1,
        .subscription_id = 999,
    }));
}

test "canceling one subscription preserves another in the same generation" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    const first = try startEmpty(&harness.plane, 4);
    const second = try startEmpty(&harness.plane, 4);
    const first_envelope = try testEnvelope(testing.allocator, first);
    const second_envelope = try testEnvelope(testing.allocator, second);
    try harness.queue.tryPush(first_envelope);
    try harness.queue.tryPush(second_envelope);

    try testing.expectEqual(CancelResult.requested, harness.plane.cancelSubscription(first));
    try testing.expectEqual(@as(usize, 1), harness.plane.activeCount());
    var remaining = harness.queue.pop() orelse return error.MissingEnvelope;
    defer remaining.deinit(testing.allocator);
    try testing.expect(harness.plane.acceptsEnvelope(remaining));
    try testing.expectEqual(second.subscription_id, remaining.subscription_id);
}

test "invalidateGeneration marks stored identities inactive" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    const stale = try startEmpty(&harness.plane, 1);
    const keep = try startEmpty(&harness.plane, 2);
    try harness.queue.tryPush(try testEnvelope(testing.allocator, stale));
    try harness.queue.tryPush(try testEnvelope(testing.allocator, keep));

    try testing.expectEqual(@as(usize, 1), harness.plane.invalidateGeneration(1));
    try testing.expectEqual(@as(usize, 1), harness.plane.activeCount());
    try testing.expectEqual(@as(usize, 2), harness.plane.trackedCount());
    try testing.expectEqual(CancelResult.already_inactive, harness.plane.cancelSubscription(stale));

    var remaining = harness.queue.pop() orelse return error.MissingPeer;
    defer remaining.deinit(testing.allocator);
    try testing.expect(harness.plane.acceptsEnvelope(remaining));
    try testing.expectEqual(keep, SubscriptionKey{
        .generation = remaining.generation,
        .subscription_id = remaining.subscription_id,
    });
    try testing.expect(!harness.queue.hasPending());

    var late = try testEnvelope(testing.allocator, stale);
    try testing.expect(!harness.plane.acceptsEnvelope(late));
    late.deinit(testing.allocator);
    var live = try testEnvelope(testing.allocator, keep);
    try testing.expect(harness.plane.acceptsEnvelope(live));
    live.deinit(testing.allocator);
}

test "late envelope after purge is rejected by exact identity" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    const key = try startEmpty(&harness.plane, 2);
    try harness.queue.tryPush(try testEnvelope(testing.allocator, key));
    _ = harness.plane.cancelSubscription(key);
    try testing.expect(!harness.queue.hasPending());

    var late = try testEnvelope(testing.allocator, key);
    try testing.expect(!harness.plane.acceptsEnvelope(late));
    late.deinit(testing.allocator);
}

test "task specs unwind on capacity and inbox failure" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    var destroyed: usize = 0;
    const Owned = struct {
        counter: *usize,

        fn deinit(
            raw: ?*anyopaque,
            _: std.mem.Alignment,
            allocator: std.mem.Allocator,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.counter.* += 1;
            allocator.destroy(self);
        }
    };
    const owned = try testing.allocator.create(Owned);
    owned.* = .{ .counter = &destroyed };
    var n: usize = 0;
    while (n < inbox_mod.LifecycleInbox.normal_capacity) : (n += 1) {
        try harness.inbox.tryPush(.{ .start_subscription = .{
            .child_key = .{ .slot = 0, .generation = 1 },
            .expected_generation = 1,
            .key = .{ .generation = 1, .subscription_id = 99 },
            .spec = inbox_mod.emptyTaskSpec(),
        } });
    }
    var failed_spec = OwnedTaskSpec{
        .ptr = owned,
        .alignment = .of(Owned),
        .owned_bytes = @sizeOf(Owned),
        .deinitFn = Owned.deinit,
    };
    defer failed_spec.deinit(testing.allocator);
    try testing.expectError(error.Full, harness.plane.startSubscription(1, &failed_spec));
    try testing.expect(failed_spec.ptr == null);
    try testing.expectEqual(@as(usize, 1), destroyed);
    try testing.expectEqual(@as(usize, 0), harness.plane.trackedCount());
}

test "SubscriptionIdExhausted deinitializes the owned task spec" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    var destroyed: usize = 0;
    const Owned = struct {
        counter: *usize,

        fn deinit(
            raw: ?*anyopaque,
            _: std.mem.Alignment,
            allocator: std.mem.Allocator,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(raw.?));
            self.counter.* += 1;
            allocator.destroy(self);
        }
    };
    const owned = try testing.allocator.create(Owned);
    owned.* = .{ .counter = &destroyed };
    harness.plane.next_subscription_id = 0;
    var exhausted_spec = OwnedTaskSpec{
        .ptr = owned,
        .alignment = .of(Owned),
        .owned_bytes = @sizeOf(Owned),
        .deinitFn = Owned.deinit,
    };
    defer exhausted_spec.deinit(testing.allocator);
    try testing.expectError(
        error.SubscriptionIdExhausted,
        harness.plane.startSubscription(1, &exhausted_spec),
    );
    try testing.expect(exhausted_spec.ptr == null);
    try testing.expectEqual(@as(usize, 1), destroyed);
    try testing.expectEqual(@as(usize, 0), harness.plane.trackedCount());
}

test "subscription identity storage and child reservations are bounded" {
    var harness: Harness = undefined;
    harness.init();
    defer harness.deinit();

    var index: usize = 0;
    while (index < DataPlane.capacity) : (index += 1) {
        const child = try harness.cancellations.reserve();
        try testing.expect(harness.cancellations.markAccepted(child));
        harness.plane.subscriptions[index] = .{
            .key = .{
                .generation = 1,
                .subscription_id = @intCast(index + 1),
            },
            .child_key = child,
        };
        harness.plane.count += 1;
    }
    var capacity_spec = inbox_mod.emptyTaskSpec();
    try testing.expectError(error.Capacity, harness.plane.startSubscription(1, &capacity_spec));
    try testing.expectEqual(DataPlane.capacity, harness.plane.trackedCount());
}

test "DataPlane source cannot own Future handles or mutating transport methods" {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "src/k8s/DataPlane.zig",
        testing.allocator,
        .limited(512 * 1024),
    );
    defer testing.allocator.free(source);
    for ([_][]const u8{
        "std.Io." ++ "Future",
        ".P" ++ "OST",
        ".P" ++ "UT",
        ".P" ++ "ATCH",
        ".D" ++ "ELETE",
    }) |needle| {
        try testing.expect(std.mem.indexOf(u8, source, needle) == null);
    }
}
