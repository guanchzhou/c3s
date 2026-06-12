/// ContextsView - View for managing Kubernetes contexts
const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Key = @import("../core/Terminal.zig").Key;
const Terminal = @import("../core/Terminal.zig").Terminal;
const Theme = theme_loader;
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const k8s_service_mod = @import("../services/K8sService.zig");
const K8sService = k8s_service_mod.K8sService;
const view_mod = @import("../viewmodel/view.zig");
const ResourceInfo = view_mod.ResourceInfo;
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

    fn getContextName(item: *const K8sService.ContextInfo) []const u8 {
        return item.name;
    }

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !ContextsView {
        return ContextsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = .empty,
            .filtered_indices = .empty,
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

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *ContextsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }
    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *ContextsView = @ptrCast(@alignCast(ptr));
        if (self.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }
    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *ContextsView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }
    fn vtableGetSelectedResource(ptr: *anyopaque) ?view_mod.ResourceInfo {
        const self: *ContextsView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
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
        .refresh = vtableRefresh,
        .getSelectedResource = vtableGetSelectedResource,
    };

    fn render(ctx: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) anyerror!void {
        const self: *ContextsView = @ptrCast(@alignCast(ctx));
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

        const w: usize = @intCast(width);
        // Column widths: 2 for current marker, rest split 4 ways
        const cw = if (w > 12) (w - 2) / 4 else 3;

        // Header
        var name_hdr_buf: [32]u8 = undefined;
        const name_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_NAME);
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const hdr_line = try buildLine(self.allocator, w, cw, " ", name_hdr, "CLUSTER", "USER", "NAMESPACE");
        defer self.allocator.free(hdr_line);
        try Theme.writeStringWithTheme(terminal, x, y, hdr_line, self.theme.title, self.theme.main_bg);

        // Render contexts using filtered_indices
        var row: u16 = 0;
        var fi: u32 = self.scroll_offset;
        while (row < self.visible_rows and fi < self.filtered_indices.items.len) : ({
            row += 1;
            fi += 1;
        }) {
            const idx = self.filtered_indices.items[fi];
            const item = self.items.items[idx];

            const is_selected = (fi == self.selected_row);
            const fg = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            const current_marker: []const u8 = if (item.is_current) "*" else " ";
            const ns = item.namespace orelse "default";

            const line = try buildLine(self.allocator, w, cw, current_marker, item.name, item.cluster, item.user, ns);
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(terminal, x, y + 1 + row, line, fg, bg);
        }
    }

    /// Build a full-width line with 5 columns padded with spaces.
    fn buildLine(allocator: std.mem.Allocator, total_width: usize, col_w: usize, current: []const u8, name: []const u8, cluster: []const u8, user: []const u8, ns: []const u8) ![]u8 {
        const buf = try allocator.alloc(u8, total_width);
        @memset(buf, ' ');

        // Col 0: current marker (1 char at pos 0)
        if (current.len > 0) buf[0] = current[0];

        // Col 1: name at pos 2
        const name_start: usize = 2;
        const name_len = @min(name.len, col_w -| 1);
        if (name_start + name_len <= total_width) {
            @memcpy(buf[name_start..][0..name_len], name[0..name_len]);
        }

        // Col 2: cluster
        const cluster_start = name_start + col_w;
        const cluster_len = @min(cluster.len, col_w -| 1);
        if (cluster_start + cluster_len <= total_width) {
            @memcpy(buf[cluster_start..][0..cluster_len], cluster[0..cluster_len]);
        }

        // Col 3: user
        const user_start = cluster_start + col_w;
        const user_len = @min(user.len, col_w -| 1);
        if (user_start + user_len <= total_width) {
            @memcpy(buf[user_start..][0..user_len], user[0..user_len]);
        }

        // Col 4: namespace
        const ns_start = user_start + col_w;
        const ns_len = @min(ns.len, total_width -| ns_start);
        if (ns_start + ns_len <= total_width) {
            @memcpy(buf[ns_start..][0..ns_len], ns[0..ns_len]);
        }

        return buf;
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
                    // Switch to selected context, then let the app return to
                    // the view that was active before entering contexts.
                    if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len) {
                        const idx = self.filtered_indices.items[self.selected_row];
                        const selected = self.items.items[idx];
                        try self.k8s_service.switchContext(selected.name);
                        try self.refresh();
                        return .context_switched;
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
            .enter => {
                // Switch to selected context, then let the app return to
                // the view that was active before entering contexts.
                if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len) {
                    const idx = self.filtered_indices.items[self.selected_row];
                    const selected = self.items.items[idx];
                    try self.k8s_service.switchContext(selected.name);
                    try self.refresh();
                    return .context_switched;
                }
                return .handled;
            },
            .page_down => {
                const items_len: u32 = @intCast(self.filtered_indices.items.len);
                const jump = @min(self.visible_rows, items_len -| self.selected_row -| 1);
                self.selected_row += jump;
                if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                    self.scroll_offset = self.selected_row -| self.visible_rows + 1;
                }
                return .handled;
            },
            .page_up => {
                const jump = @min(self.visible_rows, self.selected_row);
                self.selected_row -= jump;
                if (self.selected_row < self.scroll_offset) {
                    self.scroll_offset = self.selected_row;
                }
                return .handled;
            },
            .home => {
                self.selected_row = 0;
                self.scroll_offset = 0;
                return .handled;
            },
            .end => {
                const items_len: u32 = @intCast(self.filtered_indices.items.len);
                if (items_len > 0) {
                    self.selected_row = items_len - 1;
                    if (self.selected_row >= self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
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
        return "contexts";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ctx: *anyopaque) void {
        const self: *ContextsView = @ptrCast(@alignCast(ctx));
        self.deinit();
    }
};
