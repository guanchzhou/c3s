const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const universal_filter = @import("../viewmodel/filter.zig");
const hints_model = @import("../model/hints.zig");

/// ThemesView - displays and manages theme selection
pub const ThemesView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    themes: std.ArrayListUnmanaged(ThemeInfo),
    filtered_indices: std.ArrayListUnmanaged(usize),
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    visible_rows: u32 = 0,
    current_theme_name: []u8,
    preview_theme: ?*theme_loader.ThemeColors = null,
    filter_text: []const u8 = "",
    allocated_title: ?[]u8 = null,
    
    const ThemeInfo = struct {
        name: []const u8,
        path: []const u8,
    };
    
    pub fn init(allocator: std.mem.Allocator, current_theme: []const u8, theme: *const theme_loader.ThemeColors) !ThemesView {
        var view = ThemesView{
            .allocator = allocator,
            .theme = theme,
            .themes = std.ArrayListUnmanaged(ThemeInfo){},
            .filtered_indices = std.ArrayListUnmanaged(usize){},
            .current_theme_name = try allocator.dupe(u8, current_theme),
        };
        
        try view.scanThemes();
        
        // Initialize filtered indices to show all themes
        for (0..view.themes.items.len) |i| {
            try view.filtered_indices.append(allocator, i);
        }
        
        // Find and select current theme by default
        for (view.filtered_indices.items, 0..) |theme_idx, idx| {
            if (std.mem.eql(u8, view.themes.items[theme_idx].name, view.current_theme_name)) {
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
        self.filtered_indices.deinit(self.allocator);
        self.allocator.free(self.current_theme_name);
        
        if (self.allocated_title) |allocated| {
            self.allocator.free(allocated);
        }
        
        if (self.preview_theme) |preview| {
            theme_loader.deinitTheme(preview);
            self.allocator.destroy(preview);
        }
    }
    
    fn scanThemes(self: *ThemesView) !void {
        // Scan user skins directory ($XDG_CONFIG_HOME/c3s/skins)
        const xdg = @import("../core/xdg.zig");
        if (xdg.ensurePaths()) |paths| {
            self.scanDirectory(paths.skins_dir) catch {};
        } else |_| {}

        // Scan skins relative to executable directory (installed location)
        var exe_dir_buf: [std.fs.max_path_bytes]u8 = undefined;
        if (std.fs.selfExeDirPath(&exe_dir_buf)) |exe_dir| {
            const skins_path = std.fs.path.join(self.allocator, &[_][]const u8{ exe_dir, "skins" }) catch null;
            if (skins_path) |path| {
                defer self.allocator.free(path);
                self.scanDirectory(path) catch {};
            }
        } else |_| {}

        // Scan bundled skins directory relative to CWD (development fallback)
        self.scanDirectory("skins") catch {};

        // Sort alphabetically by name (stable, so first-found wins on dedup)
        std.mem.sort(ThemeInfo, self.themes.items, {}, compareThemeInfo);

        // Deduplicate by name (keep first occurrence)
        if (self.themes.items.len > 1) {
            var write: usize = 1;
            for (1..self.themes.items.len) |read| {
                if (std.mem.eql(u8, self.themes.items[read].name, self.themes.items[write - 1].name)) {
                    self.allocator.free(self.themes.items[read].name);
                    self.allocator.free(self.themes.items[read].path);
                } else {
                    self.themes.items[write] = self.themes.items[read];
                    write += 1;
                }
            }
            self.themes.items.len = write;
        }
    }
    
    fn compareThemeInfo(_: void, a: ThemeInfo, b: ThemeInfo) bool {
        return std.mem.lessThan(u8, a.name, b.name);
    }
    
    fn scanDirectory(self: *ThemesView, dir_path: []const u8) !void {
        Logger.debug("ThemesView: scanDirectory trying '{s}'", .{dir_path});
        var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch |err| {
            Logger.debug("ThemesView: scanDirectory failed to open '{s}': {}", .{ dir_path, err });
            return;
        };
        defer dir.close();
        
        var count: usize = 0;
        var iterator = dir.iterate();
        while (try iterator.next()) |e| {
            if (e.kind == .file and std.mem.endsWith(u8, e.name, ".yaml")) {
                const name = e.name[0 .. e.name.len - ".yaml".len];
                try self.themes.append(self.allocator, .{
                    .name = try self.allocator.dupe(u8, name),
                    .path = try self.allocator.dupe(u8, dir_path),
                });
                count += 1;
            }
        }
        Logger.debug("ThemesView: scanDirectory '{s}' found {d} themes", .{ dir_path, count });
    }
    
    fn navigateUp(self: *ThemesView) !void {
        if (self.selected_row > 0) {
            self.selected_row -= 1;
            
            // Adjust scroll if needed
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
            
            if (self.selected_row < self.filtered_indices.items.len) {
                const theme_idx = self.filtered_indices.items[self.selected_row];
                Logger.debug("ThemesView: navigated UP to {s}", .{self.themes.items[theme_idx].name});
            }
            try self.updatePreview();
        }
    }
    
    fn navigateDown(self: *ThemesView) !void {
        if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len - 1) {
            self.selected_row += 1;

            // Adjust scroll if needed
            if (self.visible_rows > 0 and self.selected_row >= self.scroll_offset + self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }

            const theme_idx = self.filtered_indices.items[self.selected_row];
            Logger.debug("ThemesView: navigated DOWN to {s}", .{self.themes.items[theme_idx].name});
            try self.updatePreview();
        }
    }
    
    fn gotoTop(self: *ThemesView) !void {
        if (self.filtered_indices.items.len > 0) {
            self.selected_row = 0;
            self.scroll_offset = 0;
            try self.updatePreview();
        }
    }
    
    fn gotoBottom(self: *ThemesView) !void {
        if (self.filtered_indices.items.len > 0) {
            self.selected_row = @intCast(self.filtered_indices.items.len - 1);
            
            // Scroll to show the last item
            if (self.visible_rows > 0 and self.selected_row >= self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            } else {
                self.scroll_offset = 0;
            }
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
        
        // Adjust scroll
        if (self.selected_row < self.scroll_offset) {
            self.scroll_offset = self.selected_row;
        }
        
        try self.updatePreview();
    }
    
    fn pageDown(self: *ThemesView) !void {
        const page_size: u32 = 10;
        if (self.filtered_indices.items.len > 0) {
            if (self.selected_row + page_size < self.filtered_indices.items.len) {
                self.selected_row += page_size;
            } else {
                self.selected_row = @intCast(self.filtered_indices.items.len - 1);
            }
            
            // Adjust scroll
            if (self.visible_rows > 0 and self.selected_row >= self.scroll_offset + self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }
        try self.updatePreview();
    }
    
    fn updatePreview(self: *ThemesView) !void {
        // Free previous preview if exists
        if (self.preview_theme) |preview| {
            theme_loader.deinitTheme(preview);
            self.allocator.destroy(preview);
            self.preview_theme = null;
        }

        // Load new preview theme (if we have filtered items)
        if (self.filtered_indices.items.len == 0 or self.selected_row >= self.filtered_indices.items.len) return;

        const theme_idx = self.filtered_indices.items[self.selected_row];
        const selected_theme = self.themes.items[theme_idx];
        Logger.debug("ThemesView: Loading preview for '{s}' from '{s}'", .{ selected_theme.name, selected_theme.path });
        const preview = try self.allocator.create(theme_loader.ThemeColors);
        preview.* = try theme_loader.loadThemeFromDir(self.allocator, selected_theme.name, selected_theme.path);
        self.preview_theme = preview;
        Logger.debug("ThemesView: Preview loaded, main_bg='{s}'", .{preview.main_bg});
    }
    
    pub fn getSelectedThemeName(self: *const ThemesView) []const u8 {
        if (self.filtered_indices.items.len == 0) return "tokyo-night";
        if (self.selected_row >= self.filtered_indices.items.len) return "tokyo-night";
        const theme_idx = self.filtered_indices.items[self.selected_row];
        return self.themes.items[theme_idx].name;
    }
    
    pub fn applyFilter(self: *ThemesView, filter: []const u8) !void {
        // Free old allocated title
        if (self.allocated_title) |allocated| {
            self.allocator.free(allocated);
            self.allocated_title = null;
        }
        
        self.filter_text = filter;
        
        // Use universal filter with current visible_rows (will be set during render)
        // If visible_rows is 0, use a default value for the first call
        const visible_rows = if (self.visible_rows > 0) self.visible_rows else 20;
        try universal_filter.applyFilter(
            ThemeInfo,
            self.allocator,
            self.themes.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            visible_rows,
            themeMatchFn,
        );
        
        // Update preview after filtering
        try self.updatePreview();
    }
    
    fn themeMatchFn(theme_info: *const ThemeInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, theme_info.name, filter) != null;
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
    
    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *ThemesView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }
    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *ThemesView = @ptrCast(@alignCast(ptr));
        if (self.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinit,
        .applyFilter = vtableApplyFilter,
        .clearFilter = vtableClearFilter,
    };
    
    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *ThemesView = @ptrCast(@alignCast(ptr));

        // Use preview theme if available, otherwise use base theme
        const active_theme = if (self.preview_theme) |preview| preview else self.theme;
        if (self.preview_theme != null) {
            Logger.debug("ThemesView: Rendering with PREVIEW theme", .{});
        } else {
            Logger.debug("ThemesView: Rendering with BASE theme", .{});
        }

        // Fill entire view area with theme background
        for (0..height) |row| {
            try terminal.fillRow(x, y + @as(u16, @intCast(row)), width, active_theme.main_fg, active_theme.main_bg);
        }

        // Column headers
        const header_y = y;
        try terminal.setCursor(x + 1, header_y);
        try terminal.writeAll(active_theme.title);
        try terminal.writeAll("  NAME");
        try terminal.writeAll("\x1b[0m");

        // Render theme list (using filtered indices)
        const visible_rows = if (height > 1) height - 1 else 0;
        self.visible_rows = visible_rows; // Store for navigation functions
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + visible_rows, self.filtered_indices.items.len);

        for (start_row..end_row, 0..) |filtered_idx, display_idx| {
            const theme_idx = self.filtered_indices.items[filtered_idx];
            const theme_info = self.themes.items[theme_idx];
            const row_y = header_y + @as(u16, @intCast(display_idx)) + 1;

            const is_selected = filtered_idx == self.selected_row;
            const is_current = std.mem.eql(u8, theme_info.name, self.current_theme_name);

            // Fill row background
            if (width > 0) {
                try terminal.fillRow(x, row_y, width, active_theme.main_fg,
                    if (is_selected) active_theme.selected_bg else active_theme.main_bg);
            }

            // Enabled marker (small bullet, same as pods page)
            const marker = if (is_current) "•" else " ";
            try terminal.setCursor(x + 1, row_y);
            if (is_selected) {
                try terminal.writeAll(active_theme.selected_fg);
                try terminal.writeAll(active_theme.selected_bg);
            } else {
                try terminal.writeAll(active_theme.status_running);
            }
            try terminal.writeAll(marker);
            try terminal.writeAll("\x1b[0m");

            // Skin name
            try terminal.setCursor(x + 3, row_y);
            if (is_selected) {
                try terminal.writeAll(active_theme.selected_fg);
                try terminal.writeAll(active_theme.selected_bg);
            } else {
                try terminal.writeAll(active_theme.main_fg);
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
                '/' => return .request_filter,
                ':' => return .request_command_palette,
                else => return .not_handled,
            },
            .up => { try self.navigateUp(); return .handled; },
            .down => { try self.navigateDown(); return .handled; },
            .home => { try self.gotoTop(); return .handled; },
            .end => { try self.gotoBottom(); return .handled; },
            .shift_g => { try self.gotoBottom(); return .handled; },
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
        // Load preview for initially selected theme
        self.updatePreview() catch |err| {
            Logger.err("ThemesView: Failed to load initial preview: {}", .{err});
        };
    }
    
    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("ThemesView: View deactivated", .{});
    }
    
    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "themes";
    }
    
    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.themesHints();
    }
    
    fn deinit(ptr: *anyopaque) void {
        const self: *ThemesView = @ptrCast(@alignCast(ptr));
        self.cleanup();
    }
};
