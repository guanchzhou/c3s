/// Condition Inspector Tab - CEL condition chain details (Tab 3, KEP 5681)
///
/// Shows detailed authorization conditions for a specific resource selected
/// from the Access Review tab. Requires Kubernetes v1.36+ with
/// ConditionalAuthorization feature gate enabled.
/// Part of the Authorization View three-tab layout.
const std = @import("std");
const Terminal = @import("../core/Terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const Logger = @import("../core/logger.zig");
const k8s_service_mod = @import("../services/K8sService.zig");
const K8sService = k8s_service_mod.K8sService;
const TableState = @import("../ui/TableState.zig").TableState;

pub const ConditionRow = struct {
    index: u32,
    effect: []const u8, // "Allow" or "Deny"
    authorizer: []const u8,
    expression: []const u8,
    description: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ConditionRow) void {
        self.allocator.free(self.effect);
        self.allocator.free(self.authorizer);
        self.allocator.free(self.expression);
        self.allocator.free(self.description);
    }
};

pub const ConditionInspectorTab = struct {
    allocator: std.mem.Allocator,
    k8s_service: *K8sService,
    table: TableState(ConditionRow),
    condition_resource: ?[]const u8 = null, // e.g. "pods/delete"

    pub fn init(allocator: std.mem.Allocator, k8s_service: *K8sService) ConditionInspectorTab {
        return ConditionInspectorTab{
            .allocator = allocator,
            .k8s_service = k8s_service,
            .table = TableState(ConditionRow).init(allocator),
        };
    }

    pub fn deinit(self: *ConditionInspectorTab) void {
        self.table.deinit();
        if (self.condition_resource) |r| self.allocator.free(r);
    }

    /// Refresh conditions for a specific resource
    pub fn refresh(self: *ConditionInspectorTab, resource: []const u8, group: []const u8, conditional_auth_available: ?bool) !void {
        self.table.loading = true;
        defer self.table.loading = false;

        self.table.clearItems();

        // Dupe before freeing: `resource` is sometimes self.condition_resource
        // itself on a refresh, and a failed dupe would otherwise leave the field
        // dangling for the next call to free again.
        const new_resource = try self.allocator.dupe(u8, resource);
        if (self.condition_resource) |r| self.allocator.free(r);
        self.condition_resource = new_resource;

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        if (conditional_auth_available != null and !conditional_auth_available.?) {
            try self.table.setError("Conditional Authorization (KEP 5681) not available on this cluster. Requires K8s v1.36+ with ConditionalAuthorization feature gate enabled.");
            return;
        }

        const namespace = self.k8s_service.getCurrentNamespace();
        const conditions = self.k8s_service.getAuthorizationConditions(resource, group, namespace) catch |err| {
            try self.table.setConnectionError("conditions", err);
            return;
        };
        defer {
            for (conditions) |*c| {
                var mc = c.*;
                mc.deinit();
            }
            self.allocator.free(conditions);
        }

        for (conditions, 0..) |c, i| {
            try self.table.appendItem(ConditionRow{
                .index = @intCast(i + 1),
                .effect = try self.allocator.dupe(u8, c.effect),
                .authorizer = try self.allocator.dupe(u8, c.authorizer),
                .expression = try self.allocator.dupe(u8, c.expression),
                .description = try self.allocator.dupe(u8, c.description),
                .allocator = self.allocator,
            });
        }

        // Rebuild filtered indices to show all items (no filtering for conditions)
        try self.table.applyFilter("", conditionMatchFn);
    }

    pub fn render(self: *ConditionInspectorTab, term: *Terminal, x: u16, y: u16, _: u16, height: u16, theme: *const theme_loader.ThemeColors) !void {
        if (height == 0) return;

        // Title
        var title_buf: [128]u8 = undefined;
        const title = if (self.condition_resource) |r|
            std.fmt.bufPrint(&title_buf, "Conditions for: {s} ({d} conditions)", .{ r, self.table.items.items.len }) catch "Conditions"
        else
            "No resource selected. Press Enter on a conditional row in Tab 1.";

        try Theme.writeStringWithTheme(term, x, y, title, theme.title, theme.main_bg);

        if (self.table.items.items.len == 0 and self.condition_resource != null) {
            if (self.table.error_message) |msg| {
                // Word-wrap the error message
                const max_w: usize = if (x + 2 < 65535) 60 else 1;
                var err_y = y + 2;
                var remaining = msg;
                while (remaining.len > 0 and err_y < y + height) {
                    const chunk = remaining[0..@min(max_w, remaining.len)];
                    try Theme.writeStringWithTheme(term, x, err_y, chunk, theme.status_failed, theme.main_bg);
                    remaining = remaining[@min(max_w, remaining.len)..];
                    err_y += 1;
                }
                return;
            }
            try Theme.writeStringWithTheme(term, x, y + 2, "No conditions found for this resource.", theme.main_fg, theme.main_bg);
            return;
        }

        // Header
        const hdr_y = y + 1;
        const col_idx: u16 = x;
        const col_effect: u16 = col_idx + 4;
        const col_auth: u16 = col_effect + 10;
        const col_expr: u16 = col_auth + 18;
        const col_desc: u16 = col_expr + 40;

        try Theme.writeStringWithTheme(term, col_idx, hdr_y, "#", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_effect, hdr_y, "EFFECT", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_auth, hdr_y, "AUTHORIZER", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_expr, hdr_y, "EXPRESSION", theme.title, theme.main_bg);
        try Theme.writeStringWithTheme(term, col_desc, hdr_y, "DESCRIPTION", theme.title, theme.main_bg);

        // Rows — condition inspector uses items directly (via filtered indices showing all)
        const vis: u32 = if (height > 2) height - 2 else 0;
        self.table.visible_rows = vis;
        const range = self.table.getVisibleRange();
        var row_y = hdr_y + 1;
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |idx, i| {
            const row = self.table.items.items[idx];
            const is_sel = self.table.isSelected(i);
            const colors = self.table.rowColors(i, theme);

            var idx_buf: [8]u8 = undefined;
            const idx_str = std.fmt.bufPrint(&idx_buf, "{d}", .{row.index}) catch "?";
            try Theme.writeStringWithTheme(term, col_idx, row_y, idx_str, colors.fg, colors.bg);

            // Color the effect
            const effect_fg = if (std.mem.eql(u8, row.effect, "Deny"))
                theme.status_failed
            else
                theme.status_running;
            try Theme.writeStringWithTheme(term, col_effect, row_y, row.effect[0..@min(8, row.effect.len)], effect_fg, if (is_sel) theme.selected_bg else theme.main_bg);

            try Theme.writeStringWithTheme(term, col_auth, row_y, row.authorizer[0..@min(16, row.authorizer.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, col_expr, row_y, row.expression[0..@min(38, row.expression.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(term, col_desc, row_y, row.description[0..@min(30, row.description.len)], colors.fg, colors.bg);

            row_y += 1;
        }
    }

    pub fn moveDown(self: *ConditionInspectorTab) void {
        self.table.navigateDown();
    }

    pub fn moveUp(self: *ConditionInspectorTab) void {
        self.table.navigateUp();
    }

    pub fn moveTop(self: *ConditionInspectorTab) void {
        self.table.gotoTop();
    }

    pub fn moveBottom(self: *ConditionInspectorTab) void {
        self.table.gotoBottom();
    }

    pub fn pageDown(self: *ConditionInspectorTab) void {
        self.table.pageDown();
    }

    pub fn pageUp(self: *ConditionInspectorTab) void {
        self.table.pageUp();
    }

    /// Always match — condition inspector does not support filtering
    fn conditionMatchFn(_: *const ConditionRow, _: []const u8) bool {
        return true;
    }
};
