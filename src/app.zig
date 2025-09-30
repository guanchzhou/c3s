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

// Global flag for terminal resize signal
var terminal_resized: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

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
    
    // Track which primary view is active (for view switching, not pushing)
    current_primary_view: enum { pods, themes } = .pods,

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
        var header = try Header.init(allocator, theme, config.debug);
        const footer = try Footer.init(allocator, theme);
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
        // === QUIT COMMANDS ===
        try self.command_registry.register("q", Command{ .name = "q", .execute = quitCommand });
        try self.command_registry.register("q!", Command{ .name = "q!", .execute = quitCommand });
        try self.command_registry.register("qa", Command{ .name = "qa", .execute = quitCommand });
        try self.command_registry.register("Q", Command{ .name = "Q", .execute = quitCommand });
        try self.command_registry.register("quit", Command{ .name = "quit", .execute = quitCommand });
        try self.command_registry.register("exit", Command{ .name = "exit", .execute = quitCommand });
        
        // === HELP COMMANDS ===
        try self.command_registry.register("?", Command{ .name = "?", .execute = helpCommand });
        try self.command_registry.register("h", Command{ .name = "h", .execute = helpCommand });
        try self.command_registry.register("help", Command{ .name = "help", .execute = helpCommand });
        
        // === CONTEXT COMMANDS ===
        try self.command_registry.register("ctx", Command{ .name = "ctx", .execute = notImplementedCommand });
        try self.command_registry.register("context", Command{ .name = "context", .execute = notImplementedCommand });
        try self.command_registry.register("contexts", Command{ .name = "contexts", .execute = notImplementedCommand });
        
        // === NAMESPACE COMMANDS ===
        try self.command_registry.register("ns", Command{ .name = "ns", .execute = notImplementedCommand });
        try self.command_registry.register("namespace", Command{ .name = "namespace", .execute = notImplementedCommand });
        try self.command_registry.register("namespaces", Command{ .name = "namespaces", .execute = notImplementedCommand });
        
        // === PODS COMMANDS ===
        try self.command_registry.register("pods", Command{ .name = "pods", .execute = podsCommand });
        try self.command_registry.register("po", Command{ .name = "po", .execute = podsCommand });
        
        // === DEPLOYMENTS ===
        try self.command_registry.register("deployments", Command{ .name = "deployments", .execute = notImplementedCommand });
        try self.command_registry.register("deploy", Command{ .name = "deploy", .execute = notImplementedCommand });
        try self.command_registry.register("dp", Command{ .name = "dp", .execute = notImplementedCommand });
        
        // === SERVICES ===
        try self.command_registry.register("services", Command{ .name = "services", .execute = notImplementedCommand });
        try self.command_registry.register("svc", Command{ .name = "svc", .execute = notImplementedCommand });
        
        // === STATEFULSETS ===
        try self.command_registry.register("statefulsets", Command{ .name = "statefulsets", .execute = notImplementedCommand });
        try self.command_registry.register("sts", Command{ .name = "sts", .execute = notImplementedCommand });
        
        // === DAEMONSETS ===
        try self.command_registry.register("daemonsets", Command{ .name = "daemonsets", .execute = notImplementedCommand });
        try self.command_registry.register("ds", Command{ .name = "ds", .execute = notImplementedCommand });
        
        // === REPLICASETS ===
        try self.command_registry.register("replicasets", Command{ .name = "replicasets", .execute = notImplementedCommand });
        try self.command_registry.register("rs", Command{ .name = "rs", .execute = notImplementedCommand });
        
        // === CONFIGMAPS ===
        try self.command_registry.register("configmaps", Command{ .name = "configmaps", .execute = notImplementedCommand });
        try self.command_registry.register("cm", Command{ .name = "cm", .execute = notImplementedCommand });
        
        // === SECRETS ===
        try self.command_registry.register("secrets", Command{ .name = "secrets", .execute = notImplementedCommand });
        try self.command_registry.register("sec", Command{ .name = "sec", .execute = notImplementedCommand });
        
        // === INGRESS ===
        try self.command_registry.register("ingresses", Command{ .name = "ingresses", .execute = notImplementedCommand });
        try self.command_registry.register("ing", Command{ .name = "ing", .execute = notImplementedCommand });
        
        // === JOBS ===
        try self.command_registry.register("jobs", Command{ .name = "jobs", .execute = notImplementedCommand });
        try self.command_registry.register("jo", Command{ .name = "jo", .execute = notImplementedCommand });
        
        // === CRONJOBS ===
        try self.command_registry.register("cronjobs", Command{ .name = "cronjobs", .execute = notImplementedCommand });
        try self.command_registry.register("cj", Command{ .name = "cj", .execute = notImplementedCommand });
        
        // === NODES ===
        try self.command_registry.register("nodes", Command{ .name = "nodes", .execute = notImplementedCommand });
        try self.command_registry.register("no", Command{ .name = "no", .execute = notImplementedCommand });
        
        // === PVC ===
        try self.command_registry.register("persistentvolumeclaims", Command{ .name = "persistentvolumeclaims", .execute = notImplementedCommand });
        try self.command_registry.register("pvc", Command{ .name = "pvc", .execute = notImplementedCommand });
        
        // === PV ===
        try self.command_registry.register("persistentvolumes", Command{ .name = "persistentvolumes", .execute = notImplementedCommand });
        try self.command_registry.register("pv", Command{ .name = "pv", .execute = notImplementedCommand });
        
        // === STORAGE CLASSES ===
        try self.command_registry.register("storageclasses", Command{ .name = "storageclasses", .execute = notImplementedCommand });
        try self.command_registry.register("sc", Command{ .name = "sc", .execute = notImplementedCommand });
        
        // === SERVICE ACCOUNTS ===
        try self.command_registry.register("serviceaccounts", Command{ .name = "serviceaccounts", .execute = notImplementedCommand });
        try self.command_registry.register("sa", Command{ .name = "sa", .execute = notImplementedCommand });
        
        // === RBAC ===
        try self.command_registry.register("clusterroles", Command{ .name = "clusterroles", .execute = notImplementedCommand });
        try self.command_registry.register("cr", Command{ .name = "cr", .execute = notImplementedCommand });
        try self.command_registry.register("clusterrolebindings", Command{ .name = "clusterrolebindings", .execute = notImplementedCommand });
        try self.command_registry.register("crb", Command{ .name = "crb", .execute = notImplementedCommand });
        try self.command_registry.register("roles", Command{ .name = "roles", .execute = notImplementedCommand });
        try self.command_registry.register("ro", Command{ .name = "ro", .execute = notImplementedCommand });
        try self.command_registry.register("rolebindings", Command{ .name = "rolebindings", .execute = notImplementedCommand });
        try self.command_registry.register("rb", Command{ .name = "rb", .execute = notImplementedCommand });
        
        // === NETWORK ===
        try self.command_registry.register("networkpolicies", Command{ .name = "networkpolicies", .execute = notImplementedCommand });
        try self.command_registry.register("np", Command{ .name = "np", .execute = notImplementedCommand });
        try self.command_registry.register("endpoints", Command{ .name = "endpoints", .execute = notImplementedCommand });
        try self.command_registry.register("ep", Command{ .name = "ep", .execute = notImplementedCommand });
        
        // === AUTOSCALING ===
        try self.command_registry.register("horizontalpodautoscalers", Command{ .name = "horizontalpodautoscalers", .execute = notImplementedCommand });
        try self.command_registry.register("hpa", Command{ .name = "hpa", .execute = notImplementedCommand });
        
        // === POLICY ===
        try self.command_registry.register("poddisruptionbudgets", Command{ .name = "poddisruptionbudgets", .execute = notImplementedCommand });
        try self.command_registry.register("pdb", Command{ .name = "pdb", .execute = notImplementedCommand });
        
        // === EVENTS ===
        try self.command_registry.register("events", Command{ .name = "events", .execute = notImplementedCommand });
        try self.command_registry.register("ev", Command{ .name = "ev", .execute = notImplementedCommand });
        
        // === CRD ===
        try self.command_registry.register("customresourcedefinitions", Command{ .name = "customresourcedefinitions", .execute = notImplementedCommand });
        try self.command_registry.register("crd", Command{ .name = "crd", .execute = notImplementedCommand });
        
        // === K9S SPECIFIC COMMANDS ===
        try self.command_registry.register("aliases", Command{ .name = "aliases", .execute = notImplementedCommand });
        try self.command_registry.register("a", Command{ .name = "a", .execute = notImplementedCommand });
        try self.command_registry.register("xray", Command{ .name = "xray", .execute = notImplementedCommand });
        try self.command_registry.register("xr", Command{ .name = "xr", .execute = notImplementedCommand });
        try self.command_registry.register("x", Command{ .name = "x", .execute = notImplementedCommand });
        try self.command_registry.register("portforwards", Command{ .name = "portforwards", .execute = notImplementedCommand });
        try self.command_registry.register("pf", Command{ .name = "pf", .execute = notImplementedCommand });
        try self.command_registry.register("benchmarks", Command{ .name = "benchmarks", .execute = notImplementedCommand });
        try self.command_registry.register("containers", Command{ .name = "containers", .execute = notImplementedCommand });
        try self.command_registry.register("co", Command{ .name = "co", .execute = notImplementedCommand });
        
        // === DIRECTORY/LS ===
        try self.command_registry.register("dir", Command{ .name = "dir", .execute = notImplementedCommand });
        try self.command_registry.register("dirs", Command{ .name = "dirs", .execute = notImplementedCommand });
        try self.command_registry.register("d", Command{ .name = "d", .execute = notImplementedCommand });
        try self.command_registry.register("ls", Command{ .name = "ls", .execute = notImplementedCommand });
        
        // === THEMES/SKINS ===
        try self.command_registry.register("themes", Command{ .name = "themes", .execute = themesCommand });
        try self.command_registry.register("skins", Command{ .name = "skins", .execute = themesCommand });
        
        // === INTERNAL COMMANDS ===
        try self.command_registry.register("select_theme", Command{ .name = "select_theme", .execute = selectThemeCommand });
    }

    pub fn run(self: *App) !void {
        try self.terminal.enterAlternateScreen();
        defer _ = self.terminal.exitAlternateScreen() catch {};

        try self.terminal.hideCursor();
        defer _ = self.terminal.showCursor() catch {};

        try self.terminal.enableRawMode();
        defer self.terminal.disableRawMode();

        // Setup SIGWINCH handler for terminal resize
        setupResizeHandler() catch |err| {
            Logger.warn("Failed to setup SIGWINCH handler: {}", .{err});
        };

        self.dirty = true;
        self.prev_width = 0;
        self.prev_height = 0;

        while (self.running) {
            try self.renderIfNeeded();

            // Check if terminal was resized
            if (terminal_resized.load(.acquire)) {
                terminal_resized.store(false, .release);
                self.dirty = true;
            }

            var pollfds = [_]posix.pollfd{
                posix.pollfd{ .fd = self.terminal.stdin.handle, .events = posix.POLL.IN, .revents = 0 },
            };

            // Poll with timeout to catch resize events via signal
            const poll_result = posix.poll(&pollfds, 100) catch |err| { // 100ms timeout
                return err;
            };

            if (poll_result == 0) {
                // Timeout - check if terminal size changed (fallback)
                continue;
            }

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

        // Update header and footer themes if we're previewing a theme
        const effective_theme = if (self.themes_view.preview_theme) |preview| preview else self.theme;
        self.header.setTheme(effective_theme);
        self.footer.setTheme(effective_theme);

        // Render header with hints from current view
        if (size.height >= self.header_height) {
            const current_view = self.view_manager.getCurrentView() orelse unreachable;
            const hints = current_view.getHints();
            try self.header.render(&self.terminal, 0, 0, size.width, self.header_height, hints);
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
                    // Toggle help view - if already open, close it; otherwise open it
                    const help_is_active = self.view_manager.isViewActive("help");
                    Logger.info("Shift+? pressed, help_is_active={}", .{help_is_active});
                    if (help_is_active) {
                        Logger.info("Closing help view", .{});
                        _ = self.view_manager.popView();
                    } else {
                        Logger.info("Opening help view", .{});
                        try self.view_manager.pushView(self.help_view.createView());
                    }
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
                // First, check if there's an active filter to clear
                var filter_cleared = false;
                if (self.view_manager.getCurrentView()) |current_view| {
                    if (std.mem.eql(u8, current_view.getName(), "pods")) {
                        if (self.pods_view.filter_text.len > 0) {
                            try self.pods_view.applyFilter("");
                            self.dirty = true;
                            filter_cleared = true;
                        }
                    } else if (std.mem.eql(u8, current_view.getName(), "themes")) {
                        if (self.themes_view.filter_text.len > 0) {
                            try self.themes_view.applyFilter("");
                            self.dirty = true;
                            filter_cleared = true;
                        }
                    }
                }
                
                // Only pop if:
                // 1. No filter was cleared AND
                // 2. We're in a pushed sub-view (depth > 1, like help view)
                // Primary views (pods, themes) are at depth 1, so they don't get popped
                if (!filter_cleared and self.view_manager.getDepth() > 1) {
                    _ = self.view_manager.popView();
                    self.dirty = true;
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
    
    // Don't push - replace the root view with themes view
    if (ctx.view_manager.getDepth() == 1) {
        // We're at root level, switch primary view
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.themes_view.createView());
        app.current_primary_view = .themes;
    }
    Logger.info("Themes command executed", .{});
}

fn podsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    
    // Switch back to pods view
    if (ctx.view_manager.getDepth() == 1) {
        // We're at root level, switch primary view
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.pods_view.createView());
        app.current_primary_view = .pods;
    }
    Logger.info("Pods command executed", .{});
}

