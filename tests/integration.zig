const std = @import("std");
const testing = std.testing;
const App = @import("src").App;
const Terminal = @import("src").Terminal;
const Header = @import("src").Header;
const PodsView = @import("src").PodsView;
const Footer = @import("src").Footer;

test "full application integration test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test complete application initialization
    var app = try App.init(allocator);
    defer app.deinit();

    // Test that all components are properly initialized
    try testing.expect(app.running == true);
    try testing.expect(app.body.pods.items.len > 0);
    try testing.expect(std.mem.eql(u8, app.header.context, "rancher-desktop [RW]"));
    try testing.expect(std.mem.eql(u8, app.footer.current_resource, "pod"));
}

test "component rendering integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    var header = try Header.init(allocator);
    defer header.deinit();

    var body = try Body.init(allocator);
    defer body.deinit();

    var footer = try Footer.init(allocator);
    defer footer.deinit();

    // Test that all components can render without crashing
    try header.render(&terminal, 0, 0, 80, 8);
    try body.render(&terminal, 0, 8, 80, 15);
    try footer.render(&terminal, 0, 23, 80, 1);

    // Test rendering with different layouts
    try header.render(&terminal, 0, 0, 120, 10);
    try body.render(&terminal, 0, 10, 120, 20);
    try footer.render(&terminal, 0, 30, 120, 1);
}

test "navigation integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var body = try Body.init(allocator);
    defer body.deinit();

    const initial_selected = body.selected_row;
    const initial_scroll = body.scroll_offset;

    // Test navigation sequence
    try body.navigateDown();
    try body.navigateDown();
    try body.navigateUp();
    try body.navigateUp();
    
    // Test that we're back to initial state
    try testing.expect(body.selected_row == initial_selected);
    try testing.expect(body.scroll_offset == initial_scroll);

    // Test left/right navigation
    try body.navigateLeft();
    try body.navigateRight();
}

test "memory allocation integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test multiple app creation and destruction cycles
    for (0..3) |_| {
        var app = try App.init(allocator);
        app.deinit();
    }

    // Test that no memory leaks occurred
    const allocated = gpa.deinit();
    try testing.expect(allocated == .ok);
}

test "terminal and component integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    var app = try App.init(allocator);
    defer app.deinit();

    // Test that terminal operations work with components
    try terminal.clear();
    try terminal.hideCursor();
    
    // Test component rendering through terminal
    try app.header.render(&terminal, 0, 0, 80, 8);
    try app.body.render(&terminal, 0, 8, 80, 15);
    try app.footer.render(&terminal, 0, 23, 80, 1);
    
    try terminal.showCursor();
    try terminal.flush();
}

test "error handling integration" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test that components handle edge cases gracefully
    var body = try Body.init(allocator);
    defer body.deinit();

    // Test navigation at boundaries
    body.selected_row = 0;
    try body.navigateUp(); // Should not crash
    try testing.expect(body.selected_row >= 0);

    body.selected_row = body.pods.items.len - 1;
    try body.navigateDown(); // Should not crash
    try testing.expect(body.selected_row < body.pods.items.len);
}
