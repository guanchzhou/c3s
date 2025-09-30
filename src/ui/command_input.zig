const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");

/// CommandInput - handles command line input with different prompts
pub const CommandInput = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    visible: bool = false,
    prompt: []const u8 = "",
    buffer: std.ArrayList(u8),
    cursor_pos: usize = 0,
    
    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !CommandInput {
        return CommandInput{
            .allocator = allocator,
            .theme = theme,
            .buffer = try std.ArrayList(u8).initCapacity(allocator, 256),
        };
    }
    
    pub fn deinit(self: *CommandInput) void {
        self.buffer.deinit(self.allocator);
    }
    
    pub fn showWithPrompt(self: *CommandInput, prompt: []const u8) void {
        self.visible = true;
        self.prompt = prompt;
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
        Logger.debug("CommandInput: Opened with prompt '{s}'", .{prompt});
    }
    
    pub fn hide(self: *CommandInput) void {
        self.visible = false;
        self.buffer.clearRetainingCapacity();
        self.cursor_pos = 0;
        Logger.debug("CommandInput: Closed", .{});
    }
    
    pub fn addChar(self: *CommandInput, c: u8) !void {
        if (c >= 32 and c <= 126) { // Printable ASCII
            try self.buffer.insert(self.allocator, self.cursor_pos, c);
            self.cursor_pos += 1;
        }
    }
    
    pub fn backspace(self: *CommandInput) void {
        if (self.cursor_pos > 0) {
            _ = self.buffer.orderedRemove(self.cursor_pos - 1);
            self.cursor_pos -= 1;
        }
    }
    
    pub fn getCommand(self: *CommandInput) []const u8 {
        return self.buffer.items;
    }
    
    pub fn render(self: *CommandInput, terminal: *Terminal, x: u16, y: u16, width: u16) !void {
        if (!self.visible) return;
        
        // Clear the line with prompt background color
        try terminal.setCursor(x, y);
        try terminal.writeAll(self.theme.prompt_bg);
        var spaces_buf: [256]u8 = undefined;
        @memset(&spaces_buf, ' ');
        var remaining: usize = width;
        while (remaining > 0) {
            const chunk = @min(remaining, spaces_buf.len);
            try terminal.writeAll(spaces_buf[0..chunk]);
            remaining -= chunk;
        }
        
        // Draw prompt and buffer with prompt colors
        try terminal.setCursor(x, y);
        try terminal.writeAll(self.theme.prompt_fg);
        try terminal.writeAll(self.theme.prompt_bg);
        var line_buf: [512]u8 = undefined;
        const line_text = try std.fmt.bufPrint(&line_buf, " {s} {s}", .{ self.prompt, self.buffer.items });
        try terminal.writeAll(line_text);
        try terminal.writeAll("\x1b[0m");
        
        // Position cursor after the text (accounting for leading space)
        try terminal.setCursor(x + @as(u16, @intCast(1 + self.prompt.len + 1 + self.cursor_pos)), y);
    }
};



