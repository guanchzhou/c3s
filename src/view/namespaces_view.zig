/// Namespaces View - Display and switch between Kubernetes namespaces
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
const universal_filter = @import("../viewmodel/filter.zig");
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");

pub const NamespacesView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    namespaces: std.ArrayListUnmanaged(NamespaceInfo),
    filtered_indices: std.ArrayListUnmanaged(usize),
    selected_row: u32,
    scroll_offset: u32,
    visible_rows: u32,
    filter_text: []const u8,
    sort_column: ?u8 = null,
    sort_ascending: bool = true,
    loading: bool,
    error_message: ?[]const u8,
    current_namespace: []const u8,

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;
    const COL_STATUS: u8 = 2;

    const NamespaceInfo = struct {
        name: []const u8,
        status: []const u8,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *NamespaceInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.status);
            self.allocator.free(self.age);
        }

        fn getName(self: *const NamespaceInfo) []const u8 { return self.name; }
        fn getAge(self: *const NamespaceInfo) []const u8 { return self.age; }
        fn getStatus(self: *const NamespaceInfo) []const u8 { return self.status; }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) !NamespacesView {
        const current_ns = k8s_service.getCurrentNamespace();

        const view = NamespacesView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .namespaces = std.ArrayListUnmanaged(NamespaceInfo){},
            .filtered_indices = std.ArrayListUnmanaged(usize){},
            .selected_row = 0,
            .scroll_offset = 0,
            .visible_rows = 0,
            .filter_text = "",
            .loading = false,
            .error_message = null,
            .current_namespace = try allocator.dupe(u8, current_ns),
        };

        // Don't call refresh() here - k8s_service pointer will become invalid after App is created
        // Views will refresh when first activated
        return view;
    }

    pub fn deinit(self: *NamespacesView) void {
        for (self.namespaces.items) |*ns| {
            ns.deinit();
        }
        self.namespaces.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        self.allocator.free(self.current_namespace);

        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    /// Refresh namespaces list from K8s API
    pub fn refresh(self: *NamespacesView) !void {
        self.loading = true;
        defer self.loading = false;

        // Clear existing namespaces
        for (self.namespaces.items) |*ns| {
            ns.deinit();
        }
        self.namespaces.clearRetainingCapacity();

        // Clear any previous error
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        // SAFETY: Check if connected to k8s before making requests
        if (!self.k8s_service.isConnected()) {
            self.error_message = try self.allocator.dupe(u8, "Not connected to Kubernetes cluster");
            Logger.warn("NamespacesView: Cannot refresh - not connected to k8s", .{});
            return;
        }

        // Fetch namespaces
        const k8s_namespaces = self.k8s_service.listNamespaces() catch |err| {
            self.error_message = try std.fmt.allocPrint(
                self.allocator,
                "Failed to list namespaces: {}",
                .{err},
            );
            return;
        };

        // Convert to NamespaceInfo
        var selected_idx: ?usize = null;
        for (k8s_namespaces, 0..) |ns, i| {
            // Extract status from JSON value
            const status = if (ns.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("phase")) |phase| {
                        if (phase == .string) {
                            break :blk try self.allocator.dupe(u8, phase.string);
                        }
                    }
                }
                break :blk try self.allocator.dupe(u8, "Active");
            } else try self.allocator.dupe(u8, "Unknown");

            const info = NamespaceInfo{
                .name = try self.allocator.dupe(u8, ns.metadata.name),
                .status = status,
                .age = try age_util.calculateAge(self.allocator, ns.metadata.creationTimestamp),
                .allocator = self.allocator,
            };

            // Check if this is the current namespace
            if (std.mem.eql(u8, info.name, self.current_namespace)) {
                selected_idx = i;
            }

            try self.namespaces.append(self.allocator, info);
        }

        // Set selected row to current namespace
        if (selected_idx) |idx| {
            self.selected_row = @intCast(idx);
            if (self.selected_row >= self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows / 2;
            }
        }

        Logger.info("Loaded {} namespaces", .{self.namespaces.items.len});

        // Rebuild filtered indices
        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *NamespacesView) ?ResourceInfo {
        if (self.filtered_indices.items.len == 0) return null;
        if (self.selected_row >= self.filtered_indices.items.len) return null;
        const idx = self.filtered_indices.items[self.selected_row];
        const item = self.namespaces.items[idx];
        return ResourceInfo{
            .name = item.name,
            .namespace = "cluster",
        };
    }

    pub fn applyFilter(self: *NamespacesView, filter: []const u8) !void {
        self.filter_text = filter;
        try universal_filter.applyFilter(
            NamespaceInfo,
            self.allocator,
            self.namespaces.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            namespaceMatchFn,
        );
        self.applySorting();
    }

    fn applySorting(self: *NamespacesView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(NamespaceInfo, self.namespaces.items, &self.filtered_indices, NamespaceInfo.getName, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(NamespaceInfo, self.namespaces.items, &self.filtered_indices, NamespaceInfo.getAge, self.sort_ascending),
                COL_STATUS => sort_util.sortFilteredIndices(NamespaceInfo, self.namespaces.items, &self.filtered_indices, NamespaceInfo.getStatus, self.sort_ascending),
                else => {},
            }
        }
    }

    fn namespaceMatchFn(item: *const NamespaceInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null;
    }


    /// Switch to the selected namespace
    fn switchNamespace(self: *NamespacesView) !void {
        if (self.selected_row >= self.filtered_indices.items.len) return;

        const actual_idx = self.filtered_indices.items[self.selected_row];
        const selected_ns = self.namespaces.items[actual_idx].name;

        // Update K8s service namespace
        try self.k8s_service.setCurrentNamespace(selected_ns);

        // Update our current namespace
        self.allocator.free(self.current_namespace);
        self.current_namespace = try self.allocator.dupe(u8, selected_ns);

        Logger.info("Switched to namespace: {s}", .{selected_ns});
    }

    pub fn createView(self: *NamespacesView) View {
        return View.create(NamespacesView, self, &vtable);
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
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        self.visible_rows = if (height > 3) height - 3 else 0;

        // Draw box border
        const BoxDrawing = @import("../ui/box_drawing.zig");
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, self.theme.proc_box, self.theme.main_bg, null, .rounded, self.theme.main_fg, self.theme.title);

        // Draw title
        var title_buf: [128]u8 = undefined;
        const title = try std.fmt.bufPrint(&title_buf, "ns(all)[{d}]", .{self.filtered_indices.items.len});
        try terminal.setCursor(x + 1, y);
        try terminal.writeAll(self.theme.title);
        try terminal.writeAll(title);
        try terminal.writeAll("\x1b[0m");

        if (self.loading) {
            try Theme.writeStringWithTheme(terminal, x + 2, y + height / 2, "Loading namespaces...", self.theme.main_fg, self.theme.main_bg);
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
        const status_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_STATUS);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        var status_hdr_buf: [32]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        const status_hdr = std.fmt.bufPrint(&status_hdr_buf, "STATUS{s}", .{status_ind}) catch "STATUS";
        try Theme.writeStringWithTheme(terminal, x + 1, header_y, name_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 40, header_y, status_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 60, header_y, age_hdr, self.theme.title, self.theme.main_bg);

        // Render namespaces
        var row_y = y + 2;
        const end_idx = @min(
            self.scroll_offset + self.visible_rows,
            @as(u32, @intCast(self.filtered_indices.items.len)),
        );

        for (self.filtered_indices.items[self.scroll_offset..end_idx], 0..) |ns_idx, i| {
            const ns = self.namespaces.items[ns_idx];
            const is_selected = (self.scroll_offset + i) == self.selected_row;
            const is_current = std.mem.eql(u8, ns.name, self.current_namespace);

            const fg = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            // Current namespace indicator
            const indicator = if (is_current) "• " else "  ";
            try Theme.writeStringWithTheme(terminal, x + 1, row_y, indicator, fg, bg);

            // Name
            try Theme.writeStringWithTheme(terminal, x + 3, row_y, ns.name[0..@min(36, ns.name.len)], fg, bg);

            // Status
            try Theme.writeStringWithTheme(terminal, x + 40, row_y, ns.status, fg, bg);

            // Age
            try Theme.writeStringWithTheme(terminal, x + 60, row_y, ns.age, fg, bg);

            row_y += 1;
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));

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
                            Logger.err("Failed to refresh namespaces: {}", .{err});
                        };
                        return .handled;
                    },
                    '\n', '\r' => {
                        // Switch to selected namespace
                        self.switchNamespace() catch |err| {
                            Logger.err("Failed to switch namespace: {}", .{err});
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
                    'S' => {
                        sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_STATUS);
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
            .enter => {
                // Switch to selected namespace
                self.switchNamespace() catch |err| {
                    Logger.err("Failed to switch namespace: {}", .{err});
                };
                return .handled;
            },
            .page_down, .page_up, .home, .end => {
                // Navigation shortcuts
                switch (key) {
                    .page_down => {
                        const items_len: u32 = @intCast(self.filtered_indices.items.len);
                        const jump = @min(self.visible_rows, items_len -| self.selected_row -| 1);
                        self.selected_row += jump;
                        if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                            self.scroll_offset = self.selected_row - self.visible_rows + 1;
                        }
                    },
                    .page_up => {
                        const jump = @min(self.visible_rows, self.selected_row);
                        self.selected_row -= jump;
                        if (self.selected_row < self.scroll_offset) {
                            self.scroll_offset = self.selected_row;
                        }
                    },
                    .home => {
                        self.selected_row = 0;
                        self.scroll_offset = 0;
                    },
                    .end => {
                        if (self.filtered_indices.items.len > 0) {
                            self.selected_row = @intCast(self.filtered_indices.items.len - 1);
                            if (self.selected_row >= self.visible_rows) {
                                self.scroll_offset = self.selected_row - self.visible_rows + 1;
                            }
                        }
                    },
                    else => {},
                }
                return .handled;
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        Logger.info("NamespacesView: View activated", .{});
        // Refresh data when view is shown - catch ALL errors to prevent crashes
        self.refresh() catch |err| {
            Logger.err("Failed to refresh namespaces: {any}", .{err});
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
        Logger.debug("NamespacesView hidden", .{});
    }

    fn getName(_: *anyopaque) []const u8 {
        return "Namespaces";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
