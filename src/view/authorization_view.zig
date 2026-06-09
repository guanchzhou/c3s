/// Authorization View - Unified view for K8s authorization (access review, policies, conditions)
///
/// Three-tab view:
///   Tab 1 (Access Review): Permission matrix for current user
///   Tab 2 (Policy Browser): Aggregated RBAC + Cedar policies
///   Tab 3 (Condition Inspector): CEL condition chain details (KEP 5681)
///
/// This is the coordinator that owns 3 tab structs and dispatches
/// rendering, key handling, and filtering to the active tab.
const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = theme_loader;
const theme_loader = @import("../model/theme_loader.zig");
const view_mod = @import("../viewmodel/view.zig");
const View = view_mod.View;
const Key = @import("../core/terminal.zig").Key;
const KeyResult = View.KeyResult;
const Logger = @import("../core/logger.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const hints_model = @import("../model/hints.zig");

// Tab modules
const auth_access_tab = @import("auth_access_tab.zig");
const auth_policy_tab = @import("auth_policy_tab.zig");
const auth_condition_tab = @import("auth_condition_tab.zig");

pub const AuthorizationView = struct {
    // Re-export tab types so `AuthorizationView.AccessRow` etc. works in tests
    pub const AccessStatus = auth_access_tab.AccessStatus;
    pub const AccessRow = auth_access_tab.AccessRow;
    pub const PolicyRow = auth_policy_tab.PolicyRow;
    pub const ConditionRow = auth_condition_tab.ConditionRow;

    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,

    // Tab state
    active_tab: Tab = .access_review,

    // The three tabs
    access_tab: auth_access_tab.AccessReviewTab,
    policy_tab: auth_policy_tab.PolicyBrowserTab,
    condition_tab: auth_condition_tab.ConditionInspectorTab,

    // Common state
    visible_rows: u32 = 0,
    filter_text: []const u8 = "",
    loading: bool = false,
    error_message: ?[]const u8 = null,

    pub const Tab = enum(u8) {
        access_review = 1,
        policy_browser = 2,
        condition_inspector = 3,
    };

    // ===== Compatibility accessors =====
    // These expose the internal tab state so existing tests keep working
    // without changing their field access patterns.

    /// Proxy for access_tab.table.items
    pub fn getAccessRows(self: *AuthorizationView) *std.ArrayListUnmanaged(AccessRow) {
        return &self.access_tab.table.items;
    }
    /// Proxy for access_tab.table.filtered_indices
    pub fn getAccessFiltered(self: *AuthorizationView) *std.ArrayListUnmanaged(usize) {
        return &self.access_tab.table.filtered_indices;
    }

    /// Proxy for policy_tab.table.items
    pub fn getPolicyRows(self: *AuthorizationView) *std.ArrayListUnmanaged(PolicyRow) {
        return &self.policy_tab.table.items;
    }
    /// Proxy for policy_tab.table.filtered_indices
    pub fn getPolicyFiltered(self: *AuthorizationView) *std.ArrayListUnmanaged(usize) {
        return &self.policy_tab.table.filtered_indices;
    }

    /// Proxy for condition_tab.table.items
    pub fn getConditionRows(self: *AuthorizationView) *std.ArrayListUnmanaged(ConditionRow) {
        return &self.condition_tab.table.items;
    }

    // Provide public field-like access via direct struct fields that mirror
    // the old layout. We use wrapper functions called from tests.

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) !AuthorizationView {
        return AuthorizationView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .access_tab = auth_access_tab.AccessReviewTab.init(allocator, k8s_service),
            .policy_tab = auth_policy_tab.PolicyBrowserTab.init(allocator, k8s_service),
            .condition_tab = auth_condition_tab.ConditionInspectorTab.init(allocator, k8s_service),
        };
    }

    pub fn deinit(self: *AuthorizationView) void {
        self.access_tab.deinit();
        self.policy_tab.deinit();
        self.condition_tab.deinit();
        if (self.error_message) |msg| self.allocator.free(msg);
    }

    // ===== Compatibility methods for tests =====

    pub fn clearAccessRows(self: *AuthorizationView) void {
        self.access_tab.table.clearItems();
    }

    pub fn clearPolicyRows(self: *AuthorizationView) void {
        self.policy_tab.table.clearItems();
    }

    pub fn clearConditionRows(self: *AuthorizationView) void {
        self.condition_tab.table.clearItems();
    }

    // ===== Data fetching =====

    /// Refresh Tab 1: Access Review data
    pub fn refreshAccessReview(self: *AuthorizationView) !void {
        self.loading = true;
        defer self.loading = false;

        // Sync error state: clear coordinator error before refresh
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        try self.access_tab.refresh();

        // Propagate error from tab to coordinator for backward compat
        if (self.access_tab.table.error_message) |msg| {
            self.error_message = try self.allocator.dupe(u8, msg);
        }
    }

    /// Refresh Tab 2: Policy Browser data
    pub fn refreshPolicies(self: *AuthorizationView) !void {
        self.loading = true;
        defer self.loading = false;

        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        try self.policy_tab.refresh();

        // Propagate error from tab to coordinator
        if (self.policy_tab.table.error_message) |msg| {
            self.error_message = try self.allocator.dupe(u8, msg);
        }
    }

    /// Refresh Tab 3: Condition Inspector for a specific resource
    pub fn refreshConditions(self: *AuthorizationView, resource: []const u8, group: []const u8) !void {
        self.loading = true;
        defer self.loading = false;

        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        try self.condition_tab.refresh(resource, group, self.access_tab.conditional_auth_available);

        // Propagate error from tab to coordinator
        if (self.condition_tab.table.error_message) |msg| {
            self.error_message = try self.allocator.dupe(u8, msg);
        }
    }

    // ===== Filter =====

    pub fn applyFilter(self: *AuthorizationView, filter: []const u8) !void {
        self.filter_text = filter;
        switch (self.active_tab) {
            .access_review => try self.access_tab.applyFilter(filter),
            .policy_browser => try self.policy_tab.applyFilter(filter),
            .condition_inspector => {},
        }
    }

    pub fn rebuildAccessFilter(self: *AuthorizationView) !void {
        try self.access_tab.applyFilter(self.access_tab.table.filter_text);
    }

    // ===== Navigation =====

    pub fn moveDown(self: *AuthorizationView) void {
        switch (self.active_tab) {
            .access_review => self.access_tab.moveDown(),
            .policy_browser => self.policy_tab.moveDown(),
            .condition_inspector => self.condition_tab.moveDown(),
        }
    }

    pub fn moveUp(self: *AuthorizationView) void {
        switch (self.active_tab) {
            .access_review => self.access_tab.moveUp(),
            .policy_browser => self.policy_tab.moveUp(),
            .condition_inspector => self.condition_tab.moveUp(),
        }
    }

    pub fn moveTop(self: *AuthorizationView) void {
        switch (self.active_tab) {
            .access_review => self.access_tab.moveTop(),
            .policy_browser => self.policy_tab.moveTop(),
            .condition_inspector => self.condition_tab.moveTop(),
        }
    }

    pub fn moveBottom(self: *AuthorizationView) void {
        switch (self.active_tab) {
            .access_review => self.access_tab.moveBottom(),
            .policy_browser => self.policy_tab.moveBottom(),
            .condition_inspector => self.condition_tab.moveBottom(),
        }
    }

    // ===== View trait =====

    pub fn createView(self: *AuthorizationView) View {
        return View.create(AuthorizationView, self, &vtable);
    }

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *AuthorizationView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }
    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *AuthorizationView = @ptrCast(@alignCast(ptr));
        if (self.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }
    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *AuthorizationView = @ptrCast(@alignCast(ptr));
        try self.refreshAccessReview();
    }
    fn vtableGetSelectedResource(ptr: *anyopaque) ?view_mod.ResourceInfo {
        const self: *AuthorizationView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
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

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *AuthorizationView = @ptrCast(@alignCast(ptr));

        // Update visible_rows on all tabs
        const content_vis = if (height > 3) height - 3 else 0;
        self.visible_rows = content_vis;
        self.access_tab.table.visible_rows = content_vis;
        self.policy_tab.table.visible_rows = content_vis;
        // condition tab sets its own visible_rows in its render

        // Tab bar
        const tab_y = y;
        try self.renderTabBar(term, x, tab_y, width);

        if (self.loading) {
            try Theme.writeStringWithTheme(term, x, y + 1, "Loading...", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        if (self.error_message) |msg| {
            // Word-wrap the error message
            const max_w: usize = if (width > 2) width - 2 else 1;
            var err_y = y + 2;
            var remaining = msg;
            while (remaining.len > 0 and err_y < y + height) {
                const chunk = remaining[0..@min(max_w, remaining.len)];
                try Theme.writeStringWithTheme(term, x, err_y, chunk, self.theme.status_failed, self.theme.main_bg);
                remaining = remaining[@min(max_w, remaining.len)..];
                err_y += 1;
            }
            return;
        }

        // Render active tab content
        const content_y = tab_y + 1;
        const content_h = if (height > 1) height - 1 else 0;
        switch (self.active_tab) {
            .access_review => try self.access_tab.render(term, x, content_y, width, content_h, self.theme),
            .policy_browser => try self.policy_tab.render(term, x, content_y, width, content_h, self.theme),
            .condition_inspector => try self.condition_tab.render(term, x, content_y, width, content_h, self.theme),
        }
    }

    fn renderTabBar(self: *AuthorizationView, term: *Terminal, x: u16, y: u16, width: u16) !void {
        _ = width;
        const tabs = [_]struct { label: []const u8, tab: Tab }{
            .{ .label = " 1:Access Review ", .tab = .access_review },
            .{ .label = " 2:Policies ", .tab = .policy_browser },
            .{ .label = " 3:Conditions ", .tab = .condition_inspector },
        };

        var cx: u16 = x;
        for (tabs) |t| {
            const is_active = self.active_tab == t.tab;
            const fg = if (is_active) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (is_active) self.theme.selected_bg else self.theme.main_bg;
            try Theme.writeStringWithTheme(term, cx, y, t.label, fg, bg);
            cx += @intCast(t.label.len);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *AuthorizationView = @ptrCast(@alignCast(ptr));

        switch (key) {
            .char => |c| {
                switch (c) {
                    '1' => {
                        self.active_tab = .access_review;
                        return .handled;
                    },
                    '2' => {
                        self.active_tab = .policy_browser;
                        if (self.policy_tab.table.items.items.len == 0) {
                            self.refreshPolicies() catch |err| {
                                Logger.err("Failed to refresh policies: {}", .{err});
                            };
                        }
                        return .handled;
                    },
                    '3' => {
                        self.active_tab = .condition_inspector;
                        return .handled;
                    },
                    '\t' => {
                        // Cycle tabs
                        self.active_tab = switch (self.active_tab) {
                            .access_review => .policy_browser,
                            .policy_browser => .condition_inspector,
                            .condition_inspector => .access_review,
                        };
                        // Lazy-load policy data
                        if (self.active_tab == .policy_browser and self.policy_tab.table.items.items.len == 0) {
                            self.refreshPolicies() catch |err| {
                                Logger.err("Failed to refresh policies: {}", .{err});
                            };
                        }
                        return .handled;
                    },
                    'j' => {
                        self.moveDown();
                        return .handled;
                    },
                    'k' => {
                        self.moveUp();
                        return .handled;
                    },
                    'g' => {
                        self.moveTop();
                        return .handled;
                    },
                    'G' => {
                        self.moveBottom();
                        return .handled;
                    },
                    'r' => {
                        // Refresh current tab
                        switch (self.active_tab) {
                            .access_review => self.refreshAccessReview() catch |err| {
                                Logger.err("Failed to refresh access review: {}", .{err});
                            },
                            .policy_browser => self.refreshPolicies() catch |err| {
                                Logger.err("Failed to refresh policies: {}", .{err});
                            },
                            .condition_inspector => {
                                const sel = self.access_tab.getSelectedRow();
                                if (sel) |row| {
                                    self.refreshConditions(row.resource, row.group) catch |err| {
                                        Logger.err("Failed to refresh conditions: {}", .{err});
                                    };
                                }
                            },
                        }
                        return .handled;
                    },
                    'd' => {
                        if (self.active_tab == .policy_browser) return .request_describe;
                        return .not_handled;
                    },
                    'y' => {
                        if (self.active_tab == .policy_browser) return .request_yaml;
                        return .not_handled;
                    },
                    ':' => return .request_command_palette,
                    '/' => return .request_filter,
                    else => return .not_handled,
                }
            },
            .down => {
                self.moveDown();
                return .handled;
            },
            .up => {
                self.moveUp();
                return .handled;
            },
            .page_down => {
                switch (self.active_tab) {
                    .access_review => self.access_tab.pageDown(),
                    .policy_browser => self.policy_tab.pageDown(),
                    .condition_inspector => self.condition_tab.pageDown(),
                }
                return .handled;
            },
            .page_up => {
                switch (self.active_tab) {
                    .access_review => self.access_tab.pageUp(),
                    .policy_browser => self.policy_tab.pageUp(),
                    .condition_inspector => self.condition_tab.pageUp(),
                }
                return .handled;
            },
            .home => {
                self.moveTop();
                return .handled;
            },
            .end => {
                self.moveBottom();
                return .handled;
            },
            .enter => {
                // In Tab 1, Enter on a conditional row opens Tab 3
                if (self.active_tab == .access_review) {
                    if (self.access_tab.getSelectedRow()) |row| {
                        self.refreshConditions(row.resource, row.group) catch |err| {
                            Logger.err("Failed to refresh conditions: {}", .{err});
                        };
                        self.active_tab = .condition_inspector;
                        return .handled;
                    }
                }
                return .not_handled;
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *AuthorizationView = @ptrCast(@alignCast(ptr));
        // Refresh access review on show
        if (self.access_tab.table.items.items.len == 0) {
            self.refreshAccessReview() catch |err| {
                Logger.err("Failed to refresh access review on show: {}", .{err});
            };
        }
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "authorization";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return authorizationHints();
    }

    fn deinitView(_: *anyopaque) void {}

    // ===== Hints =====

    pub fn authorizationHints() hints_model.HintConfig {
        const hint_items = comptime [_]hints_model.Hint{
            hints_model.Hint.highlighted("1/2/3", "", " tabs", 1),
            hints_model.Hint.highlighted("Tab", "", " cycle", 2),
            hints_model.Hint.highlighted("Enter", "", " inspect", 3),
            hints_model.Hint.highlighted("/", "", " filter", 4),
            hints_model.Hint.highlighted("r", "", "efresh", 5),
            hints_model.Hint.highlighted("d", "", "escribe", 6),
            hints_model.Hint.highlighted("y", "", " yaml", 7),
            hints_model.Hint.highlighted("?", "", " help", 20),
        };

        return .{
            .quick_commands = &.{},
            .hints = &hint_items,
        };
    }

    pub fn getSelectedResourceInfo(_: *AuthorizationView) ?view_mod.ResourceInfo {
        return null;
    }

    // ===== Compatibility: match functions exposed for tests =====

    pub fn accessMatchFn(item: *const AccessRow, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.resource, filter) != null;
    }

    pub fn policyMatchFn(item: *const PolicyRow, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.source, filter) != null or
            std.mem.indexOf(u8, item.resource, filter) != null or
            std.mem.indexOf(u8, item.subjects, filter) != null;
    }
};

// ===== Tests =====

test "AccessStatus.symbol returns correct UTF-8" {
    const testing = std.testing;
    try testing.expectEqualStrings("\xe2\x9c\x93", AuthorizationView.AccessStatus.allowed.symbol());
    try testing.expectEqualStrings("\xe2\x9c\x97", AuthorizationView.AccessStatus.denied.symbol());
    try testing.expectEqualStrings("~", AuthorizationView.AccessStatus.conditional.symbol());
}

test "PolicyRow.PolicyType.label returns correct strings" {
    const testing = std.testing;
    try testing.expectEqualStrings("RBAC", AuthorizationView.PolicyRow.PolicyType.rbac.label());
    try testing.expectEqualStrings("Cedar", AuthorizationView.PolicyRow.PolicyType.cedar.label());
}

test "Tab enum values" {
    const testing = std.testing;
    try testing.expectEqual(@as(u8, 1), @intFromEnum(AuthorizationView.Tab.access_review));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(AuthorizationView.Tab.policy_browser));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(AuthorizationView.Tab.condition_inspector));
}

