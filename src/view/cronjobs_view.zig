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
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const ResourceInfo = k8s_service_mod.ResourceInfo;
const universal_filter = @import("../viewmodel/filter.zig");
const sort_util = @import("../viewmodel/sort.zig");
const Logger = @import("../core/logger.zig");

pub const CronJobsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    items: std.ArrayListUnmanaged(CronJobInfo),
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

        fn getName(self: *const CronJobInfo) []const u8 { return self.name; }
        fn getLastSchedule(self: *const CronJobInfo) []const u8 { return self.last_schedule; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !CronJobsView {
        var view = CronJobsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = std.ArrayListUnmanaged(CronJobInfo){},
            .filtered_indices = std.ArrayListUnmanaged(usize){},
            .selected_row = 0,
            .scroll_offset = 0,
            .visible_rows = 0,
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
        self.filtered_indices.deinit(self.allocator);
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

        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *CronJobsView) ?ResourceInfo {
        if (self.filtered_indices.items.len == 0) return null;
        if (self.selected_row >= self.filtered_indices.items.len) return null;
        const idx = self.filtered_indices.items[self.selected_row];
        const item = self.items.items[idx];
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *CronJobsView, filter: []const u8) !void {
        self.filter_text = filter;
        try universal_filter.applyFilter(
            CronJobInfo,
            self.allocator,
            self.items.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            cronjobMatchFn,
        );
        self.applySorting();
    }

    fn applySorting(self: *CronJobsView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(CronJobInfo, self.items.items, &self.filtered_indices, CronJobInfo.getName, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(CronJobInfo, self.items.items, &self.filtered_indices, CronJobInfo.getLastSchedule, self.sort_ascending),
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

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        _ = width;
        self.visible_rows = if (height > 1) height - 1 else 0;

        if (self.loading) {
            try Theme.writeStringWithTheme(term, x, y, "Loading cronjobs...", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }

        if (self.filtered_indices.items.len == 0) {
            const msg = if (self.show_all_namespaces) "No cronjobs found in cluster" else "No cronjobs in current namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        // Header with sort indicators
        const name_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_AGE);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "LAST{s}", .{age_ind}) catch "LAST";
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             {s: <25}SCHEDULE       SUSPEND ACTIVE {s}", .{ name_hdr, age_hdr }) catch "  NAMESPACE             NAME                     SCHEDULE       SUSPEND ACTIVE LAST";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        // Items
        const start_idx = self.scroll_offset;
        const end_idx = @min(start_idx + self.visible_rows, self.filtered_indices.items.len);
        var row: u16 = 0;

        for (start_idx..end_idx) |fi| {
            const item_idx = self.filtered_indices.items[fi];
            const item = &self.items.items[item_idx];
            const is_selected = (fi == self.selected_row);

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
            row += 1;
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *CronJobsView = @ptrCast(@alignCast(ptr));
        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len - 1) {
                        self.selected_row += 1;
                        if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                            self.scroll_offset = self.selected_row - self.visible_rows + 1;
                        }
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
                    if (self.filtered_indices.items.len > 0) {
                        self.selected_row = @intCast(self.filtered_indices.items.len - 1);
                        if (self.selected_row >= self.visible_rows) {
                            self.scroll_offset = self.selected_row - self.visible_rows + 1;
                        }
                    }
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
                    if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len) {
                        const item_idx = self.filtered_indices.items[self.selected_row];
                        const item = &self.items.items[item_idx];
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
        return hints_model.resourceHints();
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
