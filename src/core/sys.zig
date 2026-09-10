//! Thin libc-backed file-descriptor helpers.
//!
//! Zig 0.16 removed the blocking `std.posix.{write,close,dup2,open,isatty}`
//! wrappers — general I/O now flows through `std.Io`. c3s links libc, so we
//! wrap the C calls here for the handful of low-level fd operations on hot or
//! crash paths that intentionally bypass `std.Io`: the terminal frame flush
//! (latency-sensitive), the log-file append, and the panic/exit stderr
//! redirect (must work without the io thread pool).
const std = @import("std");
pub const fd_t = std.c.fd_t;

pub const WriteError = error{WriteFailed};

pub const PollReadiness = enum {
    timeout,
    input,
    wakeup,
    both,
};

pub const PollDescriptorEvents = struct {
    raw: i16 = 0,
    readable: bool = false,
    hangup: bool = false,
    errored: bool = false,
    invalid: bool = false,

    pub fn hasAny(self: PollDescriptorEvents) bool {
        return self.raw != 0;
    }

    pub fn isTerminal(self: PollDescriptorEvents) bool {
        return self.hangup or self.errored or self.invalid;
    }

    fn fromRaw(raw: i16) PollDescriptorEvents {
        return .{
            .raw = raw,
            .readable = (raw & std.posix.POLL.IN) != 0,
            .hangup = (raw & std.posix.POLL.HUP) != 0,
            .errored = (raw & std.posix.POLL.ERR) != 0,
            .invalid = (raw & std.posix.POLL.NVAL) != 0,
        };
    }
};

pub const PollInputAndWakeupResult = struct {
    readiness: PollReadiness,
    input: PollDescriptorEvents,
    wakeup: PollDescriptorEvents,
};

/// Poll stdin and a wakeup descriptor while retaining per-descriptor flags.
pub fn pollInputAndWakeup(
    stdin_fd: fd_t,
    wakeup_fd: fd_t,
    timeout_ms: i32,
) std.posix.PollError!PollInputAndWakeupResult {
    var poll_fds = [_]std.posix.pollfd{
        .{ .fd = stdin_fd, .events = std.posix.POLL.IN, .revents = 0 },
        .{ .fd = wakeup_fd, .events = std.posix.POLL.IN, .revents = 0 },
    };
    _ = try std.posix.poll(&poll_fds, timeout_ms);

    const input = PollDescriptorEvents.fromRaw(poll_fds[0].revents);
    const wakeup = PollDescriptorEvents.fromRaw(poll_fds[1].revents);
    const readiness: PollReadiness = if (input.hasAny() and wakeup.hasAny())
        .both
    else if (input.hasAny())
        .input
    else if (wakeup.hasAny())
        .wakeup
    else
        .timeout;

    return .{
        .readiness = readiness,
        .input = input,
        .wakeup = wakeup,
    };
}

/// Write all bytes to `fd`, retrying short writes. Returns error.WriteFailed on
/// a write error; callers on best-effort paths (render/log) just `catch {}`.
pub fn writeAll(fd: fd_t, bytes: []const u8) WriteError!void {
    var off: usize = 0;
    while (off < bytes.len) {
        const n = std.c.write(fd, bytes.ptr + off, bytes.len - off);
        if (n < 0) return error.WriteFailed;
        if (n == 0) break;
        off += @intCast(n);
    }
}

pub fn close(fd: fd_t) void {
    _ = std.c.close(fd);
}

pub fn dup2(old_fd: fd_t, new_fd: fd_t) void {
    _ = std.c.dup2(old_fd, new_fd);
}

pub fn isatty(fd: fd_t) bool {
    return std.c.isatty(fd) != 0;
}

/// Open `path` write-only, creating it if absent, in append mode.
/// Returns the fd, or null on failure.
pub fn openAppend(path: [*:0]const u8) ?fd_t {
    const rc = std.c.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true }, @as(std.c.mode_t, 0o644));
    return if (rc < 0) null else rc;
}

/// Open an existing `path` write-only (e.g. /dev/null for redirects).
/// Returns the fd, or null on failure.
pub fn openWrite(path: [*:0]const u8) ?fd_t {
    const rc = std.c.open(path, .{ .ACCMODE = .WRONLY }, @as(std.c.mode_t, 0));
    return if (rc < 0) null else rc;
}

const Wakeup = @import("Wakeup.zig").Wakeup;

test "poll distinguishes timeout input wakeup and both" {
    var input = try Wakeup.init();
    defer input.deinit();
    var wakeup = try Wakeup.init();
    defer wakeup.deinit();

    const timed_out = try pollInputAndWakeup(input.readHandle(), wakeup.readHandle(), 0);
    try std.testing.expectEqual(PollReadiness.timeout, timed_out.readiness);
    try std.testing.expect(!timed_out.input.hasAny());
    try std.testing.expect(!timed_out.wakeup.hasAny());

    input.notify();
    const input_ready = try pollInputAndWakeup(input.readHandle(), wakeup.readHandle(), 0);
    try std.testing.expectEqual(PollReadiness.input, input_ready.readiness);
    try std.testing.expect(input_ready.input.readable);
    try std.testing.expect(!input_ready.wakeup.hasAny());
    input.drain();

    wakeup.notify();
    const wakeup_ready = try pollInputAndWakeup(input.readHandle(), wakeup.readHandle(), 0);
    try std.testing.expectEqual(PollReadiness.wakeup, wakeup_ready.readiness);
    try std.testing.expect(!wakeup_ready.input.hasAny());
    try std.testing.expect(wakeup_ready.wakeup.readable);
    wakeup.drain();

    input.notify();
    wakeup.notify();
    const both_ready = try pollInputAndWakeup(input.readHandle(), wakeup.readHandle(), 0);
    try std.testing.expectEqual(PollReadiness.both, both_ready.readiness);
    try std.testing.expect(both_ready.input.readable);
    try std.testing.expect(both_ready.wakeup.readable);
}

test "poll reports terminal flags for either descriptor" {
    var wakeup = try Wakeup.init();
    defer wakeup.deinit();

    var hangup_pair: [2]fd_t = undefined;
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &hangup_pair),
    );
    defer _ = std.c.close(hangup_pair[0]);
    _ = std.c.close(hangup_pair[1]);

    const hangup = try pollInputAndWakeup(hangup_pair[0], wakeup.readHandle(), 0);
    try std.testing.expectEqual(PollReadiness.input, hangup.readiness);
    try std.testing.expect(hangup.input.hangup);
    try std.testing.expect(hangup.input.isTerminal());

    var invalid_pair: [2]fd_t = undefined;
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.socketpair(std.c.AF.UNIX, std.c.SOCK.STREAM, 0, &invalid_pair),
    );
    const invalid_fd = invalid_pair[0];
    _ = std.c.close(invalid_pair[0]);
    _ = std.c.close(invalid_pair[1]);

    const invalid_input = try pollInputAndWakeup(invalid_fd, wakeup.readHandle(), 0);
    try std.testing.expectEqual(PollReadiness.input, invalid_input.readiness);
    try std.testing.expect(invalid_input.input.invalid);
    try std.testing.expect(invalid_input.input.isTerminal());

    const invalid_wakeup = try pollInputAndWakeup(wakeup.readHandle(), invalid_fd, 0);
    try std.testing.expectEqual(PollReadiness.wakeup, invalid_wakeup.readiness);
    try std.testing.expect(invalid_wakeup.wakeup.invalid);
    try std.testing.expect(invalid_wakeup.wakeup.isTerminal());
}
