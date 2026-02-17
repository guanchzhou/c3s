/// ContextsView - View for managing Kubernetes contexts
const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = @import("../theme.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const ResourceInfo = k8s_service_mod.ResourceInfo;
const Logger = @import("../core/logger.zig");
const sort_util = @import("../viewmodel/sort.zig");

pub const ContextsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    items: std.ArrayListUnmanaged(K8sService.ContextInfo),
    filtered_indices: std.ArrayListUnmanaged(usize),
    selected_row: u32,
    scroll_offset: u32,
    visible_rows: u32,
    loading: bool,
    error_message: ?[]const u8,
    filter_text: []const u8,
    sort_column: ?u8 = null,
    sort_ascending: bool = true,

    // Sort column indices
    const COL_NAME: u8 = 0;

    fn getContextName(item: *const K8sService.ContextInfo) []const u8 { return item.name; }

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !ContextsView {
        return ContextsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = .{},
            .filtered_indices = .{},
            .selected_row = 0,
            .scroll_offset = 0,
            .visible_rows = 0,
            .loading = false,
            .error_message = null,
            .filter_text = "",
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
        self.filtered_indices.deinit(self.allocator);
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
            self.selected_row = @intCast(self.items.items.len - 1);
        }
        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *ContextsView) ?ResourceInfo {
        _ = self;
        return null;
    }

    pub fn applyFilter(self: *ContextsView, filter: []const u8) !void {
        self.filter_text = filter;
        self.filtered_indices.clearRetainingCapacity();
        for (self.items.items, 0..) |item, i| {
            if (filter.len == 0 or std.mem.indexOf(u8, item.name, filter) != null or
                std.mem.indexOf(u8, item.cluster, filter) != null)
            {
                try self.filtered_indices.append(self.allocator, i);
            }
        }
        if (self.selected_row >= self.filtered_indices.items.len and self.filtered_indices.items.len > 0) {
            self.selected_row = @intCast(self.filtered_indices.items.len - 1);
        }
        self.applySorting();
    }

    fn applySorting(self: *ContextsView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(K8sService.ContextInfo, self.items.items, &self.filtered_indices, getContextName, self.sort_ascending),
                else => {},
            }
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
        self.visible_rows = if (height > 1) height - 1 else 0;
        if (self.loading) {
            try Theme.writeStringWithTheme(terminal, x, y, "Loading contexts...", self.theme.main_fg, self.theme.main_bg);
            return;
        }
        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(terminal, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }
        if (self.filtered_indices.items.len == 0) {
            try Theme.writeStringWithTheme(terminal, x, y, "No contexts found", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        // Header with sort indicators
        var name_hdr_buf: [32]u8 = undefined;
        const name_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_NAME);
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "CURRENT  {s: <31}CLUSTER                        NAMESPACE", .{name_hdr}) catch "CURRENT  NAME                           CLUSTER                        NAMESPACE";
        try Theme.writeStringWithTheme(terminal, x, y, header, self.theme.title, self.theme.main_bg);

        // Render contexts using filtered_indices
        var row: u16 = 1;
        const visible_rows_count = height -| 1;
        var fi: u32 = self.scroll_offset;
        while (row < visible_rows_count and fi < self.filtered_indices.items.len) : ({ row += 1; fi += 1; }) {
            const idx = self.filtered_indices.items[fi];
            const item = self.items.items[idx];

            const is_selected = (fi == self.selected_row);
            const fg = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            const current_marker = if (item.is_current) "*" else " ";
            const ns = item.namespace orelse "default";

            const line = try std.fmt.allocPrint(self.allocator, "{s}        {s: <30} {s: <30} {s}", .{ current_marker, item.name, item.cluster, ns });
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(terminal, x, y + row, line, fg, bg);
        }
    }

    fn handleKey(ctx: *anyopaque, key: Key) anyerror!KeyResult {
        const self: *ContextsView = @ptrCast(@alignCast(ctx));
        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    if (self.selected_row < self.filtered_indices.items.len -| 1) self.selected_row += 1;
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
                    if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len) {
                        const idx = self.filtered_indices.items[self.selected_row];
                        const selected = self.items.items[idx];
                        try self.k8s_service.switchContext(selected.name);
                        try self.refresh();
                    }
                    return .handled;
                },
                'N' => {
                    sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_NAME);
                    self.applySorting();
                    return .handled;
                },
                'd' => return .request_describe,
                'y' => return .request_yaml,
                '/' => return .request_filter,
                'q' => return .request_quit,
                ':' => return .request_command_palette,
                else => return .not_handled,
            },
            .down => {
                if (self.selected_row < self.filtered_indices.items.len -| 1) self.selected_row += 1;
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
        return hints_model.resourceHints();
    }

    fn deinitView(ctx: *anyopaque) void {
        const self: *ContextsView = @ptrCast(@alignCast(ctx));
        self.deinit();
    }
};
