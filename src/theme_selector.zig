const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const Theme = @import("theme.zig");
const BoxDrawing = @import("box_drawing.zig");
const theme_loader = @import("theme_loader.zig");

const ThemeInfo = struct {
    name: []const u8,
    author: []const u8,
    path: []const u8,
};

pub const ThemeSelector = struct {
    allocator: std.mem.Allocator,
    themes: std.ArrayListUnmanaged(ThemeInfo),
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    visible: bool = false,
    current_theme_name: []const u8,
    preview_theme: ?*theme_loader.ThemeColors = null,
    
    pub fn init(allocator: std.mem.Allocator, current_theme: []const u8) !ThemeSelector {
        var selector = ThemeSelector{
            .allocator = allocator,
            .themes = std.ArrayListUnmanaged(ThemeInfo){},
            .current_theme_name = current_theme,
        };
        
        try selector.scanThemes();
        return selector;
    }
    
    pub fn deinit(self: *ThemeSelector) void {
        for (self.themes.items) |theme_info| {
            self.allocator.free(theme_info.name);
            self.allocator.free(theme_info.author);
            self.allocator.free(theme_info.path);
        }
        self.themes.deinit(self.allocator);
        
        if (self.preview_theme) |preview| {
            theme_loader.deinitTheme(preview);
            self.allocator.destroy(preview);
        }
    }
    
    pub fn show(self: *ThemeSelector) void {
        self.visible = true;
    }
    
    pub fn hide(self: *ThemeSelector) void {
        self.visible = false;
    }
    
    fn scanThemes(self: *ThemeSelector) !void {
        // Scan bundled themes directory
        try self.scanDirectory("themes");
        
        // Scan user themes directory ($XDG_CONFIG_HOME/c3s/skins)
        const xdg = @import("xdg.zig");
        const paths = xdg.ensurePaths() catch return;
        const skins_dir = try std.fs.path.join(self.allocator, &[_][]const u8{ paths.config_dir, "skins" });
        defer self.allocator.free(skins_dir);
        
        self.scanDirectory(skins_dir) catch {}; // Ignore errors if directory doesn't exist
    }
    
    fn scanDirectory(self: *ThemeSelector, dir_path: []const u8) !void {
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch return;
        defer dir.close();
        
        var iterator = dir.iterate();
        while (try iterator.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".theme")) continue;
            
            // Extract theme name from filename (remove .theme extension)
            const name_end = entry.name.len - 6; // ".theme" = 6 chars
            const theme_name = try self.allocator.dupe(u8, entry.name[0..name_end]);
            
            // Read file to extract author
            const file_path = try std.fs.path.join(self.allocator, &[_][]const u8{ dir_path, entry.name });
            const author = try self.extractAuthor(file_path);
            
            try self.themes.append(self.allocator, ThemeInfo{
                .name = theme_name,
                .author = author,
                .path = file_path,
            });
        }
    }
    
    fn extractAuthor(self: *ThemeSelector, file_path: []const u8) ![]const u8 {
        const content = std.fs.cwd().readFileAlloc(self.allocator, file_path, 1024) catch {
            return self.allocator.dupe(u8, "Unknown");
        };
        defer self.allocator.free(content);
        
        // Look for 2nd line with author info
        var lines = std.mem.splitScalar(u8, content, '\n');
        _ = lines.next(); // Skip first line
        
        if (lines.next()) |second_line| {
            const trimmed = std.mem.trim(u8, second_line, " \t\r#");
            
            // Look for "by" or "By"
            if (std.mem.indexOf(u8, trimmed, "by ")) |pos| {
                const author_part = std.mem.trim(u8, trimmed[pos + 3..], " \t:");
                return self.allocator.dupe(u8, author_part);
            } else if (std.mem.indexOf(u8, trimmed, "By ")) |pos| {
                const author_part = std.mem.trim(u8, trimmed[pos + 3..], " \t:");
                return self.allocator.dupe(u8, author_part);
            } else if (std.mem.indexOf(u8, trimmed, "by: ")) |pos| {
                const author_part = std.mem.trim(u8, trimmed[pos + 4..], " \t");
                return self.allocator.dupe(u8, author_part);
            } else if (std.mem.indexOf(u8, trimmed, "By: ")) |pos| {
                const author_part = std.mem.trim(u8, trimmed[pos + 4..], " \t");
                return self.allocator.dupe(u8, author_part);
            }
        }
        
        return self.allocator.dupe(u8, "Unknown");
    }
    
    pub fn navigateUp(self: *ThemeSelector) !void {
        if (self.selected_row > 0) {
            self.selected_row -= 1;
            try self.updatePreview();
        }
    }
    
    pub fn navigateDown(self: *ThemeSelector) !void {
        if (self.selected_row < self.themes.items.len - 1) {
            self.selected_row += 1;
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
    
    pub fn render(self: *ThemeSelector, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        if (!self.visible) return;
        
        // Draw box
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, Theme.proc_box, Theme.main_bg, null, .rounded);
        
        // Draw title
        const title_x = x + 2;
        try Theme.writeText(terminal, title_x, y, BoxDrawing.Symbols.title_left, Theme.proc_box);
        try Theme.writeText(terminal, title_x + 1, y, "Available Themes", Theme.title);
        try Theme.writeText(terminal, title_x + 1 + 16, y, BoxDrawing.Symbols.title_right, Theme.proc_box);
        
        // Column headers
        const header_y = y + 1;
        try Theme.writeStringWithTheme(terminal, x + 2, header_y, "  NAME", Theme.title, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 32, header_y, "AUTHOR", Theme.title, Theme.main_bg);
        
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
            
            // Enabled marker
            const marker = if (is_current) "●" else " ";
            try Theme.writeStringWithTheme(terminal, x + 2, row_y, marker, Theme.status_running, bg_color);
            
            // Theme name
            try Theme.writeStringWithTheme(terminal, x + 4, row_y, theme_info.name, fg_color, bg_color);
            
            // Author
            try Theme.writeStringWithTheme(terminal, x + 32, row_y, theme_info.author, fg_color, bg_color);
        }
    }
};
