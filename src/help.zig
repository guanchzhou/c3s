const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const Theme = @import("theme.zig");

pub const Help = struct {
    allocator: std.mem.Allocator,
    visible: bool = false,

    pub fn init(allocator: std.mem.Allocator) !Help {
        return Help{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Help) void {
        _ = self;
    }

    pub fn toggle(self: *Help) void {
        self.visible = !self.visible;
    }

    pub fn show(self: *Help) void {
        self.visible = true;
    }

    pub fn hide(self: *Help) void {
        self.visible = false;
    }

    pub fn render(self: *Help, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        if (!self.visible) return;

        // Draw overlay only in the interior of the body component (preserve borders)
        // Leave 1 character margin on all sides to preserve the body border
        const inner_x = x + 1;
        const inner_y = y + 1;
        const inner_width = if (width > 2) width - 2 else 0;
        const inner_height = if (height > 2) height - 2 else 0;

        if (inner_width == 0 or inner_height == 0) return;

        // Fill only the interior area with theme background
        for (0..inner_height) |row| {
            for (0..inner_width) |col| {
                try Theme.writeStringWithTheme(terminal, @intCast(inner_x + col), @intCast(inner_y + row), " ", Theme.main_fg, Theme.main_bg);
            }
        }

        // Help content area - position within the preserved border area
        const help_x = inner_x + 1;
        const help_y = inner_y; // Start from top since title is now in border
        const help_width = if (inner_width > 2) inner_width - 2 else 0;

        // Three columns of shortcuts - start immediately, no extra spacing
        const col_width = help_width / 3;
        var current_y = help_y; // Start right at the top, no gap

        // RESOURCE column
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "RESOURCE", Theme.title, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<0> all", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<1> default", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<a> Attach", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<c> Copy", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<n> Copy Namespace", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<ctrl-d> Delete", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<d> Describe", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<e> Edit", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<?> Help", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<shift-j> Jump Owner", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<ctrl-k> Kill", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<ctrl-f> Kill finalizers", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<l> Logs", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<p> Logs Previous", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<shift-f> Port-Forward", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<ctrl-r> Refresh", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try Theme.writeStringWithTheme(terminal, help_x, current_y, "<z> Sanitize", Theme.main_fg, Theme.main_bg);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<i> Set Image", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<s> Shell", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<o> Show Node", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<f> Show PortForward", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-a> Sort Age", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-c> Sort CPU", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<ctrl-x> Sort CPU/L", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-x> Sort CPU/R", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-i> Sort IP", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-m> Sort MEM", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<ctrl-q> Sort MEM/L", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-z> Sort MEM/R", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-n> Sort Name", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-p> Sort Namespace", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-o> Sort Node", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-r> Sort Ready", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-t> Sort Restart", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<shift-s> Sort Status", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<ctrl-z> Toggle Faults", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<ctrl-w> Toggle Wide", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<t> Transfer", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<enter> View", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(help_x, current_y, "<y> YAML", .white, .default);

        // GENERAL column
        current_y = help_y + 2;
        const general_x = help_x + col_width;
        try terminal.writeStringWithColor(general_x, current_y, "GENERAL", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<ctrl-a> Aliases", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<esc> Back/Clear", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<ctrl-u> Command Clear", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<:cmd> Command mode", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<tab> Field Next", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<backtab> Field Previous", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "</term> Filter mode", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<?> Help", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<space> Mark", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<ctrl-\\> Mark Clear", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<ctrl-space> Mark Range", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<:q> Quit", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<ctrl-r> Reload", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<ctrl-s> Save", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<ctrl-g> Toggle Crumbs", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(general_x, current_y, "<ctrl-e> Toggle Header", .white, .default);

        // NAVIGATION column
        current_y = help_y + 2;
        const nav_x = help_x + col_width * 2;
        try terminal.writeStringWithColor(nav_x, current_y, "NAVIGATION", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(nav_x, current_y, "<j> Down", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(nav_x, current_y, "<shift-g> Goto Bottom", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(nav_x, current_y, "<g> Goto Top", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(nav_x, current_y, "<[> History Back", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(nav_x, current_y, "<]> History Forward", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(nav_x, current_y, "<h> Left", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(nav_x, current_y, "<ctrl-f> Page Down", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(nav_x, current_y, "<ctrl-b> Page Up", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(nav_x, current_y, "<l> Right", .white, .default);
        current_y += 1;
        try terminal.writeStringWithColor(nav_x, current_y, "<k> Up", .white, .default);
    }
};
