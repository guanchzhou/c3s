const std = @import("std");
const testing = std.testing;

const runtime = @import("../core/runtime.zig");
const inbox_mod = @import("LifecycleInbox.zig");
const queue_mod = @import("ChangeQueue.zig");
const keys = @import("ResourceKey.zig");
const session_mod = @import("ActiveContextSession.zig");
const slot_mod = @import("ActiveSessionSlot.zig");
const DataPlane = @import("DataPlane.zig").DataPlane;

pub const LifecycleInbox = inbox_mod.LifecycleInbox;
pub const LifecycleProducer = inbox_mod.LifecycleProducer;
pub const LifecycleCommand = inbox_mod.LifecycleCommand;
pub const LifecycleCompletion = inbox_mod.LifecycleCompletion;
pub const CancellationIntents = inbox_mod.CancellationIntents;
pub const ChildControl = inbox_mod.ChildControl;
pub const ChildKey = inbox_mod.ChildKey;
pub const ChildPhase = inbox_mod.ChildPhase;
pub const OwnedTaskSpec = inbox_mod.OwnedTaskSpec;
pub const SwitchId = inbox_mod.SwitchId;
pub const Generation = inbox_mod.Generation;
pub const ActiveContextSession = session_mod.ActiveContextSession;
pub const SessionFactory = session_mod.SessionFactory;
pub const ActiveSessionSlot = slot_mod.ActiveSessionSlot;
pub const ChangeQueue = queue_mod.ChangeQueue;
pub const Envelope = keys.Envelope;
pub const ErrorDetail = keys.ErrorDetail;

const ChildResult = anyerror!void;
const ChildFuture = std.Io.Future(ChildResult);
const detached_completion_capacity =
    CancellationIntents.capacity + LifecycleInbox.retire_control_capacity + 2;

const ChildWork = union(enum) {
    task: struct {
        completion: LifecycleCompletion,
    },
    preparation: struct {
        switch_id: SwitchId,
        generation: Generation,
        spec: session_mod.OwnedContextSpec,
    },
};

const ChildNode = struct {
    control: ChildControl,
    future: ?ChildFuture = null,
    work: ChildWork,
    expected_generation: Generation,
    pending: ?Envelope = null,
    pending_critical: bool = false,
    canceled: bool = false,
    entered: std.atomic.Value(bool) = .init(false),
};

const RetiringSession = struct {
    session: *ActiveContextSession,
    generation: Generation,
    observed_lease_epoch: u64,
    stalled_reported: bool = false,
};

const DetachedCompletion = struct {
    envelope: Envelope,
    release_key: ?ChildKey,
    observed_queue_space_epoch: u64,
    critical: bool,
};

pub const Metrics = struct {
    launched: usize = 0,
    reaped: usize = 0,
    canceled: usize = 0,
    max_live: usize = 0,
    root_awaits: usize = 0,
};

