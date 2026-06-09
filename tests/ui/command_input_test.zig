const std = @import("std");
const testing = std.testing;
const CommandInput = @import("src").CommandInput;
const theme_loader = @import("src").theme_loader;

test "CommandInput initialization" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    try testing.expect(!cmd_input.visible);
    try testing.expectEqual(@as(usize, 0), cmd_input.buffer.items.len);
    try testing.expectEqual(@as(usize, 0), cmd_input.cursor_pos);
}

test "CommandInput show and hide" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    try testing.expect(!cmd_input.visible);

    cmd_input.showWithPrompt(":");
    try testing.expect(cmd_input.visible);
    try testing.expect(std.mem.eql(u8, cmd_input.prompt, ":"));

    cmd_input.hide();
    try testing.expect(!cmd_input.visible);
}

test "CommandInput insertChar adds character" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    cmd_input.showWithPrompt(":");

    try cmd_input.addChar('t');
    try testing.expectEqual(@as(usize, 1), cmd_input.buffer.items.len);
    try testing.expectEqual(@as(u8, 't'), cmd_input.buffer.items[0]);
    try testing.expectEqual(@as(usize, 1), cmd_input.cursor_pos);

    try cmd_input.addChar('e');
    try cmd_input.addChar('s');
    try cmd_input.addChar('t');
    try testing.expectEqual(@as(usize, 4), cmd_input.buffer.items.len);
    try testing.expect(std.mem.eql(u8, cmd_input.buffer.items, "test"));
}

test "CommandInput deleteChar removes character" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    cmd_input.showWithPrompt(":");
    try cmd_input.addChar('a');
    try cmd_input.addChar('b');
    try cmd_input.addChar('c');

    cmd_input.backspace();
    try testing.expectEqual(@as(usize, 2), cmd_input.buffer.items.len);
    try testing.expect(std.mem.eql(u8, cmd_input.buffer.items, "ab"));
}

test "CommandInput deleteChar on empty buffer does nothing" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    cmd_input.showWithPrompt(":");
    cmd_input.backspace();

    try testing.expectEqual(@as(usize, 0), cmd_input.buffer.items.len);
}

test "CommandInput clear resets buffer" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    cmd_input.showWithPrompt(":");
    try cmd_input.addChar('h');
    try cmd_input.addChar('e');
    try cmd_input.addChar('l');
    try cmd_input.addChar('l');
    try cmd_input.addChar('o');

    cmd_input.hide();

    try testing.expectEqual(@as(usize, 0), cmd_input.buffer.items.len);
    try testing.expectEqual(@as(usize, 0), cmd_input.cursor_pos);
}

test "CommandInput getText returns buffer content" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    cmd_input.showWithPrompt(":");
    try cmd_input.addChar('t');
    try cmd_input.addChar('e');
    try cmd_input.addChar('s');
    try cmd_input.addChar('t');

    const text = cmd_input.getCommand();
    try testing.expect(std.mem.eql(u8, text, "test"));
}

test "CommandInput prompt can be changed" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    cmd_input.showWithPrompt(":");
    try testing.expect(std.mem.eql(u8, cmd_input.prompt, ":"));

    cmd_input.hide();
    cmd_input.showWithPrompt("/");
    try testing.expect(std.mem.eql(u8, cmd_input.prompt, "/"));
}

test "CommandInput cursor position tracks insertions" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    cmd_input.showWithPrompt(":");

    try testing.expectEqual(@as(usize, 0), cmd_input.cursor_pos);
    try cmd_input.addChar('a');
    try testing.expectEqual(@as(usize, 1), cmd_input.cursor_pos);
    try cmd_input.addChar('b');
    try testing.expectEqual(@as(usize, 2), cmd_input.cursor_pos);
}

test "CommandInput cursor position tracks deletions" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    cmd_input.showWithPrompt(":");
    try cmd_input.addChar('a');
    try cmd_input.addChar('b');
    try cmd_input.addChar('c');

    try testing.expectEqual(@as(usize, 3), cmd_input.cursor_pos);
    cmd_input.backspace();
    try testing.expectEqual(@as(usize, 2), cmd_input.cursor_pos);
    cmd_input.backspace();
    try testing.expectEqual(@as(usize, 1), cmd_input.cursor_pos);
}
