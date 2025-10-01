/// NetworkPoliciesView - View for Kubernetes NetworkPolicies
const std = @import("std");
const klient = @import("klient");
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = @import("../theme.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const K8sService = @import("../services/k8s_service.zig").K8sService;
const Logger = @import("../core/logger.zig");

pub const NetworkPoliciesView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,

    items: std.ArrayListUnmanaged(NetworkPolicyInfo),
    selected_row: usize,
    scroll_offset: usize,
    loading: bool,
    error_message: ?[]const u8,
    filter_text: []const u8,
    show_all_namespaces: bool,

    const NetworkPolicyInfo = struct {
        name: []const u8,
        namespace: []const u8,
        pod_selector: []const u8,
        age: []const u8,

        pub fn deinit(self: *NetworkPolicyInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.namespace);
            allocator.free(self.pod_selector);
            allocator.free(self.age);
        }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !NetworkPoliciesView {
        return NetworkPoliciesView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = .{},
            .selected_row = 0,
            .scroll_offset = 0,
            .loading = false,
            .error_message = null,
            .filter_text = "",
            .show_all_namespaces = true,
        };
    }

    pub fn deinit(self: *NetworkPoliciesView) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    pub fn refresh(self: *NetworkPoliciesView) !void {
        self.loading = true;
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.clearRetainingCapacity();

        if (!self.k8s_service.isConnected()) {
            self.error_message = try self.allocator.dupe(u8, "Not connected to Kubernetes cluster");
            return;
        }

        const policies = if (self.show_all_namespaces)
            self.k8s_service.listAllNetworkPolicies() catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list network policies: {}", .{err});
                return;
            }
        else
            self.k8s_service.listNetworkPolicies(null) catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list network policies: {}", .{err});
                return;
            };
        defer self.allocator.free(policies);

        for (policies) |np| {
            const name = try self.allocator.dupe(u8, np.metadata.name);
            const namespace = try self.allocator.dupe(u8, np.metadata.namespace orelse "default");
            const pod_selector = try self.allocator.dupe(u8, "<all>");
            const age = try self.allocator.dupe(u8, "1d");

            try self.items.append(self.allocator, NetworkPolicyInfo{
                .name = name,
                .namespace = namespace,
                .pod_selector = pod_selector,
                .age = age,
            });
        }

        self.loading = false;
        if (self.items.items.len == 0) {
            self.selected_row = 0;
        } else if (self.selected_row >= self.items.items.len) {
            self.selected_row = self.items.items.len - 1;
        }
    }

    pub fn createView(self: *NetworkPoliciesView) View {
        return View.create(NetworkPoliciesView, self, &vtable);
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *NetworkPoliciesView = @ptrCast(@alignCast(ptr));
        _ = width;

        if (self.loading) {
            try Theme.writeStringWithTheme(term, x, y, "Loading network policies...", self.theme.main_fg, self.theme.main_bg);
            return;
        }
        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }
        if (self.items.items.len == 0) {
            const msg = if (self.show_all_namespaces) "No network policies found in cluster" else "No network policies in current namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        const header = "  NAMESPACE             NAME                          POD-SELECTOR       AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        const visible_rows = if (height > 1) height - 1 else 0;
        var row: u16 = 0;
        var idx = self.scroll_offset;

        while (row < visible_rows and idx < self.items.items.len) : ({ row += 1; idx += 1; }) {
            const item = &self.items.items[idx];
            const is_selected = (idx == self.selected_row);
            const fg_color = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg_color = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            const line = try std.fmt.allocPrint(
                self.allocator,
                "  {s: <20} {s: <28} {s: <18} {s}",
                .{
                    if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                    if (item.name.len > 28) item.name[0..28] else item.name,
                    if (item.pod_selector.len > 18) item.pod_selector[0..18] else item.pod_selector,
                    item.age,
                },
            );
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, y + 1 + row, line, fg_color, bg_color);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *NetworkPoliciesView = @ptrCast(@alignCast(ptr));
        switch (key) {
            .down => {
                if (self.selected_row < self.items.items.len -| 1) {
                    self.selected_row += 1;
                }
                return .handled;
            },
            .up => {
                if (self.selected_row > 0) {
                    self.selected_row -= 1;
                }
                return .handled;
            },
            .char => |c| switch (c) {
                'j' => {
                    if (self.selected_row < self.items.items.len -| 1) {
                        self.selected_row += 1;
                    }
                    return .handled;
                },
                'k' => {
                    if (self.selected_row > 0) self.selected_row -= 1;
                    return .handled;
                },
                'r' => {
                    try self.refresh();
                    return .handled;
                },
                '0' => {
                    self.show_all_namespaces = !self.show_all_namespaces;
                    try self.refresh();
                    return .handled;
                },
                else => {},
            },
            else => {},
        }
        return .not_handled;
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *NetworkPoliciesView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh NetworkPolicies: {}", .{err});
        };
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "networkpolicies";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        const hint_items = comptime [_]hints_model.Hint{
            hints_model.Hint.plain("↑↓ Navigate", 1),
            hints_model.Hint.plain("r Refresh", 2),
            hints_model.Hint.plain("0 All Namespaces", 3),
        };
        return hints_model.HintConfig{ .hints = &hint_items };
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *NetworkPoliciesView = @ptrCast(@alignCast(ptr));
        self.deinit();
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
};
