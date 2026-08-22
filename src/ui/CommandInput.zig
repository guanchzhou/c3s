const std = @import("std");
const Terminal = @import("../core/Terminal.zig").Terminal;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const fuzzy = @import("fuzzy.zig");
const BoxDrawing = @import("box_drawing.zig");

/// CommandInput - handles command line input with different prompts
pub const CommandInput = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    visible: bool = false,
    prompt: []const u8 = "",
    buffer: std.ArrayList(u8),
    cursor_pos: usize = 0,

    // Fuzzy suggestion state (borrowed slice; owned by App, lives as long as App)
    candidates: []const []const u8 = &.{},
    match_idx: [10]usize = undefined,
    match_count: usize = 0,
    selected: usize = 0,
    show_suggestions: bool = false,

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

    /// Set the candidate list for fuzzy matching. The slice is borrowed — it
    /// must outlive this CommandInput (App stores it for the app lifetime).
    pub fn setCandidates(self: *CommandInput, names: []const []const u8) void {
        self.candidates = names;
    }

    pub fn showWithPrompt(self: *CommandInput, prompt: []const u8) void {
        self.visible = true;
        self.prompt = prompt;
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
        self.show_suggestions = std.mem.eql(u8, prompt, ":");
        self.selected = 0;
        self.recompute();
        Logger.debug("CommandInput: Opened with prompt '{s}'", .{prompt});
    }

    pub fn hide(self: *CommandInput) void {
        self.visible = false;
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
        self.match_count = 0;
        self.selected = 0;
        Logger.debug("CommandInput: Closed", .{});
    }

    /// Recompute the ranked suggestion list based on the current buffer.
    pub fn recompute(self: *CommandInput) void {
        if (!self.show_suggestions) {
            self.match_count = 0;
            return;
        }
        self.match_count = fuzzy.rank(self.buffer.items, self.candidates, &self.match_idx);
        if (self.selected >= self.match_count) {
            self.selected = if (self.match_count > 0) self.match_count - 1 else 0;
        }
    }

    /// Move the selection by `delta` rows, wrapping within [0, match_count).
    pub fn moveSelection(self: *CommandInput, delta: i32) void {
        if (self.match_count == 0) return;
        const n: i32 = @intCast(self.match_count);
        var s: i32 = @intCast(self.selected);
        s += delta;
        // Wrap around
        s = @mod(s, n);
        self.selected = @intCast(s);
    }

    /// Return the currently highlighted suggestion, or null if none.
    pub fn currentSuggestion(self: *CommandInput) ?[]const u8 {
        if (!self.show_suggestions or self.match_count == 0) return null;
        return self.candidates[self.match_idx[self.selected]];
    }

    pub fn addChar(self: *CommandInput, c: u8) !void {
        if (c >= 32 and c <= 126) { // Printable ASCII
            try self.buffer.insert(self.allocator, self.cursor_pos, c);
            self.cursor_pos += 1;
            self.recompute();
        }
    }

    pub fn backspace(self: *CommandInput) void {
        if (self.cursor_pos > 0) {
            _ = self.buffer.orderedRemove(self.cursor_pos - 1);
            self.cursor_pos -= 1;
            self.recompute();
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

        // --- Draw the input line (unchanged from original) ---

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

        // --- Draw the suggestion dropdown as a bordered popup ---
        // The body box refills its whole interior every frame BEFORE this view
        // renders, so a shrinking match list leaves no stale rows — we just draw
        // a fresh popup sized to the current matches. Using the same box-drawing
        // as the rest of the UI makes it read as an intentional overlay rather
        // than a hole punched in the table.
        if (self.show_suggestions and self.match_count > 0) {
            const rows: u16 = @intCast(@min(self.match_count, @as(usize, 8)));

            // Popup width = longest shown candidate + padding, clamped to screen.
            var longest: usize = 0;
            for (0..rows) |i| {
                const c = self.candidates[self.match_idx[i]];
                if (c.len > longest) longest = c.len;
            }
            var box_w: u16 = @intCast(@min(longest + 4, @as(usize, width)));
            if (box_w < 16) box_w = 16;

            const box_y = y + 1;
            const box_h = rows + 2;
            try BoxDrawing.Box.createBox(
                terminal,
                x,
                box_y,
                box_w,
                box_h,
                self.theme.proc_box,
                self.theme.main_bg,
                null,
                .rounded,
                self.theme.main_fg,
                self.theme.title_highlight,
            );

            const inner_w: usize = box_w - 2;
            for (0..rows) |i| {
                const candidate = self.candidates[self.match_idx[i]];
                const row_y = box_y + 1 + @as(u16, @intCast(i));
                try terminal.setCursor(x + 1, row_y);

                const is_selected = (i == self.selected);
                if (is_selected) {
                    try terminal.writeAll(self.theme.selected_bg);
                    try terminal.writeAll(self.theme.main_fg);
                } else {
                    try terminal.writeAll(self.theme.main_bg);
                    try terminal.writeAll(self.theme.inactive_fg);
                }

                // " candidate", truncated to the box interior.
                var row_buf: [256]u8 = undefined;
                const text_len = @min(candidate.len, inner_w - 1);
                const row_text = std.fmt.bufPrint(&row_buf, " {s}", .{candidate[0..text_len]}) catch candidate[0..text_len];
                try terminal.writeAll(row_text);

                // Pad to the interior width so the highlight bar is solid.
                var written: usize = 1 + text_len;
                while (written < inner_w) : (written += 1) try terminal.writeAll(" ");

                try terminal.writeAll("\x1b[0m");
            }
        }

        // Position cursor back on the INPUT line so typing still shows the caret
        // on the input row (must be set AFTER drawing suggestions).
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

test "CommandInput suggestions: colon prompt enables dropdown" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    const names = [_][]const u8{ "pods", "deployments", "services", "nodes" };
    cmd_input.setCandidates(&names);

    // ':' prompt enables suggestions
    cmd_input.showWithPrompt(":");
    try testing.expect(cmd_input.show_suggestions);
    try testing.expect(cmd_input.match_count > 0); // all match empty query

    // '/' prompt does NOT enable suggestions
    cmd_input.hide();
    cmd_input.showWithPrompt("/");
    try testing.expect(!cmd_input.show_suggestions);
    try testing.expectEqual(@as(usize, 0), cmd_input.match_count);
}

test "CommandInput suggestions: currentSuggestion and moveSelection" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    const names = [_][]const u8{ "pods", "deployments", "services" };
    cmd_input.setCandidates(&names);
    cmd_input.showWithPrompt(":");

    // With empty buffer all candidates match; currentSuggestion returns one.
    try testing.expect(cmd_input.currentSuggestion() != null);

    // After typing "pod" only "pods" should remain
    try cmd_input.addChar('p');
    try cmd_input.addChar('o');
    try cmd_input.addChar('d');
    try testing.expect(cmd_input.match_count >= 1);
    const sug = cmd_input.currentSuggestion();
    try testing.expect(sug != null);
    // "pods" starts with "pod" — it must be in the match set
    const found = for (0..cmd_input.match_count) |i| {
        if (std.mem.eql(u8, cmd_input.candidates[cmd_input.match_idx[i]], "pods")) break true;
    } else false;
    try testing.expect(found);

    // moveSelection wraps
    cmd_input.selected = 0;
    if (cmd_input.match_count > 1) {
        cmd_input.moveSelection(1);
        try testing.expectEqual(@as(usize, 1), cmd_input.selected);
        cmd_input.moveSelection(-1);
        try testing.expectEqual(@as(usize, 0), cmd_input.selected);
    }
}

test "CommandInput suggestions: no suggestion for slash prompt" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    const names = [_][]const u8{ "pods", "deployments" };
    cmd_input.setCandidates(&names);
    cmd_input.showWithPrompt("/");

    try testing.expect(cmd_input.currentSuggestion() == null);
}

test "addChar accepts the characters Terminal routes as separate key variants" {
    // ':' '?' and 'G' are all printable ASCII, so addChar always accepted them --
    // the bug was upstream in App, which never called it for those keys because
    // Terminal.readKey converts them to .colon / .question_mark / .shift_g before
    // App's dispatch sees them. This pins the low-level contract App now relies on:
    // filtering for a pod named "Gateway" must be expressible.
    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);

    var ci = try CommandInput.init(std.testing.allocator, &theme);
    defer ci.deinit();

    ci.showWithPrompt("/");
    for ("Gateway:?") |c| try ci.addChar(c);
    try std.testing.expectEqualStrings("Gateway:?", ci.getCommand());
}