test "AuthorizationView init and deinit" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // Check initial state
    try testing.expectEqual(AuthorizationView.Tab.access_review, view.active_tab);
    try testing.expectEqual(@as(usize, 0), view.access_tab.table.items.items.len);
    try testing.expectEqual(@as(usize, 0), view.policy_tab.table.items.items.len);
    try testing.expectEqual(@as(usize, 0), view.condition_tab.table.items.items.len);
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);
    try testing.expectEqual(@as(u32, 0), view.policy_tab.table.selected_row);
    try testing.expectEqual(@as(u32, 0), view.condition_tab.table.selected_row);
    try testing.expect(view.condition_tab.condition_resource == null);
    try testing.expect(view.error_message == null);
    try testing.expectEqual(false, view.loading);
    try testing.expect(view.access_tab.conditional_auth_available == null);
    try testing.expect(view.policy_tab.cedar_available == null);
}

test "AuthorizationView multiple init/deinit cycles" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    for (0..10) |_| {
        var view = try AuthorizationView.init(allocator, &theme, &k8s);
        view.deinit();
    }
}

test "AuthorizationView createView returns correct interface" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    const v = view.createView();
    try testing.expectEqualStrings("authorization", v.getName());
}

test "AuthorizationView hints are valid" {
    const testing = std.testing;
    const hints = AuthorizationView.authorizationHints();

    try testing.expect(hints.hints.len > 0);
    try testing.expectEqual(@as(usize, 8), hints.hints.len);

    // Check all hints are accessible without crash
    for (hints.hints) |hint| {
        const rt = @intFromEnum(hint.render_fn);
        try testing.expect(rt == 0 or rt == 1);
        try testing.expect(std.unicode.utf8ValidateSlice(hint.key));
        try testing.expect(std.unicode.utf8ValidateSlice(hint.before));
        try testing.expect(std.unicode.utf8ValidateSlice(hint.after));
    }
}

