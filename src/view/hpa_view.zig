/// HPAView - View for HorizontalPodAutoscalers
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

pub const HPAView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    items: std.ArrayListUnmanaged(HPAInfo),
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

    const HPAInfo = struct {
        namespace: []const u8,
        name: []const u8,
        min_replicas: i32,
        max_replicas: i32,
        current_replicas: i32,
        age: []const u8,
        pub fn deinit(self: *HPAInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.namespace);
            allocator.free(self.name);
            allocator.free(self.age);
        }
        fn getName(self: *const HPAInfo) []const u8 { return self.name; }
        fn getAge(self: *const HPAInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !HPAView {
        return HPAView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = .{},
            .filtered_indices = .{},
            .selected_row = 0,
            .scroll_offset = 0,
            .visible_rows = 0,
            .loading = false,
            .error_message = null,
            .filter_text = "",
            .show_all_namespaces = true,
        };
    }

    pub fn deinit(self: *HPAView) void {
        for (self.items.items) |*item| item.deinit(self.allocator);
        self.items.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        if (self.error_message) |msg| self.allocator.free(msg);
    }

    pub fn refresh(self: *HPAView) !void {
        self.loading = true;
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }
        for (self.items.items) |*item| item.deinit(self.allocator);
        self.items.clearRetainingCapacity();
        if (!self.k8s_service.isConnected()) {
            self.error_message = try self.allocator.dupe(u8, "Not connected");
            return;
        }
        const hpas = if (self.show_all_namespaces)
            self.k8s_service.listAllHPAs() catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed: {}", .{err});
                return;
            }
        else
            self.k8s_service.listHPAs(null) catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed: {}", .{err});
                return;
            };
        defer self.allocator.free(hpas);
        for (hpas) |hpa| {
            const current = blk: {
                if (hpa.status) |status_val| {
                    if (status_val == .object) {
                        const status_obj = status_val.object;
                        if (status_obj.get("currentReplicas")) |val| {
                            if (val == .integer) {
                                break :blk @as(i32, @intCast(val.integer));
                            }
                        }
                    }
                }
                break :blk @as(i32, 0);
            };
            const min = if (hpa.spec) |spec| if (spec.minReplicas) |m| m else 1 else 1;
            const max = if (hpa.spec) |spec| spec.maxReplicas else 1;
            try self.items.append(self.allocator, HPAInfo{
                .namespace = try self.allocator.dupe(u8, hpa.metadata.namespace orelse "default"),
                .name = try self.allocator.dupe(u8, hpa.metadata.name),
                .min_replicas = min,
                .max_replicas = max,
                .current_replicas = current,
                .age = try age_util.calculateAge(self.allocator, hpa.metadata.creationTimestamp),
            });
        }
        self.loading = false;
        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *HPAView) ?ResourceInfo {
        if (self.items.items.len == 0) return null;
        const idx = if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len)
            self.filtered_indices.items[self.selected_row]
        else if (self.selected_row < self.items.items.len)
            self.selected_row
        else
            return null;
        const item = self.items.items[idx];
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *HPAView, filter: []const u8) !void {
        self.filter_text = filter;
        try universal_filter.applyFilter(
            HPAInfo,
            self.allocator,
            self.items.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            hpaMatchFn,
        );
        self.applySorting();
    }

    fn applySorting(self: *HPAView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(HPAInfo, self.items.items, &self.filtered_indices, HPAInfo.getName, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(HPAInfo, self.items.items, &self.filtered_indices, HPAInfo.getAge, self.sort_ascending),
                else => {},
            }
        }
    }

    fn hpaMatchFn(item: *const HPAInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *HPAView) View {
        return View.create(HPAView, self, &vtable);
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

    fn render(ctx: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) anyerror!void {
        const self: *HPAView = @ptrCast(@alignCast(ctx));
        _ = width;
        self.visible_rows = if (height > 1) height - 1 else 0;
        if (self.loading) {
            try Theme.writeStringWithTheme(terminal, x, y, "Loading HPAs...", self.theme.main_fg, self.theme.main_bg);
            return;
        }
        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(terminal, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }
        if (self.filtered_indices.items.len == 0) {
            try Theme.writeStringWithTheme(terminal, x, y, "No HPAs found", self.theme.main_fg, self.theme.main_bg);
            return;
        }
        // Render header row with sort indicators
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        const name_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_AGE);
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "NAMESPACE/{s}  MIN  MAX  CURRENT  {s}", .{ name_hdr, age_hdr }) catch "NAMESPACE/NAME  MIN  MAX  CURRENT  AGE";
        try Theme.writeStringWithTheme(terminal, x, y, header, self.theme.title, self.theme.main_bg);
        // Render rows using filtered_indices
        var row: u32 = 0;
        const visible = self.visible_rows;
        var fi: u32 = self.scroll_offset;
        while (row < visible and fi < self.filtered_indices.items.len) : ({ row += 1; fi += 1; }) {
            const idx = self.filtered_indices.items[fi];
            const item = self.items.items[idx];
            const is_selected = (fi == self.selected_row);
            const fg = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (is_selected) self.theme.selected_bg else self.theme.main_bg;
            const line = try std.fmt.allocPrint(self.allocator, "{s}/{s} min:{d} max:{d} current:{d}", .{ item.namespace, item.name, item.min_replicas, item.max_replicas, item.current_replicas });
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(terminal, x, y + 1 + @as(u16, @intCast(row)), line, fg, bg);
        }
    }

    fn handleKey(ctx: *anyopaque, key: Key) anyerror!KeyResult {
        const self: *HPAView = @ptrCast(@alignCast(ctx));
        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    if (self.selected_row < self.filtered_indices.items.len -| 1) self.selected_row += 1;
                    return .handled;
                },
                'k' => {
                    if (self.selected_row > 0) self.selected_row -= 1;
                    return .handled;
                },
                '0' => {
                    self.show_all_namespaces = !self.show_all_namespaces;
                    try self.refresh();
                    return .handled;
                },
                'r' => {
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
                '/' => return .request_filter,
                'q' => return .request_quit,
                ':' => return .request_command_palette,
                else => return .not_handled,
            },
            .down => {
                if (self.selected_row < self.filtered_indices.items.len -| 1) self.selected_row += 1;
                return .handled;
            },
            .up => {
                if (self.selected_row > 0) self.selected_row -= 1;
                return .handled;
            },
            else => return .not_handled,
        }
    }

    fn onShow(ctx: *anyopaque) void {
        const self: *HPAView = @ptrCast(@alignCast(ctx));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh HPAs: {}", .{err});
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "HorizontalPodAutoscalers";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ctx: *anyopaque) void {
        const self: *HPAView = @ptrCast(@alignCast(ctx));
        self.deinit();
    }
};
