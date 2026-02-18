/// PersistentVolumeClaimsView - View for Kubernetes PersistentVolumeClaims
const std = @import("std");
const klient = @import("klient");
const view_mod = @import("../viewmodel/view.zig");
const View = view_mod.View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = theme_loader;
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const ResourceInfo = view_mod.ResourceInfo;

const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");
const Logger = @import("../core/logger.zig");
const TableState = @import("../ui/table_state.zig").TableState;

pub const PersistentVolumeClaimsView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(PVCInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;
    const COL_STATUS: u8 = 2;

    const PVCInfo = struct {
        name: []const u8,
        namespace: []const u8,
        status: []const u8,
        volume: []const u8,
        capacity: []const u8,
        access_modes: []const u8,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *PVCInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.namespace);
            self.allocator.free(self.status);
            self.allocator.free(self.volume);
            self.allocator.free(self.capacity);
            self.allocator.free(self.access_modes);
            self.allocator.free(self.age);
        }

        fn getName(self: *const PVCInfo) []const u8 { return self.name; }
        fn getAge(self: *const PVCInfo) []const u8 { return self.age; }
        fn getStatus(self: *const PVCInfo) []const u8 { return self.status; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !PersistentVolumeClaimsView {
        return PersistentVolumeClaimsView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(PVCInfo).init(allocator),
        };
    }

    pub fn deinit(self: *PersistentVolumeClaimsView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *PersistentVolumeClaimsView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        const pvcs = if (self.table.show_all_namespaces)
            self.k8s_service.listAllPersistentVolumeClaims() catch |err| {
                try self.table.setErrorFmt("Failed to list PVCs: {}", .{err});
                return;
            }
        else
            self.k8s_service.listPersistentVolumeClaims(null) catch |err| {
                try self.table.setErrorFmt("Failed to list PVCs: {}", .{err});
                return;
            };
        defer self.table.allocator.free(pvcs);

        for (pvcs) |pvc| {
            try self.table.appendItem(.{
                .name = try self.table.allocator.dupe(u8, pvc.metadata.name),
                .namespace = try self.table.allocator.dupe(u8, pvc.metadata.namespace orelse "default"),
                .status = try self.table.allocator.dupe(u8, "Bound"),
                .volume = try self.table.allocator.dupe(u8, "pv-001"),
                .capacity = try self.table.allocator.dupe(u8, "10Gi"),
                .access_modes = try self.table.allocator.dupe(u8, "RWO"),
                .age = try age_util.calculateAge(self.table.allocator, pvc.metadata.creationTimestamp),
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *PersistentVolumeClaimsView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{ .name = item.name, .namespace = item.namespace };
    }

    pub fn applyFilter(self: *PersistentVolumeClaimsView, filter: []const u8) !void {
        try self.table.applyFilter(filter, pvcMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *PersistentVolumeClaimsView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(PVCInfo.getName),
                COL_AGE => self.table.sortBy(PVCInfo.getAge),
                COL_STATUS => self.table.sortBy(PVCInfo.getStatus),
                else => {},
            }
        }
    }

    fn pvcMatchFn(item: *const PVCInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *PersistentVolumeClaimsView) View {
        return View.create(PersistentVolumeClaimsView, self, &vtable);
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
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, _: u16, height: u16) !void {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(term, x, y, self.theme)) return;

        // Header row with sort indicators
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        const status_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_STATUS);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        var status_hdr_buf: [16]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        const status_hdr = std.fmt.bufPrint(&status_hdr_buf, "STATUS{s}", .{status_ind}) catch "STATUS";
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             {s: <22}{s: <9}VOLUME   CAPACITY   ACCESS   {s}", .{ name_hdr, status_hdr, age_hdr }) catch "  NAMESPACE             NAME                  STATUS   VOLUME   CAPACITY   ACCESS   AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        // Data rows
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |item_idx, i| {
            const item = self.table.items.items[item_idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            try Theme.writeStringWithTheme(term, x, row_y, "  ", colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, x + 2, row_y, item.namespace[0..@min(20, item.namespace.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, x + 24, row_y, item.name[0..@min(20, item.name.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, x + 46, row_y, item.status, colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, x + 55, row_y, item.volume, colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, x + 64, row_y, item.capacity, colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, x + 75, row_y, item.access_modes, colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, x + 84, row_y, item.age, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh PVCs: {}", .{err});
                    return .handled;
                },
                '0' => {
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    self.table.gotoTop();
                    self.refresh() catch |err| Logger.err("Failed to refresh PVCs: {}", .{err});
                    return .handled;
                },
                'N' => { self.table.toggleSort(COL_NAME); self.applySorting(); return .handled; },
                'A' => { self.table.toggleSort(COL_AGE); self.applySorting(); return .handled; },
                'S' => { self.table.toggleSort(COL_STATUS); self.applySorting(); return .handled; },
                else => return .not_handled,
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh PVCs: {any}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {
                    Logger.err("Failed to allocate error message", .{});
                };
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "persistentvolumeclaims";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
