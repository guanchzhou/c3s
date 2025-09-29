const std = @import("std");
const testing = std.testing;
const Body = @import("body").Body;

test "visible_rows computed correctly" {
    const allocator = testing.allocator;
    
    var body = try Body.init(allocator);
    defer body.deinit();
    
    // Mock terminal dimensions
    const height: u16 = 25; // Total terminal height
    const expected_visible = 25 - 3; // height - 3 (header + border)
    
    // After render, visible_rows should be set
    // Note: This test will need actual rendering to properly test
    // For now, verify the field exists and can be set
    try testing.expect(body.visible_rows == 0); // Initially 0
    
    // After a render call with height=25, visible_rows should be 22
    // body.render(..., height=25) would set visible_rows = 22
}

test "viewportHeight returns visible_rows" {
    const allocator = testing.allocator;
    
    var body = try Body.init(allocator);
    defer body.deinit();
    
    // Set visible_rows
    body.visible_rows = 20;
    
    // viewportHeight should return it
    const viewport = body.viewportHeight();
    try testing.expectEqual(@as(u32, 20), viewport);
}

test "viewportHeight returns 1 when visible_rows is 0" {
    const allocator = testing.allocator;
    
    var body = try Body.init(allocator);
    defer body.deinit();
    
    // visible_rows defaults to 0
    const viewport = body.viewportHeight();
    try testing.expectEqual(@as(u32, 1), viewport);
}

test "pageDown navigation uses viewport height" {
    const allocator = testing.allocator;
    
    var body = try Body.init(allocator);
    defer body.deinit();
    
    // Set visible_rows to simulate a rendered viewport
    body.visible_rows = 10;
    
    // Start at row 0
    try testing.expectEqual(@as(u32, 0), body.selected_row);
    
    // Page down
    try body.pageDown();
    
    // Should move by viewport height (10)
    try testing.expectEqual(@as(u32, 10), body.selected_row);
}

test "pageUp navigation uses viewport height" {
    const allocator = testing.allocator;
    
    var body = try Body.init(allocator);
    defer body.deinit();
    
    // Set visible_rows to simulate a rendered viewport
    body.visible_rows = 10;
    
    // Start at row 20
    body.selected_row = 20;
    body.scroll_offset = 10;
    
    // Page up
    try body.pageUp();
    
    // Should move back by viewport height (10)
    try testing.expectEqual(@as(u32, 10), body.selected_row);
}

test "gotoBottom uses viewport height for scroll calculation" {
    const allocator = testing.allocator;
    
    var body = try Body.init(allocator);
    defer body.deinit();
    
    // Set visible_rows
    body.visible_rows = 10;
    
    // Go to bottom
    try body.gotoBottom();
    
    // Should be at last item
    const last_row = @as(u32, @intCast(body.pods.items.len - 1));
    try testing.expectEqual(last_row, body.selected_row);
    
    // Scroll offset should position last item at bottom of viewport
    if (last_row >= body.visible_rows) {
        const expected_offset = last_row - body.visible_rows + 1;
        try testing.expectEqual(expected_offset, body.scroll_offset);
    }
}
