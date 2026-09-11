const std = @import("std");
const klient = @import("klient");
const resource_key = @import("ResourceKey.zig");

pub const ObjectKey = resource_key.ObjectKey;
pub const OwnedBytes = resource_key.OwnedBytes;
pub const TypedBatch = resource_key.TypedBatch;
pub const TypedChange = resource_key.TypedChange;
pub const DataError = resource_key.DataError;
pub const ErrorDetail = resource_key.ErrorDetail;
pub const Generation = resource_key.Generation;
pub const SubscriptionId = resource_key.SubscriptionId;
pub const Revision = resource_key.Revision;

pub const PublicWatchOutcome = klient.WatchOutcome;

pub const CancelToken = struct {
    context: *const anyopaque,
    is_canceled_fn: *const fn (*const anyopaque) bool,

    pub fn isCanceled(self: CancelToken) bool {
        return self.is_canceled_fn(self.context);
    }

    pub fn never() CancelToken {
        return .{ .context = @ptrFromInt(1), .is_canceled_fn = neverCanceled };
    }
};

fn neverCanceled(_: *const anyopaque) bool {
    return false;
}

pub const BackoffPolicy = struct {
    initial_ns: u64 = 100 * std.time.ns_per_ms,
    max_ns: u64 = 5 * std.time.ns_per_s,
    max_attempts: u8 = 6,

    pub fn delay(self: BackoffPolicy, attempt: u8) u64 {
        var value = @min(self.initial_ns, self.max_ns);
        var remaining = attempt;
        while (remaining > 0 and value < self.max_ns) : (remaining -= 1) {
            value = @min(value *| 2, self.max_ns);
        }
        return value;
    }
};

pub const RetryHooks = struct {
    context: *anyopaque,
    wait_fn: *const fn (*anyopaque, u64, CancelToken) anyerror!bool,

    /// Returns false when cancellation interrupted the wait.
    pub fn wait(self: RetryHooks, delay_ns: u64, cancel: CancelToken) !bool {
        return self.wait_fn(self.context, delay_ns, cancel);
    }
};

pub const DiagnosticKind = enum {
    list_start,
    list_page,
    list_complete,
    watch_http_established,
    watch_event,
    watch_bookmark,
    watch_disconnect,
    reconnect_attempt,
    reconnect_success,
    gone_410,
    relist,
    terminal_forbidden,
    terminal_unauthorized,
    terminal_absent,
    terminal_malformed,
    retries_exhausted,
    transport_retry,
};

pub const DiagnosticObserver = struct {
    context: *anyopaque,
    notify_fn: *const fn (*anyopaque, DiagnosticKind, usize, []const u8) void,

    pub fn notify(
        self: DiagnosticObserver,
        kind: DiagnosticKind,
        count: usize,
        fingerprint_source: []const u8,
    ) void {
        self.notify_fn(self.context, kind, count, fingerprint_source);
    }
};

pub const Failure = union(enum) {
    unauthorized,
    forbidden,
    absent,
    gone,
    throttled: ?u64,
    server,
    transport,
    malformed: ErrorDetail,
    canceled,
};

pub const ListOutcome = union(enum) {
    complete: OwnedBytes,
    failure: Failure,

    pub fn deinit(self: *ListOutcome, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .complete => |*rv| rv.deinit(allocator),
            else => {},
        }
    }
};

pub fn WatchEvent(comptime Record: type) type {
    return union(enum) {
        added: ?Record,
        modified: ?Record,
        deleted: ?ObjectKey,
        bookmark: OwnedBytes,
        established,

        pub fn deinit(self: *@This(), allocator: std.mem.Allocator) void {
            switch (self.*) {
                .added => |*record| if (record.*) |*value| value.deinit(allocator),
                .modified => |*record| if (record.*) |*value| value.deinit(allocator),
                .deleted => |*key| if (key.*) |*value| value.deinit(allocator),
                .bookmark => |*rv| rv.deinit(allocator),
                .established => {},
            }
        }
    };
}

pub fn Source(comptime Record: type) type {
    return struct {
        context: *anyopaque,
        list_fn: *const fn (
            *anyopaque,
            CancelToken,
            *anyopaque,
            *const fn (*anyopaque, Record) anyerror!void,
            *const fn (*anyopaque) anyerror!void,
        ) anyerror!ListOutcome,
        watch_fn: *const fn (
            *anyopaque,
            []const u8,
            CancelToken,
            *anyopaque,
            *const fn (*anyopaque, *WatchEvent(Record)) anyerror!void,
        ) anyerror!Failure,

        pub fn list(
            self: @This(),
            cancel: CancelToken,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, Record) anyerror!void,
            chunk_end: *const fn (*anyopaque) anyerror!void,
        ) !ListOutcome {
            return self.list_fn(self.context, cancel, receiver_context, receiver, chunk_end);
        }

        pub fn watch(
            self: @This(),
            resource_version: []const u8,
            cancel: CancelToken,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, *WatchEvent(Record)) anyerror!void,
        ) !Failure {
            return self.watch_fn(
                self.context,
                resource_version,
                cancel,
                receiver_context,
                receiver,
            );
        }
    };
}

pub fn BatchSink(comptime Record: type) type {
    return struct {
        context: *anyopaque,
        /// Takes ownership of the batch on every return path.
        emit_fn: *const fn (*anyopaque, *TypedBatch(Record)) anyerror!void,

        pub fn emit(self: @This(), batch: *TypedBatch(Record)) !void {
            return self.emit_fn(self.context, batch);
        }
    };
}

