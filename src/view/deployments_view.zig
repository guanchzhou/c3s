/// Deployments View - Display and manage Kubernetes deployments
const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
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

pub const DeploymentsView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(DeploymentInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const DeploymentInfo = struct {
        name: []const u8,
        namespace: []const u8,
        replicas: i32,
        ready_replicas: i32,
        available_replicas: i32,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *DeploymentInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.namespace);
            self.allocator.free(self.age);
        }

        fn getName(self: *const DeploymentInfo) []const u8 { return self.name; }
        fn getAge(self: *const DeploymentInfo) []const u8 { return self.age; }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) !DeploymentsView {
        return DeploymentsView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(DeploymentInfo).init(allocator),
        };
    }

    pub fn deinit(self: *DeploymentsView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *DeploymentsView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        const k8s_deployments = if (self.table.show_all_namespaces)
            self.k8s_service.listAllDeployments() catch |err| {
                try self.table.setErrorFmt("Failed to list deployments: {}", .{err});
                return;
            }
        else
            self.k8s_service.listDeployments(null) catch |err| {
                try self.table.setErrorFmt("Failed to list deployments: {}", .{err});
                return;
            };

        for (k8s_deployments) |dep| {
            const ready_replicas: i32 = if (dep.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("readyReplicas")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            const available_replicas: i32 = if (dep.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("availableReplicas")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            try self.table.appendItem(.{
                .name = try self.table.allocator.dupe(u8, dep.metadata.name),
                .namespace = if (dep.metadata.namespace) |ns|
                    try self.table.allocator.dupe(u8, ns)
                else
                    try self.table.allocator.dupe(u8, "default"),
                .replicas = dep.spec.?.replicas orelse 0,
                .ready_replicas = ready_replicas,
                .available_replicas = available_replicas,
                .age = try age_util.calculateAge(self.table.allocator, dep.metadata.creationTimestamp),
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *DeploymentsView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{ .name = item.name, .namespace = item.namespace };
    }

    pub fn applyFilter(self: *DeploymentsView, filter: []const u8) !void {
        try self.table.applyFilter(filter, deploymentMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *DeploymentsView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(DeploymentInfo.getName),
                COL_AGE => self.table.sortBy(DeploymentInfo.getAge),
                else => {},
            }
        }
    }

    fn deploymentMatchFn(item: *const DeploymentInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *DeploymentsView) View {
        return View.create(DeploymentsView, self, &vtable);
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
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));
        _ = width;
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(terminal, x, y, self.theme)) return;

        // Header row with sort indicators
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        try Theme.writeStringWithTheme(terminal, x, y, "NAMESPACE", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 19, y, name_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 49, y, "READY", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 61, y, "AVAILABLE", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 77, y, age_hdr, self.theme.title, self.theme.main_bg);

        // Data rows
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |dep_idx, i| {
            const dep = self.table.items.items[dep_idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            try Theme.writeStringWithTheme(terminal, x, row_y, dep.namespace[0..@min(18, dep.namespace.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 19, row_y, dep.name[0..@min(28, dep.name.len)], colors.fg, colors.bg);

            var ready_buf: [16]u8 = undefined;
            const ready_str = try std.fmt.bufPrint(&ready_buf, "{d}/{d}", .{ dep.ready_replicas, dep.replicas });
            try Theme.writeStringWithTheme(terminal, x + 49, row_y, ready_str, colors.fg, colors.bg);

            var avail_buf: [16]u8 = undefined;
            const avail_str = try std.fmt.bufPrint(&avail_buf, "{d}", .{dep.available_replicas});
            try Theme.writeStringWithTheme(terminal, x + 61, row_y, avail_str, colors.fg, colors.bg);

            try Theme.writeStringWithTheme(terminal, x + 77, row_y, dep.age, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh deployments: {}", .{err});
                    return .handled;
                },
                '0' => {
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    self.table.gotoTop();
                    self.refresh() catch |err| Logger.err("Failed to refresh deployments: {}", .{err});
                    return .handled;
                },
                'N' => { self.table.toggleSort(COL_NAME); self.applySorting(); return .handled; },
                'A' => { self.table.toggleSort(COL_AGE); self.applySorting(); return .handled; },
                else => return .not_handled,
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh deployments: {any}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {};
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "deployments";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
