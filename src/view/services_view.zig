/// Services View - Display and manage Kubernetes services
const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = @import("../theme.zig");
const theme_loader = @import("../model/theme_loader.zig");
const View = @import("../viewmodel/view.zig").View;
const Key = @import("../core/terminal.zig").Key;
const KeyResult = View.KeyResult;
const Logger = @import("../core/logger.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const ResourceInfo = k8s_service_mod.ResourceInfo;
const klient = @import("klient");
const hints_model = @import("../model/hints.zig");
const BoxDrawing = @import("../ui/box_drawing.zig");
const universal_filter = @import("../viewmodel/filter.zig");
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");

pub const ServicesView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    services: std.ArrayListUnmanaged(ServiceInfo),
    filtered_indices: std.ArrayListUnmanaged(usize),
    selected_row: u32,
    scroll_offset: u32,
    visible_rows: u32,
    filter_text: []const u8,
    show_all_namespaces: bool,
    sort_column: ?u8 = null,
    sort_ascending: bool = true,
    loading: bool,
    error_message: ?[]const u8,

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
        const view = ServicesView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .services = std.ArrayListUnmanaged(ServiceInfo){},
            .filtered_indices = std.ArrayListUnmanaged(usize){},
            .selected_row = 0,
            .scroll_offset = 0,
            .visible_rows = 0,
            .filter_text = "",
            .show_all_namespaces = false,
            .loading = false,
            .error_message = null,
        };

        // Don't call refresh() here - k8s_service pointer will become invalid after App is created
        // Views will refresh when first activated
        return view;
    }

    pub fn deinit(self: *ServicesView) void {
        for (self.services.items) |*svc| {
            svc.deinit();
        }
        self.services.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);

        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Refresh services list from K8s API
    pub fn refresh(self: *ServicesView) !void {
        self.loading = true;
        defer self.loading = false;

        // Clear existing services
        for (self.services.items) |*svc| {
            svc.deinit();
        }
        self.services.clearRetainingCapacity();

        // Clear any previous error
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        // SAFETY: Check if connected to k8s before making requests
        if (!self.k8s_service.isConnected()) {
            self.error_message = try self.allocator.dupe(u8, "Not connected to Kubernetes cluster");
            Logger.warn("ServicesView: Cannot refresh - not connected to k8s", .{});
            return;
        }

        // Fetch services
        const k8s_services = if (self.show_all_namespaces)
            self.k8s_service.listAllServices() catch |err| {
                self.error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to list services: {}",
                    .{err},
                );
                return;
            }
        else
            self.k8s_service.listServices(null) catch |err| {
                self.error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to list services: {}",
                    .{err},
                );
                return;
            };

        // Convert to ServiceInfo
        for (k8s_services) |svc| {
            const ports_str = if (svc.spec) |spec| blk: {
                if (spec.ports) |ports| {
                    if (ports.len > 0) {
                        // Extract port number from JSON Value
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
                        break :blk try self.allocator.dupe(u8, port_str);
                    }
                }
                break :blk try self.allocator.dupe(u8, "<none>");
            } else try self.allocator.dupe(u8, "<none>");

            const info = ServiceInfo{
                .name = try self.allocator.dupe(u8, svc.metadata.name),
                .namespace = if (svc.metadata.namespace) |ns|
                    try self.allocator.dupe(u8, ns)
                else
                    try self.allocator.dupe(u8, "default"),
                .type_ = if (svc.spec) |spec|
                    try self.allocator.dupe(u8, spec.type_ orelse "ClusterIP")
                else
                    try self.allocator.dupe(u8, "Unknown"),
                .cluster_ip = if (svc.spec) |spec|
                    try self.allocator.dupe(u8, spec.clusterIP orelse "<none>")
                else
                    try self.allocator.dupe(u8, "<none>"),
                .external_ip = try self.allocator.dupe(u8, "<pending>"),
                .ports = ports_str,
                .age = try age_util.calculateAge(self.allocator, svc.metadata.creationTimestamp),
                .allocator = self.allocator,
            };
            try self.services.append(self.allocator, info);
        }

        Logger.info("Loaded {} services", .{self.services.items.len});

        // Rebuild filtered indices
        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *ServicesView) ?ResourceInfo {
        if (self.filtered_indices.items.len == 0) return null;
        if (self.selected_row >= self.filtered_indices.items.len) return null;
        const idx = self.filtered_indices.items[self.selected_row];
        const item = self.services.items[idx];
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *ServicesView, filter: []const u8) !void {
        self.filter_text = filter;
        try universal_filter.applyFilter(
            ServiceInfo,
            self.allocator,
            self.services.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            serviceMatchFn,
        );
        self.applySorting();
    }

    fn applySorting(self: *ServicesView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(ServiceInfo, self.services.items, &self.filtered_indices, ServiceInfo.getName, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(ServiceInfo, self.services.items, &self.filtered_indices, ServiceInfo.getAge, self.sort_ascending),
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
    };

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
        self.visible_rows = if (height > 3) height - 3 else 0;

        var title_buf: [128]u8 = undefined;
        const ns = if (self.show_all_namespaces)
            "all"
        else
            self.k8s_service.getCurrentNamespace();
        const title_text = try std.fmt.bufPrint(&title_buf, "services({s})[{d}]", .{ ns, self.filtered_indices.items.len });

        // Draw box border with title
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, self.theme.proc_box, self.theme.main_bg, title_text, .rounded, self.theme.main_fg, self.theme.title_highlight);

        if (self.loading) {
            try Theme.writeStringWithTheme(terminal, x + 2, y + height / 2, "Loading services...", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(terminal, x + 2, y + height / 2, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }

        // Render header row with sort indicators
        const header_y = y + 1;
        const name_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_AGE);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        try Theme.writeStringWithTheme(terminal, x + 1, header_y, "NAMESPACE", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 16, header_y, name_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 38, header_y, "TYPE", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 52, header_y, "CLUSTER-IP", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 68, header_y, "PORTS", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 82, header_y, age_hdr, self.theme.title, self.theme.main_bg);

        // Render services
        var row_y = y + 2;
        const end_idx = @min(
            self.scroll_offset + self.visible_rows,
            @as(u32, @intCast(self.filtered_indices.items.len)),
        );

        // Render service rows
        for (self.filtered_indices.items[self.scroll_offset..end_idx], 0..) |svc_idx, i| {
            const svc = self.services.items[svc_idx];
            const is_selected = (self.scroll_offset + i) == self.selected_row;

            // Determine colors based on selection
            const fg = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            // Namespace
            try Theme.writeStringWithTheme(terminal, x + 1, row_y, svc.namespace[0..@min(14, svc.namespace.len)], fg, bg);

            // Name
            try Theme.writeStringWithTheme(terminal, x + 16, row_y, svc.name[0..@min(20, svc.name.len)], fg, bg);

            // Type
            try Theme.writeStringWithTheme(terminal, x + 38, row_y, svc.type_, fg, bg);

            // Cluster IP
            try Theme.writeStringWithTheme(terminal, x + 52, row_y, svc.cluster_ip[0..@min(14, svc.cluster_ip.len)], fg, bg);

            // Ports
            try Theme.writeStringWithTheme(terminal, x + 68, row_y, svc.ports, fg, bg);

            // Age
            try Theme.writeStringWithTheme(terminal, x + 82, row_y, svc.age, fg, bg);

            row_y += 1;
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));

        switch (key) {
            .char => |c| {
                switch (c) {
                    'j' => {
                        if (self.selected_row + 1 < self.filtered_indices.items.len) {
                            self.selected_row += 1;
                            if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                                self.scroll_offset += 1;
                            }
                        }
                        return .handled;
                    },
                    'k' => {
                        if (self.selected_row > 0) {
                            self.selected_row -= 1;
                            if (self.selected_row < self.scroll_offset) {
                                self.scroll_offset = self.selected_row;
                            }
                        }
                        return .handled;
                    },
                    'g' => {
                        self.selected_row = 0;
                        self.scroll_offset = 0;
                        return .handled;
                    },
                    'G' => {
                        if (self.filtered_indices.items.len > 0) {
                            self.selected_row = @intCast(self.filtered_indices.items.len - 1);
                            if (self.selected_row >= self.visible_rows) {
                                self.scroll_offset = self.selected_row - self.visible_rows + 1;
                            }
                        }
                        return .handled;
                    },
                    'r' => {
                        self.refresh() catch |err| {
                            Logger.err("Failed to refresh services: {}", .{err});
                        };
                        return .handled;
                    },
                    '0' => {
                        self.show_all_namespaces = !self.show_all_namespaces;
                        self.selected_row = 0;
                        self.scroll_offset = 0;
                        self.refresh() catch |err| {
                            Logger.err("Failed to refresh services: {}", .{err});
                        };
                        return .handled;
                    },
                    'N' => {
                        sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_NAME);
                        self.applySorting();
                        return .handled;
                    },
                    'A' => {
                        sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_AGE);
                        self.applySorting();
                        return .handled;
                    },
                    'd' => return .request_describe,
                    'y' => return .request_yaml,
                    ':' => return .request_command_palette,
                    '/' => return .request_filter,
                    else => return .not_handled,
                }
            },
            .down => {
                if (self.selected_row + 1 < self.filtered_indices.items.len) {
                    self.selected_row += 1;
                    if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset += 1;
                    }
                }
                return .handled;
            },
            .up => {
                if (self.selected_row > 0) {
                    self.selected_row -= 1;
                    if (self.selected_row < self.scroll_offset) {
                        self.scroll_offset = self.selected_row;
                    }
                }
                return .handled;
            },
            .page_down => {
                const items_len: u32 = @intCast(self.filtered_indices.items.len);
                const jump = @min(self.visible_rows, items_len -| self.selected_row -| 1);
                self.selected_row += jump;
                if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                    self.scroll_offset = self.selected_row - self.visible_rows + 1;
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
                if (self.filtered_indices.items.len > 0) {
                    self.selected_row = @intCast(self.filtered_indices.items.len - 1);
                    if (self.selected_row >= self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
        Logger.info("ServicesView: View activated", .{});
        // Refresh data when view is shown - catch ALL errors to prevent crashes
        self.refresh() catch |err| {
            Logger.err("Failed to refresh services: {any}", .{err});
            // Set a fallback error message if one wasn't already set
            if (self.error_message == null) {
                self.error_message = self.allocator.dupe(u8, "Unexpected error during refresh") catch {
                    Logger.err("Failed to allocate error message", .{});
                    return;
                };
            }
        };
    }

    fn onHide(_: *anyopaque) void {
        Logger.debug("ServicesView hidden", .{});
    }

    fn getName(_: *anyopaque) []const u8 {
        return "Services";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
