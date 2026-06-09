/// DetailView - Scrollable text view for describe/JSON display.
/// Supports IDE-style folding of JSON objects/arrays: fold/unfold the block at
/// the cursor (Enter/Space), or fold/unfold everything (c / o).
const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");

pub const DetailView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    lines: std.ArrayListUnmanaged([]const u8),
    /// Per-line: index of the matching close line if this line opens a foldable
    /// block (ends with `{` or `[`), else null. Parallel to `lines`.
    fold_end: std.ArrayListUnmanaged(?u32),
    /// Per-line collapse state (only meaningful where fold_end != null). Parallel to `lines`.
    folded: std.ArrayListUnmanaged(bool),
    /// Indices into `lines` that are currently visible (rebuilt when folds change).
    visible: std.ArrayListUnmanaged(u32),
    title: []const u8,
    /// Cursor position as an index into `visible`.
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    horizontal_scroll: u16 = 0,
    visible_rows: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !DetailView {
        return DetailView{
            .allocator = allocator,
            .theme = theme,
            .lines = .empty,
            .fold_end = .empty,
            .folded = .empty,
            .visible = .empty,
            .title = "Detail",
        };
    }

    pub fn deinit(self: *DetailView) void {
        self.clearContent();
        self.fold_end.deinit(self.allocator);
        self.folded.deinit(self.allocator);
        self.visible.deinit(self.allocator);
    }

    fn clearContent(self: *DetailView) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();
        self.fold_end.clearRetainingCapacity();
        self.folded.clearRetainingCapacity();
        self.visible.clearRetainingCapacity();
        if (!std.mem.eql(u8, self.title, "Detail")) {
            self.allocator.free(self.title);
            self.title = "Detail";
        }
    }

    /// Set content from raw JSON string, pretty-printed.
    pub fn setContentJson(self: *DetailView, json_str: []const u8, title: []const u8) !void {
        self.clearContent();
        self.title = try self.allocator.dupe(u8, title);
        self.selected_row = 0;
        self.scroll_offset = 0;
        self.horizontal_scroll = 0;

        // Pretty-print JSON with indentation
        var indent: usize = 0;
        var in_string = false;
        var escape_next = false;
        var line_buf = std.ArrayListUnmanaged(u8).empty;
        defer line_buf.deinit(self.allocator);

        for (json_str) |c| {
            if (escape_next) {
                try line_buf.append(self.allocator, c);
                escape_next = false;
                continue;
            }
            if (c == '\\' and in_string) {
                try line_buf.append(self.allocator, c);
                escape_next = true;
                continue;
            }
            if (c == '"') {
                in_string = !in_string;
                try line_buf.append(self.allocator, c);
                continue;
            }
            if (in_string) {
                try line_buf.append(self.allocator, c);
                continue;
            }

            switch (c) {
                '{', '[' => {
                    try line_buf.append(self.allocator, c);
                    try self.flushLine(&line_buf);
                    indent += 2;
                    try self.writeIndent(&line_buf, indent);
                },
                '}', ']' => {
                    try self.flushLine(&line_buf);
                    indent -|= 2;
                    try self.writeIndent(&line_buf, indent);
                    try line_buf.append(self.allocator, c);
                },
                ',' => {
                    try line_buf.append(self.allocator, c);
                    try self.flushLine(&line_buf);
                    try self.writeIndent(&line_buf, indent);
                },
                ':' => {
                    try line_buf.appendSlice(self.allocator, ": ");
                },
                ' ', '\t', '\n', '\r' => {
                    // Skip whitespace in raw JSON
                },
                else => {
                    try line_buf.append(self.allocator, c);
                },
            }
        }
        if (line_buf.items.len > 0) {
            try self.flushLine(&line_buf);
        }

        try self.computeFolds();
        try self.rebuildVisible();
    }

    /// Set content from raw JSON, formatted as kubectl-describe style.
    pub fn setContentDescribe(self: *DetailView, json_str: []const u8, title: []const u8) !void {
        self.clearContent();
        self.title = try self.allocator.dupe(u8, title);
        self.selected_row = 0;
        self.scroll_offset = 0;
        self.horizontal_scroll = 0;

        // Parse JSON and format as describe output
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch {
            // If JSON parsing fails, just show raw text line by line
            var line_iter = std.mem.splitScalar(u8, json_str, '\n');
            while (line_iter.next()) |line| {
                try self.lines.append(self.allocator, try self.allocator.dupe(u8, line));
            }
            try self.computeFolds();
            try self.rebuildVisible();
            return;
        };
        defer parsed.deinit();

        try self.formatDescribeValue(parsed.value, 0);
        try self.computeFolds();
        try self.rebuildVisible();
    }

    fn formatDescribeValue(self: *DetailView, value: std.json.Value, indent: usize) !void {
        // Create indent string
        var indent_buf: [128]u8 = undefined;
        const indent_len = @min(indent, 128);
        @memset(indent_buf[0..indent_len], ' ');
        const indent_str = indent_buf[0..indent_len];

        switch (value) {
            .object => |obj| {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;

                    switch (val) {
                        .object => {
                            const line = try std.fmt.allocPrint(self.allocator, "{s}{s}:", .{ indent_str, key });
                            try self.lines.append(self.allocator, line);
                            try self.formatDescribeValue(val, indent + 2);
                        },
                        .array => |arr| {
                            const line = try std.fmt.allocPrint(self.allocator, "{s}{s}:", .{ indent_str, key });
                            try self.lines.append(self.allocator, line);
                            for (arr.items) |item| {
                                try self.formatDescribeValue(item, indent + 2);
                            }
                        },
                        else => {
                            const val_str = try self.jsonValueToString(val);
                            defer self.allocator.free(val_str);
                            const line = try std.fmt.allocPrint(self.allocator, "{s}{s}: {s}", .{ indent_str, key, val_str });
                            try self.lines.append(self.allocator, line);
                        },
                    }
                }
            },
            .array => |arr| {
                for (arr.items) |item| {
                    try self.formatDescribeValue(item, indent + 2);
                }
            },
            else => {
                const val_str = try self.jsonValueToString(value);
                defer self.allocator.free(val_str);
                const line = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ indent_str, val_str });
                try self.lines.append(self.allocator, line);
            },
        }
    }

    fn jsonValueToString(self: *DetailView, value: std.json.Value) ![]u8 {
        return switch (value) {
            .string => |s| try self.allocator.dupe(u8, s),
            .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
            .float => |f| try std.fmt.allocPrint(self.allocator, "{d}", .{f}),
            .bool => |b| try self.allocator.dupe(u8, if (b) "true" else "false"),
            .null => try self.allocator.dupe(u8, "null"),
            else => try self.allocator.dupe(u8, "<complex>"),
        };
    }

    fn flushLine(self: *DetailView, line_buf: *std.ArrayListUnmanaged(u8)) !void {
        if (line_buf.items.len > 0) {
            try self.lines.append(self.allocator, try self.allocator.dupe(u8, line_buf.items));
            line_buf.clearRetainingCapacity();
        }
    }

    fn writeIndent(self: *DetailView, line_buf: *std.ArrayListUnmanaged(u8), indent: usize) !void {
        for (0..indent) |_| {
            try line_buf.append(self.allocator, ' ');
        }
    }

    // ===== Folding =====

    fn indentOf(line: []const u8) usize {
        return std.mem.indexOfNone(u8, line, " ") orelse line.len;
    }

    /// True if the line opens a foldable block (last non-space char is `{` or `[`).
    fn opensBlock(line: []const u8) bool {
        const t = std.mem.trimEnd(u8, line, " \t");
        return t.len > 0 and (t[t.len - 1] == '{' or t[t.len - 1] == '[');
    }

    /// The closing bracket char of a close line (`}` / `]`), or 0 if not a closer.
    fn closeBracketOf(line: []const u8) u8 {
        const t = std.mem.trimStart(u8, line, " \t");
        if (t.len > 0 and (t[0] == '}' or t[0] == ']')) return t[0];
        return 0;
    }

    /// Fill fold_end/folded (parallel to lines). An opener's match is the first
    /// later line at the SAME indent that begins with a closing bracket — which,
    /// for consistent 2-space pretty-printing, is exactly its block close.
    fn computeFolds(self: *DetailView) !void {
        const n = self.lines.items.len;
        try self.fold_end.ensureTotalCapacity(self.allocator, n);
        try self.folded.ensureTotalCapacity(self.allocator, n);
        self.fold_end.clearRetainingCapacity();
        self.folded.clearRetainingCapacity();
        for (0..n) |_| {
            self.fold_end.appendAssumeCapacity(null);
            self.folded.appendAssumeCapacity(false);
        }
        for (self.lines.items, 0..) |line, i| {
            if (!opensBlock(line)) continue;
            const ind = indentOf(line);
            var j = i + 1;
            while (j < n) : (j += 1) {
                const lj = self.lines.items[j];
                if (indentOf(lj) == ind) {
                    if (closeBracketOf(lj) != 0) self.fold_end.items[i] = @intCast(j);
                    break; // first same-indent line decides (close, or a malformed sibling)
                }
            }
        }
    }

    /// Rebuild the visible-line projection from fold state.
    fn rebuildVisible(self: *DetailView) !void {
        self.visible.clearRetainingCapacity();
        var i: usize = 0;
        const n = self.lines.items.len;
        while (i < n) {
            try self.visible.append(self.allocator, @intCast(i));
            if (self.folded.items[i]) {
                if (self.fold_end.items[i]) |e| {
                    i = e + 1; // hide i+1..e (the opener shows a collapsed marker)
                    continue;
                }
            }
            i += 1;
        }
        if (self.visible.items.len == 0) {
            self.selected_row = 0;
        } else if (self.selected_row >= self.visible.items.len) {
            self.selected_row = @intCast(self.visible.items.len - 1);
        }
        self.clampScroll();
    }

    fn clampScroll(self: *DetailView) void {
        if (self.visible_rows == 0) return;
        if (self.selected_row < self.scroll_offset) {
            self.scroll_offset = self.selected_row;
        } else if (self.selected_row >= self.scroll_offset + self.visible_rows) {
            self.scroll_offset = self.selected_row - self.visible_rows + 1;
        }
    }

    fn toggleFoldAtCursor(self: *DetailView) !void {
        if (self.selected_row >= self.visible.items.len) return;
        const raw = self.visible.items[self.selected_row];
        if (self.fold_end.items[raw] == null) return; // not a foldable line
        self.folded.items[raw] = !self.folded.items[raw];
        try self.rebuildVisible();
    }

    fn setAllFolds(self: *DetailView, value: bool) !void {
        for (self.folded.items, 0..) |*f, i| {
            if (self.fold_end.items[i] != null) f.* = value;
        }
        // Keep the cursor on the same raw line if still visible; else clamp.
        try self.rebuildVisible();
    }

    // View trait implementation
    pub fn createView(self: *DetailView) View {
        return View.create(DetailView, self, &vtable);
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinitView,
    };

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *DetailView = @ptrCast(@alignCast(ptr));
        self.visible_rows = if (height > 1) height - 1 else 0;

        if (self.visible.items.len == 0) {
            const Theme = theme_loader;
            try Theme.writeStringWithTheme(terminal, x, y, "No content", self.theme.inactive_fg, self.theme.main_bg);
            return;
        }

        const content_width: u16 = if (width > 2) width - 2 else 1;
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + self.visible_rows, self.visible.items.len);

        for (start_row..end_row, 0..) |vis_idx, display_idx| {
            const raw = self.visible.items[vis_idx];
            const line = self.lines.items[raw];
            const row_y = y + @as(u16, @intCast(display_idx));
            const selected = vis_idx == self.selected_row;

            try terminal.setCursor(x, row_y);
            if (selected) {
                try terminal.writeAll(self.theme.selected_bg);
                try terminal.writeAll(self.theme.selected_fg);
            } else {
                try terminal.writeAll(self.theme.main_fg);
            }

            var written: u16 = 0;

            // Line text with horizontal scroll + truncation
            const visible_line = if (self.horizontal_scroll < line.len)
                line[self.horizontal_scroll..]
            else
                "";
            const display_len = @min(visible_line.len, @as(usize, content_width));
            if (display_len > 0) {
                try terminal.writeAll(visible_line[0..display_len]);
                written += @intCast(display_len);
            }

            // Collapsed marker: "...}" / "...]" appended to a folded opener.
            const is_folded = self.folded.items[raw] and self.fold_end.items[raw] != null;
            if (is_folded and written < content_width) {
                const closer = closeBracketOf(self.lines.items[self.fold_end.items[raw].?]);
                var mbuf: [4]u8 = undefined;
                const marker = std.fmt.bufPrint(&mbuf, "...{c}", .{if (closer != 0) closer else '}'}) catch "...";
                const room = content_width - written;
                const mlen = @min(marker.len, @as(usize, room));
                try terminal.writeAll(marker[0..mlen]);
                written += @intCast(mlen);
            }

            // Pad the rest of the row so the selection bar spans the full width.
            if (selected) {
                while (written < content_width) : (written += 1) {
                    try terminal.writeAll(" ");
                }
            }
            try terminal.writeAll("\x1b[0m");
        }
    }

    fn moveDown(self: *DetailView) void {
        if (self.selected_row + 1 < self.visible.items.len) {
            self.selected_row += 1;
            if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }
    }

    fn moveUp(self: *DetailView) void {
        if (self.selected_row > 0) {
            self.selected_row -= 1;
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *DetailView = @ptrCast(@alignCast(ptr));
        const count: u32 = @intCast(self.visible.items.len);

        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    self.moveDown();
                    return .handled;
                },
                'k' => {
                    self.moveUp();
                    return .handled;
                },
                'g' => {
                    self.selected_row = 0;
                    self.scroll_offset = 0;
                    return .handled;
                },
                'h' => {
                    if (self.horizontal_scroll > 0) self.horizontal_scroll -= 1;
                    return .handled;
                },
                'l' => {
                    self.horizontal_scroll += 1;
                    return .handled;
                },
                // Folding: Space toggles the block at the cursor; c folds all, o unfolds all.
                ' ' => {
                    try self.toggleFoldAtCursor();
                    return .handled;
                },
                'c' => {
                    try self.setAllFolds(true);
                    return .handled;
                },
                'o' => {
                    try self.setAllFolds(false);
                    return .handled;
                },
                else => return .not_handled,
            },
            .enter => {
                try self.toggleFoldAtCursor();
                return .handled;
            },
            .up => {
                self.moveUp();
                return .handled;
            },
            .down => {
                self.moveDown();
                return .handled;
            },
            .shift_g => {
                if (count > 0) {
                    self.selected_row = count - 1;
                    if (self.selected_row >= self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .page_up => {
                if (self.selected_row >= self.visible_rows) {
                    self.selected_row -= self.visible_rows;
                    if (self.selected_row < self.scroll_offset) {
                        self.scroll_offset = self.selected_row;
                    }
                } else {
                    self.selected_row = 0;
                    self.scroll_offset = 0;
                }
                return .handled;
            },
            .page_down => {
                if (self.selected_row + self.visible_rows < count) {
                    self.selected_row += self.visible_rows;
                    if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                } else if (count > 0) {
                    self.selected_row = count - 1;
                    if (self.selected_row >= self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .home => {
                self.selected_row = 0;
                self.scroll_offset = 0;
                return .handled;
            },
            .end => {
                if (count > 0) {
                    self.selected_row = count - 1;
                    if (self.selected_row >= self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .escape => return .not_handled, // Let parent handle pop
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("DetailView: View activated", .{});
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("DetailView: View deactivated", .{});
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "detail";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.detailHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *DetailView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

test "DetailView fold: collapse and expand a JSON block" {
    const testing = std.testing;
    var theme = try theme_loader.defaultTheme(testing.allocator);
    defer theme_loader.deinitTheme(&theme);

    var dv = try DetailView.init(testing.allocator, &theme);
    defer dv.deinit();

    try dv.setContentJson(
        \\{"metadata":{"name":"x","labels":{"a":"b"}},"spec":{"n":1}}
    , "pod");

    // All expanded initially: every produced line is visible.
    try testing.expectEqual(dv.lines.items.len, dv.visible.items.len);
    const full = dv.visible.items.len;

    // The root line (index 0) opens a block and must have a matching close.
    try testing.expect(dv.fold_end.items[0] != null);

    // Fold everything: far fewer visible lines, but at least the root remains.
    try dv.setAllFolds(true);
    try testing.expect(dv.visible.items.len < full);
    try testing.expect(dv.visible.items.len >= 1);

    // Unfold everything: back to the full set.
    try dv.setAllFolds(false);
    try testing.expectEqual(full, dv.visible.items.len);

    // Toggle the block at the cursor (root) collapses to a single visible line.
    dv.selected_row = 0;
    try dv.toggleFoldAtCursor();
    try testing.expectEqual(@as(usize, 1), dv.visible.items.len);
}
