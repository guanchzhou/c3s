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
const K8sService = @import("../services/k8s_service.zig").K8sService;
const Logger = @import("../core/logger.zig");

pub const StatefulSetsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,

    // State
    items: std.ArrayListUnmanaged(StatefulSetInfo),
    selected_row: usize,
    scroll_offset: usize,
    loading: bool,
    error_message: ?[]const u8,

    // Filtering
    filter_text: []const u8,
    show_all_namespaces: bool,

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
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !StatefulSetsView {
        var view = StatefulSetsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = std.ArrayListUnmanaged(StatefulSetInfo){},
            .selected_row = 0,
            .scroll_offset = 0,
            .loading = false,
            .error_message = null,
            .filter_text = try allocator.dupe(u8, ""),
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
        self.allocator.free(self.filter_text);
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

            const age = try self.calculateAge(sts.metadata.creationTimestamp orelse "");

            try self.items.append(self.allocator, StatefulSetInfo{
                .name = name,
                .namespace = namespace,
                .ready = ready,
                .desired = desired,
                .age = age,
            });
        }

        // Reset selection if out of bounds
        if (self.items.items.len == 0) {
            self.selected_row = 0;
        } else if (self.selected_row >= self.items.items.len) {
            self.selected_row = self.items.items.len - 1;
        }

        Logger.info("Loaded {} statefulsets", .{self.items.items.len});
    }

    fn calculateAge(self: *StatefulSetsView, timestamp: []const u8) ![]const u8 {
        _ = timestamp;
        // TODO: Implement proper age calculation from timestamp
        return try self.allocator.dupe(u8, "1d");
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

        // Render header
        const header = "  NAMESPACE             NAME                          READY      AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        // Render statefulsets
        const visible_rows = if (height > 1) height - 1 else 0;
        var row: u16 = 0;
        var idx = self.scroll_offset;

        while (row < visible_rows and idx < self.items.items.len) : ({
            row += 1;
            idx += 1;
        }) {
            const item = &self.items.items[idx];
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
        while (row < visible_rows) : (row += 1) {
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
                    if (self.items.items.len > 0 and self.selected_row < self.items.items.len - 1) {
                        self.selected_row += 1;
                        // Auto-scroll
                        const visible_rows = 20; // TODO: Get from height
                        if (self.selected_row >= self.scroll_offset + visible_rows) {
                            self.scroll_offset = self.selected_row - visible_rows + 1;
                        }
                    }
                    return .handled;
                },
                'k' => {
                    if (self.selected_row > 0) {
                        self.selected_row -= 1;
                        // Auto-scroll
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
                    if (self.items.items.len > 0) {
                        self.selected_row = self.items.items.len - 1;
                        const visible_rows = 20;
                        if (self.items.items.len > visible_rows) {
                            self.scroll_offset = self.items.items.len - visible_rows;
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
                else => return .not_handled,
            },
            .down => {
                if (self.items.items.len > 0 and self.selected_row < self.items.items.len - 1) {
                    self.selected_row += 1;
                    const visible_rows = 20;
                    if (self.selected_row >= self.scroll_offset + visible_rows) {
                        self.scroll_offset = self.selected_row - visible_rows + 1;
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
                const page_size: usize = 20;
                if (self.items.items.len > 0) {
                    self.selected_row = @min(self.selected_row + page_size, self.items.items.len - 1);
                    const visible_rows = 20;
                    if (self.selected_row >= self.scroll_offset + visible_rows) {
                        self.scroll_offset = self.selected_row - visible_rows + 1;
                    }
                }
                return .handled;
            },
            .page_up => {
                const page_size: usize = 20;
                if (self.selected_row >= page_size) {
                    self.selected_row -= page_size;
                } else {
                    self.selected_row = 0;
                }
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
                if (self.items.items.len > 0) {
                    self.selected_row = self.items.items.len - 1;
                    const visible_rows = 20;
                    if (self.items.items.len > visible_rows) {
                        self.scroll_offset = self.items.items.len - visible_rows;
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
        const hint_items = comptime [_]hints_model.Hint{
            hints_model.Hint.plain("↑↓ Navigate", 1),
            hints_model.Hint.plain("r Refresh", 2),
            hints_model.Hint.plain("0 All Namespaces", 3),
            hints_model.Hint.plain("? Help", 4),
        };
        return hints_model.HintConfig{
            .hints = &hint_items,
        };
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
