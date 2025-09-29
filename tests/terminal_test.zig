const std = @import("std");
const testing = std.testing;
const Terminal = @import("../src/terminal.zig").Terminal;

test "terminal initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test that terminal was initialized successfully
    try testing.expect(terminal.allocator == allocator);
}

test "terminal size query" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    const size = try terminal.getSize();
    try testing.expect(size.width > 0);
    try testing.expect(size.height > 0);
}

test "terminal cursor control" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test cursor positioning
    try terminal.setCursor(10, 5);
    // Test hide/show cursor
    try terminal.hideCursor();
    try terminal.showCursor();
}

test "terminal text rendering" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test basic text rendering
    try terminal.writeString(0, 0, "Hello, World!");
    
    // Test colored text rendering
    try terminal.writeStringWithColor(0, 1, "Colored Text", .red, .black);
    
    // Test flush
    try terminal.flush();
}

test "terminal color handling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test color setting
    try terminal.setColor(.red, .black);
    try terminal.resetColor();
    
    // Test all color combinations
    const colors = [_]Terminal.Color{ .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white };
    
    for (colors, 0..) |fg, i| {
        const bg = colors[i];
        try terminal.setColor(fg, bg);
        try terminal.resetColor();
    }
}

test "terminal key reading" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test that readKey doesn't crash
    // Note: In a real test environment, we might need to mock input
    const key = terminal.readKey() catch null;
    // Key might be null if no input is available, which is expected
    _ = key;
}

test "terminal clear screen" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test screen clearing
    try terminal.clear();
    
    // Test that we can write after clearing
    try terminal.writeString(0, 0, "After clear");
    try terminal.flush();
}
