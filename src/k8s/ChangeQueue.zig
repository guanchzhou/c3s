const std = @import("std");
const testing = std.testing;

const runtime = @import("../core/runtime.zig");
const Wakeup = @import("../core/Wakeup.zig").Wakeup;
const keys = @import("ResourceKey.zig");

pub const Envelope = keys.Envelope;
pub const EnvelopeTarget = keys.EnvelopeTarget;
pub const Limits = keys.Limits;
pub const Generation = keys.Generation;

pub const Snapshot = struct {
    count: usize,
    bytes: usize,
    high_water_count: usize,
    high_water_bytes: usize,
    retries: u64,
    drops: u64,
};

const Queued = struct {
    envelope: Envelope,
    sequence: u64,
    lane: Lane,
};

const Lane = enum { data, ordinary, critical };

fn laneIndex(lane: Lane) usize {
    return @intFromEnum(lane);
}

pub const Popped = struct {
    envelope: Envelope,
    sequence: u64,
    lane: Lane,
    active: bool = true,
    /// Set only while this token holds the capacity reservation its envelope
    /// occupied in the queue, so `retryPopped` cannot lose the slot to a
    /// concurrent producer. Cleared once the reservation is resolved.
    reservation: ?*ChangeQueue = null,

    fn releaseReservation(self: *Popped) void {
        const queue = self.reservation orelse return;
        self.reservation = null;
        queue.releaseRetryReservation(self.lane, self.envelope.owned_bytes);
    }

    fn takeEnvelope(self: *Popped) Envelope {
        std.debug.assert(self.active);
        self.releaseReservation();
        self.active = false;
        return self.envelope;
    }

    pub fn destroy(self: *Popped, allocator: std.mem.Allocator) void {
        std.debug.assert(self.active);
        self.releaseReservation();
        self.envelope.deinit(allocator);
        self.active = false;
    }

    pub fn finishConsumed(self: *Popped) void {
        std.debug.assert(self.active);
        std.debug.assert(self.envelope.state == .consumed);
        self.releaseReservation();
        self.active = false;
    }
};

