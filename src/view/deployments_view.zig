/// Deployments View - Display and manage Kubernetes deployments
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

pub const DeploymentsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    deployments: std.ArrayListUnmanaged(DeploymentInfo),
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

    const DeploymentInfo = struct {
        name: []const u8,
        namespace: []const u8,
        replicas: i32,
        ready_replicas: i32,
        available_replicas: i32,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *DeploymentInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.namespace);
            self.allocator.free(self.age);
        }

        fn getName(self: *const DeploymentInfo) []const u8 { return self.name; }
        fn getAge(self: *const DeploymentInfo) []const u8 { return self.age; }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) !DeploymentsView {
        const view = DeploymentsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .deployments = std.ArrayListUnmanaged(DeploymentInfo){},
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

    pub fn deinit(self: *DeploymentsView) void {
        for (self.deployments.items) |*dep| {
            dep.deinit();
        }
        self.deployments.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);

        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Refresh deployment list from K8s API
    pub fn refresh(self: *DeploymentsView) !void {
        Logger.info("=== DEPLOYMENTS_VIEW REFRESH CALLED ===", .{});
        self.loading = true;
        defer self.loading = false;

        Logger.info("Clearing existing deployments...", .{});
        // Clear existing deployments
        for (self.deployments.items) |*dep| {
            dep.deinit();
        }
        self.deployments.clearRetainingCapacity();

        Logger.info("Clearing previous error...", .{});
        // Clear any previous error
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        // SAFETY: Check if connected to k8s before making requests
        if (!self.k8s_service.isConnected()) {
            self.error_message = try self.allocator.dupe(u8, "Not connected to Kubernetes cluster");
            Logger.warn("DeploymentsView: Cannot refresh - not connected to k8s", .{});
            return;
        }

        Logger.info("Fetching deployments (show_all_namespaces = {})...", .{self.show_all_namespaces});
        // Fetch deployments
        const k8s_deployments = if (self.show_all_namespaces) blk: {
            Logger.info("Calling listAllDeployments()...", .{});
            const result = self.k8s_service.listAllDeployments() catch |err| {
                Logger.err("listAllDeployments() returned error: {}", .{err});
                self.error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to list deployments: {}",
                    .{err},
                );
                return;
            };
            break :blk result;
        } else blk: {
            Logger.info("Calling listDeployments(null)...", .{});
            const result = self.k8s_service.listDeployments(null) catch |err| {
                Logger.err("listDeployments() returned error: {}", .{err});
                self.error_message = try std.fmt.allocPrint(
                    self.allocator,
                    "Failed to list deployments: {}",
                    .{err},
                );
                return;
            };
            break :blk result;
        };

        // Convert to DeploymentInfo
        for (k8s_deployments) |dep| {
            // Extract status fields from JSON Value
            const ready_replicas: i32 = if (dep.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("readyReplicas")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            const available_replicas: i32 = if (dep.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("availableReplicas")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            const info = DeploymentInfo{
                .name = try self.allocator.dupe(u8, dep.metadata.name),
                .namespace = if (dep.metadata.namespace) |ns|
                    try self.allocator.dupe(u8, ns)
                else
                    try self.allocator.dupe(u8, "default"),
                .replicas = dep.spec.?.replicas orelse 0,
                .ready_replicas = ready_replicas,
                .available_replicas = available_replicas,
                .age = try age_util.calculateAge(self.allocator, dep.metadata.creationTimestamp),
                .allocator = self.allocator,
            };
            try self.deployments.append(self.allocator, info);
        }

        Logger.info("Loaded {} deployments", .{self.deployments.items.len});

        // Rebuild filtered indices
        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *DeploymentsView) ?ResourceInfo {
        if (self.filtered_indices.items.len == 0) return null;
        if (self.selected_row >= self.filtered_indices.items.len) return null;
        const idx = self.filtered_indices.items[self.selected_row];
        const item = self.deployments.items[idx];
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *DeploymentsView, filter: []const u8) !void {
        self.filter_text = filter;
        try universal_filter.applyFilter(
            DeploymentInfo,
            self.allocator,
            self.deployments.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            deploymentMatchFn,
        );
        self.applySorting();
    }

    fn applySorting(self: *DeploymentsView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(DeploymentInfo, self.deployments.items, &self.filtered_indices, DeploymentInfo.getName, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(DeploymentInfo, self.deployments.items, &self.filtered_indices, DeploymentInfo.getAge, self.sort_ascending),
                else => {},
            }
        }
    }

    fn deploymentMatchFn(item: *const DeploymentInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }


    pub fn createView(self: *DeploymentsView) View {
        return View.create(DeploymentsView, self, &vtable);
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
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));
        self.visible_rows = if (height > 3) height - 3 else 0;

        var title_buf: [128]u8 = undefined;
        const ns = if (self.show_all_namespaces)
            "all"
        else
            self.k8s_service.getCurrentNamespace();
        const title_text = try std.fmt.bufPrint(&title_buf, "deployments({s})[{d}]", .{ ns, self.filtered_indices.items.len });

        // Draw box border with title
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, self.theme.proc_box, self.theme.main_bg, title_text, .rounded, self.theme.main_fg, self.theme.title_highlight);

        if (self.loading) {
            try Theme.writeStringWithTheme(terminal, x + 2, y + height / 2, "Loading deployments...", self.theme.main_fg, self.theme.main_bg);
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
        try Theme.writeStringWithTheme(terminal, x + 20, header_y, name_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 50, header_y, "READY", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 62, header_y, "AVAILABLE", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 78, header_y, age_hdr, self.theme.title, self.theme.main_bg);

        // Render deployment rows
        var row_y = y + 2;
        const end_idx = @min(
            self.scroll_offset + self.visible_rows,
            @as(u32, @intCast(self.filtered_indices.items.len)),
        );

        for (self.filtered_indices.items[self.scroll_offset..end_idx], 0..) |dep_idx, i| {
            const dep = self.deployments.items[dep_idx];
            const is_selected = (self.scroll_offset + i) == self.selected_row;

            // Determine colors based on selection
            const fg = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            // Namespace
            try Theme.writeStringWithTheme(terminal, x + 1, row_y, dep.namespace[0..@min(18, dep.namespace.len)], fg, bg);

            // Name
            try Theme.writeStringWithTheme(terminal, x + 20, row_y, dep.name[0..@min(28, dep.name.len)], fg, bg);

            // Ready replicas
            var ready_buf: [16]u8 = undefined;
            const ready_str = try std.fmt.bufPrint(
                &ready_buf,
                "{d}/{d}",
                .{ dep.ready_replicas, dep.replicas },
            );
            try Theme.writeStringWithTheme(terminal, x + 50, row_y, ready_str, fg, bg);

            // Available replicas
            var avail_buf: [16]u8 = undefined;
            const avail_str = try std.fmt.bufPrint(&avail_buf, "{d}", .{dep.available_replicas});
            try Theme.writeStringWithTheme(terminal, x + 62, row_y, avail_str, fg, bg);

            // Age
            try Theme.writeStringWithTheme(terminal, x + 78, row_y, dep.age, fg, bg);

            row_y += 1;
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));

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
                        // Refresh
                        self.refresh() catch |err| {
                            Logger.err("Failed to refresh deployments: {}", .{err});
                        };
                        return .handled;
                    },
                    '0' => {
                        // Toggle all namespaces
                        self.show_all_namespaces = !self.show_all_namespaces;
                        self.selected_row = 0;
                        self.scroll_offset = 0;
                        self.refresh() catch |err| {
                            Logger.err("Failed to refresh deployments: {}", .{err});
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
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));
        Logger.info("DeploymentsView: View activated", .{});
        // Refresh data when view is shown - catch ALL errors to prevent crashes
        self.refresh() catch |err| {
            Logger.err("Failed to refresh deployments: {any}", .{err});
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
        Logger.debug("DeploymentsView hidden", .{});
    }

    fn getName(_: *anyopaque) []const u8 {
        return "Deployments";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *DeploymentsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
