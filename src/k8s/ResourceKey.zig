const std = @import("std");
const testing = std.testing;

pub const Generation = u64;
pub const SubscriptionId = u32;
pub const Revision = u64;

pub const OwnedBytes = struct {
    bytes: []u8 = &.{},

    pub fn clone(allocator: std.mem.Allocator, source: []const u8) !OwnedBytes {
        if (source.len == 0) return .{};
        return .{ .bytes = try allocator.dupe(u8, source) };
    }

    pub fn deinit(self: *OwnedBytes, allocator: std.mem.Allocator) void {
        if (self.bytes.len > 0) allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

pub const ObjectKey = struct {
    uid: []const u8,
    namespace: []const u8,
    name: []const u8,

    pub fn eql(self: ObjectKey, other: ObjectKey) bool {
        return std.mem.eql(u8, self.uid, other.uid);
    }

    pub fn clone(self: ObjectKey, allocator: std.mem.Allocator) !ObjectKey {
        const uid = try allocator.dupe(u8, self.uid);
        errdefer allocator.free(uid);
        const namespace = try allocator.dupe(u8, self.namespace);
        errdefer allocator.free(namespace);
        const name = try allocator.dupe(u8, self.name);
        return .{ .uid = uid, .namespace = namespace, .name = name };
    }

    pub fn deinit(self: *ObjectKey, allocator: std.mem.Allocator) void {
        allocator.free(self.uid);
        allocator.free(self.namespace);
        allocator.free(self.name);
        self.* = undefined;
    }
};

pub const ChangeKind = enum {
    initial_upsert,
    watch_upsert,
    delete,
    metrics,
};

pub const PodMetricsRecord = struct {
    uid: []const u8 = &.{},
    cpu_milli: u64 = 0,
    mem_bytes: u64 = 0,
    revision: Revision = 0,

    pub fn deinit(self: *PodMetricsRecord, allocator: std.mem.Allocator) void {
        if (self.uid.len > 0) allocator.free(self.uid);
        self.uid = &.{};
    }
};

pub const SyncBoundary = union(enum) {
    list_started,
    list_complete: struct {
        resource_version: OwnedBytes,
        object_count: usize,
    },
    watch_connected,
    metrics_ready,
    reconnecting,

    pub fn deinit(self: *SyncBoundary, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .list_complete => |*complete| complete.resource_version.deinit(allocator),
            else => {},
        }
    }
};

pub fn TypedChange(comptime Record: type) type {
    return union(ChangeKind) {
        initial_upsert: ?Record,
        watch_upsert: ?Record,
        delete: ObjectKey,
        metrics: PodMetricsRecord,

        pub fn takeRecord(self: *@This()) ?Record {
            switch (self.*) {
                .initial_upsert => |value| {
                    self.* = .{ .initial_upsert = null };
                    return value;
                },
                .watch_upsert => |value| {
                    self.* = .{ .watch_upsert = null };
                    return value;
                },
                else => return null,
            }
        }

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            switch (self.*) {
                .initial_upsert => |*value| if (value.*) |*record| deinitRecord(Record, record, allocator),
                .watch_upsert => |*value| if (value.*) |*record| deinitRecord(Record, record, allocator),
                .delete => |*key| key.deinit(allocator),
                .metrics => |*metrics| metrics.deinit(allocator),
            }
        }
    };
}

fn deinitRecord(comptime Record: type, record: *Record, allocator: std.mem.Allocator) void {
    if (@hasDecl(Record, "deinit")) record.deinit(allocator);
}

pub fn TypedBatch(comptime Record: type) type {
    return struct {
        generation: Generation,
        subscription_id: SubscriptionId,
        revision: Revision,
        changes: []TypedChange(Record),
        sync: ?SyncBoundary,
        owned_bytes: usize,

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            for (self.changes) |*change| change.deinit(allocator);
            if (self.changes.len > 0) allocator.free(self.changes);
            if (self.sync) |*sync| sync.deinit(allocator);
            self.changes = &.{};
            self.sync = null;
        }
    };
}

pub const EnvelopeTarget = union(enum) {
    resource: struct { generation: Generation, subscription_id: SubscriptionId },
    lifecycle,
    header_metrics,
    traffic,
    detail,
    yaml,
    logs,
    authorization,
};

