const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const KeyResult = View.KeyResult;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const hints_model = @import("../model/hints.zig");
const table_layout = @import("../ui/table_layout.zig");
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const view_mod = @import("../viewmodel/view.zig");
const ResourceInfo = view_mod.ResourceInfo;
const TableState = @import("../ui/table_state.zig").TableState;

/// PodsView - displays Kubernetes pods with filtering and navigation
pub const PodsView = struct {
    theme: *theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(Pod),

    // Pod-specific extra state
    allocated_title: ?[]u8 = null,
    horizontal_scroll: table_layout.TableScroll = .{ .scroll_offset = 0, .visible_width = 0, .total_width = 0 },
    // Cache for column widths to avoid recalculation on every render
    cached_col_widths: ?table_layout.ColumnWidths = null,
    cached_terminal_width: u16 = 0,

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_STATUS: u8 = 1;
    const COL_AGE: u8 = 2;
    const COL_READY: u8 = 3;
    const COL_CPU: u8 = 4;
    const COL_MEM: u8 = 5;

    const Pod = struct {
        namespace: []const u8,
        name: []const u8,
        ready: []const u8,
        status: []const u8,
        cpu_l: []const u8,
        mem_l: []const u8,
        ip: []const u8,
        node: []const u8,
        age: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Pod) void {
            self.allocator.free(self.namespace);
            self.allocator.free(self.name);
            self.allocator.free(self.ready);
            self.allocator.free(self.status);
            self.allocator.free(self.cpu_l);
            self.allocator.free(self.mem_l);
            self.allocator.free(self.ip);
            self.allocator.free(self.node);
            self.allocator.free(self.age);
        }

        fn getName(self: *const Pod) []const u8 {
            return self.name;
        }
        fn getStatus(self: *const Pod) []const u8 {
            return self.status;
        }
        fn getAge(self: *const Pod) []const u8 {
            return self.age;
        }
        fn getReady(self: *const Pod) []const u8 {
            return self.ready;
        }
        fn getCpu(self: *const Pod) []const u8 {
            return self.cpu_l;
        }
        fn getMem(self: *const Pod) []const u8 {
            return self.mem_l;
        }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *theme_loader.ThemeColors, k8s_service: *K8sService) !PodsView {
        var view = PodsView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(Pod).init(allocator),
        };

        // Real data will be loaded in onShow() to avoid blocking initialization
        try view.applyFilter("");

        return view;
    }

    pub fn deinit(self: *PodsView) void {
        self.table.deinit();
        if (self.allocated_title) |allocated| {
            self.table.allocator.free(allocated);
        }
        // Clean up cached column widths
        if (self.cached_col_widths) |*widths| {
            widths.deinit();
        }
    }

    /// Refresh pod list from Kubernetes API
    pub fn refresh(self: *PodsView) !void {
        // If connection not yet attempted, stay in loading state
        if (!self.k8s_service.isConnected() and !self.k8s_service.hasAttemptedConnect()) {
            self.table.loading = true;
            return;
        }

        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            Logger.warn("PodsView: Cannot refresh - not connected to k8s", .{});
            return;
        }

        // Fetch pods from k8s
        var k8s_pod_list = if (self.table.show_all_namespaces)
            self.k8s_service.listAllPods() catch |err| {
                Logger.err("Failed to list all pods: {any}", .{err});
                try self.table.setConnectionError("pods", err);
                return;
            }
        else
            self.k8s_service.listPods(null) catch |err| {
                Logger.err("Failed to list pods in namespace: {any}", .{err});
                try self.table.setConnectionError("pods", err);
                return;
            };
        defer k8s_pod_list.deinit();

        const k8s_pods = k8s_pod_list.value.items;

        // Fetch pod metrics (gracefully -- metrics server may not be installed)
        var metrics_map = self.k8s_service.getPodMetrics(self.table.show_all_namespaces) catch |err| blk: {
            Logger.warn("Failed to fetch pod metrics: {any}", .{err});
            break :blk null;
        };
        defer if (metrics_map) |*m| self.k8s_service.freePodMetrics(m);

        const allocator = self.table.allocator;

        // Convert to view pods
        for (k8s_pods) |k8s_pod| {
            // Parse status (dynamic JSON)
            const phase = if (k8s_pod.status) |status_json|
                if (status_json.object.get("phase")) |p| p.string else "Unknown"
            else
                "Unknown";

            const pod_ip = if (k8s_pod.status) |status_json|
                if (status_json.object.get("podIP")) |ip| ip.string else "-"
            else
                "-";

            // Count ready/total containers
            var ready_count: u32 = 0;
            var total_count: u32 = 0;
            if (k8s_pod.status) |status_json| {
                if (status_json.object.get("containerStatuses")) |cs| {
                    if (cs == .array) {
                        total_count = @intCast(cs.array.items.len);
                        for (cs.array.items) |container_status| {
                            if (container_status.object.get("ready")) |r| {
                                if (r.bool) ready_count += 1;
                            }
                        }
                    }
                }
            }

            // Look up metrics for this pod
            const pod_ns = k8s_pod.metadata.namespace orelse "default";
            const pod_name = k8s_pod.metadata.name;
            const metric_key = std.fmt.allocPrint(allocator, "{s}/{s}", .{ pod_ns, pod_name }) catch null;
            defer if (metric_key) |k| allocator.free(k);

            var cpu_val: ?[]const u8 = null;
            var mem_val: ?[]const u8 = null;
            if (metric_key) |k| {
                if (metrics_map) |*m| {
                    if (m.get(k)) |pm| {
                        cpu_val = pm.cpu;
                        mem_val = pm.mem;
                    }
                }
            }

            try self.table.appendItem(.{
                .namespace = try allocator.dupe(u8, pod_ns),
                .name = try allocator.dupe(u8, pod_name),
                .ready = try std.fmt.allocPrint(allocator, "{d}/{d}", .{ ready_count, total_count }),
                .status = try allocator.dupe(u8, phase),
                .cpu_l = try allocator.dupe(u8, cpu_val orelse "n/a"),
                .mem_l = try allocator.dupe(u8, mem_val orelse "n/a"),
                .ip = try allocator.dupe(u8, pod_ip),
                .node = try allocator.dupe(u8, if (k8s_pod.spec) |spec| spec.nodeName orelse "-" else "-"),
                .age = try age_util.calculateAge(allocator, k8s_pod.metadata.creationTimestamp),
                .allocator = allocator,
            });
        }

        // Reapply filter
        try self.applyFilter(self.table.filter_text);
    }

    /// Get the name and namespace of the currently selected pod
    pub fn getSelectedResourceInfo(self: *PodsView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    fn loadSampleData(self: *PodsView) !void {
        const allocator = self.table.allocator;
        const sample_pods = [_]struct { []const u8, []const u8, []const u8, []const u8, []const u8, []const u8, []const u8, []const u8, []const u8 }{
            .{ "default", "nginx-deployment-7d4b4b8c9c-abc123", "1/1", "Running", "2m", "45Mi", "10.244.1.5", "worker-1", "2d" },
            .{ "kube-system", "coredns-558bd4d5db-xyz789", "1/1", "Running", "1m", "32Mi", "10.244.0.2", "master-1", "5d" },
            .{ "default", "redis-master-0", "1/1", "Running", "3m", "67Mi", "10.244.2.10", "worker-2", "1d" },
            .{ "kube-system", "kube-proxy-def456", "1/1", "Running", "500m", "28Mi", "10.244.0.3", "master-1", "5d" },
            .{ "default", "postgres-0", "0/1", "Pending", "0m", "0Mi", "-", "worker-1", "30m" },
        };

        for (sample_pods) |pod_data| {
            try self.table.appendItem(.{
                .namespace = try allocator.dupe(u8, pod_data[0]),
                .name = try allocator.dupe(u8, pod_data[1]),
                .ready = try allocator.dupe(u8, pod_data[2]),
                .status = try allocator.dupe(u8, pod_data[3]),
                .cpu_l = try allocator.dupe(u8, pod_data[4]),
                .mem_l = try allocator.dupe(u8, pod_data[5]),
                .ip = try allocator.dupe(u8, pod_data[6]),
                .node = try allocator.dupe(u8, pod_data[7]),
                .age = try allocator.dupe(u8, pod_data[8]),
                .allocator = allocator,
            });
        }
    }

    pub fn applyFilter(self: *PodsView, filter: []const u8) !void {
        const allocator = self.table.allocator;

        // Free old allocated title
        if (self.allocated_title) |allocated| {
            allocator.free(allocated);
            self.allocated_title = null;
        }

        // Invalidate cache when filter changes (data set changes)
        if (self.cached_col_widths) |*widths| {
            widths.deinit();
            self.cached_col_widths = null;
        }

        // Use TableState filter
        try self.table.applyFilter(filter, podMatchFn);

        // Re-apply sorting after filter
        self.applySorting();
    }

    fn applySorting(self: *PodsView) void {
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(Pod.getName),
                COL_STATUS => self.table.sortBy(Pod.getStatus),
                COL_AGE => self.table.sortBy(Pod.getAge),
                COL_READY => self.table.sortBy(Pod.getReady),
                COL_CPU => self.table.sortBy(Pod.getCpu),
                COL_MEM => self.table.sortBy(Pod.getMem),
                else => {},
            }
        }
    }

    fn podMatchFn(pod: *const Pod, filter: []const u8) bool {
        return std.mem.indexOf(u8, pod.name, filter) != null or
            std.mem.indexOf(u8, pod.namespace, filter) != null;
    }

    // View trait implementation
    pub fn createView(self: *PodsView) View {
        return View.create(PodsView, self, &vtable);
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
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        const allocator = self.table.allocator;

        self.table.visible_rows = if (height > 1) height - 1 else 0;

        // Show loading/error states
        if (try self.table.renderStatus(terminal, x, y, self.theme)) return;

        // Define column configuration with priorities
        const columns = [_]table_layout.ColumnInfo{
            .{ .name = "NAMESPACE", .min_width = 10, .max_width = null, .priority = table_layout.ColumnPriority.MEDIUM },
            .{ .name = "NAME", .min_width = 15, .max_width = null, .priority = table_layout.ColumnPriority.CRITICAL },
            .{ .name = "READY", .min_width = 6, .max_width = 8, .priority = table_layout.ColumnPriority.HIGH },
            .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = table_layout.ColumnPriority.HIGH },
            .{ .name = "CPU", .min_width = 6, .max_width = 10, .priority = table_layout.ColumnPriority.VERY_LOW },
            .{ .name = "MEM", .min_width = 6, .max_width = 10, .priority = table_layout.ColumnPriority.VERY_LOW },
            .{ .name = "IP", .min_width = 10, .max_width = null, .priority = table_layout.ColumnPriority.LOW },
            .{ .name = "NODE", .min_width = 10, .max_width = null, .priority = table_layout.ColumnPriority.LOW },
            .{ .name = "AGE", .min_width = 5, .max_width = 8, .priority = table_layout.ColumnPriority.MEDIUM },
        };

        const col_names = [_][]const u8{ "NAMESPACE", "NAME", "READY", "STATUS", "CPU", "MEM", "IP", "NODE", "AGE" };
        const available_width = width;

        // Use cached column widths if terminal width hasn't changed
        const use_cache = self.cached_col_widths != null and self.cached_terminal_width == available_width;

        const col_widths = if (use_cache) blk: {
            // Use cached widths - no allocation needed
            break :blk &self.cached_col_widths.?;
        } else blk: {
            // Recalculate widths - terminal size changed or first render
            // Prepare data for width calculation
            var rows_data = try std.ArrayList([]const []const u8).initCapacity(allocator, self.table.filtered_indices.items.len);
            defer rows_data.deinit(allocator);

            for (self.table.filtered_indices.items) |pod_idx| {
                const pod = self.table.items.items[pod_idx];
                const row = [_][]const u8{ pod.namespace, pod.name, pod.ready, pod.status, pod.cpu_l, pod.mem_l, pod.ip, pod.node, pod.age };
                try rows_data.append(allocator, &row);
            }

            // Free old cache if exists
            if (self.cached_col_widths) |*old_widths| {
                old_widths.deinit();
            }

            // Calculate and cache new widths
            self.cached_col_widths = try table_layout.calculateColumnWidths(
                allocator,
                &col_names,
                rows_data.items,
                &columns,
                available_width,
            );
            self.cached_terminal_width = available_width;

            break :blk &self.cached_col_widths.?;
        };

        // Update horizontal scroll
        self.horizontal_scroll.visible_width = available_width;
        self.horizontal_scroll.total_width = col_widths.total_width;

        // Draw column headers with sort indicators
        const header_y = y;
        var col_x = x;
        // Map column index to sort column id (only for sortable columns)
        const col_sort_ids = [_]?u8{ null, COL_NAME, COL_READY, COL_STATUS, null, null, null, null, COL_AGE };
        for (col_names, col_widths.widths, 0..) |name, w, col_i| {
            if (w == 0) continue; // Skip hidden columns

            try terminal.setCursor(col_x, header_y);
            try terminal.writeAll(self.theme.title);

            // Add sort indicator if this column is sorted
            const indicator = if (col_i < col_sort_ids.len)
                if (col_sort_ids[col_i]) |sid|
                    sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, sid)
                else
                    ""
            else
                "";

            const header_with_indicator = try std.fmt.allocPrint(allocator, "{s}{s}", .{ name, indicator });
            defer allocator.free(header_with_indicator);

            // Truncate header if needed
            const header_text = if (header_with_indicator.len > w)
                try table_layout.truncateText(allocator, header_with_indicator, w, false)
            else
                header_with_indicator;
            // Only free if truncateText allocated a new string
            defer if (header_text.ptr != header_with_indicator.ptr) allocator.free(header_text);

            try terminal.writeAll(header_text);
            try terminal.writeAll("\x1b[0m");
            col_x += w + 1;
        }

        // Show empty message if no pods
        if (self.table.filtered_indices.items.len == 0) {
            const empty_msg = "No pods found";
            try Theme.writeStringWithTheme(terminal, x, y, empty_msg, self.theme.inactive_fg, self.theme.main_bg);
            return;
        }

        // Draw pod rows
        const range = self.table.getVisibleRange();

        for (self.table.filtered_indices.items[range.start..range.end], 0..) |pod_idx, display_idx| {
            const pod = self.table.items.items[pod_idx];
            const row_y = header_y + @as(u16, @intCast(display_idx)) + 1;
            const is_selected = self.table.isSelected(display_idx);

            // Highlight selected row
            if (is_selected) {
                try terminal.setCursor(x, row_y);
                try terminal.writeAll(self.theme.selected_bg);
                var spaces_buf: [256]u8 = undefined;
                @memset(&spaces_buf, ' ');
                var remaining: usize = width;
                while (remaining > 0) {
                    const chunk = @min(remaining, spaces_buf.len);
                    try terminal.writeAll(spaces_buf[0..chunk]);
                    remaining -= chunk;
                }
                try terminal.writeAll("\x1b[0m");
            }

            // Draw pod data with adaptive widths
            col_x = x;
            const pod_data = [_][]const u8{ pod.namespace, pod.name, pod.ready, pod.status, pod.cpu_l, pod.mem_l, pod.ip, pod.node, pod.age };

            for (pod_data, col_widths.widths) |data, w| {
                if (w == 0) continue; // Skip hidden columns

                try terminal.setCursor(col_x, row_y);
                if (is_selected) {
                    try terminal.writeAll(self.theme.selected_fg);
                    try terminal.writeAll(self.theme.selected_bg);
                } else {
                    try terminal.writeAll(self.theme.main_fg);
                }

                // Truncate cell data if needed
                const cell_text = if (data.len > w)
                    try table_layout.truncateText(allocator, data, w, true)
                else
                    try allocator.dupe(u8, data);
                defer allocator.free(cell_text);

                try terminal.writeAll(cell_text);
                try terminal.writeAll("\x1b[0m");
                col_x += w + 1;
            }
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *PodsView = @ptrCast(@alignCast(ptr));

        // Common navigation keys (j/k/g/G/d/y/:/  and arrow keys)
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .char => |c| switch (c) {
                'h' => {
                    self.horizontal_scroll.scrollLeft(5);
                    return .handled;
                },
                'l' => return .request_logs,
                'r' => {
                    self.refresh() catch |err| {
                        Logger.err("Failed to refresh pods: {any}", .{err});
                    };
                    return .handled;
                },
                '0' => {
                    // Toggle all namespaces
                    self.table.show_all_namespaces = !self.table.show_all_namespaces;
                    Logger.info("PodsView: toggled show_all_namespaces={}, refreshing...", .{self.table.show_all_namespaces});
                    self.table.gotoTop();
                    self.refresh() catch |err| {
                        Logger.err("Failed to refresh pods after toggling namespaces: {any}", .{err});
                    };
                    Logger.info("PodsView: refresh complete, pods={}, filtered={}", .{ self.table.items.items.len, self.table.filtered_indices.items.len });
                    return .handled;
                },
                '$' => {
                    self.horizontal_scroll.scrollToEnd();
                    return .handled;
                },
                'N' => {
                    self.table.toggleSort(COL_NAME);
                    self.applySorting();
                    return .handled;
                },
                'S' => {
                    self.table.toggleSort(COL_STATUS);
                    self.applySorting();
                    return .handled;
                },
                'A' => {
                    self.table.toggleSort(COL_AGE);
                    self.applySorting();
                    return .handled;
                },
                'R' => {
                    self.table.toggleSort(COL_READY);
                    self.applySorting();
                    return .handled;
                },
                'C' => {
                    self.table.toggleSort(COL_CPU);
                    self.applySorting();
                    return .handled;
                },
                'M' => {
                    self.table.toggleSort(COL_MEM);
                    self.applySorting();
                    return .handled;
                },
                '?' => return .request_command_palette,
                else => return .not_handled,
            },
            .shift_g => {
                self.table.gotoBottom();
                return .handled;
            },
            .escape => {
                if (self.table.filter_text.len > 0) {
                    try self.applyFilter("");
                    return .handled;
                }
                return .not_handled;
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        Logger.info("PodsView: View activated", .{});
        // Refresh data when view is shown - catch ALL errors to prevent crashes
        self.refresh() catch |err| {
            Logger.err("Failed to refresh pods: {any}", .{err});
            // Set a fallback error message if one wasn't already set
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {
                    Logger.err("Failed to allocate error message", .{});
                    return;
                };
            }
        };
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("PodsView: View deactivated", .{});
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "pods";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.podsHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
