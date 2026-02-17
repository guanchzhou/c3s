/// StatefulSetsView - View for Kubernetes StatefulSets
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
const age_util = @import("../viewmodel/age.zig");

pub const StatefulSetsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,

    // State
    items: std.ArrayListUnmanaged(StatefulSetInfo),
    filtered_indices: std.ArrayListUnmanaged(usize),
    selected_row: u32,
    scroll_offset: u32,
    visible_rows: u32,
    loading: bool,
    error_message: ?[]const u8,

    // Filtering
    filter_text: []const u8,
    show_all_namespaces: bool,
    sort_column: ?u8 = null,
    sort_ascending: bool = true,

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const StatefulSetInfo = struct {
        name: []const u8,
        namespace: []const u8,
        ready: i32,
        desired: i32,
        age: []const u8,

        pub fn deinit(self: *StatefulSetInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.namespace);
            allocator.free(self.age);
        }

        fn getName(self: *const StatefulSetInfo) []const u8 { return self.name; }
        fn getAge(self: *const StatefulSetInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !StatefulSetsView {
        var view = StatefulSetsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = std.ArrayListUnmanaged(StatefulSetInfo){},
            .filtered_indices = std.ArrayListUnmanaged(usize){},
            .selected_row = 0,
            .scroll_offset = 0,
            .visible_rows = 0,
            .loading = false,
            .error_message = null,
            .filter_text = "",
            .show_all_namespaces = false,
        };

        // Load initial data
        try view.refresh();

        return view;
    }

    pub fn deinit(self: *StatefulSetsView) void {
        self.cleanup();
    }

    fn cleanup(self: *StatefulSetsView) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    pub fn refresh(self: *StatefulSetsView) !void {
        self.loading = true;
        defer self.loading = false;

        // Clear old error if any
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        // Clear old items
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.clearRetainingCapacity();

        // Fetch statefulsets from API
        const statefulsets = if (self.show_all_namespaces)
            self.k8s_service.listAllStatefulSets() catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list statefulsets: {}", .{err});
                Logger.err("Failed to list all statefulsets: {}", .{err});
                return;
            }
        else
            self.k8s_service.listStatefulSets(null) catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list statefulsets: {}", .{err});
                Logger.err("Failed to list statefulsets: {}", .{err});
                return;
            };
        defer self.allocator.free(statefulsets);

        // Convert to display format
        for (statefulsets) |sts| {
            const name = try self.allocator.dupe(u8, sts.metadata.name);
            const namespace = try self.allocator.dupe(u8, sts.metadata.namespace orelse "default");

            // Extract readyReplicas from JSON Value
            const ready: i32 = if (sts.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("readyReplicas")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            const desired = if (sts.spec) |s| s.replicas orelse 0 else 0;

            const age = try age_util.calculateAge(self.allocator, sts.metadata.creationTimestamp);

            try self.items.append(self.allocator, StatefulSetInfo{
                .name = name,
                .namespace = namespace,
                .ready = ready,
                .desired = desired,
                .age = age,
            });
        }

        Logger.info("Loaded {} statefulsets", .{self.items.items.len});

        // Rebuild filtered indices
        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *StatefulSetsView) ?ResourceInfo {
        if (self.filtered_indices.items.len == 0) return null;
        if (self.selected_row >= self.filtered_indices.items.len) return null;
        const idx = self.filtered_indices.items[self.selected_row];
        const item = self.items.items[idx];
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *StatefulSetsView, filter: []const u8) !void {
        self.filter_text = filter;
        try universal_filter.applyFilter(
            StatefulSetInfo,
            self.allocator,
            self.items.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            statefulsetMatchFn,
        );
        self.applySorting();
    }

    fn applySorting(self: *StatefulSetsView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(StatefulSetInfo, self.items.items, &self.filtered_indices, StatefulSetInfo.getName, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(StatefulSetInfo, self.items.items, &self.filtered_indices, StatefulSetInfo.getAge, self.sort_ascending),
                else => {},
            }
        }
    }

    fn statefulsetMatchFn(item: *const StatefulSetInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }


    pub fn createView(self: *StatefulSetsView) View {
        return View.create(StatefulSetsView, self, &vtable);
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));

        if (self.loading) {
            const title = "Loading statefulsets...";
            try Theme.writeStringWithTheme(term, x, y, title, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }

        if (self.items.items.len == 0) {
            const msg = if (self.show_all_namespaces)
                "No statefulsets found in cluster"
            else
                "No statefulsets in current namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        // Render header with sort indicators
        const name_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_AGE);
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             NAME{s: <30}READY      AGE{s}", .{ name_ind, age_ind }) catch "  NAMESPACE             NAME                          READY      AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        // Render statefulsets
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

            // Format: "  namespace   name   ready/desired   age"
            const line = try std.fmt.allocPrint(
                self.allocator,
                "  {s: <20} {s: <28} {d}/{d: <6} {s}",
                .{
                    if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                    if (item.name.len > 28) item.name[0..28] else item.name,
                    item.ready,
                    item.desired,
                    item.age,
                },
            );
            defer self.allocator.free(line);

            try Theme.writeStringWithTheme(term, x, y + 1 + row, line, fg_color, bg_color);
        }

        // Clear remaining lines
        while (row < self.visible_rows) : (row += 1) {
            const blank_line = "                                                                                ";
            try Theme.writeStringWithTheme(term, x, y + 1 + row, blank_line[0..@min(blank_line.len, width)], self.theme.main_fg, self.theme.main_bg);
            row += 1;
        }
        row = row; // Suppress unused warning
        if (false) {
            var col: u16 = 0;
            while (col < width) : (col += 1) {
                try term.writeString(" ");
            }
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));

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
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));
        Logger.info("StatefulSetsView shown", .{});
        self.refresh() catch |err| {
            Logger.err("Failed to refresh StatefulSets on show: {}", .{err});
        };
    }

    fn onHide(ptr: *anyopaque) void {
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));
        Logger.info("StatefulSetsView hidden", .{});
        _ = self;
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "statefulsets";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *StatefulSetsView = @ptrCast(@alignCast(ptr));
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
