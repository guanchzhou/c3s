const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;

// btop-inspired Theme - Using Tokyo Night palette
// Based on btop's tokyo-night.theme for a modern, comfortable look

// Main colors - Tokyo Night inspired
pub const main_bg = "\x1b[49m";           // Terminal default background (transparent)
pub const main_fg = "\x1b[38;2;207;201;194m";     // #cfc9c2 -> light beige/gray
pub const title = "\x1b[38;2;207;201;194m";       // #cfc9c2 -> light beige/gray
pub const app_name = "\x1b[1;97m";                // Bold white for "c3s"
pub const hi_fg = "\x1b[38;2;125;207;255m";       // #7dcfff -> bright cyan
pub const selected_bg = "\x1b[48;2;65;72;104m";   // #414868 -> dark blue-gray
pub const selected_fg = "\x1b[38;2;207;201;194m"; // #cfc9c2 -> light beige/gray
pub const inactive_fg = "\x1b[38;2;86;95;137m";   // #565f89 -> muted blue-gray
pub const graph_text = "\x1b[38;2;207;201;194m";  // #cfc9c2 -> light beige/gray
pub const meter_bg = "\x1b[38;2;86;95;137m";      // #565f89 -> muted blue-gray
pub const proc_misc = "\x1b[38;2;125;207;255m";   // #7dcfff -> bright cyan
pub const cpu_box = "\x1b[38;2;86;95;137m";       // #565f89 -> muted blue-gray
pub const mem_box = "\x1b[38;2;86;95;137m";       // #565f89 -> muted blue-gray
pub const net_box = "\x1b[38;2;86;95;137m";       // #565f89 -> muted blue-gray
pub const proc_box = "\x1b[38;2;86;95;137m";      // #565f89 -> muted blue-gray
pub const div_line = "\x1b[38;2;86;95;137m";      // #565f89 -> muted blue-gray

// Status colors for pods (Tokyo Night palette)
pub const status_running = "\x1b[38;2;158;206;106m";  // #9ece6a -> green
pub const status_pending = "\x1b[38;2;224;175;104m";  // #e0af68 -> yellow
pub const status_failed = "\x1b[38;2;247;118;142m";   // #f7768e -> red
pub const status_succeeded = "\x1b[38;2;125;207;255m"; // #7dcfff -> cyan

// Keyboard shortcut colors (btop style)
pub const key_highlight = "\x1b[38;2;247;118;142m";   // #f7768e -> red for key letters
pub const shortcut_text = "\x1b[38;2;207;201;194m";    // #cfc9c2 -> light text for commands

// Reset sequence
pub const reset = "\x1b[0m";

// Text formatting
pub const bold = "\x1b[1m";
pub const unbold = "\x1b[22m";

// Helper function to write text with ANSI escape sequences directly
pub fn writeStringWithTheme(
    terminal: *Terminal,
    x: u16,
    y: u16,
    text: []const u8,
    fg_color: []const u8,
    bg_color: []const u8
) !void {
    // Build the full escape sequence: fg + bg + text + reset
    var buffer: [512]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buffer, "{s}{s}{s}{s}", .{ fg_color, bg_color, text, reset });
    try terminal.setCursor(x, y);
    try terminal.stdout.writeAll(formatted);
}

// Simplified color-only function for basic usage
pub fn writeText(
    terminal: *Terminal,
    x: u16,
    y: u16,
    text: []const u8,
    color: []const u8
) !void {
    try writeStringWithTheme(terminal, x, y, text, color, main_bg);
}

// Bold text function like btop uses
pub fn writeStringWithBold(
    terminal: *Terminal,
    x: u16,
    y: u16,
    text: []const u8,
    fg_color: []const u8,
    bg_color: []const u8
) !void {
    // Build the full escape sequence: bold + fg + bg + text + reset
    var buffer: [512]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buffer, "{s}{s}{s}{s}{s}", .{ bold, fg_color, bg_color, text, reset });
    try terminal.setCursor(x, y);
    try terminal.stdout.writeAll(formatted);
}

// btop-style shortcut rendering: key in red + command in bold
pub fn writeShortcut(
    terminal: *Terminal,
    x: u16,
    y: u16,
    key: []const u8,
    command: []const u8,
    bg_color: []const u8
) !void {
    var buffer: [512]u8 = undefined;
    // Format: <red_key> bold_command
    const formatted = try std.fmt.bufPrint(&buffer, "{s}{s}<{s}>{s} {s}{s}{s}", .{
        key_highlight, bg_color, key, reset,
        bold, command, reset
    });
    try terminal.setCursor(x, y);
    try terminal.stdout.writeAll(formatted);
}

// btop-style shortcut for commands with highlighted letter in middle
pub fn writeShortcutWithHighlight(
    terminal: *Terminal,
    x: u16,
    y: u16,
    before: []const u8,
    highlight_char: []const u8,
    after: []const u8,
    bg_color: []const u8
) !void {
    _ = bg_color; // Unused parameter
    // Write each part separately to avoid format string complexity
    try terminal.setCursor(x, y);
    try terminal.stdout.writeAll(bold);
    try terminal.stdout.writeAll(before);
    try terminal.stdout.writeAll(key_highlight);
    try terminal.stdout.writeAll(highlight_char);
    try terminal.stdout.writeAll(reset);
    try terminal.stdout.writeAll(bold);
    try terminal.stdout.writeAll(after);
    try terminal.stdout.writeAll(reset);
}

// NO background filling - btop uses terminal default background
// Remove this function entirely since btop doesn't fill background