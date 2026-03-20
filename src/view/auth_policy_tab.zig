/// Policy Browser Tab - Aggregated RBAC + Cedar policies (Tab 2)
///
/// Lists all RBAC ClusterRoles/Bindings and Cedar policies in a unified table.
/// Part of the Authorization View three-tab layout.
const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const Logger = @import("../core/logger.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const TableState = @import("../ui/table_state.zig").TableState;

pub const PolicyRow = struct {
    source: []const u8, // role name or cedar policy name
    policy_type: PolicyType,
    resource: []const u8,
    verbs: []const u8,
    subjects: []const u8,
    allocator: std.mem.Allocator,

    pub const PolicyType = enum {
        rbac,
        cedar,

        pub fn label(self: PolicyType) []const u8 {
            return switch (self) {
                .rbac => "RBAC",
                .cedar => "Cedar",
            };
        }
    };

    pub fn deinit(self: *PolicyRow) void {
        self.allocator.free(self.source);
        self.allocator.free(self.resource);
        self.allocator.free(self.verbs);
        self.allocator.free(self.subjects);
    }

    pub fn getSource(self: *const PolicyRow) []const u8 {
        return self.source;
    }
};

pub const PolicyBrowserTab = struct {
    allocator: std.mem.Allocator,
    k8s_service: *K8sService,
    table: TableState(PolicyRow),
    cedar_available: ?bool = null,

    pub fn init(allocator: std.mem.Allocator, k8s_service: *K8sService) PolicyBrowserTab {
        return PolicyBrowserTab{
            .allocator = allocator,
            .k8s_service = k8s_service,
            .table = TableState(PolicyRow).init(allocator),
        };
    }

    pub fn deinit(self: *PolicyBrowserTab) void {
        self.table.deinit();
    }

    /// Refresh policy browser data from the cluster
    pub fn refresh(self: *PolicyBrowserTab) !void {
        self.table.loading = true;
        defer self.table.loading = false;

        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        // Fetch RBAC roles and bindings
        const rbac_policies = self.k8s_service.listRBACPolicies() catch |err| {
            try self.table.setConnectionError("RBAC policies", err);
            return;
        };
        defer {
            for (rbac_policies) |*p| {
                var mp = p.*;
                mp.deinit();
            }
            self.allocator.free(rbac_policies);
        }

        for (rbac_policies) |p| {
            try self.table.appendItem(PolicyRow{
                .source = try self.allocator.dupe(u8, p.source),
                .policy_type = .rbac,
                .resource = try self.allocator.dupe(u8, p.resource),
                .verbs = try self.allocator.dupe(u8, p.verbs),
                .subjects = try self.allocator.dupe(u8, p.subjects),
                .allocator = self.allocator,
            });
        }

        // Detect Cedar and fetch policies
        if (self.cedar_available == null) {
            self.cedar_available = self.k8s_service.detectCedarAuth() catch false;
        }

        if (self.cedar_available.?) {
            const cedar_policies = self.k8s_service.listCedarPolicies() catch |err| {
                Logger.warn("Failed to list Cedar policies: {}", .{err});
                return;
            };
            defer {
                for (cedar_policies) |*p| {
                    var mp = p.*;
                    mp.deinit();
                }
                self.allocator.free(cedar_policies);
            }

            for (cedar_policies) |p| {
                try self.table.appendItem(PolicyRow{
                    .source = try self.allocator.dupe(u8, p.source),
                    .policy_type = .cedar,
                    .resource = try self.allocator.dupe(u8, p.resource),
                    .verbs = try self.allocator.dupe(u8, p.verbs),
                    .subjects = try self.allocator.dupe(u8, p.subjects),
                    .allocator = self.allocator,
                });
            }
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn render(self: *PolicyBrowserTab, term: *Terminal, x: u16, y: u16, width: u16, height: u16, theme: *const theme_loader.ThemeColors) !void {
        if (height == 0) return;
        _ = width;

        if (try self.table.renderStatus(term, x, y, theme)) return;

        // Header
        const hdr_y = y;
        const col_source: u16 = x;
        const col_type: u16 = x + 27;
        const col_res: u16 = col_type + 8;
        const col_verbs: u16 = col_res + 18;
        const col_subj: u16 = col_verbs + 24;

        try Theme.writeStringWithTheme(term, col_source, hdr_y, "SOURCE", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_type, hdr_y, "TYPE", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_res, hdr_y, "RESOURCE", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_verbs, hdr_y, "VERBS", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_subj, hdr_y, "SUBJECTS", theme.title, theme.main_bg);

        // Rows
        const range = self.table.getVisibleRange();
        var row_y = y + 1;
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |idx, i| {
            const row = self.table.items.items[idx];
            const colors = self.table.rowColors(i, theme);

            try Theme.writeStringWithTheme(term, col_source, row_y, row.source[0..@min(26, row.source.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, col_type, row_y, row.policy_type.label(), colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, col_res, row_y, row.resource[0..@min(16, row.resource.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, col_verbs, row_y, row.verbs[0..@min(22, row.verbs.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, col_subj, row_y, row.subjects[0..@min(30, row.subjects.len)], colors.fg, colors.bg);

            row_y += 1;
        }
    }

    pub fn applyFilter(self: *PolicyBrowserTab, filter: []const u8) !void {
        try self.table.applyFilter(filter, policyMatchFn);
    }

    pub fn moveDown(self: *PolicyBrowserTab) void {
        self.table.navigateDown();
    }

    pub fn moveUp(self: *PolicyBrowserTab) void {
        self.table.navigateUp();
    }

    pub fn moveTop(self: *PolicyBrowserTab) void {
        self.table.gotoTop();
    }

    pub fn moveBottom(self: *PolicyBrowserTab) void {
        self.table.gotoBottom();
    }

    pub fn pageDown(self: *PolicyBrowserTab) void {
        self.table.pageDown();
    }

    pub fn pageUp(self: *PolicyBrowserTab) void {
        self.table.pageUp();
    }

    fn policyMatchFn(item: *const PolicyRow, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.source, filter) != null or
            std.mem.indexOf(u8, item.resource, filter) != null or
            std.mem.indexOf(u8, item.subjects, filter) != null;
    }
};