pub const LifecycleSupervisor = struct {
    pub const max_retiring_sessions = LifecycleInbox.retire_control_capacity + 1;

    allocator: std.mem.Allocator,
    io: std.Io,
    shared_event: *std.Io.Event,
    inbox: *LifecycleInbox,
    cancellations: *CancellationIntents,
    active_slot: *ActiveSessionSlot,
    change_queue: *ChangeQueue,
    session_factory: SessionFactory,
    active_session: ?*ActiveContextSession,
    children: [CancellationIntents.capacity]?*ChildNode = [_]?*ChildNode{null} ** CancellationIntents.capacity,
    retiring: [max_retiring_sessions]?RetiringSession = [_]?RetiringSession{null} ** max_retiring_sessions,
    detached_completions: [detached_completion_capacity]?DetachedCompletion =
        [_]?DetachedCompletion{null} ** detached_completion_capacity,
    detached_completion_count: usize = 0,
    latest_switch_id: SwitchId = 0,
    shutting_down: bool = false,
    runtime_failed: bool = false,
    live_children: std.atomic.Value(usize) = .init(0),
    delivery_ready_count: std.atomic.Value(usize) = .init(0),
    task_specs_destroyed: std.atomic.Value(usize) = .init(0),
    metrics: Metrics = .{},
    root_future: ?std.Io.Future(void) = null,

    pub fn liveChildren(self: *const LifecycleSupervisor) usize {
        return self.live_children.load(.acquire);
    }

    pub fn deliveryReadyCount(self: *const LifecycleSupervisor) usize {
        return self.delivery_ready_count.load(.acquire);
    }

    pub fn taskSpecsDestroyed(self: *const LifecycleSupervisor) usize {
        return self.task_specs_destroyed.load(.acquire);
    }

    pub fn detachedCompletionCount(self: *const LifecycleSupervisor) usize {
        return self.detached_completion_count;
    }

    pub fn retiringLeaseCount(self: *const LifecycleSupervisor) usize {
        var count: usize = 0;
        for (self.retiring) |entry| {
            if (entry) |retiring| count +|= retiring.session.leaseCount();
        }
        return count;
    }

    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        shared_event: *std.Io.Event,
        inbox: *LifecycleInbox,
        cancellations: *CancellationIntents,
        active_slot: *ActiveSessionSlot,
        change_queue: *ChangeQueue,
        session_factory: SessionFactory,
        initial_session: ?*ActiveContextSession,
    ) !LifecycleSupervisor {
        if (inbox.shared_event != shared_event or
            active_slot.shared_event != shared_event or
            change_queue.shared_event != shared_event)
        {
            return error.SharedEventMismatch;
        }
        if (initial_session) |session| {
            const view = active_slot.view();
            if (session.shared_event != shared_event or
                view.state != .active or
                view.generation != session.generation)
            {
                return error.InitialSessionOwnershipMismatch;
            }
        } else {
            const view = active_slot.view();
            if (view.state == .active) return error.InitialSessionRequired;
        }
        return .{
            .allocator = allocator,
            .io = io,
            .shared_event = shared_event,
            .inbox = inbox,
            .cancellations = cancellations,
            .active_slot = active_slot,
            .change_queue = change_queue,
            .session_factory = session_factory,
            .active_session = initial_session,
        };
    }

    pub fn startRoot(self: *LifecycleSupervisor) !void {
        if (self.root_future != null) return;
        self.root_future = try std.Io.concurrent(self.io, runRoot, .{self});
    }

    pub fn awaitRoot(self: *LifecycleSupervisor) bool {
        if (self.root_future == null) return false;
        self.root_future.?.await(self.io);
        self.root_future = null;
        return true;
    }

    pub fn runRoot(self: *LifecycleSupervisor) void {
        self.run() catch |err| self.failRuntime(err);
        self.shutdownToCompletion();
        self.destroyUndeliverable();
        self.change_queue.close();
        self.inbox.markRootTerminated();
    }

    fn run(self: *LifecycleSupervisor) !void {
        while (!self.shutting_down) {
            self.shared_event.reset();
            try self.drainCommands();
            self.scanDeliveries();
            self.scanCancellationIntents();
            self.scanReturning();
            self.advanceRetirement();
            self.retryPending();
            self.retryDetachedCompletions();
            if (self.shutting_down) break;
            if (self.shared_event.isSet()) continue;
            try self.shared_event.wait(self.io);
        }
    }

    fn shutdownToCompletion(self: *LifecycleSupervisor) void {
        self.shutting_down = true;
        self.inbox.closeNormal();
        if (self.active_slot.invalidate(null) catch null) |session| {
            self.active_session = null;
            self.beginRetirement(session) catch self.failRuntime(error.RetirementCapacity);
        }
        self.requestAllCancellations();

        while (self.liveChildren() != 0 or
            self.retirementCount() != 0 or
            self.detached_completion_count != 0)
        {
            self.shared_event.reset();
            self.drainCommands() catch {};
            self.scanDeliveries();
            self.scanCancellationIntents();
            self.scanReturning();
            self.advanceRetirement();
            self.retryPending();
            self.retryDetachedCompletions();
            self.requestAllCancellations();
            if (self.liveChildren() == 0 and
                self.retirementCount() == 0 and
                self.detached_completion_count == 0) break;
            if (self.shared_event.isSet()) continue;
            self.shared_event.waitUncancelable(self.io);
        }
    }

    fn drainCommands(self: *LifecycleSupervisor) !void {
        while (self.inbox.tryPop()) |value| {
            var command = value;
            switch (command) {
                .prepare_context => |*prepare| {
                    const owned = prepare.*;
                    command = .shutdown;
                    try self.startPreparation(owned.switch_id, owned.spec);
                },
                .start_subscription => |*start| {
                    const owned = start.*;
                    command = .shutdown;
                    self.startTask(
                        owned.child_key,
                        owned.expected_generation,
                        .resource_subscription,
                        owned.spec,
                        .{ .subscription_stopped = .{ .key = owned.key, .detail = null } },
                        null,
                    );
                },
                .start_request => |*start| {
                    const owned = start.*;
                    command = .shutdown;
                    if (owned.expected_generation != owned.key.generation) {
                        var spec = owned.spec;
                        spec.deinit(self.allocator);
                        self.rejectStart(owned.child_key, owned.key, .stale_generation);
                        continue;
                    }
                    self.startTask(
                        owned.child_key,
                        owned.expected_generation,
                        .command_request,
                        owned.spec,
                        .{ .request_finished = .{ .key = owned.key } },
                        owned.key,
                    );
                },
                .retire => |generation| self.retireGeneration(generation),
                .shutdown => self.shutting_down = true,
            }
            command.deinit(self.allocator);
        }
    }

    fn startTask(
        self: *LifecycleSupervisor,
        key: ChildKey,
        expected_generation: Generation,
        kind: inbox_mod.ChildKind,
        spec_value: OwnedTaskSpec,
        completion: LifecycleCompletion,
        request_key: ?keys.RequestKey,
    ) void {
        var spec = spec_value;
        if (self.shutting_down) {
            spec.deinit(self.allocator);
            self.rejectStart(key, request_key, .shutting_down);
            return;
        }
        const view = self.active_slot.view();
        if (view.state != .active or view.generation != expected_generation) {
            spec.deinit(self.allocator);
            self.rejectStart(key, request_key, .stale_generation);
            return;
        }
        if (key.slot >= CancellationIntents.capacity or self.children[key.slot] != null) {
            spec.deinit(self.allocator);
            self.rejectStart(key, request_key, .capacity);
            return;
        }

        const lease_purpose: session_mod.LeasePurpose = spec.lease_purpose orelse switch (kind) {
            .resource_subscription => .list_watch,
            .command_request => .command,
            else => unreachable,
        };
        const lease = self.active_slot.acquire(expected_generation, lease_purpose) catch {
            spec.deinit(self.allocator);
            self.rejectStart(key, request_key, .stale_generation);
            return;
        } orelse {
            spec.deinit(self.allocator);
            self.rejectStart(key, request_key, .stale_generation);
            return;
        };

        const node = self.allocator.create(ChildNode) catch {
            var owned_lease = lease;
            owned_lease.release();
            spec.deinit(self.allocator);
            self.rejectStart(key, request_key, .capacity);
            return;
        };
        node.* = .{
            .control = .{
                .key = key,
                .kind = kind,
                .spec = spec,
                .lease = lease,
                .io = self.io,
                .shared_event = self.shared_event,
                .allocator = self.allocator,
                .delivery_ready_count = &self.delivery_ready_count,
            },
            .work = .{ .task = .{ .completion = completion } },
            .expected_generation = expected_generation,
        };
        self.installAndLaunch(node, taskMain) catch |err| {
            self.cleanupUnlaunched(node);
            self.failRuntime(err);
        };
    }

    fn startPreparation(
        self: *LifecycleSupervisor,
        switch_id: SwitchId,
        spec_value: session_mod.OwnedContextSpec,
    ) !void {
        var spec = spec_value;
        if (self.shutting_down or switch_id <= self.latest_switch_id) {
            spec.deinit(self.allocator);
            return;
        }
        self.latest_switch_id = switch_id;
        self.cancelSupersededPreparations(switch_id);
        const key = self.cancellations.reserve() catch {
            spec.deinit(self.allocator);
            return error.ChildCapacity;
        };
        if (!self.cancellations.markAccepted(key)) {
            _ = self.cancellations.free(key);
            spec.deinit(self.allocator);
            return error.CancellationState;
        }
        const generation = try self.active_slot.reserveGeneration();
        const node = self.allocator.create(ChildNode) catch {
            _ = self.cancellations.free(key);
            spec.deinit(self.allocator);
            return error.OutOfMemory;
        };
        node.* = .{
            .control = .{
                .key = key,
                .kind = .context_preparation,
                .io = self.io,
                .shared_event = self.shared_event,
                .allocator = self.allocator,
                .delivery_ready_count = &self.delivery_ready_count,
            },
            .work = .{ .preparation = .{
                .switch_id = switch_id,
                .generation = generation,
                .spec = spec,
            } },
            .expected_generation = generation,
        };
        self.installAndLaunch(node, preparationMain) catch |err| {
            self.cleanupUnlaunched(node);
            return err;
        };
    }

    fn installAndLaunch(
        self: *LifecycleSupervisor,
        node: *ChildNode,
        comptime function: fn (*LifecycleSupervisor, *ChildNode) ChildResult,
    ) !void {
        const key = node.control.key;
        self.children[key.slot] = node;
        const live_children = self.live_children.fetchAdd(1, .acq_rel) + 1;
        self.metrics.launched += 1;
        self.metrics.max_live = @max(self.metrics.max_live, live_children);
        node.future = std.Io.concurrent(self.io, function, .{ self, node }) catch |err| {
            self.children[key.slot] = null;
            _ = self.live_children.fetchSub(1, .acq_rel);
            return err;
        };
        if (!self.cancellations.markLive(key)) {
            self.markNodeCanceled(node);
            self.awaitCanceledNode(node);
        }
    }

    fn taskMain(self: *LifecycleSupervisor, node: *ChildNode) ChildResult {
        node.entered.store(true, .release);
        const result = node.control.spec.runFn(
            node.control.spec.ptr,
            &node.control,
            node.control.io,
        );
        node.control.spec.deinit(node.control.allocator);
        _ = self.task_specs_destroyed.fetchAdd(1, .acq_rel);
        if (node.control.lease) |*lease| lease.release();
        node.control.lease = null;
        if (node.control.phase.load(.acquire) != .returning) {
            if (node.control.outcome == .none) {
                const completion = switch (node.work) {
                    .task => |task| task.completion,
                    else => unreachable,
                };
                node.control.finish(completion);
            } else {
                node.control.phase.store(.returning, .release);
                node.control.shared_event.set(node.control.io);
            }
        }
        return result;
    }

    fn preparationMain(self: *LifecycleSupervisor, node: *ChildNode) ChildResult {
        node.entered.store(true, .release);
        var preparation = switch (node.work) {
            .preparation => |value| value,
            else => unreachable,
        };
        node.work = .{ .task = .{ .completion = .{ .context_canceled = preparation.switch_id } } };
        const session = self.session_factory.prepare(
            self.allocator,
            self.io,
            self.shared_event,
            preparation.generation,
            preparation.spec.value,
        ) catch |err| {
            preparation.spec.deinit(self.allocator);
            node.control.outcome = .{ .candidate_failed = errorDetail(err) };
            node.control.phase.store(.returning, .release);
            node.control.shared_event.set(node.control.io);
            return if (err == error.Canceled) error.Canceled else {};
        };
        preparation.spec.deinit(self.allocator);
        session.ensureReady() catch |err| {
            session.deinit();
            node.control.outcome = .{ .candidate_failed = errorDetail(err) };
            node.control.phase.store(.returning, .release);
            node.control.shared_event.set(node.control.io);
            return if (err == error.Canceled) error.Canceled else {};
        };
        node.control.finishCandidate(session);
    }

    fn scanDeliveries(self: *LifecycleSupervisor) void {
        for (self.children) |node_optional| {
            const node = node_optional orelse continue;
            if (node.control.phase.load(.acquire) == .delivery_ready) {
                if (node.control.observed_queue_space_epoch) |observed| {
                    if (observed == self.change_queue.spaceEpoch()) continue;
                }
                self.forwardDelivery(node, false);
            }
        }
    }

    fn forwardDelivery(self: *LifecycleSupervisor, node: *ChildNode, abandon: bool) void {
        var envelope = switch (node.control.outcome) {
            .delivery => |value| value,
            else => return,
        };
        node.control.outcome = .none;
        var outcome: inbox_mod.DeliveryOutcome = .accepted;
        if (abandon) {
            envelope.deinit(self.allocator);
            outcome = .abandoned;
        } else {
            self.change_queue.tryPush(envelope) catch |err| switch (err) {
                error.Full => {
                    node.control.outcome = .{ .delivery = envelope };
                    node.control.observed_queue_space_epoch = self.change_queue.spaceEpoch();
                    return;
                },
                error.Closed => {
                    envelope.deinit(self.allocator);
                    outcome = .abandoned;
                },
            };
        }
        _ = self.delivery_ready_count.fetchSub(1, .acq_rel);
        node.control.observed_queue_space_epoch = null;
        node.control.delivery_outcome.store(outcome, .release);
        node.control.phase.store(.running, .release);
        node.control.delivery_ack.set(self.io);
    }

    fn scanCancellationIntents(self: *LifecycleSupervisor) void {
        var slot: usize = 0;
        while (slot < self.children.len) : (slot += 1) {
            const node = self.children[slot] orelse continue;
            if (self.cancellations.claimRequested(node.control.key) == .none) continue;
            self.markNodeCanceled(node);
        }
        slot = 0;
        while (slot < self.children.len) : (slot += 1) {
            const node = self.children[slot] orelse continue;
            if (!node.canceled or node.future == null) continue;
            self.awaitCanceledNode(node);
        }
    }

    fn markNodeCanceled(self: *LifecycleSupervisor, node: *ChildNode) void {
        node.canceled = true;
        node.control.cancel_requested.store(true, .release);
        if (node.control.phase.load(.acquire) == .delivery_ready or
            node.control.outcome == .delivery)
        {
            self.forwardDelivery(node, true);
        }
        node.control.delivery_outcome.store(.abandoned, .release);
        node.control.delivery_ack.set(self.io);
    }

    fn awaitCanceledNode(self: *LifecycleSupervisor, node: *ChildNode) void {
        if (node.control.phase.load(.acquire) != .returning) {
            node.future.?.cancel(self.io) catch {};
        }
        node.future.?.await(self.io) catch {};
        node.future = null;
        self.cleanupCanceledBeforeEntry(node);
        self.metrics.canceled += 1;
        self.finishReaped(node);
    }

    fn cancelNode(self: *LifecycleSupervisor, node: *ChildNode) void {
        if (node.future == null) return;
        self.markNodeCanceled(node);
        self.awaitCanceledNode(node);
    }

    fn scanReturning(self: *LifecycleSupervisor) void {
        var slot: usize = 0;
        while (slot < self.children.len) : (slot += 1) {
            const node = self.children[slot] orelse continue;
            if (node.future == null) continue;
            if (node.control.phase.load(.acquire) != .returning) continue;
            node.future.?.await(self.io) catch {};
            node.future = null;
            self.finishReaped(node);
        }
    }

    fn finishReaped(self: *LifecycleSupervisor, node: *ChildNode) void {
        node.control.phase.store(.reaped, .release);
        self.metrics.reaped += 1;
        switch (node.work) {
            .preparation => unreachable,
            .task => {},
        }
        switch (node.control.outcome) {
            .candidate_ready => |session| {
                node.control.outcome = .none;
                self.handleCandidate(node, session);
            },
            .candidate_failed => |detail| {
                node.control.outcome = .none;
                const switch_id = preparationSwitchId(node);
                if (!node.canceled and switch_id == self.latest_switch_id) {
                    self.queueCompletion(node, .{ .context_failed = .{
                        .switch_id = switch_id,
                        .detail = detail,
                    } });
                } else {
                    self.queueCompletion(node, .{ .context_canceled = switch_id });
                }
            },
            .completed => |completion| {
                node.control.outcome = .none;
                self.queueCompletion(node, completion);
            },
            .delivery => {
                self.forwardDelivery(node, true);
                self.freeNode(node);
            },
            .none => switch (node.work) {
                .task => |task| self.queueCompletion(node, task.completion),
                .preparation => unreachable,
            },
        }
    }

    fn handleCandidate(
        self: *LifecycleSupervisor,
        node: *ChildNode,
        candidate: *ActiveContextSession,
    ) void {
        const switch_id = preparationSwitchId(node);
        if (node.canceled or switch_id != self.latest_switch_id or self.shutting_down) {
            candidate.deinit();
            self.freeNode(node);
            return;
        }
        const previous = self.active_slot.replaceAndRetire(candidate) catch |err| {
            candidate.deinit();
            self.queueCompletion(node, .{ .context_failed = .{
                .switch_id = switch_id,
                .detail = errorDetail(err),
            } });
            return;
        };
        self.active_session = candidate;
        if (previous) |old| self.beginRetirement(old) catch self.failRuntime(error.RetirementCapacity);
        self.queueCompletion(node, .{ .context_committed = .{
            .switch_id = switch_id,
            .generation = candidate.generation,
        } });
    }

    fn queueCompletion(
        self: *LifecycleSupervisor,
        node: *ChildNode,
        completion: LifecycleCompletion,
    ) void {
        var envelope = completionEnvelope(self.allocator, completion) catch {
            var owned = completion;
            owned.deinit(self.allocator);
            self.freeNode(node);
            self.failRuntime(error.OutOfMemory);
            return;
        };
        const critical = completion == .lifecycle_failed;
        const pushed = if (critical)
            self.change_queue.tryPushCritical(envelope)
        else
            self.change_queue.tryPushControl(envelope);
        pushed catch |err| switch (err) {
            error.Full => {
                node.pending = envelope;
                node.pending_critical = critical;
                node.control.observed_queue_space_epoch = self.change_queue.spaceEpoch();
                return;
            },
            error.Closed => envelope.deinit(self.allocator),
        };
        self.freeNode(node);
    }

    fn retryPending(self: *LifecycleSupervisor) void {
        for (self.children) |node_optional| {
            const node = node_optional orelse continue;
            var envelope = node.pending orelse continue;
            const epoch = self.change_queue.spaceEpoch();
            if (node.control.observed_queue_space_epoch == epoch) continue;
            const pushed = if (node.pending_critical)
                self.change_queue.tryPushCritical(envelope)
            else
                self.change_queue.tryPushControl(envelope);
            pushed catch |err| switch (err) {
                error.Full => {
                    node.control.observed_queue_space_epoch = epoch;
                    continue;
                },
                error.Closed => envelope.deinit(self.allocator),
            };
            node.pending = null;
            node.pending_critical = false;
            self.freeNode(node);
        }
    }

    fn retireGeneration(self: *LifecycleSupervisor, generation: Generation) void {
        const session = self.active_slot.invalidate(generation) catch return orelse return;
        self.active_session = null;
        self.beginRetirement(session) catch self.failRuntime(error.RetirementCapacity);
    }

    fn beginRetirement(self: *LifecycleSupervisor, session: *ActiveContextSession) !void {
        session.invalidate();
        self.requestGenerationCancellations(session.generation);
        for (&self.retiring) |*entry| {
            if (entry.* != null) continue;
            entry.* = .{
                .session = session,
                .generation = session.generation,
                .observed_lease_epoch = session.leaseEpoch(),
            };
            self.shared_event.set(self.io);
            return;
        }
        return error.Capacity;
    }

    fn advanceRetirement(self: *LifecycleSupervisor) void {
        for (&self.retiring) |*entry| {
            var retiring = entry.* orelse continue;
            self.requestGenerationCancellations(retiring.generation);
            if (self.hasGenerationChildren(retiring.generation)) continue;
            if (retiring.session.leaseCount() == 0) {
                retiring.session.deinit();
                entry.* = null;
                continue;
            }
            const epoch = retiring.session.leaseEpoch();
            if (epoch != retiring.observed_lease_epoch) {
                retiring.observed_lease_epoch = epoch;
                retiring.stalled_reported = false;
                entry.* = retiring;
                continue;
            }
            if (!retiring.stalled_reported) {
                retiring.stalled_reported = true;
                entry.* = retiring;
                self.queueDetachedCompletion(.{ .lifecycle_stalled = .{
                    .generation = retiring.generation,
                    .lease_count = retiring.session.leaseCount(),
                } }, null);
            }
        }
    }

    fn requestGenerationCancellations(self: *LifecycleSupervisor, generation: Generation) void {
        for (self.children) |node_optional| {
            const node = node_optional orelse continue;
            if (node.expected_generation != generation) continue;
            _ = self.cancellations.request(node.control.key);
        }
    }

    fn requestAllCancellations(self: *LifecycleSupervisor) void {
        for (self.children) |node_optional| {
            const node = node_optional orelse continue;
            _ = self.cancellations.request(node.control.key);
        }
    }

    fn cancelSupersededPreparations(self: *LifecycleSupervisor, latest: SwitchId) void {
        for (self.children) |node_optional| {
            const node = node_optional orelse continue;
            if (node.control.kind != .context_preparation) continue;
            if (preparationSwitchId(node) >= latest) continue;
            _ = self.cancellations.request(node.control.key);
        }
    }

    fn hasGenerationChildren(self: *LifecycleSupervisor, generation: Generation) bool {
        for (self.children) |node_optional| {
            const node = node_optional orelse continue;
            if (node.expected_generation == generation) return true;
        }
        return false;
    }

    fn rejectStart(
        self: *LifecycleSupervisor,
        key: ChildKey,
        request_key: ?keys.RequestKey,
        code: @FieldType(@FieldType(LifecycleCompletion, "start_rejected"), "code"),
    ) void {
        self.queueDetachedCompletion(.{ .start_rejected = .{
            .child_key = key,
            .request_key = request_key,
            .code = code,
        } }, key);
    }

    fn queueDetachedCompletion(
        self: *LifecycleSupervisor,
        completion: LifecycleCompletion,
        release_key: ?ChildKey,
    ) void {
        var envelope = completionEnvelope(self.allocator, completion) catch {
            var owned = completion;
            owned.deinit(self.allocator);
            if (release_key) |key| _ = self.cancellations.free(key);
            self.failRuntime(error.OutOfMemory);
            return;
        };
        const critical = completion == .lifecycle_failed;
        const result = if (critical)
            self.change_queue.tryPushCritical(envelope)
        else
            self.change_queue.tryPushControl(envelope);
        result catch |err| switch (err) {
            error.Full => {
                for (&self.detached_completions) |*slot| {
                    if (slot.* != null) continue;
                    slot.* = .{
                        .envelope = envelope,
                        .release_key = release_key,
                        .observed_queue_space_epoch = self.change_queue.spaceEpoch(),
                        .critical = critical,
                    };
                    self.detached_completion_count += 1;
                    return;
                }
                envelope.deinit(self.allocator);
                if (release_key) |key| _ = self.cancellations.free(key);
                std.debug.panic("detached lifecycle completion capacity exhausted", .{});
            },
            error.Closed => {
                envelope.deinit(self.allocator);
                if (release_key) |key| _ = self.cancellations.free(key);
                return;
            },
        };
        if (release_key) |key| _ = self.cancellations.free(key);
    }

    fn retryDetachedCompletions(self: *LifecycleSupervisor) void {
        const epoch = self.change_queue.spaceEpoch();
        for (&self.detached_completions) |*slot| {
            var pending = slot.* orelse continue;
            if (pending.observed_queue_space_epoch == epoch) continue;
            const result = if (pending.critical)
                self.change_queue.tryPushCritical(pending.envelope)
            else
                self.change_queue.tryPushControl(pending.envelope);
            result catch |err| switch (err) {
                error.Full => {
                    pending.observed_queue_space_epoch = epoch;
                    slot.* = pending;
                    continue;
                },
                error.Closed => pending.envelope.deinit(self.allocator),
            };
            if (pending.release_key) |key| _ = self.cancellations.free(key);
            slot.* = null;
            self.detached_completion_count -= 1;
        }
    }

    fn cleanupUnlaunched(self: *LifecycleSupervisor, node: *ChildNode) void {
        if (node.control.lease) |*lease| lease.release();
        node.control.spec.deinit(self.allocator);
        switch (node.work) {
            .preparation => |*preparation| preparation.spec.deinit(self.allocator),
            .task => {},
        }
        _ = self.cancellations.free(node.control.key);
        self.allocator.destroy(node);
    }

    fn cleanupCanceledBeforeEntry(self: *LifecycleSupervisor, node: *ChildNode) void {
        if (node.entered.load(.acquire)) return;
        if (node.control.lease) |*lease| lease.release();
        node.control.lease = null;
        node.control.spec.deinit(self.allocator);
        _ = self.task_specs_destroyed.fetchAdd(1, .acq_rel);
        switch (node.work) {
            .preparation => |*preparation| {
                const switch_id = preparation.switch_id;
                preparation.spec.deinit(self.allocator);
                node.work = .{ .task = .{ .completion = .{ .context_canceled = switch_id } } };
            },
            .task => {},
        }
    }

    fn freeNode(self: *LifecycleSupervisor, node: *ChildNode) void {
        const key = node.control.key;
        if (node.pending) |*envelope| envelope.deinit(self.allocator);
        node.control.outcome.deinitNonCandidate(self.allocator);
        _ = self.cancellations.free(key);
        self.children[key.slot] = null;
        _ = self.live_children.fetchSub(1, .acq_rel);
        self.allocator.destroy(node);
    }

    fn destroyUndeliverable(self: *LifecycleSupervisor) void {
        for (self.children) |node_optional| {
            const node = node_optional orelse continue;
            if (node.pending) |*envelope| envelope.deinit(self.allocator);
            node.pending = null;
            if (node.future == null) self.freeNode(node);
        }
        for (&self.detached_completions) |*slot| {
            var pending = slot.* orelse continue;
            pending.envelope.deinit(self.allocator);
            if (pending.release_key) |key| _ = self.cancellations.free(key);
            slot.* = null;
        }
        self.detached_completion_count = 0;
        while (self.inbox.tryPop()) |value| {
            var command = value;
            command.deinit(self.allocator);
        }
    }

    fn failRuntime(self: *LifecycleSupervisor, err: anyerror) void {
        if (self.runtime_failed) return;
        self.runtime_failed = true;
        self.shutting_down = true;
        self.inbox.closeNormal();
        self.queueDetachedCompletion(.{ .lifecycle_failed = errorDetail(err) }, null);
    }

    fn retirementCount(self: *const LifecycleSupervisor) usize {
        var count: usize = 0;
        for (self.retiring) |entry| if (entry != null) {
            count += 1;
        };
        return count;
    }
};

