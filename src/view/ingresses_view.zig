/// IngressesView - View for Kubernetes Ingresses
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

pub const IngressesView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(IngressInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const IngressInfo = struct {
        name: []const u8,
        namespace: []const u8,
        class: []const u8,
        hosts: []const u8,
        address: []const u8,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *IngressInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.namespace);
            self.allocator.free(self.class);
            self.allocator.free(self.hosts);
            self.allocator.free(self.address);
            self.allocator.free(self.age);
        }

        fn getName(self: *const IngressInfo) []const u8 { return self.name; }
        fn getAge(self: *const IngressInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !IngressesView {
        return IngressesView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(IngressInfo).init(allocator),
        };
    }

    pub fn deinit(self: *IngressesView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *IngressesView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        const ingresses = if (self.table.show_all_namespaces)
            self.k8s_service.listAllIngresses() catch |err| {
                try self.table.setErrorFmt("Failed to list ingresses: {}", .{err});
                return;
            }
        else
            self.k8s_service.listIngresses(null) catch |err| {
                try self.table.setErrorFmt("Failed to list ingresses: {}", .{err});
                return;
            };
        defer self.table.allocator.free(ingresses);

        for (ingresses) |ing| {
            try self.table.appendItem(.{
                .name = try self.table.allocator.dupe(u8, ing.metadata.name),
                .namespace = try self.table.allocator.dupe(u8, ing.metadata.namespace orelse "default"),
                .class = try self.table.allocator.dupe(u8, "nginx"),
                .hosts = try self.table.allocator.dupe(u8, "*"),
                .address = try self.table.allocator.dupe(u8, "10.0.0.1"),
                .age = try age_util.calculateAge(self.table.allocator, ing.metadata.creationTimestamp),
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *IngressesView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{ .name = item.name, .namespace = item.namespace };
    }

    pub fn applyFilter(self: *IngressesView, filter: []const u8) !void {
        try self.table.applyFilter(filter, ingressMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *IngressesView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(IngressInfo.getName),
                COL_AGE => self.table.sortBy(IngressInfo.getAge),
                else => {},
            }
        }
    }

    fn ingressMatchFn(item: *const IngressInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *IngressesView) View {
        return View.create(IngressesView, self, &vtable);
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
        const self: *IngressesView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *IngressesView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *IngressesView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *IngressesView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, _: u16, height: u16) !void {
        const self: *IngressesView = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(term, x, y, self.theme)) return;

        // Header row with sort indicators
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             {s: <22}CLASS      HOSTS      ADDRESS       {s}", .{ name_hdr, age_hdr }) catch "  NAMESPACE             NAME                  CLASS      HOSTS      ADDRESS       AGE";
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
            try Theme.writeStringWithTheme(term, x + 46, row_y, item.class[0..@min(10, item.class.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, x + 57, row_y, item.hosts[0..@min(10, item.hosts.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, x + 68, row_y, item.address[0..@min(13, item.address.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, x + 82, row_y, item.age, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *IngressesView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh ingresses: {}", .{err});
                    return .handled;
                },
                '0' => {
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    self.table.gotoTop();
                    self.refresh() catch |err| Logger.err("Failed to refresh ingresses: {}", .{err});
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
        const self: *IngressesView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh ingresses: {any}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {
                    Logger.err("Failed to allocate error message", .{});
                };
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "ingresses";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *IngressesView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
