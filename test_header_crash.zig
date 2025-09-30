const std = @import("std");
const Header = @import("src/ui/header.zig").Header;
const Terminal = @import("src/core/terminal.zig").Terminal;
const theme_loader = @import("src/model/theme_loader.zig");
const hints_model = @import("src/model/hints.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(allocator, theme);
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Get the ACTUAL hints that cause the crash
    const hints = hints_model.podsHints();

    std.debug.print("Testing header render with pods hints...\n", .{});
    std.debug.print("Number of hints: {}\n", .{hints.hints.len});
    
    // Test at width that causes the crash
    std.debug.print("Rendering at width 120...\n", .{});
    try header.render(&terminal, 0, 0, 120, 5, hints);
    
    std.debug.print("✅ SUCCESS! No crash!\n", .{});
}
