const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = @import("../model/theme_loader.zig");

// Box drawing characters (exact from btop)
pub const Symbols = struct {
    pub const h_line = "─"; // horizontal line
    pub const v_line = "│"; // vertical line
    pub const left_up = "┌"; // top-left corner
    pub const right_up = "┐"; // top-right corner
    pub const left_down = "└"; // bottom-left corner
    pub const right_down = "┘"; // bottom-right corner
    pub const div_right = "┤"; // divider right
    pub const div_left = "├"; // divider left
    pub const div_up = "┬"; // divider up
    pub const div_down = "┴"; // divider down
    pub const cross = "┼"; // cross intersection
    pub const title_left = "┐"; // title left bracket
    pub const title_right = "┌"; // title right bracket
};

pub const BoxStyle = enum {
    normal,
    rounded,
    thick,
};

pub const Box = struct {
    pub fn createBox(
        terminal: *Terminal,
        x: u16,
        y: u16,
        width: u16,
        height: u16,
        line_color: []const u8,
        fill_color: ?[]const u8,
        title: ?[]const u8,
        style: BoxStyle,
        main_fg: []const u8,
        title_color: []const u8,
    ) !void {
        if (width < 2 or height < 2) return;

        // Use fill_color as background for borders too, so they match the theme
        const bg = fill_color orelse Theme.default_bg;

        // Choose corner characters based on style
        const Corners = struct {
            top_left: []const u8,
            top_right: []const u8,
            bottom_left: []const u8,
            bottom_right: []const u8,
        };
        const corners: Corners = switch (style) {
            .normal => Corners{
                .top_left = Symbols.left_up,
                .top_right = Symbols.right_up,
                .bottom_left = Symbols.left_down,
                .bottom_right = Symbols.right_down,
            },
            .rounded => Corners{
                .top_left = "╭",
                .top_right = "╮",
                .bottom_left = "╰",
                .bottom_right = "╯",
            },
            .thick => Corners{
                .top_left = "┏",
                .top_right = "┓",
                .bottom_left = "┗",
                .bottom_right = "┛",
            },
        };

        // Draw horizontal lines (exclude corners)
        if (width > 2) {
            for (1..width - 1) |i| {
                try Theme.writeStringWithTheme(terminal, @intCast(x + i), y, Symbols.h_line, line_color, bg);
                try Theme.writeStringWithTheme(terminal, @intCast(x + i), y + height - 1, Symbols.h_line, line_color, bg);
            }
        }

        // Draw vertical lines and fill interior
        for (1..height - 1) |row| {
            const row_y = @as(u16, @intCast(y + row));
            try Theme.writeStringWithTheme(terminal, x, row_y, Symbols.v_line, line_color, bg);

            if (fill_color) |fill| {
                // Fill the row interior with theme background
                if (width > 2) {
                    try terminal.fillRow(x + 1, row_y, width - 2, main_fg, fill);
                }
            }

            try Theme.writeStringWithTheme(terminal, x + width - 1, row_y, Symbols.v_line, line_color, bg);
        }

        // Draw corners
        try Theme.writeStringWithTheme(terminal, x, y, corners.top_left, line_color, bg);
        try Theme.writeStringWithTheme(terminal, x + width - 1, y, corners.top_right, line_color, bg);
        try Theme.writeStringWithTheme(terminal, x, y + height - 1, corners.bottom_left, line_color, bg);
        try Theme.writeStringWithTheme(terminal, x + width - 1, y + height - 1, corners.bottom_right, line_color, bg);

        // Draw title if provided
        if (title) |title_text| {
            const title_x = x + 2;
            const title_y = y;
            try Theme.writeStringWithTheme(terminal, title_x, title_y, Symbols.title_left, line_color, bg);
            try Theme.writeStringWithTheme(terminal, title_x + 1, title_y, title_text, title_color, bg);
            try Theme.writeStringWithTheme(terminal, title_x + 1 + @as(u16, @intCast(title_text.len)), title_y, Symbols.title_right, line_color, bg);
        }
    }

    pub fn createHorizontalDivider(terminal: *Terminal, x: u16, y: u16, width: u16, color: []const u8) !void {
        for (0..width) |i| {
            try Theme.writeText(terminal, @intCast(x + i), y, Symbols.h_line, color);
        }
    }
};
