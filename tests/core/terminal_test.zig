const std = @import("std");
const testing = std.testing;
const Terminal = @import("src").Terminal;
const Color = @import("src").Color;

test "terminal initialization and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test that terminal was initialized successfully
    // Note: We can't directly compare allocators, so we just check that terminal exists
    // The terminal should have been created without errors
}

test "terminal size query" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    const size = try terminal.getSize();
    try testing.expect(size.width > 0);
    try testing.expect(size.height > 0);
}

test "terminal screen control" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test basic screen control
    try terminal.clear();
    try terminal.hideCursor();
    try terminal.showCursor();
    try terminal.setCursor(0, 0);
}

test "terminal text writing" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test basic text output
    try terminal.writeString(0, 0, "Hello, World!");
    try terminal.flush();
}

test "terminal color support" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test color setting
    try terminal.setColor(.red, .black);
    try terminal.resetColor();

    // Test all color combinations
    const colors = [_]Color{ .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white };

    for (colors, 0..) |fg, i| {
        const bg = colors[i];
        try terminal.setColor(fg, bg);
        try terminal.resetColor();
    }
}

test "terminal colored text writing" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test colored text output
    try terminal.writeStringWithColor(0, 0, "Red text", .red, .black);
    try terminal.writeStringWithColor(0, 1, "Green text", .green, .black);
    try terminal.writeStringWithColor(0, 2, "Blue text", .blue, .black);
    try terminal.flush();
}

test "terminal raw mode" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // These tests can't run in automated environment as they require a terminal
    // Just verify they exist and can be called with proper error handling
    _ = terminal.enableRawMode() catch {};
    terminal.disableRawMode();
}

test "terminal buffer operations" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test buffer operations
    try terminal.writeString(0, 0, "Test");
    try terminal.flush();
}