pub const RunOutcome = union(enum) {
    canceled,
    unauthorized,
    forbidden,
    absent,
    malformed: ErrorDetail,
    retries_exhausted: DataError,
};

pub fn detailForRunOutcome(outcome: RunOutcome) ?ErrorDetail {
    return switch (outcome) {
        .canceled => null,
        .unauthorized => .{ .code = .unauthorized, .http_status = 401 },
        .forbidden => .{ .code = .forbidden, .http_status = 403 },
        .absent => .{ .code = .absent, .http_status = 404 },
        .malformed => |detail| detail,
        .retries_exhausted => |code| .{ .code = code },
    };
}

pub fn Driver(comptime Record: type) type {
    return struct {
        allocator: std.mem.Allocator,
        source: Source(Record),
        sink: BatchSink(Record),
        retry_hooks: RetryHooks,
        cancel: CancelToken,
        generation: Generation,
        subscription_id: SubscriptionId,
        max_batch_items: usize = 128,
        backoff: BackoffPolicy = .{},
        revision: Revision = 0,
        resource_version: OwnedBytes = .{},
        pending: std.ArrayListUnmanaged(TypedChange(Record)) = .empty,
        pending_bytes: usize = 0,
        list_object_count: usize = 0,
        change_kind: enum { initial, watch } = .initial,
        /// True once the current watch session delivered a valid event or bookmark.
        watch_progressed: bool = false,
        observer: ?DiagnosticObserver = null,
        list_pages: usize = 0,
        reconnecting: bool = false,

        const Self = @This();

        pub fn deinit(self: *Self) void {
            self.clearPending();
            self.pending.deinit(self.allocator);
            self.resource_version.deinit(self.allocator);
        }

        pub fn run(self: *Self) !RunOutcome {
            if (self.max_batch_items == 0) return error.InvalidBatchLimit;
            var retry_attempt: u8 = 0;
            var needs_list = true;

            while (true) {
                if (self.cancel.isCanceled()) return .canceled;
                if (needs_list) {
                    self.change_kind = .initial;
                    self.list_object_count = 0;
                    self.list_pages = 0;
                    self.observe(if (self.resource_version.bytes.len == 0) .list_start else .relist, 0, self.resource_version.bytes);
                    try self.emitSync(.list_started);

                    var list_outcome = try self.source.list(
                        self.cancel,
                        self,
                        receiveListRecord,
                        flushListChunk,
                    );
                    defer list_outcome.deinit(self.allocator);
                    if (self.cancel.isCanceled()) return .canceled;

                    switch (list_outcome) {
                        .complete => |*rv| {
                            try self.flush();
                            try self.setResourceVersion(rv.bytes);
                            const sync_rv = rv.*;
                            rv.* = .{};
                            try self.emitSync(.{ .list_complete = .{
                                .resource_version = sync_rv,
                                .object_count = self.list_object_count,
                            } });
                            self.observe(.list_complete, self.list_object_count, self.resource_version.bytes);
                            retry_attempt = 0;
                            needs_list = false;
                        },
                        .failure => |failure| {
                            self.clearPending();
                            switch (failure) {
                                .gone => {
                                    self.observe(.gone_410, 0, self.resource_version.bytes);
                                    self.resource_version.deinit(self.allocator);
                                    continue;
                                },
                                else => if (try self.handleFailure(failure, &retry_attempt)) |outcome| {
                                    return outcome;
                                },
                            }
                        },
                    }
                    continue;
                }

                self.change_kind = .watch;
                self.watch_progressed = false;
                const watch_outcome = try self.source.watch(
                    self.resource_version.bytes,
                    self.cancel,
                    self,
                    receiveWatchEvent,
                );
                try self.flush();
                if (self.cancel.isCanceled()) return .canceled;

                switch (watch_outcome) {
                    .gone => {
                        self.observe(.gone_410, 0, self.resource_version.bytes);
                        self.resource_version.deinit(self.allocator);
                        retry_attempt = 0;
                        needs_list = true;
                    },
                    else => {
                        self.observe(.watch_disconnect, 0, self.resource_version.bytes);
                        // A session that delivered events made forward progress, so
                        // its transient failure starts a fresh retry budget rather
                        // than consuming the budget of a stream that never worked.
                        if (self.watch_progressed) retry_attempt = 0;
                        if (try self.handleFailure(watch_outcome, &retry_attempt)) |outcome| {
                            return outcome;
                        }
                    },
                }
            }
        }

        fn receiveListRecord(raw: *anyopaque, record: Record) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(raw));
            try self.appendChange(.{ .initial_upsert = record });
            self.list_object_count += 1;
        }

        fn flushListChunk(raw: *anyopaque) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(raw));
            self.list_pages +|= 1;
            self.observe(.list_page, self.list_pages, "");
            try self.flush();
        }

        fn receiveWatchEvent(raw: *anyopaque, event: *WatchEvent(Record)) anyerror!void {
            const self: *Self = @ptrCast(@alignCast(raw));
            switch (event.*) {
                .added => |*record| {
                    const owned = record.* orelse return error.MalformedWatchEvent;
                    record.* = null;
                    try self.appendChange(.{ .watch_upsert = owned });
                    self.observe(.watch_event, 1, "");
                },
                .modified => |*record| {
                    const owned = record.* orelse return error.MalformedWatchEvent;
                    record.* = null;
                    try self.appendChange(.{ .watch_upsert = owned });
                    self.observe(.watch_event, 1, "");
                },
                .deleted => |*key| {
                    const owned = key.* orelse return error.MalformedWatchEvent;
                    key.* = null;
                    try self.appendChange(.{ .delete = owned });
                    self.observe(.watch_event, 1, "");
                },
                .bookmark => |*rv| {
                    try self.setResourceVersion(rv.bytes);
                    rv.deinit(self.allocator);
                    self.observe(.watch_bookmark, 0, self.resource_version.bytes);
                },
                .established => {
                    try self.emitSync(.watch_connected);
                    self.observe(
                        if (self.reconnecting) .reconnect_success else .watch_http_established,
                        0,
                        self.resource_version.bytes,
                    );
                    self.reconnecting = false;
                },
            }
            if (event.* != .established) self.watch_progressed = true;
        }

        fn appendChange(self: *Self, change: TypedChange(Record)) !void {
            var owned = change;
            // Once appended, `pending` owns the change: a later flush failure must
            // leave it for clearPending rather than free it here.
            self.pending.append(self.allocator, owned) catch |err| {
                owned.deinit(self.allocator);
                return err;
            };
            self.pending_bytes +|= estimateChangeBytes(Record, &owned);
            // A watch stream can stay open for hours, so a change cannot wait for
            // the batch limit or for the session to end before it becomes visible.
            const deliver_now = self.change_kind == .watch or
                self.pending.items.len >= self.max_batch_items;
            if (deliver_now) try self.flush();
        }

        fn flush(self: *Self) !void {
            if (self.pending.items.len == 0) return;
            const changes = try self.pending.toOwnedSlice(self.allocator);
            var batch = TypedBatch(Record){
                .generation = self.generation,
                .subscription_id = self.subscription_id,
                .revision = self.nextRevision(),
                .changes = changes,
                .sync = null,
                .owned_bytes = self.pending_bytes,
            };
            self.pending_bytes = 0;
            try self.sink.emit(&batch);
        }

        fn emitSync(self: *Self, sync: resource_key.SyncBoundary) !void {
            const owned_bytes = switch (sync) {
                .list_complete => |complete| complete.resource_version.bytes.len,
                else => 0,
            };
            var batch = TypedBatch(Record){
                .generation = self.generation,
                .subscription_id = self.subscription_id,
                .revision = self.nextRevision(),
                .changes = &.{},
                .sync = sync,
                .owned_bytes = owned_bytes,
            };
            try self.sink.emit(&batch);
        }

        fn nextRevision(self: *Self) Revision {
            self.revision +|= 1;
            return self.revision;
        }

        fn setResourceVersion(self: *Self, value: []const u8) !void {
            const replacement = try OwnedBytes.clone(self.allocator, value);
            self.resource_version.deinit(self.allocator);
            self.resource_version = replacement;
        }

        fn handleFailure(
            self: *Self,
            failure: Failure,
            retry_attempt: *u8,
        ) !?RunOutcome {
            switch (failure) {
                .canceled => return RunOutcome.canceled,
                .unauthorized => {
                    self.observe(.terminal_unauthorized, 0, "");
                    return RunOutcome.unauthorized;
                },
                .forbidden => {
                    self.observe(.terminal_forbidden, 0, "");
                    return RunOutcome.forbidden;
                },
                .absent => {
                    self.observe(.terminal_absent, 0, "");
                    return RunOutcome.absent;
                },
                .malformed => |detail| {
                    self.observe(.terminal_malformed, 0, "");
                    return RunOutcome{ .malformed = detail };
                },
                .gone => unreachable,
                .throttled => |retry_after_ns| {
                    self.observe(.transport_retry, retry_attempt.*, "");
                    self.reconnecting = true;
                    self.observe(.reconnect_attempt, retry_attempt.* + 1, "");
                    if (retry_attempt.* >= self.backoff.max_attempts) {
                        self.observe(.retries_exhausted, retry_attempt.*, "");
                        return RunOutcome{ .retries_exhausted = .throttled };
                    }
                    const delay_ns = retry_after_ns orelse self.backoff.delay(retry_attempt.*);
                    retry_attempt.* += 1;
                    if (!try self.retry_hooks.wait(delay_ns, self.cancel)) return RunOutcome.canceled;
                },
                .server, .transport => {
                    self.observe(.transport_retry, retry_attempt.*, "");
                    self.reconnecting = true;
                    self.observe(.reconnect_attempt, retry_attempt.* + 1, "");
                    const code: DataError = if (failure == .server) .server else .transport;
                    if (retry_attempt.* >= self.backoff.max_attempts) {
                        self.observe(.retries_exhausted, retry_attempt.*, "");
                        return RunOutcome{ .retries_exhausted = code };
                    }
                    const delay_ns = self.backoff.delay(retry_attempt.*);
                    retry_attempt.* += 1;
                    if (!try self.retry_hooks.wait(delay_ns, self.cancel)) return RunOutcome.canceled;
                },
            }
            return null;
        }

        fn observe(
            self: *Self,
            kind: DiagnosticKind,
            count: usize,
            fingerprint_source: []const u8,
        ) void {
            if (self.observer) |observer| observer.notify(kind, count, fingerprint_source);
        }

        fn clearPending(self: *Self) void {
            for (self.pending.items) |*change| change.deinit(self.allocator);
            self.pending.clearRetainingCapacity();
            self.pending_bytes = 0;
        }
    };
}

