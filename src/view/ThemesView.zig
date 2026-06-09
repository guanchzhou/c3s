const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const TableState = @import("../ui/TableState.zig").TableState;
const runtime = @import("../core/runtime.zig");

/// ThemesView - displays and manages theme selection
pub const ThemesView = struct {
    theme: *const theme_loader.ThemeColors,
    table: TableState(ThemeInfo),
    current_theme_name: []u8,
    preview_theme: ?*theme_loader.ThemeColors = null,
    allocated_title: ?[]u8 = null,

    const ThemeInfo = struct {
        name: []const u8,
        path: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *ThemeInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.path);
        }
    };

    pub fn init(allocator: std.mem.Allocator, current_theme: []const u8, theme: *const theme_loader.ThemeColors) !ThemesView {
        var view = ThemesView{
            .theme = theme,
            .table = TableState(ThemeInfo).init(allocator),
            .current_theme_name = try allocator.dupe(u8, current_theme),
        };

        try view.scanThemes();

        // Initialize filtered indices to show all themes
        for (0..view.table.items.items.len) |i| {
            try view.table.filtered_indices.append(allocator, i);
        }

        // Find and select current theme by default
        for (view.table.filtered_indices.items, 0..) |theme_idx, idx| {
            if (std.mem.eql(u8, view.table.items.items[theme_idx].name, view.current_theme_name)) {
                view.table.selected_row = @intCast(idx);
                break;
            }
        }

        return view;
    }

    pub fn deinit(self: *ThemesView) void {
        self.table.deinit();
        self.table.allocator.free(self.current_theme_name);

        if (self.allocated_title) |allocated| {
            self.table.allocator.free(allocated);
        }

        if (self.preview_theme) |preview| {
            theme_loader.deinitTheme(preview);
            self.table.allocator.destroy(preview);
        }
    }

    fn scanThemes(self: *ThemesView) !void {
        // Scan user skins directory ($XDG_CONFIG_HOME/c3s/skins)
        const xdg = @import("../core/xdg.zig");
        if (xdg.ensurePaths()) |paths| {
            self.scanDirectory(paths.skins_dir) catch {};
        } else |_| {}

        // Scan skins relative to executable directory (installed location)
        var exe_dir_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        if (std.process.executableDirPath(runtime.io(), &exe_dir_buf)) |exe_dir_len| {
            const exe_dir = exe_dir_buf[0..exe_dir_len];
            const skins_path = std.fs.path.join(self.table.allocator, &[_][]const u8{ exe_dir, "skins" }) catch null;
            if (skins_path) |path| {
                defer self.table.allocator.free(path);
                self.scanDirectory(path) catch {};
            }
        } else |_| {}

        // Scan bundled skins directory relative to CWD (development fallback)
        self.scanDirectory("skins") catch {};

        // Sort alphabetically by name (stable, so first-found wins on dedup)
        std.mem.sort(ThemeInfo, self.table.items.items, {}, compareThemeInfo);

        // Deduplicate by name (keep first occurrence)
        if (self.table.items.items.len > 1) {
            var write: usize = 1;
            for (1..self.table.items.items.len) |read| {
                if (std.mem.eql(u8, self.table.items.items[read].name, self.table.items.items[write - 1].name)) {
                    self.table.allocator.free(self.table.items.items[read].name);
                    self.table.allocator.free(self.table.items.items[read].path);
                } else {
                    self.table.items.items[write] = self.table.items.items[read];
                    write += 1;
                }
            }
            self.table.items.items.len = write;
        }
    }

    fn compareThemeInfo(_: void, a: ThemeInfo, b: ThemeInfo) bool {
        return std.mem.lessThan(u8, a.name, b.name);
    }

    fn scanDirectory(self: *ThemesView, dir_path: []const u8) !void {
        Logger.debug("ThemesView: scanDirectory trying '{s}'", .{dir_path});
        var dir = std.Io.Dir.cwd().openDir(runtime.io(), dir_path, .{ .iterate = true }) catch |err| {
            Logger.debug("ThemesView: scanDirectory failed to open '{s}': {}", .{ dir_path, err });
            return;
        };
        defer dir.close(runtime.io());

        var count: usize = 0;
        var iterator = dir.iterate();
        while (try iterator.next(runtime.io())) |e| {
            if (e.kind == .file and std.mem.endsWith(u8, e.name, ".yaml")) {
                const name = e.name[0 .. e.name.len - ".yaml".len];
                try self.table.appendItem(.{
                    .name = try self.table.allocator.dupe(u8, name),
                    .path = try self.table.allocator.dupe(u8, dir_path),
                    .allocator = self.table.allocator,
                });
                count += 1;
            }
        }
        Logger.debug("ThemesView: scanDirectory '{s}' found {d} themes", .{ dir_path, count });
    }

    fn updatePreview(self: *ThemesView) !void {
        // Free previous preview if exists
        if (self.preview_theme) |preview| {
            theme_loader.deinitTheme(preview);
            self.table.allocator.destroy(preview);
            self.preview_theme = null;
        }

        // Load new preview theme (if we have a valid selection)
        const selected = self.table.getSelectedItem() orelse return;
        Logger.debug("ThemesView: Loading preview for '{s}' from '{s}'", .{ selected.name, selected.path });
        const preview = try self.table.allocator.create(theme_loader.ThemeColors);
        preview.* = try theme_loader.loadThemeFromDir(self.table.allocator, selected.name, selected.path);
        self.preview_theme = preview;
        Logger.debug("ThemesView: Preview loaded, main_bg='{s}'", .{preview.main_bg});
    }

    pub fn getSelectedThemeName(self: *const ThemesView) []const u8 {
        const selected = self.table.getSelectedItem() orelse return "tokyo-night";
        return selected.name;
    }

    pub fn applyFilter(self: *ThemesView, filter: []const u8) !void {
        // Free old allocated title
        if (self.allocated_title) |allocated| {
            self.table.allocator.free(allocated);
            self.allocated_title = null;
        }

        try self.table.applyFilter(filter, themeMatchFn);

        // Update preview after filtering
        try self.updatePreview();
    }

    fn themeMatchFn(theme_info: *const ThemeInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, theme_info.name, filter) != null;
    }

    pub fn setCurrentTheme(self: *ThemesView, theme_name: []const u8) !void {
        // Free old current_theme_name
        self.table.allocator.free(self.current_theme_name);
        // Allocate new one
        self.current_theme_name = try self.table.allocator.dupe(u8, theme_name);
    }

    /// Returns true if the key is a navigation key that may change selection
    fn isNavigationKey(key: Key) bool {
        return switch (key) {
            .char => |c| c == 'j' or c == 'k' or c == 'g',
            .up, .down, .page_up, .page_down, .home, .end => true,
            .shift_g => true,
            else => false,
        };
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
        if (self.table.filter_text.len > 0) {
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
        .deinit = deinitView,
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
        self.table.visible_rows = visible_rows;

        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |theme_idx, display_idx| {
            const theme_info = self.table.items.items[theme_idx];
            const row_y = header_y + @as(u16, @intCast(display_idx)) + 1;

            const is_selected = self.table.isSelected(display_idx);
            const is_current = std.mem.eql(u8, theme_info.name, self.current_theme_name);

            // Fill row background
            if (width > 0) {
                try terminal.fillRow(x, row_y, width, active_theme.main_fg, if (is_selected) active_theme.selected_bg else active_theme.main_bg);
            }

            // Enabled marker (small bullet, same as pods page)
            const marker = if (is_current) "\xe2\x80\xa2" else " ";
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

        const is_nav = isNavigationKey(key);

        // Common navigation keys handled by TableState
        if (self.table.handleNavigationKey(key)) |result| {
            if (is_nav) {
                self.updatePreview() catch |err| {
                    Logger.err("ThemesView: Failed to update preview after nav: {}", .{err});
                };
            }
            return result;
        }

        // Handle shift_g (gotoBottom) - terminal parses 'G' as shift_g, not char
        switch (key) {
            .shift_g => {
                self.table.gotoBottom();
                self.updatePreview() catch |err| {
                    Logger.err("ThemesView: Failed to update preview after gotoBottom: {}", .{err});
                };
                return .handled;
            },
            .enter => {
                // Theme selected - return request to execute command
                Logger.info("ThemesView: Theme selected: {s}", .{self.getSelectedThemeName()});
                return .request_command_palette;
            },
            .escape => return .not_handled, // Let parent handle pop
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *ThemesView = @ptrCast(@alignCast(ptr));
        Logger.info("ThemesView: View activated, current theme: {s}, total skins: {d}", .{ self.current_theme_name, self.table.items.items.len });
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

    fn deinitView(ptr: *anyopaque) void {
        const self: *ThemesView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};
