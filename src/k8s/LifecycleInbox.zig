const std = @import("std");
const testing = std.testing;

const runtime = @import("../core/runtime.zig");
const keys = @import("ResourceKey.zig");
const session_mod = @import("ActiveContextSession.zig");

pub const Generation = keys.Generation;
pub const SubscriptionId = keys.SubscriptionId;
pub const ErrorDetail = keys.ErrorDetail;
pub const Envelope = keys.Envelope;
pub const OwnedContextSpec = session_mod.OwnedContextSpec;
pub const ContextSpec = session_mod.ContextSpec;
pub const ActiveContextSession = session_mod.ActiveContextSession;
pub const RequestLease = session_mod.RequestLease;

pub const SwitchId = u64;
pub const RequestId = u64;

pub const ChildKey = struct {
    slot: u16,
    generation: u60,

    pub fn eql(self: ChildKey, other: ChildKey) bool {
        return self.slot == other.slot and self.generation == other.generation;
    }
};

pub const SubscriptionKey = struct {
    generation: Generation,
    subscription_id: SubscriptionId,
};

pub const ChildKind = enum {
    context_preparation,
    resource_subscription,
    command_request,
    retirement,
};

pub const ChildPhase = enum {
    starting,
    running,
    delivery_ready,
    returning,
    reaped,
};

pub const OwnedPayloadTicket = struct {
    ptr: *anyopaque,
    alignment: std.mem.Alignment,
    owned_bytes: usize,
    deinitFn: *const fn (*anyopaque, std.mem.Alignment, std.mem.Allocator) void,

    pub fn deinit(self: *OwnedPayloadTicket, allocator: std.mem.Allocator) void {
        self.deinitFn(self.ptr, self.alignment, allocator);
        self.ptr = undefined;
    }
};

pub const OwnedTaskSpec = struct {
    ptr: ?*anyopaque = null,
    alignment: std.mem.Alignment = .@"1",
    owned_bytes: usize = 0,
    runFn: *const fn (*anyopaque, *ChildControl, std.Io) std.Io.Cancelable!void = noopRun,
    deinitFn: *const fn (?*anyopaque, std.mem.Alignment, std.mem.Allocator) void = noopSpecDeinit,

    pub fn deinit(self: *OwnedTaskSpec, allocator: std.mem.Allocator) void {
        self.deinitFn(self.ptr, self.alignment, allocator);
        self.ptr = null;
        self.owned_bytes = 0;
    }
};

fn noopRun(_: *anyopaque, _: *ChildControl, _: std.Io) std.Io.Cancelable!void {}
fn noopSpecDeinit(_: ?*anyopaque, _: std.mem.Alignment, _: std.mem.Allocator) void {}

pub fn emptyTaskSpec() OwnedTaskSpec {
    return .{};
}

pub const LifecycleCommand = union(enum) {
    prepare_context: struct { switch_id: SwitchId, spec: OwnedContextSpec },
    start_subscription: struct {
        child_key: ChildKey,
        expected_generation: Generation,
        key: SubscriptionKey,
        spec: OwnedTaskSpec,
    },
    start_request: struct {
        child_key: ChildKey,
        expected_generation: Generation,
        request_id: RequestId,
        spec: OwnedTaskSpec,
    },
    retire: Generation,
    shutdown,

    pub fn deinit(self: *LifecycleCommand, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .prepare_context => |*prep| prep.spec.deinit(allocator),
            .start_subscription => |*start| start.spec.deinit(allocator),
            .start_request => |*start| start.spec.deinit(allocator),
            .retire, .shutdown => {},
        }
        self.* = .shutdown;
    }

    fn taskBytes(self: LifecycleCommand) usize {
        return switch (self) {
            .start_subscription => |start| start.spec.owned_bytes,
            .start_request => |start| start.spec.owned_bytes,
            else => 0,
        };
    }

    fn lane(self: LifecycleCommand) Lane {
        return switch (self) {
            .prepare_context, .start_subscription, .start_request => .normal,
            .retire => .control,
            .shutdown => .shutdown,
        };
    }
};