fn estimateChangeBytes(comptime Record: type, change: *const TypedChange(Record)) usize {
    return switch (change.*) {
        .initial_upsert, .watch_upsert => |record| @sizeOf(TypedChange(Record)) +
            if (record) |value| recordOwnedBytes(Record, value) else 0,
        .delete => |key| @sizeOf(TypedChange(Record)) +
            key.uid.len + key.namespace.len + key.name.len + key.labels.len,
        .metrics => |metrics| @sizeOf(TypedChange(Record)) +
            metrics.namespace.len + metrics.name.len,
    };
}

fn recordOwnedBytes(comptime Record: type, record: Record) usize {
    const base = if (@hasDecl(Record, "ownedBytes")) record.ownedBytes() else @sizeOf(Record);
    return base + if (@hasField(Record, "key")) record.key.labels.len else 0;
}

pub fn failureFromKlient(outcome: klient.WatchOutcome) ?Failure {
    return switch (outcome) {
        .eof => .transport,
        .canceled => .canceled,
        .http_unauthorized => .unauthorized,
        .http_forbidden => .forbidden,
        .http_gone, .status_expired => .gone,
        .http_throttled => |throttled| .{ .throttled = if (throttled.retry_after_seconds) |seconds|
            @as(u64, seconds) * std.time.ns_per_s
        else
            null },
        .http_server_error => .server,
        .transport_error => .transport,
        .malformed_event, .decode_error => |detail| .{ .malformed = detailFromKlient(detail) },
        .status_error => |detail| classifyStatusDetail(detail),
        .http_error => |status| classifyStatusCode(@intFromEnum(status)),
    };
}

