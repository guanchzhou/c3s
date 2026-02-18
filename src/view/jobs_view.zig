/// JobsView - View for Kubernetes Jobs
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

pub const JobsView = struct {
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(JobInfo),

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const JobInfo = struct {
        name: []const u8,
        namespace: []const u8,
        completions: []const u8,
        duration: []const u8,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *JobInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.namespace);
            self.allocator.free(self.completions);
            self.allocator.free(self.duration);
            self.allocator.free(self.age);
        }

        fn getName(self: *const JobInfo) []const u8 { return self.name; }
        fn getAge(self: *const JobInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !JobsView {
        return JobsView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(JobInfo).init(allocator),
        };
    }

    pub fn deinit(self: *JobsView) void {
        self.table.deinit();
    }

    pub fn refresh(self: *JobsView) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            return;
        }

        const jobs = if (self.table.show_all_namespaces)
            self.k8s_service.listAllJobs() catch |err| {
                try self.table.setErrorFmt("Failed to list jobs: {}", .{err});
                return;
            }
        else
            self.k8s_service.listJobs(null) catch |err| {
                try self.table.setErrorFmt("Failed to list jobs: {}", .{err});
                return;
            };
        defer self.table.allocator.free(jobs);

        for (jobs) |job| {
            // Extract succeeded from JSON Value
            const succeeded: i32 = if (job.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("succeeded")) |val| {
                        if (val == .integer) break :blk @intCast(val.integer);
                    }
                }
                break :blk 0;
            } else 0;

            const desired = if (job.spec) |s| s.completions orelse 1 else 1;
            const completions = try std.fmt.allocPrint(self.table.allocator, "{d}/{d}", .{ succeeded, desired });

            // Calculate duration from startTime/completionTime in status JSON
            const duration = blk: {
                const start_time_str: ?[]const u8 = if (job.status) |status_json| st: {
                    if (status_json == .object) {
                        if (status_json.object.get("startTime")) |val| {
                            if (val == .string) break :st val.string;
                        }
                    }
                    break :st null;
                } else null;

                const completion_time_str: ?[]const u8 = if (job.status) |status_json| ct: {
                    if (status_json == .object) {
                        if (status_json.object.get("completionTime")) |val| {
                            if (val == .string) break :ct val.string;
                        }
                    }
                    break :ct null;
                } else null;

                const start_epoch = age_util.parseTimestampToEpoch(start_time_str) orelse
                    break :blk try self.table.allocator.dupe(u8, "-");

                const end_epoch = if (age_util.parseTimestampToEpoch(completion_time_str)) |ce|
                    ce
                else
                    std.time.timestamp();

                const diff = end_epoch - start_epoch;
                if (diff < 0) break :blk try self.table.allocator.dupe(u8, "0s");
                break :blk try age_util.formatDuration(self.table.allocator, @intCast(diff));
            };

            try self.table.appendItem(.{
                .name = try self.table.allocator.dupe(u8, job.metadata.name),
                .namespace = try self.table.allocator.dupe(u8, job.metadata.namespace orelse "default"),
                .completions = completions,
                .duration = duration,
                .age = try age_util.calculateAge(self.table.allocator, job.metadata.creationTimestamp),
                .allocator = self.table.allocator,
            });
        }

        try self.applyFilter(self.table.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *JobsView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{ .name = item.name, .namespace = item.namespace };
    }

    pub fn applyFilter(self: *JobsView, filter: []const u8) !void {
        try self.table.applyFilter(filter, jobMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *JobsView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(JobInfo.getName),
                COL_AGE => self.table.sortBy(JobInfo.getAge),
                else => {},
            }
        }
    }

    fn jobMatchFn(item: *const JobInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *JobsView) View {
        return View.create(JobsView, self, &vtable);
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
        const self: *JobsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, _: u16, height: u16) !void {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(term, x, y, self.theme)) return;

        // Header with sort indicators
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             NAME{s: <28}COMPLETIONS   DURATION   AGE{s}", .{ name_ind, age_ind }) catch "  NAMESPACE             NAME                          COMPLETIONS   DURATION   AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        // Data rows
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |actual_idx, i| {
            const item = self.table.items.items[actual_idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            const line = try std.fmt.allocPrint(
                self.table.allocator,
                "  {s: <20} {s: <28} {s: <13} {s: <10} {s}",
                .{
                    if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                    if (item.name.len > 28) item.name[0..28] else item.name,
                    item.completions,
                    item.duration,
                    item.age,
                },
            );
            defer self.table.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, row_y, line, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *JobsView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh jobs: {}", .{err});
                    return .handled;
                },
                '0' => {
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    self.table.gotoTop();
                    self.refresh() catch |err| Logger.err("Failed to refresh jobs: {}", .{err});
                    return .handled;
                },
                'N' => { self.table.toggleSort(COL_NAME); self.applySorting(); return .handled; },
                'A' => { self.table.toggleSort(COL_AGE); self.applySorting(); return .handled; },
                else => return .not_handled,
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh jobs: {any}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {};
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "jobs";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