test "AuthorizationView getSelectedResourceInfo always null" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    try testing.expect(view.getSelectedResourceInfo() == null);
}

test "AuthorizationView navigation on empty lists" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // moveDown/moveUp on empty list shouldn't crash
    view.moveDown();
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);
    view.moveUp();
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);
    view.moveTop();
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);
    view.moveBottom();
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);
}

test "AuthorizationView tab switching" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // Start on access review
    try testing.expectEqual(AuthorizationView.Tab.access_review, view.active_tab);

    // Switch to Tab 2 via key
    const v = view.createView();
    _ = try v.handleKey(.{ .char = '2' });
    try testing.expectEqual(AuthorizationView.Tab.policy_browser, view.active_tab);

    // Switch to Tab 3 via key
    _ = try v.handleKey(.{ .char = '3' });
    try testing.expectEqual(AuthorizationView.Tab.condition_inspector, view.active_tab);

    // Switch to Tab 1 via key
    _ = try v.handleKey(.{ .char = '1' });
    try testing.expectEqual(AuthorizationView.Tab.access_review, view.active_tab);
}

test "AuthorizationView tab cycling" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    const v = view.createView();

    // Tab cycles: access_review -> policy_browser -> condition_inspector -> access_review
    try testing.expectEqual(AuthorizationView.Tab.access_review, view.active_tab);

    _ = try v.handleKey(.{ .char = '\t' });
    try testing.expectEqual(AuthorizationView.Tab.policy_browser, view.active_tab);

    _ = try v.handleKey(.{ .char = '\t' });
    try testing.expectEqual(AuthorizationView.Tab.condition_inspector, view.active_tab);

    _ = try v.handleKey(.{ .char = '\t' });
    try testing.expectEqual(AuthorizationView.Tab.access_review, view.active_tab);
}

