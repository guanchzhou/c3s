const std = @import("std");
const testing = std.testing;
const PodsView = @import("src").PodsView;
const Terminal = @import("src").Terminal;

test "body initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var body = try Body.init(allocator);
    defer body.deinit();

    // Test that body was initialized with sample data
    try testing.expect(body.pods.items.len > 0);
    try testing.expect(body.selected_row == 0);
    try testing.expect(body.scroll_offset == 0);
}

test "body pod data validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var body = try Body.init(allocator);
    defer body.deinit();

    // Test that all pods have valid data
    for (body.pods.items) |pod| {
        try testing.expect(pod.namespace.len > 0);
        try testing.expect(pod.name.len > 0);
        try testing.expect(pod.ready.len > 0);
        try testing.expect(pod.status.len > 0);
        try testing.expect(pod.ip.len > 0);
        try testing.expect(pod.node.len > 0);
        try testing.expect(pod.age.len > 0);
    }
}

test "body navigation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var body = try Body.init(allocator);
    defer body.deinit();

    const initial_selected = body.selected_row;
    const initial_scroll = body.scroll_offset;

    // Test navigation down
    try body.navigateDown();
    if (body.pods.items.len > 1) {
        try testing.expect(body.selected_row == initial_selected + 1);
    }

    // Test navigation up
    try body.navigateUp();
    try testing.expect(body.selected_row == initial_selected);

    // Test navigation left/right (currently no-op, but should not crash)
    try body.navigateLeft();
    try body.navigateRight();
}

test "body rendering" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var body = try Body.init(allocator);
    defer body.deinit();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test that rendering doesn't crash
    try body.render(&terminal, 0, 0, 80, 20);
    
    // Test rendering at different positions
    try body.render(&terminal, 10, 5, 100, 25);
    
    // Test rendering with different sizes
    try body.render(&terminal, 0, 0, 120, 30);
}

test "body scroll behavior" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var body = try Body.init(allocator);
    defer body.deinit();

    const initial_scroll = body.scroll_offset;
    const initial_selected = body.selected_row;

    // Test that scroll offset doesn't go negative
    body.scroll_offset = 0;
    try body.navigateUp();
    try testing.expect(body.scroll_offset >= 0);

    // Test that scroll offset doesn't exceed bounds
    body.scroll_offset = body.pods.items.len;
    try body.navigateDown();
    try testing.expect(body.scroll_offset <= body.pods.items.len);
}

test "body selection bounds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var body = try Body.init(allocator);
    defer body.deinit();

    // Test that selected_row doesn't go negative
    body.selected_row = 0;
    try body.navigateUp();
    try testing.expect(body.selected_row >= 0);

    // Test that selected_row doesn't exceed bounds
    body.selected_row = body.pods.items.len - 1;
    try body.navigateDown();
    try testing.expect(body.selected_row < body.pods.items.len);
}

test "body memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test multiple initialization and cleanup cycles
    for (0..10) |_| {
        var body = try Body.init(allocator);
        body.deinit();
    }
    
    // Test that no memory leaks occurred
    const allocated = gpa.deinit();
    try testing.expect(allocated == .ok);
}