const Lane = enum { normal, control, shutdown };

pub const LifecycleCompletion = union(enum) {
    context_committed: struct { switch_id: SwitchId, generation: Generation },
    context_failed: struct { switch_id: SwitchId, detail: ErrorDetail },
    context_canceled: SwitchId,
    subscription_stopped: struct { key: SubscriptionKey, detail: ?ErrorDetail },
    request_finished: struct { request_id: RequestId, ticket: OwnedPayloadTicket },
    start_rejected: struct {
        child_key: ChildKey,
        code: enum { stale_generation, capacity, shutting_down },
    },
    lifecycle_stalled: struct { generation: Generation, lease_count: usize },
    lifecycle_failed: ErrorDetail,
    shutdown_complete,

    pub fn deinit(self: *LifecycleCompletion, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .request_finished => |*finished| finished.ticket.deinit(allocator),
            else => {},
        }
        self.* = .shutdown_complete;
    }
};

pub const ChildOutcomeStorage = union(enum) {
    none,
    candidate_ready: *ActiveContextSession,
    candidate_failed: ErrorDetail,
    delivery: Envelope,
    completed: LifecycleCompletion,

    pub fn takeCandidate(self: *ChildOutcomeStorage) ?*ActiveContextSession {
        switch (self.*) {
            .candidate_ready => |session| {
                self.* = .none;
                return session;
            },
            else => return null,
        }
    }

    pub fn deinitNonCandidate(self: *ChildOutcomeStorage, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .none, .candidate_failed => {},
            .candidate_ready => std.debug.panic("deinitNonCandidate on candidate_ready", .{}),
            .delivery => |*envelope| envelope.deinit(allocator),
            .completed => |*completion| completion.deinit(allocator),
        }
        self.* = .none;
    }
};

pub const ChildControl = struct {
    key: ChildKey,
    kind: ChildKind,
    phase: std.atomic.Value(ChildPhase) = std.atomic.Value(ChildPhase).init(.starting),
    outcome: ChildOutcomeStorage = .none,
    lease: ?RequestLease = null,
    delivery_ack: std.Io.Event = .unset,
    observed_queue_space_epoch: ?u64 = null,
    spec: OwnedTaskSpec = .{},
    io: std.Io,
    shared_event: *std.Io.Event,
    allocator: std.mem.Allocator,

    pub fn publishDelivery(self: *ChildControl, envelope: Envelope) std.Io.Cancelable!void {
        std.debug.assert(self.outcome == .none);
        self.outcome = .{ .delivery = envelope };
        self.phase.store(.delivery_ready, .release);
        self.shared_event.set(self.io);
        try self.delivery_ack.wait(self.io);
        self.delivery_ack.reset();
    }

    pub fn finish(self: *ChildControl, completion: LifecycleCompletion) void {
        std.debug.assert(self.outcome == .none);
        self.outcome = .{ .completed = completion };
        self.phase.store(.returning, .release);
        self.shared_event.set(self.io);
    }

    pub fn finishCandidate(self: *ChildControl, session: *ActiveContextSession) void {
        std.debug.assert(self.outcome == .none);
        self.outcome = .{ .candidate_ready = session };
        self.phase.store(.returning, .release);
        self.shared_event.set(self.io);
    }
};

pub const CancellationCellState = enum(u3) {
    free,
    reserved,
    accepted,
    live,
    canceling,
};

pub const CancellationWord = packed struct(u64) {
    generation: u60,
    state: CancellationCellState,
    cancel_requested: bool,
};