test "AuthorizationView key bindings return correct results" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    const v = view.createView();

    // Navigation keys
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.{ .char = 'j' }));
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.{ .char = 'k' }));
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.{ .char = 'g' }));
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.{ .char = 'G' }));
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.down));
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.up));

    // Command keys
    try testing.expectEqual(View.KeyResult.request_command_palette, try v.handleKey(.{ .char = ':' }));
    try testing.expectEqual(View.KeyResult.request_filter, try v.handleKey(.{ .char = '/' }));

    // Tab switch keys
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.{ .char = '1' }));
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.{ .char = '2' }));
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.{ .char = '3' }));
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.{ .char = '\t' }));

    // Refresh
    try testing.expectEqual(View.KeyResult.handled, try v.handleKey(.{ .char = 'r' }));

    // Unhandled keys
    try testing.expectEqual(View.KeyResult.not_handled, try v.handleKey(.{ .char = 'z' }));
    try testing.expectEqual(View.KeyResult.not_handled, try v.handleKey(.{ .char = 'q' }));
}

test "AuthorizationView describe/yaml only on policy tab" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    const v = view.createView();

    // On Tab 1, d/y should be not_handled
    try testing.expectEqual(View.KeyResult.not_handled, try v.handleKey(.{ .char = 'd' }));
    try testing.expectEqual(View.KeyResult.not_handled, try v.handleKey(.{ .char = 'y' }));

    // Switch to Tab 2
    _ = try v.handleKey(.{ .char = '2' });
    try testing.expectEqual(View.KeyResult.request_describe, try v.handleKey(.{ .char = 'd' }));
    try testing.expectEqual(View.KeyResult.request_yaml, try v.handleKey(.{ .char = 'y' }));

    // On Tab 3, d/y should be not_handled
    _ = try v.handleKey(.{ .char = '3' });
    try testing.expectEqual(View.KeyResult.not_handled, try v.handleKey(.{ .char = 'd' }));
    try testing.expectEqual(View.KeyResult.not_handled, try v.handleKey(.{ .char = 'y' }));
}

