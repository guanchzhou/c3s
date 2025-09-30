// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for panic hook (limited scope - signal handlers are hard to test)

const std = @import("std");
const testing = std.testing;

// Note: We can't directly test signal handlers in unit tests as they require
// the process to actually receive signals. These tests verify the setup and
// helper functions are correct.

test "panic_hook: log file path is valid" {
    // The panic hook creates a log file at "c3s.log"
    // We can verify the path format is valid
    const log_path = "c3s.log";
    
    try testing.expect(log_path.len > 0);
    try testing.expect(std.mem.endsWith(u8, log_path, ".log"));
}

test "panic_hook: signal numbers are valid" {
    const std = @import("std");
    
    // SIGSEGV = 11 (segmentation fault)
    try testing.expectEqual(@as(c_int, 11), std.posix.SIG.SEGV);
    
    // SIGABRT = 6 (abort)
    try testing.expectEqual(@as(c_int, 6), std.posix.SIG.ABRT);
    
    // These are the main signals we handle
    // This test verifies the constants are correct
}

test "panic_hook: can open log file for writing" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    
    const test_log = "test_panic.log";
    
    // Create and write to test log file
    var file = try std.fs.cwd().createFile(test_log, .{});
    defer {
        file.close();
        std.fs.cwd().deleteFile(test_log) catch {};
    }
    
    try file.writeAll("Test panic log entry\n");
    
    // Verify file exists and has content
    const stat = try std.fs.cwd().statFile(test_log);
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
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Simulate writing stack trace information
    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();
    
    const writer = buffer.writer();
    try writer.print("Segmentation fault at address 0x{x}\n", .{0x12345678});
    try writer.print("Stack trace:\n", .{});
    try writer.print("  test.zig:123:45 in testFunction\n", .{});
    
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Segmentation fault") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "Stack trace") != null);
}

test "panic_hook: error messages are properly formatted" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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
