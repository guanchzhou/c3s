/// Services View - Display and manage Kubernetes services
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

pub const ServicesView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(ServiceInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const ServiceInfo = struct {
        name: []const u8,
        namespace: []const u8,
        type_: []const u8,
        cluster_ip: []const u8,
        external_ip: []const u8,
        ports: []const u8,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *ServiceInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.namespace);
            self.allocator.free(self.type_);
            self.allocator.free(self.cluster_ip);
            self.allocator.free(self.external_ip);
            self.allocator.free(self.ports);
            self.allocator.free(self.age);
        }

        fn getName(self: *const ServiceInfo) []const u8 { return self.name; }
        fn getAge(self: *const ServiceInfo) []const u8 { return self.age; }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) !ServicesView {
        return ServicesView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(ServiceInfo).init(allocator),
        };
    }

    pub fn deinit(self: *ServicesView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *ServicesView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        const k8s_services = if (self.table.show_all_namespaces)
            self.k8s_service.listAllServices() catch |err| {
                try self.table.setErrorFmt("Failed to list services: {}", .{err});
                return;
            }
        else
            self.k8s_service.listServices(null) catch |err| {
                try self.table.setErrorFmt("Failed to list services: {}", .{err});
                return;
            };

        for (k8s_services) |svc| {
            const ports_str = if (svc.spec) |spec| blk: {
                if (spec.ports) |ports| {
                    if (ports.len > 0) {
                        const port_num = if (ports[0].port) |p| blk2: {
                            if (p == .integer) break :blk2 @as(i64, @intCast(p.integer));
                            break :blk2 @as(i64, 0);
                        } else 0;

                        var buf: [64]u8 = undefined;
                        const port_str = try std.fmt.bufPrint(
                            &buf,
                            "{d}/{s}",
                            .{ port_num, ports[0].protocol orelse "TCP" },
                        );
                        break :blk try self.table.allocator.dupe(u8, port_str);
                    }
                }
                break :blk try self.table.allocator.dupe(u8, "<none>");
            } else try self.table.allocator.dupe(u8, "<none>");

            try self.table.appendItem(.{
                .name = try self.table.allocator.dupe(u8, svc.metadata.name),
                .namespace = if (svc.metadata.namespace) |ns|
                    try self.table.allocator.dupe(u8, ns)
                else
                    try self.table.allocator.dupe(u8, "default"),
                .type_ = if (svc.spec) |spec|
                    try self.table.allocator.dupe(u8, spec.type_ orelse "ClusterIP")
                else
                    try self.table.allocator.dupe(u8, "Unknown"),
                .cluster_ip = if (svc.spec) |spec|
                    try self.table.allocator.dupe(u8, spec.clusterIP orelse "<none>")
                else
                    try self.table.allocator.dupe(u8, "<none>"),
                .external_ip = try self.table.allocator.dupe(u8, "<pending>"),
                .ports = ports_str,
                .age = try age_util.calculateAge(self.table.allocator, svc.metadata.creationTimestamp),
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *ServicesView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{ .name = item.name, .namespace = item.namespace };
    }

    pub fn applyFilter(self: *ServicesView, filter: []const u8) !void {
        try self.table.applyFilter(filter, serviceMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *ServicesView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(ServiceInfo.getName),
                COL_AGE => self.table.sortBy(ServiceInfo.getAge),
                else => {},
            }
        }
    }

    fn serviceMatchFn(item: *const ServiceInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *ServicesView) View {
        return View.create(ServicesView, self, &vtable);
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
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
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
        try Theme.writeStringWithTheme(terminal, x + 15, y, name_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 37, y, "TYPE", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 51, y, "CLUSTER-IP", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 67, y, "PORTS", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 81, y, age_hdr, self.theme.title, self.theme.main_bg);

        // Data rows
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |svc_idx, i| {
            const svc = self.table.items.items[svc_idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            try Theme.writeStringWithTheme(terminal, x, row_y, svc.namespace[0..@min(14, svc.namespace.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 15, row_y, svc.name[0..@min(20, svc.name.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 37, row_y, svc.type_, colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 51, row_y, svc.cluster_ip[0..@min(14, svc.cluster_ip.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 67, row_y, svc.ports, colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 81, row_y, svc.age, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh services: {}", .{err});
                    return .handled;
                },
                '0' => {
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    self.table.gotoTop();
                    self.refresh() catch |err| Logger.err("Failed to refresh services: {}", .{err});
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
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh services: {any}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {
                    Logger.err("Failed to allocate error message", .{});
                };
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "services";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