pub const ApplyPlan = struct {
    scratch: ?*anyopaque = null,
    scratch_alignment: std.mem.Alignment = .@"1",
    revision: Revision = 0,
    deinitFn: *const fn (?*anyopaque, std.mem.Alignment, std.mem.Allocator) void = noopPlanDeinit,

    pub fn empty(revision: Revision) ApplyPlan {
        return .{ .revision = revision };
    }

    pub fn deinit(self: *ApplyPlan, allocator: std.mem.Allocator) void {
        self.deinitFn(self.scratch, self.scratch_alignment, allocator);
        self.scratch = null;
    }
};

fn noopPlanDeinit(_: ?*anyopaque, _: std.mem.Alignment, _: std.mem.Allocator) void {}

pub const UiRouter = struct {
    context: *anyopaque,
    targetFn: *const fn (*anyopaque, EnvelopeTarget) ?*anyopaque,

    pub fn target(self: *UiRouter, route: EnvelopeTarget) ?*anyopaque {
        return self.targetFn(self.context, route);
    }
};

pub fn PayloadHandler(comptime Payload: type) type {
    return struct {
        preflight: *const fn (*Payload, *UiRouter, std.mem.Allocator) anyerror!ApplyPlan,
        commit: *const fn (*Payload, *UiRouter, *ApplyPlan) void,
        deinit: *const fn (*Payload, std.mem.Allocator) void,
    };
}

pub const Envelope = struct {
    generation: Generation = 0,
    subscription_id: SubscriptionId = 0,
    revision: Revision = 0,
    owned_bytes: usize = 0,
    after_revision: ?Revision = null,
    target: EnvelopeTarget = .lifecycle,
    payload: ?*anyopaque = null,
    payload_alignment: std.mem.Alignment = .@"1",
    vtable: *const VTable = &empty_vtable,
    state: State = .queued,

    pub const State = enum { queued, applying, consumed };

    pub const VTable = struct {
        preflightApply: *const fn (*anyopaque, std.mem.Alignment, *UiRouter, std.mem.Allocator) anyerror!ApplyPlan,
        commitApply: *const fn (*anyopaque, std.mem.Alignment, *UiRouter, *ApplyPlan) void,
        destroy: *const fn (*anyopaque, std.mem.Alignment, std.mem.Allocator) void,
    };

    pub fn apply(self: *Envelope, router: *UiRouter, allocator: std.mem.Allocator) !void {
        std.debug.assert(self.state == .queued);
        const payload = self.payload orelse {
            self.state = .consumed;
            return;
        };
        self.state = .applying;
        if (router.target(self.target) == null) {
            self.vtable.destroy(payload, self.payload_alignment, allocator);
            self.payload = null;
            self.state = .consumed;
            return;
        }
        var plan = self.vtable.preflightApply(payload, self.payload_alignment, router, allocator) catch |err| {
            self.state = .queued;
            return err;
        };
        self.vtable.commitApply(payload, self.payload_alignment, router, &plan);
        plan.deinit(allocator);
        self.vtable.destroy(payload, self.payload_alignment, allocator);
        self.payload = null;
        self.state = .consumed;
    }

    pub fn deinit(self: *Envelope, allocator: std.mem.Allocator) void {
        switch (self.state) {
            .applying => std.debug.panic("envelope deinit during apply", .{}),
            .consumed => {},
            .queued => {
                if (self.payload) |payload| {
                    self.vtable.destroy(payload, self.payload_alignment, allocator);
                    self.payload = null;
                }
                self.state = .consumed;
            },
        }
    }
};

const empty_vtable = Envelope.VTable{
    .preflightApply = emptyPreflight,
    .commitApply = emptyCommit,
    .destroy = emptyDestroy,
};

fn emptyPreflight(_: *anyopaque, _: std.mem.Alignment, _: *UiRouter, _: std.mem.Allocator) anyerror!ApplyPlan {
    return ApplyPlan.empty(0);
}
fn emptyCommit(_: *anyopaque, _: std.mem.Alignment, _: *UiRouter, _: *ApplyPlan) void {}
fn emptyDestroy(_: *anyopaque, _: std.mem.Alignment, _: std.mem.Allocator) void {}

pub fn BatchHandler(comptime Record: type) type {
    return struct {
        preflight: *const fn (*anyopaque, *TypedBatch(Record), std.mem.Allocator) anyerror!ApplyPlan,
        commit: *const fn (*anyopaque, *TypedBatch(Record), *ApplyPlan) void,
    };
}

fn BatchBox(comptime Record: type) type {
    return struct {
        batch: *TypedBatch(Record),
        handler: *const BatchHandler(Record),
        sink: *anyopaque,
    };
}

