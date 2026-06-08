//! Thin libc-backed file-descriptor helpers.
//!
//! Zig 0.16 removed the blocking `std.posix.{write,close,dup2,open,isatty}`
//! wrappers — general I/O now flows through `std.Io`. c3s links libc, so we
//! wrap the C calls here for the handful of low-level fd operations on hot or
//! crash paths that intentionally bypass `std.Io`: the terminal frame flush
//! (latency-sensitive), the log-file append, and the panic/exit stderr
//! redirect (must work without the io thread pool).
const std = @import("std");
const fd_t = std.c.fd_t;

pub const WriteError = error{WriteFailed};

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
