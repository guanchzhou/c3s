const std = @import("std");
const Terminal = @import("../core/Terminal.zig").Terminal;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");

/// CommandInput - handles command line input with different prompts
pub const CommandInput = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    visible: bool = false,
    prompt: []const u8 = "",
    buffer: std.ArrayList(u8),
    cursor_pos: usize = 0,

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !CommandInput {
        return CommandInput{
            .allocator = allocator,
            .theme = theme,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, 256),
        };
    }

    pub fn deinit(self: *CommandInput) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn showWithPrompt(self: *CommandInput, prompt: []const u8) void {
        self.visible = true;
        self.prompt = prompt;
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
        Logger.debug("CommandInput: Opened with prompt '{s}'", .{prompt});
    }

    pub fn hide(self: *CommandInput) void {
        self.visible = false;
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
        Logger.debug("CommandInput: Closed", .{});
    }

    pub fn addChar(self: *CommandInput, c: u8) !void {
        if (c >= 32 and c <= 126) { // Printable ASCII
            try self.buffer.insert(self.allocator, self.cursor_pos, c);
            self.cursor_pos += 1;
        }
    }

    pub fn backspace(self: *CommandInput) void {
        if (self.cursor_pos > 0) {
            _ = self.buffer.orderedRemove(self.cursor_pos - 1);
            self.cursor_pos -= 1;
        }
    }

    pub fn getCommand(self: *CommandInput) []const u8 {
        return self.buffer.items;
    }

    pub fn render(self: *CommandInput, terminal: *Terminal, x: u16, y: u16, width: u16) !void {
        // If not visible, do not touch the screen row to avoid erasing view borders
        if (!self.visible) {
            try terminal.hideCursor();
            return;
        }

        // Clear the command line before drawing
        try terminal.setCursor(x, y);
        try terminal.writeAll("\x1b[K"); // Clear to end of line

        // Clear the line with prompt background color
        try terminal.setCursor(x, y);
        try terminal.writeAll(self.theme.prompt_bg);
        var spaces_buf: [256]u8 = undefined;
        @memset(&spaces_buf, ' ');
        var remaining: usize = width;
        while (remaining > 0) {
            const chunk = @min(remaining, spaces_buf.len);
            try terminal.writeAll(spaces_buf[0..chunk]);
            remaining -= chunk;
        }

        // Draw prompt and buffer with prompt colors
        try terminal.setCursor(x, y);
        try terminal.writeAll(self.theme.prompt_fg);
        try terminal.writeAll(self.theme.prompt_bg);
        var line_buf: [512]u8 = undefined;
        const line_text = try std.fmt.bufPrint(&line_buf, " {s} {s}", .{ self.prompt, self.buffer.items });
        try terminal.writeAll(line_text);
        try terminal.writeAll("\x1b[0m");

        // Position cursor after the text (accounting for leading space)
        try terminal.setCursor(x + @as(u16, @intCast(1 + self.prompt.len + 1 + self.cursor_pos)), y);
    }
};

const testing = std.testing;

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
