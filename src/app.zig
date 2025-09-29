const std = @import("std");
const posix = std.posix;
const terminal = @import("terminal.zig");
const Terminal = terminal.Terminal;
const Key = terminal.Key;
const Header = @import("header.zig").Header;
const Body = @import("body.zig").Body;
const Footer = @import("footer.zig").Footer;
const Help = @import("help.zig").Help;
const CommandInput = @import("command_input.zig").CommandInput;
const ThemeSelector = @import("theme_selector.zig").ThemeSelector;
const Theme = @import("theme.zig");
const Cli = @import("cli.zig");
const Config = @import("config.zig");
const Logger = @import("logger.zig");
const version = @import("version.zig");

pub const App = struct {
    allocator: std.mem.Allocator,
    terminal: Terminal,
    header: Header,
    body: Body,
    footer: Footer,
    help: Help,
    command_input: CommandInput,
    theme_selector: ThemeSelector,
    config: Cli.Config,
    running: bool = true,
    prev_width: u16 = 0,
    prev_height: u16 = 0,
    header_height: u16 = 8,
    dirty: bool = true,
    last_render_time: i128 = 0,
    min_frame_time_ns: i128 = 16_666_667, // ~60 FPS (16.67ms)
    current_theme_name: []const u8,

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

        // Initialize components
        var header = try Header.init(allocator);
        const body = try Body.init(allocator);
        const footer = try Footer.init(allocator);
        const help = try Help.init(allocator);
        const command_input = CommandInput.init(allocator);
        const theme_selector = try ThemeSelector.init(allocator, ui_config.ui.theme);
        
        // Apply UI config
        header.setCompact(ui_config.ui.compact);

        return App{
            .allocator = allocator,
            .terminal = term,
            .header = header,
            .body = body,
            .footer = footer,
            .help = help,
            .command_input = command_input,
            .theme_selector = theme_selector,
            .config = config,
            .current_theme_name = try allocator.dupe(u8, ui_config.ui.theme),
        };
    }

    pub fn deinit(self: *App) void {
        self.header.deinit();
        self.body.deinit();
        self.footer.deinit();
        self.help.deinit();
        self.command_input.deinit();
        self.theme_selector.deinit();
        self.allocator.free(self.current_theme_name);
        self.terminal.deinit();
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
            // Too soon since last render, skip to maintain smooth 60 FPS
            return;
        }
        self.last_render_time = now;

        // Start DEC synchronized output mode - terminal buffers everything until endSyncOutput
        try self.terminal.beginSyncOutput();
        defer self.terminal.endSyncOutput() catch {};

        const new_header_height = self.header.height();
        const header_height_changed = self.header_height != new_header_height;
        self.header_height = new_header_height;
        const footer_height: u16 = 1;
        const command_height: u16 = if (self.command_input.visible) 1 else 0;

        // Clear on resize OR header size change (compact toggle)
        if (size_changed or header_height_changed) {
            try self.terminal.clear();
            
            // On resize, render everything
            if (size.height >= self.header_height) {
                try self.header.render(&self.terminal, 0, 0, size.width, self.header_height);
            }

            const body_start = if (size.height >= self.header_height + command_height) 
                self.header_height + command_height 
            else 
                size.height;
            var body_height: u16 = 0;
            if (size.height > body_start) {
                const remaining = size.height - body_start;
                body_height = if (remaining > footer_height) remaining - footer_height else remaining;
            }

            if (body_height > 0) {
                try self.body.render(&self.terminal, 0, body_start, size.width, body_height);
            }

            if (self.help.visible and body_height > 0) {
                try self.help.render(&self.terminal, 0, body_start, size.width, body_height);
            }
            
            if (self.theme_selector.visible and body_height > 0) {
                try self.theme_selector.render(&self.terminal, 0, body_start, size.width, body_height);
            }

            if (size.height >= footer_height and size.height > 0) {
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
        } else {
            // Normal update - redraw all components
            // (header might have toggled compact mode, body has selection changes)
            
            if (size.height >= self.header_height) {
                try self.header.render(&self.terminal, 0, 0, size.width, self.header_height);
            }
            
            const body_start = if (size.height >= self.header_height + command_height) 
                self.header_height + command_height 
            else 
                size.height;
            var body_height: u16 = 0;
            if (size.height > body_start) {
                const remaining = size.height - body_start;
                body_height = if (remaining > footer_height) remaining - footer_height else remaining;
            }

            if (body_height > 0) {
                try self.body.render(&self.terminal, 0, body_start, size.width, body_height);
            }

            if (self.help.visible and body_height > 0) {
                try self.help.render(&self.terminal, 0, body_start, size.width, body_height);
            }
            
            if (self.theme_selector.visible and body_height > 0) {
                try self.theme_selector.render(&self.terminal, 0, body_start, size.width, body_height);
            }
            
            if (size.height >= footer_height and size.height > 0) {
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
        }

        if (self.command_input.visible and size.height > self.header_height) {
            // Render command input between header and body
            try self.command_input.render(&self.terminal, 0, self.header_height, size.width, 1);
        } else {
            // Hide cursor when not in command mode
            try self.terminal.hideCursor();
        }

        try self.terminal.flush();
        self.prev_width = size.width;
        self.prev_height = size.height;
        self.dirty = false;
    }

    fn handleKey(self: *App, key: Key) !void {
        if (self.theme_selector.visible) {
            switch (key) {
                .char => |c| switch (c) {
                    'j' => { try self.theme_selector.navigateDown(); self.dirty = true; return; },
                    'k' => { try self.theme_selector.navigateUp(); self.dirty = true; return; },
                    '/' => {
                        self.theme_selector.hide();
                        self.command_input.showWithPrompt("/");
                        self.dirty = true;
                        // Do not return, let it fall through to command_input handler
                    },
                    else => {}, // Fall through for other chars
                },
                .colon => {
                    self.theme_selector.hide();
                    self.command_input.showWithPrompt(":");
                    self.dirty = true;
                    // Do not return, let it fall through to command_input handler
                },
                .up => { try self.theme_selector.navigateUp(); self.dirty = true; return; },
                .down => { try self.theme_selector.navigateDown(); self.dirty = true; return; },
                .enter => {
                    // Save selected theme to config and update current marker
                    const selected_theme = self.theme_selector.getSelectedThemeName();
                    try self.saveThemeToConfig(selected_theme);
                    try self.theme_selector.setCurrentTheme(selected_theme);
                    // Don't hide - stay in themes view to try more themes
                    self.dirty = true;
                    return;
                },
                .escape => {
                    self.theme_selector.hide();
                    self.dirty = true;
                    return;
                },
                else => {}, // Fall through for other keys
            }
        }
        
        // The rest of the handleKey function will now be executed,
        // including the command_input.visible block if relevant.
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
                    // Process command based on prompt
                    const cmd_text = self.command_input.getCommand();
                    const prompt = self.command_input.prompt;
                    
                    if (std.mem.eql(u8, prompt, "/")) {
                        // Apply filter
                        try self.body.applyFilter(cmd_text);
                    } else if (std.mem.eql(u8, prompt, ":")) {
                        // Process command
                        if (std.mem.eql(u8, cmd_text, "q") or std.mem.eql(u8, cmd_text, "quit")) {
                            self.running = false;
                        } else if (std.mem.eql(u8, cmd_text, "themes") or std.mem.eql(u8, cmd_text, "skins")) {
                            self.theme_selector.show();
                        }
                        // TODO: Add more commands here
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

        switch (key) {
            .char => |c| switch (c) {
                'h' => { try self.body.navigateLeft(); self.dirty = true; },
                'j' => { try self.body.navigateDown(); self.dirty = true; },
                'k' => { try self.body.navigateUp(); self.dirty = true; },
                'l' => { try self.body.navigateRight(); self.dirty = true; },
                'g' => { try self.body.gotoTop(); self.dirty = true; },
                '/' => {
                    self.command_input.showWithPrompt("/");
                    self.dirty = true;
                },
                'x' => {
                    // Clear filter with 'x' key (like delete)
                    try self.body.applyFilter("");
                    self.dirty = true;
                },
                else => {},
            },
            .up => { try self.body.navigateUp(); self.dirty = true; },
            .down => { try self.body.navigateDown(); self.dirty = true; },
            .left => { try self.body.navigateLeft(); self.dirty = true; },
            .right => { try self.body.navigateRight(); self.dirty = true; },
            .home => { try self.body.gotoTop(); self.dirty = true; },
            .end => { try self.body.gotoBottom(); self.dirty = true; },
            .page_up => { try self.body.pageUp(); self.dirty = true; },
            .page_down => { try self.body.pageDown(); self.dirty = true; },
            .escape => {
                if (self.help.visible) {
                    // Esc closes help
                    self.help.hide();
                    self.body.setHelpMode(false);
                    self.footer.setHelpMode(false);
                    self.dirty = true;
                }
                // Esc never exits the app
            },
            .ctrl_c => {
                // Ctrl+C doesn't exit in k9s, use :q command instead
            },
            .ctrl_d => {
                // Ctrl+D reserved for delete action (k9s compat)
            },
            .shift_g => { try self.body.gotoBottom(); self.dirty = true; },
            .ctrl_f => { try self.body.pageDown(); self.dirty = true; },
            .ctrl_b => { try self.body.pageUp(); self.dirty = true; },
            .question_mark => {
                self.help.toggle();
                self.body.setHelpMode(self.help.visible);
                self.footer.setHelpMode(self.help.visible);
                self.dirty = true;
            },
            .colon => {
                self.command_input.showWithPrompt(":");
                self.dirty = true;
            },
            .backspace => {},
            .enter => {},
            .unsupported => {},
            .ctrl_e => {
                self.header.toggleCompact();
                self.dirty = true;
            },
        }
    }
    
    fn saveThemeToConfig(self: *App, theme_name: []const u8) !void {
        Logger.info("Changing theme to: {s}", .{theme_name});
        
        const xdg = @import("xdg.zig");
        const paths = try xdg.ensurePaths();
        
        Logger.info("Config file path: {s}", .{paths.config_file});
        
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