pub const ChangeQueue = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    limits: Limits,
    shared_event: *std.Io.Event,
    wakeup: ?*Wakeup,
    mutex: std.Io.Mutex = .init,
    items: std.ArrayListUnmanaged(Queued) = .empty,
    next_sequence: u64 = 1,
    data_count: usize = 0,
    data_bytes: usize = 0,
    ordinary_count: usize = 0,
    ordinary_bytes: usize = 0,
    critical_count: usize = 0,
    critical_bytes: usize = 0,
    /// Capacity held by outstanding `Popped` retry tokens, indexed by lane.
    /// Charged against the limits so a retry always has its slot back.
    reserved_count: [3]usize = @splat(0),
    reserved_bytes: [3]usize = @splat(0),
    closed: bool = false,
    queue_space_epoch: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    high_water_count: usize = 0,
    high_water_bytes: usize = 0,
    retries: u64 = 0,
    drops: u64 = 0,

    pub fn init(
        io: std.Io,
        allocator: std.mem.Allocator,
        limits: Limits,
        shared_event: *std.Io.Event,
        wakeup: ?*Wakeup,
    ) ChangeQueue {
        return .{
            .io = io,
            .allocator = allocator,
            .limits = limits,
            .shared_event = shared_event,
            .wakeup = wakeup,
        };
    }

    pub fn deinit(self: *ChangeQueue) void {
        self.mutex.lockUncancelable(self.io);
        self.closed = true;
        const leftover = self.items;
        self.items = .empty;
        self.mutex.unlock(self.io);
        for (leftover.items) |*item| item.envelope.deinit(self.allocator);
        var copy = leftover;
        copy.deinit(self.allocator);
    }

    pub fn spaceEpoch(self: *const ChangeQueue) u64 {
        return self.queue_space_epoch.load(.acquire);
    }

    pub fn hasPending(self: *ChangeQueue) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.items.items.len > 0;
    }

    pub fn snapshot(self: *ChangeQueue) Snapshot {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{
            .count = self.items.items.len,
            .bytes = self.data_bytes + self.ordinary_bytes + self.critical_bytes,
            .high_water_count = self.high_water_count,
            .high_water_bytes = self.high_water_bytes,
            .retries = self.retries,
            .drops = self.drops,
        };
    }

    pub fn close(self: *ChangeQueue) void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        self.closed = true;
    }

    pub fn tryPush(self: *ChangeQueue, envelope: Envelope) error{ Full, Closed }!void {
        return self.pushLane(envelope, .data);
    }

    pub fn tryPushControl(self: *ChangeQueue, envelope: Envelope) error{ Full, Closed }!void {
        return self.pushLane(envelope, .ordinary);
    }

    pub fn tryPushCritical(self: *ChangeQueue, envelope: Envelope) error{ Full, Closed }!void {
        return self.pushLane(envelope, .critical);
    }

    pub fn pop(self: *ChangeQueue) ?Envelope {
        var popped = self.removeNext(false) orelse return null;
        return popped.takeEnvelope();
    }

    /// Removes one item while retaining its original ordering token and the
    /// capacity it occupied. Only the sole UI consumer may hold this token, and
    /// only across one synchronous apply attempt before calling retryPopped or
    /// destroying it. Holding the reservation is what makes `retryPopped`
    /// infallible on capacity: no producer can claim the vacated slot.
    pub fn popForRetry(self: *ChangeQueue) ?Popped {
        return self.removeNext(true);
    }

    fn removeNext(self: *ChangeQueue, reserve: bool) ?Popped {
        self.mutex.lockUncancelable(self.io);
        const index = self.nextIndexLocked() orelse {
            self.mutex.unlock(self.io);
            return null;
        };
        const item = self.items.orderedRemove(index);
        self.debit(item.lane, item.envelope.owned_bytes);
        if (reserve) {
            self.reserved_count[laneIndex(item.lane)] += 1;
            self.reserved_bytes[laneIndex(item.lane)] += item.envelope.owned_bytes;
        }
        _ = self.queue_space_epoch.fetchAdd(1, .acq_rel);
        self.mutex.unlock(self.io);
        self.shared_event.set(self.io);
        return .{
            .envelope = item.envelope,
            .sequence = item.sequence,
            .lane = item.lane,
            .reservation = if (reserve) self else null,
        };
    }

    fn releaseRetryReservation(self: *ChangeQueue, lane: Lane, bytes: usize) void {
        self.mutex.lockUncancelable(self.io);
        self.reserved_count[laneIndex(lane)] -= 1;
        self.reserved_bytes[laneIndex(lane)] -= bytes;
        _ = self.queue_space_epoch.fetchAdd(1, .acq_rel);
        self.mutex.unlock(self.io);
        self.shared_event.set(self.io);
    }

    /// Requeues a just-popped item with its original sequence, consuming the
    /// reservation the token has held since `popForRetry`.
    /// Takes ownership only on success.
    pub fn retryPopped(self: *ChangeQueue, popped: *Popped) error{ Full, Closed }!void {
        std.debug.assert(popped.active);
        const lane = popped.lane;
        const bytes = popped.envelope.owned_bytes;
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.Closed;
        const reserved = popped.reservation != null;
        if (reserved) {
            self.reserved_count[laneIndex(lane)] -= 1;
            self.reserved_bytes[laneIndex(lane)] -= bytes;
        }
        errdefer if (reserved) {
            self.reserved_count[laneIndex(lane)] += 1;
            self.reserved_bytes[laneIndex(lane)] += bytes;
        };
        if (!self.fits(lane, bytes)) {
            self.drops +|= 1;
            return error.Full;
        }
        self.items.append(self.allocator, .{
            .envelope = popped.envelope,
            .sequence = popped.sequence,
            .lane = lane,
        }) catch return error.Full;
        self.credit(lane, bytes);
        self.retries +|= 1;
        self.updateHighWater();
        popped.reservation = null;
        popped.active = false;
        if (self.wakeup) |wakeup| wakeup.notify();
        self.shared_event.set(self.io);
    }

    /// Destroys queued data for one exact subscription identity while
    /// preserving every other subscription, including peers in its generation.
    pub fn purgeSubscription(
        self: *ChangeQueue,
        key: anytype,
    ) usize {
        var removed: usize = 0;
        while (true) {
            self.mutex.lockUncancelable(self.io);
            const match_index = for (self.items.items, 0..) |item, index| {
                const matches = switch (item.envelope.target) {
                    .resource => |resource| resource.generation == key.generation and
                        resource.subscription_id == key.subscription_id,
                    else => false,
                };
                if (matches) break index;
            } else null;
            const index = match_index orelse {
                self.mutex.unlock(self.io);
                break;
            };
            var owned = self.items.orderedRemove(index);
            self.debit(owned.lane, owned.envelope.owned_bytes);
            self.mutex.unlock(self.io);
            owned.envelope.deinit(self.allocator);
            removed += 1;
        }
        if (removed > 0) {
            _ = self.queue_space_epoch.fetchAdd(1, .acq_rel);
        }
        if (removed > 0) self.shared_event.set(self.io);
        return removed;
    }

    /// Destroys queued data for one exact ancillary request identity without
    /// affecting peer requests, resources, or lifecycle completions.
    pub fn purgeRequest(self: *ChangeQueue, key: keys.RequestKey) usize {
        var removed: usize = 0;
        while (true) {
            self.mutex.lockUncancelable(self.io);
            const match_index = for (self.items.items, 0..) |item, index| {
                const request_key = keys.requestKey(item.envelope.target) orelse continue;
                if (request_key.eql(key)) break index;
            } else null;
            const index = match_index orelse {
                self.mutex.unlock(self.io);
                break;
            };
            var owned = self.items.orderedRemove(index);
            self.debit(owned.lane, owned.envelope.owned_bytes);
            self.mutex.unlock(self.io);
            owned.envelope.deinit(self.allocator);
            removed += 1;
        }
        if (removed > 0) {
            _ = self.queue_space_epoch.fetchAdd(1, .acq_rel);
            self.shared_event.set(self.io);
        }
        return removed;
    }

    fn pushLane(self: *ChangeQueue, envelope: Envelope, lane: Lane) error{ Full, Closed }!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.Closed;
        if (keys.deliveryMustSplit(envelope.owned_bytes, self.limits) and lane == .data)
            return error.Full;
        if (lane != .data and envelope.owned_bytes > self.limits.max_control_envelope_bytes)
            return error.Full;
        if (!self.fits(lane, envelope.owned_bytes)) {
            self.drops +|= 1;
            return error.Full;
        }

        self.items.append(self.allocator, .{
            .envelope = envelope,
            .sequence = self.next_sequence,
            .lane = lane,
        }) catch return error.Full;
        self.next_sequence += 1;
        self.credit(lane, envelope.owned_bytes);
        self.updateHighWater();
        if (self.wakeup) |wakeup| wakeup.notify();
    }

    fn updateHighWater(self: *ChangeQueue) void {
        self.high_water_count = @max(self.high_water_count, self.items.items.len);
        self.high_water_bytes = @max(
            self.high_water_bytes,
            self.data_bytes + self.ordinary_bytes + self.critical_bytes,
        );
    }

    fn fits(self: *const ChangeQueue, lane: Lane, bytes: usize) bool {
        const held_count = self.reserved_count[laneIndex(lane)];
        const held_bytes = self.reserved_bytes[laneIndex(lane)];
        const total = self.data_count + self.ordinary_count + self.critical_count +
            self.reserved_count[0] + self.reserved_count[1] + self.reserved_count[2];
        if (total >= self.limits.max_batches) return false;
        return switch (lane) {
            .data => self.data_count + held_count < self.limits.max_data_batches and
                self.data_bytes + held_bytes + bytes <= self.limits.max_data_bytes,
            .ordinary => self.ordinary_count + held_count < self.limits.ordinary_control_batches and
                self.ordinary_bytes + held_bytes + bytes <= self.limits.ordinary_control_bytes,
            .critical => self.critical_count + held_count < self.limits.critical_control_batches and
                self.critical_bytes + held_bytes + bytes <= self.limits.critical_control_bytes,
        };
    }

    fn credit(self: *ChangeQueue, lane: Lane, bytes: usize) void {
        switch (lane) {
            .data => {
                self.data_count += 1;
                self.data_bytes += bytes;
            },
            .ordinary => {
                self.ordinary_count += 1;
                self.ordinary_bytes += bytes;
            },
            .critical => {
                self.critical_count += 1;
                self.critical_bytes += bytes;
            },
        }
    }

    fn debit(self: *ChangeQueue, lane: Lane, bytes: usize) void {
        switch (lane) {
            .data => {
                self.data_count -= 1;
                self.data_bytes -= bytes;
            },
            .ordinary => {
                self.ordinary_count -= 1;
                self.ordinary_bytes -= bytes;
            },
            .critical => {
                self.critical_count -= 1;
                self.critical_bytes -= bytes;
            },
        }
    }

    fn nextIndexLocked(self: *const ChangeQueue) ?usize {
        var best_in_order: ?usize = null;
        var best_bypass: ?usize = null;
        for (self.items.items, 0..) |item, i| {
            if (item.envelope.after_revision == null and item.lane != .data) {
                if (best_bypass == null or item.sequence < self.items.items[best_bypass.?].sequence)
                    best_bypass = i;
            }
            if (self.blockedByPriorData(i)) continue;
            if (best_in_order == null or item.sequence < self.items.items[best_in_order.?].sequence)
                best_in_order = i;
        }
        if (best_bypass) |bypass| {
            if (best_in_order) |in_order| {
                if (self.items.items[in_order].lane == .data) return bypass;
                if (self.items.items[bypass].sequence < self.items.items[in_order].sequence)
                    return bypass;
                return in_order;
            }
            return bypass;
        }
        return best_in_order;
    }

    fn blockedByPriorData(self: *const ChangeQueue, index: usize) bool {
        const item = self.items.items[index];
        const after = item.envelope.after_revision orelse return false;
        for (self.items.items) |other| {
            if (other.lane != .data) continue;
            if (other.sequence >= item.sequence) continue;
            if (other.envelope.revision <= after) return true;
        }
        return false;
    }
};