fn classifyStatusDetail(detail: klient.WatchErrorDetail) Failure {
    return switch (detail.code orelse return .{ .malformed = detailFromKlient(detail) }) {
        401 => .unauthorized,
        403 => .forbidden,
        404 => .absent,
        410 => .gone,
        429 => .{ .throttled = null },
        else => .{ .malformed = detailFromKlient(detail) },
    };
}

fn classifyStatusCode(code: ?u16) Failure {
    return switch (code orelse return .server) {
        401 => .unauthorized,
        403 => .forbidden,
        404 => .absent,
        410 => .gone,
        429 => .{ .throttled = null },
        else => .server,
    };
}

fn detailFromKlient(detail: klient.WatchErrorDetail) ErrorDetail {
    var result: ErrorDetail = .{
        .code = .malformed_event,
        .http_status = detail.code,
    };
    const message = if (detail.messageSlice().len > 0)
        detail.messageSlice()
    else
        detail.payloadSlice();
    result.len = @intCast(@min(message.len, result.bytes.len));
    @memcpy(result.bytes[0..result.len], message[0..result.len]);
    return result;
}

const TestRecord = struct {
    key: ObjectKey,
    value: u32,

    fn make(allocator: std.mem.Allocator, uid: []const u8, value: u32) !TestRecord {
        return .{
            .key = try (ObjectKey{
                .uid = uid,
                .namespace = "ns",
                .name = "pod",
            }).clone(allocator),
            .value = value,
        };
    }

    pub fn clone(self: TestRecord, allocator: std.mem.Allocator) !TestRecord {
        return .{ .key = try self.key.clone(allocator), .value = self.value };
    }

    pub fn deinit(self: *TestRecord, allocator: std.mem.Allocator) void {
        self.key.deinit(allocator);
    }
};

const Scenario = enum {
    normal,
    gone,
    unauthorized,
    forbidden,
    throttled,
    server,
    transport,
    malformed,
    cancel_list,
    cancel_watch,
    event_then_hold,
    progress_then_transport,
};