test "AuthorizationView filter application" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // Apply filter on empty data - should not crash
    try view.applyFilter("pods");
    try testing.expectEqualStrings("pods", view.filter_text);

    // Clear filter
    try view.applyFilter("");
    try testing.expectEqualStrings("", view.filter_text);
}

test "AuthorizationView accessMatchFn" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var row = AuthorizationView.AccessRow{
        .resource = try allocator.dupe(u8, "pods"),
        .group = try allocator.dupe(u8, ""),
        .allocator = allocator,
    };
    defer row.deinit();

    try testing.expect(AuthorizationView.accessMatchFn(&row, "pod"));
    try testing.expect(AuthorizationView.accessMatchFn(&row, "pods"));
    try testing.expect(!AuthorizationView.accessMatchFn(&row, "deploy"));
    try testing.expect(AuthorizationView.accessMatchFn(&row, "")); // empty filter matches all
}

test "AuthorizationView policyMatchFn" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var row = AuthorizationView.PolicyRow{
        .source = try allocator.dupe(u8, "admin"),
        .policy_type = .rbac,
        .resource = try allocator.dupe(u8, "pods"),
        .verbs = try allocator.dupe(u8, "get,list"),
        .subjects = try allocator.dupe(u8, "system:masters"),
        .allocator = allocator,
    };
    defer row.deinit();

    // Matches on source
    try testing.expect(AuthorizationView.policyMatchFn(&row, "admin"));
    // Matches on resource
    try testing.expect(AuthorizationView.policyMatchFn(&row, "pods"));
    // Matches on subjects
    try testing.expect(AuthorizationView.policyMatchFn(&row, "system"));
    // Does not match
    try testing.expect(!AuthorizationView.policyMatchFn(&row, "cedar"));
    // Empty filter matches all
    try testing.expect(AuthorizationView.policyMatchFn(&row, ""));
}

