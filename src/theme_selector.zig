const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const Theme = @import("theme.zig");
const BoxDrawing = @import("box_drawing.zig");
const theme_loader = @import("theme_loader.zig");

const ThemeInfo = struct {
    name: []const u8,
    path: []const u8,
};

pub const ThemeSelector = struct {
    allocator: std.mem.Allocator,
    themes: std.ArrayListUnmanaged(ThemeInfo),
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    visible: bool = false,
    current_theme_name: []u8,
    preview_theme: ?*theme_loader.ThemeColors = null,
    
    pub fn init(allocator: std.mem.Allocator, current_theme: []const u8) !ThemeSelector {
        var selector = ThemeSelector{
            .allocator = allocator,
            .themes = std.ArrayListUnmanaged(ThemeInfo){},
            .current_theme_name = try allocator.dupe(u8, current_theme),
        };
        
        try selector.scanThemes();
        
        // Find and select current theme by default
        for (selector.themes.items, 0..) |theme_info, idx| {
            if (std.mem.eql(u8, theme_info.name, selector.current_theme_name)) {
                selector.selected_row = @intCast(idx);
                break;
            }
        }
        
        return selector;
    }
    
    pub fn deinit(self: *ThemeSelector) void {
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
    
    pub fn show(self: *ThemeSelector) void {
        self.visible = true;
        const Logger = @import("logger.zig");
        Logger.info("Theme selector opened, current theme: {s}, total skins: {d}", .{ self.current_theme_name, self.themes.items.len });
    }
    
    pub fn hide(self: *ThemeSelector) void {
        self.visible = false;
    }
    
    fn scanThemes(self: *ThemeSelector) !void {
        // Scan bundled skins directory
        try self.scanDirectory("skins");
        
        // Scan user skins directory ($XDG_CONFIG_HOME/c3s/skins)
        const xdg = @import("xdg.zig");
        const paths = xdg.ensurePaths() catch return;
        self.scanDirectory(paths.skins_dir) catch {}; // Ignore errors if directory doesn't exist
        
        // Sort alphabetically by name
        std.mem.sort(ThemeInfo, self.themes.items, {}, compareThemeInfo);
    }
    
    fn compareThemeInfo(_: void, a: ThemeInfo, b: ThemeInfo) bool {
        return std.mem.lessThan(u8, a.name, b.name);
    }
    
    fn scanDirectory(self: *ThemeSelector, dir_path: []const u8) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".yaml")) continue;
            
            // Extract skin name from filename (remove .yaml extension)
            const name_end = entry.name.len - 5; // ".yaml" = 5 chars
            const skin_name = try self.allocator.dupe(u8, entry.name[0..name_end]);
            
            const file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.name });
            
            try self.themes.append(self.allocator, ThemeInfo{
                .name = skin_name,
                .path = file_path,
            });
        }
    }
    
    
    pub fn navigateUp(self: *ThemeSelector) !void {
        if (self.selected_row > 0) {
            self.selected_row -= 1;
            const Logger = @import("logger.zig");
            Logger.info("Theme selector: navigated to {s}", .{self.themes.items[self.selected_row].name});
            try self.updatePreview();
        }
    }
    
    pub fn navigateDown(self: *ThemeSelector) !void {
        if (self.selected_row < self.themes.items.len - 1) {
            self.selected_row += 1;
            const Logger = @import("logger.zig");
            Logger.info("Theme selector: navigated to {s}", .{self.themes.items[self.selected_row].name});
            try self.updatePreview();
        }
    }
    
    fn updatePreview(self: *ThemeSelector) !void {
        // Free previous preview if exists
        if (self.preview_theme) |preview| {
            theme_loader.deinitTheme(preview);
            self.allocator.destroy(preview);
            self.preview_theme = null;
        }
        
        // Load new preview theme
        const selected_theme = self.themes.items[self.selected_row];
        const preview = try self.allocator.create(theme_loader.ThemeColors);
        preview.* = try theme_loader.loadTheme(self.allocator, selected_theme.name);
        self.preview_theme = preview;
    }
    
    pub fn getSelectedThemeName(self: *const ThemeSelector) []const u8 {
        if (self.themes.items.len == 0) return "tokyo-night";
        return self.themes.items[self.selected_row].name;
    }
    
    pub fn setCurrentTheme(self: *ThemeSelector, theme_name: []const u8) !void {
        // Free old current_theme_name
        self.allocator.free(self.current_theme_name);
        // Allocate new one
        self.current_theme_name = try self.allocator.dupe(u8, theme_name);
    }
    
    pub fn render(self: *ThemeSelector, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        if (!self.visible) return;
        
        // Draw box
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, Theme.proc_box, Theme.main_bg, null, .rounded);
        
        // Draw title with count
        const title_x = x + 2;
        try Theme.writeText(terminal, title_x, y, BoxDrawing.Symbols.title_left, Theme.proc_box);
        
        // Render title with count: "Available Skins[35]"
        var title_buf: [64]u8 = undefined;
        const title_text = try std.fmt.bufPrint(&title_buf, "Available Skins[{d}]", .{self.themes.items.len});
        try Theme.writeText(terminal, title_x + 1, y, title_text, Theme.title);
        try Theme.writeText(terminal, title_x + 1 + @as(u16, @intCast(title_text.len)), y, BoxDrawing.Symbols.title_right, Theme.proc_box);
        
        // Column headers
        const header_y = y + 1;
        try Theme.writeStringWithTheme(terminal, x + 2, header_y, "  NAME", Theme.title, Theme.main_bg);
        
        // Render theme list
        const visible_rows = if (height > 3) height - 3 else 0;
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + visible_rows, self.themes.items.len);
        
        for (start_row..end_row, 0..) |theme_idx, display_idx| {
            const theme_info = self.themes.items[theme_idx];
            const row_y = header_y + @as(u16, @intCast(display_idx)) + 1;
            
            const is_selected = theme_idx == self.selected_row;
            const is_current = std.mem.eql(u8, theme_info.name, self.current_theme_name);
            
            const bg_color = if (is_selected) Theme.selected_bg else Theme.main_bg;
            const fg_color = if (is_selected) Theme.selected_fg else Theme.main_fg;
            
            // Fill row background
            if (width > 2) {
                try terminal.fillRow(x + 1, row_y, width - 2, fg_color, bg_color);
            }
            
            // Enabled marker (small bullet, same as pods page)
            const marker = if (is_current) "•" else " ";
            try Theme.writeStringWithTheme(terminal, x + 2, row_y, marker, Theme.status_running, bg_color);
            
            // Skin name
            try Theme.writeStringWithTheme(terminal, x + 4, row_y, theme_info.name, fg_color, bg_color);
        }
    }
};
