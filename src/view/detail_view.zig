/// DetailView - Scrollable text view for describe/JSON display
const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");

pub const DetailView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    lines: std.ArrayListUnmanaged([]const u8),
    title: []const u8,
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    horizontal_scroll: u16 = 0,
    visible_rows: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !DetailView {
        return DetailView{
            .allocator = allocator,
            .theme = theme,
            .lines = .empty,
            .title = "Detail",
        };
    }

    pub fn deinit(self: *DetailView) void {
        self.clearContent();
    }

    fn clearContent(self: *DetailView) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();
        if (!std.mem.eql(u8, self.title, "Detail")) {
            self.allocator.free(self.title);
            self.title = "Detail";
        }
    }

    /// Set content from raw JSON string, pretty-printed
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
    }

    /// Set content from raw JSON, formatted as kubectl-describe style
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
            return;
        };
        defer parsed.deinit();

        try self.formatDescribeValue(parsed.value, 0);
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

        if (self.lines.items.len == 0) {
            const Theme = theme_loader;
            try Theme.writeStringWithTheme(terminal, x, y, "No content", self.theme.inactive_fg, self.theme.main_bg);
            return;
        }

        // Draw content lines
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + self.visible_rows, self.lines.items.len);
        const content_width: u16 = if (width > 2) width - 2 else 1;

        for (start_row..end_row, 0..) |line_idx, display_idx| {
            const line = self.lines.items[line_idx];
            const row_y = y + @as(u16, @intCast(display_idx));

            try terminal.setCursor(x, row_y);
            try terminal.writeAll(self.theme.main_fg);

            // Apply horizontal scroll
            const visible_line = if (self.horizontal_scroll < line.len)
                line[self.horizontal_scroll..]
            else
                "";

            // Truncate to visible width
            const display_len = @min(visible_line.len, content_width);
            if (display_len > 0) {
                try terminal.writeAll(visible_line[0..display_len]);
            }
            try terminal.writeAll("\x1b[0m");
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *DetailView = @ptrCast(@alignCast(ptr));

        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    if (self.selected_row + 1 < self.lines.items.len) {
                        self.selected_row += 1;
                        if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                            self.scroll_offset = self.selected_row - self.visible_rows + 1;
                        }
                    }
                    return .handled;
                },
                'k' => {
                    if (self.selected_row > 0) {
                        self.selected_row -= 1;
                        if (self.selected_row < self.scroll_offset) {
                            self.scroll_offset = self.selected_row;
                        }
                    }
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
                else => return .not_handled,
            },
            .up => {
                if (self.selected_row > 0) {
                    self.selected_row -= 1;
                    if (self.selected_row < self.scroll_offset) {
                        self.scroll_offset = self.selected_row;
                    }
                }
                return .handled;
            },
            .down => {
                if (self.selected_row + 1 < self.lines.items.len) {
                    self.selected_row += 1;
                    if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .shift_g => {
                if (self.lines.items.len > 0) {
                    self.selected_row = @intCast(self.lines.items.len - 1);
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
                if (self.selected_row + self.visible_rows < self.lines.items.len) {
                    self.selected_row += self.visible_rows;
                    if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                } else if (self.lines.items.len > 0) {
                    self.selected_row = @intCast(self.lines.items.len - 1);
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
                if (self.lines.items.len > 0) {
                    self.selected_row = @intCast(self.lines.items.len - 1);
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
