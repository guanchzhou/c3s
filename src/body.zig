const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const Color = @import("terminal.zig").Color;
const BoxDrawing = @import("box_drawing.zig");
const Theme = @import("theme.zig");
const json = std.json;

const Pod = struct {
    namespace: []const u8,
    name: []const u8,
    pf: bool,
    ready: []const u8,
    status: []const u8,
    restarts: u32,
    cpu: u32,
    cpu_r: u32,
    cpu_l: []const u8,
    mem: u32,
    mem_r: u32,
    mem_l: []const u8,
    ip: []const u8,
    node: []const u8,
    age: []const u8,
};

pub const Body = struct {
    allocator: std.mem.Allocator,
    pods: std.ArrayListUnmanaged(Pod),
    filtered_indices: std.ArrayListUnmanaged(usize),
    filter_text: []const u8,
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    last_selected_row: u32 = 0, // Track previous selection for minimal redraw
    last_scroll_offset: u32 = 0, // Track previous scroll for minimal redraw
    title: []const u8 = "pods(all)[7]", // Dynamic title that can change
    allocated_title: ?[]u8 = null, // Track if title was allocated
    visible_rows: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) !Body {
        var pods = std.ArrayListUnmanaged(Pod){};
        // Attempt to load real pods via kubectl
        var arena_temp = std.heap.ArenaAllocator.init(allocator);
        defer arena_temp.deinit();
        const temp_allocator = arena_temp.allocator();

        var child = std.process.Child.init(&[_][]const u8{"kubectl", "--context=rancher-desktop", "get", "pods", "-A", "-o", "json"}, temp_allocator);
        child.stdout_behavior = .Pipe;
        if (child.spawn() catch null) |_| {
            if (child.stdout) |stdout_pipe| {
                const data = stdout_pipe.readToEndAlloc(temp_allocator, 1024 * 1024) catch null;
                if (data) |buf| {
                    const parsed = json.parseFromSliceLeaky(json.Value, temp_allocator, buf, .{}) catch null;
                    if (parsed) |root| {
                        const items = root.object.get("items") orelse null;
                        if (items) |arr| {
                            if (arr.array.items.len > 0) {
                                var count: usize = 0;
                                while (count < arr.array.items.len and count < 20) : (count += 1) {
                                    const item = arr.array.items[count];
                                    const meta = item.object.get("metadata") orelse continue;
                                    const status = item.object.get("status") orelse continue;
                                    const namespace = meta.object.get("namespace") orelse continue;
                                    const name = meta.object.get("name") orelse continue;
                                    const phase = status.object.get("phase") orelse continue;

                                    const ns = try allocator.dupe(u8, namespace.string);
                                    const nm = try allocator.dupe(u8, name.string);
                                    const ph = try allocator.dupe(u8, phase.string);

                                    try pods.append(allocator, Pod{
                                        .namespace = ns,
                                        .name = nm,
                                        .pf = false,
                                        .ready = try allocator.dupe(u8, "-"),
                                        .status = ph,
                                        .restarts = 0,
                                        .cpu = 0,
                                        .cpu_r = 0,
                                        .cpu_l = try allocator.dupe(u8, "n/a"),
                                        .mem = 0,
                                        .mem_r = 0,
                                        .mem_l = try allocator.dupe(u8, "n/a"),
                                        .ip = try allocator.dupe(u8, "-"),
                                        .node = try allocator.dupe(u8, "-"),
                                        .age = try allocator.dupe(u8, "-"),
                                    });
                                }
                            }
                        }
                    }
                }
            }
            _ = child.wait() catch {};
        }

        if (pods.items.len == 0) {
            try pods.append(allocator, Pod{
                .namespace = try allocator.dupe(u8, "kube-system"),
                .name = try allocator.dupe(u8, "coredns-5688667fd4-5lznl"),
                .pf = true,
                .ready = try allocator.dupe(u8, "1/1"),
                .status = try allocator.dupe(u8, "Running"),
                .restarts = 7,
                .cpu = 2,
                .cpu_r = 2,
                .cpu_l = try allocator.dupe(u8, "n/a"),
                .mem = 69,
                .mem_r = 99,
                .mem_l = try allocator.dupe(u8, "n/a"),
                .ip = try allocator.dupe(u8, "10.42.0.207"),
                .node = try allocator.dupe(u8, "lima-rancher-desktop"),
                .age = try allocator.dupe(u8, "33d"),
            });

            try pods.append(allocator, Pod{
                .namespace = try allocator.dupe(u8, "kube-system"),
                .name = try allocator.dupe(u8, "helm-install-traefik-bm65l"),
                .pf = true,
                .ready = try allocator.dupe(u8, "0/1"),
                .status = try allocator.dupe(u8, "Completed"),
                .restarts = 0,
                .cpu = 0,
                .cpu_r = 0,
                .cpu_l = try allocator.dupe(u8, "n/a"),
                .mem = 0,
                .mem_r = 0,
                .mem_l = try allocator.dupe(u8, "n/a"),
                .ip = try allocator.dupe(u8, "10.42.0.200"),
                .node = try allocator.dupe(u8, "lima-rancher-desktop"),
                .age = try allocator.dupe(u8, "33d"),
            });

            try pods.append(allocator, Pod{
                .namespace = try allocator.dupe(u8, "kube-system"),
                .name = try allocator.dupe(u8, "helm-install-traefik-crd-8wmzj"),
                .pf = true,
                .ready = try allocator.dupe(u8, "0/1"),
                .status = try allocator.dupe(u8, "Completed"),
                .restarts = 0,
                .cpu = 0,
                .cpu_r = 0,
                .cpu_l = try allocator.dupe(u8, "n/a"),
                .mem = 0,
                .mem_r = 0,
                .mem_l = try allocator.dupe(u8, "n/a"),
                .ip = try allocator.dupe(u8, "10.42.0.201"),
                .node = try allocator.dupe(u8, "lima-rancher-desktop"),
                .age = try allocator.dupe(u8, "33d"),
            });

            try pods.append(allocator, Pod{
                .namespace = try allocator.dupe(u8, "kube-system"),
                .name = try allocator.dupe(u8, "local-path-provisioner-774c6665dc-244hc"),
                .pf = true,
                .ready = try allocator.dupe(u8, "1/1"),
                .status = try allocator.dupe(u8, "Running"),
                .restarts = 0,
                .cpu = 0,
                .cpu_r = 0,
                .cpu_l = try allocator.dupe(u8, "n/a"),
                .mem = 0,
                .mem_r = 0,
                .mem_l = try allocator.dupe(u8, "n/a"),
                .ip = try allocator.dupe(u8, "10.42.0.202"),
                .node = try allocator.dupe(u8, "lima-rancher-desktop"),
                .age = try allocator.dupe(u8, "33d"),
            });

            try pods.append(allocator, Pod{
                .namespace = try allocator.dupe(u8, "kube-system"),
                .name = try allocator.dupe(u8, "metrics-server-6f4c6665dc-qzgqt"),
                .pf = true,
                .ready = try allocator.dupe(u8, "1/1"),
                .status = try allocator.dupe(u8, "Running"),
                .restarts = 0,
                .cpu = 0,
                .cpu_r = 0,
                .cpu_l = try allocator.dupe(u8, "n/a"),
                .mem = 0,
                .mem_r = 0,
                .mem_l = try allocator.dupe(u8, "n/a"),
                .ip = try allocator.dupe(u8, "10.42.0.203"),
                .node = try allocator.dupe(u8, "lima-rancher-desktop"),
                .age = try allocator.dupe(u8, "33d"),
            });
        }

        try pods.append(allocator, Pod{
            .namespace = try allocator.dupe(u8, "kube-system"),
            .name = try allocator.dupe(u8, "svclb-traefik-79dca93b-4757q"),
            .pf = true,
            .ready = try allocator.dupe(u8, "1/1"),
            .status = try allocator.dupe(u8, "Running"),
            .restarts = 0,
            .cpu = 0,
            .cpu_r = 0,
            .cpu_l = try allocator.dupe(u8, "n/a"),
            .mem = 0,
            .mem_r = 0,
            .mem_l = try allocator.dupe(u8, "n/a"),
            .ip = try allocator.dupe(u8, "10.42.0.204"),
            .node = try allocator.dupe(u8, "lima-rancher-desktop"),
            .age = try allocator.dupe(u8, "33d"),
        });

        try pods.append(allocator, Pod{
            .namespace = try allocator.dupe(u8, "kube-system"),
            .name = try allocator.dupe(u8, "traefik-c98fdf6fb-kmbnk"),
            .pf = true,
            .ready = try allocator.dupe(u8, "1/1"),
            .status = try allocator.dupe(u8, "Running"),
            .restarts = 0,
            .cpu = 0,
            .cpu_r = 0,
            .cpu_l = try allocator.dupe(u8, "n/a"),
            .mem = 0,
            .mem_r = 0,
            .mem_l = try allocator.dupe(u8, "n/a"),
            .ip = try allocator.dupe(u8, "10.42.0.205"),
            .node = try allocator.dupe(u8, "lima-rancher-desktop"),
            .age = try allocator.dupe(u8, "33d"),
        });

        var body = Body{
            .allocator = allocator,
            .pods = pods,
            .filtered_indices = std.ArrayListUnmanaged(usize){},
            .filter_text = "",
        };
        
        // Initialize filter with all pods visible
        try body.applyFilter("");
        
        return body;
    }

    pub fn deinit(self: *Body) void {
        // Deallocate individual strings in pods if they were duplicated
        if (self.pods.items.len > 0) {
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
        }
        self.pods.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        if (self.allocated_title) |allocated| {
            self.allocator.free(allocated);
        }
    }
    
    pub fn applyFilter(self: *Body, filter: []const u8) !void {
        self.filter_text = filter;
        self.filtered_indices.clearRetainingCapacity();
        
        // Free previously allocated title if exists
        if (self.allocated_title) |allocated| {
            self.allocator.free(allocated);
            self.allocated_title = null;
        }
        
        // If no filter, include all pods
        if (filter.len == 0) {
            for (0..self.pods.items.len) |i| {
                try self.filtered_indices.append(self.allocator, i);
            }
            self.selected_row = 0;
            self.scroll_offset = 0;
            self.title = "pods(all)[7]";
            return;
        }
        
        // Filter pods - check if filter text appears in any column
        for (self.pods.items, 0..) |pod, i| {
            const matches = 
                std.mem.containsAtLeast(u8, pod.namespace, 1, filter) or
                std.mem.containsAtLeast(u8, pod.name, 1, filter) or
                std.mem.containsAtLeast(u8, pod.status, 1, filter) or
                std.mem.containsAtLeast(u8, pod.ready, 1, filter) or
                std.mem.containsAtLeast(u8, pod.ip, 1, filter) or
                std.mem.containsAtLeast(u8, pod.node, 1, filter) or
                std.mem.containsAtLeast(u8, pod.age, 1, filter);
            
            if (matches) {
                try self.filtered_indices.append(self.allocator, i);
            }
        }
        
        // Reset selection to first filtered item
        self.selected_row = 0;
        self.scroll_offset = 0;
        
        // Update title to show the actual filter
        const filtered_count = self.filtered_indices.items.len;
        const new_title = try std.fmt.allocPrint(
            self.allocator,
            "pods(all)[{d}] </{s}>",
            .{ filtered_count, filter }
        );
        self.allocated_title = new_title;
        self.title = new_title;
    }
    

    pub fn render(self: *Body, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        // Create a border around the entire body with btop theme colors and rounded corners (no title)
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, Theme.proc_box, Theme.main_bg, null, .rounded);
        
        // Render custom title with colored text
        const title_x = x + 2;
        const title_y = y;
        try Theme.writeText(terminal, title_x, title_y, BoxDrawing.Symbols.title_left, Theme.proc_box);
        
        var current_x = title_x + 1;
        
        // Render "pods"
        try terminal.setCursor(current_x, title_y);
        try terminal.writeAll(Theme.title);
        try terminal.writeAll("pods");
        current_x += 4;
        
        // Render "(" 
        try terminal.writeAll("(");
        current_x += 1;
        
        // Check if we have a filter or showing "all"
        const is_filtered = self.filter_text.len > 0;
        if (!is_filtered) {
            // Render "all" in yellow highlight
            try terminal.writeAll(Theme.title_highlight);
            try terminal.writeAll("all");
            try terminal.writeAll(Theme.title);
            current_x += 3;
        } else {
            // Render "all" in normal color when filtered
            try terminal.writeAll("all");
            current_x += 3;
        }
        
        // Render ")[count]"
        try terminal.writeAll(")");
        current_x += 1;
        
        // Render count
        var count_buf: [16]u8 = undefined;
        const count_str = std.fmt.bufPrint(&count_buf, "[{d}]", .{self.filtered_indices.items.len}) catch "[?]";
        try terminal.writeAll(count_str);
        current_x += @as(u16, @intCast(count_str.len));
        
        // Render filter if active
        if (is_filtered) {
            try terminal.writeAll(" ");
            try terminal.writeAll(Theme.hi_fg);
            try terminal.writeAll("</");
            try terminal.writeAll(self.filter_text);
            try terminal.writeAll(">");
            try terminal.writeAll(Theme.title);
            current_x += @as(u16, @intCast(3 + self.filter_text.len + 1));
        }
        
        try terminal.writeAll(Theme.reset);
        try Theme.writeText(terminal, current_x, title_y, BoxDrawing.Symbols.title_right, Theme.proc_box);

        // Table header - offset by 1 for border
        const header_y = y + 1;
        const columns = [_]struct { name: []const u8, width: u16 }{
            .{ .name = "NAMESPACE+", .width = 12 },
            .{ .name = "NAME", .width = 30 },
            .{ .name = "PF", .width = 3 },
            .{ .name = "READY", .width = 6 },
            .{ .name = "STATUS", .width = 10 },
            .{ .name = "RESTARTS", .width = 9 },
            .{ .name = "CPU", .width = 4 },
            .{ .name = "%CPU/R", .width = 7 },
            .{ .name = "%CPU/L", .width = 7 },
            .{ .name = "MEM", .width = 4 },
            .{ .name = "%MEM/R", .width = 7 },
            .{ .name = "%MEM/L", .width = 7 },
            .{ .name = "IP", .width = 15 },
            .{ .name = "NODE", .width = 20 },
            .{ .name = "AGE", .width = 6 },
        };
        // Compute scaled widths to fill entire available width
        const cols_len = columns.len;
        var scaled: [cols_len]u16 = undefined;
        var total_base: u32 = 0;
        for (columns) |c| total_base += c.width;
        if (total_base == 0) total_base = 1;

        var used: u16 = 0;
        var i: usize = 0;
        while (i < cols_len - 1) : (i += 1) {
            const w = @as(u16, @intCast((@as(u32, columns[i].width) * @as(u32, width)) / total_base));
            const ww: u16 = if (w == 0) 1 else w;
            scaled[i] = ww;
            used += ww;
        }
        // Last column absorbs remaining to fit exactly
        scaled[cols_len - 1] = if (width > used) width - used else 1;

        var col_x = x + 1; // Offset by 1 for border
        i = 0;
        while (i < cols_len) : (i += 1) {
            try Theme.writeStringWithTheme(terminal, col_x, header_y, columns[i].name, Theme.title, Theme.main_bg);
            col_x += scaled[i];
        }

        // Table rows
        const visible_rows = if (height > 3) height - 3 else 0;
        self.visible_rows = @intCast(visible_rows);
        
        // Use filtered indices count
        const total_visible = self.filtered_indices.items.len;
        
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + visible_rows, total_visible);

        for (start_row..end_row, 0..) |filter_idx, display_idx| {
            const pod_idx = self.filtered_indices.items[filter_idx];
            const pod = self.pods.items[pod_idx];
            const row_y = header_y + @as(u16, @intCast(display_idx)) + 1;

            // Paint entire row background first (default or selected color)
            const is_selected = filter_idx == self.selected_row;
            const bg_color = if (is_selected) Theme.selected_bg else Theme.main_bg;
            const fg_color = if (is_selected) Theme.selected_fg else Theme.main_fg;
            
            // Use efficient fillRow instead of per-character writes
            if (width > 2) {
                try terminal.fillRow(x + 1, row_y, width - 2, fg_color, bg_color);
            }

            col_x = x + 1; // Offset by 1 for border

            // NAMESPACE+
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pod.namespace, fg_color, bg_color);
            col_x += scaled[0];

            // NAME
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pod.name, fg_color, bg_color);
            col_x += scaled[1];

            // PF
            const pf_char = if (pod.pf) "•" else " ";
            const pf_color = if (pod.pf) Theme.status_running else fg_color;
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pf_char, pf_color, bg_color);
            col_x += scaled[2];

            // READY
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pod.ready, fg_color, bg_color);
            col_x += scaled[3];

            // STATUS
            const status_color = if (std.mem.eql(u8, pod.status, "Running")) Theme.status_running else fg_color;
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pod.status, status_color, bg_color);
            col_x += scaled[4];

            // RESTARTS - use stack buffer instead of heap allocation
            var restarts_buf: [16]u8 = undefined;
            const restarts_str = std.fmt.bufPrint(&restarts_buf, "{}", .{pod.restarts}) catch unreachable;
            try Theme.writeStringWithTheme(terminal, col_x, row_y, restarts_str, fg_color, bg_color);
            col_x += scaled[5];

            // CPU - use stack buffer
            var cpu_buf: [16]u8 = undefined;
            const cpu_str = std.fmt.bufPrint(&cpu_buf, "{}", .{pod.cpu}) catch unreachable;
            try Theme.writeStringWithTheme(terminal, col_x, row_y, cpu_str, fg_color, bg_color);
            col_x += scaled[6];

            // %CPU/R - use stack buffer
            var cpu_r_buf: [16]u8 = undefined;
            const cpu_r_str = std.fmt.bufPrint(&cpu_r_buf, "{}", .{pod.cpu_r}) catch unreachable;
            try Theme.writeStringWithTheme(terminal, col_x, row_y, cpu_r_str, fg_color, bg_color);
            col_x += scaled[7];

            // %CPU/L
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pod.cpu_l, fg_color, bg_color);
            col_x += scaled[8];

            // MEM - use stack buffer
            var mem_buf: [16]u8 = undefined;
            const mem_str = std.fmt.bufPrint(&mem_buf, "{}", .{pod.mem}) catch unreachable;
            try Theme.writeStringWithTheme(terminal, col_x, row_y, mem_str, fg_color, bg_color);
            col_x += scaled[9];

            // %MEM/R - use stack buffer
            var mem_r_buf: [16]u8 = undefined;
            const mem_r_str = std.fmt.bufPrint(&mem_r_buf, "{}", .{pod.mem_r}) catch unreachable;
            try Theme.writeStringWithTheme(terminal, col_x, row_y, mem_r_str, fg_color, bg_color);
            col_x += scaled[10];

            // %MEM/L
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pod.mem_l, fg_color, bg_color);
            col_x += scaled[11];

            // IP
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pod.ip, fg_color, bg_color);
            col_x += scaled[12];

            // NODE
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pod.node, fg_color, bg_color);
            col_x += scaled[13];

            // AGE
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pod.age, fg_color, bg_color);
        }
        // Bottom border is already rendered by createBox
    }

    fn viewportHeight(self: *const Body) u32 {
        return if (self.visible_rows == 0) 1 else self.visible_rows;
    }

    pub fn navigateUp(self: *Body) !void {
        if (self.selected_row > 0) {
            self.last_selected_row = self.selected_row;
            self.last_scroll_offset = self.scroll_offset;
            self.selected_row -= 1;
            // Adjust scroll if needed
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        }
    }

    pub fn navigateDown(self: *Body) !void {
        const total_items = self.filtered_indices.items.len;
        
        if (total_items > 0 and self.selected_row < total_items - 1) {
            self.last_selected_row = self.selected_row;
            self.last_scroll_offset = self.scroll_offset;
            self.selected_row += 1;
            const visible = self.viewportHeight();
            if (self.selected_row >= self.scroll_offset + visible) {
                self.scroll_offset = self.selected_row - visible + 1;
            }
        }
    }

    pub fn navigateLeft(self: *Body) !void {
        // TODO: Implement column navigation
        _ = self;
    }

    // Title management methods
    pub fn setTitle(self: *Body, title: []const u8) void {
        self.title = title;
    }

    pub fn setHelpMode(self: *Body, help_visible: bool) void {
        if (help_visible) {
            self.title = "Help";
        } else {
            self.title = "pods(all)[7]";
        }
    }

        pub fn navigateRight(self: *Body) !void {
            // TODO: Implement column navigation
            _ = self;
        }

        // Navigation methods
        pub fn gotoTop(self: *Body) !void {
            self.selected_row = 0;
            self.scroll_offset = 0;
        }

        pub fn gotoBottom(self: *Body) !void {
            const total_items = self.filtered_indices.items.len;
            
            if (total_items > 0) {
                self.selected_row = @intCast(total_items - 1);
                const visible = self.viewportHeight();
                if (self.selected_row >= visible) {
                    self.scroll_offset = self.selected_row - visible + 1;
                } else {
                    self.scroll_offset = 0;
                }
            }
        }

        pub fn pageUp(self: *Body) !void {
            const page = self.viewportHeight();
            if (self.selected_row >= page) {
                self.selected_row -= page;
            } else {
                self.selected_row = 0;
            }
            // Adjust scroll if needed
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        }

        pub fn pageDown(self: *Body) !void {
            const total_items = self.filtered_indices.items.len;
            
            const page = self.viewportHeight();
            if (total_items > 0 and self.selected_row + page < total_items) {
                self.selected_row += page;
            } else {
                self.selected_row = @intCast(total_items - 1);
            }
            // Adjust scroll if needed
            const visible_rows = self.viewportHeight();
            if (self.selected_row >= self.scroll_offset + visible_rows) {
                self.scroll_offset = self.selected_row - visible_rows + 1;
            }
        }

        // Resource management methods
        pub fn refresh(self: *Body) !void {
            // TODO: Implement refresh logic
            _ = self;
        }

        pub fn describe(self: *Body) !void {
            // TODO: Implement describe logic
            _ = self;
        }

        pub fn edit(self: *Body) !void {
            // TODO: Implement edit logic
            _ = self;
        }

        pub fn logs(self: *Body) !void {
            // TODO: Implement logs logic
            _ = self;
        }

        pub fn shell(self: *Body) !void {
            // TODO: Implement shell logic
            _ = self;
        }

        pub fn yaml(self: *Body) !void {
            // TODO: Implement yaml logic
            _ = self;
        }

        pub fn attach(self: *Body) !void {
            // TODO: Implement attach logic
            _ = self;
        }

        pub fn copy(self: *Body) !void {
            // TODO: Implement copy logic
            _ = self;
        }

        pub fn copyNamespace(self: *Body) !void {
            // TODO: Implement copy namespace logic
            _ = self;
        }

        pub fn setImage(self: *Body) !void {
            // TODO: Implement set image logic
            _ = self;
        }

        pub fn showNode(self: *Body) !void {
            // TODO: Implement show node logic
            _ = self;
        }

        pub fn portForward(self: *Body) !void {
            // TODO: Implement port forward logic
            _ = self;
        }

        pub fn transfer(self: *Body) !void {
            // TODO: Implement transfer logic
            _ = self;
        }

        pub fn sanitize(self: *Body) !void {
            // TODO: Implement sanitize logic
            _ = self;
        }

        // Sorting methods
        pub fn sortByAge(self: *Body) !void {
            // TODO: Implement sort by age
            _ = self;
        }

        pub fn sortByCpu(self: *Body) !void {
            // TODO: Implement sort by CPU
            _ = self;
        }

        pub fn sortByCpuR(self: *Body) !void {
            // TODO: Implement sort by CPU/R
            _ = self;
        }

        pub fn sortByCpuL(self: *Body) !void {
            // TODO: Implement sort by CPU/L
            _ = self;
        }

        pub fn sortByIp(self: *Body) !void {
            // TODO: Implement sort by IP
            _ = self;
        }

        pub fn sortByMem(self: *Body) !void {
            // TODO: Implement sort by MEM
            _ = self;
        }

        pub fn sortByMemR(self: *Body) !void {
            // TODO: Implement sort by MEM/R
            _ = self;
        }

        pub fn sortByMemL(self: *Body) !void {
            // TODO: Implement sort by MEM/L
            _ = self;
        }

        pub fn sortByName(self: *Body) !void {
            // TODO: Implement sort by name
            _ = self;
        }

        pub fn sortByNamespace(self: *Body) !void {
            // TODO: Implement sort by namespace
            _ = self;
        }

        pub fn sortByNode(self: *Body) !void {
            // TODO: Implement sort by node
            _ = self;
        }

        pub fn sortByReady(self: *Body) !void {
            // TODO: Implement sort by ready
            _ = self;
        }

        pub fn sortByRestart(self: *Body) !void {
            // TODO: Implement sort by restart
            _ = self;
        }

        pub fn sortByStatus(self: *Body) !void {
            // TODO: Implement sort by status
            _ = self;
        }

        // General methods
        pub fn mark(self: *Body) !void {
            // TODO: Implement mark logic
            _ = self;
        }

        pub fn markClear(self: *Body) !void {
            // TODO: Implement mark clear logic
            _ = self;
        }

        pub fn markRange(self: *Body) !void {
            // TODO: Implement mark range logic
            _ = self;
        }

        pub fn toggleWide(self: *Body) !void {
            // TODO: Implement toggle wide logic
            _ = self;
        }

        pub fn toggleFaults(self: *Body) !void {
            // TODO: Implement toggle faults logic
            _ = self;
        }

        pub fn toggleHeader(self: *Body) !void {
            self.dirty = true;
        }

        pub fn toggleCrumbs(self: *Body) !void {
            // TODO: Implement toggle crumbs logic
            _ = self;
        }
};
