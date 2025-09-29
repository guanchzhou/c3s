const std = @import("std");
const builtin = @import("builtin");

var log_file_path: ?[]const u8 = null;

pub fn setup(path: []const u8) void {
    log_file_path = path;
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    // Try to log the panic message to file
    if (log_file_path) |path| {
        logPanicToFile(path, msg) catch {};
    }
    
    // Call the default panic handler
    std.builtin.default_panic(msg, error_return_trace, ret_addr);
}

fn logPanicToFile(path: []const u8, msg: []const u8) !void {
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
}