fn helpCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    
    // Toggle help view - don't stack it!
    if (ctx.view_manager.isViewActive("help")) {
        Logger.info("Help command: closing help view", .{});
        _ = ctx.view_manager.popView();
    } else {
        Logger.info("Help command: opening help view", .{});
        try ctx.view_manager.pushView(app.help_view.createView());
    }
}

fn selectThemeCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    const selected_theme = app.themes_view.getSelectedThemeName();
    try app.saveThemeToConfig(selected_theme);
    try app.themes_view.setCurrentTheme(selected_theme);
    Logger.info("Theme selected: {s}", .{selected_theme});
}

fn notImplementedCommand(ctx: *Command.CommandContext) !void {
    _ = ctx;
    Logger.warn("Command not implemented yet", .{});
    // TODO: Show "Not implemented" message to user
}

// SIGWINCH signal handler for terminal resize
fn handleResize(_: c_int) callconv(.c) void {
    terminal_resized.store(true, .release);
}

fn setupResizeHandler() !void {
    const empty_set = std.mem.zeroes(posix.sigset_t);
    var sa = posix.Sigaction{
        .handler = .{ .handler = handleResize },
        .mask = empty_set,
        .flags = posix.SA.RESTART,
    };
    posix.sigaction(posix.SIG.WINCH, &sa, null);
}