pub const CancellationIntents = struct {
    pub const capacity = 512;
    pub const max_generation: u60 = std.math.maxInt(u60);

    cells: [capacity]std.atomic.Value(u64) = [_]std.atomic.Value(u64){std.atomic.Value(u64).init(0)} ** capacity,

    pub fn init() CancellationIntents {
        return .{};
    }

    pub fn reserve(self: *CancellationIntents) error{Capacity}!ChildKey {
        var slot: u16 = 0;
        while (slot < capacity) : (slot += 1) {
            var observed = self.cells[slot].load(.monotonic);
            while (true) {
                const word = unpack(observed);
                if (word.state != .free) break;
                if (word.generation == max_generation) break;
                const next = CancellationWord{
                    .generation = word.generation + 1,
                    .state = .reserved,
                    .cancel_requested = false,
                };
                if (self.cells[slot].cmpxchgWeak(observed, pack(next), .acq_rel, .monotonic)) |actual| {
                    observed = actual;
                    continue;
                }
                return .{ .slot = slot, .generation = next.generation };
            }
        }
        return error.Capacity;
    }

    pub fn markAccepted(self: *CancellationIntents, key: ChildKey) bool {
        return self.transition(key, .reserved, .accepted, false);
    }

    pub fn markLive(self: *CancellationIntents, key: ChildKey) bool {
        return self.transition(key, .accepted, .live, false);
    }

    pub fn request(self: *CancellationIntents, key: ChildKey) bool {
        var observed = self.cells[key.slot].load(.monotonic);
        while (true) {
            var word = unpack(observed);
            if (word.generation != key.generation) return false;
            switch (word.state) {
                .free, .reserved => return false,
                .canceling => return true,
                .accepted, .live => {
                    if (word.cancel_requested) return true;
                    word.cancel_requested = true;
                    if (self.cells[key.slot].cmpxchgWeak(observed, pack(word), .acq_rel, .monotonic)) |actual| {
                        observed = actual;
                        continue;
                    }
                    return true;
                },
            }
        }
    }

    pub fn claimRequested(self: *CancellationIntents, key: ChildKey) enum { none, accepted_not_launched, live } {
        var observed = self.cells[key.slot].load(.monotonic);
        while (true) {
            var word = unpack(observed);
            if (word.generation != key.generation) return .none;
            if (!word.cancel_requested and word.state != .canceling) return .none;
            const kind: enum { none, accepted_not_launched, live } = switch (word.state) {
                .accepted => .accepted_not_launched,
                .live => .live,
                .canceling => return if (word.cancel_requested) .live else .none,
                .free, .reserved => return .none,
            };
            word.state = .canceling;
            word.cancel_requested = true;
            if (self.cells[key.slot].cmpxchgWeak(observed, pack(word), .acq_rel, .monotonic)) |actual| {
                observed = actual;
                continue;
            }
            return kind;
        }
    }

    pub fn free(self: *CancellationIntents, key: ChildKey) bool {
        var observed = self.cells[key.slot].load(.monotonic);
        while (true) {
            var word = unpack(observed);
            if (word.generation != key.generation) return false;
            if (word.state == .free) return true;
            word.state = .free;
            word.cancel_requested = false;
            if (self.cells[key.slot].cmpxchgWeak(observed, pack(word), .acq_rel, .monotonic)) |actual| {
                observed = actual;
                continue;
            }
            return true;
        }
    }

    fn transition(
        self: *CancellationIntents,
        key: ChildKey,
        from: CancellationCellState,
        to: CancellationCellState,
        keep_cancel: bool,
    ) bool {
        var observed = self.cells[key.slot].load(.monotonic);
        while (true) {
            var word = unpack(observed);
            if (word.generation != key.generation) return false;
            if (word.state != from) return false;
            word.state = to;
            if (!keep_cancel) word.cancel_requested = false;
            if (self.cells[key.slot].cmpxchgWeak(observed, pack(word), .acq_rel, .monotonic)) |actual| {
                observed = actual;
                continue;
            }
            return true;
        }
    }

    fn unpack(raw: u64) CancellationWord {
        return @bitCast(raw);
    }

    fn pack(word: CancellationWord) u64 {
        return @bitCast(word);
    }
};