const Script = struct {
    allocator: std.mem.Allocator,
    scenario: Scenario,
    list_calls: usize = 0,
    watch_calls: usize = 0,
    watched_rv_len: usize = 0,
    watched_rv: [32]u8 = @splat(0),
    /// Observed by scenarios that assert delivery latency from inside the callback.
    sink: ?*Sink = null,
    reconnects_before_cancel: usize = 0,
    mid_watch_upserts: usize = 0,
    mid_watch_batches: usize = 0,
    mid_list_upserts: usize = 0,

    fn source(self: *Script) Source(TestRecord) {
        return .{
            .context = self,
            .list_fn = scriptedList,
            .watch_fn = scriptedWatch,
        };
    }

    fn scriptedList(
        raw: *anyopaque,
        _: CancelToken,
        receiver_context: *anyopaque,
        receiver: *const fn (*anyopaque, TestRecord) anyerror!void,
        chunk_end: *const fn (*anyopaque) anyerror!void,
    ) anyerror!ListOutcome {
        const self: *Script = @ptrCast(@alignCast(raw));
        self.list_calls += 1;
        if (self.scenario == .cancel_list) return .{ .failure = .canceled };
        if (self.scenario == .unauthorized) return .{ .failure = .unauthorized };
        if (self.scenario == .forbidden) return .{ .failure = .forbidden };

        const item_count: usize = if (self.scenario == .normal) 5 else 1;
        for (0..item_count) |index| {
            var uid_buffer: [16]u8 = undefined;
            const uid = try std.fmt.bufPrint(&uid_buffer, "uid-{d}", .{index});
            const record = try TestRecord.make(self.allocator, uid, @intCast(index));
            try receiver(receiver_context, record);
        }
        try chunk_end(receiver_context);
        if (self.sink) |sink| self.mid_list_upserts = sink.initial_upserts;
        const rv = if (self.scenario == .gone and self.list_calls > 1) "20" else "10";
        return .{ .complete = try OwnedBytes.clone(self.allocator, rv) };
    }

    fn scriptedWatch(
        raw: *anyopaque,
        resource_version: []const u8,
        _: CancelToken,
        receiver_context: *anyopaque,
        receiver: *const fn (*anyopaque, *WatchEvent(TestRecord)) anyerror!void,
    ) anyerror!Failure {
        const self: *Script = @ptrCast(@alignCast(raw));
        self.watch_calls += 1;
        self.watched_rv_len = @min(resource_version.len, self.watched_rv.len);
        @memcpy(self.watched_rv[0..self.watched_rv_len], resource_version[0..self.watched_rv_len]);
        var established: WatchEvent(TestRecord) = .established;
        try receiver(receiver_context, &established);

        switch (self.scenario) {
            .normal => {
                var added: WatchEvent(TestRecord) = .{
                    .added = try TestRecord.make(self.allocator, "watch-1", 6),
                };
                defer added.deinit(self.allocator);
                try receiver(receiver_context, &added);

                var modified: WatchEvent(TestRecord) = .{
                    .modified = try TestRecord.make(self.allocator, "watch-1", 7),
                };
                defer modified.deinit(self.allocator);
                try receiver(receiver_context, &modified);

                var deleted: WatchEvent(TestRecord) = .{
                    .deleted = try (ObjectKey{
                        .uid = "watch-1",
                        .namespace = "ns",
                        .name = "pod",
                    }).clone(self.allocator),
                };
                defer deleted.deinit(self.allocator);
                try receiver(receiver_context, &deleted);

                var bookmark: WatchEvent(TestRecord) = .{
                    .bookmark = try OwnedBytes.clone(self.allocator, "11"),
                };
                defer bookmark.deinit(self.allocator);
                try receiver(receiver_context, &bookmark);
                return .canceled;
            },
            .gone => if (self.watch_calls == 1) return .gone else return .canceled,
            .throttled => if (self.watch_calls == 1)
                return .{ .throttled = 9 * std.time.ns_per_s }
            else
                return .canceled,
            .server => return .server,
            .transport => return .transport,
            .malformed => return .{ .malformed = malformedDetail("bad event") },
            .cancel_watch => return .canceled,
            .event_then_hold => {
                var added: WatchEvent(TestRecord) = .{
                    .added = try TestRecord.make(self.allocator, "watch-1", 1),
                };
                defer added.deinit(self.allocator);
                try receiver(receiver_context, &added);
                // The stream stays open here in production; record what the sink
                // has already seen before this session ends.
                if (self.sink) |sink| {
                    self.mid_watch_upserts = sink.watch_upserts;
                    self.mid_watch_batches = sink.batches;
                }

                var bookmark: WatchEvent(TestRecord) = .{
                    .bookmark = try OwnedBytes.clone(self.allocator, "12"),
                };
                defer bookmark.deinit(self.allocator);
                try receiver(receiver_context, &bookmark);
                return .canceled;
            },
            .progress_then_transport => {
                var added: WatchEvent(TestRecord) = .{
                    .added = try TestRecord.make(self.allocator, "watch-1", 1),
                };
                defer added.deinit(self.allocator);
                try receiver(receiver_context, &added);
                if (self.watch_calls >= self.reconnects_before_cancel) return .canceled;
                return .transport;
            },
            .unauthorized, .forbidden, .cancel_list => unreachable,
        }
    }
};

fn malformedDetail(message: []const u8) ErrorDetail {
    var detail: ErrorDetail = .{ .code = .malformed_event };
    detail.len = @intCast(@min(message.len, detail.bytes.len));
    @memcpy(detail.bytes[0..detail.len], message[0..detail.len]);
    return detail;
}

const Sink = struct {
    const Observed = enum {
        list_started,
        initial_upsert,
        list_complete,
        watch_connected,
        watch_upsert,
        delete,
    };

    allocator: std.mem.Allocator,
    batches: usize = 0,
    max_changes: usize = 0,
    initial_upserts: usize = 0,
    watch_upserts: usize = 0,
    deletes: usize = 0,
    list_started_count: usize = 0,
    list_complete_boundaries: usize = 0,
    watch_connected_count: usize = 0,
    list_complete_count: usize = 0,
    list_complete_rv_len: usize = 0,
    list_complete_rv: [32]u8 = @splat(0),
    observed: [32]Observed = undefined,
    observed_len: usize = 0,

    fn batchSink(self: *Sink) BatchSink(TestRecord) {
        return .{ .context = self, .emit_fn = emit };
    }

    fn emit(raw: *anyopaque, batch: *TypedBatch(TestRecord)) anyerror!void {
        const self: *Sink = @ptrCast(@alignCast(raw));
        self.batches += 1;
        self.max_changes = @max(self.max_changes, batch.changes.len);
        for (batch.changes) |change| switch (change) {
            .initial_upsert => {
                self.initial_upserts += 1;
                self.observe(.initial_upsert);
            },
            .watch_upsert => {
                self.watch_upserts += 1;
                self.observe(.watch_upsert);
            },
            .delete => {
                self.deletes += 1;
                self.observe(.delete);
            },
            .metrics => {},
        };
        if (batch.sync) |sync| switch (sync) {
            .list_started => {
                self.list_started_count += 1;
                self.observe(.list_started);
            },
            .list_complete => |complete| {
                self.list_complete_boundaries += 1;
                self.observe(.list_complete);
                self.list_complete_count = complete.object_count;
                self.list_complete_rv_len = @min(
                    complete.resource_version.bytes.len,
                    self.list_complete_rv.len,
                );
                @memcpy(
                    self.list_complete_rv[0..self.list_complete_rv_len],
                    complete.resource_version.bytes[0..self.list_complete_rv_len],
                );
            },
            .watch_connected => {
                self.watch_connected_count += 1;
                self.observe(.watch_connected);
            },
            else => {},
        };
        batch.deinit(self.allocator);
    }

    fn observe(self: *Sink, value: Observed) void {
        if (self.observed_len >= self.observed.len) return;
        self.observed[self.observed_len] = value;
        self.observed_len += 1;
    }
};