pub fn eraseBatch(
    comptime Record: type,
    allocator: std.mem.Allocator,
    batch: *TypedBatch(Record),
    handler: *const BatchHandler(Record),
    sink: *anyopaque,
) !Envelope {
    const Box = BatchBox(Record);
    const box = try allocator.create(Box);
    box.* = .{ .batch = batch, .handler = handler, .sink = sink };
    const after_revision: ?Revision = if (batch.sync) |sync| switch (sync) {
        .list_complete => batch.revision,
        else => null,
    } else null;
    return .{
        .generation = batch.generation,
        .subscription_id = batch.subscription_id,
        .revision = batch.revision,
        .owned_bytes = batch.owned_bytes,
        .after_revision = after_revision,
        .target = .{ .resource = .{
            .generation = batch.generation,
            .subscription_id = batch.subscription_id,
        } },
        .payload = box,
        .payload_alignment = .of(Box),
        .vtable = batchVTable(Record),
        .state = .queued,
    };
}

fn batchVTable(comptime Record: type) *const Envelope.VTable {
    const Box = BatchBox(Record);
    const v = struct {
        fn preflight(
            raw: *anyopaque,
            alignment: std.mem.Alignment,
            router: *UiRouter,
            allocator: std.mem.Allocator,
        ) anyerror!ApplyPlan {
            _ = router;
            std.debug.assert(alignment.check(@intFromPtr(raw)));
            const box: *Box = @ptrCast(@alignCast(raw));
            return box.handler.preflight(box.sink, box.batch, allocator);
        }

        fn commit(
            raw: *anyopaque,
            alignment: std.mem.Alignment,
            router: *UiRouter,
            plan: *ApplyPlan,
        ) void {
            _ = router;
            std.debug.assert(alignment.check(@intFromPtr(raw)));
            const box: *Box = @ptrCast(@alignCast(raw));
            box.handler.commit(box.sink, box.batch, plan);
        }

        fn destroy(
            raw: *anyopaque,
            alignment: std.mem.Alignment,
            allocator: std.mem.Allocator,
        ) void {
            std.debug.assert(alignment.check(@intFromPtr(raw)));
            const box: *Box = @ptrCast(@alignCast(raw));
            box.batch.deinit(allocator);
            allocator.destroy(box.batch);
            allocator.destroy(box);
        }

        const table = Envelope.VTable{
            .preflightApply = preflight,
            .commitApply = commit,
            .destroy = destroy,
        };
    };
    return &v.table;
}

fn PayloadBox(comptime Payload: type) type {
    return struct {
        payload: *Payload,
        handler: *const PayloadHandler(Payload),
    };
}

pub fn erasePayload(
    comptime Payload: type,
    allocator: std.mem.Allocator,
    target: EnvelopeTarget,
    payload: *Payload,
    handler: *const PayloadHandler(Payload),
    generation: Generation,
    subscription_id: SubscriptionId,
    revision: Revision,
    owned_bytes: usize,
    after_revision: ?Revision,
) !Envelope {
    const Box = PayloadBox(Payload);
    const box = try allocator.create(Box);
    box.* = .{ .payload = payload, .handler = handler };
    return .{
        .generation = generation,
        .subscription_id = subscription_id,
        .revision = revision,
        .owned_bytes = owned_bytes,
        .after_revision = after_revision,
        .target = target,
        .payload = box,
        .payload_alignment = .of(Box),
        .vtable = payloadVTable(Payload),
        .state = .queued,
    };
}

fn payloadVTable(comptime Payload: type) *const Envelope.VTable {
    const Box = PayloadBox(Payload);
    const v = struct {
        fn preflight(
            raw: *anyopaque,
            alignment: std.mem.Alignment,
            router: *UiRouter,
            allocator: std.mem.Allocator,
        ) anyerror!ApplyPlan {
            std.debug.assert(alignment.check(@intFromPtr(raw)));
            const box: *Box = @ptrCast(@alignCast(raw));
            return box.handler.preflight(box.payload, router, allocator);
        }

        fn commit(
            raw: *anyopaque,
            alignment: std.mem.Alignment,
            router: *UiRouter,
            plan: *ApplyPlan,
        ) void {
            std.debug.assert(alignment.check(@intFromPtr(raw)));
            const box: *Box = @ptrCast(@alignCast(raw));
            box.handler.commit(box.payload, router, plan);
        }

        fn destroy(
            raw: *anyopaque,
            alignment: std.mem.Alignment,
            allocator: std.mem.Allocator,
        ) void {
            std.debug.assert(alignment.check(@intFromPtr(raw)));
            const box: *Box = @ptrCast(@alignCast(raw));
            box.handler.deinit(box.payload, allocator);
            allocator.destroy(box.payload);
            allocator.destroy(box);
        }

        const table = Envelope.VTable{
            .preflightApply = preflight,
            .commitApply = commit,
            .destroy = destroy,
        };
    };
    return &v.table;
}

