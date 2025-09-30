const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const BoxDrawing = @import("../ui/box_drawing.zig");
const theme_loader = @import("../model/theme_loader.zig");

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
        const help_content = [_][]const u8{
            "C3S - Kubernetes TUI Client (k9s-compatible)",
            "",
            "RESOURCE:",
            "  <0>              all          <ctrl-a>         Aliases        <c>              Down",
            "  <1>              default      <esc>            Back/Clear     <shift-g>        Goto Bottom",
            "  <a>              Attach       <ctrl-u>         Command Clear  <g>              Goto Top",
            "  <shift-a>        Copy         <esc>            Command mode   <shift-d>        History Back",
            "  <ctrl-c>         Copy Namespace <tab>          Copy Namespace <j>              History Forward",
            "  <ctrl-d>         Delete       <delete>         Delete         <shift-j>        Last Used Command",
            "  <d>              Describe     <shift-k>        Delete         <l>              Logs",
            "  <e>              Edit         <?>              Help           <ctrl-f>         Page Down",
            "  <?>              Help         </>              Mark           <ctrl-b>         Page Up",
            "  <shift-j>        Jump Owner   <ctrl-l>         Mark Clear     <k>              Right",
            "  <ctrl-k>         Kill         <ctrl-space>     Mark Range     <k>              Up",
            "  <ctrl-l>         Kill Finalizers <n>           Logs",
            "  <l>              Logs         <ctrl-r>         Port-Forward",
            "  <shift-l>        Logs Previous <ctrl-p>        Port-Forward",
            "  <shift-f>        Port-Forward <ctrl-p>         Refresh",
            "  <ctrl-r>         Refresh      <ctrl-a>         Reload",
            "  <?>              Sanitize     <s>              Shell",
            "  <s>              Set Image",
            "  <z>              Shell",
            "  <y>              Show Node",
            "  <?>              Show PortForward",
            "  <shift-a>        Sort Age     <shift-n>        Sort Name",
            "  <shift-c>        Sort CPU     <shift-p>        Sort Namespace",
            "  <ctrl-x>         Sort CPU/L   <shift-o>        Sort Node",
            "  <shift-s>        Sort CPU/R   <shift-r>        Sort Ready",
            "  <ctrl-y>         Sort IP      <shift-t>        Sort Restart",
            "  <shift-m>        Sort MEM     <shift-a>        Sort Status",
            "  <ctrl-q>         Sort MEM/L   <ctrl-z>         Toggle Faults",
            "  <shift-z>        Sort MEM/R   <ctrl-w>         Toggle Wide",
            "  <shift-n>        Sort Name    <t>              Transfer",
            "  <shift-p>        Sort Namespace <v>            View",
            "  <shift-o>        Sort Node    <enter>          View",
            "  <shift-r>        Sort Ready   </>              YAML",
            "  <shift-t>        Sort Restart",
            "  <shift-a>        Sort Status",
            "  <ctrl-z>         Toggle Faults",
            "  <ctrl-w>         Toggle Wide",
            "  <t>              Transfer",
            "  <v>              View",
            "  <enter>          View",
            "  </>              YAML",
            "",
            "GENERAL:",
            "  <ctrl-a>         Aliases",
            "  <esc>            Back/Clear",
            "  <ctrl-u>         Command Clear",
            "  <esc>            Command mode",
            "  <tab>            Field Next",
            "  <shift-tab>      Field Previous",
            "  <?>              Help",
            "  </>              Mark",
            "  <ctrl-l>         Mark Clear",
            "  <ctrl-space>     Mark Range",
            "  <ctrl-r>         Reload",
            "  <:>              Toggle Command",
            "  <ctrl-e>         Toggle Crumbs",
            "  <ctrl-p>         Toggle Header",
            "",
            "HOTKEYS:",
            "  <c>              Down",
            "  <shift-g>        Goto Bottom",
            "  <g>              Goto Top",
            "  <shift-d>        History Back",
            "  <j>              History Forward",
            "  <shift-j>        Last Used Command",
            "  <l>              Logs",
            "  <ctrl-f>         Page Down",
            "  <ctrl-b>         Page Up",
            "  <k>              Right",
            "  <k>              Up",
            "",
            "Press Esc or q to close this help",
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
        .deinit = deinit,
    };
    
    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *HelpView = @ptrCast(@alignCast(ptr));
        
        self.visible_rows = if (height > 3) height - 3 else 0;
        
        // Draw box with theme colors
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, self.theme.proc_box, self.theme.main_bg, "Help", .rounded);
        
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
    
    fn deinit(ptr: *anyopaque) void {
        const self: *HelpView = @ptrCast(@alignCast(ptr));
        self.cleanup();
    }
};
