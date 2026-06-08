const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Zig 0.16: file I/O flows through std.Io; this standalone build tool owns
    // its own thread-pool io.
    var threaded = std.Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();
    const cwd = std.Io.Dir.cwd();

    var current: u64 = 0;
    if (cwd.readFileAlloc(io, ".build_number", allocator, .limited(64))) |data| {
        defer allocator.free(data);
        const trimmed = std.mem.trim(u8, data, " \n\r\t");
        if (trimmed.len > 0) current = std.fmt.parseInt(u64, trimmed, 10) catch 0;
    } else |_| {}

    const next = current + 1;
    var buf: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "{d}\n", .{next});
    try cwd.writeFile(io, .{ .sub_path = ".build_number", .data = s });

    std.debug.print("bumped build number to {d}\n", .{next});
}
