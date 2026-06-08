const std = @import("std");
const App = @import("app.zig").App;
const Cli = @import("cli.zig");
const Logger = @import("core/logger.zig");
const panic_hook = @import("panic_hook.zig");
const runtime = @import("core/runtime.zig");
const posix = std.posix;

/// Suppress debug/info spam from dependencies on stderr; c3s logs to file.
/// This affects ALL std.log calls in the entire program (including dependencies).
pub const std_options: std.Options = .{
    .log_level = .err,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        // Redirect stderr to /dev/null before GPA deinit so leak reports
        // don't pollute the user's terminal. Leaks are logged in c3s.log.
        // Uses posix directly (no std.Io) so it stays valid after the global
        // io's thread pool has been torn down.
        if (posix.open("/dev/null", .{ .ACCMODE = .WRONLY }, 0)) |fd| {
            posix.dup2(fd, posix.STDERR_FILENO) catch {};
            posix.close(fd);
        } else |_| {}
        _ = gpa.deinit();
    }
    const allocator = gpa.allocator();

    // Zig 0.16: own one std.Io for the whole program (file I/O, subprocess,
    // k8s client). Published via runtime.io. Must outlive every io operation,
    // so its deinit defer is declared before logger/app (LIFO → runs after).
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    runtime.io = threaded.io();

    // Set up signal handlers for graceful shutdown
    // Default system signal handling is sufficient for now.

    // Parse command line arguments
    const config = Cli.parseArgs(allocator) catch |err| {
        // Use std.log.err here because Logger might not be fully initialized or might be corrupted.
        std.log.err("Failed to parse arguments: {}", .{err});
        std.process.exit(1);
    };

    // Initialize logging
    const log_level = if (std.mem.eql(u8, config.log_level, "debug")) Logger.LogLevel.debug else if (std.mem.eql(u8, config.log_level, "warn")) Logger.LogLevel.warn else if (std.mem.eql(u8, config.log_level, "error")) Logger.LogLevel.err else Logger.LogLevel.info;

    try Logger.initGlobalLogger(log_level);
    defer Logger.deinitGlobalLogger();

    // Setup panic hook to log panics to file
    if (Logger.getLogFilePath()) |log_path| {
        panic_hook.setup(log_path);
    }

    Logger.info("C3S starting up...", .{});

    // Initialize the TUI application with config
    var app = try App.init(allocator, config);
    defer app.deinit();

    // Run the main application loop
    try app.run();
}
