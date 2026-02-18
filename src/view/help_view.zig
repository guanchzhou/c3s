const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const keybindings = @import("../model/keybindings.zig");
const KeyBindingsViewModel = @import("../viewmodel/keybindings_vm.zig").KeyBindingsViewModel;
const ViewType = @import("../viewmodel/keybindings_vm.zig").ViewType;

/// HelpView - displays help information
pub const HelpView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    help_lines: std.ArrayListUnmanaged([]const u8),
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    visible_rows: u32 = 0,
    bindings_vm: KeyBindingsViewModel,
    
    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !HelpView {
        // Default to pods bindings; updated via setViewType() when help is opened
        const bindings_vm = try KeyBindingsViewModel.init(allocator, .pods);
        
        var view = HelpView{
            .allocator = allocator,
            .theme = theme,
            .help_lines = std.ArrayListUnmanaged([]const u8){},
            .bindings_vm = bindings_vm,
        };
        
        try view.loadHelpContent();
        return view;
    }
    
    /// Update the help view to show keybindings for a different view type.
    /// Called before pushing the help view so it shows context-relevant bindings.
    pub fn setViewType(self: *HelpView, view_type: ViewType) !void {
        if (self.bindings_vm.view_type == view_type) return;

        // Clean up old bindings and help lines
        self.bindings_vm.deinit();
        for (self.help_lines.items) |line| {
            self.allocator.free(line);
        }
        self.help_lines.deinit(self.allocator);

        // Reinitialize with new view type
        self.bindings_vm = try KeyBindingsViewModel.init(self.allocator, view_type);
        self.help_lines = std.ArrayListUnmanaged([]const u8){};
        try self.loadHelpContent();

        // Reset scroll position
        self.selected_row = 0;
        self.scroll_offset = 0;
    }

    pub fn deinit(self: *HelpView) void {
        for (self.help_lines.items) |line| {
            self.allocator.free(line);
        }
        self.help_lines.deinit(self.allocator);
        self.bindings_vm.deinit();
    }
    
    fn loadHelpContent(self: *HelpView) !void {
        // Generate help content dynamically from key bindings model
        const bindings = self.bindings_vm.getBindings();
        self.help_lines = try keybindings.generateHelpContent(self.allocator, bindings);
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
        if (self.selected_row + 1 < self.help_lines.items.len) {
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
        .deinit = deinitView,
    };
    
    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, _: u16, height: u16) !void {
        const self: *HelpView = @ptrCast(@alignCast(ptr));

        self.visible_rows = if (height > 1) height - 1 else 0;

        // Draw help content
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + self.visible_rows, self.help_lines.items.len);

        for (start_row..end_row, 0..) |line_idx, display_idx| {
            const line = self.help_lines.items[line_idx];
            const row_y = y + @as(u16, @intCast(display_idx));

            try terminal.setCursor(x, row_y);
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
                else => return .not_handled,
            },
            .up => { try self.navigateUp(); return .handled; },
            .down => { try self.navigateDown(); return .handled; },
            .home => { try self.gotoTop(); return .handled; },
            .end => { try self.gotoBottom(); return .handled; },
            .shift_g => { try self.gotoBottom(); return .handled; },
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
    
    fn deinitView(ptr: *anyopaque) void {
        const self: *HelpView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
