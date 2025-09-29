const std = @import("std");

// Test that we can import and use our modules
const Terminal = @import("src/terminal.zig").Terminal;
const Header = @import("src/header.zig").Header;
const Body = @import("src/body.zig").Body;
const Footer = @import("src/footer.zig").Footer;
const App = @import("src/app.zig").App;

pub fn main() !void {
    std.debug.print("Testing C3S compilation...\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test terminal initialization
    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();
    std.debug.print("✅ Terminal initialized\n", .{});
    
    // Test header initialization
    var header = try Header.init(allocator);
    defer header.deinit();
    std.debug.print("✅ Header initialized\n", .{});
    
    // Test body initialization
    var body = try Body.init(allocator);
    defer body.deinit();
    std.debug.print("✅ Body initialized\n", .{});
    
    // Test footer initialization
    var footer = try Footer.init(allocator);
    defer footer.deinit();
    std.debug.print("✅ Footer initialized\n", .{});
    
    // Test app initialization
    var app = try App.init(allocator);
    defer app.deinit();
    std.debug.print("✅ App initialized\n", .{});
    
    // Test basic functionality
    const size = try terminal.getSize();
    std.debug.print("✅ Terminal size: {}x{}\n", .{ size.width, size.height });
    
    // Test navigation
    try body.navigateDown();
    try body.navigateUp();
    std.debug.print("✅ Navigation works\n", .{});
    
    std.debug.print("🎉 All compilation tests passed!\n", .{});
}
