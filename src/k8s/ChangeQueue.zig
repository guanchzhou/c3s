const std = @import("std");
const testing = std.testing;

const runtime = @import("../core/runtime.zig");
const Wakeup = @import("../core/Wakeup.zig").Wakeup;
const keys = @import("ResourceKey.zig");

pub const Envelope = keys.Envelope;
pub const EnvelopeTarget = keys.EnvelopeTarget;
pub const Limits = keys.Limits;
pub const Generation = keys.Generation;

const Queued = struct {
    envelope: Envelope,
    sequence: u64,
    lane: Lane,
};

const Lane = enum { data, ordinary, critical };

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
    closed: bool = false,
    queue_space_epoch: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

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
        self.mutex.lockUncancelable(self.io);
        const index = self.nextIndexLocked() orelse {
            self.mutex.unlock(self.io);
            return null;
        };
        const item = self.items.orderedRemove(index);
        self.debit(item.lane, item.envelope.owned_bytes);
        const epoch = self.queue_space_epoch.fetchAdd(1, .acq_rel) + 1;
        _ = epoch;
        self.mutex.unlock(self.io);
        self.shared_event.set(self.io);
        return item.envelope;
    }

    fn pushLane(self: *ChangeQueue, envelope: Envelope, lane: Lane) error{ Full, Closed }!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        if (self.closed) return error.Closed;
        if (keys.deliveryMustSplit(envelope.owned_bytes, self.limits) and lane == .data)
            return error.Full;
        if (lane != .data and envelope.owned_bytes > self.limits.max_control_envelope_bytes)
            return error.Full;
        if (!self.fits(lane, envelope.owned_bytes)) return error.Full;

        self.items.append(self.allocator, .{
            .envelope = envelope,
            .sequence = self.next_sequence,
            .lane = lane,
        }) catch return error.Full;
        self.next_sequence += 1;
        self.credit(lane, envelope.owned_bytes);
        if (self.wakeup) |wakeup| wakeup.notify();
    }

    fn fits(self: *const ChangeQueue, lane: Lane, bytes: usize) bool {
        const total = self.data_count + self.ordinary_count + self.critical_count;
        if (total >= self.limits.max_batches) return false;
        return switch (lane) {
            .data => self.data_count < self.limits.max_data_batches and
                self.data_bytes + bytes <= self.limits.max_data_bytes,
            .ordinary => self.ordinary_count < self.limits.ordinary_control_batches and
                self.ordinary_bytes + bytes <= self.limits.ordinary_control_bytes,
            .critical => self.critical_count < self.limits.critical_control_batches and
                self.critical_bytes + bytes <= self.limits.critical_control_bytes,
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
