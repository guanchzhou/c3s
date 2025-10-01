const std = @import("std");
const App = @import("app.zig").App;
const Cli = @import("cli.zig");
const Logger = @import("core/logger.zig");
const panic_hook = @import("panic_hook.zig");
const posix = std.posix;

/// Configure global logging to suppress debug spam from zig-yaml dependency
/// This affects ALL std.log calls in the entire program (including dependencies)
pub const std_options: std.Options = .{
    .log_level = .err,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

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
