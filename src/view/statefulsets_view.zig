/// StatefulSetsView - View for Kubernetes StatefulSets
const std = @import("std");
const klient = @import("klient");
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const hints_model = @import("../model/hints.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const view_mod = @import("../viewmodel/view.zig");
const ResourceInfo = view_mod.ResourceInfo;
const Logger = @import("../core/logger.zig");
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");
const TableState = @import("../ui/table_state.zig").TableState;

pub const StatefulSetsView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(StatefulSetInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const StatefulSetInfo = struct {
        name: []const u8,
        namespace: []const u8,
        ready: i32,
        desired: i32,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *StatefulSetInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.namespace);
            self.allocator.free(self.age);
        }

        fn getName(self: *const StatefulSetInfo) []const u8 { return self.name; }
        fn getAge(self: *const StatefulSetInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !StatefulSetsView {
        return StatefulSetsView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(StatefulSetInfo).init(allocator),
        };
    }

    pub fn deinit(self: *StatefulSetsView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *StatefulSetsView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        const statefulsets = if (self.table.show_all_namespaces)
            self.k8s_service.listAllStatefulSets() catch |err| {
                try self.table.setErrorFmt("Failed to list statefulsets: {}", .{err});
                return;
            }
        else
            self.k8s_service.listStatefulSets(null) catch |err| {
                try self.table.setErrorFmt("Failed to list statefulsets: {}", .{err});
                return;
            };
        defer self.table.allocator.free(statefulsets);

        for (statefulsets) |sts| {
            // Extract readyReplicas from JSON Value
            const ready: i32 = if (sts.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("readyReplicas")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            const desired = if (sts.spec) |s| s.replicas orelse 0 else 0;

            try self.table.appendItem(.{
                .name = try self.table.allocator.dupe(u8, sts.metadata.name),
                .namespace = try self.table.allocator.dupe(u8, sts.metadata.namespace orelse "default"),
                .ready = ready,
                .desired = desired,
                .age = try age_util.calculateAge(self.table.allocator, sts.metadata.creationTimestamp),
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *StatefulSetsView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{ .name = item.name, .namespace = item.namespace };
    }

    pub fn applyFilter(self: *StatefulSetsView, filter: []const u8) !void {
        try self.table.applyFilter(filter, statefulsetMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *StatefulSetsView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(StatefulSetInfo.getName),
                COL_AGE => self.table.sortBy(StatefulSetInfo.getAge),
                else => {},
            }
        }
    }

    fn statefulsetMatchFn(item: *const StatefulSetInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *StatefulSetsView) View {
        return View.create(StatefulSetsView, self, &vtable);
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
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));
        _ = width;
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(term, x, y, self.theme)) return;

        // Header with sort indicators
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             NAME{s: <30}READY      AGE{s}", .{ name_ind, age_ind }) catch "  NAMESPACE             NAME                          READY      AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        // Data rows
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |actual_idx, i| {
            const item = self.table.items.items[actual_idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            const formatted = try std.fmt.allocPrint(
                self.table.allocator,
                "  {s: <20} {s: <28} {d}/{d: <6} {s}",
                .{
                    if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                    if (item.name.len > 28) item.name[0..28] else item.name,
                    item.ready,
                    item.desired,
                    item.age,
                },
            );
            defer self.table.allocator.free(formatted);

            try Theme.writeStringWithTheme(term, x, row_y, formatted, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh statefulsets: {}", .{err});
                    return .handled;
                },
                '0' => {
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    self.table.gotoTop();
                    self.refresh() catch |err| Logger.err("Failed to refresh statefulsets: {}", .{err});
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
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh statefulsets: {any}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {};
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "statefulsets";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
