const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const universal_filter = @import("../viewmodel/filter.zig");
const hints_model = @import("../model/hints.zig");
const table_layout = @import("../ui/table_layout.zig");
const sort_util = @import("../viewmodel/sort.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const ResourceInfo = k8s_service_mod.ResourceInfo;

/// PodsView - displays Kubernetes pods with filtering and navigation
pub const PodsView = struct {
    allocator: std.mem.Allocator,
    theme: *theme_loader.ThemeColors,
    k8s_service: *K8sService,
    pods: std.ArrayListUnmanaged(Pod),
    filtered_indices: std.ArrayListUnmanaged(usize),
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    filter_text: []const u8 = "",
    visible_rows: u32 = 0,
    allocated_title: ?[]u8 = null,
    horizontal_scroll: table_layout.TableScroll = .{ .scroll_offset = 0, .visible_width = 0, .total_width = 0 },
    error_message: ?[]u8 = null,
    show_all_namespaces: bool = false,
    sort_column: ?u8 = null,
    sort_ascending: bool = true,
    // Cache for column widths to avoid recalculation on every render
    cached_col_widths: ?table_layout.ColumnWidths = null,
    cached_terminal_width: u16 = 0,

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_STATUS: u8 = 1;
    const COL_AGE: u8 = 2;
    const COL_READY: u8 = 3;

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

        fn getName(self: *const Pod) []const u8 { return self.name; }
        fn getStatus(self: *const Pod) []const u8 { return self.status; }
        fn getAge(self: *const Pod) []const u8 { return self.age; }
        fn getReady(self: *const Pod) []const u8 { return self.ready; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *theme_loader.ThemeColors, k8s_service: *K8sService) !PodsView {
        var view = PodsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .pods = std.ArrayListUnmanaged(Pod){},
            .filtered_indices = std.ArrayListUnmanaged(usize){},
        };

        // Real data will be loaded in onShow() to avoid blocking initialization
        try view.applyFilter("");

        return view;
    }

    /// Refresh pod list from Kubernetes API
    pub fn refresh(self: *PodsView) !void {
        // Clear previous error
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        // Safety check
        if (!self.k8s_service.isConnected()) {
            self.error_message = try self.allocator.dupe(u8, "Not connected to Kubernetes cluster");
            Logger.warn("PodsView: Cannot refresh - not connected to k8s", .{});
            return;
        }

        // Clear existing pods
        for (self.pods.items) |pod| {
            self.allocator.free(pod.namespace);
            self.allocator.free(pod.name);
            self.allocator.free(pod.ready);
            self.allocator.free(pod.status);
            self.allocator.free(pod.cpu_l);
            self.allocator.free(pod.mem_l);
            self.allocator.free(pod.ip);
            self.allocator.free(pod.node);
            self.allocator.free(pod.age);
        }
        self.pods.clearRetainingCapacity();

        // Fetch pods from k8s
        var k8s_pod_list = if (self.show_all_namespaces)
            self.k8s_service.listAllPods() catch |err| {
                Logger.err("Failed to list all pods: {any}", .{err});
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to fetch pods: {any}", .{err});
                return;
            }
        else
            self.k8s_service.listPods(null) catch |err| {
                Logger.err("Failed to list pods in namespace: {any}", .{err});
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to fetch pods: {any}", .{err});
                return;
            };
        defer k8s_pod_list.deinit();

        const k8s_pods = k8s_pod_list.value.items;

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

            try self.pods.append(self.allocator, .{
                .namespace = try self.allocator.dupe(u8, k8s_pod.metadata.namespace orelse "default"),
                .name = try self.allocator.dupe(u8, k8s_pod.metadata.name),
                .ready = try std.fmt.allocPrint(self.allocator, "{d}/{d}", .{ ready_count, total_count }),
                .status = try self.allocator.dupe(u8, phase),
                .cpu_l = try self.allocator.dupe(u8, "0m"), // TODO: Get from metrics
                .mem_l = try self.allocator.dupe(u8, "0Mi"), // TODO: Get from metrics
                .ip = try self.allocator.dupe(u8, pod_ip),
                .node = try self.allocator.dupe(u8, if (k8s_pod.spec) |spec| spec.nodeName orelse "-" else "-"),
                .age = try self.allocator.dupe(u8, "TODO"), // TODO: Calculate from creationTimestamp
            });
        }

        // Reapply filter
        try self.applyFilter(self.filter_text);
    }

    pub fn cleanup(self: *PodsView) void {
        // Deallocate individual strings in pods
        // All strings are allocated via dupe in loadSampleData() and loadPodsFromK8s()
        for (self.pods.items) |pod| {
            self.allocator.free(pod.namespace);
            self.allocator.free(pod.name);
            self.allocator.free(pod.ready);
            self.allocator.free(pod.status);
            self.allocator.free(pod.cpu_l);
            self.allocator.free(pod.mem_l);
            self.allocator.free(pod.ip);
            self.allocator.free(pod.node);
            self.allocator.free(pod.age);
        }
        self.pods.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        if (self.allocated_title) |allocated| {
            self.allocator.free(allocated);
        }
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
        // Clean up cached column widths
        if (self.cached_col_widths) |*widths| {
            widths.deinit();
        }
    }

    /// Get the name and namespace of the currently selected pod
    pub fn getSelectedResourceInfo(self: *PodsView) ?ResourceInfo {
        if (self.filtered_indices.items.len == 0) return null;
        if (self.selected_row >= self.filtered_indices.items.len) return null;
        const pod_idx = self.filtered_indices.items[self.selected_row];
        const pod = self.pods.items[pod_idx];
        return ResourceInfo{
            .name = pod.name,
            .namespace = pod.namespace,
        };
    }

    fn loadSampleData(self: *PodsView) !void {
        const sample_pods = [_]struct { []const u8, []const u8, []const u8, []const u8, []const u8, []const u8, []const u8, []const u8, []const u8 }{
            .{ "default", "nginx-deployment-7d4b4b8c9c-abc123", "1/1", "Running", "2m", "45Mi", "10.244.1.5", "worker-1", "2d" },
            .{ "kube-system", "coredns-558bd4d5db-xyz789", "1/1", "Running", "1m", "32Mi", "10.244.0.2", "master-1", "5d" },
            .{ "default", "redis-master-0", "1/1", "Running", "3m", "67Mi", "10.244.2.10", "worker-2", "1d" },
            .{ "kube-system", "kube-proxy-def456", "1/1", "Running", "500m", "28Mi", "10.244.0.3", "master-1", "5d" },
            .{ "default", "postgres-0", "0/1", "Pending", "0m", "0Mi", "-", "worker-1", "30m" },
        };

        for (sample_pods) |pod_data| {
            try self.pods.append(self.allocator, .{
                .namespace = try self.allocator.dupe(u8, pod_data[0]),
                .name = try self.allocator.dupe(u8, pod_data[1]),
                .ready = try self.allocator.dupe(u8, pod_data[2]),
                .status = try self.allocator.dupe(u8, pod_data[3]),
                .cpu_l = try self.allocator.dupe(u8, pod_data[4]),
                .mem_l = try self.allocator.dupe(u8, pod_data[5]),
                .ip = try self.allocator.dupe(u8, pod_data[6]),
                .node = try self.allocator.dupe(u8, pod_data[7]),
                .age = try self.allocator.dupe(u8, pod_data[8]),
            });
        }
    }

    pub fn applyFilter(self: *PodsView, filter: []const u8) !void {
        // Free old allocated title
        if (self.allocated_title) |allocated| {
            self.allocator.free(allocated);
            self.allocated_title = null;
        }

        self.filter_text = filter;

        // Invalidate cache when filter changes (data set changes)
        if (self.cached_col_widths) |*widths| {
            widths.deinit();
            self.cached_col_widths = null;
        }

        // Use universal filter
        try universal_filter.applyFilter(
            Pod,
            self.allocator,
            self.pods.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            podMatchFn,
        );

        // Re-apply sorting after filter
        self.applySorting();
    }

    fn applySorting(self: *PodsView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(Pod, self.pods.items, &self.filtered_indices, Pod.getName, self.sort_ascending),
                COL_STATUS => sort_util.sortFilteredIndices(Pod, self.pods.items, &self.filtered_indices, Pod.getStatus, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(Pod, self.pods.items, &self.filtered_indices, Pod.getAge, self.sort_ascending),
                COL_READY => sort_util.sortFilteredIndices(Pod, self.pods.items, &self.filtered_indices, Pod.getReady, self.sort_ascending),
                else => {},
            }
        }
    }

    fn podMatchFn(pod: *const Pod, filter: []const u8) bool {
        return std.mem.indexOf(u8, pod.name, filter) != null or
            std.mem.indexOf(u8, pod.namespace, filter) != null;
    }

    fn navigateUp(self: *PodsView) !void {
        if (self.selected_row > 0) {
            self.selected_row -= 1;
            // Adjust scroll if needed
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        }
    }

    fn navigateDown(self: *PodsView) !void {
        if (self.selected_row + 1 < self.filtered_indices.items.len) {
            self.selected_row += 1;
            // Adjust scroll if needed
            if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }
    }

    fn gotoTop(self: *PodsView) !void {
        self.selected_row = 0;
        self.scroll_offset = 0;
    }

    fn gotoBottom(self: *PodsView) !void {
        if (self.filtered_indices.items.len > 0) {
            self.selected_row = @intCast(self.filtered_indices.items.len - 1);
            if (self.selected_row >= self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }
    }

    fn pageUp(self: *PodsView) !void {
        const page_size = self.visible_rows;
        if (self.selected_row >= page_size) {
            self.selected_row -= page_size;
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        } else {
            try self.gotoTop();
        }
    }

    fn pageDown(self: *PodsView) !void {
        const page_size = self.visible_rows;
        if (self.selected_row + page_size < self.filtered_indices.items.len) {
            self.selected_row += page_size;
            if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        } else {
            try self.gotoBottom();
        }
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
        .deinit = deinit,
    };

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *PodsView = @ptrCast(@alignCast(ptr));

        self.visible_rows = if (height > 3) height - 3 else 0;

        // Build title first
        var title_buf: [256]u8 = undefined;
        const ns = if (self.show_all_namespaces)
            "all"
        else
            // Always show an effective namespace, even when disconnected
            self.k8s_service.getCurrentNamespace();

        const title_text = if (self.filter_text.len > 0)
            try std.fmt.bufPrint(&title_buf, "pods({s})[{d}] </{s}>", .{ ns, self.filtered_indices.items.len, self.filter_text })
        else
            try std.fmt.bufPrint(&title_buf, "pods({s})[{d}]", .{ ns, self.filtered_indices.items.len });

        // Draw box border with title
        const BoxDrawing = @import("../ui/box_drawing.zig");
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, self.theme.proc_box, self.theme.main_bg, title_text, .rounded, self.theme.main_fg, self.theme.title);

        // Show error message if present
        if (self.error_message) |msg| {
            const Theme = @import("../theme.zig");
            try Theme.writeStringWithTheme(terminal, x + 2, y + height / 2, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }

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
        const available_width = if (width > 2) width - 2 else 0;

        // Use cached column widths if terminal width hasn't changed
        const use_cache = self.cached_col_widths != null and self.cached_terminal_width == available_width;

        const col_widths = if (use_cache) blk: {
            // Use cached widths - no allocation needed
            break :blk &self.cached_col_widths.?;
        } else blk: {
            // Recalculate widths - terminal size changed or first render
            // Prepare data for width calculation
            var rows_data = try std.ArrayList([]const []const u8).initCapacity(self.allocator, self.filtered_indices.items.len);
            defer rows_data.deinit(self.allocator);

            for (self.filtered_indices.items) |pod_idx| {
                const pod = self.pods.items[pod_idx];
                const row = [_][]const u8{ pod.namespace, pod.name, pod.ready, pod.status, pod.cpu_l, pod.mem_l, pod.ip, pod.node, pod.age };
                try rows_data.append(self.allocator, &row);
            }

            // Free old cache if exists
            if (self.cached_col_widths) |*old_widths| {
                old_widths.deinit();
            }

            // Calculate and cache new widths
            self.cached_col_widths = try table_layout.calculateColumnWidths(
                self.allocator,
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
        const header_y = y + 1;
        var col_x = x + 1;
        // Map column index to sort column id (only for sortable columns)
        const col_sort_ids = [_]?u8{ null, COL_NAME, COL_READY, COL_STATUS, null, null, null, null, COL_AGE };
        for (col_names, col_widths.widths, 0..) |name, w, col_i| {
            if (w == 0) continue; // Skip hidden columns

            try terminal.setCursor(col_x, header_y);
            try terminal.writeAll(self.theme.title);

            // Add sort indicator if this column is sorted
            const indicator = if (col_i < col_sort_ids.len)
                if (col_sort_ids[col_i]) |sid|
                    sort_util.sortIndicator(self.sort_column, self.sort_ascending, sid)
                else
                    ""
            else
                "";

            const header_with_indicator = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ name, indicator });
            defer self.allocator.free(header_with_indicator);

            // Truncate header if needed
            const header_text = if (header_with_indicator.len > w)
                try table_layout.truncateText(self.allocator, header_with_indicator, w, false)
            else
                header_with_indicator;
            // Only free if truncateText allocated a new string
            defer if (header_text.ptr != header_with_indicator.ptr) self.allocator.free(header_text);

            try terminal.writeAll(header_text);
            try terminal.writeAll("\x1b[0m");
            col_x += w + 1;
        }

        // Show empty message if no pods
        if (self.filtered_indices.items.len == 0) {
            const Theme = @import("../theme.zig");
            const empty_msg = "No pods found";
            try Theme.writeStringWithTheme(terminal, x + 2, y + height / 2, empty_msg, self.theme.inactive_fg, self.theme.main_bg);
            return;
        }

        // Draw pod rows
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + self.visible_rows, self.filtered_indices.items.len);

        for (start_row..end_row, 0..) |filter_idx, display_idx| {
            const pod_idx = self.filtered_indices.items[filter_idx];
            const pod = self.pods.items[pod_idx];
            const row_y = header_y + @as(u16, @intCast(display_idx)) + 1;
            const is_selected = filter_idx == self.selected_row;

            // Highlight selected row
            if (is_selected) {
                try terminal.setCursor(x + 1, row_y);
                try terminal.writeAll(self.theme.selected_bg);
                var spaces_buf: [256]u8 = undefined;
                @memset(&spaces_buf, ' ');
                var remaining: usize = width - 2;
                while (remaining > 0) {
                    const chunk = @min(remaining, spaces_buf.len);
                    try terminal.writeAll(spaces_buf[0..chunk]);
                    remaining -= chunk;
                }
                try terminal.writeAll("\x1b[0m");
            }

            // Draw pod data with adaptive widths
            col_x = x + 1;
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
                    try table_layout.truncateText(self.allocator, data, w, true)
                else
                    try self.allocator.dupe(u8, data);
                defer self.allocator.free(cell_text);

                try terminal.writeAll(cell_text);
                try terminal.writeAll("\x1b[0m");
                col_x += w + 1;
            }
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *PodsView = @ptrCast(@alignCast(ptr));

        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    try self.navigateDown();
                    return .handled;
                },
                'k' => {
                    try self.navigateUp();
                    return .handled;
                },
                'g' => {
                    try self.gotoTop();
                    return .handled;
                },
                'h' => {
                    self.horizontal_scroll.scrollLeft(5);
                    return .handled;
                },
                'l' => return .request_logs,
                'd' => return .request_describe,
                'y' => return .request_yaml,
                'r' => {
                    self.refresh() catch |err| {
                        Logger.err("Failed to refresh pods: {any}", .{err});
                    };
                    return .handled;
                },
                '0' => {
                    // Toggle all namespaces
                    self.show_all_namespaces = !self.show_all_namespaces;
                    self.refresh() catch |err| {
                        Logger.err("Failed to refresh pods after toggling namespaces: {any}", .{err});
                    };
                    return .handled;
                },
                '$' => {
                    self.horizontal_scroll.scrollToEnd();
                    return .handled;
                },
                'N' => {
                    sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_NAME);
                    self.applySorting();
                    return .handled;
                },
                'S' => {
                    sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_STATUS);
                    self.applySorting();
                    return .handled;
                },
                'A' => {
                    sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_AGE);
                    self.applySorting();
                    return .handled;
                },
                'R' => {
                    sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_READY);
                    self.applySorting();
                    return .handled;
                },
                '/' => return .request_filter,
                ':' => return .request_command_palette,
                '?' => return .request_command_palette, // Help
                else => return .not_handled,
            },
            .up => {
                try self.navigateUp();
                return .handled;
            },
            .down => {
                try self.navigateDown();
                return .handled;
            },
            .home => {
                try self.gotoTop();
                return .handled;
            },
            .end => {
                try self.gotoBottom();
                return .handled;
            },
            .shift_g => {
                try self.gotoBottom();
                return .handled;
            },
            .page_up => {
                try self.pageUp();
                return .handled;
            },
            .page_down => {
                try self.pageDown();
                return .handled;
            },
            .escape => {
                if (self.filter_text.len > 0) {
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
            if (self.error_message == null) {
                self.error_message = self.allocator.dupe(u8, "Unexpected error during refresh") catch {
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

    fn deinit(ptr: *anyopaque) void {
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        self.cleanup();
    }
};
