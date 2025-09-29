const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const Theme = @import("theme.zig");

pub const Footer = struct {
    allocator: std.mem.Allocator,
    current_resource: []const u8,
    current_view: ?[]const u8 = null, // Additional view status (e.g., "help")

    pub fn init(allocator: std.mem.Allocator) !Footer {
        return Footer{
            .allocator = allocator,
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

    pub fn render(self: *Footer, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        _ = height; // Fixed height

        // Fill the footer line with theme background
        for (0..width) |i| {
            try Theme.writeStringWithTheme(terminal, @intCast(x + i), y, " ", Theme.main_fg, Theme.main_bg);
        }

        // Display current resource and view status with padding like other components (offset by 1)
        // Use bold text without brackets, like btop: "pods | help" or just "pod"
        if (self.current_view) |view| {
            // Format: "resource | view" 
            var status_buffer: [64]u8 = undefined;
            const status_text = try std.fmt.bufPrint(&status_buffer, "{s} | {s}", .{ self.current_resource, view });
            try Theme.writeStringWithBold(terminal, x + 1, y, status_text, Theme.hi_fg, Theme.main_bg);
        } else {
            // Just the resource name
            try Theme.writeStringWithBold(terminal, x + 1, y, self.current_resource, Theme.hi_fg, Theme.main_bg);
        }
    }
};
