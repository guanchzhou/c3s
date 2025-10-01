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
const K8sService = @import("../services/k8s_service.zig").K8sService;
const Logger = @import("../core/logger.zig");

pub const JobsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    items: std.ArrayListUnmanaged(JobInfo),
    selected_row: usize,
    scroll_offset: usize,
    loading: bool,
    error_message: ?[]const u8,
    filter_text: []const u8,
    show_all_namespaces: bool,

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
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !JobsView {
        var view = JobsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = std.ArrayListUnmanaged(JobInfo){},
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

    pub fn deinit(self: *JobsView) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
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

        if (self.items.items.len == 0) {
            self.selected_row = 0;
        } else if (self.selected_row >= self.items.items.len) {
            self.selected_row = self.items.items.len - 1;
        }
    }

    pub fn createView(self: *JobsView) View {
        return View.create(JobsView, self, &vtable);
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
        _ = width;

        if (self.loading) {
            try Theme.writeStringWithTheme(term, x, y, "Loading jobs...", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }

        if (self.items.items.len == 0) {
            const msg = if (self.show_all_namespaces) "No jobs found in cluster" else "No jobs in current namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        // Header
        const header = "  NAMESPACE             NAME                          COMPLETIONS   DURATION   AGE";
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
        }

        // Clear remaining lines (optional - terminal typically handles this)
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *JobsView = @ptrCast(@alignCast(ptr));
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
        const hint_items = comptime [_]hints_model.Hint{
            hints_model.Hint.plain("↑↓ Navigate", 1),
            hints_model.Hint.plain("r Refresh", 2),
            hints_model.Hint.plain("0 All Namespaces", 3),
        };
        return hints_model.HintConfig{
            .hints = &hint_items,
        };
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
