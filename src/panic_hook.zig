const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const sys = @import("core/sys.zig");
const clock = @import("core/clock.zig");

var log_file_path: ?[]const u8 = null;

pub fn setup(path: []const u8) void {
    log_file_path = path;
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    // Restore terminal state before anything else — exit raw mode and alternate screen
    // so the user's terminal is left clean even if we crash.
    restoreTerminal();

    // Redirect stderr to /dev/null so the default panic handler doesn't
    // dump a stack trace into the user's terminal. Raw fd ops via core/sys.zig
    // (std.posix.{open,dup2,close} were removed in Zig 0.16).
    if (sys.openWrite("/dev/null")) |fd| {
        sys.dup2(fd, posix.STDERR_FILENO);
        sys.close(fd);
    }

    // Log the panic message to our log file
    if (log_file_path) |path| {
        logPanicToFile(path, msg, error_return_trace, ret_addr) catch {};
    }

    // Call the default panic handler (output goes to /dev/null).
    // Zig 0.16: std.builtin.default_panic → std.debug.defaultPanic(msg, ret_addr).
    std.debug.defaultPanic(msg, ret_addr);
}

fn restoreTerminal() void {
    const stdout = std.Io.File.stdout();
    // Show cursor, exit alternate screen, end synchronized output.
    // Use raw fd writes (core/sys.zig) — std.posix.write was removed in 0.16.
    sys.writeAll(stdout.handle, "\x1b[?25h") catch {};
    sys.writeAll(stdout.handle, "\x1b[?1049l") catch {};
    sys.writeAll(stdout.handle, "\x1b[?2026l") catch {};

    // Restore original termios (disable raw mode).
    const stdin_handle = std.Io.File.stdin().handle;
    var termios = posix.tcgetattr(stdin_handle) catch return;
    // Re-enable canonical mode, echo, and signal processing
    termios.lflag.ECHO = true;
    termios.lflag.ICANON = true;
    termios.lflag.ISIG = true;
    termios.lflag.IEXTEN = true;
    termios.iflag.ICRNL = true;
    termios.iflag.IXON = true;
    termios.oflag.OPOST = true;
    posix.tcsetattr(stdin_handle, .FLUSH, termios) catch {};
}

fn logPanicToFile(path: []const u8, msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) !void {
    // Open the log file in append mode via libc (std.fs / std.Io would route
    // through the io thread pool, which must not be touched on the crash path).
    // sys.openAppend needs a null-terminated path.
    var path_buf: [std.Io.Dir.max_path_bytes:0]u8 = undefined;
    if (path.len >= path_buf.len) return error.NameTooLong;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    const fd = sys.openAppend(&path_buf) orelse return error.OpenFailed;
    defer sys.close(fd);

    // Write panic message (append mode means writes go to end of file).
    const timestamp = clock.timestamp();
    var buf: [512]u8 = undefined;
    const log_line = try std.fmt.bufPrint(&buf, "[{}] PANIC: {s}\n", .{ timestamp, msg });
    sys.writeAll(fd, log_line) catch {};

    // Write return address if available
    if (ret_addr) |addr| {
        var addr_buf: [128]u8 = undefined;
        const addr_line = std.fmt.bufPrint(&addr_buf, "[{}] PANIC: at address 0x{x}\n", .{ timestamp, addr }) catch return;
        sys.writeAll(fd, addr_line) catch {};
    }

    // Write stack trace if available
    if (error_return_trace) |trace| {
        var trace_buf: [256]u8 = undefined;
        const trace_line = std.fmt.bufPrint(&trace_buf, "[{}] PANIC: error return trace has {} frames\n", .{ timestamp, trace.index }) catch return;
        sys.writeAll(fd, trace_line) catch {};
    }
}
