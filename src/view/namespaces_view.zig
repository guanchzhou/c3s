/// Namespaces View - Display and switch between Kubernetes namespaces
const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = theme_loader;
const theme_loader = @import("../model/theme_loader.zig");
const View = @import("../viewmodel/view.zig").View;
const Key = @import("../core/terminal.zig").Key;
const KeyResult = View.KeyResult;
const Logger = @import("../core/logger.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const view_mod = @import("../viewmodel/view.zig");
const ResourceInfo = view_mod.ResourceInfo;
const klient = @import("klient");
const hints_model = @import("../model/hints.zig");
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");
const TableState = @import("../ui/table_state.zig").TableState;

pub const NamespacesView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(NamespaceInfo),
    current_namespace: []const u8,

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;
    const COL_STATUS: u8 = 2;

    const NamespaceInfo = struct {
        name: []const u8,
        status: []const u8,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *NamespaceInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.status);
            self.allocator.free(self.age);
        }

        fn getName(self: *const NamespaceInfo) []const u8 { return self.name; }
        fn getAge(self: *const NamespaceInfo) []const u8 { return self.age; }
        fn getStatus(self: *const NamespaceInfo) []const u8 { return self.status; }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) !NamespacesView {
        const current_ns = k8s_service.getCurrentNamespace();

        return NamespacesView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(NamespaceInfo).init(allocator),
            .current_namespace = try allocator.dupe(u8, current_ns),
        };
    }

    pub fn deinit(self: *NamespacesView) void {
        self.table.allocator.free(self.current_namespace);
        self.table.deinit();
    }

    /// Refresh namespaces list from K8s API
    pub fn refresh(self: *NamespacesView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        // SAFETY: Check if connected to k8s before making requests
        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            Logger.warn("NamespacesView: Cannot refresh - not connected to k8s", .{});
            return;
        }

        // Fetch namespaces
        const k8s_namespaces = self.k8s_service.listNamespaces() catch |err| {
            try self.table.setConnectionError("namespaces", err);
            return;
        };

        // Convert to NamespaceInfo
        var selected_idx: ?usize = null;
        for (k8s_namespaces, 0..) |ns, i| {
            // Extract status from JSON value
            const status = if (ns.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("phase")) |phase| {
                        if (phase == .string) {
                            break :blk try self.table.allocator.dupe(u8, phase.string);
                        }
                    }
                }
                break :blk try self.table.allocator.dupe(u8, "Active");
            } else try self.table.allocator.dupe(u8, "Unknown");

            const info = NamespaceInfo{
                .name = try self.table.allocator.dupe(u8, ns.metadata.name),
                .status = status,
                .age = try age_util.calculateAge(self.table.allocator, ns.metadata.creationTimestamp),
                .allocator = self.table.allocator,
            };

            // Check if this is the current namespace
            if (std.mem.eql(u8, info.name, self.current_namespace)) {
                selected_idx = i;
            }

            try self.table.appendItem(info);
        }

        // Set selected row to current namespace
        if (selected_idx) |idx| {
            self.table.selected_row = @intCast(idx);
            if (self.table.selected_row >= self.table.visible_rows) {
                self.table.scroll_offset = self.table.selected_row - self.table.visible_rows / 2;
            }
        }

        Logger.info("Loaded {} namespaces", .{self.table.items.items.len});

        // Rebuild filtered indices
        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *NamespacesView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{
            .name = item.name,
            .namespace = "cluster",
        };
    }

    pub fn applyFilter(self: *NamespacesView, filter: []const u8) !void {
        try self.table.applyFilter(filter, namespaceMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *NamespacesView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(NamespaceInfo.getName),
                COL_AGE => self.table.sortBy(NamespaceInfo.getAge),
                COL_STATUS => self.table.sortBy(NamespaceInfo.getStatus),
                else => {},
            }
        }
    }

    fn namespaceMatchFn(item: *const NamespaceInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null;
    }

    /// Switch to the selected namespace
    fn switchNamespace(self: *NamespacesView) !void {
        const item = self.table.getSelectedItem() orelse return;
        const selected_ns = item.name;

        // Update K8s service namespace
        try self.k8s_service.setCurrentNamespace(selected_ns);

        // Update our current namespace
        self.table.allocator.free(self.current_namespace);
        self.current_namespace = try self.table.allocator.dupe(u8, selected_ns);

        Logger.info("Switched to namespace: {s}", .{selected_ns});
    }

    pub fn createView(self: *NamespacesView) View {
        return View.create(NamespacesView, self, &vtable);
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

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, _: u16, height: u16) !void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(terminal, x, y, self.theme)) return;

        // Render header row with sort indicators
        const header_y = y;
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        const status_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_STATUS);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        var status_hdr_buf: [32]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        const status_hdr = std.fmt.bufPrint(&status_hdr_buf, "STATUS{s}", .{status_ind}) catch "STATUS";
        try Theme.writeStringWithTheme(terminal, x, header_y, name_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 39, header_y, status_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 59, header_y, age_hdr, self.theme.title, self.theme.main_bg);

        // Render namespaces
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |ns_idx, i| {
            const ns = self.table.items.items[ns_idx];
            const colors = self.table.rowColors(i, self.theme);
            const is_current = std.mem.eql(u8, ns.name, self.current_namespace);
            const row_y = y + 1 + @as(u16, @intCast(i));

            // Current namespace indicator
            const indicator = if (is_current) "* " else "  ";
            try Theme.writeStringWithTheme(terminal, x, row_y, indicator, colors.fg, colors.bg);

            // Name
            try Theme.writeStringWithTheme(terminal, x + 2, row_y, ns.name[0..@min(36, ns.name.len)], colors.fg, colors.bg);

            // Status
            try Theme.writeStringWithTheme(terminal, x + 39, row_y, ns.status, colors.fg, colors.bg);

            // Age
            try Theme.writeStringWithTheme(terminal, x + 59, row_y, ns.age, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| {
                        Logger.err("Failed to refresh namespaces: {}", .{err});
                    };
                    return .handled;
                },
                '\n', '\r' => {
                    // Switch to selected namespace
                    self.switchNamespace() catch |err| {
                        Logger.err("Failed to switch namespace: {}", .{err});
                    };
                    return .handled;
                },
                'N' => { self.table.toggleSort(COL_NAME); self.applySorting(); return .handled; },
                'A' => { self.table.toggleSort(COL_AGE); self.applySorting(); return .handled; },
                'S' => { self.table.toggleSort(COL_STATUS); self.applySorting(); return .handled; },
                else => return .not_handled,
            },
            .enter => {
                // Switch to selected namespace
                self.switchNamespace() catch |err| {
                    Logger.err("Failed to switch namespace: {}", .{err});
                };
                return .handled;
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        Logger.info("NamespacesView: View activated", .{});
        // Refresh data when view is shown - catch ALL errors to prevent crashes
        self.refresh() catch |err| {
            Logger.err("Failed to refresh namespaces: {any}", .{err});
            // Set a fallback error message if one wasn't already set
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {
                    Logger.err("Failed to allocate error message", .{});
                    return;
                };
            }
        };
    }

    fn onHide(_: *anyopaque) void {
        Logger.debug("NamespacesView hidden", .{});
    }

    fn getName(_: *anyopaque) []const u8 {
        return "namespaces";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
