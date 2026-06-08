const std = @import("std");
const App = @import("app.zig").App;
const Cli = @import("cli.zig");
const Logger = @import("core/logger.zig");
const panic_hook = @import("panic_hook.zig");
const runtime = @import("core/runtime.zig");
const sys = @import("core/sys.zig");
const posix = std.posix;

/// Suppress debug/info spam from dependencies on stderr; c3s logs to file.
/// This affects ALL std.log calls in the entire program (including dependencies).
pub const std_options: std.Options = .{
    .log_level = .err,
};

// Zig 0.16: the runtime provides a std.process.Init with a managed allocator,
// a std.Io (thread pool + leak checking in debug), and command-line args.
// We publish the io globally via runtime.io so leaf modules can reach it.
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    runtime.io = init.io;

    defer {
        // The runtime deinits its debug allocator AFTER main returns and prints
        // any leak report to stderr. Redirect stderr to /dev/null on exit so it
        // doesn't pollute the TUI (leaks are captured in c3s.log). posix-only so
        // it stays valid after the runtime's io is torn down.
        if (sys.openWrite("/dev/null")) |fd| {
            sys.dup2(fd, posix.STDERR_FILENO);
            sys.close(fd);
        }
    }

    // Parse command line arguments
    const config = Cli.parseArgs(init.minimal.args, allocator) catch |err| {
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
