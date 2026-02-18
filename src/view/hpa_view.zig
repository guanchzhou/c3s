/// HPAView - View for HorizontalPodAutoscalers
const std = @import("std");
const klient = @import("klient");
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = theme_loader;
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const view_mod = @import("../viewmodel/view.zig");
const ResourceInfo = view_mod.ResourceInfo;
const Logger = @import("../core/logger.zig");
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");
const TableState = @import("../ui/table_state.zig").TableState;

pub const HPAView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(HPAInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const HPAInfo = struct {
        namespace: []const u8,
        name: []const u8,
        min_replicas: i32,
        max_replicas: i32,
        current_replicas: i32,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *HPAInfo) void {
            self.allocator.free(self.namespace);
            self.allocator.free(self.name);
            self.allocator.free(self.age);
        }

        fn getName(self: *const HPAInfo) []const u8 { return self.name; }
        fn getAge(self: *const HPAInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !HPAView {
        var tbl = TableState(HPAInfo).init(allocator);
        tbl.show_all_namespaces = true;
        return HPAView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = tbl,
        };
    }

    pub fn deinit(self: *HPAView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *HPAView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected");
            return;
        }

        const hpas = if (self.table.show_all_namespaces)
            self.k8s_service.listAllHPAs() catch |err| {
                try self.table.setErrorFmt("Failed: {}", .{err});
                return;
            }
        else
            self.k8s_service.listHPAs(null) catch |err| {
                try self.table.setErrorFmt("Failed: {}", .{err});
                return;
            };
        defer self.table.allocator.free(hpas);

        for (hpas) |hpa| {
            const current = blk: {
                if (hpa.status) |status_val| {
                    if (status_val == .object) {
                        const status_obj = status_val.object;
                        if (status_obj.get("currentReplicas")) |val| {
                            if (val == .integer) {
                                break :blk @as(i32, @intCast(val.integer));
                            }
                        }
                    }
                }
                break :blk @as(i32, 0);
            };
            const min = if (hpa.spec) |spec| if (spec.minReplicas) |m| m else 1 else 1;
            const max = if (hpa.spec) |spec| spec.maxReplicas else 1;
            try self.table.appendItem(.{
                .namespace = try self.table.allocator.dupe(u8, hpa.metadata.namespace orelse "default"),
                .name = try self.table.allocator.dupe(u8, hpa.metadata.name),
                .min_replicas = min,
                .max_replicas = max,
                .current_replicas = current,
                .age = try age_util.calculateAge(self.table.allocator, hpa.metadata.creationTimestamp),
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *HPAView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *HPAView, filter: []const u8) !void {
        try self.table.applyFilter(filter, hpaMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *HPAView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(HPAInfo.getName),
                COL_AGE => self.table.sortBy(HPAInfo.getAge),
                else => {},
            }
        }
    }

    fn hpaMatchFn(item: *const HPAInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *HPAView) View {
        return View.create(HPAView, self, &vtable);
    }

    fn render(ctx: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) anyerror!void {
        const self: *HPAView = @ptrCast(@alignCast(ctx));
        _ = width;
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(terminal, x, y, self.theme)) return;

        if (self.table.filtered_indices.items.len == 0) {
            try Theme.writeStringWithTheme(terminal, x, y, "No HPAs found", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        // Render header row with sort indicators
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "NAMESPACE/{s}  MIN  MAX  CURRENT  {s}", .{ name_hdr, age_hdr }) catch "NAMESPACE/NAME  MIN  MAX  CURRENT  AGE";
        try Theme.writeStringWithTheme(terminal, x, y, header, self.theme.title, self.theme.main_bg);

        // Render rows
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |idx, i| {
            const item = self.table.items.items[idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            const line = try std.fmt.allocPrint(self.table.allocator, "{s}/{s} min:{d} max:{d} current:{d}", .{ item.namespace, item.name, item.min_replicas, item.max_replicas, item.current_replicas });
            defer self.table.allocator.free(line);
            try Theme.writeStringWithTheme(terminal, x, row_y, line, colors.fg, colors.bg);
        }
    }

    fn handleKey(ctx: *anyopaque, key: Key) anyerror!KeyResult {
        const self: *HPAView = @ptrCast(@alignCast(ctx));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                '0' => {
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    self.table.gotoTop();
                    self.refresh() catch |err| Logger.err("Failed to refresh HPAs: {}", .{err});
                    return .handled;
                },
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh HPAs: {}", .{err});
                    return .handled;
                },
                'N' => { self.table.toggleSort(COL_NAME); self.applySorting(); return .handled; },
                'A' => { self.table.toggleSort(COL_AGE); self.applySorting(); return .handled; },
                'q' => return .request_quit,
                else => return .not_handled,
            },
            else => return .not_handled,
        }
    }

    fn onShow(ctx: *anyopaque) void {
        const self: *HPAView = @ptrCast(@alignCast(ctx));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh HPAs: {}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {
                    Logger.err("Failed to allocate error message", .{});
                };
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "hpa";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ctx: *anyopaque) void {
        const self: *HPAView = @ptrCast(@alignCast(ctx));
        self.deinit();
    }

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *HPAView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *HPAView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *HPAView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?view_mod.ResourceInfo {
        const self: *HPAView = @ptrCast(@alignCast(ptr));
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
};
