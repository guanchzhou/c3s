const std = @import("std");
const testing = std.testing;
const Logger = @import("logger");

test "logger writes to file" {
    const allocator = testing.allocator;
    
    // Create temp directory for test
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    // Get the temp path
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    // Set XDG_STATE_HOME to temp directory
    try std.process.setEnvVar("XDG_STATE_HOME", tmp_path);
    
    // Initialize logger
    try Logger.initGlobalLogger(.info);
    defer Logger.deinitGlobalLogger();
    
    // Write a log message
    Logger.info("Test log message: {s}", .{"hello"});
    
    // Read log file and verify content
    const log_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "c3s", "c3s.log" });
    defer allocator.free(log_path);
    
    const log_content = try std.fs.cwd().readFileAlloc(allocator, log_path, 1024 * 1024);
    defer allocator.free(log_content);
    
    // Verify log contains our message
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "INFO"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "Test log message: hello"));
}

test "logger respects log level" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    try std.process.setEnvVar("XDG_STATE_HOME", tmp_path);
    
    // Initialize with WARN level
    try Logger.initGlobalLogger(.warn);
    defer Logger.deinitGlobalLogger();
    
    // Debug and Info should not be logged
    Logger.debug("Debug message", .{});
    Logger.info("Info message", .{});
    
    // Warn and Error should be logged
    Logger.warn("Warn message", .{});
    Logger.err("Error message", .{});
    
    const log_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "c3s", "c3s.log" });
    defer allocator.free(log_path);
    
    const log_content = try std.fs.cwd().readFileAlloc(allocator, log_path, 1024 * 1024);
    defer allocator.free(log_content);
    
    // Should not contain debug/info
    try testing.expect(!std.mem.containsAtLeast(u8, log_content, 1, "Debug message"));
    try testing.expect(!std.mem.containsAtLeast(u8, log_content, 1, "Info message"));
    
    // Should contain warn/error
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "Warn message"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "Error message"));
}

test "logger appends to existing file" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    try std.process.setEnvVar("XDG_STATE_HOME", tmp_path);
    
    // First logger session
    try Logger.initGlobalLogger(.info);
    Logger.info("First message", .{});
    Logger.deinitGlobalLogger();
    
    // Second logger session
    try Logger.initGlobalLogger(.info);
    defer Logger.deinitGlobalLogger();
    Logger.info("Second message", .{});
    
    // Read log file
    const log_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "c3s", "c3s.log" });
    defer allocator.free(log_path);
    
    const log_content = try std.fs.cwd().readFileAlloc(allocator, log_path, 1024 * 1024);
    defer allocator.free(log_content);
    
    // Should contain both messages
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "First message"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "Second message"));
}
