/// CronJobsView - View for Kubernetes CronJobs
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

pub const CronJobsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    items: std.ArrayListUnmanaged(CronJobInfo),
    selected_row: usize,
    scroll_offset: usize,
    loading: bool,
    error_message: ?[]const u8,
    filter_text: []const u8,
    show_all_namespaces: bool,

    const CronJobInfo = struct {
        name: []const u8,
        namespace: []const u8,
        schedule: []const u8,
        suspended: bool,
        active: i32,
        last_schedule: []const u8,

        pub fn deinit(self: *CronJobInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.namespace);
            allocator.free(self.schedule);
            allocator.free(self.last_schedule);
        }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !CronJobsView {
        var view = CronJobsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = std.ArrayListUnmanaged(CronJobInfo){},
            .selected_row = 0,
            .scroll_offset = 0,
            .loading = false,
            .error_message = null,
            .filter_text = try allocator.dupe(u8, ""),
            .show_all_namespaces = false,
        };
        try view.refresh();
        return view;
    }

    pub fn deinit(self: *CronJobsView) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
        self.allocator.free(self.filter_text);
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    pub fn refresh(self: *CronJobsView) !void {
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

        const cronjobs = if (self.show_all_namespaces)
            self.k8s_service.listAllCronJobs() catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list cronjobs: {}", .{err});
                return;
            }
        else
            self.k8s_service.listCronJobs(null) catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list cronjobs: {}", .{err});
                return;
            };
        defer self.allocator.free(cronjobs);

        for (cronjobs) |cj| {
            const name = try self.allocator.dupe(u8, cj.metadata.name);
            const namespace = try self.allocator.dupe(u8, cj.metadata.namespace orelse "default");

            const schedule = if (cj.spec) |s|
                if (s.schedule) |sched| try self.allocator.dupe(u8, sched) else try self.allocator.dupe(u8, "")
            else
                try self.allocator.dupe(u8, "");
            const suspended = if (cj.spec) |s| s.suspended orelse false else false;

            // Extract active from JSON Value (it's an array of references)
            const active: i32 = if (cj.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("active")) |val| {
                        if (val == .array) break :blk @intCast(val.array.items.len);
                    }
                }
                break :blk 0;
            } else 0;

            const last_schedule = try self.allocator.dupe(u8, "1m"); // TODO: Calculate from lastScheduleTime

            try self.items.append(self.allocator, CronJobInfo{
                .name = name,
                .namespace = namespace,
                .schedule = schedule,
                .suspended = suspended,
                .active = active,
                .last_schedule = last_schedule,
            });
        }

        if (self.items.items.len == 0) {
            self.selected_row = 0;
        } else if (self.selected_row >= self.items.items.len) {
            self.selected_row = self.items.items.len - 1;
        }
    }

    pub fn createView(self: *CronJobsView) View {
        return View.create(CronJobsView, self, &vtable);
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        _ = width;

        if (self.loading) {
            try Theme.writeStringWithTheme(term, x, y, "Loading cronjobs...", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }

        if (self.items.items.len == 0) {
            const msg = if (self.show_all_namespaces) "No cronjobs found in cluster" else "No cronjobs in current namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        // Header
        const header = "  NAMESPACE             NAME                     SCHEDULE       SUSPEND ACTIVE LAST";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        // Items
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

            const suspend_str = if (item.suspended) "True" else "False";

            const line = try std.fmt.allocPrint(
                self.allocator,
                "  {s: <20} {s: <23} {s: <14} {s: <7} {d: >6} {s}",
                .{
                    if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                    if (item.name.len > 23) item.name[0..23] else item.name,
                    if (item.schedule.len > 14) item.schedule[0..14] else item.schedule,
                    suspend_str,
                    item.active,
                    item.last_schedule,
                },
            );
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, y + 1 + row, line, fg_color, bg_color);
        }

        // Clear remaining lines (optional - terminal typically handles this)
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    if (self.items.items.len > 0 and self.selected_row < self.items.items.len - 1) {
                        self.selected_row += 1;
                        if (self.selected_row >= self.scroll_offset + 20) self.scroll_offset = self.selected_row - 19;
                    }
                    return .handled;
                },
                'k' => {
                    if (self.selected_row > 0) {
                        self.selected_row -= 1;
                        if (self.selected_row < self.scroll_offset) self.scroll_offset = self.selected_row;
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
                        if (self.items.items.len > 20) self.scroll_offset = self.items.items.len - 20;
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
                's' => {
                    // Toggle suspend/resume on selected cronjob
                    if (self.items.items.len > 0) {
                        const item = &self.items.items[self.selected_row];
                        const new_suspended = !item.suspended;
                        self.k8s_service.setCronJobSuspend(item.name, new_suspended, item.namespace) catch |err| {
                            Logger.err("Failed to suspend/resume cronjob: {}", .{err});
                            return .handled;
                        };
                        try self.refresh();
                    }
                    return .handled;
                },
                else => return .not_handled,
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        Logger.info("CronJobsView shown", .{});
        self.refresh() catch |err| {
            Logger.err("Failed to refresh CronJobs on show: {}", .{err});
        };
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "cronjobs";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        const hint_items = comptime [_]hints_model.Hint{
            hints_model.Hint.plain("↑↓ Navigate", 1),
            hints_model.Hint.plain("s Suspend/Resume", 2),
            hints_model.Hint.plain("r Refresh", 3),
            hints_model.Hint.plain("0 All Namespaces", 4),
        };
        return hints_model.HintConfig{
            .hints = &hint_items,
        };
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
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
