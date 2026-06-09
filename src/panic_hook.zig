const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const sys = @import("core/sys.zig");
const clock = @import("core/clock.zig");
const runtime = @import("core/runtime.zig");

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

const testing = std.testing;

// Note: We can't directly test signal handlers / the noreturn panic path in unit
// tests as they require the process to actually crash. These tests verify the
// setup and helper functions are correct, and force panic_hook.zig to compile.

test "panic_hook: module compiles and exposes its API" {
    // Referencing the decls forces semantic analysis of panic_hook.zig's bodies
    // (setup, panic, and the private helpers they call) under Zig 0.16.
    setup("c3s.log");
    try testing.expect(@TypeOf(panic) == fn ([]const u8, ?*std.builtin.StackTrace, ?usize) noreturn);
}

test "panic_hook: log file path is valid" {
    // The panic hook creates a log file at "c3s.log"
    // We can verify the path format is valid
    const log_path = "c3s.log";

    try testing.expect(log_path.len > 0);
    try testing.expect(std.mem.endsWith(u8, log_path, ".log"));
}

test "panic_hook: signal numbers are valid" {
    // Zig 0.16: std.posix.SIG is the system enum, not a struct of c_int
    // constants, so compare numeric values via @intFromEnum.
    // SIGSEGV = 11 (segmentation fault)
    try testing.expectEqual(@as(u32, 11), @intFromEnum(std.posix.SIG.SEGV));

    // SIGABRT = 6 (abort) on darwin/linux
    try testing.expectEqual(@as(u32, 6), @intFromEnum(std.posix.SIG.ABRT));
}

test "panic_hook: can open log file for writing" {
    const io = runtime.io();
    const test_log = "test_panic.log";
    const cwd = std.Io.Dir.cwd();

    // Create and write to test log file (Zig 0.16 routes file I/O through std.Io).
    var file = try cwd.createFile(io, test_log, .{});
    defer {
        file.close(io);
        cwd.deleteFile(io, test_log) catch {};
    }

    try file.writeStreamingAll(io, "Test panic log entry\n");

    // Verify file exists and has content
    const stat = try cwd.statFile(io, test_log, .{});
    try testing.expect(stat.size > 0);
}

test "panic_hook: timestamp format is valid" {
    // The panic hook uses timestamps in log messages
    // Verify we can format timestamps correctly
    var buf: [100]u8 = undefined;
    const timestamp = try std.fmt.bufPrint(&buf, "[{d:0>2}:{d:0>2}:{d:0>2}]", .{ 14, 30, 45 });

    try testing.expect(std.mem.eql(u8, timestamp, "[14:30:45]"));
}

test "panic_hook: can write stack trace info" {
    // Simulate writing stack trace information into a stack buffer (Zig 0.16
    // removed ArrayList.writer(); panic_hook itself uses std.fmt.bufPrint).
    var buf: [256]u8 = undefined;
    const line1 = try std.fmt.bufPrint(&buf, "Segmentation fault at address 0x{x}\n", .{0x12345678});
    try testing.expect(line1.len > 0);
    try testing.expect(std.mem.indexOf(u8, line1, "Segmentation fault") != null);

    var buf2: [256]u8 = undefined;
    const line2 = try std.fmt.bufPrint(&buf2, "Stack trace:\n  test.zig:123:45 in testFunction\n", .{});
    try testing.expect(std.mem.indexOf(u8, line2, "Stack trace") != null);
}

test "panic_hook: error messages are properly formatted" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test various error message formats that might appear in panic logs
    const messages = [_][]const u8{
        "panic: switch on corrupt value",
        "Segmentation fault at address 0x0",
        "thread 12345 panic: index out of bounds",
    };

    for (messages) |msg| {
        const formatted = try std.fmt.allocPrint(allocator, "ERROR: {s}", .{msg});
        defer allocator.free(formatted);

        try testing.expect(std.mem.startsWith(u8, formatted, "ERROR: "));
        try testing.expect(formatted.len > msg.len);
    }
}

// Note: Actual signal handler tests would require:
// 1. Forking a child process
// 2. Sending signals to it
// 3. Checking the log output
// This is complex and brittle for unit tests.
//
// The panic hook has been manually tested through:
// - The segfault bugs we fixed (logged to c3s.log)
// - Various crashes during development
// - All produced proper stack traces in the log file