fn makeNotice(allocator: std.mem.Allocator, target: EnvelopeTarget, bytes: usize) !Envelope {
    const payload = try allocator.create(u8);
    payload.* = 1;
    return keys.erasePayload(
        u8,
        allocator,
        target,
        payload,
        &keys.test_noop_u8_handler,
        1,
        0,
        0,
        bytes,
        null,
    );
}

const RetryPayload = struct {
    fail_once: *bool,
    order: *[2]u8,
    applied: *usize,
    destroyed: *usize,
    id: u8,
};

fn retryPreflight(
    payload: *RetryPayload,
    _: *keys.UiRouter,
    _: std.mem.Allocator,
) anyerror!keys.ApplyPlan {
    if (payload.fail_once.*) {
        payload.fail_once.* = false;
        return error.PreflightFailed;
    }
    return keys.ApplyPlan.empty(0);
}

fn retryCommit(payload: *RetryPayload, _: *keys.UiRouter, _: *keys.ApplyPlan) void {
    payload.order[payload.applied.*] = payload.id;
    payload.applied.* += 1;
}

fn retryDestroy(payload: *RetryPayload, _: std.mem.Allocator) void {
    payload.destroyed.* += 1;
}

const retry_handler = keys.PayloadHandler(RetryPayload){
    .preflight = retryPreflight,
    .commit = retryCommit,
    .deinit = retryDestroy,
};

