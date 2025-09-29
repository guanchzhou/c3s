const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;

// btop Default Theme - Exact replica
// Note: btop uses "#00" for main_bg which means transparent/terminal default background

// btop exact color scheme from Default_theme using proper hex values
pub const main_bg = "\x1b[49m";           // #00 -> terminal default background (transparent)
pub const main_fg = "\x1b[38;5;204m";     // #cc -> light gray
pub const title = "\x1b[38;5;255m";       // #ee -> bright white  
pub const hi_fg = "\x1b[38;5;131m";       // #b54040 -> reddish brown
pub const selected_bg = "\x1b[48;5;52m";  // #6a2f2f -> dark red background
pub const selected_fg = "\x1b[38;5;255m"; // #ee -> bright white
pub const inactive_fg = "\x1b[38;5;238m"; // #40 -> dark gray
pub const graph_text = "\x1b[38;5;242m";  // #60 -> medium gray
pub const meter_bg = "\x1b[38;5;238m";    // #40 -> dark gray
pub const proc_misc = "\x1b[38;5;48m";    // #0de756 -> bright green
pub const cpu_box = "\x1b[38;5;65m";      // #556d59 -> green-gray
pub const mem_box = "\x1b[38;5;143m";     // #6c6c4b -> olive
pub const net_box = "\x1b[38;5;61m";      // #5c588d -> blue-purple
pub const proc_box = "\x1b[38;5;239m";    // #805252 -> very subtle, close to div_line
pub const div_line = "\x1b[38;5;236m";    // #30 -> very dark gray

// Status colors for pods
pub const status_running = "\x1b[38;5;46m";   // bright green
pub const status_pending = "\x1b[38;5;226m";  // bright yellow
pub const status_failed = "\x1b[38;5;196m";   // bright red
pub const status_succeeded = "\x1b[38;5;51m"; // bright cyan

// Keyboard shortcut colors (btop style)
pub const key_highlight = "\x1b[38;5;196m";   // bright red for key letters
pub const shortcut_text = "\x1b[37m";          // white for command text

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