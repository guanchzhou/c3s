/// Nodes View - Display and monitor Kubernetes cluster nodes
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

pub const NodesView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    nodes: std.ArrayListUnmanaged(NodeInfo),
    selected_row: usize,
    scroll_offset: usize,
    visible_rows: u16,
    filter_text: []const u8,
    loading: bool,
    error_message: ?[]const u8,

    const NodeInfo = struct {
        name: []const u8,
        status: []const u8,
        roles: []const u8,
        age: []const u8,
        version: []const u8,
        internal_ip: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *NodeInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.status);
            self.allocator.free(self.roles);
            self.allocator.free(self.age);
            self.allocator.free(self.version);
            self.allocator.free(self.internal_ip);
        }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) !NodesView {
        const view = NodesView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .nodes = std.ArrayListUnmanaged(NodeInfo){},
            .selected_row = 0,
            .scroll_offset = 0,
            .visible_rows = 0,
            .filter_text = "",
            .loading = false,
            .error_message = null,
        };

        // Don't call refresh() here - k8s_service pointer will become invalid after App is created
        // Views will refresh when first activated
        return view;
    }

    pub fn deinit(self: *NodesView) void {
        for (self.nodes.items) |*node| {
            node.deinit();
        }
        self.nodes.deinit(self.allocator);

        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Refresh nodes list from K8s API
    pub fn refresh(self: *NodesView) !void {
        self.loading = true;
        defer self.loading = false;

        // Clear existing nodes
        for (self.nodes.items) |*node| {
            node.deinit();
        }
        self.nodes.clearRetainingCapacity();

        // Clear any previous error
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        // SAFETY: Check if connected to k8s before making requests
        if (!self.k8s_service.isConnected()) {
            self.error_message = try self.allocator.dupe(u8, "Not connected to Kubernetes cluster");
            Logger.warn("NodesView: Cannot refresh - not connected to k8s", .{});
            return;
        }

        // Fetch nodes
        const k8s_nodes = self.k8s_service.listNodes() catch |err| {
            self.error_message = try std.fmt.allocPrint(
                self.allocator,
                "Failed to list nodes: {}",
                .{err},
            );
            return;
        };

        // Convert to NodeInfo
        for (k8s_nodes) |node| {
            // Determine node status - simplified since status is JSON Value
            // TODO: Parse the JSON structure properly to extract conditions
            const status = try self.allocator.dupe(u8, "Ready");

            // Get node roles from labels - simplified
            const roles = try self.allocator.dupe(u8, "<none>");

            // TODO: Extract internal IP from JSON status.addresses
            const internal_ip = try self.allocator.dupe(u8, "<unknown>");

            // TODO: Extract version from JSON status.nodeInfo.kubeletVersion
            const version = try self.allocator.dupe(u8, "unknown");

            const info = NodeInfo{
                .name = try self.allocator.dupe(u8, node.metadata.name),
                .status = status,
                .roles = roles,
                .age = try self.calculateAge(node.metadata.creationTimestamp),
                .version = version,
                .internal_ip = internal_ip,
                .allocator = self.allocator,
            };
            try self.nodes.append(self.allocator, info);
        }

        Logger.info("Loaded {} nodes", .{self.nodes.items.len});
    }

    fn calculateAge(self: *NodesView, timestamp: ?[]const u8) ![]const u8 {
        _ = timestamp;
        // TODO: Calculate actual age from timestamp
        return try self.allocator.dupe(u8, "90d");
    }

    pub fn createView(self: *NodesView) View {
        return View.create(NodesView, self, &vtable);
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
        const self: *NodesView = @ptrCast(@alignCast(ptr));
        self.visible_rows = if (height > 3) height - 3 else 0;

        // Draw box border
        const BoxDrawing = @import("../ui/box_drawing.zig");
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, self.theme.proc_box, self.theme.main_bg, null, .rounded, self.theme.main_fg, self.theme.title);

        // Draw title
        var title_buf: [128]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buf, "no(all)[{d}]", .{self.nodes.items.len});
        try terminal.setCursor(x + 1, y);
        try terminal.writeAll(self.theme.title);
        try terminal.writeAll(title);
        try terminal.writeAll("\x1b[0m");

        if (self.loading) {
            try Theme.writeStringWithTheme(terminal, x + 2, y + height / 2, "Loading nodes...", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(terminal, x + 2, y + height / 2, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }

        // Render header row
        const header_y = y + 1;
        try Theme.writeStringWithTheme(terminal, x + 1, header_y, "NAME", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 28, header_y, "STATUS", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 40, header_y, "ROLES", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 56, header_y, "VERSION", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 72, header_y, "INTERNAL-IP", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 92, header_y, "AGE", self.theme.title, self.theme.main_bg);

        // Render nodes
        var row_y = y + 2;
        const end_idx = @min(
            self.scroll_offset + self.visible_rows,
            self.nodes.items.len,
        );

        for (self.nodes.items[self.scroll_offset..end_idx], 0..) |node, i| {
            const is_selected = (self.scroll_offset + i) == self.selected_row;

            const fg = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            // Name
            try Theme.writeStringWithTheme(terminal, x + 1, row_y, node.name[0..@min(26, node.name.len)], fg, bg);

            // Status
            try Theme.writeStringWithTheme(terminal, x + 28, row_y, node.status, fg, bg);

            // Roles
            try Theme.writeStringWithTheme(terminal, x + 40, row_y, node.roles[0..@min(14, node.roles.len)], fg, bg);

            // Version
            try Theme.writeStringWithTheme(terminal, x + 56, row_y, node.version[0..@min(14, node.version.len)], fg, bg);

            // Internal IP
            try Theme.writeStringWithTheme(terminal, x + 72, row_y, node.internal_ip, fg, bg);

            // Age
            try Theme.writeStringWithTheme(terminal, x + 92, row_y, node.age, fg, bg);

            row_y += 1;
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *NodesView = @ptrCast(@alignCast(ptr));

        switch (key) {
            .char => |c| {
                switch (c) {
                    'j' => {
                        if (self.selected_row + 1 < self.nodes.items.len) {
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
                        if (self.nodes.items.len > 0) {
                            self.selected_row = self.nodes.items.len - 1;
                            if (self.selected_row >= self.visible_rows) {
                                self.scroll_offset = self.selected_row - self.visible_rows + 1;
                            }
                        }
                        return .handled;
                    },
                    'r' => {
                        self.refresh() catch |err| {
                            Logger.err("Failed to refresh nodes: {}", .{err});
                        };
                        return .handled;
                    },
                    ':' => return .request_command_palette,
                    '/' => return .request_filter,
                    else => return .not_handled,
                }
            },
            .down => {
                if (self.selected_row + 1 < self.nodes.items.len) {
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
                const jump = @min(self.visible_rows, self.nodes.items.len -| self.selected_row -| 1);
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
                if (self.nodes.items.len > 0) {
                    self.selected_row = self.nodes.items.len - 1;
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
        const self: *NodesView = @ptrCast(@alignCast(ptr));
        Logger.info("NodesView: View activated", .{});
        // Refresh data when view is shown - catch ALL errors to prevent crashes
        self.refresh() catch |err| {
            Logger.err("Failed to refresh nodes: {any}", .{err});
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
        Logger.debug("NodesView hidden", .{});
    }

    fn getName(_: *anyopaque) []const u8 {
        return "Nodes";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.podsHints(); // TODO: Create specific hints
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *NodesView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