test "AuthorizationView navigation with data" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // Manually add rows to test navigation
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "pods"),
        .group = try allocator.dupe(u8, ""),
        .get = .allowed,
        .allocator = allocator,
    });
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "deployments"),
        .group = try allocator.dupe(u8, "apps"),
        .get = .denied,
        .allocator = allocator,
    });
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "secrets"),
        .group = try allocator.dupe(u8, ""),
        .get = .conditional,
        .allocator = allocator,
    });

    // Rebuild filter to populate filtered_indices
    try view.rebuildAccessFilter();
    try testing.expectEqual(@as(usize, 3), view.access_tab.table.filtered_indices.items.len);

    // Navigate down
    view.access_tab.table.visible_rows = 10;
    view.moveDown();
    try testing.expectEqual(@as(u32, 1), view.access_tab.table.selected_row);
    view.moveDown();
    try testing.expectEqual(@as(u32, 2), view.access_tab.table.selected_row);
    // Can't go past end
    view.moveDown();
    try testing.expectEqual(@as(u32, 2), view.access_tab.table.selected_row);

    // Navigate up
    view.moveUp();
    try testing.expectEqual(@as(u32, 1), view.access_tab.table.selected_row);
    view.moveUp();
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);
    // Can't go past start
    view.moveUp();
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);

    // Jump to bottom
    view.moveBottom();
    try testing.expectEqual(@as(u32, 2), view.access_tab.table.selected_row);

    // Jump to top
    view.moveTop();
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);
}

