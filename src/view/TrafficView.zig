const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const K8sService = @import("../services/K8sService.zig").K8sService;
const kt = @import("kubectl_traffic");

pub const FrameState = enum {
    loading,
    ready,
    unavailable,
};

/// UI-owned traffic frame. Background work may only reach this state through
/// the supervised envelope commit.
pub const TrafficView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    workload: []const u8 = "",
    namespace: []const u8 = "",
    cached_arena: ?std.heap.ArenaAllocator = null,
    cached_lines: ?[]kt.line.StyledLine = null,
    state: FrameState = .loading,
    refresh_requested: bool = false,
    scroll_offset: u32 = 0,
    visible_rows: u32 = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) TrafficView {
        return .{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
        };
    }

    pub fn deinit(self: *TrafficView) void {
        if (self.cached_arena) |*arena| arena.deinit();
        self.cached_arena = null;
        self.cached_lines = null;
    }

    pub fn setTarget(self: *TrafficView, workload: []const u8, namespace: []const u8) void {
        self.workload = workload;
        self.namespace = namespace;
        self.scroll_offset = 0;
        if (self.cached_arena) |*arena| arena.deinit();
        self.cached_arena = null;
        self.cached_lines = null;
        self.state = .loading;
        self.refresh_requested = true;
    }

    pub fn matchesTarget(
        self: *const TrafficView,
        workload: []const u8,
        namespace: []const u8,
    ) bool {
        return std.mem.eql(u8, self.workload, workload) and
            std.mem.eql(u8, self.namespace, namespace);
    }

    /// Installs the complete replacement before freeing the previous arena.
    pub fn commitFrame(
        self: *TrafficView,
        arena: std.heap.ArenaAllocator,
        lines: []kt.line.StyledLine,
        state: FrameState,
    ) void {
        var previous = self.cached_arena;
        self.cached_arena = arena;
        self.cached_lines = lines;
        self.state = state;
        if (previous) |*old| old.deinit();
    }

    pub fn takeRefreshRequest(self: *TrafficView) bool {
        const requested = self.refresh_requested;
        self.refresh_requested = false;
        return requested;
    }

    fn ansiColor(color: kt.line.Color, theme: *const theme_loader.ThemeColors) []const u8 {
        return switch (color) {
            .default => theme.main_fg,
            .dim => theme.inactive_fg,
            .green => theme.status_running,
            .yellow => theme.status_pending,
            .red => theme.status_failed,
            .cyan => theme.title_highlight,
        };
    }

    pub fn createView(self: *TrafficView) View {
        return View.create(TrafficView, self, &vtable);
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinitView,
        .refresh = vtableRefresh,
    };

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));
        self.visible_rows = height;
        if (!self.k8s_service.isConnected()) {
            try theme_loader.writeStringWithTheme(
                terminal,
                x,
                y,
                "Not connected — traffic data unavailable",
                self.theme.inactive_fg,
                self.theme.main_bg,
            );
            return;
        }
        switch (self.state) {
            .loading => {
                try theme_loader.writeStringWithTheme(
                    terminal,
                    x,
                    y,
                    "Loading traffic data…",
                    self.theme.inactive_fg,
                    self.theme.main_bg,
                );
                return;
            },
            .unavailable => {
                try theme_loader.writeStringWithTheme(
                    terminal,
                    x,
                    y,
                    "Failed to fetch traffic data — check Prometheus connectivity",
                    self.theme.status_failed,
                    self.theme.main_bg,
                );
                return;
            },
            .ready => {},
        }

        const lines = self.cached_lines orelse {
            try theme_loader.writeStringWithTheme(
                terminal,
                x,
                y,
                "No traffic data",
                self.theme.inactive_fg,
                self.theme.main_bg,
            );
            return;
        };
        const total: u32 = @intCast(lines.len);
        if (self.visible_rows > 0 and self.scroll_offset + self.visible_rows > total) {
            self.scroll_offset = if (total > self.visible_rows) total - self.visible_rows else 0;
        }
        const end_row = @min(self.scroll_offset + self.visible_rows, total);
        for (lines[self.scroll_offset..end_row], 0..) |line, display_idx| {
            try terminal.setCursor(x, y + @as(u16, @intCast(display_idx)));
            var column: u16 = 0;
            for (line.spans) |span| {
                if (column >= width) break;
                try terminal.writeAll(ansiColor(span.color, self.theme));
                try terminal.writeAll(self.theme.main_bg);
                const text_len = @min(span.text.len, width - column);
                try terminal.writeAll(span.text[0..text_len]);
                try terminal.writeAll("\x1b[0m");
                column += @intCast(text_len);
                if (column < width) {
                    try terminal.writeAll(" ");
                    column += 1;
                }
            }
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));
        switch (key) {
            .ctrl_r => {
                self.refresh_requested = true;
                return .handled;
            },
            .char => |character| switch (character) {
                'q' => return .not_handled,
                'r' => {
                    self.refresh_requested = true;
                    return .handled;
                },
                'j' => {
                    self.scrollDown();
                    return .handled;
                },
                'k' => {
                    if (self.scroll_offset > 0) self.scroll_offset -= 1;
                    return .handled;
                },
                else => return .not_handled,
            },
            .down => {
                self.scrollDown();
                return .handled;
            },
            .up => {
                if (self.scroll_offset > 0) self.scroll_offset -= 1;
                return .handled;
            },
            .escape => return .not_handled,
            else => return .not_handled,
        }
    }

    fn scrollDown(self: *TrafficView) void {
        const total: u32 = if (self.cached_lines) |lines| @intCast(lines.len) else 0;
        if (self.visible_rows > 0 and self.scroll_offset + self.visible_rows < total) {
            self.scroll_offset += 1;
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));
        if (self.cached_lines == null) self.refresh_requested = true;
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "traffic";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        const hints = comptime [_]hints_model.Hint{
            hints_model.Hint.highlighted("r", "", "efresh", 10),
            hints_model.Hint.plain("<q/Esc> back", 20),
            hints_model.Hint.highlighted("j", "", "/k scroll", 30),
        };
        return .{ .hints = &hints };
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));
        self.refresh_requested = true;
    }
};
