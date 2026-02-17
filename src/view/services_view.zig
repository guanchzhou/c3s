/// Services View - Display and manage Kubernetes services
const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = @import("../theme.zig");
const theme_loader = @import("../model/theme_loader.zig");
const View = @import("../viewmodel/view.zig").View;
const Key = @import("../core/terminal.zig").Key;
const KeyResult = View.KeyResult;
const Logger = @import("../core/logger.zig");
const K8sService = @import("../services/k8s_service.zig").K8sService;
const klient = @import("klient");
const hints_model = @import("../model/hints.zig");
const BoxDrawing = @import("../ui/box_drawing.zig");

pub const ServicesView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    services: std.ArrayListUnmanaged(ServiceInfo),
    selected_row: usize,
    scroll_offset: usize,
    visible_rows: u16,
    filter_text: []const u8,
    show_all_namespaces: bool,
    loading: bool,
    error_message: ?[]const u8,

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
                .age = try self.calculateAge(svc.metadata.creationTimestamp),
                .allocator = self.allocator,
            };
            try self.services.append(self.allocator, info);
        }

        Logger.info("Loaded {} services", .{self.services.items.len});
    }

    fn calculateAge(self: *ServicesView, timestamp: ?[]const u8) ![]const u8 {
        _ = timestamp;
        // TODO: Calculate actual age from timestamp
        return try self.allocator.dupe(u8, "5d");
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
        const title_text = try std.fmt.bufPrint(&title_buf, "services({s})[{d}]", .{ ns, self.services.items.len });

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

        // Render header row
        const header_y = y + 1;
        try Theme.writeStringWithTheme(terminal, x + 1, header_y, "NAMESPACE", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 16, header_y, "NAME", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 38, header_y, "TYPE", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 52, header_y, "CLUSTER-IP", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 68, header_y, "PORTS", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 82, header_y, "AGE", self.theme.title, self.theme.main_bg);

        // Render services
        var row_y = y + 2;
        const end_idx = @min(
            self.scroll_offset + self.visible_rows,
            self.services.items.len,
        );

        // Render service rows
        for (self.services.items[self.scroll_offset..end_idx], 0..) |svc, i| {
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
                        if (self.selected_row + 1 < self.services.items.len) {
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
                        if (self.services.items.len > 0) {
                            self.selected_row = self.services.items.len - 1;
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
                    ':' => return .request_command_palette,
                    '/' => return .request_filter,
                    else => return .not_handled,
                }
            },
            .down => {
                if (self.selected_row + 1 < self.services.items.len) {
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
                const jump = @min(self.visible_rows, self.services.items.len -| self.selected_row -| 1);
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
                if (self.services.items.len > 0) {
                    self.selected_row = self.services.items.len - 1;
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
        return hints_model.podsHints(); // TODO: Create specific hints
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *ServicesView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