fn preparationSwitchId(node: *const ChildNode) SwitchId {
    return switch (node.work) {
        .preparation => |preparation| preparation.switch_id,
        .task => |task| switch (task.completion) {
            .context_canceled => |switch_id| switch_id,
            else => 0,
        },
    };
}

fn errorDetail(err: anyerror) ErrorDetail {
    const name = @errorName(err);
    var detail = ErrorDetail{ .code = if (err == error.Canceled) .canceled else .transport };
    detail.len = @intCast(@min(name.len, detail.bytes.len));
    @memcpy(detail.bytes[0..detail.len], name[0..detail.len]);
    return detail;
}

fn completionEnvelope(
    allocator: std.mem.Allocator,
    completion: LifecycleCompletion,
) !Envelope {
    const after_revision: ?keys.Revision = switch (completion) {
        .subscription_stopped, .request_finished => std.math.maxInt(keys.Revision),
        else => null,
    };
    const payload = try allocator.create(LifecycleCompletion);
    payload.* = completion;
    return keys.erasePayload(
        LifecycleCompletion,
        allocator,
        .lifecycle,
        payload,
        &completion_handler,
        0,
        0,
        0,
        @sizeOf(LifecycleCompletion),
        after_revision,
    );
}

fn completionPreflight(
    _: *LifecycleCompletion,
    _: *keys.UiRouter,
    _: std.mem.Allocator,
) anyerror!keys.ApplyPlan {
    return keys.ApplyPlan.empty(0);
}

