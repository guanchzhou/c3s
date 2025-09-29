const std = @import("std");
const App = @import("app.zig").App;
const Cli = @import("cli.zig");
const Logger = @import("logger.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const config = Cli.parseArgs(allocator) catch |err| {
        std.log.err("Failed to parse arguments: {}", .{err});
        std.process.exit(1);
    };

    // Initialize logging
    const log_level = if (std.mem.eql(u8, config.log_level, "debug")) Logger.LogLevel.debug
        else if (std.mem.eql(u8, config.log_level, "warn")) Logger.LogLevel.warn
        else if (std.mem.eql(u8, config.log_level, "error")) Logger.LogLevel.err
        else Logger.LogLevel.info;
    
    try Logger.initGlobalLogger(allocator, log_level);
    defer Logger.deinitGlobalLogger();

    Logger.info("C3S starting up...", .{});

    // Initialize the TUI application with config
    var app = try App.init(allocator, config);
    defer app.deinit();

    // Run the main application loop
    try app.run();
}