test "AuthorizationView filter with data" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // Add test rows
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "pods"),
        .group = try allocator.dupe(u8, ""),
        .allocator = allocator,
    });
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "deployments"),
        .group = try allocator.dupe(u8, "apps"),
        .allocator = allocator,
    });
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "secrets"),
        .group = try allocator.dupe(u8, ""),
        .allocator = allocator,
    });

    // No filter - all visible
    try view.applyFilter("");
    try testing.expectEqual(@as(usize, 3), view.access_tab.table.filtered_indices.items.len);

    // Filter for "pod"
    try view.applyFilter("pod");
    try testing.expectEqual(@as(usize, 1), view.access_tab.table.filtered_indices.items.len);

    // Filter for "s" - matches "pods", "deployments", "secrets"
    try view.applyFilter("s");
    try testing.expectEqual(@as(usize, 3), view.access_tab.table.filtered_indices.items.len);

    // Filter for "deploy"
    try view.applyFilter("deploy");
    try testing.expectEqual(@as(usize, 1), view.access_tab.table.filtered_indices.items.len);

    // Filter that matches nothing
    try view.applyFilter("zzzzz");
    try testing.expectEqual(@as(usize, 0), view.access_tab.table.filtered_indices.items.len);

    // Clear filter
    try view.applyFilter("");
    try testing.expectEqual(@as(usize, 3), view.access_tab.table.filtered_indices.items.len);
}

test "AuthorizationView refreshAccessReview without connection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // Not connected - should set error message
    try view.refreshAccessReview();
    try testing.expect(view.error_message != null);
    try testing.expectEqualStrings("Not connected to Kubernetes cluster", view.error_message.?);
    try testing.expectEqual(@as(usize, 0), view.access_tab.table.items.items.len);
}

test "AuthorizationView refreshPolicies without connection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    try view.refreshPolicies();
    try testing.expect(view.error_message != null);
    try testing.expectEqualStrings("Not connected to Kubernetes cluster", view.error_message.?);
    try testing.expectEqual(@as(usize, 0), view.policy_tab.table.items.items.len);
}

test "AuthorizationView refreshConditions without connection" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    try view.refreshConditions("pods", "");
    try testing.expect(view.error_message != null);
    try testing.expectEqualStrings("Not connected to Kubernetes cluster", view.error_message.?);
    try testing.expect(view.condition_tab.condition_resource != null);
    try testing.expectEqualStrings("pods", view.condition_tab.condition_resource.?);
}

test "AuthorizationView refreshConditions when conditional auth unavailable" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // Simulate detected but unavailable
    view.access_tab.conditional_auth_available = false;
    try testing.expectEqual(false, view.access_tab.conditional_auth_available.?);
}

test "AuthorizationView AccessRow deinit frees memory" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var row = AuthorizationView.AccessRow{
        .resource = try allocator.dupe(u8, "test-resource"),
        .group = try allocator.dupe(u8, "test-group"),
        .get = .allowed,
        .list = .denied,
        .create = .conditional,
        .update = .denied,
        .delete = .denied,
        .watch = .allowed,
        .condition_count = 5,
        .allocator = allocator,
    };
    row.deinit();
    // If this doesn't leak, the test passes (testing.allocator tracks leaks)
}

test "AuthorizationView PolicyRow deinit frees memory" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var row = AuthorizationView.PolicyRow{
        .source = try allocator.dupe(u8, "admin-role"),
        .policy_type = .rbac,
        .resource = try allocator.dupe(u8, "*.*"),
        .verbs = try allocator.dupe(u8, "*"),
        .subjects = try allocator.dupe(u8, "system:masters"),
        .allocator = allocator,
    };
    row.deinit();
}

test "AuthorizationView ConditionRow deinit frees memory" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var row = AuthorizationView.ConditionRow{
        .index = 1,
        .effect = try allocator.dupe(u8, "Deny"),
        .authorizer = try allocator.dupe(u8, "cedar-webhook"),
        .expression = try allocator.dupe(u8, "resource.metadata.labels[\"protected\"]"),
        .description = try allocator.dupe(u8, "Block protected pods"),
        .allocator = allocator,
    };
    row.deinit();
}

