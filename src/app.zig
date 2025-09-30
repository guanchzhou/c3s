const std = @import("std");
const posix = std.posix;
const terminal = @import("core/terminal.zig");
const Terminal = terminal.Terminal;
const Key = terminal.Key;
const Header = @import("ui/header.zig").Header;
const Footer = @import("ui/footer.zig").Footer;
const CommandInput = @import("ui/command_input.zig").CommandInput;
const Theme = @import("theme.zig");
const Cli = @import("cli.zig");
const Config = @import("model/config.zig");
const Logger = @import("core/logger.zig");
const version = @import("model/version.zig");
const theme_loader = @import("model/theme_loader.zig");

// MVVM imports
const View = @import("viewmodel/view.zig").View;
const ViewManager = @import("viewmodel/view_manager.zig").ViewManager;
const Command = @import("viewmodel/command.zig").Command;
const CommandRegistry = @import("viewmodel/command.zig").CommandRegistry;

// View imports
const PodsView = @import("view/pods_view.zig").PodsView;
const ThemesView = @import("view/themes_view.zig").ThemesView;
const HelpView = @import("view/help_view.zig").HelpView;

pub const App = struct {
    allocator: std.mem.Allocator,
    terminal: Terminal,
    header: Header,
    footer: Footer,
    command_input: CommandInput,
    config: Cli.Config,
    running: bool = true,
    prev_width: u16 = 0,
    prev_height: u16 = 0,
    header_height: u16 = 8,
    footer_visible: bool = true,
    dirty: bool = true,
    last_render_time: i128 = 0,
    min_frame_time_ns: i128 = 16_666_667, // ~60 FPS (16.67ms)
    current_theme_name: []const u8,
    
    // MVVM components
    view_manager: ViewManager,
    command_registry: CommandRegistry,
    theme: *theme_loader.ThemeColors,
    
    // Views
    pods_view: *PodsView,
    themes_view: *ThemesView,
    help_view: *HelpView,

    pub fn init(allocator: std.mem.Allocator, config: Cli.Config) !App {
        // Initialize terminal
        const term = try Terminal.init(allocator);

        // Load UI config from file
        const ui_config = Config.load(allocator) catch Config.Config{
            .allocator = allocator,
            .ui = Config.UiConfig{},
            .theme_owned = null,
        };
        defer ui_config.deinit();

        // Load theme
        const theme = try allocator.create(theme_loader.ThemeColors);
        theme.* = try theme_loader.loadTheme(allocator, ui_config.ui.theme);

        // Initialize MVVM components
        const view_manager = try ViewManager.init(allocator);
        const command_registry = try CommandRegistry.init(allocator);
        
        // Initialize views
        const pods_view = try allocator.create(PodsView);
        pods_view.* = try PodsView.init(allocator, theme);
        
        const themes_view = try allocator.create(ThemesView);
        themes_view.* = try ThemesView.init(allocator, ui_config.ui.theme, theme);
        
        const help_view = try allocator.create(HelpView);
        help_view.* = try HelpView.init(allocator, theme);

        // Initialize components
        var header = try Header.init(allocator);
        const footer = try Footer.init(allocator);
        const command_input = try CommandInput.init(allocator, theme);
        
        // Apply UI config
        header.setCompact(ui_config.ui.compact);

        // Create app
        var app = App{
            .allocator = allocator,
            .terminal = term,
            .header = header,
            .footer = footer,
            .command_input = command_input,
            .config = config,
            .footer_visible = ui_config.ui.footer,
            .current_theme_name = try allocator.dupe(u8, ui_config.ui.theme),
            .view_manager = view_manager,
            .command_registry = command_registry,
            .theme = theme,
            .pods_view = pods_view,
            .themes_view = themes_view,
            .help_view = help_view,
        };
        
        // Register commands
        try app.registerCommands();
        
        // Push initial view (pods)
        try app.view_manager.pushView(app.pods_view.createView());
        
        return app;
    }

    pub fn deinit(self: *App) void {
        // Clean up views
        self.pods_view.cleanup();
        self.allocator.destroy(self.pods_view);
        
        self.themes_view.cleanup();
        self.allocator.destroy(self.themes_view);
        
        self.help_view.cleanup();
        self.allocator.destroy(self.help_view);
        
        // Clean up MVVM components
        self.view_manager.deinit();
        self.command_registry.deinit();
        
        // Clean up theme
        theme_loader.deinitTheme(self.theme);
        self.allocator.destroy(self.theme);
        
        // Clean up other components
        self.header.deinit();
        self.footer.deinit();
        self.command_input.deinit();
        self.allocator.free(self.current_theme_name);
        self.terminal.deinit();
    }

    fn registerCommands(self: *App) !void {
        // Quit command
        try self.command_registry.register("q", Command{
            .name = "q",
            .execute = quitCommand,
        });
        try self.command_registry.register("quit", Command{
            .name = "quit", 
            .execute = quitCommand,
        });
        
        // Themes command
        try self.command_registry.register("themes", Command{
            .name = "themes",
            .execute = themesCommand,
        });
        try self.command_registry.register("skins", Command{
            .name = "skins",
            .execute = themesCommand,
        });
        
        // Help command
        try self.command_registry.register("help", Command{
            .name = "help",
            .execute = helpCommand,
        });
        
        // Theme selection command (when Enter is pressed in themes view)
        try self.command_registry.register("select_theme", Command{
            .name = "select_theme",
            .execute = selectThemeCommand,
        });
    }

    pub fn run(self: *App) !void {
        try self.terminal.enterAlternateScreen();
        defer _ = self.terminal.exitAlternateScreen() catch {};

        try self.terminal.hideCursor();
        defer _ = self.terminal.showCursor() catch {};

        try self.terminal.enableRawMode();
        defer self.terminal.disableRawMode();

        self.dirty = true;
        self.prev_width = 0;
        self.prev_height = 0;

        while (self.running) {
            try self.renderIfNeeded();

            var pollfds = [_]posix.pollfd{
                posix.pollfd{ .fd = self.terminal.stdin.handle, .events = posix.POLL.IN, .revents = 0 },
            };

            const poll_result = posix.poll(&pollfds, -1) catch |err| {
                return err;
            };

            if (poll_result == 0) continue;

            const events = pollfds[0].revents;
            if ((events & posix.POLL.IN) != 0) {
                if (try self.terminal.readKey()) |key| {
                    try self.handleKey(key);
                }
            }

            if ((events & (posix.POLL.ERR | posix.POLL.HUP | posix.POLL.NVAL)) != 0) {
                self.running = false;
            }
        }
    }

    fn renderIfNeeded(self: *App) !void {
            const size = try self.terminal.getSize();
            const size_changed = self.prev_width != size.width or self.prev_height != size.height;
        if (!size_changed and !self.dirty) return;

        // Rate limit rendering to prevent excessive updates (60 FPS max)
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_render_time;
        if (!size_changed and elapsed < self.min_frame_time_ns) {
            return;
        }
        self.last_render_time = now;

        // Start DEC synchronized output mode
        try self.terminal.beginSyncOutput();
        defer self.terminal.endSyncOutput() catch {};

        const new_header_height = self.header.height();
        const header_height_changed = self.header_height != new_header_height;
        self.header_height = new_header_height;
        const footer_height: u16 = if (self.footer_visible) 1 else 0;
        const command_height: u16 = if (self.command_input.visible) 1 else 0;

        // Clear on resize OR header size change (compact toggle)
        if (size_changed or header_height_changed) {
                    try self.terminal.clear();
        }

        // Render header
        if (size.height >= self.header_height) {
            try self.header.render(&self.terminal, 0, 0, size.width, self.header_height);
        }

        // Calculate body area
        const body_start = if (size.height >= self.header_height + command_height) 
            self.header_height + command_height 
        else 
            size.height;
        var body_height: u16 = 0;
        if (size.height > body_start) {
            const remaining = size.height - body_start;
            body_height = if (remaining > footer_height) remaining - footer_height else remaining;
        }

        // Render current view
        if (body_height > 0) {
            if (self.view_manager.getCurrentView()) |current_view| {
                try current_view.render(&self.terminal, 0, body_start, size.width, body_height);
            }
        }

        // Render footer (only if visible)
        if (self.footer_visible and size.height >= footer_height and size.height > 0) {
            const footer_y = if (body_height > 0)
                body_start + body_height
            else if (size.height > 0)
                size.height - 1
            else
                0;
            if (footer_y < size.height) {
                try self.footer.render(&self.terminal, 0, footer_y, size.width, footer_height);
            }
        }

        // Render command input
        if (self.command_input.visible and size.height > self.header_height) {
            try self.command_input.render(&self.terminal, 0, self.header_height, size.width);
        } else {
            try self.terminal.hideCursor();
                }

                try self.terminal.flush();
                self.prev_width = size.width;
                self.prev_height = size.height;
                self.dirty = false;
            }

    fn handleKey(self: *App, key: Key) !void {
        // Handle command input first
        if (self.command_input.visible) {
            switch (key) {
                .char => |c| {
                    if (c >= 32 and c <= 126) {
                        try self.command_input.addChar(c);
                self.dirty = true;
            }
                },
                .backspace => {
                    self.command_input.backspace();
                self.dirty = true;
                },
                .enter => {
                    // Process command
                    const cmd_text = self.command_input.getCommand();
                    const prompt = self.command_input.prompt;
                    
                    if (std.mem.eql(u8, prompt, "/")) {
                        // Apply filter to current view
                        if (self.view_manager.getCurrentView()) |current_view| {
                            if (std.mem.eql(u8, current_view.getName(), "pods")) {
                                try self.pods_view.applyFilter(cmd_text);
                            } else if (std.mem.eql(u8, current_view.getName(), "themes")) {
                                try self.themes_view.applyFilter(cmd_text);
                            }
                        }
                    } else if (std.mem.eql(u8, prompt, ":")) {
                    // Execute command
                    var ctx = Command.CommandContext{
                        .allocator = self.allocator,
                        .view_manager = &self.view_manager,
                        .data = self,
                    };
                    _ = try self.command_registry.execute(cmd_text, &ctx);
                    }
                    
                    self.command_input.hide();
                self.dirty = true;
                },
                .escape => {
                    self.command_input.hide();
                self.dirty = true;
                },
                else => {},
            }
            return;
        }

        // Handle global keys
        switch (key) {
            .char => |c| switch (c) {
                'h' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'j' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'k' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'l' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'g' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'G' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'x' => {
                    // Clear filter with 'x' key (like delete)
                    if (self.view_manager.getCurrentView()) |current_view| {
                        if (std.mem.eql(u8, current_view.getName(), "pods")) {
                            try self.pods_view.applyFilter("");
                            self.dirty = true;
                        } else if (std.mem.eql(u8, current_view.getName(), "themes")) {
                            try self.themes_view.applyFilter("");
                            self.dirty = true;
                        }
                    }
                },
                '/' => {
                    self.command_input.showWithPrompt("/");
                    self.dirty = true;
                },
                ':' => {
                    self.command_input.showWithPrompt(":");
                    self.dirty = true;
                },
                '?' => {
                    // Show help view
                    try self.view_manager.pushView(self.help_view.createView());
                self.dirty = true;
                },
                else => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        switch (result) {
                            .handled => self.dirty = true,
                            .not_handled => {},
                            .request_command_palette => {
                                // Check if we're in themes view and Enter was pressed
                                if (std.mem.eql(u8, current_view.getName(), "themes") and key == .enter) {
                                    // Execute theme selection directly
                                    const selected_theme = self.themes_view.getSelectedThemeName();
                                    try self.saveThemeToConfig(selected_theme);
                                    try self.themes_view.setCurrentTheme(selected_theme);
                self.dirty = true;
            } else {
                                    self.command_input.showWithPrompt(":");
                                    self.dirty = true;
                                }
                            },
                            .request_filter => {
                                self.command_input.showWithPrompt("/");
                                self.dirty = true;
                            },
                            .request_quit => {
                self.running = false;
                            },
                        }
                    }
                },
            },
            .up => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .down => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .left => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .right => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .home => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .end => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .page_up => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .page_down => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .escape => {
                // Check if we're in a sub-view first
                if (self.view_manager.getDepth() > 1) {
                    // Pop current view (go back)
                    _ = self.view_manager.popView();
                    self.dirty = true;
                } else {
                    // Clear filter if one is active
                    if (self.view_manager.getCurrentView()) |current_view| {
                        if (std.mem.eql(u8, current_view.getName(), "pods")) {
                            try self.pods_view.applyFilter("");
                            self.dirty = true;
                        } else if (std.mem.eql(u8, current_view.getName(), "themes")) {
                            try self.themes_view.applyFilter("");
                            self.dirty = true;
                        }
                    }
                }
            },
            .ctrl_c => {
                // Ctrl+C doesn't exit in k9s, use :q command instead
            },
            .ctrl_d => {
                // Ctrl+D reserved for delete action (k9s compat)
            },
            .shift_g => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .ctrl_f => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .ctrl_b => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .question_mark => {
                // Show help view
                try self.view_manager.pushView(self.help_view.createView());
                self.dirty = true;
            },
            .colon => {
                self.command_input.showWithPrompt(":");
                self.dirty = true;
            },
            .backspace => {},
            .enter => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    switch (result) {
                        .handled => self.dirty = true,
                        .not_handled => {},
                        .request_command_palette => {
                            // Check if we're in themes view and Enter was pressed
                            if (std.mem.eql(u8, current_view.getName(), "themes")) {
                                // Execute theme selection directly
                                const selected_theme = self.themes_view.getSelectedThemeName();
                                try self.saveThemeToConfig(selected_theme);
                                try self.themes_view.setCurrentTheme(selected_theme);
                self.dirty = true;
                            } else {
                                self.command_input.showWithPrompt(":");
                self.dirty = true;
                            }
                        },
                        .request_filter => {
                            self.command_input.showWithPrompt("/");
                self.dirty = true;
                        },
                        .request_quit => {
                            self.running = false;
                        },
                    }
                }
            },
            .unsupported => {},
            .ctrl_e => {
                self.header.toggleCompact();
                self.dirty = true;
            },
        }
    }
    
    fn saveThemeToConfig(self: *App, theme_name: []const u8) !void {
        Logger.info("Changing theme to: {s}", .{theme_name});
        
        const xdg = @import("core/xdg.zig");
        const paths = try xdg.ensurePaths();
        
        // Read existing config or create new one
        const existing_content = std.fs.cwd().readFileAlloc(
            self.allocator,
            paths.config_file,
            1024 * 1024,
        ) catch "";
        defer if (existing_content.len > 0) self.allocator.free(existing_content);
        
        // Build new config with updated theme
        var new_config = try std.ArrayList(u8).initCapacity(self.allocator, 1024);
        defer new_config.deinit(self.allocator);
        
        var found_theme_line = false;
        var in_ui_section = false;
        
        var lines = std.mem.splitScalar(u8, existing_content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            
            // Check for ui section
            if (std.mem.indexOf(u8, trimmed, "ui:")) |_| {
                in_ui_section = true;
                try new_config.appendSlice(self.allocator, line);
                try new_config.append(self.allocator, '\n');
                continue;
            }
            
            // Update theme line if in ui section
            if (in_ui_section) {
                if (std.mem.indexOf(u8, trimmed, "theme:")) |_| {
                    const theme_line = try std.fmt.allocPrint(self.allocator, "    theme: {s}\n", .{theme_name});
                    defer self.allocator.free(theme_line);
                    try new_config.appendSlice(self.allocator, theme_line);
                    found_theme_line = true;
                    continue;
                }
            }
            
            // Check if we left ui section
            if (in_ui_section and trimmed.len > 0 and trimmed[0] != ' ') {
                // Add theme line if not found yet
                if (!found_theme_line) {
                    const theme_line = try std.fmt.allocPrint(self.allocator, "    theme: {s}\n", .{theme_name});
                    defer self.allocator.free(theme_line);
                    try new_config.appendSlice(self.allocator, theme_line);
                    found_theme_line = true;
                }
                in_ui_section = false;
            }
            
            try new_config.appendSlice(self.allocator, line);
            try new_config.append(self.allocator, '\n');
        }
        
        // If no config existed, create minimal one
        if (existing_content.len == 0) {
            const default_config = try std.fmt.allocPrint(self.allocator, "c3s:\n  ui:\n    compact: false\n    theme: {s}\n", .{theme_name});
            defer self.allocator.free(default_config);
            try new_config.appendSlice(self.allocator, default_config);
        } else if (!found_theme_line) {
            // Config exists but no theme line, append it
            const theme_line = try std.fmt.allocPrint(self.allocator, "    theme: {s}\n", .{theme_name});
            defer self.allocator.free(theme_line);
            try new_config.appendSlice(self.allocator, theme_line);
        }
        
        // Write config file
        try std.fs.cwd().writeFile(.{
            .sub_path = paths.config_file,
            .data = new_config.items,
        });
        
        Logger.info("Theme saved to config successfully: {s}", .{theme_name});
        
        // Update current theme name
        self.allocator.free(self.current_theme_name);
        self.current_theme_name = try self.allocator.dupe(u8, theme_name);
        
        Logger.info("Current theme updated in memory: {s}", .{self.current_theme_name});
    }
};

// Command implementations
fn quitCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    app.running = false;
        Logger.info("Quit command executed", .{});
}

fn themesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    try ctx.view_manager.pushView(app.themes_view.createView());
    Logger.info("Themes command executed", .{});
}

fn helpCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    try ctx.view_manager.pushView(app.help_view.createView());
    Logger.info("Help command executed", .{});
}

fn selectThemeCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    const selected_theme = app.themes_view.getSelectedThemeName();
    try app.saveThemeToConfig(selected_theme);
    try app.themes_view.setCurrentTheme(selected_theme);
    Logger.info("Theme selected: {s}", .{selected_theme});
}