const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const ObjectTimeline = @import("../viewmodel/ObjectTimeline.zig").ObjectTimeline;
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const table_layout = @import("../ui/table_layout.zig");

pub const TimelineView = struct {
    theme: *const theme_loader.ThemeColors,
    timeline: *ObjectTimeline,
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    visible_rows: u32 = 0,
    title_buf: [192]u8 = undefined,

    pub fn init(theme: *const theme_loader.ThemeColors, timeline: *ObjectTimeline) TimelineView {
        return .{ .theme = theme, .timeline = timeline };
    }

    pub fn createView(self: *TimelineView) View {
        return View.create(TimelineView, self, &vtable);
    }

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *TimelineView = @ptrCast(@alignCast(ptr));
        self.visible_rows = height;
        if (self.timeline.entries.items.len == 0) {
            try theme_loader.writeStringWithTheme(terminal, x, y, "No changes observed in this session", self.theme.inactive_fg, self.theme.main_bg);
            return;
        }
        const end = @min(self.timeline.entries.items.len, self.scroll_offset + self.visible_rows);
        for (self.timeline.entries.items[self.scroll_offset..end], 0..) |entry, index| {
            const selected = self.scroll_offset + index == self.selected_row;
            const fg = if (selected) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (selected) self.theme.selected_bg else self.theme.main_bg;
            var buffer: [512]u8 = undefined;
            const line = std.fmt.bufPrint(&buffer, "{d}  r{d}  {s}", .{
                entry.timestamp,
                entry.revision,
                entry.summary,
            }) catch entry.summary;
            try terminal.fillRow(x, y + @as(u16, @intCast(index)), width, fg, bg);
            try theme_loader.writeStringWithTheme(
                terminal,
                x,
                y + @as(u16, @intCast(index)),
                table_layout.utf8TruncateCols(line, width),
                fg,
                bg,
            );
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *TimelineView = @ptrCast(@alignCast(ptr));
        switch (key) {
            .up => {
                self.moveUp();
                return .handled;
            },
            .char => |value| {
                if (value == 'k') self.moveUp() else if (value == 'j') self.moveDown() else return .not_handled;
                return .handled;
            },
            .down => {
                self.moveDown();
                return .handled;
            },
            else => return .not_handled,
        }
    }

    fn moveUp(self: *TimelineView) void {
        if (self.selected_row > 0) self.selected_row -= 1;
        if (self.selected_row < self.scroll_offset) self.scroll_offset = self.selected_row;
    }

    fn moveDown(self: *TimelineView) void {
        const count: u32 = @intCast(self.timeline.entries.items.len);
        if (self.selected_row + 1 < count) self.selected_row += 1;
        if (self.visible_rows > 0 and self.selected_row >= self.scroll_offset + self.visible_rows)
            self.scroll_offset = self.selected_row - self.visible_rows + 1;
    }

    fn getTitle(ptr: *anyopaque) []const u8 {
        const self: *TimelineView = @ptrCast(@alignCast(ptr));
        return std.fmt.bufPrint(&self.title_buf, "Timeline {s}[{d}]", .{
            self.timeline.source,
            self.timeline.entries.items.len,
        }) catch "Timeline";
    }

    fn noop(_: *anyopaque) void {}
    fn name(_: *anyopaque) []const u8 {
        return "timeline";
    }
    fn hints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.commonHints();
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = noop,
        .onHide = noop,
        .getName = name,
        .getTitle = getTitle,
        .getHints = hints,
        .deinit = noop,
    };
};

test "empty unrendered timeline navigation stays at origin" {
    var timeline = ObjectTimeline.init(std.testing.allocator);
    defer timeline.deinit();
    var view = TimelineView.init(undefined, &timeline);
    try std.testing.expectEqual(View.KeyResult.handled, try TimelineView.handleKey(&view, .down));
    try std.testing.expectEqual(View.KeyResult.handled, try TimelineView.handleKey(&view, .{ .char = 'j' }));
    try std.testing.expectEqual(@as(u32, 0), view.selected_row);
    try std.testing.expectEqual(@as(u32, 0), view.scroll_offset);
}