pub const LifecycleInbox = struct {
    pub const capacity = 256;
    pub const normal_capacity = 240;
    pub const reserved_control_capacity = 16;
    pub const retire_control_capacity = 15;
    pub const shutdown_capacity = 1;
    pub const max_task_spec_bytes = 64 << 10;

    entries: [capacity]?LifecycleCommand = [_]?LifecycleCommand{null} ** capacity,
    head: std.atomic.Value(u64) = .init(0),
    tail: std.atomic.Value(u64) = .init(0),
    normal_occupied: std.atomic.Value(u32) = .init(0),
    control_occupied: std.atomic.Value(u32) = .init(0),
    normal_closed: std.atomic.Value(bool) = .init(false),
    shutdown_enqueued: std.atomic.Value(bool) = .init(false),
    root_terminated: std.atomic.Value(bool) = .init(false),
    io: std.Io,
    shared_event: *std.Io.Event,

    pub fn init(io: std.Io, shared_event: *std.Io.Event) LifecycleInbox {
        return .{ .io = io, .shared_event = shared_event };
    }

    pub fn tryPush(self: *LifecycleInbox, command: LifecycleCommand) error{ Full, Closed, TaskSpecTooLarge }!void {
        if (self.root_terminated.load(.acquire)) return error.Closed;
        if (command.taskBytes() > max_task_spec_bytes) return error.TaskSpecTooLarge;

        switch (command.lane()) {
            .shutdown => {
                self.enqueueShutdownInternal(command);
                return;
            },
            .normal => {
                if (self.normal_closed.load(.acquire)) return error.Closed;
                if (self.normal_occupied.load(.monotonic) >= normal_capacity) return error.Full;
            },
            .control => {
                if (self.control_occupied.load(.monotonic) >= retire_control_capacity) return error.Full;
            },
        }

        const t = self.tail.load(.monotonic);
        const h = self.head.load(.acquire);
        if (t - h >= capacity) return error.Full;

        self.entries[t % capacity] = command;
        switch (command.lane()) {
            .normal => _ = self.normal_occupied.fetchAdd(1, .acq_rel),
            .control => _ = self.control_occupied.fetchAdd(1, .acq_rel),
            .shutdown => {},
        }
        self.tail.store(t + 1, .release);
        self.shared_event.set(self.io);
    }

    pub fn enqueueShutdown(self: *LifecycleInbox) error{Closed}!void {
        if (self.root_terminated.load(.acquire)) return error.Closed;
        self.enqueueShutdownInternal(.shutdown);
    }

    pub fn tryPop(self: *LifecycleInbox) ?LifecycleCommand {
        const h = self.head.load(.monotonic);
        const t = self.tail.load(.acquire);
        if (h == t) return null;
        const command = self.entries[h % capacity] orelse return null;
        self.entries[h % capacity] = null;
        switch (command.lane()) {
            .normal => _ = self.normal_occupied.fetchSub(1, .acq_rel),
            .control => _ = self.control_occupied.fetchSub(1, .acq_rel),
            .shutdown => {},
        }
        self.head.store(h + 1, .release);
        return command;
    }

    pub fn closeNormal(self: *LifecycleInbox) void {
        self.normal_closed.store(true, .release);
    }

    pub fn markRootTerminated(self: *LifecycleInbox) void {
        self.root_terminated.store(true, .release);
        self.shared_event.set(self.io);
    }

    pub fn deinit(self: *LifecycleInbox, allocator: std.mem.Allocator) void {
        while (self.tryPop()) |cmd| {
            var owned = cmd;
            owned.deinit(allocator);
        }
    }

    fn enqueueShutdownInternal(self: *LifecycleInbox, command: LifecycleCommand) void {
        self.normal_closed.store(true, .release);
        if (self.shutdown_enqueued.swap(true, .acq_rel)) return;
        const t = self.tail.load(.monotonic);
        self.entries[t % capacity] = command;
        self.tail.store(t + 1, .release);
        self.shared_event.set(self.io);
    }
};

