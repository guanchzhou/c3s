/// ReplicaSetsView - View for Kubernetes ReplicaSets
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

pub const ReplicaSetsView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(ReplicaSetInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const ReplicaSetInfo = struct {
        name: []const u8,
        namespace: []const u8,
        desired: i32,
        current: i32,
        ready: i32,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *ReplicaSetInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.namespace);
            self.allocator.free(self.age);
        }

        fn getName(self: *const ReplicaSetInfo) []const u8 { return self.name; }
        fn getAge(self: *const ReplicaSetInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !ReplicaSetsView {
        return ReplicaSetsView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(ReplicaSetInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ReplicaSetsView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *ReplicaSetsView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        const replicasets = if (self.table.show_all_namespaces)
            self.k8s_service.listAllReplicaSets() catch |err| {
                try self.table.setErrorFmt("Failed to list replicasets: {}", .{err});
                return;
            }
        else
            self.k8s_service.listReplicaSets(null) catch |err| {
                try self.table.setErrorFmt("Failed to list replicasets: {}", .{err});
                return;
            };
        defer self.table.allocator.free(replicasets);

        for (replicasets) |rs| {
            const desired = if (rs.spec) |s| s.replicas orelse 0 else 0;

            // Extract status fields from JSON Value
            const current: i32 = if (rs.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("replicas")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            const ready: i32 = if (rs.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("readyReplicas")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            try self.table.appendItem(.{
                .name = try self.table.allocator.dupe(u8, rs.metadata.name),
                .namespace = try self.table.allocator.dupe(u8, rs.metadata.namespace orelse "default"),
                .desired = desired,
                .current = current,
                .ready = ready,
                .age = try age_util.calculateAge(self.table.allocator, rs.metadata.creationTimestamp),
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *ReplicaSetsView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{ .name = item.name, .namespace = item.namespace };
    }

    pub fn applyFilter(self: *ReplicaSetsView, filter: []const u8) !void {
        try self.table.applyFilter(filter, replicasetMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *ReplicaSetsView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(ReplicaSetInfo.getName),
                COL_AGE => self.table.sortBy(ReplicaSetInfo.getAge),
                else => {},
            }
        }
    }

    fn replicasetMatchFn(item: *const ReplicaSetInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *ReplicaSetsView) View {
        return View.create(ReplicaSetsView, self, &vtable);
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
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, _: u16, height: u16) !void {
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(term, x, y, self.theme)) return;

        // Header with sort indicators
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             NAME{s: <28}DESIRED CURRENT READY AGE{s}", .{ name_ind, age_ind }) catch "  NAMESPACE             NAME                          DESIRED CURRENT READY AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        // Data rows
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |actual_idx, i| {
            const item = self.table.items.items[actual_idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            const line = try std.fmt.allocPrint(
                self.table.allocator,
                "  {s: <20} {s: <28} {d: >7} {d: >7} {d: >5} {s}",
                .{
                    if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                    if (item.name.len > 28) item.name[0..28] else item.name,
                    item.desired,
                    item.current,
                    item.ready,
                    item.age,
                },
            );
            defer self.table.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, row_y, line, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh replicasets: {}", .{err});
                    return .handled;
                },
                '0' => {
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    self.table.gotoTop();
                    self.refresh() catch |err| Logger.err("Failed to refresh replicasets: {}", .{err});
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
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh replicasets: {any}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {};
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "replicasets";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