fn completionCommit(completion: *LifecycleCompletion, router: *keys.UiRouter, _: *keys.ApplyPlan) void {
    const target = router.target(.lifecycle) orelse return;
    const data_plane: *DataPlane = @ptrCast(@alignCast(target));
    const key = data_plane.keyForCompletion(completion.*);
    const handled_resource = data_plane.handleCompletion(completion.*);
    const is_request = switch (completion.*) {
        .request_finished => true,
        .start_rejected => |rejected| rejected.request_key != null,
        else => false,
    };
    if (!handled_resource and !is_request) return;
    const identity: ?keys.ResourceIdentity = if (key) |value| .{
        .generation = value.generation,
        .subscription_id = value.subscription_id,
    } else null;
    router.observeLifecycle(@ptrCast(completion), identity);
}

fn completionDeinit(completion: *LifecycleCompletion, allocator: std.mem.Allocator) void {
    completion.deinit(allocator);
}

const completion_handler = keys.PayloadHandler(LifecycleCompletion){
    .preflight = completionPreflight,
    .commit = completionCommit,
    .deinit = completionDeinit,
};

fn makeTestSession(
    allocator: std.mem.Allocator,
    io: std.Io,
    event: *std.Io.Event,
    generation: Generation,
) !*ActiveContextSession {
    const client = try allocator.create(@import("klient").K8sClient);
    errdefer allocator.destroy(client);
    client.* = try @import("klient").K8sClient.init(allocator, io, .{
        .server = "http://127.0.0.1",
        .namespace = "default",
    });
    errdefer client.deinit();
    return ActiveContextSession.adopt(allocator, io, generation, .{
        .context_name = "test",
        .kubeconfig_path = null,
        .default_namespace = "default",
        .force_proxy = false,
        .readonly = true,
    }, .{
        .shared_event = event,
        .client = client,
        .cluster_name = "cluster",
        .user_name = "user",
        .readiness_verified = true,
    });
}

