const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const BoxDrawing = @import("box_drawing.zig");
const Theme = @import("../theme.zig");
const build = @import("c3s_build");
const version = @import("../model/version.zig");

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
            try Theme.writeShortcut(terminal, qx, qy, item.key, item.cmd, Theme.main_bg);
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
                0 => try Theme.writeStringWithTheme(terminal, hx, hy, item.text, Theme.main_fg, Theme.main_bg),
                1 => try Theme.writeShortcutWithHighlight(terminal, hx, hy, item.before, item.key, item.after),
                else => {},
            }
        }
        
        self.last_height = box_height;
    }
};