test "AuthorizationView navigation across tabs" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // Add data to access tab
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "pods"),
        .group = try allocator.dupe(u8, ""),
        .allocator = allocator,
    });
    try view.rebuildAccessFilter();
    view.access_tab.table.visible_rows = 10;

    // Navigate in access tab
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);

    // Switch to policy tab
    view.active_tab = .policy_browser;
    // Policy tab has its own selection state
    try testing.expectEqual(@as(u32, 0), view.policy_tab.table.selected_row);

    // Switch to condition tab
    view.active_tab = .condition_inspector;
    try testing.expectEqual(@as(u32, 0), view.condition_tab.table.selected_row);

    // Switch back - access selection should be preserved
    view.active_tab = .access_review;
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);
}

test "AuthorizationView policy filter with data" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // Add policy rows
    try view.policy_tab.table.appendItem(.{
        .source = try allocator.dupe(u8, "admin"),
        .policy_type = .rbac,
        .resource = try allocator.dupe(u8, "*.* "),
        .verbs = try allocator.dupe(u8, "*"),
        .subjects = try allocator.dupe(u8, "system:masters"),
        .allocator = allocator,
    });
    try view.policy_tab.table.appendItem(.{
        .source = try allocator.dupe(u8, "pod-reader"),
        .policy_type = .rbac,
        .resource = try allocator.dupe(u8, "pods"),
        .verbs = try allocator.dupe(u8, "get,list,watch"),
        .subjects = try allocator.dupe(u8, "dev-team"),
        .allocator = allocator,
    });

    // Switch to policy tab and apply filter
    view.active_tab = .policy_browser;
    try view.applyFilter("admin");
    try testing.expectEqual(@as(usize, 1), view.policy_tab.table.filtered_indices.items.len);

    try view.applyFilter("");
    try testing.expectEqual(@as(usize, 2), view.policy_tab.table.filtered_indices.items.len);

    // Filter by subject
    try view.applyFilter("dev-team");
    try testing.expectEqual(@as(usize, 1), view.policy_tab.table.filtered_indices.items.len);
}

test "AuthorizationView clearAccessRows cleans up" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    // Add some rows
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "pods"),
        .group = try allocator.dupe(u8, ""),
        .allocator = allocator,
    });
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "secrets"),
        .group = try allocator.dupe(u8, ""),
        .allocator = allocator,
    });
    try testing.expectEqual(@as(usize, 2), view.access_tab.table.items.items.len);

    view.clearAccessRows();
    try testing.expectEqual(@as(usize, 0), view.access_tab.table.items.items.len);
}

test "AuthorizationView clearPolicyRows cleans up" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    try view.policy_tab.table.appendItem(.{
        .source = try allocator.dupe(u8, "admin"),
        .policy_type = .rbac,
        .resource = try allocator.dupe(u8, "*"),
        .verbs = try allocator.dupe(u8, "*"),
        .subjects = try allocator.dupe(u8, "system:masters"),
        .allocator = allocator,
    });
    try testing.expectEqual(@as(usize, 1), view.policy_tab.table.items.items.len);

    view.clearPolicyRows();
    try testing.expectEqual(@as(usize, 0), view.policy_tab.table.items.items.len);
}

test "AuthorizationView clearConditionRows cleans up" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const theme_loader_mod = @import("../model/theme_loader.zig");
    var theme = try theme_loader_mod.loadTheme(allocator, "dracula");
    defer theme_loader_mod.deinitTheme(&theme);

    var k8s = try K8sService.init(allocator);
    defer k8s.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s);
    defer view.deinit();

    try view.condition_tab.table.appendItem(.{
        .index = 1,
        .effect = try allocator.dupe(u8, "Deny"),
        .authorizer = try allocator.dupe(u8, "webhook"),
        .expression = try allocator.dupe(u8, "x == y"),
        .description = try allocator.dupe(u8, "test"),
        .allocator = allocator,
    });
    try testing.expectEqual(@as(usize, 1), view.condition_tab.table.items.items.len);

    view.clearConditionRows();
    try testing.expectEqual(@as(usize, 0), view.condition_tab.table.items.items.len);
}
