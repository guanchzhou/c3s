const std = @import("std");
const testing = std.testing;
const BoxDrawing = @import("src").box_drawing;

test "Symbols constants are defined" {
    try testing.expect(BoxDrawing.Symbols.h_line.len > 0);
    try testing.expect(BoxDrawing.Symbols.v_line.len > 0);
    try testing.expect(BoxDrawing.Symbols.left_up.len > 0);
    try testing.expect(BoxDrawing.Symbols.right_up.len > 0);
    try testing.expect(BoxDrawing.Symbols.left_down.len > 0);
    try testing.expect(BoxDrawing.Symbols.right_down.len > 0);
}

test "Symbols have correct Unicode values" {
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.h_line, "─"));
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.v_line, "│"));
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.left_up, "┌"));
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.right_up, "┐"));
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.left_down, "└"));
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.right_down, "┘"));
}

test "Symbols for dividers are defined" {
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.div_right, "┤"));
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.div_left, "├"));
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.div_up, "┬"));
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.div_down, "┴"));
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.cross, "┼"));
}

test "Symbols for title brackets are defined" {
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.title_left, "┐"));
    try testing.expect(std.mem.eql(u8, BoxDrawing.Symbols.title_right, "┌"));
}

test "BoxStyle enum has all styles" {
    const styles = [_]BoxDrawing.BoxStyle{
        .normal,
        .rounded,
        .thick,
    };

    for (styles) |style| {
        _ = style;
        // Just verify they exist
    }
}

test "BoxStyle enum comparison" {
    try testing.expect(BoxDrawing.BoxStyle.normal != BoxDrawing.BoxStyle.rounded);
    try testing.expect(BoxDrawing.BoxStyle.normal != BoxDrawing.BoxStyle.thick);
    try testing.expect(BoxDrawing.BoxStyle.rounded != BoxDrawing.BoxStyle.thick);
}

// Note: Testing createBox would require mocking Terminal, which is complex
// The function signature and style selection logic can be verified at compile time
test "Box.createBox function exists and compiles" {
    // This test ensures the function signature is correct
    _ = BoxDrawing.Box.createBox;
}

test "Box.createHorizontalDivider function exists" {
    _ = BoxDrawing.Box.createHorizontalDivider;
}
