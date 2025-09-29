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
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    last_selected_row: u32 = 0, // Track previous selection for minimal redraw
    last_scroll_offset: u32 = 0, // Track previous scroll for minimal redraw
    title: []const u8 = "pods(all)[7]", // Dynamic title that can change

    pub fn init(allocator: std.mem.Allocator) !Body {
        var pods = std.ArrayListUnmanaged(Pod){};
        // Attempt to load real pods via kubectl
        var arena = std.heap.ArenaAllocator.init(allocator);
        defer arena.deinit();
        const a = arena.allocator();

            var child = std.process.Child.init(&[_][]const u8{"kubectl", "--context=rancher-desktop", "get", "pods", "-A", "-o", "json"}, a);
        child.stdout_behavior = .Pipe;
        if (child.spawn() catch null) |_| {
            if (child.stdout) |stdout_pipe| {
                const data = stdout_pipe.readToEndAlloc(a, 1024 * 1024) catch null;
                if (data) |buf| {
                    const parsed = json.parseFromSliceLeaky(json.Value, a, buf, .{}) catch null;
                    if (parsed) |root| {
                        const items = root.object.get("items") orelse null;
                        if (items) |arr| {
                            if (arr.array.items.len > 0) {
                                // Populate a subset for now
                                var count: usize = 0;
                                while (count < arr.array.items.len and count < 20) : (count += 1) {
                                    const item = arr.array.items[count];
                                    const meta = item.object.get("metadata") orelse continue;
                                    const status = item.object.get("status") orelse continue;
                                    const namespace = meta.object.get("namespace") orelse continue;
                                    const name = meta.object.get("name") orelse continue;
                                    const phase = status.object.get("phase") orelse continue;

                                    const ns_s = namespace.string;
                                    const name_s = name.string;
                                    const phase_s = phase.string;

                                    const ns = try std.fmt.allocPrint(allocator, "{s}", .{ns_s});
                                    const nm = try std.fmt.allocPrint(allocator, "{s}", .{name_s});
                                    const ph = try std.fmt.allocPrint(allocator, "{s}", .{phase_s});

                                    try pods.append(allocator, Pod{
                                        .namespace = ns,
                                        .name = nm,
                                        .pf = false,
                                        .ready = "-",
                                        .status = ph,
                                        .restarts = 0,
                                        .cpu = 0,
                                        .cpu_r = 0,
                                        .cpu_l = "n/a",
                                        .mem = 0,
                                        .mem_r = 0,
                                        .mem_l = "n/a",
                                        .ip = "-",
                                        .node = "-",
                                        .age = "-",
                                    });
                                }
                            }
                        }
                    }
                }
            }
            _ = child.wait() catch {};
        }
        
        // Fallback to sample pods when kubectl not available or returned nothing
        if (pods.items.len == 0) {
        // Add some sample pods (similar to the screenshot)
        try pods.append(allocator, Pod{
            .namespace = "kube-system",
            .name = "coredns-5688667fd4-5lznl",
            .pf = true,
            .ready = "1/1",
            .status = "Running",
            .restarts = 7,
            .cpu = 2,
            .cpu_r = 2,
            .cpu_l = "n/a",
            .mem = 69,
            .mem_r = 99,
            .mem_l = "n/a",
            .ip = "10.42.0.207",
            .node = "lima-rancher-desktop",
            .age = "33d",
        });
        
        try pods.append(allocator, Pod{
            .namespace = "kube-system",
            .name = "helm-install-traefik-bm65l",
            .pf = true,
            .ready = "0/1",
            .status = "Completed",
            .restarts = 0,
            .cpu = 0,
            .cpu_r = 0,
            .cpu_l = "n/a",
            .mem = 0,
            .mem_r = 0,
            .mem_l = "n/a",
            .ip = "10.42.0.200",
            .node = "lima-rancher-desktop",
            .age = "33d",
        });
        
        try pods.append(allocator, Pod{
            .namespace = "kube-system",
            .name = "helm-install-traefik-crd-8wmzj",
            .pf = true,
            .ready = "0/1",
            .status = "Completed",
            .restarts = 0,
            .cpu = 0,
            .cpu_r = 0,
            .cpu_l = "n/a",
            .mem = 0,
            .mem_r = 0,
            .mem_l = "n/a",
            .ip = "10.42.0.201",
            .node = "lima-rancher-desktop",
            .age = "33d",
        });
        
        try pods.append(allocator, Pod{
            .namespace = "kube-system",
            .name = "local-path-provisioner-774c6665dc-244hc",
            .pf = true,
            .ready = "1/1",
            .status = "Running",
            .restarts = 0,
            .cpu = 0,
            .cpu_r = 0,
            .cpu_l = "n/a",
            .mem = 0,
            .mem_r = 0,
            .mem_l = "n/a",
            .ip = "10.42.0.202",
            .node = "lima-rancher-desktop",
            .age = "33d",
        });
        
        try pods.append(allocator, Pod{
            .namespace = "kube-system",
            .name = "metrics-server-6f4c6665dc-qzgqt",
            .pf = true,
            .ready = "1/1",
            .status = "Running",
            .restarts = 0,
            .cpu = 0,
            .cpu_r = 0,
            .cpu_l = "n/a",
            .mem = 0,
            .mem_r = 0,
            .mem_l = "n/a",
            .ip = "10.42.0.203",
            .node = "lima-rancher-desktop",
            .age = "33d",
        });
        }
        
        try pods.append(allocator, Pod{
            .namespace = "kube-system",
            .name = "svclb-traefik-79dca93b-4757q",
            .pf = true,
            .ready = "1/1",
            .status = "Running",
            .restarts = 0,
            .cpu = 0,
            .cpu_r = 0,
            .cpu_l = "n/a",
            .mem = 0,
            .mem_r = 0,
            .mem_l = "n/a",
            .ip = "10.42.0.204",
            .node = "lima-rancher-desktop",
            .age = "33d",
        });
        
        try pods.append(allocator, Pod{
            .namespace = "kube-system",
            .name = "traefik-c98fdf6fb-kmbnk",
            .pf = true,
            .ready = "1/1",
            .status = "Running",
            .restarts = 0,
            .cpu = 0,
            .cpu_r = 0,
            .cpu_l = "n/a",
            .mem = 0,
            .mem_r = 0,
            .mem_l = "n/a",
            .ip = "10.42.0.205",
            .node = "lima-rancher-desktop",
            .age = "33d",
        });

        return Body{
            .allocator = allocator,
            .pods = pods,
        };
    }

    pub fn deinit(self: *Body) void {
        self.pods.deinit(self.allocator);
    }

    pub fn render(self: *Body, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        // Create a border around the entire body with btop theme colors and rounded corners
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, Theme.proc_box, Theme.main_bg, self.title, .rounded);
        
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
        const visible_rows = height - 2; // Subtract header and title
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + visible_rows, self.pods.items.len);
        
        for (start_row..end_row, 0..) |pod_idx, display_idx| {
            const pod = self.pods.items[pod_idx];
            const row_y = header_y + 1 + @as(u16, @intCast(display_idx));
            
            // Paint entire row background first (default or selected color)
            const is_selected = pod_idx == self.selected_row;
            const bg_color = if (is_selected) Theme.selected_bg else Theme.main_bg;
            const fg_color = if (is_selected) Theme.selected_fg else Theme.main_fg;
            for (0..width - 2) |i_fill| { // Account for border
                try Theme.writeStringWithTheme(terminal, x + 1 + @as(u16, @intCast(i_fill)), row_y, " ", fg_color, bg_color);
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
            
            // RESTARTS
            const restarts_str = try std.fmt.allocPrint(self.allocator, "{}", .{pod.restarts});
            defer self.allocator.free(restarts_str);
            try Theme.writeStringWithTheme(terminal, col_x, row_y, restarts_str, fg_color, bg_color);
            col_x += scaled[5];
            
            // CPU
            const cpu_str = try std.fmt.allocPrint(self.allocator, "{}", .{pod.cpu});
            defer self.allocator.free(cpu_str);
            try Theme.writeStringWithTheme(terminal, col_x, row_y, cpu_str, fg_color, bg_color);
            col_x += scaled[6];
            
            // %CPU/R
            const cpu_r_str = try std.fmt.allocPrint(self.allocator, "{}", .{pod.cpu_r});
            defer self.allocator.free(cpu_r_str);
            try Theme.writeStringWithTheme(terminal, col_x, row_y, cpu_r_str, fg_color, bg_color);
            col_x += scaled[7];
            
            // %CPU/L
            try Theme.writeStringWithTheme(terminal, col_x, row_y, pod.cpu_l, fg_color, bg_color);
            col_x += scaled[8];
            
            // MEM
            const mem_str = try std.fmt.allocPrint(self.allocator, "{}", .{pod.mem});
            defer self.allocator.free(mem_str);
            try Theme.writeStringWithTheme(terminal, col_x, row_y, mem_str, fg_color, bg_color);
            col_x += scaled[9];
            
            // %MEM/R
            const mem_r_str = try std.fmt.allocPrint(self.allocator, "{}", .{pod.mem_r});
            defer self.allocator.free(mem_r_str);
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
        if (self.selected_row < self.pods.items.len - 1) {
            self.last_selected_row = self.selected_row;
            self.last_scroll_offset = self.scroll_offset;
            self.selected_row += 1;
            // Adjust scroll if needed (assuming 20 visible rows)
            const visible_rows = 20;
            if (self.selected_row >= self.scroll_offset + visible_rows) {
                self.scroll_offset = self.selected_row - visible_rows + 1;
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
            if (self.pods.items.len > 0) {
                self.selected_row = @as(u32, @intCast(self.pods.items.len - 1));
                // Adjust scroll to show the last row
                const visible_rows = 20; // This should be dynamically calculated
                if (self.selected_row >= visible_rows) {
                    self.scroll_offset = self.selected_row - visible_rows + 1;
                }
            }
        }

        pub fn pageUp(self: *Body) !void {
            const page_size = 10; // Page size
            if (self.selected_row >= page_size) {
                self.selected_row -= page_size;
            } else {
                self.selected_row = 0;
            }
            // Adjust scroll if needed
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        }

        pub fn pageDown(self: *Body) !void {
            const page_size = 10; // Page size
            if (self.selected_row + page_size < self.pods.items.len) {
                self.selected_row += page_size;
            } else {
                self.selected_row = @as(u32, @intCast(self.pods.items.len - 1));
            }
            // Adjust scroll if needed
            const visible_rows = 20; // This should be dynamically calculated
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
            // TODO: Implement toggle header logic
            _ = self;
        }

        pub fn toggleCrumbs(self: *Body) !void {
            // TODO: Implement toggle crumbs logic
            _ = self;
        }
};
