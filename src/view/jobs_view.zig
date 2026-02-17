/// JobsView - View for Kubernetes Jobs
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

pub const JobsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    items: std.ArrayListUnmanaged(JobInfo),
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

    const JobInfo = struct {
        name: []const u8,
        namespace: []const u8,
        completions: []const u8,
        duration: []const u8,
        age: []const u8,

        pub fn deinit(self: *JobInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.namespace);
            allocator.free(self.completions);
            allocator.free(self.duration);
            allocator.free(self.age);
        }

        fn getName(self: *const JobInfo) []const u8 { return self.name; }
        fn getAge(self: *const JobInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !JobsView {
        var view = JobsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = std.ArrayListUnmanaged(JobInfo){},
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

    pub fn deinit(self: *JobsView) void {
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

    pub fn refresh(self: *JobsView) !void {
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

        const jobs = if (self.show_all_namespaces)
            self.k8s_service.listAllJobs() catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list jobs: {}", .{err});
                return;
            }
        else
            self.k8s_service.listJobs(null) catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list jobs: {}", .{err});
                return;
            };
        defer self.allocator.free(jobs);

        for (jobs) |job| {
            const name = try self.allocator.dupe(u8, job.metadata.name);
            const namespace = try self.allocator.dupe(u8, job.metadata.namespace orelse "default");

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
            const completions = try std.fmt.allocPrint(self.allocator, "{d}/{d}", .{ succeeded, desired });

            const duration = try self.allocator.dupe(u8, "1m"); // TODO: Calculate from start/completion time
            const age = try self.allocator.dupe(u8, "1d");

            try self.items.append(self.allocator, JobInfo{
                .name = name,
                .namespace = namespace,
                .completions = completions,
                .duration = duration,
                .age = age,
            });
        }

        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *JobsView) ?ResourceInfo {
        if (self.filtered_indices.items.len == 0) return null;
        if (self.selected_row >= self.filtered_indices.items.len) return null;
        const idx = self.filtered_indices.items[self.selected_row];
        const item = self.items.items[idx];
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *JobsView, filter: []const u8) !void {
        self.filter_text = filter;
        try universal_filter.applyFilter(
            JobInfo,
            self.allocator,
            self.items.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            jobMatchFn,
        );
        self.applySorting();
    }

    fn applySorting(self: *JobsView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(JobInfo, self.items.items, &self.filtered_indices, JobInfo.getName, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(JobInfo, self.items.items, &self.filtered_indices, JobInfo.getAge, self.sort_ascending),
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

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
        _ = width;
        self.visible_rows = if (height > 1) height - 1 else 0;

        if (self.loading) {
            try Theme.writeStringWithTheme(term, x, y, "Loading jobs...", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }

        if (self.filtered_indices.items.len == 0) {
            const msg = if (self.show_all_namespaces) "No jobs found in cluster" else "No jobs in current namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        // Header with sort indicators
        const name_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_AGE);
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             NAME{s: <28}COMPLETIONS   DURATION   AGE{s}", .{ name_ind, age_ind }) catch "  NAMESPACE             NAME                          COMPLETIONS   DURATION   AGE";
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

            const line = try std.fmt.allocPrint(
                self.allocator,
                "  {s: <20} {s: <28} {s: <13} {s: <10} {s}",
                .{
                    if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                    if (item.name.len > 28) item.name[0..28] else item.name,
                    item.completions,
                    item.duration,
                    item.age,
                },
            );
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, y + 1 + row, line, fg_color, bg_color);
            row += 1;
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
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
                else => return .not_handled,
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
        Logger.info("JobsView shown", .{});
        self.refresh() catch |err| {
            Logger.err("Failed to refresh Jobs on show: {}", .{err});
        };
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "jobs";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
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
