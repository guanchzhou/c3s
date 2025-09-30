const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");

/// PodsView - displays Kubernetes pods with filtering and navigation
pub const PodsView = struct {
    allocator: std.mem.Allocator,
    theme: *theme_loader.ThemeColors,
    pods: std.ArrayListUnmanaged(Pod),
    filtered_indices: std.ArrayListUnmanaged(usize),
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    filter_text: []const u8 = "",
    visible_rows: u32 = 0,
    allocated_title: ?[]u8 = null,
    
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
    };
    
    pub fn init(allocator: std.mem.Allocator, theme: *theme_loader.ThemeColors) !PodsView {
        var view = PodsView{
            .allocator = allocator,
            .theme = theme,
            .pods = std.ArrayListUnmanaged(Pod){},
            .filtered_indices = std.ArrayListUnmanaged(usize){},
        };
        
        // Load sample data
        try view.loadSampleData();
        try view.applyFilter("");
        
        return view;
    }
    
    pub fn cleanup(self: *PodsView) void {
        // Deallocate individual strings in pods
        for (self.pods.items) |pod| {
            if (pod.namespace.len > 0) self.allocator.free(pod.namespace);
            if (pod.name.len > 0) self.allocator.free(pod.name);
            if (pod.ready.len > 0) self.allocator.free(pod.ready);
            if (pod.status.len > 0) self.allocator.free(pod.status);
            if (pod.cpu_l.len > 0 and pod.cpu_l.ptr != "n/a".ptr) self.allocator.free(pod.cpu_l);
            if (pod.mem_l.len > 0 and pod.mem_l.ptr != "n/a".ptr) self.allocator.free(pod.mem_l);
            if (pod.ip.len > 0 and pod.ip.ptr != "-".ptr) self.allocator.free(pod.ip);
            if (pod.node.len > 0 and pod.node.ptr != "-".ptr) self.allocator.free(pod.node);
            if (pod.age.len > 0 and pod.age.ptr != "-".ptr) self.allocator.free(pod.age);
        }
        self.pods.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        if (self.allocated_title) |allocated| {
            self.allocator.free(allocated);
        }
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
        
        // Remember the currently selected pod index (if any)
        const old_selected_pod_idx = if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len)
            self.filtered_indices.items[self.selected_row]
        else
            null;
        
        self.filter_text = filter;
        self.filtered_indices.clearRetainingCapacity();
        
        if (filter.len == 0) {
            // No filter - show all pods
            for (0..self.pods.items.len) |i| {
                try self.filtered_indices.append(self.allocator, i);
            }
        } else {
            // Apply filter
            for (self.pods.items, 0..) |pod, i| {
                if (std.mem.indexOf(u8, pod.name, filter) != null or
                    std.mem.indexOf(u8, pod.namespace, filter) != null) {
                    try self.filtered_indices.append(self.allocator, i);
                }
            }
        }
        
        // Try to restore selection to the same pod if it's still in the filtered list
        if (old_selected_pod_idx) |pod_idx| {
            for (self.filtered_indices.items, 0..) |filtered_pod_idx, i| {
                if (filtered_pod_idx == pod_idx) {
                    self.selected_row = @intCast(i);
                    // Adjust scroll to keep selection visible
                    if (self.selected_row < self.scroll_offset) {
                        self.scroll_offset = self.selected_row;
                    } else if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset = if (self.selected_row >= self.visible_rows)
                            self.selected_row - self.visible_rows + 1
                        else
                            0;
                    }
                    return;
                }
            }
        }
        
        // If we couldn't restore the selection, reset to top
        self.selected_row = 0;
        self.scroll_offset = 0;
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
        if (self.selected_row < self.filtered_indices.items.len - 1) {
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
        .deinit = deinit,
    };
    
    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        
        self.visible_rows = if (height > 3) height - 3 else 0;
        
        // Draw box border using theme colors
        const BoxDrawing = @import("../ui/box_drawing.zig");
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, self.theme.proc_box, self.theme.main_bg, null, .rounded);
        
        // Draw title with filter info
        var title_buf: [256]u8 = undefined;
        const title_text = if (self.filter_text.len > 0)
            try std.fmt.bufPrint(&title_buf, "pods(all)[{d}] </{s}>", .{ self.filtered_indices.items.len, self.filter_text })
        else
            try std.fmt.bufPrint(&title_buf, "pods(all)[{d}]", .{self.filtered_indices.items.len});
        
        // Draw title with proper theme colors
        try terminal.setCursor(x + 1, y);
        try terminal.writeAll(self.theme.title);
        try terminal.writeAll(title_text);
        try terminal.writeAll("\x1b[0m"); // Reset colors
        
        // Draw column headers
        const header_y = y + 1;
        const col_widths = [_]u16{ 12, 25, 8, 10, 8, 8, 15, 12, 8 };
        const col_names = [_][]const u8{ "NAMESPACE", "NAME", "READY", "STATUS", "CPU", "MEM", "IP", "NODE", "AGE" };
        
        var col_x = x + 1;
        for (col_names, 0..) |name, i| {
            try terminal.setCursor(col_x, header_y);
            try terminal.writeAll(self.theme.title);
            try terminal.writeAll(name);
            try terminal.writeAll("\x1b[0m");
            col_x += col_widths[i] + 1;
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
            
            // Draw pod data with theme colors
            col_x = x + 1;
            const pod_data = [_][]const u8{ pod.namespace, pod.name, pod.ready, pod.status, pod.cpu_l, pod.mem_l, pod.ip, pod.node, pod.age };
            
            for (pod_data, 0..) |data, i| {
                try terminal.setCursor(col_x, row_y);
                if (is_selected) {
                    try terminal.writeAll(self.theme.selected_fg);
                    try terminal.writeAll(self.theme.selected_bg);
                } else {
                    try terminal.writeAll(self.theme.main_fg);
                }
                try terminal.writeAll(data);
                try terminal.writeAll("\x1b[0m");
                col_x += col_widths[i] + 1;
            }
        }
    }
    
    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        
        switch (key) {
            .char => |c| switch (c) {
                'j' => { try self.navigateDown(); return .handled; },
                'k' => { try self.navigateUp(); return .handled; },
                'g' => { try self.gotoTop(); return .handled; },
                'G' => { try self.gotoBottom(); return .handled; },
                '/' => return .request_filter,
                ':' => return .request_command_palette,
                '?' => return .request_command_palette, // Help
                else => return .not_handled,
            },
            .up => { try self.navigateUp(); return .handled; },
            .down => { try self.navigateDown(); return .handled; },
            .home => { try self.gotoTop(); return .handled; },
            .end => { try self.gotoBottom(); return .handled; },
            .page_up => { try self.pageUp(); return .handled; },
            .page_down => { try self.pageDown(); return .handled; },
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
        _ = ptr;
        Logger.info("PodsView: View activated", .{});
    }
    
    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("PodsView: View deactivated", .{});
    }
    
    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "pods";
    }
    
    fn deinit(ptr: *anyopaque) void {
        const self: *PodsView = @ptrCast(@alignCast(ptr));
        self.cleanup();
    }
};