pub const Limits = struct {
    max_batches: usize = 64,
    max_queue_bytes: usize = 16 << 20,
    reserved_control_batches: usize = 4,
    reserved_control_bytes: usize = 256 << 10,
    ordinary_control_batches: usize = 3,
    ordinary_control_bytes: usize = 192 << 10,
    critical_control_batches: usize = 1,
    critical_control_bytes: usize = 64 << 10,
    max_control_envelope_bytes: usize = 64 << 10,
    max_child_delivery_bytes: usize = 256 << 10,
    drain_batches: usize = 16,
    max_data_batches: usize = 60,
    max_data_bytes: usize = (15 << 20) + (768 << 10),

    pub const default: Limits = .{};
};

pub const DataError = enum {
    unauthorized,
    forbidden,
    expired,
    throttled,
    server,
    malformed_event,
    decode,
    limit,
    transport,
    canceled,
};

pub const ErrorDetail = struct {
    code: DataError,
    http_status: ?u16 = null,
    retry_after_ns: ?u64 = null,
    len: u16 = 0,
    bytes: [256]u8 = undefined,
};

pub fn deliveryMustSplit(owned_bytes: usize, limits: Limits) bool {
    return owned_bytes > limits.max_child_delivery_bytes;
}

const TestRecord = struct {
    key: ObjectKey,
    value: u32 = 0,

    pub fn deinit(self: *TestRecord, allocator: std.mem.Allocator) void {
        self.key.deinit(allocator);
    }
};

const CountingSink = struct {
    applied: usize = 0,
    last_value: u32 = 0,
};

fn testBatchPreflight(
    _: *anyopaque,
    batch: *TypedBatch(TestRecord),
    _: std.mem.Allocator,
) anyerror!ApplyPlan {
    return ApplyPlan.empty(batch.revision);
}

fn testBatchCommit(raw: *anyopaque, batch: *TypedBatch(TestRecord), _: *ApplyPlan) void {
    const sink: *CountingSink = @ptrCast(@alignCast(raw));
    for (batch.changes) |*change| {
        if (change.takeRecord()) |record| {
            var owned = record;
            sink.last_value = owned.value;
            sink.applied += 1;
            owned.deinit(testing.allocator);
        }
    }
}

const test_batch_handler = BatchHandler(TestRecord){
    .preflight = testBatchPreflight,
    .commit = testBatchCommit,
};

fn nullTarget(_: *anyopaque, _: EnvelopeTarget) ?*anyopaque {
    return null;
}

fn sinkTarget(ctx: *anyopaque, _: EnvelopeTarget) ?*anyopaque {
    return ctx;
}

test "ObjectKey identity is UID, not namespace/name" {
    const a = ObjectKey{ .uid = "uid-1", .namespace = "ns-a", .name = "web" };
    const b = ObjectKey{ .uid = "uid-1", .namespace = "ns-b", .name = "web" };
    const c = ObjectKey{ .uid = "uid-2", .namespace = "ns-a", .name = "web" };
    try testing.expect(a.eql(b));
    try testing.expect(!a.eql(c));
}

test "takeRecord nulls the upsert so destroy skips it" {
    var change: TypedChange(TestRecord) = .{ .initial_upsert = .{
        .key = .{ .uid = "u", .namespace = "n", .name = "x" },
        .value = 7,
    } };
    const taken = change.takeRecord() orelse return error.MissingRecord;
    try testing.expectEqual(@as(u32, 7), taken.value);
    try testing.expect(change.initial_upsert == null);
    change.deinit(testing.allocator);
}

