/// ReplicaSetsView - View for Kubernetes ReplicaSets
const std = @import("std");
const klient = @import("klient");
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = @import("../theme.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const ResourceInfo = k8s_service_mod.ResourceInfo;
const Logger = @import("../core/logger.zig");
const universal_filter = @import("../viewmodel/filter.zig");
const sort_util = @import("../viewmodel/sort.zig");

pub const ReplicaSetsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    items: std.ArrayListUnmanaged(ReplicaSetInfo),
    filtered_indices: std.ArrayListUnmanaged(usize),
    selected_row: u32,
    scroll_offset: u32,
    visible_rows: u32,
    loading: bool,
    error_message: ?[]const u8,
    filter_text: []const u8,
    show_all_namespaces: bool,
    sort_column: ?u8 = null,
    sort_ascending: bool = true,

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const ReplicaSetInfo = struct {
        name: []const u8,
        namespace: []const u8,
        desired: i32,
        current: i32,
        ready: i32,
        age: []const u8,

        pub fn deinit(self: *ReplicaSetInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.namespace);
            allocator.free(self.age);
        }

        fn getName(self: *const ReplicaSetInfo) []const u8 { return self.name; }
        fn getAge(self: *const ReplicaSetInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !ReplicaSetsView {
        var view = ReplicaSetsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = std.ArrayListUnmanaged(ReplicaSetInfo){},
            .filtered_indices = std.ArrayListUnmanaged(usize){},
            .selected_row = 0,
            .scroll_offset = 0,
            .visible_rows = 0,
            .loading = false,
            .error_message = null,
            .filter_text = "",
            .show_all_namespaces = false,
        };
        try view.refresh();
        return view;
    }

    pub fn deinit(self: *ReplicaSetsView) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    pub fn refresh(self: *ReplicaSetsView) !void {
        self.loading = true;
        defer self.loading = false;

        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.clearRetainingCapacity();

        const replicasets = if (self.show_all_namespaces)
            self.k8s_service.listAllReplicaSets() catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list replicasets: {}", .{err});
                return;
            }
        else
            self.k8s_service.listReplicaSets(null) catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list replicasets: {}", .{err});
                return;
            };
        defer self.allocator.free(replicasets);

        for (replicasets) |rs| {
            const name = try self.allocator.dupe(u8, rs.metadata.name);
            const namespace = try self.allocator.dupe(u8, rs.metadata.namespace orelse "default");

            const desired = if (rs.spec) |s| s.replicas orelse 0 else 0;

            // Extract status fields from JSON Value
            const current: i32 = if (rs.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("replicas")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            const ready: i32 = if (rs.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("readyReplicas")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            const age = try self.allocator.dupe(u8, "1d");

            try self.items.append(self.allocator, ReplicaSetInfo{
                .name = name,
                .namespace = namespace,
                .desired = desired,
                .current = current,
                .ready = ready,
                .age = age,
            });
        }

        // Rebuild filtered indices
        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *ReplicaSetsView) ?ResourceInfo {
        if (self.filtered_indices.items.len == 0) return null;
        if (self.selected_row >= self.filtered_indices.items.len) return null;
        const idx = self.filtered_indices.items[self.selected_row];
        const item = self.items.items[idx];
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *ReplicaSetsView, filter: []const u8) !void {
        self.filter_text = filter;
        try universal_filter.applyFilter(
            ReplicaSetInfo,
            self.allocator,
            self.items.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            replicasetMatchFn,
        );
        self.applySorting();
    }

    fn applySorting(self: *ReplicaSetsView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(ReplicaSetInfo, self.items.items, &self.filtered_indices, ReplicaSetInfo.getName, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(ReplicaSetInfo, self.items.items, &self.filtered_indices, ReplicaSetInfo.getAge, self.sort_ascending),
                else => {},
            }
        }
    }

    fn replicasetMatchFn(item: *const ReplicaSetInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *ReplicaSetsView) View {
        return View.create(ReplicaSetsView, self, &vtable);
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
        _ = width;

        if (self.loading) {
            try Theme.writeStringWithTheme(term, x, y, "Loading replicasets...", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }

        if (self.items.items.len == 0) {
            const msg = if (self.show_all_namespaces) "No replicasets found in cluster" else "No replicasets in current namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        // Header with sort indicators
        const name_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_AGE);
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             NAME{s: <28}DESIRED CURRENT READY AGE{s}", .{ name_ind, age_ind }) catch "  NAMESPACE             NAME                          DESIRED CURRENT READY AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        // Items
        self.visible_rows = if (height > 1) height - 1 else 0;
        var row: u16 = 0;
        var idx: u32 = self.scroll_offset;

        while (row < self.visible_rows and idx < self.filtered_indices.items.len) : ({
            row += 1;
            idx += 1;
        }) {
            const actual_idx = self.filtered_indices.items[idx];
            const item = &self.items.items[actual_idx];
            const is_selected = (idx == self.selected_row);

            const fg_color = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg_color = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            const line = try std.fmt.allocPrint(
                self.allocator,
                "  {s: <20} {s: <28} {d: >7} {d: >7} {d: >5} {s}",
                .{
                    if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                    if (item.name.len > 28) item.name[0..28] else item.name,
                    item.desired,
                    item.current,
                    item.ready,
                    item.age,
                },
            );
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, y + 1 + row, line, fg_color, bg_color);
        }

        // Clear remaining lines (optional - terminal typically handles this)
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
        switch (key) {
            .char => |c| switch (c) {
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
                    try self.refresh();
                    return .handled;
                },
                '0' => {
                    self.show_all_namespaces = !self.show_all_namespaces;
                    try self.refresh();
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
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
        Logger.info("ReplicaSetsView shown", .{});
        self.refresh() catch |err| {
            Logger.err("Failed to refresh ReplicaSets on show: {}", .{err});
        };
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "replicasets";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *ReplicaSetsView = @ptrCast(@alignCast(ptr));
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
