/// Nodes View - Display and monitor Kubernetes cluster nodes
const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const View = @import("../viewmodel/view.zig").View;
const Key = @import("../core/terminal.zig").Key;
const KeyResult = View.KeyResult;
const Logger = @import("../core/logger.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const view_mod = @import("../viewmodel/view.zig");
const ResourceInfo = view_mod.ResourceInfo;
const klient = @import("klient");
const hints_model = @import("../model/hints.zig");
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");
const TableState = @import("../ui/table_state.zig").TableState;

pub const NodesView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(NodeInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;
    const COL_STATUS: u8 = 2;

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

        fn getName(self: *const NodeInfo) []const u8 { return self.name; }
        fn getAge(self: *const NodeInfo) []const u8 { return self.age; }
        fn getStatus(self: *const NodeInfo) []const u8 { return self.status; }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) !NodesView {
        return NodesView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(NodeInfo).init(allocator),
        };
    }

    pub fn deinit(self: *NodesView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *NodesView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        const k8s_nodes = self.k8s_service.listNodes() catch |err| {
            try self.table.setErrorFmt("Failed to list nodes: {}", .{err});
            return;
        };

        for (k8s_nodes) |node| {
            // Determine node status from conditions array
            const status = blk: {
                if (node.status) |status_json| {
                    if (status_json == .object) {
                        if (status_json.object.get("conditions")) |conditions| {
                            if (conditions == .array) {
                                for (conditions.array.items) |condition| {
                                    if (condition == .object) {
                                        const cond_type = if (condition.object.get("type")) |t|
                                            (if (t == .string) t.string else null)
                                        else
                                            null;
                                        if (cond_type) |ct| {
                                            if (std.mem.eql(u8, ct, "Ready")) {
                                                const cond_status = if (condition.object.get("status")) |s|
                                                    (if (s == .string) s.string else null)
                                                else
                                                    null;
                                                if (cond_status) |cs| {
                                                    if (std.mem.eql(u8, cs, "True")) {
                                                        break :blk try self.table.allocator.dupe(u8, "Ready");
                                                    } else {
                                                        break :blk try self.table.allocator.dupe(u8, "NotReady");
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                break :blk try self.table.allocator.dupe(u8, "Unknown");
            };

            // Get node roles from labels
            const roles = blk: {
                if (node.metadata.labels) |labels_json| {
                    if (labels_json == .object) {
                        const role_prefix = "node-role.kubernetes.io/";
                        var roles_buf: [256]u8 = undefined;
                        var roles_len: usize = 0;
                        var it = labels_json.object.iterator();
                        while (it.next()) |entry| {
                            const key_str = entry.key_ptr.*;
                            if (std.mem.startsWith(u8, key_str, role_prefix)) {
                                const role_name = key_str[role_prefix.len..];
                                if (role_name.len > 0) {
                                    if (roles_len > 0) {
                                        if (roles_len + 1 < roles_buf.len) {
                                            roles_buf[roles_len] = ',';
                                            roles_len += 1;
                                        }
                                    }
                                    const copy_len = @min(role_name.len, roles_buf.len - roles_len);
                                    @memcpy(roles_buf[roles_len..][0..copy_len], role_name[0..copy_len]);
                                    roles_len += copy_len;
                                }
                            }
                        }
                        if (roles_len > 0) {
                            break :blk try self.table.allocator.dupe(u8, roles_buf[0..roles_len]);
                        }
                    }
                }
                break :blk try self.table.allocator.dupe(u8, "<none>");
            };

            // Extract internal IP from status.addresses array
            const internal_ip = blk: {
                if (node.status) |status_json| {
                    if (status_json == .object) {
                        if (status_json.object.get("addresses")) |addresses| {
                            if (addresses == .array) {
                                for (addresses.array.items) |addr| {
                                    if (addr == .object) {
                                        const addr_type = if (addr.object.get("type")) |t|
                                            (if (t == .string) t.string else null)
                                        else
                                            null;
                                        if (addr_type) |at| {
                                            if (std.mem.eql(u8, at, "InternalIP")) {
                                                if (addr.object.get("address")) |a| {
                                                    if (a == .string) {
                                                        break :blk try self.table.allocator.dupe(u8, a.string);
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                break :blk try self.table.allocator.dupe(u8, "<unknown>");
            };

            // Extract version from status.nodeInfo.kubeletVersion
            const version = blk: {
                if (node.status) |status_json| {
                    if (status_json == .object) {
                        if (status_json.object.get("nodeInfo")) |node_info| {
                            if (node_info == .object) {
                                if (node_info.object.get("kubeletVersion")) |v| {
                                    if (v == .string) {
                                        break :blk try self.table.allocator.dupe(u8, v.string);
                                    }
                                }
                            }
                        }
                    }
                }
                break :blk try self.table.allocator.dupe(u8, "unknown");
            };

            try self.table.appendItem(.{
                .name = try self.table.allocator.dupe(u8, node.metadata.name),
                .status = status,
                .roles = roles,
                .age = try age_util.calculateAge(self.table.allocator, node.metadata.creationTimestamp),
                .version = version,
                .internal_ip = internal_ip,
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *NodesView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{ .name = item.name, .namespace = "cluster" };
    }

    pub fn applyFilter(self: *NodesView, filter: []const u8) !void {
        try self.table.applyFilter(filter, nodeMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *NodesView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(NodeInfo.getName),
                COL_AGE => self.table.sortBy(NodeInfo.getAge),
                COL_STATUS => self.table.sortBy(NodeInfo.getStatus),
                else => {},
            }
        }
    }

    fn nodeMatchFn(item: *const NodeInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null;
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
        .applyFilter = vtableApplyFilter,
        .clearFilter = vtableClearFilter,
        .refresh = vtableRefresh,
        .getSelectedResource = vtableGetSelectedResource,
    };

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *NodesView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *NodesView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *NodesView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *NodesView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, _: u16, height: u16) !void {
        const self: *NodesView = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(terminal, x, y, self.theme)) return;

        // Header row with sort indicators
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        const status_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_STATUS);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        var status_hdr_buf: [32]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        const status_hdr = std.fmt.bufPrint(&status_hdr_buf, "STATUS{s}", .{status_ind}) catch "STATUS";
        try Theme.writeStringWithTheme(terminal, x, y, name_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 27, y, status_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 39, y, "ROLES", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 55, y, "VERSION", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 71, y, "INTERNAL-IP", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 91, y, age_hdr, self.theme.title, self.theme.main_bg);

        // Data rows
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |node_idx, i| {
            const node = self.table.items.items[node_idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            try Theme.writeStringWithTheme(terminal, x, row_y, node.name[0..@min(26, node.name.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 27, row_y, node.status, colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 39, row_y, node.roles[0..@min(14, node.roles.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 55, row_y, node.version[0..@min(14, node.version.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 71, row_y, node.internal_ip, colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 91, row_y, node.age, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *NodesView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh nodes: {}", .{err});
                    return .handled;
                },
                'N' => { self.table.toggleSort(COL_NAME); self.applySorting(); return .handled; },
                'A' => { self.table.toggleSort(COL_AGE); self.applySorting(); return .handled; },
                'S' => { self.table.toggleSort(COL_STATUS); self.applySorting(); return .handled; },
                else => return .not_handled,
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *NodesView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh nodes: {any}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {};
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "nodes";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *NodesView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
