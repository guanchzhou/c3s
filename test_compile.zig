const std = @import("std");

// Test that all our modules can be imported
const Terminal = @import("src/terminal.zig").Terminal;
const Header = @import("src/header.zig").Header;
const Body = @import("src/body.zig").Body;
const Footer = @import("src/footer.zig").Footer;
const App = @import("src/app.zig").App;

pub fn main() !void {
    std.debug.print("✅ All modules imported successfully!\n", .{});
    
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    // Test that we can initialize all components
    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();
    
    var header = try Header.init(allocator);
    defer header.deinit();
    
    var body = try Body.init(allocator);
    defer body.deinit();
    
    var footer = try Footer.init(allocator);
    defer footer.deinit();
    
    var app = try App.init(allocator);
    defer app.deinit();
    
    std.debug.print("✅ All components initialized successfully!\n", .{});
    std.debug.print("✅ C3S TUI application is ready to run!\n", .{});
}
