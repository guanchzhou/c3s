const std = @import("std");
const testing = std.testing;

const fd_t = std.c.fd_t;

pub const max_record_bytes: usize = 512;

pub const EventKind = enum {
    sync_start,
    first_batch_queued,
    first_usable_paint,
    list_complete_received,
    complete_sync_paint,
    watch_connected,
    metrics_ready,
    reconnect_start,
    reconnect_complete,
    summary,
};

pub const Event = struct {
    kind: EventKind,
    monotonic_ns: u64,
    context: []const u8,
    resource: []const u8,
    scope: []const u8,
    generation: u64,
    subscription_id: u32,
    applied_revision: u64,
    object_count: usize,
    queue_bytes: usize,
};

pub const Counters = struct {
    dropped_oversize: u64 = 0,
    dropped_eagain: u64 = 0,
    write_faults: u64 = 0,
};

const WriteFn = *const fn (fd_t, [*]const u8, usize) callconv(.c) isize;

const Record = struct {
    bytes: [max_record_bytes]u8 = undefined,
    len: usize = 0,
    overflow: bool = false,

    fn append(self: *Record, bytes: []const u8) void {
        if (self.overflow) return;
        if (bytes.len > self.bytes.len - self.len) {
            self.overflow = true;
            return;
        }
        @memcpy(self.bytes[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
    }

    fn appendByte(self: *Record, byte: u8) void {
        self.append(&.{byte});
    }

    fn appendString(self: *Record, value: []const u8) void {
        self.appendByte('"');
        for (value) |byte| {
            switch (byte) {
                '"' => self.append("\\\""),
                '\\' => self.append("\\\\"),
                0x08 => self.append("\\b"),
                0x0c => self.append("\\f"),
                '\n' => self.append("\\n"),
                '\r' => self.append("\\r"),
                '\t' => self.append("\\t"),
                0x00...0x07, 0x0b, 0x0e...0x1f => {
                    const hex = "0123456789abcdef";
                    self.append("\\u00");
                    self.appendByte(hex[byte >> 4]);
                    self.appendByte(hex[byte & 0x0f]);
                },
                else => self.appendByte(byte),
            }
        }
        self.appendByte('"');
    }

    fn appendInt(self: *Record, value: anytype) void {
        var buf: [40]u8 = undefined;
        const encoded = std.fmt.bufPrint(&buf, "{d}", .{value}) catch {
            self.overflow = true;
            return;
        };
        self.append(encoded);
    }

    fn finish(self: *Record) ?[]const u8 {
        if (self.overflow) return null;
        return self.bytes[0..self.len];
    }
};

fn encodeRecord(event: Event, counters: ?Counters, record: *Record) ?[]const u8 {
    record.append("{\"event\":");
    record.appendString(@tagName(event.kind));
    record.append(",\"monotonic_ns\":");
    record.appendInt(event.monotonic_ns);
    record.append(",\"context\":");
    record.appendString(event.context);
    record.append(",\"resource\":");
    record.appendString(event.resource);
    record.append(",\"scope\":");
    record.appendString(event.scope);
    record.append(",\"generation\":");
    record.appendInt(event.generation);
    record.append(",\"subscription_id\":");
    record.appendInt(event.subscription_id);
    record.append(",\"applied_revision\":");
    record.appendInt(event.applied_revision);
    record.append(",\"object_count\":");
    record.appendInt(event.object_count);
    record.append(",\"queue_bytes\":");
    record.appendInt(event.queue_bytes);
    if (counters) |snapshot| {
        record.append(",\"dropped_oversize\":");
        record.appendInt(snapshot.dropped_oversize);
        record.append(",\"dropped_eagain\":");
        record.appendInt(snapshot.dropped_eagain);
        record.append(",\"write_faults\":");
        record.appendInt(snapshot.write_faults);
    }
    record.append("}\n");
    return record.finish();
}

fn setCloseOnExec(fd: fd_t) bool {
    const flags = while (true) {
        const result = std.c.fcntl(fd, std.c.F.GETFD);
        if (result >= 0) break result;
        if (std.c.errno(result) != .INTR) return false;
    };
    if (flags & std.c.FD_CLOEXEC != 0) return true;
    while (true) {
        const result = std.c.fcntl(fd, std.c.F.SETFD, flags | @as(c_int, std.c.FD_CLOEXEC));
        if (result >= 0) return true;
        if (std.c.errno(result) != .INTR) return false;
    }
}

pub const PerfTelemetry = struct {
    fd: ?fd_t = null,
    write_fn: WriteFn = std.c.write,
    counters: Counters = .{},

    /// Initialize from `C3S_PERF_FD`; an absent or invalid value is disabled.
    pub fn initFromEnv() PerfTelemetry {
        const raw = std.c.getenv("C3S_PERF_FD") orelse return .{};
        const value = std.mem.span(raw);
        const fd = std.fmt.parseInt(fd_t, value, 10) catch return .{};
        if (fd < 0) return .{};
        return initFromFd(fd);
    }

    /// Take ownership of an inherited descriptor and immediately restore CLOEXEC.
    pub fn initFromFd(fd: ?fd_t) PerfTelemetry {
        return initWithWriteFn(fd, std.c.write);
    }

    fn initWithWriteFn(maybe_fd: ?fd_t, write_fn: WriteFn) PerfTelemetry {
        const fd = maybe_fd orelse return .{ .write_fn = write_fn };
        var result = PerfTelemetry{ .fd = fd, .write_fn = write_fn };
        if (!setCloseOnExec(fd)) {
            result.counters.write_faults = 1;
            result.disable();
        }
        return result;
    }

    /// Close the owned writer; repeated calls are harmless.
    pub fn deinit(self: *PerfTelemetry) void {
        self.disable();
    }

    /// Return whether future records can still be attempted.
    pub fn isEnabled(self: *const PerfTelemetry) bool {
        return self.fd != null;
    }

    /// Return a snapshot of records dropped or faulted by this writer.
    pub fn getCounters(self: *const PerfTelemetry) Counters {
        return self.counters;
    }

    /// Attempt one bounded event record without blocking or allocating.
    pub fn emit(self: *PerfTelemetry, event: Event) void {
        if (event.kind == .summary) {
            self.emitSummary(event);
            return;
        }
        self.emitRecord(event, null);
    }

    /// Attempt a final summary record containing the current counters.
    pub fn emitSummary(self: *PerfTelemetry, event: Event) void {
        var summary = event;
        summary.kind = .summary;
        self.emitRecord(summary, self.counters);
    }

    fn emitRecord(self: *PerfTelemetry, event: Event, counters: ?Counters) void {
        const fd = self.fd orelse return;
        var record = Record{};
        const bytes = encodeRecord(event, counters, &record) orelse {
            self.counters.dropped_oversize += 1;
            return;
        };

        while (true) {
            const written = self.write_fn(fd, bytes.ptr, bytes.len);
            if (written < 0) {
                switch (std.c.errno(written)) {
                    .INTR => continue,
                    .AGAIN => {
                        self.counters.dropped_eagain += 1;
                        return;
                    },
                    else => {
                        self.recordWriteFault();
                        return;
                    },
                }
            }
            if (written != bytes.len) {
                self.recordWriteFault();
            }
            return;
        }
    }

    fn recordWriteFault(self: *PerfTelemetry) void {
        self.counters.write_faults += 1;
        self.disable();
    }

    fn disable(self: *PerfTelemetry) void {
        if (self.fd) |fd| {
            _ = std.c.close(fd);
            self.fd = null;
        }
    }
};

fn testEvent(context: []const u8) Event {
    return .{
        .kind = .sync_start,
        .monotonic_ns = 1_000_000_000,
        .context = context,
        .resource = "pods",
        .scope = "all_namespaces",
        .generation = 7,
        .subscription_id = 3,
        .applied_revision = 11,
        .object_count = 128,
        .queue_bytes = 4096,
    };
}

fn openTestPipe() ![2]fd_t {
    var fds: [2]fd_t = undefined;
    if (std.c.pipe(&fds) != 0) return error.PipeFailed;
    return fds;
}

fn setNonblocking(fd: fd_t) !void {
    const flags = std.c.fcntl(fd, std.c.F.GETFL);
    if (flags < 0) return error.FcntlFailed;
    const nonblocking: c_int = @bitCast(std.c.O{ .NONBLOCK = true });
    if (std.c.fcntl(fd, std.c.F.SETFL, flags | nonblocking) != 0) return error.FcntlFailed;
}

test "disabled telemetry emits nothing without a descriptor" {
    var telemetry = PerfTelemetry.initFromFd(null);
    telemetry.emit(testEvent(""));

    try testing.expect(!telemetry.isEnabled());
    try testing.expectEqual(Counters{}, telemetry.getCounters());
}

test "ordinary startup without C3S_PERF_FD is silent" {
    if (std.c.getenv("C3S_PERF_FD") != null) return error.SkipZigTest;
    var telemetry = PerfTelemetry.initFromEnv();
    telemetry.emit(testEvent(""));

    try testing.expect(!telemetry.isEnabled());
    try testing.expectEqual(Counters{}, telemetry.getCounters());
}

test "initialization restores close-on-exec and owns descriptor closure" {
    const fds = try openTestPipe();
    defer _ = std.c.close(fds[0]);

    const inherited_flags = std.c.fcntl(fds[1], std.c.F.GETFD);
    try testing.expect(inherited_flags >= 0);
    try testing.expectEqual(
        @as(c_int, 0),
        std.c.fcntl(fds[1], std.c.F.SETFD, inherited_flags & ~@as(c_int, std.c.FD_CLOEXEC)),
    );

    const owned_fd = fds[1];
    var telemetry = PerfTelemetry.initFromFd(owned_fd);
    try testing.expect(telemetry.isEnabled());
    try testing.expect(std.c.fcntl(owned_fd, std.c.F.GETFD) & std.c.FD_CLOEXEC != 0);

    telemetry.deinit();
    telemetry.deinit();
    try testing.expectEqual(@as(c_int, -1), std.c.fcntl(owned_fd, std.c.F.GETFD));
    try testing.expectEqual(std.c.E.BADF, std.c.errno(-1));
}

const RecordingWriter = struct {
    var behavior: enum { success, eagain, short, interrupt_once, fault } = .success;
    var calls: usize = 0;
    var attempted_bytes: usize = 0;

    fn reset(next: @TypeOf(behavior)) void {
        behavior = next;
        calls = 0;
        attempted_bytes = 0;
    }

    fn write(_: fd_t, _: [*]const u8, len: usize) callconv(.c) isize {
        calls += 1;
        attempted_bytes = len;
        return switch (behavior) {
            .success => @intCast(len),
            .eagain => result: {
                std.c._errno().* = @intFromEnum(std.c.E.AGAIN);
                break :result -1;
            },
            .short => @intCast(len - 1),
            .interrupt_once => result: {
                if (calls == 1) {
                    std.c._errno().* = @intFromEnum(std.c.E.INTR);
                    break :result -1;
                }
                break :result @intCast(len);
            },
            .fault => result: {
                std.c._errno().* = @intFromEnum(std.c.E.PIPE);
                break :result -1;
            },
        };
    }
};

test "records fit one bounded write and oversize records are dropped before IO" {
    const fds = try openTestPipe();
    defer _ = std.c.close(fds[0]);

    RecordingWriter.reset(.success);
    var telemetry = PerfTelemetry.initWithWriteFn(fds[1], RecordingWriter.write);
    defer telemetry.deinit();

    telemetry.emit(testEvent(""));
    try testing.expectEqual(@as(usize, 1), RecordingWriter.calls);
    try testing.expect(RecordingWriter.attempted_bytes <= max_record_bytes);

    const oversized_context = [_]u8{'x'} ** max_record_bytes;
    telemetry.emit(testEvent(&oversized_context));
    try testing.expectEqual(@as(usize, 1), RecordingWriter.calls);
    try testing.expectEqual(@as(u64, 1), telemetry.getCounters().dropped_oversize);
}

test "EAGAIN drops one whole record without disabling telemetry" {
    const fds = try openTestPipe();
    defer _ = std.c.close(fds[0]);
    try setNonblocking(fds[1]);

    RecordingWriter.reset(.eagain);
    var telemetry = PerfTelemetry.initWithWriteFn(fds[1], RecordingWriter.write);
    defer telemetry.deinit();

    telemetry.emit(testEvent(""));
    try testing.expectEqual(@as(usize, 1), RecordingWriter.calls);
    try testing.expectEqual(@as(u64, 1), telemetry.getCounters().dropped_eagain);
    try testing.expectEqual(@as(u64, 0), telemetry.getCounters().write_faults);
    try testing.expect(telemetry.isEnabled());
}

test "EINTR retries the complete record only" {
    const fds = try openTestPipe();
    defer _ = std.c.close(fds[0]);

    RecordingWriter.reset(.interrupt_once);
    var telemetry = PerfTelemetry.initWithWriteFn(fds[1], RecordingWriter.write);
    defer telemetry.deinit();

    telemetry.emit(testEvent(""));
    try testing.expectEqual(@as(usize, 2), RecordingWriter.calls);
    try testing.expectEqual(Counters{}, telemetry.getCounters());
    try testing.expect(telemetry.isEnabled());
}

test "short write is never completed and permanently disables telemetry" {
    const fds = try openTestPipe();
    defer _ = std.c.close(fds[0]);

    RecordingWriter.reset(.short);
    var telemetry = PerfTelemetry.initWithWriteFn(fds[1], RecordingWriter.write);
    defer telemetry.deinit();

    telemetry.emit(testEvent(""));
    try testing.expectEqual(@as(usize, 1), RecordingWriter.calls);
    try testing.expectEqual(@as(u64, 1), telemetry.getCounters().write_faults);
    try testing.expect(!telemetry.isEnabled());

    telemetry.emit(testEvent(""));
    try testing.expectEqual(@as(usize, 1), RecordingWriter.calls);
}

test "non-EAGAIN write errors disable telemetry" {
    const fds = try openTestPipe();
    defer _ = std.c.close(fds[0]);

    RecordingWriter.reset(.fault);
    var telemetry = PerfTelemetry.initWithWriteFn(fds[1], RecordingWriter.write);
    defer telemetry.deinit();

    telemetry.emit(testEvent(""));
    try testing.expectEqual(@as(usize, 1), RecordingWriter.calls);
    try testing.expectEqual(@as(u64, 1), telemetry.getCounters().write_faults);
    try testing.expect(!telemetry.isEnabled());
}

test "summary includes accumulated counters in one complete NDJSON record" {
    const fds = try openTestPipe();
    defer _ = std.c.close(fds[0]);

    var telemetry = PerfTelemetry.initFromFd(fds[1]);
    defer telemetry.deinit();

    const oversized_context = [_]u8{'x'} ** max_record_bytes;
    telemetry.emit(testEvent(&oversized_context));
    telemetry.emitSummary(testEvent(""));

    var buf: [max_record_bytes]u8 = undefined;
    const read_len = std.c.read(fds[0], &buf, buf.len);
    try testing.expect(read_len > 0);
    const record = buf[0..@intCast(read_len)];
    try testing.expect(record.len <= max_record_bytes);
    try testing.expectEqual(@as(u8, '\n'), record[record.len - 1]);
    try testing.expect(std.mem.indexOf(u8, record, "\"event\":\"summary\"") != null);
    try testing.expect(std.mem.indexOf(u8, record, "\"dropped_oversize\":1") != null);
    try testing.expect(std.mem.indexOf(u8, record, "\"dropped_eagain\":0") != null);
    try testing.expect(std.mem.indexOf(u8, record, "\"write_faults\":0") != null);
}
