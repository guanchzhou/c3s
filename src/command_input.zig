const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const Theme = @import("theme.zig");

pub const CommandInput = struct {
    allocator: std.mem.Allocator,
    visible: bool = false,
    input_text: std.ArrayListUnmanaged(u8),
    cursor_pos: u16 = 0,
    prompt: []const u8 = ":",

    pub fn init(allocator: std.mem.Allocator) CommandInput {
        return CommandInput{
            .allocator = allocator,
            .input_text = std.ArrayListUnmanaged(u8){},
        };
    }

    pub fn deinit(self: *CommandInput) void {
        self.input_text.deinit(self.allocator);
    }

    pub fn show(self: *CommandInput) void {
        self.visible = true;
        self.input_text.clearRetainingCapacity();
        self.cursor_pos = 0;
    }

    pub fn hide(self: *CommandInput) void {
        self.visible = false;
        self.input_text.clearRetainingCapacity();
        self.cursor_pos = 0;
    }

    pub fn toggle(self: *CommandInput) void {
        if (self.visible) {
            self.hide();
        } else {
            self.show();
        }
    }

    // Handle character input
    pub fn addChar(self: *CommandInput, char: u8) !void {
        if (!self.visible) return;
        
        try self.input_text.insert(self.allocator, self.cursor_pos, char);
        self.cursor_pos += 1;
    }

    // Handle backspace
    pub fn backspace(self: *CommandInput) void {
        if (!self.visible or self.cursor_pos == 0) return;
        
        self.cursor_pos -= 1;
        _ = self.input_text.orderedRemove(self.cursor_pos);
    }

    // Handle delete
    pub fn delete(self: *CommandInput) void {
        if (!self.visible or self.cursor_pos >= self.input_text.items.len) return;
        
        _ = self.input_text.orderedRemove(self.cursor_pos);
    }

    // Handle arrow keys for cursor movement
    pub fn moveCursorLeft(self: *CommandInput) void {
        if (self.cursor_pos > 0) {
            self.cursor_pos -= 1;
        }
    }

    pub fn moveCursorRight(self: *CommandInput) void {
        if (self.cursor_pos < self.input_text.items.len) {
            self.cursor_pos += 1;
        }
    }

    // Get the current command text
    pub fn getCommand(self: *CommandInput) []const u8 {
        return self.input_text.items;
    }

    // Clear the input
    pub fn clear(self: *CommandInput) void {
        self.input_text.clearRetainingCapacity();
        self.cursor_pos = 0;
    }

    pub fn render(self: *CommandInput, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        if (!self.visible) return;
        _ = height; // Single line input

        // Clear the command line area with theme background
        for (0..width) |i| {
            try Theme.writeStringWithTheme(terminal, @intCast(x + i), y, " ", Theme.main_fg, Theme.main_bg);
        }

        // Display prompt
        try Theme.writeStringWithTheme(terminal, x, y, self.prompt, Theme.hi_fg, Theme.main_bg);
        
        // Display input text
        const input_x = x + @as(u16, @intCast(self.prompt.len));
        if (self.input_text.items.len > 0) {
            const display_text = self.input_text.items;
            const max_display_width = width - @as(u16, @intCast(self.prompt.len)) - 2; // Leave space for cursor
            
            if (display_text.len <= max_display_width) {
                try Theme.writeStringWithTheme(terminal, input_x, y, display_text, Theme.main_fg, Theme.main_bg);
            } else {
                // Scroll text if too long
                const start_pos = if (self.cursor_pos >= max_display_width) 
                    self.cursor_pos - max_display_width + 1 
                else 
                    0;
                const end_pos = @min(start_pos + max_display_width, display_text.len);
                try Theme.writeStringWithTheme(terminal, input_x, y, display_text[start_pos..end_pos], Theme.main_fg, Theme.main_bg);
            }
        }

        // Show cursor at current position
        const cursor_x = input_x + self.cursor_pos;
        if (cursor_x < x + width - 1) {
            try terminal.setCursor(cursor_x, y);
            try terminal.showCursor();
        }
    }
};
