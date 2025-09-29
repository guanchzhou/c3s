const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const BoxDrawing = @import("box_drawing.zig");
const Theme = @import("theme.zig");
const build = @import("c3s_build");
const version = @import("version.zig");

pub const Header = struct {
    allocator: std.mem.Allocator,
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

    pub fn init(allocator: std.mem.Allocator) !Header {
        const k9s_version = try version.ownedString(allocator);
        const title_with_version = k9s_version; // Just store version, we'll render "c3s" separately
        const cpu_str = try std.fmt.allocPrint(allocator, "{}%", .{@as(u8, 2)}); // Initial dummy value
        const mem_str = try std.fmt.allocPrint(allocator, "{}%", .{@as(u8, 27)}); // Initial dummy value

        return Header{
            .allocator = allocator,
            .context = "rancher-desktop [RW]",
            .cluster = "rancher-desktop",
            .user = "rancher-desktop",
            .k9s_version = k9s_version,
            .k8s_version = "v1.33.3+k3s1",
            .cpu_usage = 2,
            .mem_usage = 27,
            .title_with_version = title_with_version,
            .cpu_str = cpu_str,
            .mem_str = mem_str,
        };
    }

    pub fn toggleCompact(self: *Header) void {
        self.compact = !self.compact;
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
            if (width > 0) {
                try terminal.setCursor(x, y);
                var spaces_buf: [256]u8 = undefined;
                @memset(&spaces_buf, ' ');
                var remaining: usize = width;
                while (remaining > 0) {
                    const chunk = @min(remaining, spaces_buf.len);
                    try terminal.writeAll(spaces_buf[0..chunk]);
                    remaining -= chunk;
                }
            }

            const separator = " | ";
            const segments = [_]struct {
                label: []const u8,
                value: []const u8,
                value_fg: []const u8,
            }{
                .{ .label = "context:", .value = self.context, .value_fg = Theme.hi_fg },
                .{ .label = "cluster:", .value = self.cluster, .value_fg = Theme.hi_fg },
                .{ .label = "user:", .value = self.user, .value_fg = Theme.hi_fg },
                .{ .label = "k8s:", .value = self.k8s_version, .value_fg = Theme.title },
                .{ .label = "CPU:", .value = self.cpu_str, .value_fg = Theme.hi_fg },
                .{ .label = "MEM:", .value = self.mem_str, .value_fg = Theme.hi_fg },
            };

            var total_len: usize = 3 + 1 + self.title_with_version.len; // "c3s " + version
            for (segments) |segment| {
                total_len += separator.len + segment.label.len + 1 + segment.value.len;
            }

            const width_usize: usize = width;
            const offset = if (width_usize > total_len)
                @as(u16, @intCast((width_usize - total_len) / 2))
            else
                0;

            var current_x: u16 = x + offset;
            // Render "c3s" in bold white
            try terminal.setCursor(current_x, y);
            try terminal.writeAll(Theme.app_name);
            try terminal.writeAll("c3s");
            try terminal.writeAll(Theme.reset);
            current_x += 3; // "c3s" is 3 characters
            
            // Render version in normal color
            try terminal.writeAll(" ");
            try terminal.writeAll(Theme.title);
            try terminal.writeAll(self.title_with_version);
            try terminal.writeAll(Theme.reset);
            current_x += @as(u16, @intCast(1 + self.title_with_version.len));

            for (segments) |segment| {
                try Theme.writeStringWithTheme(terminal, current_x, y, separator, Theme.main_fg, Theme.main_bg);
                current_x += @as(u16, @intCast(separator.len));

                try Theme.writeStringWithTheme(terminal, current_x, y, segment.label, Theme.main_fg, Theme.main_bg);
                current_x += @as(u16, @intCast(segment.label.len));

                try Theme.writeStringWithTheme(terminal, current_x, y, " ", Theme.main_fg, Theme.main_bg);
                current_x += 1;

                try Theme.writeStringWithTheme(terminal, current_x, y, segment.value, segment.value_fg, Theme.main_bg);
                current_x += @as(u16, @intCast(segment.value.len));
            }

            self.last_height = box_height;
            return;
        }

        try BoxDrawing.Box.createBox(terminal, x, y, width, box_height, Theme.div_line, Theme.main_bg, null, .rounded);
        
        // Render custom title with "c3s" in bold white and version in normal color
        const title_x = x + 2;
        const title_y = y;
        try Theme.writeText(terminal, title_x, title_y, BoxDrawing.Symbols.title_left, Theme.div_line);
        
        // "c3s" in bold white
        try terminal.setCursor(title_x + 1, title_y);
        try terminal.writeAll(Theme.app_name);
        try terminal.writeAll("c3s");
        try terminal.writeAll(Theme.reset);
        
        // Version in normal color
        try terminal.writeAll(" ");
        try terminal.writeAll(Theme.title);
        try terminal.writeAll(self.title_with_version);
        try terminal.writeAll(Theme.reset);
        
        const title_end_x = title_x + 1 + 3 + 1 + @as(u16, @intCast(self.title_with_version.len));
        try Theme.writeText(terminal, title_end_x, title_y, BoxDrawing.Symbols.title_right, Theme.div_line);

        // System information (left side) - offset by 1 for border, properly aligned
        const label_width = 9; // Fixed width for all labels for alignment
        var line: u16 = y + 1;
        
        try Theme.writeStringWithTheme(terminal, x + 1, line, "Context:", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.context, Theme.hi_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "Cluster:", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.cluster, Theme.hi_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "User:", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.user, Theme.hi_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "K8s Rev:", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.k8s_version, Theme.title, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "CPU:", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.cpu_str, Theme.hi_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "MEM:", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 1 + label_width, line, self.mem_str, Theme.hi_fg, Theme.main_bg);

        // Keyboard shortcuts distributed across available width - offset by 1 for border
        const shortcuts_start_x = @as(u16, @intCast(width / 3)) + 1; // Start at 1/3 width
        const shortcuts_width: u16 = if (width > shortcuts_start_x) width - shortcuts_start_x else 0;
        const col_step: u16 = if (shortcuts_width <= 4) 1 else @as(u16, @intCast(shortcuts_width / 4));
        const col_quick_x = shortcuts_start_x;
        const col1_x = if (shortcuts_width <= 4) col_quick_x + 1 else col_quick_x + col_step;
        const col2_x = if (shortcuts_width <= 4) col1_x + 1 else col1_x + col_step;
        const col3_x = if (shortcuts_width <= 4) col2_x + 1 else col2_x + col_step;
        
        line = y + 1;
        // Quick commands column
        try Theme.writeShortcut(terminal, col_quick_x, line, "0", "all", Theme.main_bg);
        try Theme.writeShortcutWithHighlight(terminal, col1_x, line, "", "a", "ttach", Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, col2_x, line, "<ctrl-k> kill", Theme.main_fg, Theme.main_bg);
        line += 1;

        try Theme.writeShortcut(terminal, col_quick_x, line, "1", "default", Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, col1_x, line, "<ctrl-d> delete", Theme.main_fg, Theme.main_bg);
        try Theme.writeShortcutWithHighlight(terminal, col2_x, line, "", "s", "hell", Theme.main_bg);
        line += 1;

        try Theme.writeShortcutWithHighlight(terminal, col1_x, line, "", "d", "escribe", Theme.main_bg);
        try Theme.writeShortcutWithHighlight(terminal, col2_x, line, "", "e", "dit", Theme.main_bg);
        try Theme.writeShortcutWithHighlight(terminal, col3_x, line, "sh", "o", "w node", Theme.main_bg);
        line += 1;

        try Theme.writeShortcut(terminal, col1_x, line, "?", "help", Theme.main_bg);
        try Theme.writeShortcutWithHighlight(terminal, col2_x, line, "", "l", "ogs", Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, col3_x, line, "<shift-f> port-forward", Theme.main_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, col1_x, line, "<ctrl-f> kill finalizers", Theme.main_fg, Theme.main_bg);
        try Theme.writeShortcutWithHighlight(terminal, col2_x, line, "logs ", "p", "revious", Theme.main_bg);
        try Theme.writeShortcutWithHighlight(terminal, col3_x, line, "", "t", "ransfer", Theme.main_bg);
        line += 1;

        try Theme.writeShortcutWithHighlight(terminal, col1_x, line, "saniti", "z", "e", Theme.main_bg);
        try Theme.writeShortcutWithHighlight(terminal, col2_x, line, "set ", "i", "mage", Theme.main_bg);
        try Theme.writeShortcut(terminal, col3_x, line, "y", "yaml", Theme.main_bg);
        self.last_height = box_height;
    }
};
