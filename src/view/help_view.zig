const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const BoxDrawing = @import("../ui/box_drawing.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");

/// HelpView - displays help information
pub const HelpView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    help_lines: std.ArrayListUnmanaged([]const u8),
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    visible_rows: u32 = 0,
    
    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !HelpView {
        var view = HelpView{
            .allocator = allocator,
            .theme = theme,
            .help_lines = std.ArrayListUnmanaged([]const u8){},
        };
        
        try view.loadHelpContent();
        return view;
    }
    
    pub fn cleanup(self: *HelpView) void {
        for (self.help_lines.items) |line| {
            self.allocator.free(line);
        }
        self.help_lines.deinit(self.allocator);
    }
    
    fn loadHelpContent(self: *HelpView) !void {
        // K9s-compatible help content with proper formatting
        const help_content = [_][]const u8{
            "C3S - Kubernetes TUI Client (k9s-compatible)",
            "",
            "RESOURCE                   GENERAL                    NAVIGATION",
            "  a       Attach             ?         Help             g         Goto Top",
            "  d       Describe           Ctrl-a    Aliases          Shift-g   Goto Bottom",
            "  e       Edit               :cmd      Command mode     Ctrl-b    Page Up",
            "  l       Logs               /term     Filter mode      Ctrl-f    Page Down",
            "  s       Shell              esc       Back/Clear       h         Left",
            "  y       YAML               tab       Field Next       l         Right",
            "  v       View               backtab   Field Previous   k         Up",
            "  Ctrl-d  Delete             Ctrl-r    Reload           j         Down",
            "  Ctrl-k  Kill               Ctrl-u    Command Clear    [         History Back",
            "  Shift-f Port-Forward       Ctrl-e    Toggle Header    ]         History Forward",
            "  Shift-l Logs Previous      Ctrl-g    Toggle Crumbs    -         Last Command",
            "  Shift-r Refresh            :q        Quit",
            "  t       Transfer           space     Mark",
            "  z       Sanitize           Ctrl-space Mark Range",
            "                             Ctrl-\\    Mark Clear",
            "                             Ctrl-s    Save",
            "",
            "Press ? or Esc to close help",
        };
        
        for (help_content) |line| {
            try self.help_lines.append(self.allocator, try self.allocator.dupe(u8, line));
        }
    }
    
    fn navigateUp(self: *HelpView) !void {
        if (self.selected_row > 0) {
            self.selected_row -= 1;
            // Adjust scroll if needed
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        }
    }
    
    fn navigateDown(self: *HelpView) !void {
        if (self.selected_row < self.help_lines.items.len - 1) {
            self.selected_row += 1;
            // Adjust scroll if needed
            if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }
    }
    
    fn gotoTop(self: *HelpView) !void {
        self.selected_row = 0;
        self.scroll_offset = 0;
    }
    
    fn gotoBottom(self: *HelpView) !void {
        if (self.help_lines.items.len > 0) {
            self.selected_row = @intCast(self.help_lines.items.len - 1);
            if (self.selected_row >= self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }
    }
    
    fn pageUp(self: *HelpView) !void {
        const page_size = self.visible_rows;
        if (self.selected_row >= page_size) {
            self.selected_row -= page_size;
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        } else {
            try self.gotoTop();
        }
    }
    
    fn pageDown(self: *HelpView) !void {
        const page_size = self.visible_rows;
        if (self.selected_row + page_size < self.help_lines.items.len) {
            self.selected_row += page_size;
            if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        } else {
            try self.gotoBottom();
        }
    }
    
    // View trait implementation
    pub fn createView(self: *HelpView) View {
        return View.create(HelpView, self, &vtable);
    }
    
    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinit,
    };
    
    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *HelpView = @ptrCast(@alignCast(ptr));
        
        self.visible_rows = if (height > 3) height - 3 else 0;
        
        // Draw box with theme colors
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, self.theme.proc_box, self.theme.main_bg, "Help", .rounded, self.theme.main_fg, self.theme.title);
        
        // Draw help content
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + self.visible_rows, self.help_lines.items.len);
        
        for (start_row..end_row, 0..) |line_idx, display_idx| {
            const line = self.help_lines.items[line_idx];
            const row_y = y + @as(u16, @intCast(display_idx)) + 1;
            
            try terminal.setCursor(x + 1, row_y);
            try terminal.writeAll(self.theme.main_fg);
            try terminal.writeAll(line);
            try terminal.writeAll("\x1b[0m");
        }
    }
    
    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *HelpView = @ptrCast(@alignCast(ptr));
        
        switch (key) {
            .char => |c| switch (c) {
                'j' => { try self.navigateDown(); return .handled; },
                'k' => { try self.navigateUp(); return .handled; },
                'g' => { try self.gotoTop(); return .handled; },
                'G' => { try self.gotoBottom(); return .handled; },
                else => return .not_handled,
            },
            .up => { try self.navigateUp(); return .handled; },
            .down => { try self.navigateDown(); return .handled; },
            .home => { try self.gotoTop(); return .handled; },
            .end => { try self.gotoBottom(); return .handled; },
            .page_up => { try self.pageUp(); return .handled; },
            .page_down => { try self.pageDown(); return .handled; },
            .escape => return .not_handled, // Let parent handle pop
            else => return .not_handled,
        }
    }
    
    fn onShow(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("HelpView: View activated", .{});
    }
    
    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("HelpView: View deactivated", .{});
    }
    
    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "help";
    }
    
    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.helpHints();
    }
    
    fn deinit(ptr: *anyopaque) void {
        const self: *HelpView = @ptrCast(@alignCast(ptr));
        self.cleanup();
    }
};