const Waiter = struct {
    waits: usize = 0,
    cancel_wait: bool = false,
    delays: [8]u64 = @splat(0),

    fn hooks(self: *Waiter) RetryHooks {
        return .{ .context = self, .wait_fn = wait };
    }

    fn wait(raw: *anyopaque, delay_ns: u64, _: CancelToken) anyerror!bool {
        const self: *Waiter = @ptrCast(@alignCast(raw));
        if (self.waits < self.delays.len) self.delays[self.waits] = delay_ns;
        self.waits += 1;
        return !self.cancel_wait;
    }
};

fn runScenario(
    allocator: std.mem.Allocator,
    script: *Script,
    sink: *Sink,
    waiter: *Waiter,
    max_batch_items: usize,
    backoff: BackoffPolicy,
) !RunOutcome {
    script.sink = sink;
    var driver = Driver(TestRecord){
        .allocator = allocator,
        .source = script.source(),
        .sink = sink.batchSink(),
        .retry_hooks = waiter.hooks(),
        .cancel = CancelToken.never(),
        .generation = 3,
        .subscription_id = 4,
        .max_batch_items = max_batch_items,
        .backoff = backoff,
    };
    defer driver.deinit();
    const outcome = try driver.run();
    if (script.scenario == .normal) {
        try std.testing.expectEqualStrings("11", driver.resource_version.bytes);
    }
    return outcome;
}

pub fn runTask15DiagnosticGate() !void {
    const Probe = struct {
        bookmarks: usize = 0,
        bookmark_fingerprint: u64 = 0,

        fn observe(
            raw: *anyopaque,
            kind: DiagnosticKind,
            _: usize,
            value: []const u8,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (kind != .watch_bookmark) return;
            self.bookmarks += 1;
            self.bookmark_fingerprint = std.hash.Wyhash.hash(1, value);
        }
    };
    var script = Script{ .allocator = std.testing.allocator, .scenario = .normal };
    var sink = Sink{ .allocator = std.testing.allocator };
    var waiter = Waiter{};
    var probe = Probe{};
    script.sink = &sink;
    var driver = Driver(TestRecord){
        .allocator = std.testing.allocator,
        .source = script.source(),
        .sink = sink.batchSink(),
        .retry_hooks = waiter.hooks(),
        .cancel = CancelToken.never(),
        .generation = 1,
        .subscription_id = 1,
        .observer = .{ .context = &probe, .notify_fn = Probe.observe },
    };
    defer driver.deinit();
    const outcome = try driver.run();
    try std.testing.expect(outcome == .canceled);
    try std.testing.expectEqual(@as(usize, 1), probe.bookmarks);
    try std.testing.expect(probe.bookmark_fingerprint != 0);

    try std.testing.expect(failureFromKlient(.{
        .status_error = .{ .code = 403 },
    }).? == .forbidden);
    try std.testing.expect(failureFromKlient(.{
        .status_error = .{ .code = 404 },
    }).? == .absent);
    const malformed = failureFromKlient(.{
        .status_error = .{ .code = 422 },
    }).?;
    try std.testing.expect(malformed == .malformed);
}

