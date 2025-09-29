const std = @import("std");
const testing = std.testing;
const App = @import("../src/app.zig").App;

test "app initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();

    // Test that app was initialized successfully
    try testing.expect(app.allocator == allocator);
    try testing.expect(app.running == true);
}

test "app component initialization" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();

    // Test that all components were initialized
    // Header component
    try testing.expect(std.mem.eql(u8, app.header.context, "rancher-desktop [RW]"));
    
    // Body component
    try testing.expect(app.body.pods.items.len > 0);
    
    // Footer component
    try testing.expect(std.mem.eql(u8, app.footer.current_resource, "pod"));
}

test "app memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test multiple initialization and cleanup cycles
    for (0..5) |_| {
        var app = try App.init(allocator);
        app.deinit();
    }
    
    // Test that no memory leaks occurred
    const allocated = gpa.deinit();
    try testing.expect(allocated == .ok);
}

test "app state management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();

    // Test initial state
    try testing.expect(app.running == true);
    
    // Test state change
    app.running = false;
    try testing.expect(app.running == false);
}

test "app component interaction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();

    // Test that components can be accessed and modified
    const initial_selected = app.body.selected_row;
    
    // Test navigation through app
    try app.body.navigateDown();
    if (app.body.pods.items.len > 1) {
        try testing.expect(app.body.selected_row == initial_selected + 1);
    }
    
    try app.body.navigateUp();
    try testing.expect(app.body.selected_row == initial_selected);
}