fn retryTarget(_: *anyopaque, _: EnvelopeTarget) ?*anyopaque {
    return @ptrFromInt(1);
}

fn makeRetryEnvelope(
    allocator: std.mem.Allocator,
    payload: RetryPayload,
    revision: keys.Revision,
    owned_bytes: usize,
) !Envelope {
    const owned = try allocator.create(RetryPayload);
    owned.* = payload;
    return keys.erasePayload(
        RetryPayload,
        allocator,
        .{ .resource = .{ .generation = 1, .subscription_id = 1 } },
        owned,
        &retry_handler,
        1,
        1,
        revision,
        owned_bytes,
        null,
    );
}

test "data and ordinary saturation still admit lifecycle_failed" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();

    var i: usize = 0;
    while (i < 60) : (i += 1) {
        const env = try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 1 } }, 1);
        try queue.tryPush(env);
    }
    i = 0;
    while (i < 3) : (i += 1) {
        const env = try makeNotice(allocator, .lifecycle, 1);
        try queue.tryPushControl(env);
    }
    var extra = try makeNotice(allocator, .lifecycle, 1);
    try testing.expectError(error.Full, queue.tryPushControl(extra));
    extra.deinit(allocator);

    const critical = try makeNotice(allocator, .lifecycle, 1);
    try queue.tryPushCritical(critical);
    try testing.expect(queue.hasPending());
}

test "fifth ordinary control returns Full and caller keeps ownership" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const env = try makeNotice(allocator, .lifecycle, 1);
        try queue.tryPushControl(env);
    }
    var fifth = try makeNotice(allocator, .lifecycle, 1);
    try testing.expectError(error.Full, queue.tryPushControl(fifth));
    try testing.expectEqual(Envelope.State.queued, fifth.state);
    fifth.deinit(allocator);
}