pub fn runTask14OrderingGate() !void {
    const allocator = std.testing.allocator;
    var normal = Script{ .allocator = allocator, .scenario = .normal };
    var normal_sink = Sink{ .allocator = allocator };
    var normal_waiter = Waiter{};
    const normal_outcome = try runScenario(
        allocator,
        &normal,
        &normal_sink,
        &normal_waiter,
        2,
        .{},
    );
    try std.testing.expect(normal_outcome == .canceled);
    try std.testing.expectEqual(@as(usize, 1), normal.list_calls);
    try std.testing.expectEqual(@as(usize, 1), normal.watch_calls);
    try std.testing.expectEqual(@as(usize, 1), normal_sink.list_started_count);
    try std.testing.expectEqual(@as(usize, 1), normal_sink.list_complete_boundaries);
    try std.testing.expectEqual(@as(usize, 1), normal_sink.watch_connected_count);
    try std.testing.expectEqualStrings(
        "10",
        normal.watched_rv[0..normal.watched_rv_len],
    );
    try std.testing.expectEqualStrings(
        "10",
        normal_sink.list_complete_rv[0..normal_sink.list_complete_rv_len],
    );
    try std.testing.expectEqual(@as(usize, 5), normal_sink.initial_upserts);
    try std.testing.expectEqual(@as(usize, 2), normal_sink.watch_upserts);
    try std.testing.expectEqual(@as(usize, 1), normal_sink.deletes);
    try std.testing.expectEqualSlices(
        Sink.Observed,
        &.{
            .list_started,
            .initial_upsert,
            .initial_upsert,
            .initial_upsert,
            .initial_upsert,
            .initial_upsert,
            .list_complete,
            .watch_connected,
            .watch_upsert,
            .watch_upsert,
            .delete,
        },
        normal_sink.observed[0..normal_sink.observed_len],
    );

    var gone = Script{ .allocator = allocator, .scenario = .gone };
    var gone_sink = Sink{ .allocator = allocator };
    var gone_waiter = Waiter{};
    const gone_outcome = try runScenario(
        allocator,
        &gone,
        &gone_sink,
        &gone_waiter,
        8,
        .{},
    );
    try std.testing.expect(gone_outcome == .canceled);
    try std.testing.expectEqual(@as(usize, 2), gone.list_calls);
    try std.testing.expectEqual(@as(usize, 2), gone.watch_calls);
    try std.testing.expectEqual(@as(usize, 2), gone_sink.list_started_count);
    try std.testing.expectEqual(@as(usize, 2), gone_sink.list_complete_boundaries);
    try std.testing.expectEqual(@as(usize, 2), gone_sink.watch_connected_count);
    try std.testing.expectEqualStrings("20", gone.watched_rv[0..gone.watched_rv_len]);
}

test "streaming LIST batches hand final RV exactly to WATCH and process events" {
    const allocator = std.testing.allocator;
    var script = Script{ .allocator = allocator, .scenario = .normal };
    var sink = Sink{ .allocator = allocator };
    var waiter = Waiter{};
    const outcome = try runScenario(allocator, &script, &sink, &waiter, 2, .{});

    try std.testing.expect(outcome == .canceled);
    try std.testing.expectEqual(@as(usize, 1), script.list_calls);
    try std.testing.expectEqual(@as(usize, 1), script.watch_calls);
    try std.testing.expectEqualStrings("10", script.watched_rv[0..script.watched_rv_len]);
    try std.testing.expectEqualStrings("10", sink.list_complete_rv[0..sink.list_complete_rv_len]);
    try std.testing.expectEqual(@as(usize, 5), sink.list_complete_count);
    try std.testing.expectEqual(@as(usize, 5), sink.initial_upserts);
    try std.testing.expectEqual(@as(usize, 2), sink.watch_upserts);
    try std.testing.expectEqual(@as(usize, 1), sink.deletes);
    try std.testing.expect(sink.max_changes <= 2);
}

test "source chunk boundary flushes fewer than 128 initial objects before list completion" {
    const allocator = std.testing.allocator;
    var script = Script{ .allocator = allocator, .scenario = .normal };
    var sink = Sink{ .allocator = allocator };
    var waiter = Waiter{};
    const outcome = try runScenario(allocator, &script, &sink, &waiter, 128, .{});

    try std.testing.expect(outcome == .canceled);
    try std.testing.expectEqual(@as(usize, 5), script.mid_list_upserts);
    try std.testing.expectEqual(@as(usize, 5), sink.initial_upserts);
}

test "each WATCH change reaches the sink before the session ends" {
    const allocator = std.testing.allocator;
    var script = Script{ .allocator = allocator, .scenario = .event_then_hold };
    var sink = Sink{ .allocator = allocator };
    var waiter = Waiter{};
    const outcome = try runScenario(allocator, &script, &sink, &waiter, 128, .{});

    try std.testing.expect(outcome == .canceled);
    try std.testing.expectEqual(@as(usize, 1), script.mid_watch_upserts);
    try std.testing.expect(script.mid_watch_batches > 0);
    try std.testing.expectEqual(@as(usize, 1), sink.watch_upserts);
}

test "watch progress resets the retry budget across many reconnects" {
    const allocator = std.testing.allocator;
    var script = Script{
        .allocator = allocator,
        .scenario = .progress_then_transport,
        .reconnects_before_cancel = 6,
    };
    var sink = Sink{ .allocator = allocator };
    var waiter = Waiter{};
    const outcome = try runScenario(allocator, &script, &sink, &waiter, 128, .{
        .initial_ns = 10,
        .max_ns = 15,
        .max_attempts = 2,
    });

    try std.testing.expect(outcome == .canceled);
    try std.testing.expectEqual(@as(usize, 6), script.watch_calls);
    try std.testing.expectEqual(@as(usize, 6), sink.watch_upserts);
    try std.testing.expectEqual(@as(usize, 5), waiter.waits);
    for (waiter.delays[0..5]) |delay| try std.testing.expectEqual(@as(u64, 10), delay);
}

test "410 relists and watches from replacement RV" {
    const allocator = std.testing.allocator;
    var script = Script{ .allocator = allocator, .scenario = .gone };
    var sink = Sink{ .allocator = allocator };
    var waiter = Waiter{};
    const outcome = try runScenario(allocator, &script, &sink, &waiter, 8, .{});
    try std.testing.expect(outcome == .canceled);
    try std.testing.expectEqual(@as(usize, 2), script.list_calls);
    try std.testing.expectEqual(@as(usize, 2), script.watch_calls);
    try std.testing.expectEqualStrings("20", script.watched_rv[0..script.watched_rv_len]);
}