test "envelope apply is consumed and deinit is idempotent" {
    const allocator = testing.allocator;
    const batch = try allocator.create(TypedBatch(TestRecord));
    const key = try (ObjectKey{ .uid = "u", .namespace = "n", .name = "p" }).clone(allocator);
    const changes = try allocator.alloc(TypedChange(TestRecord), 1);
    changes[0] = .{ .initial_upsert = .{ .key = key, .value = 3 } };
    batch.* = .{
        .generation = 1,
        .subscription_id = 2,
        .revision = 9,
        .changes = changes,
        .sync = .list_started,
        .owned_bytes = 32,
    };

    var sink = CountingSink{};
    var envelope = try eraseBatch(TestRecord, allocator, batch, &test_batch_handler, @ptrCast(&sink));
    var router = UiRouter{ .context = @ptrCast(&sink), .targetFn = sinkTarget };
    try envelope.apply(&router, allocator);
    try testing.expectEqual(Envelope.State.consumed, envelope.state);
    try testing.expectEqual(@as(usize, 1), sink.applied);
    try testing.expectEqual(@as(u32, 3), sink.last_value);
    envelope.deinit(allocator);
    envelope.deinit(allocator);
}

test "stale envelope with no router target is destroyed once" {
    const allocator = testing.allocator;
    const batch = try allocator.create(TypedBatch(TestRecord));
    batch.* = .{
        .generation = 1,
        .subscription_id = 1,
        .revision = 1,
        .changes = &.{},
        .sync = null,
        .owned_bytes = 8,
    };
    var envelope = try eraseBatch(TestRecord, allocator, batch, &test_batch_handler, @ptrFromInt(1));
    var router = UiRouter{ .context = @ptrFromInt(1), .targetFn = nullTarget };
    try envelope.apply(&router, allocator);
    try testing.expectEqual(Envelope.State.consumed, envelope.state);
    envelope.deinit(allocator);
}

const ScratchPayload = struct {
    allocs: usize,
    seen: usize = 0,
    scratch_allocator: std.mem.Allocator,
};

fn scratchPreflight(payload: *ScratchPayload, _: *UiRouter, _: std.mem.Allocator) anyerror!ApplyPlan {
    const allocator = payload.scratch_allocator;
    var i: usize = 0;
    var held: std.ArrayListUnmanaged([]u8) = .empty;
    errdefer {
        for (held.items) |item| allocator.free(item);
        held.deinit(allocator);
    }
    while (i < payload.allocs) : (i += 1) {
        const buf = try allocator.alloc(u8, 1);
        held.append(allocator, buf) catch |err| {
            allocator.free(buf);
            return err;
        };
        payload.seen += 1;
    }
    const scratch = try allocator.create(std.ArrayListUnmanaged([]u8));
    scratch.* = held;
    return .{
        .scratch = scratch,
        .scratch_alignment = .of(std.ArrayListUnmanaged([]u8)),
        .revision = 1,
        .deinitFn = scratchPlanDeinit,
    };
}

fn scratchPlanDeinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
    const scratch: *std.ArrayListUnmanaged([]u8) = @ptrCast(@alignCast(raw orelse return));
    for (scratch.items) |item| allocator.free(item);
    scratch.deinit(allocator);
    allocator.destroy(scratch);
}

fn scratchCommit(_: *ScratchPayload, _: *UiRouter, _: *ApplyPlan) void {}

fn scratchDeinit(_: *ScratchPayload, _: std.mem.Allocator) void {}

const scratch_handler = PayloadHandler(ScratchPayload){
    .preflight = scratchPreflight,
    .commit = scratchCommit,
    .deinit = scratchDeinit,
};

test "preflight allocation failure frees partial scratch and leaves target unchanged" {
    const backing = testing.allocator;
    const ancillary = [_]EnvelopeTarget{
        .lifecycle,
        .header_metrics,
        .traffic,
        .detail,
        .yaml,
        .logs,
        .authorization,
    };
    for (ancillary) |target| {
        var fail_index: usize = 0;
        while (fail_index < 4) : (fail_index += 1) {
            var failing = testing.FailingAllocator.init(backing, .{ .fail_index = fail_index });
            const payload = try backing.create(ScratchPayload);
            payload.* = .{ .allocs = 3, .scratch_allocator = failing.allocator() };
            var envelope = try erasePayload(
                ScratchPayload,
                backing,
                target,
                payload,
                &scratch_handler,
                1,
                1,
                1,
                16,
                null,
            );
            try testing.expectEqual(target, envelope.target);
            try testing.expectEqual(@as(Revision, 1), envelope.revision);
            var sink: u8 = 0;
            var router = UiRouter{ .context = @ptrCast(&sink), .targetFn = sinkTarget };
            const result = envelope.apply(&router, backing);
            if (result) |_| {
                try testing.expectEqual(Envelope.State.consumed, envelope.state);
                envelope.deinit(backing);
                break;
            } else |_| {
                try testing.expectEqual(Envelope.State.queued, envelope.state);
                try testing.expectEqual(target, envelope.target);
                try testing.expectEqual(@as(Revision, 1), envelope.revision);
                envelope.deinit(backing);
            }
        }
    }
}