test "byte reserves: 192 KiB ordinary plus 64 KiB critical" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const env = try makeNotice(allocator, .lifecycle, 64 << 10);
        try queue.tryPushControl(env);
    }
    var overflow = try makeNotice(allocator, .lifecycle, 1);
    try testing.expectError(error.Full, queue.tryPushControl(overflow));
    overflow.deinit(allocator);

    const critical = try makeNotice(allocator, .lifecycle, 64 << 10);
    try queue.tryPushCritical(critical);
}

test "data byte cap is 15.75 MiB" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var limits = Limits.default;
    limits.max_child_delivery_bytes = 16 << 20;
    var queue = ChangeQueue.init(io, allocator, limits, &event, null);
    defer queue.deinit();

    const big = try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 1 } }, 15 << 20);
    try queue.tryPush(big);
    var overflow = try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 1 } }, (768 << 10) + 1);
    try testing.expectError(error.Full, queue.tryPush(overflow));
    overflow.deinit(allocator);
}

test "child delivery above 256 KiB is rejected with caller ownership" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();

    var env = try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 1 } }, (256 << 10) + 1);
    try testing.expectError(error.Full, queue.tryPush(env));
    try testing.expectEqual(Envelope.State.queued, env.state);
    env.deinit(allocator);
}

test "pop increments queue-space epoch and sets the shared Event" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();

    try testing.expectEqual(@as(u64, 0), queue.spaceEpoch());
    const env = try makeNotice(allocator, .lifecycle, 1);
    try queue.tryPushControl(env);
    const epoch_before = queue.spaceEpoch();
    var popped = queue.pop() orelse return error.MissingEnvelope;
    try testing.expectEqual(epoch_before + 1, queue.spaceEpoch());
    try testing.expect(event.isSet());
    popped.deinit(allocator);
}

test "unchanged space epoch stays dormant until UI pop" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();

    var i: usize = 0;
    while (i < 3) : (i += 1) {
        const env = try makeNotice(allocator, .lifecycle, 1);
        try queue.tryPushControl(env);
    }
    const epoch = queue.spaceEpoch();
    const held = try makeNotice(allocator, .lifecycle, 1);
    try testing.expectError(error.Full, queue.tryPushControl(held));
    try testing.expectEqual(epoch, queue.spaceEpoch());

    var popped = queue.pop() orelse return error.MissingEnvelope;
    popped.deinit(allocator);
    try testing.expectEqual(epoch + 1, queue.spaceEpoch());
    try queue.tryPushControl(held);
    var delivered = queue.pop() orelse return error.MissingRetry;
    delivered.deinit(allocator);
}

test "list-complete after_revision waits for prior data" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();

    var data = try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 1 } }, 1);
    data.revision = 4;
    try queue.tryPush(data);

    var complete = try makeNotice(allocator, .lifecycle, 1);
    complete.after_revision = 4;
    complete.revision = 4;
    try queue.tryPushControl(complete);

    var first = queue.pop() orelse return error.MissingData;
    try testing.expectEqual(EnvelopeTarget{ .resource = .{ .generation = 1, .subscription_id = 1 } }, first.target);
    first.deinit(allocator);

    var second = queue.pop() orelse return error.MissingComplete;
    try testing.expectEqual(EnvelopeTarget.lifecycle, second.target);
    second.deinit(allocator);
}

test "lifecycle error without after_revision may bypass data" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();

    const data = try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 1 } }, 1);
    try queue.tryPush(data);
    const fail = try makeNotice(allocator, .lifecycle, 1);
    try queue.tryPushCritical(fail);

    var first = queue.pop() orelse return error.Missing;
    try testing.expectEqual(EnvelopeTarget.lifecycle, first.target);
    first.deinit(allocator);
    var second = queue.pop() orelse return error.MissingData;
    second.deinit(allocator);
}

test "successful push notifies wakeup" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var wakeup = try Wakeup.init();
    defer wakeup.deinit();
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, &wakeup);
    defer queue.deinit();

    const env = try makeNotice(allocator, .lifecycle, 1);
    try queue.tryPushControl(env);
    try testing.expect(wakeup.pending.load(.acquire));
    wakeup.drain();
}