test "401 and 403 are terminal without retry" {
    inline for (.{ Scenario.unauthorized, Scenario.forbidden }) |scenario| {
        const allocator = std.testing.allocator;
        var script = Script{ .allocator = allocator, .scenario = scenario };
        var sink = Sink{ .allocator = allocator };
        var waiter = Waiter{};
        const outcome = try runScenario(allocator, &script, &sink, &waiter, 8, .{});
        if (scenario == .unauthorized) {
            try std.testing.expect(outcome == .unauthorized);
        } else {
            try std.testing.expect(outcome == .forbidden);
        }
        try std.testing.expectEqual(@as(usize, 0), waiter.waits);
    }
}

test "429 honors retry-after without sleeping" {
    const allocator = std.testing.allocator;
    var script = Script{ .allocator = allocator, .scenario = .throttled };
    var sink = Sink{ .allocator = allocator };
    var waiter = Waiter{};
    const outcome = try runScenario(allocator, &script, &sink, &waiter, 8, .{});
    try std.testing.expect(outcome == .canceled);
    try std.testing.expectEqual(@as(usize, 1), waiter.waits);
    try std.testing.expectEqual(@as(u64, 9 * std.time.ns_per_s), waiter.delays[0]);
}

test "5xx and transport retries are deterministic and bounded" {
    inline for (.{ Scenario.server, Scenario.transport }) |scenario| {
        const allocator = std.testing.allocator;
        var script = Script{ .allocator = allocator, .scenario = scenario };
        var sink = Sink{ .allocator = allocator };
        var waiter = Waiter{};
        const outcome = try runScenario(allocator, &script, &sink, &waiter, 8, .{
            .initial_ns = 10,
            .max_ns = 15,
            .max_attempts = 2,
        });
        try std.testing.expect(outcome == .retries_exhausted);
        try std.testing.expectEqual(@as(usize, 2), waiter.waits);
        try std.testing.expectEqual(@as(u64, 10), waiter.delays[0]);
        try std.testing.expectEqual(@as(u64, 15), waiter.delays[1]);
    }
}

test "malformed event is surfaced without retry" {
    const allocator = std.testing.allocator;
    var script = Script{ .allocator = allocator, .scenario = .malformed };
    var sink = Sink{ .allocator = allocator };
    var waiter = Waiter{};
    const outcome = try runScenario(allocator, &script, &sink, &waiter, 8, .{});
    try std.testing.expect(outcome == .malformed);
    try std.testing.expectEqualStrings(
        "bad event",
        outcome.malformed.bytes[0..outcome.malformed.len],
    );
    try std.testing.expectEqual(@as(usize, 0), waiter.waits);
}

test "cancellation during list watch and backoff is explicit" {
    inline for (.{ Scenario.cancel_list, Scenario.cancel_watch }) |scenario| {
        const allocator = std.testing.allocator;
        var script = Script{ .allocator = allocator, .scenario = scenario };
        var sink = Sink{ .allocator = allocator };
        var waiter = Waiter{};
        const outcome = try runScenario(allocator, &script, &sink, &waiter, 8, .{});
        try std.testing.expect(outcome == .canceled);
    }

    const allocator = std.testing.allocator;
    var script = Script{ .allocator = allocator, .scenario = .server };
    var sink = Sink{ .allocator = allocator };
    var waiter = Waiter{ .cancel_wait = true };
    const outcome = try runScenario(allocator, &script, &sink, &waiter, 8, .{});
    try std.testing.expect(outcome == .canceled);
    try std.testing.expectEqual(@as(usize, 1), waiter.waits);
}

test "klient outcomes preserve auth expiry retry-after and malformed classes" {
    try std.testing.expect(failureFromKlient(.http_unauthorized).? == .unauthorized);
    try std.testing.expect(failureFromKlient(.http_forbidden).? == .forbidden);
    try std.testing.expect(failureFromKlient(.http_gone).? == .gone);
    const throttled = failureFromKlient(.{
        .http_throttled = .{ .retry_after_seconds = 3 },
    }).?;
    try std.testing.expectEqual(
        @as(?u64, 3 * std.time.ns_per_s),
        throttled.throttled,
    );
    try std.testing.expect(failureFromKlient(.{
        .status_error = .{ .code = 401 },
    }).? == .unauthorized);
    try std.testing.expect(failureFromKlient(.{
        .status_error = .{ .code = 403 },
    }).? == .forbidden);
    try std.testing.expect(failureFromKlient(.{
        .status_error = .{ .code = 410 },
    }).? == .gone);
}

test "allocation failures unwind records batches and resource versions" {
    const backing = std.testing.allocator;
    var reached_success = false;
    var fail_index: usize = 0;
    while (fail_index < 48) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(backing, .{ .fail_index = fail_index });
        const allocator = failing.allocator();
        var script = Script{ .allocator = allocator, .scenario = .normal };
        var sink = Sink{ .allocator = allocator };
        var waiter = Waiter{};

        const result = runScenario(allocator, &script, &sink, &waiter, 2, .{});
        if (result) |outcome| {
            try std.testing.expect(outcome == .canceled);
            reached_success = true;
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
        }
    }
    try std.testing.expect(reached_success);
}
