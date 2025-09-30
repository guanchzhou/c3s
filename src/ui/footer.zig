const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = @import("../theme.zig");
const theme_loader = @import("../model/theme_loader.zig");

pub const Footer = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    current_resource: []const u8,
    current_view: ?[]const u8 = null, // Additional view status (e.g., "help")

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
        for (0..width) |i| {
            try Theme.writeStringWithTheme(terminal, @intCast(x + i), y, " ", self.theme.main_fg, self.theme.main_bg);
        }

        // Display current resource and view status with padding like other components (offset by 1)
        // Use bold text without brackets, like btop: "pods | help" or just "pod"
        if (self.current_view) |view| {
            // Format: "resource | view" 
            var status_buffer: [64]u8 = undefined;
            const status_text = try std.fmt.bufPrint(&status_buffer, "{s} | {s}", .{ self.current_resource, view });
            try Theme.writeStringWithBold(terminal, x + 1, y, status_text, self.theme.hi_fg, self.theme.main_bg);
        } else {
            // Just the resource name
            try Theme.writeStringWithBold(terminal, x + 1, y, self.current_resource, self.theme.hi_fg, self.theme.main_bg);
        }
    }
};