pub const LifecycleProducer = struct {
    inbox: *LifecycleInbox,
    cancellations: *CancellationIntents,
    io: std.Io,
    shared_event: *std.Io.Event,
    allocator: std.mem.Allocator,

    pub fn init(
        inbox: *LifecycleInbox,
        cancellations: *CancellationIntents,
        allocator: std.mem.Allocator,
    ) LifecycleProducer {
        return .{
            .inbox = inbox,
            .cancellations = cancellations,
            .io = inbox.io,
            .shared_event = inbox.shared_event,
            .allocator = allocator,
        };
    }

    pub fn reserveChild(self: *LifecycleProducer) error{Capacity}!ChildKey {
        return self.cancellations.reserve();
    }

    pub fn tryPushCommand(self: *LifecycleProducer, command: LifecycleCommand) error{ Full, Closed, TaskSpecTooLarge }!void {
        return self.inbox.tryPush(command);
    }

    pub fn tryPushStart(self: *LifecycleProducer, command: LifecycleCommand) error{ Full, Closed, TaskSpecTooLarge }!void {
        const key = switch (command) {
            .start_subscription => |start| start.child_key,
            .start_request => |start| start.child_key,
            else => {
                self.tryPushCommand(command) catch |err| return err;
                return;
            },
        };
        self.inbox.tryPush(command) catch |err| {
            _ = self.cancellations.free(key);
            return err;
        };
        _ = self.cancellations.markAccepted(key);
    }

    pub fn tryRequestCancel(self: *LifecycleProducer, key: ChildKey) bool {
        const matched = self.cancellations.request(key);
        self.shared_event.set(self.io);
        return matched;
    }

    pub fn enqueueShutdown(self: *LifecycleProducer) error{Closed}!void {
        try self.inbox.enqueueShutdown();
    }
};

fn sampleSpec(name: []const u8) ContextSpec {
    return .{
        .context_name = name,
        .kubeconfig_path = null,
        .default_namespace = "default",
        .force_proxy = false,
        .readonly = true,
    };
}

fn startCommand(key: ChildKey, spec: OwnedTaskSpec) LifecycleCommand {
    return .{ .start_subscription = .{
        .child_key = key,
        .expected_generation = 1,
        .key = .{ .generation = 1, .subscription_id = 1 },
        .spec = spec,
    } };
}

test "normal ring saturates at 240 then retire control still admits" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);

    var i: usize = 0;
    while (i < LifecycleInbox.normal_capacity) : (i += 1) {
        try inbox.tryPush(startCommand(.{ .slot = 0, .generation = 1 }, emptyTaskSpec()));
    }
    try testing.expectError(error.Full, inbox.tryPush(startCommand(.{ .slot = 1, .generation = 1 }, emptyTaskSpec())));

    i = 0;
    while (i < LifecycleInbox.retire_control_capacity) : (i += 1) {
        try inbox.tryPush(.{ .retire = 1 });
    }
    try testing.expectError(error.Full, inbox.tryPush(.{ .retire = 2 }));
    try inbox.enqueueShutdown();
}

test "enqueueShutdown never returns Full and repeats are no-ops" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);

    var i: usize = 0;
    while (i < LifecycleInbox.normal_capacity) : (i += 1) {
        try inbox.tryPush(startCommand(.{ .slot = 0, .generation = 1 }, emptyTaskSpec()));
    }
    i = 0;
    while (i < LifecycleInbox.retire_control_capacity) : (i += 1) {
        try inbox.tryPush(.{ .retire = 1 });
    }
    try inbox.enqueueShutdown();
    try inbox.enqueueShutdown();
    inbox.markRootTerminated();
    try testing.expectError(error.Closed, inbox.enqueueShutdown());
}

test "Closed shutdown is only after root_terminated" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    try inbox.enqueueShutdown();
    try inbox.tryPush(.{ .retire = 1 });
    inbox.markRootTerminated();
    var leftover = startCommand(.{ .slot = 0, .generation = 1 }, emptyTaskSpec());
    try testing.expectError(error.Closed, inbox.tryPush(leftover));
    leftover.deinit(testing.allocator);
}

test "TaskSpecTooLarge preserves caller ownership" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var spec = emptyTaskSpec();
    spec.owned_bytes = LifecycleInbox.max_task_spec_bytes + 1;
    var command = startCommand(.{ .slot = 0, .generation = 1 }, spec);
    try testing.expectError(error.TaskSpecTooLarge, inbox.tryPush(command));
    command.deinit(testing.allocator);
}