test "purgeSubscription keeps control lanes and increments space epoch once" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();

    try queue.tryPush(try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 1 } }, 1));
    try queue.tryPush(try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 1 } }, 1));
    try queue.tryPush(try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 2 } }, 1));
    try queue.tryPushControl(try makeNotice(allocator, .lifecycle, 1));

    const epoch = queue.spaceEpoch();
    try testing.expectEqual(@as(usize, 2), queue.purgeSubscription(.{
        .generation = 1,
        .subscription_id = 1,
    }));
    try testing.expectEqual(epoch + 1, queue.spaceEpoch());

    var extra_control: usize = 0;
    while (extra_control < 2) : (extra_control += 1) {
        try queue.tryPushControl(try makeNotice(allocator, .lifecycle, 1));
    }
    var overflow = try makeNotice(allocator, .lifecycle, 1);
    try testing.expectError(error.Full, queue.tryPushControl(overflow));
    overflow.deinit(allocator);

    var remaining_resource: usize = 0;
    var remaining_control: usize = 0;
    while (queue.pop()) |value| {
        var envelope = value;
        switch (envelope.target) {
            .resource => |resource| {
                remaining_resource += 1;
                try testing.expectEqual(@as(keys.SubscriptionId, 2), resource.subscription_id);
            },
            .lifecycle => remaining_control += 1,
            else => return error.UnexpectedTarget,
        }
        envelope.deinit(allocator);
    }
    try testing.expectEqual(@as(usize, 1), remaining_resource);
    try testing.expectEqual(@as(usize, 3), remaining_control);
}

test "purgeRequest removes only the exact ancillary key" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();

    const removed_key = keys.RequestKey{ .generation = 3, .subscription_id = 8 };
    const peer_key = keys.RequestKey{ .generation = 3, .subscription_id = 9 };
    try queue.tryPush(try makeNotice(allocator, .{ .header_metrics = removed_key }, 1));
    try queue.tryPush(try makeNotice(allocator, .{ .traffic = removed_key }, 1));
    try queue.tryPush(try makeNotice(allocator, .{ .header_metrics = peer_key }, 1));
    try queue.tryPush(try makeNotice(
        allocator,
        .{ .resource = .{
            .generation = removed_key.generation,
            .subscription_id = removed_key.subscription_id,
        } },
        1,
    ));
    try queue.tryPushControl(try makeNotice(allocator, .lifecycle, 1));

    try testing.expectEqual(@as(usize, 2), queue.purgeRequest(removed_key));
    var ancillary: usize = 0;
    var resource: usize = 0;
    var lifecycle_count: usize = 0;
    while (queue.pop()) |value| {
        var envelope = value;
        defer envelope.deinit(allocator);
        switch (envelope.target) {
            .header_metrics => |key| {
                ancillary += 1;
                try testing.expect(key.eql(peer_key));
            },
            .resource => resource += 1,
            .lifecycle => lifecycle_count += 1,
            else => return error.UnexpectedTarget,
        }
    }
    try testing.expectEqual(@as(usize, 1), ancillary);
    try testing.expectEqual(@as(usize, 1), resource);
    try testing.expectEqual(@as(usize, 1), lifecycle_count);
}

test "closed queue returns Closed and caller keeps the envelope" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();
    queue.close();
    var env = try makeNotice(allocator, .lifecycle, 1);
    try testing.expectError(error.Closed, queue.tryPushControl(env));
    env.deinit(allocator);
}

