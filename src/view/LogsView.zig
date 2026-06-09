/// LogsView - Scrollable pod log viewer with filtering and search highlighting
const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");

pub const LogsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    lines: std.ArrayListUnmanaged([]const u8),
    filtered_indices: std.ArrayListUnmanaged(usize),
    title: []const u8,
    filter_text: []const u8 = "",
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    visible_rows: u32 = 0,
    auto_scroll: bool = true,

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !LogsView {
        return LogsView{
            .allocator = allocator,
            .theme = theme,
            .lines = .empty,
            .filtered_indices = .empty,
            .title = "Logs",
        };
    }

    pub fn deinit(self: *LogsView) void {
        self.clearContent();
        self.filtered_indices.deinit(self.allocator);
    }

    fn clearContent(self: *LogsView) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();
        self.filtered_indices.clearRetainingCapacity();
        if (!std.mem.eql(u8, self.title, "Logs")) {
            self.allocator.free(self.title);
            self.title = "Logs";
        }
        self.filter_text = "";
    }

    /// Set log content from raw text
    pub fn setContent(self: *LogsView, log_text: []const u8, pod_name: []const u8) !void {
        self.clearContent();
        self.title = try std.fmt.allocPrint(self.allocator, "Logs({s})", .{pod_name});
        self.selected_row = 0;
        self.scroll_offset = 0;

        // Split text into lines
        var line_iter = std.mem.splitScalar(u8, log_text, '\n');
        while (line_iter.next()) |line| {
            try self.lines.append(self.allocator, try self.allocator.dupe(u8, line));
        }

        // Build initial unfiltered indices
        try self.rebuildFilteredIndices();

        // Auto-scroll to bottom
        if (self.auto_scroll and self.filtered_indices.items.len > 0) {
            self.selected_row = @intCast(self.filtered_indices.items.len - 1);
            if (self.selected_row >= self.visible_rows and self.visible_rows > 0) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }
    }

    /// Apply a filter to log lines
    pub fn applyFilter(self: *LogsView, filter: []const u8) !void {
        self.filter_text = filter;
        try self.rebuildFilteredIndices();
        self.selected_row = 0;
        self.scroll_offset = 0;
    }

    fn rebuildFilteredIndices(self: *LogsView) !void {
        self.filtered_indices.clearRetainingCapacity();
        for (self.lines.items, 0..) |line, i| {
            if (self.filter_text.len == 0 or containsCaseInsensitive(line, self.filter_text)) {
                try self.filtered_indices.append(self.allocator, i);
            }
        }
    }

    fn containsCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0) return true;
        if (needle.len > haystack.len) return false;
        const end = haystack.len - needle.len + 1;
        for (0..end) |i| {
            var match = true;
            for (0..needle.len) |j| {
                if (toLower(haystack[i + j]) != toLower(needle[j])) {
                    match = false;
                    break;
                }
            }
            if (match) return true;
        }
        return false;
    }

    fn toLower(c: u8) u8 {
        return if (c >= 'A' and c <= 'Z') c + 32 else c;
    }

    // View trait implementation
    pub fn createView(self: *LogsView) View {
        return View.create(LogsView, self, &vtable);
    }

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *LogsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }
    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *LogsView = @ptrCast(@alignCast(ptr));
        if (self.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinitView,
        .applyFilter = vtableApplyFilter,
        .clearFilter = vtableClearFilter,
    };

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *LogsView = @ptrCast(@alignCast(ptr));
        self.visible_rows = if (height > 1) height - 1 else 0;

        if (self.filtered_indices.items.len == 0) {
            const Theme = theme_loader;
            const msg = if (self.filter_text.len > 0) "No matching lines" else "No logs available";
            try Theme.writeStringWithTheme(terminal, x, y, msg, self.theme.inactive_fg, self.theme.main_bg);
            return;
        }

        // Draw log lines
        const total_lines: u32 = @intCast(self.filtered_indices.items.len);
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + self.visible_rows, total_lines);
        const content_width: u16 = if (width > 2) width - 2 else 1;

        for (start_row..end_row, 0..) |filtered_idx, display_idx| {
            const line_idx = self.filtered_indices.items[filtered_idx];
            const line = self.lines.items[line_idx];
            const row_y = y + @as(u16, @intCast(display_idx));

            try terminal.setCursor(x, row_y);

            const display_line = line[0..@min(line.len, content_width)];

            if (self.filter_text.len > 0) {
                // Render with highlighted matches
                try self.renderHighlightedLine(terminal, display_line);
            } else {
                try terminal.writeAll(self.theme.main_fg);
                try terminal.writeAll(display_line);
            }
            try terminal.writeAll("\x1b[0m");
        }
    }

    /// Render a line with filter matches highlighted
    fn renderHighlightedLine(self: *LogsView, terminal: *Terminal, line: []const u8) !void {
        var pos: usize = 0;
        const needle_len = self.filter_text.len;

        while (pos < line.len) {
            // Find next case-insensitive match
            const match_pos = self.findNextMatch(line, pos);
            if (match_pos) |mp| {
                // Write text before match in normal color
                if (mp > pos) {
                    try terminal.writeAll(self.theme.main_fg);
                    try terminal.writeAll(line[pos..mp]);
                }
                // Write matched text highlighted (black on yellow)
                try terminal.writeAll("\x1b[30;43m");
                try terminal.writeAll(line[mp .. mp + needle_len]);
                try terminal.writeAll("\x1b[0m");
                pos = mp + needle_len;
            } else {
                // No more matches, write remaining text
                try terminal.writeAll(self.theme.main_fg);
                try terminal.writeAll(line[pos..]);
                break;
            }
        }
    }

    fn findNextMatch(self: *LogsView, haystack: []const u8, start: usize) ?usize {
        const needle = self.filter_text;
        if (needle.len == 0) return null;
        if (start + needle.len > haystack.len) return null;
        for (start..haystack.len - needle.len + 1) |i| {
            var match = true;
            for (0..needle.len) |j| {
                if (toLower(haystack[i + j]) != toLower(needle[j])) {
                    match = false;
                    break;
                }
            }
            if (match) return i;
        }
        return null;
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *LogsView = @ptrCast(@alignCast(ptr));

        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    if (self.selected_row + 1 < self.filtered_indices.items.len) {
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
                '/' => return .request_filter,
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
                if (self.selected_row + 1 < self.filtered_indices.items.len) {
                    self.selected_row += 1;
                    if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .shift_g => {
                if (self.filtered_indices.items.len > 0) {
                    self.selected_row = @intCast(self.filtered_indices.items.len - 1);
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
                if (self.selected_row + self.visible_rows < self.filtered_indices.items.len) {
                    self.selected_row += self.visible_rows;
                    if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                } else if (self.filtered_indices.items.len > 0) {
                    self.selected_row = @intCast(self.filtered_indices.items.len - 1);
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
                if (self.filtered_indices.items.len > 0) {
                    self.selected_row = @intCast(self.filtered_indices.items.len - 1);
                    if (self.selected_row >= self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .escape => return .not_handled,
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("LogsView: View activated", .{});
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("LogsView: View deactivated", .{});
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "logs";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.logsHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *LogsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
