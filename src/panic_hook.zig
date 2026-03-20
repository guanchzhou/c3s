const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

var log_file_path: ?[]const u8 = null;

pub fn setup(path: []const u8) void {
    log_file_path = path;
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    // Restore terminal state before anything else — exit raw mode and alternate screen
    // so the user's terminal is left clean even if we crash.
    restoreTerminal();

    // Redirect stderr to /dev/null so the default panic handler doesn't
    // dump a stack trace into the user's terminal.
    const devnull = std.fs.openFileAbsolute("/dev/null", .{ .mode = .write_only }) catch null;
    if (devnull) |f| {
        posix.dup2(f.handle, posix.STDERR_FILENO) catch {};
        f.close();
    }

    // Log the panic message to our log file
    if (log_file_path) |path| {
        logPanicToFile(path, msg, error_return_trace, ret_addr) catch {};
    }

    // Call the default panic handler (output goes to /dev/null)
    std.builtin.default_panic(msg, error_return_trace, ret_addr);
}

fn restoreTerminal() void {
    const stdout = std.io.getStdOut();
    // Show cursor
    stdout.writeAll("\x1b[?25h") catch {};
    // Exit alternate screen
    stdout.writeAll("\x1b[?1049l") catch {};
    // End synchronized output
    stdout.writeAll("\x1b[?2026l") catch {};

    // Restore original termios (disable raw mode)
    // Read the original termios that Terminal.init() saved
    const stdin_handle = std.io.getStdIn().handle;
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
    const file = try std.fs.cwd().openFile(path, .{
        .mode = .read_write,
    });
    defer file.close();

    // Seek to end
    try file.seekFromEnd(0);

    // Write panic message
    const timestamp = std.time.timestamp();
    var buf: [512]u8 = undefined;
    const log_line = try std.fmt.bufPrint(&buf, "[{}] PANIC: {s}\n", .{ timestamp, msg });
    try file.writeAll(log_line);

    // Write return address if available
    if (ret_addr) |addr| {
        var addr_buf: [128]u8 = undefined;
        const addr_line = std.fmt.bufPrint(&addr_buf, "[{}] PANIC: at address 0x{x}\n", .{ timestamp, addr }) catch return;
        file.writeAll(addr_line) catch {};
    }

    // Write stack trace if available
    if (error_return_trace) |trace| {
        var trace_buf: [256]u8 = undefined;
        const trace_line = std.fmt.bufPrint(&trace_buf, "[{}] PANIC: error return trace has {} frames\n", .{ timestamp, trace.index }) catch return;
        file.writeAll(trace_line) catch {};
    }
}
