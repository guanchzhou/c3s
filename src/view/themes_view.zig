const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const BoxDrawing = @import("../ui/box_drawing.zig");

/// ThemesView - displays and manages theme selection
pub const ThemesView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    themes: std.ArrayListUnmanaged(ThemeInfo),
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    current_theme_name: []u8,
    preview_theme: ?*theme_loader.ThemeColors = null,
    
    const ThemeInfo = struct {
        name: []const u8,
        path: []const u8,
    };
    
    pub fn init(allocator: std.mem.Allocator, current_theme: []const u8, theme: *const theme_loader.ThemeColors) !ThemesView {
        var view = ThemesView{
            .allocator = allocator,
            .theme = theme,
            .themes = std.ArrayListUnmanaged(ThemeInfo){},
            .current_theme_name = try allocator.dupe(u8, current_theme),
        };
        
        try view.scanThemes();
        
        // Find and select current theme by default
        for (view.themes.items, 0..) |theme_info, idx| {
            if (std.mem.eql(u8, theme_info.name, view.current_theme_name)) {
                view.selected_row = @intCast(idx);
                break;
            }
        }
        
        return view;
    }
    
    pub fn cleanup(self: *ThemesView) void {
        for (self.themes.items) |theme_info| {
            self.allocator.free(theme_info.name);
            self.allocator.free(theme_info.path);
        }
        self.themes.deinit(self.allocator);
        self.allocator.free(self.current_theme_name);
        
        if (self.preview_theme) |preview| {
            theme_loader.deinitTheme(preview);
            self.allocator.destroy(preview);
        }
    }
    
    fn scanThemes(self: *ThemesView) !void {
        // Scan bundled skins directory
        try self.scanDirectory("skins");
        
        // Scan user skins directory ($XDG_CONFIG_HOME/c3s/skins)
        const xdg = @import("../core/xdg.zig");
        const paths = xdg.ensurePaths() catch return;
        self.scanDirectory(paths.skins_dir) catch {}; // Ignore errors if directory doesn't exist
        
        // Sort alphabetically by name
        std.mem.sort(ThemeInfo, self.themes.items, {}, compareThemeInfo);
    }
    
    fn compareThemeInfo(_: void, a: ThemeInfo, b: ThemeInfo) bool {
        return std.mem.lessThan(u8, a.name, b.name);
    }
    
    fn scanDirectory(self: *ThemesView, dir_path: []const u8) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |e| {
            if (e.kind == .file and std.mem.endsWith(u8, e.name, ".yaml")) {
                const name = std.mem.trimRight(u8, e.name, ".yaml");
                try self.themes.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, name),
                    .path = try self.allocator.dupe(u8, dir_path),
                });
            }
        }
    }
    
    fn navigateUp(self: *ThemesView) !void {
        if (self.selected_row > 0) {
            self.selected_row -= 1;
            Logger.debug("ThemesView: navigated to {s}", .{self.themes.items[self.selected_row].name});
            try self.updatePreview();
        }
    }
    
    fn navigateDown(self: *ThemesView) !void {
        if (self.selected_row < self.themes.items.len - 1) {
            self.selected_row += 1;
            Logger.debug("ThemesView: navigated to {s}", .{self.themes.items[self.selected_row].name});
            try self.updatePreview();
        }
    }
    
    fn gotoTop(self: *ThemesView) !void {
        if (self.themes.items.len > 0) {
            self.selected_row = 0;
            try self.updatePreview();
        }
    }
    
    fn gotoBottom(self: *ThemesView) !void {
        if (self.themes.items.len > 0) {
            self.selected_row = @intCast(self.themes.items.len - 1);
            try self.updatePreview();
        }
    }
    
    fn pageUp(self: *ThemesView) !void {
        const page_size: u32 = 10;
        if (self.selected_row >= page_size) {
            self.selected_row -= page_size;
        } else {
            self.selected_row = 0;
        }
        try self.updatePreview();
    }
    
    fn pageDown(self: *ThemesView) !void {
        const page_size: u32 = 10;
        if (self.selected_row + page_size < self.themes.items.len) {
            self.selected_row += page_size;
        } else if (self.themes.items.len > 0) {
            self.selected_row = @intCast(self.themes.items.len - 1);
        }
        try self.updatePreview();
    }
    
    fn updatePreview(self: *ThemesView) !void {
        // Free previous preview if exists
        if (self.preview_theme) |preview| {
            theme_loader.deinitTheme(preview);
            self.allocator.destroy(preview);
        }
        
        // Load new preview theme
        const selected_theme = self.themes.items[self.selected_row];
        const preview = try self.allocator.create(theme_loader.ThemeColors);
        preview.* = try theme_loader.loadTheme(self.allocator, selected_theme.name);
        self.preview_theme = preview;
    }
    
    pub fn getSelectedThemeName(self: *const ThemesView) []const u8 {
        if (self.themes.items.len == 0) return "tokyo-night";
        return self.themes.items[self.selected_row].name;
    }
    
    pub fn setCurrentTheme(self: *ThemesView, theme_name: []const u8) !void {
        // Free old current_theme_name
        self.allocator.free(self.current_theme_name);
        // Allocate new one
        self.current_theme_name = try self.allocator.dupe(u8, theme_name);
    }
    
    // View trait implementation
    pub fn createView(self: *ThemesView) View {
        return View.create(ThemesView, self, &vtable);
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
        const self: *ThemesView = @ptrCast(@alignCast(ptr));
        
        // Draw box using theme colors
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, self.theme.proc_box, self.theme.main_bg, null, .rounded);
        
        // Draw title with count using theme colors
        const title_x = x + 2;
        try terminal.setCursor(title_x, y);
        try terminal.writeAll(self.theme.proc_box);
        try terminal.writeAll(BoxDrawing.Symbols.title_left);
        try terminal.writeAll("\x1b[0m");
        
        // Render title with count: "Available Skins[35]"
        var title_buf: [64]u8 = undefined;
        const title_text = try std.fmt.bufPrint(&title_buf, "Available Skins[{d}]", .{self.themes.items.len});
        try terminal.setCursor(title_x + 1, y);
        try terminal.writeAll(self.theme.title);
        try terminal.writeAll(title_text);
        try terminal.writeAll("\x1b[0m");
        
        try terminal.setCursor(title_x + 1 + @as(u16, @intCast(title_text.len)), y);
        try terminal.writeAll(self.theme.proc_box);
        try terminal.writeAll(BoxDrawing.Symbols.title_right);
        try terminal.writeAll("\x1b[0m");
        
        // Column headers
        const header_y = y + 1;
        try terminal.setCursor(x + 2, header_y);
        try terminal.writeAll(self.theme.title);
        try terminal.writeAll("  NAME");
        try terminal.writeAll("\x1b[0m");
        
        // Render theme list
        const visible_rows = if (height > 3) height - 3 else 0;
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + visible_rows, self.themes.items.len);
        
        for (start_row..end_row, 0..) |theme_idx, display_idx| {
            const theme_info = self.themes.items[theme_idx];
            const row_y = header_y + @as(u16, @intCast(display_idx)) + 1;
            
            const is_selected = theme_idx == self.selected_row;
            const is_current = std.mem.eql(u8, theme_info.name, self.current_theme_name);
            
            // Fill row background
            if (width > 2) {
                try terminal.fillRow(x + 1, row_y, width - 2, self.theme.main_fg, 
                    if (is_selected) self.theme.selected_bg else self.theme.main_bg);
            }
            
            // Enabled marker (small bullet, same as pods page)
            const marker = if (is_current) "•" else " ";
            try terminal.setCursor(x + 2, row_y);
            if (is_selected) {
                try terminal.writeAll(self.theme.selected_fg);
                try terminal.writeAll(self.theme.selected_bg);
            } else {
                try terminal.writeAll(self.theme.status_running);
            }
            try terminal.writeAll(marker);
            try terminal.writeAll("\x1b[0m");
            
            // Skin name
            try terminal.setCursor(x + 4, row_y);
            if (is_selected) {
                try terminal.writeAll(self.theme.selected_fg);
                try terminal.writeAll(self.theme.selected_bg);
            } else {
                try terminal.writeAll(self.theme.main_fg);
            }
            try terminal.writeAll(theme_info.name);
            try terminal.writeAll("\x1b[0m");
        }
    }
    
    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *ThemesView = @ptrCast(@alignCast(ptr));
        
        switch (key) {
            .char => |c| switch (c) {
                'j' => { try self.navigateDown(); return .handled; },
                'k' => { try self.navigateUp(); return .handled; },
                'g' => { try self.gotoTop(); return .handled; },
                'G' => { try self.gotoBottom(); return .handled; },
                '/' => return .request_filter,
                ':' => return .request_command_palette,
                else => return .not_handled,
            },
            .up => { try self.navigateUp(); return .handled; },
            .down => { try self.navigateDown(); return .handled; },
            .home => { try self.gotoTop(); return .handled; },
            .end => { try self.gotoBottom(); return .handled; },
            .page_up => { try self.pageUp(); return .handled; },
            .page_down => { try self.pageDown(); return .handled; },
            .enter => {
                // Theme selected - return request to execute command
                Logger.info("ThemesView: Theme selected: {s}", .{self.getSelectedThemeName()});
                return .request_command_palette; // This will trigger the select_theme command
            },
            .escape => return .not_handled, // Let parent handle pop
            else => return .not_handled,
        }
    }
    
    fn onShow(ptr: *anyopaque) void {
        const self: *ThemesView = @ptrCast(@alignCast(ptr));
        Logger.info("ThemesView: View activated, current theme: {s}, total skins: {d}", .{ self.current_theme_name, self.themes.items.len });
    }
    
    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("ThemesView: View deactivated", .{});
    }
    
    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "themes";
    }
    
    fn deinit(ptr: *anyopaque) void {
        const self: *ThemesView = @ptrCast(@alignCast(ptr));
        self.cleanup();
    }
};
