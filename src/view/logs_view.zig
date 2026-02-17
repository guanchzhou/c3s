/// LogsView - Scrollable pod log viewer
const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const BoxDrawing = @import("../ui/box_drawing.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");

pub const LogsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    lines: std.ArrayListUnmanaged([]const u8),
    title: []const u8,
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    visible_rows: u32 = 0,
    auto_scroll: bool = true,

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !LogsView {
        return LogsView{
            .allocator = allocator,
            .theme = theme,
            .lines = std.ArrayListUnmanaged([]const u8){},
            .title = "Logs",
        };
    }

    pub fn cleanup(self: *LogsView) void {
        self.clearContent();
    }

    fn clearContent(self: *LogsView) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();
        if (!std.mem.eql(u8, self.title, "Logs")) {
            self.allocator.free(self.title);
            self.title = "Logs";
        }
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

        // Auto-scroll to bottom
        if (self.auto_scroll and self.lines.items.len > 0) {
            self.selected_row = @intCast(self.lines.items.len - 1);
            if (self.selected_row >= self.visible_rows and self.visible_rows > 0) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }
    }

    // View trait implementation
    pub fn createView(self: *LogsView) View {
        return View.create(LogsView, self, &vtable);
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
        const self: *LogsView = @ptrCast(@alignCast(ptr));
        self.visible_rows = if (height > 3) height - 3 else 0;

        // Draw box
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, self.theme.proc_box, self.theme.main_bg, self.title, .rounded, self.theme.main_fg, self.theme.title);

        if (self.lines.items.len == 0) {
            const Theme = @import("../theme.zig");
            try Theme.writeStringWithTheme(terminal, x + 2, y + height / 2, "No logs available", self.theme.inactive_fg, self.theme.main_bg);
            return;
        }

        // Draw log lines
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + self.visible_rows, self.lines.items.len);
        const content_width: u16 = if (width > 4) width - 4 else 1;

        for (start_row..end_row, 0..) |line_idx, display_idx| {
            const line = self.lines.items[line_idx];
            const row_y = y + @as(u16, @intCast(display_idx)) + 1;

            try terminal.setCursor(x + 2, row_y);
            try terminal.writeAll(self.theme.main_fg);

            const display_len = @min(line.len, content_width);
            if (display_len > 0) {
                try terminal.writeAll(line[0..display_len]);
            }
            try terminal.writeAll("\x1b[0m");
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *LogsView = @ptrCast(@alignCast(ptr));

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
        self.cleanup();
    }
};
