/// CronJobsView - View for Kubernetes CronJobs
const std = @import("std");
const klient = @import("klient");
const view_mod = @import("../viewmodel/view.zig");
const View = view_mod.View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const hints_model = @import("../model/hints.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const ResourceInfo = view_mod.ResourceInfo;
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");
const Logger = @import("../core/logger.zig");
const TableState = @import("../ui/table_state.zig").TableState;

pub const CronJobsView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(CronJobInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const CronJobInfo = struct {
        name: []const u8,
        namespace: []const u8,
        schedule: []const u8,
        suspended: bool,
        active: i32,
        last_schedule: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *CronJobInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.namespace);
            self.allocator.free(self.schedule);
            self.allocator.free(self.last_schedule);
        }

        fn getName(self: *const CronJobInfo) []const u8 { return self.name; }
        fn getLastSchedule(self: *const CronJobInfo) []const u8 { return self.last_schedule; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !CronJobsView {
        return CronJobsView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(CronJobInfo).init(allocator),
        };
    }

    pub fn deinit(self: *CronJobsView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *CronJobsView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        const cronjobs = if (self.table.show_all_namespaces)
            self.k8s_service.listAllCronJobs() catch |err| {
                try self.table.setErrorFmt("Failed to list cronjobs: {}", .{err});
                return;
            }
        else
            self.k8s_service.listCronJobs(null) catch |err| {
                try self.table.setErrorFmt("Failed to list cronjobs: {}", .{err});
                return;
            };
        defer self.table.allocator.free(cronjobs);

        for (cronjobs) |cj| {
            const schedule = if (cj.spec) |s|
                if (s.schedule) |sched| try self.table.allocator.dupe(u8, sched) else try self.table.allocator.dupe(u8, "")
            else
                try self.table.allocator.dupe(u8, "");
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

            // Calculate last schedule age from lastScheduleTime in status JSON
            const last_schedule_str: ?[]const u8 = if (cj.status) |status_json| lst: {
                if (status_json == .object) {
                    if (status_json.object.get("lastScheduleTime")) |val| {
                        if (val == .string) break :lst val.string;
                    }
                }
                break :lst null;
            } else null;

            const last_schedule = if (last_schedule_str != null)
                try age_util.calculateAge(self.table.allocator, last_schedule_str)
            else
                try self.table.allocator.dupe(u8, "-");

            try self.table.appendItem(.{
                .name = try self.table.allocator.dupe(u8, cj.metadata.name),
                .namespace = try self.table.allocator.dupe(u8, cj.metadata.namespace orelse "default"),
                .schedule = schedule,
                .suspended = suspended,
                .active = active,
                .last_schedule = last_schedule,
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *CronJobsView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{ .name = item.name, .namespace = item.namespace };
    }

    pub fn applyFilter(self: *CronJobsView, filter: []const u8) !void {
        try self.table.applyFilter(filter, cronjobMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *CronJobsView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(CronJobInfo.getName),
                COL_AGE => self.table.sortBy(CronJobInfo.getLastSchedule),
                else => {},
            }
        }
    }

    fn cronjobMatchFn(item: *const CronJobInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *CronJobsView) View {
        return View.create(CronJobsView, self, &vtable);
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
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, _: u16, height: u16) !void {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(term, x, y, self.theme)) return;

        // Header with sort indicators
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "LAST{s}", .{age_ind}) catch "LAST";
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             {s: <25}SCHEDULE       SUSPEND ACTIVE {s}", .{ name_hdr, age_hdr }) catch "  NAMESPACE             NAME                     SCHEDULE       SUSPEND ACTIVE LAST";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        // Data rows
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |actual_idx, i| {
            const item = self.table.items.items[actual_idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            const suspend_str = if (item.suspended) "True" else "False";

            const line = try std.fmt.allocPrint(
                self.table.allocator,
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
            defer self.table.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, row_y, line, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh cronjobs: {}", .{err});
                    return .handled;
                },
                '0' => {
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    self.table.gotoTop();
                    self.refresh() catch |err| Logger.err("Failed to refresh cronjobs: {}", .{err});
                    return .handled;
                },
                'N' => { self.table.toggleSort(COL_NAME); self.applySorting(); return .handled; },
                'A' => { self.table.toggleSort(COL_AGE); self.applySorting(); return .handled; },
                's' => {
                    // Toggle suspend/resume on selected cronjob
                    if (self.table.getSelectedItem()) |item| {
                        const new_suspended = !item.suspended;
                        self.k8s_service.setCronJobSuspend(item.name, new_suspended, item.namespace) catch |err| {
                            Logger.err("Failed to suspend/resume cronjob: {}", .{err});
                            return .handled;
                        };
                        self.refresh() catch |err| Logger.err("Failed to refresh cronjobs: {}", .{err});
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
        self.refresh() catch |err| {
            Logger.err("Failed to refresh cronjobs: {any}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {};
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "cronjobs";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