pub fn runTask14RetrySequenceGate() !void {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();
    var fail_a = true;
    var never_fail = false;
    var order: [2]u8 = undefined;
    var applied: usize = 0;
    var destroyed: usize = 0;
    const bytes = 7;
    try queue.tryPush(try makeRetryEnvelope(allocator, .{
        .fail_once = &fail_a,
        .order = &order,
        .applied = &applied,
        .destroyed = &destroyed,
        .id = 'A',
    }, 1, bytes));
    try queue.tryPush(try makeRetryEnvelope(allocator, .{
        .fail_once = &never_fail,
        .order = &order,
        .applied = &applied,
        .destroyed = &destroyed,
        .id = 'B',
    }, 2, bytes));
    var terminal = try makeNotice(allocator, .lifecycle, 1);
    terminal.after_revision = std.math.maxInt(keys.Revision);
    try queue.tryPushControl(terminal);
    try testing.expectEqual(@as(usize, 2), queue.data_count);
    try testing.expectEqual(@as(usize, bytes * 2), queue.data_bytes);

    var router = keys.UiRouter{ .context = @ptrFromInt(1), .targetFn = retryTarget };
    const epoch = queue.spaceEpoch();
    var first_attempt = queue.popForRetry() orelse return error.MissingA;
    try testing.expectEqual(@as(usize, 1), queue.data_count);
    try testing.expectEqual(@as(usize, bytes), queue.data_bytes);
    try testing.expectError(error.PreflightFailed, first_attempt.envelope.apply(&router, allocator));
    try queue.retryPopped(&first_attempt);
    try testing.expectEqual(@as(usize, 2), queue.data_count);
    try testing.expectEqual(@as(usize, bytes * 2), queue.data_bytes);
    try testing.expectEqual(epoch + 1, queue.spaceEpoch());

    var retried = queue.popForRetry() orelse return error.MissingRetriedA;
    try retried.envelope.apply(&router, allocator);
    retried.finishConsumed();
    var later = queue.popForRetry() orelse return error.MissingB;
    try later.envelope.apply(&router, allocator);
    later.finishConsumed();
    var completion = queue.popForRetry() orelse return error.MissingCompletion;
    try testing.expectEqual(EnvelopeTarget.lifecycle, completion.envelope.target);
    completion.destroy(allocator);

    try testing.expectEqualSlices(u8, "AB", &order);
    try testing.expectEqual(@as(usize, 2), destroyed);
    try testing.expect(!queue.hasPending());
}

test "retry preserves original sequence ahead of later data and fenced completion" {
    try runTask14RetrySequenceGate();
}

test "a saturated lane holds the popped slot so retry cannot lose it" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    const limits = Limits{ .max_batches = 4, .max_data_batches = 2, .max_data_bytes = 32 };
    var queue = ChangeQueue.init(io, allocator, limits, &event, null);
    defer queue.deinit();
    try queue.tryPush(try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 1 } }, 16));
    try queue.tryPush(try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 2 } }, 16));

    var popped = queue.popForRetry() orelse return error.MissingPopped;
    errdefer if (popped.active) popped.destroy(allocator);
    try testing.expectEqual(@as(usize, 1), queue.data_count);

    // The vacated slot stays charged to the token, so a concurrent producer
    // cannot claim it and strand the envelope the UI still owns.
    var intruder = try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 3 } }, 16);
    try testing.expectError(error.Full, queue.tryPush(intruder));
    intruder.deinit(allocator);

    try queue.retryPopped(&popped);
    try testing.expectEqual(@as(usize, 2), queue.data_count);
    try testing.expectEqual(@as(usize, 0), queue.reserved_count[0]);
    try testing.expectEqual(@as(usize, 0), queue.reserved_bytes[0]);

    while (queue.pop()) |value| {
        var envelope = value;
        envelope.deinit(allocator);
    }
}

test "resolving a retry token returns its reserved capacity to producers" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    const limits = Limits{ .max_batches = 4, .max_data_batches = 1, .max_data_bytes = 16 };
    var queue = ChangeQueue.init(io, allocator, limits, &event, null);
    defer queue.deinit();
    try queue.tryPush(try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 1 } }, 16));

    var popped = queue.popForRetry() orelse return error.MissingPopped;
    const epoch = queue.spaceEpoch();
    popped.destroy(allocator);
    try testing.expectEqual(@as(usize, 0), queue.reserved_count[0]);
    try testing.expect(queue.spaceEpoch() > epoch);

    try queue.tryPush(try makeNotice(allocator, .{ .resource = .{ .generation = 1, .subscription_id = 2 } }, 16));
    var drained = queue.pop() orelse return error.MissingDrained;
    drained.deinit(allocator);
}

test "stale popped data is destroyed without retry" {
    const allocator = testing.allocator;
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var queue = ChangeQueue.init(io, allocator, Limits.default, &event, null);
    defer queue.deinit();
    var never_fail = false;
    var order: [2]u8 = undefined;
    var applied: usize = 0;
    var destroyed: usize = 0;
    try queue.tryPush(try makeRetryEnvelope(allocator, .{
        .fail_once = &never_fail,
        .order = &order,
        .applied = &applied,
        .destroyed = &destroyed,
        .id = 'S',
    }, 1, 1));

    var stale = queue.popForRetry() orelse return error.MissingStale;
    stale.destroy(allocator);
    try testing.expectEqual(@as(usize, 1), destroyed);
    try testing.expectEqual(@as(usize, 0), applied);
    try testing.expect(!queue.hasPending());
}