test "supervisor adopts the exact active generation" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    const session = try makeTestSession(testing.allocator, io, &event, 1);
    _ = try slot.commit(session);
    const supervisor = try LifecycleSupervisor.init(
        testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        SessionFactory.production(),
        session,
    );
    try testing.expect(supervisor.active_session == session);
    const retired = try slot.invalidate(null);
    retired.?.deinit();
}

test "supervisor rejects hidden active session at launch" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    const session = try makeTestSession(testing.allocator, io, &event, 1);
    _ = try slot.commit(session);
    try testing.expectError(
        error.InitialSessionRequired,
        LifecycleSupervisor.init(
            testing.allocator,
            io,
            &event,
            &inbox,
            &cancellations,
            &slot,
            &queue,
            SessionFactory.production(),
            null,
        ),
    );
    const retired = try slot.invalidate(null);
    retired.?.deinit();
}

test "atomic replacement retires a leased session without blocking the new generation" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();

    const first = try makeTestSession(testing.allocator, io, &event, 1);
    _ = try slot.commit(first);
    var old_lease = (try slot.acquire(1, .command)).?;

    const second = try makeTestSession(testing.allocator, io, &event, 2);
    const retired = (try slot.replaceAndRetire(second)).?;
    try testing.expect(retired == first);
    try testing.expectEqual(session_mod.SessionState.invalidated, retired.logicalState());
    try testing.expectEqual(@as(usize, 1), retired.leaseCount());

    var new_lease = (try slot.acquire(2, .command)).?;
    new_lease.release();
    old_lease.release();
    try retired.checkTeardownReady();
    retired.deinit();

    const active = (try slot.invalidate(2)).?;
    active.deinit();
}

