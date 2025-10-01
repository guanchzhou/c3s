/// ContextsView - View for managing Kubernetes contexts
const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = @import("../theme.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const K8sService = @import("../services/k8s_service.zig").K8sService;
const Logger = @import("../core/logger.zig");

pub const ContextsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    items: std.ArrayListUnmanaged(K8sService.ContextInfo),
    selected_row: usize,
    scroll_offset: usize,
    loading: bool,
    error_message: ?[]const u8,

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !ContextsView {
        return ContextsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = .{},
            .selected_row = 0,
            .scroll_offset = 0,
            .loading = false,
            .error_message = null,
        };
    }

    pub fn deinit(self: *ContextsView) void {
        for (self.items.items) |item| {
            self.allocator.free(item.name);
            self.allocator.free(item.cluster);
            self.allocator.free(item.user);
            if (item.namespace) |ns| self.allocator.free(ns);
        }
        self.items.deinit(self.allocator);
        if (self.error_message) |msg| self.allocator.free(msg);
    }

    pub fn refresh(self: *ContextsView) !void {
        self.loading = true;
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }
        for (self.items.items) |item| {
            self.allocator.free(item.name);
            self.allocator.free(item.cluster);
            self.allocator.free(item.user);
            if (item.namespace) |ns| self.allocator.free(ns);
        }
        self.items.clearRetainingCapacity();

        const contexts = self.k8s_service.listContexts() catch |err| {
            self.error_message = try std.fmt.allocPrint(self.allocator, "Failed: {}", .{err});
            self.loading = false;
            return;
        };
        defer self.allocator.free(contexts);

        for (contexts) |ctx| {
            try self.items.append(self.allocator, ctx);
        }
        self.loading = false;

        if (self.selected_row >= self.items.items.len and self.items.items.len > 0) {
            self.selected_row = self.items.items.len - 1;
        }
    }

    pub fn createView(self: *ContextsView) View {
        return View.create(ContextsView, self, &vtable);
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

    fn render(ctx: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) anyerror!void {
        const self: *ContextsView = @ptrCast(@alignCast(ctx));
        _ = width;
        if (self.loading) {
            try Theme.writeStringWithTheme(terminal, x, y, "Loading contexts...", self.theme.main_fg, self.theme.main_bg);
            return;
        }
        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(terminal, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }
        if (self.items.items.len == 0) {
            try Theme.writeStringWithTheme(terminal, x, y, "No contexts found", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        // Header
        try Theme.writeStringWithTheme(terminal, x, y, "CURRENT  NAME                           CLUSTER                        NAMESPACE", self.theme.title, self.theme.main_bg);

        // Render contexts
        var row: u16 = 1;
        const visible_rows = height -| 1;
        for (self.items.items, 0..) |item, i| {
            if (i < self.scroll_offset) continue;
            if (row >= visible_rows) break;

            const is_selected = (i == self.selected_row);
            const fg = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            const current_marker = if (item.is_current) "*" else " ";
            const ns = item.namespace orelse "default";

            const line = try std.fmt.allocPrint(self.allocator, "{s}        {s: <30} {s: <30} {s}", .{ current_marker, item.name, item.cluster, ns });
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(terminal, x, y + row, line, fg, bg);
            row += 1;
        }
    }

    fn handleKey(ctx: *anyopaque, key: Key) anyerror!KeyResult {
        const self: *ContextsView = @ptrCast(@alignCast(ctx));
        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    if (self.selected_row < self.items.items.len -| 1) self.selected_row += 1;
                    return .handled;
                },
                'k' => {
                    if (self.selected_row > 0) self.selected_row -= 1;
                    return .handled;
                },
                'r' => {
                    try self.refresh();
                    return .handled;
                },
                '\r', '\n' => {
                    // Switch to selected context
                    if (self.items.items.len > 0) {
                        const selected = self.items.items[self.selected_row];
                        try self.k8s_service.switchContext(selected.name);
                        try self.refresh();
                    }
                    return .handled;
                },
                'q' => return .request_quit,
                ':' => return .request_command_palette,
                else => return .not_handled,
            },
            .down => {
                if (self.selected_row < self.items.items.len -| 1) self.selected_row += 1;
                return .handled;
            },
            .up => {
                if (self.selected_row > 0) self.selected_row -= 1;
                return .handled;
            },
            else => return .not_handled,
        }
    }

    fn onShow(ctx: *anyopaque) void {
        const self: *ContextsView = @ptrCast(@alignCast(ctx));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh contexts: {}", .{err});
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "Contexts";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.HintConfig{
            .hints = &[_]hints_model.Hint{
                hints_model.Hint.plain("j/k navigate", 1),
                hints_model.Hint.plain("Enter switch", 2),
                hints_model.Hint.plain("r refresh", 3),
            },
        };
    }

    fn deinitView(ctx: *anyopaque) void {
        const self: *ContextsView = @ptrCast(@alignCast(ctx));
        self.deinit();
    }
};
