const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const BoxDrawing = @import("box_drawing.zig");
const Theme = @import("../theme.zig");
const build = @import("c3s_build");
const version = @import("../model/version.zig");
const theme_loader = @import("../model/theme_loader.zig");
const fixtures = @import("../fixtures/index.zig");

pub const Header = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    context: []const u8,
    cluster: []const u8,
    user: []const u8,
    k9s_version: []const u8,
    k8s_version: []const u8,
    cpu_usage: u8,
    mem_usage: u8,
    compact: bool = false,
    title_with_version: []const u8,
    cpu_str: []const u8,
    mem_str: []const u8,
    last_height: u16 = 0,
    debug: bool = false,

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, debug: bool) !Header {
        const k9s_version = try version.ownedString(allocator);
        const title_with_version = k9s_version; // Just store version, we'll render "c3s" separately
        
        // Get K8s data from fixtures based on debug flag
        const k8s_data = fixtures.k8s_data.getData(debug);
        
        const cpu_str = if (debug) 
            try fixtures.k8s_data.getCpuString(allocator, k8s_data.cpu_usage)
        else 
            try allocator.dupe(u8, "n/a");
            
        const mem_str = if (debug)
            try fixtures.k8s_data.getMemString(allocator, k8s_data.mem_usage)
        else
            try allocator.dupe(u8, "n/a");

        return Header{
            .allocator = allocator,
            .theme = theme,
            .context = k8s_data.context,
            .cluster = k8s_data.cluster,
            .user = k8s_data.user,
            .k9s_version = k9s_version,
            .k8s_version = k8s_data.k8s_version,
            .cpu_usage = k8s_data.cpu_usage,
            .mem_usage = k8s_data.mem_usage,
            .title_with_version = title_with_version,
            .cpu_str = cpu_str,
            .mem_str = mem_str,
            .debug = debug,
        };
    }

    pub fn toggleCompact(self: *Header) void {
        self.compact = !self.compact;
    }

    pub fn setTheme(self: *Header, theme: *const theme_loader.ThemeColors) void {
        self.theme = theme;
    }

    // Calculate compact level based on available width
    pub fn calculateCompactLevel(self: *const Header, width: u16) u8 {
        // Calculate required width for each level
        const sep_len = 3;
        
        // Level 0: full (c3s v0.2025.09.30.12.08 | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | k8s: v1.33.3+k3s1 | CPU: 2% | MEM: 27%)
        var level0_len: usize = 3 + 1 + self.title_with_version.len;
        level0_len += sep_len + 8 + 1 + self.context.len; // "context: " + value
        level0_len += sep_len + 8 + 1 + self.cluster.len; // "cluster: " + value
        level0_len += sep_len + 5 + 1 + self.user.len; // "user: " + value
        level0_len += sep_len + 4 + 1 + self.k8s_version.len; // "k8s: " + value
        level0_len += sep_len + 4 + 1 + self.cpu_str.len; // "CPU: " + value
        level0_len += sep_len + 4 + 1 + self.mem_str.len; // "MEM: " + value
        if (width >= level0_len) return 0;
        
        // Level 1: drop version prefix (c3s | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | k8s: v1.33.3+k3s1 | CPU: 2% | MEM: 27%)
        var level1_len: usize = 3; // just "c3s"
        level1_len += sep_len + 8 + 1 + self.context.len;
        level1_len += sep_len + 8 + 1 + self.cluster.len;
        level1_len += sep_len + 5 + 1 + self.user.len;
        level1_len += sep_len + 4 + 1 + self.k8s_version.len;
        level1_len += sep_len + 4 + 1 + self.cpu_str.len;
        level1_len += sep_len + 4 + 1 + self.mem_str.len;
        if (width >= level1_len) return 1;
        
        // Level 2: drop k8s prefix (c3s | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | v1.33.3+k3s1 | CPU: 2% | MEM: 27%)
        var level2_len: usize = 3;
        level2_len += sep_len + 8 + 1 + self.context.len;
        level2_len += sep_len + 8 + 1 + self.cluster.len;
        level2_len += sep_len + 5 + 1 + self.user.len;
        level2_len += sep_len + self.k8s_version.len;
        level2_len += sep_len + 4 + 1 + self.cpu_str.len;
        level2_len += sep_len + 4 + 1 + self.mem_str.len;
        if (width >= level2_len) return 2;
        
        // Level 3: compact CPU/MEM (c3s | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | v1.33.3+k3s1 | 2%::27%)
        var level3_len: usize = 3;
        level3_len += sep_len + 8 + 1 + self.context.len;
        level3_len += sep_len + 8 + 1 + self.cluster.len;
        level3_len += sep_len + 5 + 1 + self.user.len;
        level3_len += sep_len + self.k8s_version.len;
        level3_len += sep_len + self.cpu_str.len + 2 + self.mem_str.len; // cpu%::mem%
        if (width >= level3_len) return 3;
        
        // Level 4: short labels (c3s | ctx: rancher-desktop [RW] | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%)
        var level4_len: usize = 3;
        level4_len += sep_len + 4 + 1 + self.context.len; // "ctx: "
        level4_len += sep_len + 2 + 1 + self.cluster.len; // "c: "
        level4_len += sep_len + 2 + 1 + self.user.len; // "u: "
        level4_len += sep_len + self.k8s_version.len;
        level4_len += sep_len + self.cpu_str.len + 2 + self.mem_str.len;
        if (width >= level4_len) return 4;
        
        // Level 5: drop [RW] (c3s | ctx: rancher-desktop | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%)
        // Calculate context without [RW]
        var ctx_without_rw = self.context;
        if (std.mem.indexOf(u8, self.context, " [")) |idx| {
            ctx_without_rw = self.context[0..idx];
        }
        var level5_len: usize = 3;
        level5_len += sep_len + 4 + 1 + ctx_without_rw.len;
        level5_len += sep_len + 2 + 1 + self.cluster.len;
        level5_len += sep_len + 2 + 1 + self.user.len;
        level5_len += sep_len + self.k8s_version.len;
        level5_len += sep_len + self.cpu_str.len + 2 + self.mem_str.len;
        if (width >= level5_len) return 5;
        
        // Level 6: drop c3s (ctx: rancher-desktop | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%)
        var level6_len: usize = 4 + 1 + ctx_without_rw.len;
        level6_len += sep_len + 2 + 1 + self.cluster.len;
        level6_len += sep_len + 2 + 1 + self.user.len;
        level6_len += sep_len + self.k8s_version.len;
        level6_len += sep_len + self.cpu_str.len + 2 + self.mem_str.len;
        if (width >= level6_len) return 6;
        
        // Level 7: values only (rancher-desktop | rancher-desktop | rancher-desktop | v1.33.3+k3s1 | 2%::27%)
        var level7_len: usize = ctx_without_rw.len;
        level7_len += sep_len + self.cluster.len;
        level7_len += sep_len + self.user.len;
        level7_len += sep_len + self.k8s_version.len;
        level7_len += sep_len + self.cpu_str.len + 2 + self.mem_str.len;
        if (width >= level7_len) return 7;
        
        // Level 8: drop k8s (rancher-desktop | rancher-desktop | rancher-desktop | 2%::27%)
        var level8_len: usize = ctx_without_rw.len;
        level8_len += sep_len + self.cluster.len;
        level8_len += sep_len + self.user.len;
        level8_len += sep_len + self.cpu_str.len + 2 + self.mem_str.len;
        if (width >= level8_len) return 8;
        
        // Level 9: truncate user to 3 chars
        const user_short = if (self.user.len > 3) self.user[0..3] else self.user;
        var level9_len: usize = ctx_without_rw.len;
        level9_len += sep_len + self.cluster.len;
        level9_len += sep_len + user_short.len;
        if (user_short.len < self.user.len) level9_len += 3; // "..."
        level9_len += sep_len + self.cpu_str.len + 2 + self.mem_str.len;
        if (width >= level9_len) return 9;
        
        // Level 10: truncate cluster to 3 chars
        const cluster_short = if (self.cluster.len > 3) self.cluster[0..3] else self.cluster;
        var level10_len: usize = ctx_without_rw.len;
        level10_len += sep_len + cluster_short.len;
        if (cluster_short.len < self.cluster.len) level10_len += 3; // "..."
        level10_len += sep_len + user_short.len;
        if (user_short.len < self.user.len) level10_len += 3;
        level10_len += sep_len + self.cpu_str.len + 2 + self.mem_str.len;
        if (width >= level10_len) return 10;
        
        // Level 11: minimum (context | 2%::27%) - 25 chars minimum
        return 11;
    }

    fn renderCompactHeader(self: *const Header, terminal: *Terminal, x: u16, y: u16, width: u16, level: u8) !void {
        const sep = " | ";
        
        // Get context without [RW] suffix for levels 5+
        var ctx_clean = self.context;
        if (level >= 5) {
            if (std.mem.indexOf(u8, self.context, " [")) |idx| {
                ctx_clean = self.context[0..idx];
            }
        }
        
        // Build the compact header string based on level
        var buf: [512]u8 = undefined;
        var parts = try std.ArrayList([]const u8).initCapacity(self.allocator, 7);
        defer parts.deinit(self.allocator);
        
        switch (level) {
            0 => {
                // c3s v0.2025.09.30.12.08 | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | k8s: v1.33.3+k3s1 | CPU: 2% | MEM: 27%
                const app_part = try std.fmt.bufPrint(&buf, "c3s {s}", .{self.title_with_version});
                try parts.append(self.allocator, try self.allocator.dupe(u8, app_part));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "context: {s}", .{self.context}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "cluster: {s}", .{self.cluster}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "user: {s}", .{self.user}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "k8s: {s}", .{self.k8s_version}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "CPU: {s}", .{self.cpu_str}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "MEM: {s}", .{self.mem_str}));
            },
            1 => {
                // c3s | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | k8s: v1.33.3+k3s1 | CPU: 2% | MEM: 27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, "c3s"));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "context: {s}", .{self.context}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "cluster: {s}", .{self.cluster}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "user: {s}", .{self.user}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "k8s: {s}", .{self.k8s_version}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "CPU: {s}", .{self.cpu_str}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "MEM: {s}", .{self.mem_str}));
            },
            2 => {
                // c3s | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | v1.33.3+k3s1 | CPU: 2% | MEM: 27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, "c3s"));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "context: {s}", .{self.context}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "cluster: {s}", .{self.cluster}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "user: {s}", .{self.user}));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.k8s_version));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "CPU: {s}", .{self.cpu_str}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "MEM: {s}", .{self.mem_str}));
            },
            3 => {
                // c3s | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | v1.33.3+k3s1 | 2%::27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, "c3s"));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "context: {s}", .{self.context}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "cluster: {s}", .{self.cluster}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "user: {s}", .{self.user}));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.k8s_version));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{self.cpu_str, self.mem_str}));
            },
            4 => {
                // c3s | ctx: rancher-desktop [RW] | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, "c3s"));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ctx: {s}", .{self.context}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "c: {s}", .{self.cluster}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "u: {s}", .{self.user}));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.k8s_version));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{self.cpu_str, self.mem_str}));
            },
            5 => {
                // c3s | ctx: rancher-desktop | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, "c3s"));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ctx: {s}", .{ctx_clean}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "c: {s}", .{self.cluster}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "u: {s}", .{self.user}));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.k8s_version));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{self.cpu_str, self.mem_str}));
            },
            6 => {
                // ctx: rancher-desktop | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ctx: {s}", .{ctx_clean}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "c: {s}", .{self.cluster}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "u: {s}", .{self.user}));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.k8s_version));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{self.cpu_str, self.mem_str}));
            },
            7 => {
                // rancher-desktop | rancher-desktop | rancher-desktop | v1.33.3+k3s1 | 2%::27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, ctx_clean));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.cluster));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.user));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.k8s_version));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{self.cpu_str, self.mem_str}));
            },
            8 => {
                // rancher-desktop | rancher-desktop | rancher-desktop | 2%::27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, ctx_clean));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.cluster));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.user));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{self.cpu_str, self.mem_str}));
            },
            9 => {
                // rancher-desktop | rancher-desktop | ran... | 2%::27%
                const user_short = if (self.user.len > 3) 
                    try std.fmt.allocPrint(self.allocator, "{s}...", .{self.user[0..3]})
                else 
                    try self.allocator.dupe(u8, self.user);
                try parts.append(self.allocator, try self.allocator.dupe(u8, ctx_clean));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.cluster));
                try parts.append(self.allocator, user_short);
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{self.cpu_str, self.mem_str}));
            },
            10 => {
                // rancher-desktop | ran... | ran... | 2%::27%
                const cluster_short = if (self.cluster.len > 3) 
                    try std.fmt.allocPrint(self.allocator, "{s}...", .{self.cluster[0..3]})
                else 
                    try self.allocator.dupe(u8, self.cluster);
                const user_short = if (self.user.len > 3) 
                    try std.fmt.allocPrint(self.allocator, "{s}...", .{self.user[0..3]})
                else 
                    try self.allocator.dupe(u8, self.user);
                try parts.append(self.allocator, try self.allocator.dupe(u8, ctx_clean));
                try parts.append(self.allocator, cluster_short);
                try parts.append(self.allocator, user_short);
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{self.cpu_str, self.mem_str}));
            },
            else => {
                // Level 11: minimum (rancher-desktop | 2%::27%)
                try parts.append(self.allocator, try self.allocator.dupe(u8, ctx_clean));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{self.cpu_str, self.mem_str}));
            },
        }
        
        // Calculate total length and render
        var total_len: usize = 0;
        for (parts.items, 0..) |part, i| {
            total_len += part.len;
            if (i < parts.items.len - 1) total_len += sep.len;
        }
        
        const width_usize: usize = width;
        const offset = if (width_usize > total_len)
            @as(u16, @intCast((width_usize - total_len) / 2))
        else
            0;
        
        var current_x: u16 = x + offset;
        try terminal.setCursor(current_x, y);
        
        for (parts.items, 0..) |part, i| {
            // Determine color for this part
            const color = if (i == 0 and level <= 5) self.theme.app_name else self.theme.hi_fg;
            try terminal.writeAll(color);
            try terminal.writeAll(part);
            try terminal.writeAll("\x1b[0m");
            current_x += @as(u16, @intCast(part.len));
            
            if (i < parts.items.len - 1) {
                try Theme.writeStringWithTheme(terminal, current_x, y, sep, self.theme.main_fg, self.theme.main_bg);
                current_x += @as(u16, @intCast(sep.len));
            }
            
            // Free allocated part
            self.allocator.free(part);
        }
    }
    
    pub fn setCompact(self: *Header, compact: bool) void {
        self.compact = compact;
    }

    pub fn height(self: *const Header) u16 {
        return if (self.compact) 1 else 8;
    }

    fn initVersion(allocator: std.mem.Allocator) ![]const u8 {
        return try version.ownedString(allocator);
    }

    pub fn deinit(self: *Header) void {
        self.allocator.free(self.title_with_version);
        self.allocator.free(self.cpu_str);
        self.allocator.free(self.mem_str);
    }

    fn clearRows(terminal: *Terminal, x: u16, y: u16, width: u16, rows: u16) !void {
        if (rows == 0 or width == 0) return;
        var row: u16 = 0;
        var spaces_buf: [256]u8 = undefined;
        @memset(&spaces_buf, ' ');
        while (row < rows) : (row += 1) {
            try terminal.setCursor(x, y + row);
            var remaining: usize = width;
            while (remaining > 0) {
                const chunk = @min(remaining, spaces_buf.len);
                try terminal.writeAll(spaces_buf[0..chunk]);
                remaining -= chunk;
            }
        }
    }

    pub fn render(self: *Header, terminal: *Terminal, x: u16, y: u16, width: u16, box_height: u16) !void {
        if (self.last_height > box_height) {
            try clearRows(terminal, x, y, width, self.last_height);
        }

        if (self.compact) {
            // Clear the line first
            if (width > 0) {
                try terminal.setCursor(x, y);
                try terminal.writeAll(self.theme.main_bg);
                var spaces_buf: [256]u8 = undefined;
                @memset(&spaces_buf, ' ');
                var remaining: usize = width;
                while (remaining > 0) {
                    const chunk = @min(remaining, spaces_buf.len);
                    try terminal.writeAll(spaces_buf[0..chunk]);
                    remaining -= chunk;
                }
            }

            // Calculate and render compact header with progressive compression
            const compact_level = self.calculateCompactLevel(width);
            try self.renderCompactHeader(terminal, x, y, width, compact_level);

            self.last_height = box_height;
            return;
        }

        try BoxDrawing.Box.createBox(terminal, x, y, width, box_height, self.theme.proc_box, self.theme.main_bg, null, .rounded, self.theme.main_fg, self.theme.title);
        
        // Render custom title with "c3s" in bold white and version in normal color
        const title_x = x + 2;
        const title_y = y;
        try Theme.writeText(terminal, title_x, title_y, BoxDrawing.Symbols.title_left, self.theme.proc_box);
        
        // "c3s" in bold white
        try terminal.setCursor(title_x + 1, title_y);
        try terminal.writeAll(self.theme.app_name);
        try terminal.writeAll("c3s");
        try terminal.writeAll("\x1b[0m");
        
        // Version in normal color
        try terminal.writeAll(" ");
        try terminal.writeAll(self.theme.title);
        try terminal.writeAll(self.title_with_version);
        try terminal.writeAll("\x1b[0m");
        
        const title_end_x = title_x + 1 + 3 + 1 + @as(u16, @intCast(self.title_with_version.len));
        try Theme.writeText(terminal, title_end_x, title_y, BoxDrawing.Symbols.title_right, self.theme.proc_box);

        // System information (left side) - offset by 1 for border, properly aligned
        const label_width = 9; // Fixed width for all labels for alignment
        var line: u16 = y + 1;
        
        try Theme.writeStringWithTheme(terminal, x + 1, line, "Context:", self.theme.main_fg, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.context, self.theme.hi_fg, self.theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "Cluster:", self.theme.main_fg, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.cluster, self.theme.hi_fg, self.theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "User:", self.theme.main_fg, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.user, self.theme.hi_fg, self.theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "K8s Rev:", self.theme.main_fg, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.k8s_version, self.theme.title, self.theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "CPU:", self.theme.main_fg, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.cpu_str, self.theme.hi_fg, self.theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "MEM:", self.theme.main_fg, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.mem_str, self.theme.hi_fg, self.theme.main_bg);

        // Keyboard shortcuts section (right side of header)
        const shortcuts_start_x = @as(u16, @intCast(width / 3)) + 1;
        const shortcuts_width: u16 = if (width > shortcuts_start_x) width - shortcuts_start_x else 0;
        
        // Quick commands (left section) - namespace shortcuts only
        const quick_commands = [_]struct { key: []const u8, cmd: []const u8 }{
            .{ .key = "0", .cmd = "all" },
            .{ .key = "1", .cmd = "default" },
        };
        
        // Determine quick commands columns: 1 column if ≤6 items, 2 columns if >6
        const quick_cols: u16 = if (quick_commands.len > 6) 2 else 1;
        const quick_width: u16 = if (shortcuts_width > 0) @as(u16, @intCast(shortcuts_width / 5)) else 15;
        
        // Render quick commands (top-to-bottom, left-to-right)
        line = y + 1;
        for (quick_commands, 0..) |item, idx| {
            const row = @as(u16, @intCast(idx / quick_cols));
            const col = @as(u16, @intCast(idx % quick_cols));
            const qx = shortcuts_start_x + (col * quick_width);
            const qy = y + 1 + row;
            try Theme.writeShortcut(terminal, qx, qy, item.key, item.cmd, self.theme.main_bg);
        }
        
        // Text hints (right section) - render up to 3 columns
        const hints = [_]struct { render_fn: u8, text: []const u8, key: []const u8, before: []const u8, after: []const u8 }{
            .{ .render_fn = 1, .text = "", .key = "a", .before = "", .after = "ttach" },
            .{ .render_fn = 0, .text = "<ctrl-k> kill", .key = "", .before = "", .after = "" },
            .{ .render_fn = 0, .text = "<ctrl-d> delete", .key = "", .before = "", .after = "" },
            .{ .render_fn = 1, .text = "", .key = "s", .before = "", .after = "hell" },
            .{ .render_fn = 1, .text = "", .key = "d", .before = "", .after = "escribe" },
            .{ .render_fn = 1, .text = "", .key = "e", .before = "", .after = "dit" },
            .{ .render_fn = 1, .text = "", .key = "o", .before = "sh", .after = "w node" },
            .{ .render_fn = 1, .text = "", .key = "?", .before = "", .after = " help" }, // ? help - key is "?", after is " help" with leading space
            .{ .render_fn = 1, .text = "", .key = "l", .before = "", .after = "ogs" },
            .{ .render_fn = 0, .text = "<shift-f> port-forward", .key = "", .before = "", .after = "" },
            .{ .render_fn = 0, .text = "<ctrl-f> kill finalizers", .key = "", .before = "", .after = "" },
            .{ .render_fn = 1, .text = "", .key = "p", .before = "logs ", .after = "revious" },
            .{ .render_fn = 1, .text = "", .key = "t", .before = "", .after = "ransfer" },
            .{ .render_fn = 1, .text = "", .key = "z", .before = "saniti", .after = "e" },
            .{ .render_fn = 1, .text = "", .key = "i", .before = "set ", .after = "mage" },
            .{ .render_fn = 1, .text = "", .key = "y", .before = "", .after = " yaml" }, // y yaml - same pattern
        };
        
        // Determine hints columns: 1 if ≤6, 2 if ≤12, 3 if >12
        const hints_cols: u16 = if (hints.len > 12) 3 else if (hints.len > 6) 2 else 1;
        const hints_start_x = shortcuts_start_x + (quick_width * quick_cols);
        const hints_width: u16 = if (shortcuts_width > (quick_width * quick_cols)) shortcuts_width - (quick_width * quick_cols) else 0;
        const hint_col_width: u16 = if (hints_width > 0 and hints_cols > 0) @as(u16, @intCast(hints_width / hints_cols)) else 20;
        
        // Render hints (top-to-bottom, left-to-right)
        for (hints, 0..) |item, idx| {
            const row = @as(u16, @intCast(idx / hints_cols));
            const col = @as(u16, @intCast(idx % hints_cols));
            const hx = hints_start_x + (col * hint_col_width);
            const hy = y + 1 + row;
            
            switch (item.render_fn) {
                0 => try Theme.writeStringWithTheme(terminal, hx, hy, item.text, self.theme.main_fg, self.theme.main_bg),
                1 => try Theme.writeShortcutWithHighlight(terminal, hx, hy, item.before, item.key, item.after),
                else => {},
            }
        }
        
        self.last_height = box_height;
    }
};