test "retirement waits for a held lease and resumes on release" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    const session = try makeTestSession(testing.allocator, io, &event, 1);
    _ = try slot.commit(session);
    var lease = (try slot.acquire(1, .command)).?;
    var supervisor = try LifecycleSupervisor.init(
        testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        SessionFactory.production(),
        session,
    );

    supervisor.retireGeneration(1);
    supervisor.advanceRetirement();
    try testing.expectEqual(@as(usize, 1), supervisor.retirementCount());
    try testing.expectEqual(session_mod.SessionState.invalidated, session.logicalState());

    event.reset();
    lease.release();
    try testing.expect(event.isSet());
    supervisor.advanceRetirement();
    try testing.expectEqual(@as(usize, 0), supervisor.retirementCount());
}

test "delivery acknowledgement distinguishes accepted and abandoned envelopes" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    var supervisor = try LifecycleSupervisor.init(
        testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        SessionFactory.production(),
        null,
    );
    var node = ChildNode{
        .control = .{
            .key = .{ .slot = 0, .generation = 1 },
            .kind = .resource_subscription,
            .outcome = .{ .delivery = .{} },
            .io = io,
            .shared_event = &event,
            .allocator = testing.allocator,
        },
        .work = .{ .task = .{ .completion = .shutdown_complete } },
        .expected_generation = 1,
    };

    supervisor.forwardDelivery(&node, false);
    try testing.expectEqual(inbox_mod.DeliveryOutcome.accepted, node.control.delivery_outcome.load(.acquire));
    var accepted = queue.pop() orelse return error.MissingAcceptedDelivery;
    accepted.deinit(testing.allocator);

    node.control.outcome = .{ .delivery = .{} };
    node.control.phase.store(.delivery_ready, .release);
    supervisor.forwardDelivery(&node, true);
    try testing.expectEqual(inbox_mod.DeliveryOutcome.abandoned, node.control.delivery_outcome.load(.acquire));
    try testing.expect(!queue.hasPending());
}

