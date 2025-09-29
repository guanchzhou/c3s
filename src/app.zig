const std = @import("std");
const vaxis = @import("vaxis");
const Terminal = @import("terminal.zig").Terminal;
const Header = @import("header.zig").Header;
const Body = @import("body.zig").Body;
const Footer = @import("footer.zig").Footer;
const Help = @import("help.zig").Help;
const CommandInput = @import("command_input.zig").CommandInput;
const Theme = @import("theme.zig");
const Cli = @import("cli.zig");

pub const App = struct {
    allocator: std.mem.Allocator,
    terminal: Terminal,
    header: Header,
    body: Body,
    footer: Footer,
    help: Help,
    command_input: CommandInput, // Add command input component
    config: Cli.Config,
    running: bool = true,
    prev_width: u16 = 0,
    prev_height: u16 = 0,
    dirty: bool = true,

    pub fn init(allocator: std.mem.Allocator, config: Cli.Config) !App {
        // Initialize terminal
        const terminal = try Terminal.init(allocator);

        // Initialize components
        const header = try Header.init(allocator);
        const body = try Body.init(allocator);
        const footer = try Footer.init(allocator);
        const help = try Help.init(allocator);
        const command_input = try CommandInput.init(allocator);

        return App{
            .allocator = allocator,
            .terminal = terminal,
            .header = header,
            .body = body,
            .footer = footer,
            .help = help,
            .command_input = command_input,
            .config = config,
        };
    }

    pub fn deinit(self: *App) void {
        self.header.deinit();
        self.body.deinit();
        self.footer.deinit();
        self.help.deinit();
        self.command_input.deinit();
        self.terminal.deinit();
    }

    pub fn run(self: *App) !void {
        // Try libvaxis first, fallback to custom terminal if it fails
        const vaxis_result = self.runWithVaxis();
        if (vaxis_result) |_| {
            return;
        } else |err| {
            // Fallback to custom terminal implementation
            std.log.info("libvaxis failed ({}), falling back to custom terminal", .{err});
            return self.runWithCustomTerminal();
        }
    }

        fn runWithVaxis(self: *App) !void {
            // vaxis TTY + enter alt screen for reliable input handling
            var tty_buf: [4096]u8 = undefined;
            var tty = try vaxis.Tty.init(&tty_buf);
            defer tty.deinit();
            var vx = try vaxis.init(self.allocator, .{});
            defer vx.deinit(self.allocator, tty.writer());
            _ = vx.enterAltScreen(tty.writer()) catch {};
            _ = vx.queryTerminal(tty.writer(), 500 * std.time.ns_per_ms) catch {};
            
            // Hide cursor completely
            try self.terminal.hideCursor();

        const Event = union(enum) { key_press: vaxis.Key, winsize: vaxis.Winsize, mouse: vaxis.Mouse };
        var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
        _ = loop.init() catch return;
        _ = loop.start() catch return;

        // Initial paint
        self.dirty = true;
        while (self.running) {
            // Wait for next input/resize event
            const ev = loop.nextEvent();
            switch (ev) {
                .winsize => |_| {
                    self.prev_width = 0;
                    self.prev_height = 0;
                    self.dirty = true;
                },
                .key_press => |key| {
                    try self.handleKey(key);
                },
                .mouse => |mouse| {
                    // Handle mouse scroll events without excessive redraws
                    if (mouse.button == .wheel_up) {
                        try self.body.navigateUp();
                        self.dirty = true;
                    } else if (mouse.button == .wheel_down) {
                        try self.body.navigateDown();
                        self.dirty = true;
                    }
                },
            }

            // Smart rendering - avoid unnecessary clears and redraws
            const size = try self.terminal.getSize();
            const size_changed = self.prev_width != size.width or self.prev_height != size.height;
            
            if (size_changed or self.dirty) {
                const header_height = 9; // Fixed header height - needs space for 7 content lines + borders
                const footer_height = 1; // Fixed footer height
                const body_height = size.height - header_height - footer_height;

                // Only clear screen on actual size change
                if (size_changed) {
                    try self.terminal.clear();
                    // Full redraw needed on resize
                    try self.header.render(&self.terminal, 0, 0, size.width, header_height);
                    try self.body.render(&self.terminal, 0, header_height, size.width, body_height);
                    try self.footer.render(&self.terminal, 0, header_height + body_height, size.width, footer_height);
                } else {
                    // Selective redraw - only redraw body on navigation changes
                    try self.body.render(&self.terminal, 0, header_height, size.width, body_height);
                }

                // Render help overlay if visible (only in body area)
                if (self.help.visible) {
                    try self.help.render(&self.terminal, 0, header_height, size.width, body_height);
                }

                // Single flush at the end
                try self.terminal.flush();
                
                self.prev_width = size.width;
                self.prev_height = size.height;
                self.dirty = false;
            }
        }

            // Stop loop before restoring terminal and tearing down vaxis
            loop.stop();
            // Ensure cursor is hidden before exit
            _ = self.terminal.hideCursor() catch {};
            // Restore terminal state
            _ = vx.exitAltScreen(tty.writer()) catch {};
    }

    fn runWithCustomTerminal(self: *App) !void {
        // Enter alternate screen
        try self.terminal.enterAlternateScreen();
        defer _ = self.terminal.exitAlternateScreen() catch {};

        // Hide cursor
        try self.terminal.hideCursor();
        defer _ = self.terminal.showCursor() catch {};

        // Initial paint
        self.dirty = true;
        while (self.running) {
            // Handle input
            try self.handleInput();

            // Smart rendering for custom terminal too
            const size = try self.terminal.getSize();
            const size_changed = self.prev_width != size.width or self.prev_height != size.height;
            
            if (size_changed or self.dirty) {
                const header_height = 9; // Fixed header height - needs space for 7 content lines + borders
                const footer_height = 1; // Fixed footer height
                const body_height = size.height - header_height - footer_height;

                // Only clear screen on actual size change
                if (size_changed) {
                    try self.terminal.clear();
                    // Full redraw needed on resize
                    try self.header.render(&self.terminal, 0, 0, size.width, header_height);
                    try self.body.render(&self.terminal, 0, header_height, size.width, body_height);
                    try self.footer.render(&self.terminal, 0, header_height + body_height, size.width, footer_height);
                } else {
                    // Selective redraw - only redraw body on navigation changes
                    try self.body.render(&self.terminal, 0, header_height, size.width, body_height);
                }
                
                // Render help overlay if visible (only in body area)
                if (self.help.visible) {
                    try self.help.render(&self.terminal, 0, header_height, size.width, body_height);
                }

                // Render command input if visible (at bottom of screen)
                if (self.command_input.visible) {
                    try self.command_input.render(&self.terminal, 0, size.height - 1, size.width, 1);
                }

                try self.terminal.flush();
                self.prev_width = size.width;
                self.prev_height = size.height;
                self.dirty = false;
            }

            // btop-style delay - much less aggressive rendering
            std.Thread.sleep(100 * std.time.ns_per_ms); // ~10 FPS, only when needed
        }
    }

        fn handleKey(self: *App, key: vaxis.Key) !void {
            const Key = vaxis.Key;
            
            // Navigation keys
            if (key.matches(Key.up, .{}) or key.matches('k', .{})) {
                try self.body.navigateUp();
                self.dirty = true;
            } else if (key.matches(Key.down, .{}) or key.matches('j', .{})) {
                try self.body.navigateDown();
                self.dirty = true;
            } else if (key.matches(Key.left, .{}) or key.matches('h', .{})) {
                try self.body.navigateLeft();
                self.dirty = true;
            } else if (key.matches(Key.right, .{}) or key.matches('l', .{})) {
                try self.body.navigateRight();
                self.dirty = true;
            }
            // Goto top/bottom
            else if (key.matches('g', .{})) {
                try self.body.gotoTop();
                self.dirty = true;
            } else if (key.matches('G', .{ .shift = true })) {
                try self.body.gotoBottom();
                self.dirty = true;
            }
            // Page up/down
            else if (key.matches('f', .{ .ctrl = true })) {
                try self.body.pageDown();
                self.dirty = true;
            } else if (key.matches('b', .{ .ctrl = true })) {
                try self.body.pageUp();
                self.dirty = true;
            }
        // Help
        else if (key.matches('?', .{}) or key.matches('?', .{ .shift = true })) {
            self.help.toggle();
            self.body.setHelpMode(self.help.visible);
            self.footer.setHelpMode(self.help.visible);
            self.dirty = true;
        }
        // Command mode
        else if (key.matches(':', .{ .shift = true })) {
            self.command_input.show();
            self.dirty = true;
        }
            // Quit
            else if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
                self.running = false;
            }
        // Escape - close help if visible, otherwise quit
        else if (key.matches(Key.escape, .{})) {
            if (self.help.visible) {
                self.help.hide();
                self.body.setHelpMode(false);
                self.footer.setHelpMode(false);
                self.dirty = true;
            } else {
                self.running = false;
            }
        }
            // Refresh
            else if (key.matches('r', .{ .ctrl = true })) {
                try self.body.refresh();
                self.dirty = true;
            }
            // Resource management shortcuts
            else if (key.matches('d', .{})) {
                try self.body.describe();
                self.dirty = true;
            } else if (key.matches('e', .{})) {
                try self.body.edit();
                self.dirty = true;
            } else if (key.matches('l', .{})) {
                try self.body.logs();
                self.dirty = true;
            } else if (key.matches('s', .{})) {
                try self.body.shell();
                self.dirty = true;
            } else if (key.matches('y', .{})) {
                try self.body.yaml();
                self.dirty = true;
            } else if (key.matches('a', .{})) {
                try self.body.attach();
                self.dirty = true;
            } else if (key.matches('c', .{})) {
                try self.body.copy();
                self.dirty = true;
            } else if (key.matches('n', .{})) {
                try self.body.copyNamespace();
                self.dirty = true;
            } else if (key.matches('i', .{})) {
                try self.body.setImage();
                self.dirty = true;
            } else if (key.matches('o', .{})) {
                try self.body.showNode();
                self.dirty = true;
            } else if (key.matches('f', .{ .shift = true })) {
                try self.body.portForward();
                self.dirty = true;
            } else if (key.matches('t', .{})) {
                try self.body.transfer();
                self.dirty = true;
            } else if (key.matches('z', .{})) {
                try self.body.sanitize();
                self.dirty = true;
            }
            // Sorting shortcuts
            else if (key.matches('a', .{ .shift = true })) {
                try self.body.sortByAge();
                self.dirty = true;
            } else if (key.matches('c', .{ .shift = true })) {
                try self.body.sortByCpu();
                self.dirty = true;
            } else if (key.matches('x', .{ .shift = true })) {
                try self.body.sortByCpuR();
                self.dirty = true;
            } else if (key.matches('x', .{ .ctrl = true })) {
                try self.body.sortByCpuL();
                self.dirty = true;
            } else if (key.matches('i', .{ .shift = true })) {
                try self.body.sortByIp();
                self.dirty = true;
            } else if (key.matches('m', .{ .shift = true })) {
                try self.body.sortByMem();
                self.dirty = true;
            } else if (key.matches('z', .{ .shift = true })) {
                try self.body.sortByMemR();
                self.dirty = true;
            } else if (key.matches('q', .{ .ctrl = true })) {
                try self.body.sortByMemL();
                self.dirty = true;
            } else if (key.matches('n', .{ .shift = true })) {
                try self.body.sortByName();
                self.dirty = true;
            } else if (key.matches('p', .{ .shift = true })) {
                try self.body.sortByNamespace();
                self.dirty = true;
            } else if (key.matches('o', .{ .shift = true })) {
                try self.body.sortByNode();
                self.dirty = true;
            } else if (key.matches('r', .{ .shift = true })) {
                try self.body.sortByReady();
                self.dirty = true;
            } else if (key.matches('t', .{ .shift = true })) {
                try self.body.sortByRestart();
                self.dirty = true;
            } else if (key.matches('s', .{ .shift = true })) {
                try self.body.sortByStatus();
                self.dirty = true;
            }
            // General shortcuts
            else if (key.matches(' ', .{})) {
                try self.body.mark();
                self.dirty = true;
            } else if (key.matches('\\', .{ .ctrl = true })) {
                try self.body.markClear();
                self.dirty = true;
            } else if (key.matches(' ', .{ .ctrl = true })) {
                try self.body.markRange();
                self.dirty = true;
            } else if (key.matches('w', .{ .ctrl = true })) {
                try self.body.toggleWide();
                self.dirty = true;
            } else if (key.matches('z', .{ .ctrl = true })) {
                try self.body.toggleFaults();
                self.dirty = true;
            } else if (key.matches('e', .{ .ctrl = true })) {
                try self.body.toggleHeader();
                self.dirty = true;
            } else if (key.matches('g', .{ .ctrl = true })) {
                try self.body.toggleCrumbs();
                self.dirty = true;
            }
        }

        fn handleInput(self: *App) !void {
            const key = self.terminal.readKey() catch return;
            if (key == null) return;

            switch (key.?) {
                .char => |c| {
                    switch (c) {
                        'q' => self.running = false,
                        'h' => { try self.body.navigateLeft(); self.dirty = true; },
                        'j' => { try self.body.navigateDown(); self.dirty = true; },
                        'k' => { try self.body.navigateUp(); self.dirty = true; },
                        'l' => { try self.body.navigateRight(); self.dirty = true; },
                        else => {},
                    }
                },
                .up => { try self.body.navigateUp(); self.dirty = true; },
                .down => { try self.body.navigateDown(); self.dirty = true; },
                .left => { try self.body.navigateLeft(); self.dirty = true; },
                .right => { try self.body.navigateRight(); self.dirty = true; },
                .escape => self.running = false,
                .ctrl_c => self.running = false,
            }
        }
};
