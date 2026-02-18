/// ResourceQuotasView
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
const Logger = @import("../core/logger.zig");
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");
const TableState = @import("../ui/table_state.zig").TableState;

pub const ResourceQuotasView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(RQInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const RQInfo = struct {
        namespace: []const u8,
        name: []const u8,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *RQInfo) void {
            self.allocator.free(self.namespace);
            self.allocator.free(self.name);
            self.allocator.free(self.age);
        }

        fn getName(self: *const RQInfo) []const u8 { return self.name; }
        fn getAge(self: *const RQInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !ResourceQuotasView {
        var tbl = TableState(RQInfo).init(allocator);
        tbl.show_all_namespaces = true;
        return ResourceQuotasView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = tbl,
        };
    }

    pub fn deinit(self: *ResourceQuotasView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *ResourceQuotasView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected");
            return;
        }

        const rqs = if (self.table.show_all_namespaces)
            self.k8s_service.listAllResourceQuotas() catch |err| {
                try self.table.setErrorFmt("Failed: {}", .{err});
                return;
            }
        else
            self.k8s_service.listResourceQuotas(null) catch |err| {
                try self.table.setErrorFmt("Failed: {}", .{err});
                return;
            };
        defer self.table.allocator.free(rqs);

        for (rqs) |rq| {
            try self.table.appendItem(.{
                .namespace = try self.table.allocator.dupe(u8, rq.metadata.namespace orelse "default"),
                .name = try self.table.allocator.dupe(u8, rq.metadata.name),
                .age = try age_util.calculateAge(self.table.allocator, rq.metadata.creationTimestamp),
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *ResourceQuotasView) ?view_mod.ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return view_mod.ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *ResourceQuotasView, filter: []const u8) !void {
        try self.table.applyFilter(filter, rqMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *ResourceQuotasView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(RQInfo.getName),
                COL_AGE => self.table.sortBy(RQInfo.getAge),
                else => {},
            }
        }
    }

    fn rqMatchFn(item: *const RQInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *ResourceQuotasView) View {
        return View.create(ResourceQuotasView, self, &vtable);
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *ResourceQuotasView = @ptrCast(@alignCast(ptr));
        _ = width;
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(term, x, y, self.theme)) return;

        if (self.table.filtered_indices.items.len == 0) {
            const msg = if (self.table.show_all_namespaces) "No resource quotas found" else "No resource quotas in namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        var header_buf: [128]u8 = undefined;
        const rq_header = std.fmt.bufPrint(&header_buf, "  NAMESPACE             {s: <30}{s}", .{ name_hdr, age_hdr }) catch "  NAMESPACE             NAME                          AGE";
        try Theme.writeStringWithTheme(term, x, y, rq_header, self.theme.title, self.theme.main_bg);

        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |idx, i| {
            const item = self.table.items.items[idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            const line = try std.fmt.allocPrint(self.table.allocator, "  {s: <20} {s: <28} {s}", .{
                if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                if (item.name.len > 28) item.name[0..28] else item.name,
                item.age,
            });
            defer self.table.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, row_y, line, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *ResourceQuotasView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh resource quotas: {}", .{err});
                    return .handled;
                },
                '0' => {
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    self.table.gotoTop();
                    self.refresh() catch |err| Logger.err("Failed to refresh resource quotas: {}", .{err});
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
        const self: *ResourceQuotasView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed: {}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {
                    Logger.err("Failed to allocate error message", .{});
                };
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "resourcequotas";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *ResourceQuotasView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *ResourceQuotasView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *ResourceQuotasView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *ResourceQuotasView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?view_mod.ResourceInfo {
        const self: *ResourceQuotasView = @ptrCast(@alignCast(ptr));
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