test "saturated ordinary lane retains rejected start and its child identity" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    var supervisor = try LifecycleSupervisor.init(
        testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        SessionFactory.production(),
        null,
    );

    for (0..keys.Limits.default.ordinary_control_batches) |_| {
        try queue.tryPushControl(try completionEnvelope(testing.allocator, .shutdown_complete));
    }
    const child_key = try cancellations.reserve();
    try testing.expect(cancellations.markAccepted(child_key));
    supervisor.rejectStart(
        child_key,
        .{ .generation = 7, .subscription_id = 11 },
        .stale_generation,
    );

    try testing.expectEqual(@as(usize, 1), supervisor.detachedCompletionCount());
    try testing.expect(cancellations.request(child_key));
    supervisor.retryDetachedCompletions();
    try testing.expectEqual(@as(usize, 1), supervisor.detachedCompletionCount());

    var freed_slot = queue.pop() orelse return error.MissingSaturatedControl;
    freed_slot.deinit(testing.allocator);
    supervisor.retryDetachedCompletions();
    try testing.expectEqual(@as(usize, 0), supervisor.detachedCompletionCount());
    try testing.expect(!cancellations.request(child_key));
    try testing.expectEqual(
        keys.Limits.default.ordinary_control_batches,
        queue.snapshot().count,
    );

    while (queue.pop()) |value| {
        var envelope = value;
        envelope.deinit(testing.allocator);
    }
}

test "delivery-ready count remains charged while saturated delivery retries" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    var supervisor = try LifecycleSupervisor.init(
        testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        SessionFactory.production(),
        null,
    );
    for (0..keys.Limits.default.max_data_batches) |_| try queue.tryPush(.{});

    supervisor.delivery_ready_count.store(1, .release);
    var node = ChildNode{
        .control = .{
            .key = .{ .slot = 0, .generation = 1 },
            .kind = .resource_subscription,
            .phase = .init(.delivery_ready),
            .outcome = .{ .delivery = .{} },
            .io = io,
            .shared_event = &event,
            .allocator = testing.allocator,
            .delivery_ready_count = &supervisor.delivery_ready_count,
        },
        .work = .{ .task = .{ .completion = .shutdown_complete } },
        .expected_generation = 1,
    };

    supervisor.forwardDelivery(&node, false);
    try testing.expectEqual(@as(usize, 1), supervisor.deliveryReadyCount());
    try testing.expect(node.control.outcome == .delivery);
    var freed_slot = queue.pop() orelse return error.MissingSaturatedData;
    freed_slot.deinit(testing.allocator);
    supervisor.forwardDelivery(&node, false);
    try testing.expectEqual(@as(usize, 0), supervisor.deliveryReadyCount());
    try testing.expect(node.control.outcome == .none);
    try testing.expectEqual(
        inbox_mod.DeliveryOutcome.accepted,
        node.control.delivery_outcome.load(.acquire),
    );
}

test "saturated publish cannot return abandoned before supervisor releases outcome" {
    const Probe = struct {
        fn publish(
            control: *ChildControl,
            returned: *std.atomic.Value(bool),
            saw_owned_outcome: *std.atomic.Value(bool),
        ) void {
            const outcome = control.publishDelivery(.{}) catch return;
            saw_owned_outcome.store(control.outcome != .none, .release);
            returned.store(outcome == .abandoned, .release);
        }
    };
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    var supervisor = try LifecycleSupervisor.init(
        testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        SessionFactory.production(),
        null,
    );
    for (0..keys.Limits.default.max_data_batches) |_| try queue.tryPush(.{});

    var node = ChildNode{
        .control = .{
            .key = .{ .slot = 0, .generation = 1 },
            .kind = .resource_subscription,
            .io = io,
            .shared_event = &event,
            .allocator = testing.allocator,
            .delivery_ready_count = &supervisor.delivery_ready_count,
        },
        .work = .{ .task = .{ .completion = .shutdown_complete } },
        .expected_generation = 1,
    };
    var returned: std.atomic.Value(bool) = .init(false);
    var saw_owned_outcome: std.atomic.Value(bool) = .init(false);
    var publisher = try std.Io.concurrent(
        io,
        Probe.publish,
        .{ &node.control, &returned, &saw_owned_outcome },
    );
    while (node.control.phase.load(.acquire) != .delivery_ready)
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);

    supervisor.forwardDelivery(&node, false);
    try testing.expect(node.control.outcome == .delivery);
    supervisor.markNodeCanceled(&node);
    publisher.await(io);

    try testing.expect(returned.load(.acquire));
    try testing.expect(!saw_owned_outcome.load(.acquire));
    try testing.expect(node.control.outcome == .none);
    try testing.expectEqual(@as(usize, 0), supervisor.deliveryReadyCount());
}

test "real supervisor start acquires the task selected metrics lease" {
    const Probe = struct {
        fn run(
            raw: ?*anyopaque,
            control: *ChildControl,
            _: std.Io,
        ) anyerror!void {
            const observed: *std.atomic.Value(u8) = @ptrCast(@alignCast(raw.?));
            const lease = control.lease orelse return error.MissingLease;
            observed.store(@intFromEnum(lease.purpose), .release);
        }
    };
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    const session = try makeTestSession(testing.allocator, io, &event, 1);
    _ = try slot.commit(session);
    var supervisor = try LifecycleSupervisor.init(
        testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        SessionFactory.production(),
        session,
    );
    const child = try cancellations.reserve();
    try testing.expect(cancellations.markAccepted(child));
    var observed: std.atomic.Value(u8) = .init(255);
    supervisor.startTask(
        child,
        1,
        .resource_subscription,
        .{
            .ptr = &observed,
            .lease_purpose = .metrics,
            .runFn = Probe.run,
        },
        .{ .subscription_stopped = .{
            .key = .{ .generation = 1, .subscription_id = 1 },
            .detail = null,
        } },
        null,
    );
    while (supervisor.liveChildren() != 0) {
        event.reset();
        supervisor.scanReturning();
        while (queue.pop()) |value| {
            var envelope = value;
            envelope.deinit(testing.allocator);
        }
        supervisor.retryPending();
        if (supervisor.liveChildren() == 0) break;
        if (!event.isSet()) event.waitUncancelable(io);
    }
    try testing.expectEqual(
        @as(u8, @intFromEnum(session_mod.LeasePurpose.metrics)),
        observed.load(.acquire),
    );
    try testing.expectEqual(@as(usize, 0), session.leaseCount());
    const retired = try slot.invalidate(null);
    retired.?.deinit();
}

