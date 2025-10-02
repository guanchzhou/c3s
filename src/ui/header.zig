const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const BoxDrawing = @import("box_drawing.zig");
const Theme = @import("../theme.zig");
const build = @import("c3s_build");
const version = @import("../model/version.zig");
const theme_loader = @import("../model/theme_loader.zig");
const fixtures = @import("../fixtures/index.zig");
const Logger = @import("../core/logger.zig");

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

        // CRITICAL: Duplicate strings to avoid use-after-free (fixture data is static)
        return Header{
            .allocator = allocator,
            .theme = theme,
            .context = try allocator.dupe(u8, k8s_data.context),
            .cluster = try allocator.dupe(u8, k8s_data.cluster),
            .user = try allocator.dupe(u8, k8s_data.user),
            .k9s_version = k9s_version,
            .k8s_version = try allocator.dupe(u8, k8s_data.k8s_version),
            .cpu_usage = k8s_data.cpu_usage,
            .mem_usage = k8s_data.mem_usage,
            .title_with_version = title_with_version,
            .cpu_str = cpu_str,
            .mem_str = mem_str,
            .debug = debug,
        };
    }

    /// Initialize header with K8s cluster data (from real K8s client or fixtures)
    pub fn initWithData(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, cluster_data: anytype) !Header {
        const k9s_version = try version.ownedString(allocator);
        const title_with_version = k9s_version;

        const cpu_str = try std.fmt.allocPrint(allocator, "{d}%", .{cluster_data.cpu_usage});
        const mem_str = try std.fmt.allocPrint(allocator, "{d}%", .{cluster_data.mem_usage});

        // CRITICAL: Duplicate strings to avoid use-after-free when cluster_data is freed
        return Header{
            .allocator = allocator,
            .theme = theme,
            .context = try allocator.dupe(u8, cluster_data.context),
            .cluster = try allocator.dupe(u8, cluster_data.cluster),
            .user = try allocator.dupe(u8, cluster_data.user),
            .k9s_version = k9s_version,
            .k8s_version = try allocator.dupe(u8, cluster_data.k8s_version),
            .cpu_usage = cluster_data.cpu_usage,
            .mem_usage = cluster_data.mem_usage,
            .title_with_version = title_with_version,
            .cpu_str = cpu_str,
            .mem_str = mem_str,
            .debug = false,
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
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ self.cpu_str, self.mem_str }));
            },
            4 => {
                // c3s | ctx: rancher-desktop [RW] | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, "c3s"));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ctx: {s}", .{self.context}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "c: {s}", .{self.cluster}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "u: {s}", .{self.user}));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.k8s_version));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ self.cpu_str, self.mem_str }));
            },
            5 => {
                // c3s | ctx: rancher-desktop | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, "c3s"));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ctx: {s}", .{ctx_clean}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "c: {s}", .{self.cluster}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "u: {s}", .{self.user}));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.k8s_version));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ self.cpu_str, self.mem_str }));
            },
            6 => {
                // ctx: rancher-desktop | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "ctx: {s}", .{ctx_clean}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "c: {s}", .{self.cluster}));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "u: {s}", .{self.user}));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.k8s_version));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ self.cpu_str, self.mem_str }));
            },
            7 => {
                // rancher-desktop | rancher-desktop | rancher-desktop | v1.33.3+k3s1 | 2%::27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, ctx_clean));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.cluster));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.user));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.k8s_version));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ self.cpu_str, self.mem_str }));
            },
            8 => {
                // rancher-desktop | rancher-desktop | rancher-desktop | 2%::27%
                try parts.append(self.allocator, try self.allocator.dupe(u8, ctx_clean));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.cluster));
                try parts.append(self.allocator, try self.allocator.dupe(u8, self.user));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ self.cpu_str, self.mem_str }));
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
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ self.cpu_str, self.mem_str }));
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
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ self.cpu_str, self.mem_str }));
            },
            else => {
                // Level 11: minimum (rancher-desktop | 2%::27%)
                try parts.append(self.allocator, try self.allocator.dupe(u8, ctx_clean));
                try parts.append(self.allocator, try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ self.cpu_str, self.mem_str }));
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
            // Determine color for this part - match non-compact header colors
            const color = blk: {
                if (i == 0 and level <= 5) {
                    break :blk self.theme.app_name; // "c3s" in app_name color
                }

                // For parts with ":" (labels), split and color accordingly
                if (std.mem.indexOf(u8, part, ":")) |colon_pos| {
                    // Label part (before colon) - use main_fg
                    try terminal.writeAll(self.theme.main_fg);
                    try terminal.writeAll(part[0 .. colon_pos + 1]); // Include the colon
                    try terminal.writeAll("\x1b[0m");

                    // Value part (after colon and space) - use hi_fg (or title for k8s)
                    if (colon_pos + 2 < part.len) {
                        const is_k8s = std.mem.startsWith(u8, part, "k8s:") or std.mem.startsWith(u8, part, "K8s:");
                        const value_color = if (is_k8s) self.theme.title else self.theme.hi_fg;
                        try terminal.writeAll(value_color);
                        try terminal.writeAll(part[colon_pos + 2 ..]); // Skip ": "
                        try terminal.writeAll("\x1b[0m");
                    }
                    current_x += @as(u16, @intCast(part.len));

                    if (i < parts.items.len - 1) {
                        try Theme.writeStringWithTheme(terminal, current_x, y, sep, self.theme.main_fg, self.theme.main_bg);
                        current_x += @as(u16, @intCast(sep.len));
                    }

                    self.allocator.free(part);
                    continue;
                }

                // No colon - just value, use hi_fg
                break :blk self.theme.hi_fg;
            };

            // Simple color (no colon in part)
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
        Logger.info("Header.setCompact called: {} (was: {})", .{ compact, self.compact });
        self.compact = compact;
    }

    pub fn height(self: *const Header) u16 {
        return if (self.compact) 1 else 8;
    }

    fn initVersion(allocator: std.mem.Allocator) ![]const u8 {
        return try version.ownedString(allocator);
    }

    pub fn deinit(self: *Header) void {
        // Free allocated strings (from initWithData)
        self.allocator.free(self.context);
        self.allocator.free(self.cluster);
        self.allocator.free(self.user);
        self.allocator.free(self.k8s_version);

        // Free version and metrics strings
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

    const hints_model = @import("../model/hints.zig");

    pub fn render(self: *Header, terminal: *Terminal, x: u16, y: u16, width: u16, box_height: u16, hint_config: hints_model.HintConfig) !void {
        Logger.debug("Header.render: compact={}, width={}, height={}", .{ self.compact, width, box_height });

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

        // Keyboard shortcuts section (right side of header) with progressive hiding
        const shortcuts_start_x = @as(u16, @intCast(width / 3)) + 1;
        const shortcuts_width: u16 = if (width > shortcuts_start_x) width - shortcuts_start_x else 0;

        // Get hints from parameter
        const quick_commands = hint_config.quick_commands;
        const hints = hint_config.hints;

        // Progressive hiding strategy based on width
        // Calculate minimum widths for each level:
        // - Level 0 (full): 1 quick commands col + 3 hints cols (~140 chars needed)
        // - Level 1: 1 quick commands col + 2 hints cols (~110 chars needed)
        // - Level 2: 1 quick commands col + 1 hints col (~80 chars needed)
        // - Level 3: 1 quick commands col + 0 hints (~50 chars needed)
        // - Level 4: 0 quick commands cols + 0 hints (shortcuts hidden)

        const min_width_for_3_hint_cols: u16 = 140;
        const min_width_for_2_hint_cols: u16 = 110;
        const min_width_for_1_hint_col: u16 = 80;
        const min_width_for_1_quick_col: u16 = 40;

        // Determine what to show based on width
        var show_hints_cols: u16 = 0;
        var show_quick_cols: u16 = 0;

        // With only 2 quick commands, always use 1 column (they stack vertically)
        if (width >= min_width_for_3_hint_cols) {
            show_hints_cols = 3;
            show_quick_cols = 1;
        } else if (width >= min_width_for_2_hint_cols) {
            show_hints_cols = 2;
            show_quick_cols = 1;
        } else if (width >= min_width_for_1_hint_col) {
            show_hints_cols = 1;
            show_quick_cols = 1;
        } else if (width >= min_width_for_1_quick_col) {
            show_hints_cols = 0;
            show_quick_cols = 1;
        } else {
            show_hints_cols = 0;
            show_quick_cols = 0;
        }

        // Render quick commands if visible
        if (show_quick_cols > 0) {
            const quick_width: u16 = if (shortcuts_width > 0) @as(u16, @intCast(shortcuts_width / 5)) else 15;

            line = y + 1;
            for (quick_commands, 0..) |item, idx| {
                const row = @as(u16, @intCast(idx / show_quick_cols));
                const col = @as(u16, @intCast(idx % show_quick_cols));
                if (col >= show_quick_cols) continue; // Skip if column is hidden

                const qx = shortcuts_start_x + (col * quick_width);
                const qy = y + 1 + row;
                try Theme.writeShortcut(terminal, qx, qy, item.key, item.cmd, self.theme.main_bg);
            }
        }

        // Render hints if visible
        if (show_hints_cols > 0) {
            const quick_width: u16 = if (shortcuts_width > 0) @as(u16, @intCast(shortcuts_width / 5)) else 15;
            const hints_start_x = shortcuts_start_x + (quick_width * show_quick_cols);
            const hints_width: u16 = if (shortcuts_width > (quick_width * show_quick_cols)) shortcuts_width - (quick_width * show_quick_cols) else 0;
            const hint_col_width: u16 = if (hints_width > 0 and show_hints_cols > 0) @as(u16, @intCast(hints_width / show_hints_cols)) else 20;

            // Calculate right boundary (header border is at x + width - 1)
            // Ensure width is large enough to prevent underflow
            const max_x = if (width > 2) x + width - 2 else x;

            for (hints, 0..) |item, idx| {
                // Safety check: ensure we're not accessing corrupt memory
                // Skip if we've somehow gone beyond reasonable hint count
                if (idx >= 100) break; // Sanity limit

                const row = @as(u16, @intCast(idx / show_hints_cols));
                const col = @as(u16, @intCast(idx % show_hints_cols));
                if (col >= show_hints_cols) continue; // Skip if column is hidden

                const hx = hints_start_x + (col * hint_col_width);
                const hy = y + 1 + row;

                // Skip if hint would overflow beyond header boundary
                if (hx >= max_x) continue;

                // Calculate maximum text length that fits
                const max_text_len = if (max_x > hx) max_x - hx else 0;
                if (max_text_len < 3) continue; // Skip if not enough space for meaningful text

                // Validate render_fn enum before switching
                const render_type = @intFromEnum(item.render_fn);
                if (render_type != 0 and render_type != 1) {
                    // Corrupt enum value - skip this item
                    continue;
                }

                switch (item.render_fn) {
                    .plain => {
                        // Plain hints should have text, highlighted hints have empty text
                        // Double-check everything before attempting to slice
                        if (item.text.len > 0 and max_text_len > 0) {
                            const text_len = @min(item.text.len, max_text_len);
                            // Final safety check: ensure slice bounds are valid
                            if (text_len > 0 and text_len <= item.text.len) {
                                const safe_slice = item.text[0..text_len];
                                try Theme.writeStringWithTheme(terminal, hx, hy, safe_slice, self.theme.main_fg, self.theme.main_bg);
                            }
                        }
                    },
                    .highlighted => {
                        // Calculate total length for highlighted hint
                        const total_len = item.before.len + item.key.len + item.after.len;
                        if (total_len > 0 and total_len <= max_text_len) {
                            try Theme.writeShortcutWithHighlight(terminal, hx, hy, item.before, item.key, item.after);
                        }
                    },
                }
            }
        }

        self.last_height = box_height;
    }
};
