/// Access Review Tab - Permission matrix for current user (Tab 1)
///
/// Displays a grid of resources x verbs showing allowed/denied/conditional status.
/// Part of the Authorization View three-tab layout.
const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const Logger = @import("../core/logger.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const TableState = @import("../ui/table_state.zig").TableState;

/// Access status for a single verb on a resource
pub const AccessStatus = enum {
    allowed,
    denied,
    conditional,

    pub fn symbol(self: AccessStatus) []const u8 {
        return switch (self) {
            .allowed => "\xe2\x9c\x93", // checkmark
            .denied => "\xe2\x9c\x97", // x-mark
            .conditional => "~",
        };
    }
};

pub const AccessRow = struct {
    resource: []const u8,
    group: []const u8,
    get: AccessStatus = .denied,
    list: AccessStatus = .denied,
    create: AccessStatus = .denied,
    update: AccessStatus = .denied,
    delete: AccessStatus = .denied,
    watch: AccessStatus = .denied,
    condition_count: ?u32 = null, // null if conditional auth not available
    allocator: std.mem.Allocator,

    pub fn deinit(self: *AccessRow) void {
        self.allocator.free(self.resource);
        self.allocator.free(self.group);
    }

    pub fn getResource(self: *const AccessRow) []const u8 {
        return self.resource;
    }
};

// Core resource types to check access for
const core_resources = [_]struct { resource: []const u8, group: []const u8 }{
    .{ .resource = "pods", .group = "" },
    .{ .resource = "deployments", .group = "apps" },
    .{ .resource = "services", .group = "" },
    .{ .resource = "configmaps", .group = "" },
    .{ .resource = "secrets", .group = "" },
    .{ .resource = "namespaces", .group = "" },
    .{ .resource = "nodes", .group = "" },
    .{ .resource = "ingresses", .group = "networking.k8s.io" },
};

pub const AccessReviewTab = struct {
    allocator: std.mem.Allocator,
    k8s_service: *K8sService,
    table: TableState(AccessRow),
    conditional_auth_available: ?bool = null, // null = not yet detected

    pub fn init(allocator: std.mem.Allocator, k8s_service: *K8sService) AccessReviewTab {
        return AccessReviewTab{
            .allocator = allocator,
            .k8s_service = k8s_service,
            .table = TableState(AccessRow).init(allocator),
        };
    }

    pub fn deinit(self: *AccessReviewTab) void {
        self.table.deinit();
    }

    /// Refresh access review data from the cluster
    pub fn refresh(self: *AccessReviewTab) !void {
        self.table.loading = true;
        defer self.table.loading = false;

        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        // Detect conditional auth support on first run
        if (self.conditional_auth_available == null) {
            self.conditional_auth_available = self.k8s_service.detectConditionalAuth() catch false;
        }

        const namespace = self.k8s_service.getCurrentNamespace();

        // Check access for each resource x verb combination
        for (core_resources) |res| {
            var row = AccessRow{
                .resource = try self.allocator.dupe(u8, res.resource),
                .group = try self.allocator.dupe(u8, res.group),
                .allocator = self.allocator,
            };

            // Check each verb
            const verbs_to_check = [_][]const u8{ "get", "list", "create", "update", "delete", "watch" };
            for (verbs_to_check, 0..) |verb, i| {
                const result = self.k8s_service.checkAccess(verb, res.group, res.resource, namespace) catch {
                    continue;
                };
                const status: AccessStatus = if (result.conditional)
                    .conditional
                else if (result.allowed)
                    .allowed
                else
                    .denied;

                switch (i) {
                    0 => row.get = status,
                    1 => row.list = status,
                    2 => row.create = status,
                    3 => row.update = status,
                    4 => row.delete = status,
                    5 => row.watch = status,
                    else => {},
                }

                if (result.condition_count > 0) {
                    row.condition_count = (row.condition_count orelse 0) + result.condition_count;
                }
            }

            if (self.conditional_auth_available != null and !self.conditional_auth_available.?) {
                row.condition_count = null; // Mark as n/a
            }

            try self.table.appendItem(row);
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn render(self: *AccessReviewTab, term: *Terminal, x: u16, y: u16, width: u16, height: u16, theme: *const theme_loader.ThemeColors) !void {
        if (height == 0) return;

        if (try self.table.renderStatus(term, x, y, theme)) return;

        // Header
        const hdr_y = y;
        const col_resource: u16 = x;
        const col_get: u16 = x + 19;
        const col_list: u16 = col_get + 6;
        const col_create: u16 = col_list + 6;
        const col_update: u16 = col_create + 8;
        const col_delete: u16 = col_update + 8;
        const col_watch: u16 = col_delete + 8;
        const col_cond: u16 = col_watch + 7;

        try Theme.writeStringWithTheme(term, col_resource, hdr_y, "RESOURCE", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_get, hdr_y, "GET", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_list, hdr_y, "LIST", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_create, hdr_y, "CREATE", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_update, hdr_y, "UPDATE", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_delete, hdr_y, "DELETE", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_watch, hdr_y, "WATCH", theme.title, theme.main_bg);

        // Only show CONDITIONS header if width permits
        if (col_cond + 10 < x + width) {
            try Theme.writeStringWithTheme(term, col_cond, hdr_y, "CONDITIONS", theme.title, theme.main_bg);
        }

        // Rows
        const range = self.table.getVisibleRange();
        var row_y = y + 1;
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |idx, i| {
            const row = self.table.items.items[idx];
            const is_sel = self.table.isSelected(i);
            const colors = self.table.rowColors(i, theme);

            try Theme.writeStringWithTheme(term, col_resource, row_y, row.resource[0..@min(18, row.resource.len)], colors.fg, colors.bg);

            // Render each verb with color
            try renderAccessCell(term, col_get, row_y, row.get, is_sel, theme);
            try renderAccessCell(term, col_list, row_y, row.list, is_sel, theme);
            try renderAccessCell(term, col_create, row_y, row.create, is_sel, theme);
            try renderAccessCell(term, col_update, row_y, row.update, is_sel, theme);
            try renderAccessCell(term, col_delete, row_y, row.delete, is_sel, theme);
            try renderAccessCell(term, col_watch, row_y, row.watch, is_sel, theme);

            // Conditions column
            if (col_cond + 10 < x + width) {
                var cond_buf: [16]u8 = undefined;
                const cond_str = if (row.condition_count) |c|
                    if (c > 0)
                        std.fmt.bufPrint(&cond_buf, "CEL: {d}", .{c}) catch "-"
                    else
                        "-"
                else
                    "(n/a)";
                const cond_fg = if (is_sel) theme.selected_fg else theme.main_fg;
                try Theme.writeStringWithTheme(term, col_cond, row_y, cond_str, cond_fg, if (is_sel) theme.selected_bg else theme.main_bg);
            }

            row_y += 1;
        }
    }

    pub fn applyFilter(self: *AccessReviewTab, filter: []const u8) !void {
        try self.table.applyFilter(filter, accessMatchFn);
    }

    pub fn moveDown(self: *AccessReviewTab) void {
        self.table.navigateDown();
    }

    pub fn moveUp(self: *AccessReviewTab) void {
        self.table.navigateUp();
    }

    pub fn moveTop(self: *AccessReviewTab) void {
        self.table.gotoTop();
    }

    pub fn moveBottom(self: *AccessReviewTab) void {
        self.table.gotoBottom();
    }

    pub fn pageDown(self: *AccessReviewTab) void {
        self.table.pageDown();
    }

    pub fn pageUp(self: *AccessReviewTab) void {
        self.table.pageUp();
    }

    pub fn getSelectedRow(self: *const AccessReviewTab) ?*const AccessRow {
        return self.table.getSelectedItem();
    }

    fn accessMatchFn(item: *const AccessRow, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.resource, filter) != null;
    }
};

fn renderAccessCell(term: *Terminal, cx: u16, cy: u16, status: AccessStatus, is_sel: bool, theme: *const theme_loader.ThemeColors) !void {
    const bg = if (is_sel) theme.selected_bg else theme.main_bg;
    const fg = switch (status) {
        .allowed => theme.status_running, // green
        .denied => theme.status_failed, // red
        .conditional => theme.status_pending, // yellow
    };
    try Theme.writeStringWithTheme(term, cx, cy, status.symbol(), fg, bg);
}