test "task kind defaults and explicit command request purposes are preserved" {
    const Probe = struct {
        fn run(
            raw: ?*anyopaque,
            control: *ChildControl,
            _: std.Io,
        ) anyerror!void {
            const observed: *std.atomic.Value(u8) = @ptrCast(@alignCast(raw.?));
            const lease = control.lease orelse return error.MissingLease;
            observed.store(@intFromEnum(lease.purpose), .release);
        }
    };
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    const session = try makeTestSession(testing.allocator, io, &event, 1);
    _ = try slot.commit(session);
    var supervisor = try LifecycleSupervisor.init(
        testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        SessionFactory.production(),
        session,
    );

    var resource_default: std.atomic.Value(u8) = .init(255);
    const resource_child = try cancellations.reserve();
    try testing.expect(cancellations.markAccepted(resource_child));
    supervisor.startTask(
        resource_child,
        1,
        .resource_subscription,
        .{ .ptr = &resource_default, .runFn = Probe.run },
        .{ .subscription_stopped = .{
            .key = .{ .generation = 1, .subscription_id = 1 },
            .detail = null,
        } },
        null,
    );

    var command_default: std.atomic.Value(u8) = .init(255);
    const command_child = try cancellations.reserve();
    try testing.expect(cancellations.markAccepted(command_child));
    const command_key = keys.RequestKey{ .generation = 1, .subscription_id = 2 };
    supervisor.startTask(
        command_child,
        1,
        .command_request,
        .{ .ptr = &command_default, .runFn = Probe.run },
        .{ .request_finished = .{ .key = command_key } },
        command_key,
    );

    var authorization_explicit: std.atomic.Value(u8) = .init(255);
    const authorization_child = try cancellations.reserve();
    try testing.expect(cancellations.markAccepted(authorization_child));
    const authorization_key = keys.RequestKey{ .generation = 1, .subscription_id = 3 };
    supervisor.startTask(
        authorization_child,
        1,
        .command_request,
        .{
            .ptr = &authorization_explicit,
            .lease_purpose = .authorization,
            .runFn = Probe.run,
        },
        .{ .request_finished = .{ .key = authorization_key } },
        authorization_key,
    );

    while (supervisor.liveChildren() != 0) {
        event.reset();
        supervisor.scanReturning();
        while (queue.pop()) |value| {
            var envelope = value;
            envelope.deinit(testing.allocator);
        }
        supervisor.retryPending();
        if (supervisor.liveChildren() == 0) break;
        if (!event.isSet()) event.waitUncancelable(io);
    }
    try testing.expectEqual(
        @as(u8, @intFromEnum(session_mod.LeasePurpose.list_watch)),
        resource_default.load(.acquire),
    );
    try testing.expectEqual(
        @as(u8, @intFromEnum(session_mod.LeasePurpose.command)),
        command_default.load(.acquire),
    );
    try testing.expectEqual(
        @as(u8, @intFromEnum(session_mod.LeasePurpose.authorization)),
        authorization_explicit.load(.acquire),
    );
    try testing.expectEqual(@as(usize, 0), session.leaseCount());
    const retired = try slot.invalidate(null);
    retired.?.deinit();
}

test "Future cancellation interrupts an outstanding Io operation" {
    const Probe = struct {
        fn run(
            io: std.Io,
            entered: *std.Io.Event,
            interrupted: *std.atomic.Value(bool),
        ) void {
            entered.set(io);
            io.sleep(.{ .nanoseconds = std.time.ns_per_hour }, .awake) catch {
                interrupted.store(true, .release);
            };
        }
    };
    const io = runtime.io();
    var entered: std.Io.Event = .unset;
    var interrupted: std.atomic.Value(bool) = .init(false);
    var future = try std.Io.concurrent(io, Probe.run, .{ io, &entered, &interrupted });
    try entered.wait(io);
    future.cancel(io);
    try testing.expect(interrupted.load(.acquire));
}

test "one hundred thousand short tasks reuse bounded child storage" {
    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = LifecycleInbox.init(io, &event);
    defer inbox.deinit(testing.allocator);
    var cancellations = CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    const session = try makeTestSession(testing.allocator, io, &event, 1);
    _ = try slot.commit(session);
    var supervisor = try LifecycleSupervisor.init(
        testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        SessionFactory.production(),
        session,
    );

    for (0..100_000) |request_id| {
        event.reset();
        const key = try cancellations.reserve();
        try testing.expect(cancellations.markAccepted(key));
        supervisor.startTask(
            key,
            1,
            .command_request,
            inbox_mod.emptyTaskSpec(),
            .{ .start_rejected = .{
                .child_key = key,
                .code = .shutting_down,
            } },
            null,
        );
        while (supervisor.liveChildren() != 0) {
            event.reset();
            supervisor.scanDeliveries();
            supervisor.scanCancellationIntents();
            supervisor.scanReturning();
            while (queue.pop()) |value| {
                var envelope = value;
                envelope.deinit(testing.allocator);
            }
            supervisor.retryPending();
            if (supervisor.liveChildren() == 0) break;
            if (event.isSet()) continue;
            event.waitUncancelable(io);
        }
        try testing.expectEqual(@as(usize, request_id + 1), supervisor.metrics.reaped);
    }
    try testing.expectEqual(@as(usize, 1), supervisor.metrics.max_live);
    try testing.expectEqual(@as(usize, 0), supervisor.liveChildren());
    const retired = try slot.invalidate(null);
    retired.?.deinit();
}

test "source audit keeps child futures inside the supervisor" {
    const files = [_][]const u8{
        "src/k8s/LifecycleInbox.zig",
        "src/k8s/LifecycleSupervisor.zig",
        "src/App.zig",
    };
    const forbidden = [_][]const u8{
        "std.Io." ++ "Group",
        "Completion" ++ "Sink",
        "Candidate" ++ "Sink",
        "reaper_" ++ "scheduled",
        "std." ++ "Thread",
    };
    for (files) |path| {
        const source = try std.Io.Dir.cwd().readFileAlloc(
            testing.io,
            path,
            testing.allocator,
            .limited(2 * 1024 * 1024),
        );
        defer testing.allocator.free(source);
        for (forbidden) |needle| try testing.expect(std.mem.indexOf(u8, source, needle) == null);
        if (!std.mem.endsWith(u8, path, "LifecycleSupervisor.zig") and
            !std.mem.endsWith(u8, path, "App.zig"))
        {
            try testing.expect(std.mem.indexOf(u8, source, "Future") == null);
        }
    }
}