const ScratchAlloc = struct { scratch_allocator: std.mem.Allocator };

fn resourceScratchPreflight(
    raw: *anyopaque,
    batch: *TypedBatch(TestRecord),
    _: std.mem.Allocator,
) anyerror!ApplyPlan {
    _ = batch;
    const sink: *ScratchAlloc = @ptrCast(@alignCast(raw));
    var payload = ScratchPayload{ .allocs = 3, .scratch_allocator = sink.scratch_allocator };
    var router = UiRouter{ .context = raw, .targetFn = sinkTarget };
    return scratchPreflight(&payload, &router, sink.scratch_allocator);
}

fn resourceScratchCommit(_: *anyopaque, _: *TypedBatch(TestRecord), _: *ApplyPlan) void {}

const resource_scratch_handler = BatchHandler(TestRecord){
    .preflight = resourceScratchPreflight,
    .commit = resourceScratchCommit,
};

test "resource batch preflight OOM frees scratch and leaves revision unchanged" {
    const backing = testing.allocator;
    var fail_index: usize = 0;
    while (fail_index < 4) : (fail_index += 1) {
        var failing = testing.FailingAllocator.init(backing, .{ .fail_index = fail_index });
        const batch = try backing.create(TypedBatch(TestRecord));
        batch.* = .{
            .generation = 4,
            .subscription_id = 9,
            .revision = 11,
            .changes = &.{},
            .sync = null,
            .owned_bytes = 8,
        };
        var scratch_alloc = ScratchAlloc{ .scratch_allocator = failing.allocator() };
        var envelope = try eraseBatch(
            TestRecord,
            backing,
            batch,
            &resource_scratch_handler,
            @ptrCast(&scratch_alloc),
        );
        try testing.expectEqual(@as(Revision, 11), envelope.revision);
        var router = UiRouter{ .context = @ptrCast(&scratch_alloc), .targetFn = sinkTarget };
        const result = envelope.apply(&router, backing);
        if (result) |_| {
            envelope.deinit(backing);
            break;
        } else |_| {
            try testing.expectEqual(Envelope.State.queued, envelope.state);
            try testing.expectEqual(@as(Revision, 11), envelope.revision);
            envelope.deinit(backing);
        }
    }
}

fn noopPayloadPreflight(_: *u8, _: *UiRouter, _: std.mem.Allocator) anyerror!ApplyPlan {
    return ApplyPlan.empty(0);
}
fn noopPayloadCommit(_: *u8, _: *UiRouter, _: *ApplyPlan) void {}
fn noopPayloadDeinit(_: *u8, _: std.mem.Allocator) void {}

pub const test_noop_u8_handler = PayloadHandler(u8){
    .preflight = noopPayloadPreflight,
    .commit = noopPayloadCommit,
    .deinit = noopPayloadDeinit,
};

test "erasePayload covers every ancillary target class" {
    const allocator = testing.allocator;
    const targets = [_]EnvelopeTarget{
        .lifecycle,
        .header_metrics,
        .traffic,
        .detail,
        .yaml,
        .logs,
        .authorization,
    };
    for (targets) |target| {
        const payload = try allocator.create(u8);
        payload.* = 1;
        var envelope = try erasePayload(
            u8,
            allocator,
            target,
            payload,
            &test_noop_u8_handler,
            1,
            0,
            0,
            1,
            null,
        );
        try testing.expectEqual(target, envelope.target);
        envelope.deinit(allocator);
    }
}

test "payload alignment is recorded from the box type" {
    const allocator = testing.allocator;
    const payload = try allocator.create(u8);
    payload.* = 0;
    var envelope = try erasePayload(
        u8,
        allocator,
        .yaml,
        payload,
        &test_noop_u8_handler,
        0,
        0,
        0,
        1,
        null,
    );
    try testing.expect(envelope.payload_alignment.toByteUnits() >= @alignOf(u8));
    envelope.deinit(allocator);
}

test "deliveryMustSplit rejects child deliveries above 256 KiB" {
    try testing.expect(!deliveryMustSplit(256 << 10, Limits.default));
    try testing.expect(deliveryMustSplit((256 << 10) + 1, Limits.default));
}