test "successful push always sets the shared Event" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    event.reset();
    try inbox.tryPush(.{ .retire = 1 });
    try testing.expect(event.isSet());
    _ = inbox.tryPop();
    event.reset();
    try inbox.tryPush(.{ .retire = 2 });
    try testing.expect(event.isSet());
}

test "consumer draining the last entry does not drop a concurrent push wake" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    try inbox.tryPush(.{ .retire = 1 });
    const first = inbox.tryPop() orelse return error.Missing;
    try testing.expectEqual(@as(Generation, 1), first.retire);
    event.reset();
    try inbox.tryPush(.{ .retire = 2 });
    try testing.expect(event.isSet());
    const second = inbox.tryPop() orelse return error.MissingWake;
    try testing.expectEqual(@as(Generation, 2), second.retire);
}

test "cancellation of all 512 accepted ChildKeys after a full normal ring" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var producer = LifecycleProducer.init(&inbox, &cancellations, testing.allocator);

    var keys_held: [CancellationIntents.capacity]ChildKey = undefined;
    var n: usize = 0;
    while (n < CancellationIntents.capacity) : (n += 1) {
        keys_held[n] = try producer.reserveChild();
        if (n < LifecycleInbox.normal_capacity) {
            try producer.tryPushStart(startCommand(keys_held[n], emptyTaskSpec()));
        } else {
            _ = cancellations.markAccepted(keys_held[n]);
        }
    }
    try testing.expectError(error.Capacity, producer.reserveChild());

    for (keys_held) |key| {
        try testing.expect(producer.tryRequestCancel(key));
        try testing.expect(producer.tryRequestCancel(key));
    }
    try testing.expect(!producer.tryRequestCancel(.{ .slot = 0, .generation = 0 }));
}

test "generation-safe slot reuse and no wrap at max u60" {
    var cancellations = CancellationIntents.init();
    const first = try cancellations.reserve();
    try testing.expectEqual(@as(u60, 1), first.generation);
    _ = cancellations.free(first);
    const second = try cancellations.reserve();
    try testing.expectEqual(first.slot, second.slot);
    try testing.expectEqual(@as(u60, 2), second.generation);
    try testing.expect(!cancellations.request(first));
    _ = cancellations.free(second);

    cancellations.cells[0].store(packWord(CancellationIntents.max_generation, .free, false), .release);
    try testing.expectError(error.Capacity, blk: {
        var slot: u16 = 0;
        while (slot < CancellationIntents.capacity) : (slot += 1) {
            if (slot == 0) continue;
            cancellations.cells[slot].store(packWord(1, .live, false), .release);
        }
        break :blk cancellations.reserve();
    });
}

fn packWord(generation: u60, state: CancellationCellState, cancel: bool) u64 {
    return @bitCast(CancellationWord{
        .generation = generation,
        .state = state,
        .cancel_requested = cancel,
    });
}

test "stale-key rejection and retire matching intents" {
    var cancellations = CancellationIntents.init();
    const key = try cancellations.reserve();
    _ = cancellations.markAccepted(key);
    try testing.expect(cancellations.request(key));
    try testing.expectEqual(.accepted_not_launched, cancellations.claimRequested(key));
    _ = cancellations.free(key);
    try testing.expect(!cancellations.request(key));
}

test "failed start push frees the reserved ChildKey" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var producer = LifecycleProducer.init(&inbox, &cancellations, testing.allocator);

    var i: usize = 0;
    while (i < LifecycleInbox.normal_capacity) : (i += 1) {
        const key = try producer.reserveChild();
        try producer.tryPushStart(startCommand(key, emptyTaskSpec()));
    }
    const extra = try producer.reserveChild();
    var command = startCommand(extra, emptyTaskSpec());
    try testing.expectError(error.Full, producer.tryPushStart(command));
    command.deinit(testing.allocator);
    const reused = try producer.reserveChild();
    try testing.expectEqual(extra.slot, reused.slot);
    _ = cancellations.free(reused);
}
