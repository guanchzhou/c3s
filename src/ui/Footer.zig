const std = @import("std");
const Terminal = @import("../core/Terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;

pub const Footer = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    current_resource: []const u8,
    current_view: ?[]const u8 = null, // Additional view status (e.g., "help")
    status: ?[]const u8 = null, // e.g., connection status
    preview_status: ?[]const u8 = null, // e.g., "previewing snazzy"

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !Footer {
        return Footer{
            .allocator = allocator,
            .theme = theme,
            .current_resource = "pod",
        };
    }

    pub fn deinit(self: *Footer) void {
        _ = self;
    }

    // Methods to update footer status
    pub fn setView(self: *Footer, view: ?[]const u8) void {
        self.current_view = view;
    }

    pub fn setStatus(self: *Footer, status: ?[]const u8) void {
        self.status = status;
    }

    pub fn setPreviewStatus(self: *Footer, theme_name: ?[]const u8) void {
        self.preview_status = theme_name;
    }

    pub fn setHelpMode(self: *Footer, help_visible: bool) void {
        if (help_visible) {
            self.current_view = "help";
        } else {
            self.current_view = null;
        }
    }

    pub fn setTheme(self: *Footer, theme: *const theme_loader.ThemeColors) void {
        self.theme = theme;
    }

    pub fn render(self: *Footer, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        _ = height; // Fixed height

        // Fill the footer line with theme background
        try terminal.fillRow(x, y, width, self.theme.main_fg, self.theme.main_bg);

        // Display current resource and view status with padding like other components (offset by 1)
        // Use bold text without brackets, like btop: "pods | help" or just "pod"
        var display_len: usize = 0;
        if (self.current_view) |view| {
            // Format: "resource | view"
            var status_buffer: [64]u8 = undefined;
            const status_text = try std.fmt.bufPrint(&status_buffer, "{s} | {s}", .{ self.current_resource, view });
            try Theme.writeStringWithBold(terminal, x + 1, y, status_text, self.theme.hi_fg, self.theme.main_bg);
            display_len = status_text.len;
        } else {
            // Just the resource name
            try Theme.writeStringWithBold(terminal, x + 1, y, self.current_resource, self.theme.hi_fg, self.theme.main_bg);
            display_len = self.current_resource.len;
        }

        // Append preview status if present: " | previewing <theme>"
        if (self.preview_status) |theme_name| {
            const start_x: u16 = x + 1 + @as(u16, @intCast(display_len));
            try Theme.writeStringWithTheme(terminal, start_x, y, " | ", self.theme.main_fg, self.theme.main_bg);
            try Theme.writeStringWithTheme(terminal, start_x + 3, y, "previewing ", self.theme.title_highlight, self.theme.main_bg);
            try Theme.writeStringWithTheme(terminal, start_x + 3 + 11, y, theme_name, self.theme.title_highlight, self.theme.main_bg);
            display_len += 3 + 11 + theme_name.len;
        }

        // Append status if present: " | <status>"
        if (self.status) |status_text2| {
            const start_x: u16 = x + 1 + @as(u16, @intCast(display_len));
            try Theme.writeStringWithTheme(terminal, start_x, y, " | ", self.theme.main_fg, self.theme.main_bg);
            try Theme.writeStringWithTheme(terminal, start_x + 3, y, status_text2, self.theme.status_failed, self.theme.main_bg);
        }
    }
};
