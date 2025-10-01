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
const K8sService = @import("../services/k8s_service.zig").K8sService;
const Logger = @import("../core/logger.zig");

pub const HPAView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    items: std.ArrayListUnmanaged(HPAInfo),
    selected_row: usize,
    scroll_offset: usize,
    loading: bool,
    error_message: ?[]const u8,
    filter_text: []const u8,
    show_all_namespaces: bool,

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
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !HPAView {
        return HPAView{
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

    pub fn deinit(self: *HPAView) void {
        for (self.items.items) |*item| item.deinit(self.allocator);
        self.items.deinit(self.allocator);
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
                .age = try self.allocator.dupe(u8, "1d"),
            });
        }
        self.loading = false;
        if (self.selected_row >= self.items.items.len and self.items.items.len > 0) {
            self.selected_row = self.items.items.len - 1;
        }
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
        if (self.loading) {
            try Theme.writeStringWithTheme(terminal, x, y, "Loading HPAs...", self.theme.main_fg, self.theme.main_bg);
            return;
        }
        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(terminal, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }
        if (self.items.items.len == 0) {
            try Theme.writeStringWithTheme(terminal, x, y, "No HPAs found", self.theme.main_fg, self.theme.main_bg);
            return;
        }
        // Simple render for now
        var row: u16 = 0;
        const visible_rows = height -| 1;
        for (self.items.items, 0..) |item, i| {
            if (i < self.scroll_offset) continue;
            if (row >= visible_rows) break;
            const is_selected = (i == self.selected_row);
            const fg = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg = if (is_selected) self.theme.selected_bg else self.theme.main_bg;
            const line = try std.fmt.allocPrint(self.allocator, "{s}/{s} min:{d} max:{d} current:{d}", .{ item.namespace, item.name, item.min_replicas, item.max_replicas, item.current_replicas });
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(terminal, x, y + row, line, fg, bg);
            row += 1;
        }
    }

    fn handleKey(ctx: *anyopaque, key: Key) anyerror!KeyResult {
        const self: *HPAView = @ptrCast(@alignCast(ctx));
        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    if (self.selected_row < self.items.items.len -| 1) self.selected_row += 1;
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
                'q' => return .request_quit,
                ':' => return .request_command_palette,
                '/' => return .request_filter,
                else => return .not_handled,
            },
            .down => {
                if (self.selected_row < self.items.items.len -| 1) self.selected_row += 1;
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
        return hints_model.HintConfig{
            .hints = &[_]hints_model.Hint{
                hints_model.Hint.plain("j/k navigate", 1),
                hints_model.Hint.plain("0 toggle ns", 2),
                hints_model.Hint.plain("r refresh", 3),
            },
        };
    }

    fn deinitView(ctx: *anyopaque) void {
        const self: *HPAView = @ptrCast(@alignCast(ctx));
        self.deinit();
    }
};
