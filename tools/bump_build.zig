const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const cwd = std.fs.cwd();
    var file = cwd.createFile(".build_number.tmp", .{ .read = true, .truncate = true }) catch |e| switch (e) {
        error.PathAlreadyExists => try cwd.openFile(".build_number.tmp", .{ .mode = .read_write }),
        else => return e,
    };
    defer file.close();

    var current: u64 = 0;
    if (cwd.openFile(".build_number", .{})) |in| {
        defer in.close();
        const data = try in.readToEndAlloc(allocator, 64);
        defer allocator.free(data);
        const trimmed = std.mem.trim(u8, data, " \n\r\t");
        if (trimmed.len > 0) {
            current = std.fmt.parseInt(u64, trimmed, 10) catch 0;
        }
    } else |_| {}

    const next = current + 1;
    var buf: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "{d}\n", .{next});
    try file.writeAll(s);

    // Atomically replace
    try cwd.rename(".build_number.tmp", ".build_number");

    // Print for logs
    var stdout_buf: [4096]u8 = undefined;
    var out = std.fs.File.stdout().writer(&stdout_buf);
    try out.print("bumped build number to {d}\n", .{next});
}
