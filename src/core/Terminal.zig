const std = @import("std");
const posix = std.posix;
const Logger = @import("logger.zig");
const runtime = @import("runtime.zig");
const env = @import("env.zig");
const sys = @import("sys.zig");
const c = @cImport({
    @cInclude("termios.h");
    @cInclude("sys/ioctl.h"); // TIOCGWINSZ + struct winsize for terminal size
    @cInclude("fcntl.h"); // open + O_RDONLY for /dev/tty size probe
    @cInclude("unistd.h"); // close
});

pub const Terminal = struct {
    allocator: std.mem.Allocator,
    stdin: std.Io.File,
    stdout: std.Io.File,
    stderr: std.Io.File,
    width: u16 = 80,
    height: u16 = 24,
    raw_enabled: bool = false,
    original_termios: ?c.termios = null,
    write_buffer: std.ArrayList(u8),

    /// Viewport offset — all rendering coordinates are translated by these values.
    /// Set by the app before rendering a view so views use local (0,0) coordinates.
    viewport_x: u16 = 0,
    viewport_y: u16 = 0,

    /// Set the viewport offset for view rendering. Views render at (0,0) relative
    /// coordinates; the terminal translates to screen coordinates.
    pub fn setViewport(self: *Terminal, x: u16, y: u16) void {
        self.viewport_x = x;
        self.viewport_y = y;
    }

    /// Reset viewport to no offset.
    pub fn resetViewport(self: *Terminal) void {
        self.viewport_x = 0;
        self.viewport_y = 0;
    }

    pub fn init(allocator: std.mem.Allocator) !Terminal {
        const stdin = std.Io.File.stdin();
        const stdout = std.Io.File.stdout();
        const stderr = std.Io.File.stderr();

        const write_buffer = try std.ArrayList(u8).initCapacity(allocator, 32768); // Pre-allocate 32KB for smooth rendering

        return Terminal{
            .allocator = allocator,
            .stdin = stdin,
            .stdout = stdout,
            .stderr = stderr,
            .write_buffer = write_buffer,
        };
    }

    pub fn deinit(self: *Terminal) void {
        if (self.raw_enabled) {
            self.disableRawMode();
        }
        self.write_buffer.deinit(self.allocator);
    }

    pub fn enableRawMode(self: *Terminal) !void {
        if (self.raw_enabled) return;

        // Check if stdin is a TTY first
        if (!sys.isatty(self.stdin.handle)) {
            Logger.warn("stdin is not a TTY, skipping raw mode", .{});
            return;
        }

        // Save original termios
        var termios: c.termios = undefined;
        const result = c.tcgetattr(self.stdin.handle, &termios);
        if (result != 0) {
            Logger.err("tcgetattr failed with result: {}, errno: {}", .{ result, std.posix.errno(-1) });
            return error.TermiosGetFailed;
        }
        self.original_termios = termios;

        // Configure raw mode
        c.cfmakeraw(&termios);
        termios.c_cc[c.VMIN] = 0; // Return immediately even if no data
        termios.c_cc[c.VTIME] = 0; // No timeout

        if (c.tcsetattr(self.stdin.handle, c.TCSANOW, &termios) != 0) {
            return error.TermiosSetFailed;
        }

        self.raw_enabled = true;
    }

    pub fn disableRawMode(self: *Terminal) void {
        if (!self.raw_enabled) return;

        // Restore original termios
        if (self.original_termios) |termios| {
            _ = c.tcsetattr(self.stdin.handle, c.TCSANOW, &termios);
        }

        self.raw_enabled = false;
    }

    pub fn getSize(self: *Terminal) !struct { width: u16, height: u16 } {
        // 0) ioctl(TIOCGWINSZ) on the tty fd — the canonical way to get terminal
        // size: no subprocess, reads the real terminal directly. (stty/tput below
        // can't be relied on: std.process.run forces child stdin=.ignore, so
        // `stty size` has no controlling TTY and returns nothing.)
        var ws: c.winsize = undefined;
        // Try whichever of stdout/stdin/stderr is a real terminal. Under a
        // debugger (lldb) or when stdout is piped, fd 1 isn't a tty.
        for ([_]c_int{ self.stdout.handle, self.stdin.handle, self.stderr.handle }) |fd| {
            if (c.ioctl(fd, c.TIOCGWINSZ, &ws) == 0 and ws.ws_col > 0 and ws.ws_row > 0) {
                return .{ .width = @intCast(ws.ws_col), .height = @intCast(ws.ws_row) };
            }
        }
        // Last resort: the controlling terminal, which survives stdio redirection.
        const tty_fd = c.open("/dev/tty", c.O_RDONLY);
        if (tty_fd >= 0) {
            defer _ = c.close(tty_fd);
            if (c.ioctl(tty_fd, c.TIOCGWINSZ, &ws) == 0 and ws.ws_col > 0 and ws.ws_row > 0) {
                return .{ .width = @intCast(ws.ws_col), .height = @intCast(ws.ws_row) };
            }
        }

        // 1) Try environment variables (often accurate in interactive shells)
        if (env.getOwned(std.heap.page_allocator, "COLUMNS")) |cols_str| {
            defer std.heap.page_allocator.free(cols_str);
            if (env.getOwned(std.heap.page_allocator, "LINES")) |lines_str| {
                defer std.heap.page_allocator.free(lines_str);
                const cols = std.fmt.parseInt(u16, std.mem.trim(u8, cols_str, " \n\r\t"), 10) catch 0;
                const lines = std.fmt.parseInt(u16, std.mem.trim(u8, lines_str, " \n\r\t"), 10) catch 0;
                if (cols > 0 and lines > 0) return .{ .width = cols, .height = lines };
            } else |_| {}
        } else |_| {}

        // 2) Try `stty size` (rows cols). Zig 0.16: std.process.Child.init was
        // removed; std.process.run spawns, waits, and collects output in one call.
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        if (std.process.run(alloc, runtime.io(), .{
            .argv = &[_][]const u8{ "stty", "size" },
            .stdout_limit = .limited(64),
        })) |res| {
            const trimmed = std.mem.trim(u8, res.stdout, " \n\r\t");
            if (std.mem.indexOfScalar(u8, trimmed, ' ')) |sp| {
                const rows = std.fmt.parseInt(u16, trimmed[0..sp], 10) catch 0;
                const cols = std.fmt.parseInt(u16, trimmed[sp + 1 ..], 10) catch 0;
                if (rows > 0 and cols > 0) return .{ .width = cols, .height = rows };
            }
        } else |_| {}

        // 3) Fallback to tput
        const cols = blk: {
            const res = std.process.run(alloc, runtime.io(), .{
                .argv = &[_][]const u8{ "tput", "cols" },
                .stdout_limit = .limited(64),
            }) catch break :blk 0;
            break :blk std.fmt.parseInt(u16, std.mem.trim(u8, res.stdout, " \n\r\t"), 10) catch 0;
        };
        const lines = blk: {
            const res = std.process.run(alloc, runtime.io(), .{
                .argv = &[_][]const u8{ "tput", "lines" },
                .stdout_limit = .limited(64),
            }) catch break :blk 0;
            break :blk std.fmt.parseInt(u16, std.mem.trim(u8, res.stdout, " \n\r\t"), 10) catch 0;
        };
        if (cols > 0 and lines > 0) return .{ .width = cols, .height = lines };

        // 4) Hard fallback
        return .{ .width = 120, .height = 40 };
    }

    fn bufferWrite(self: *Terminal, data: []const u8) !void {
        try self.write_buffer.appendSlice(self.allocator, data);
    }

    /// Write directly to stdout. Zig 0.16 routes std.Io.File writes through a
    /// buffered io Writer; for the render path we write to the fd via posix to
    /// stay io-free and allocation-free.
    fn writeAllStdout(self: *Terminal, data: []const u8) !void {
        try sys.writeAll(self.stdout.handle, data);
    }

    // Wrapper for components that need to write directly
    pub fn writeAll(self: *Terminal, data: []const u8) !void {
        try self.bufferWrite(data);
    }

    pub fn clear(self: *Terminal) !void {
        // Clear screen using ANSI escape codes
        try self.bufferWrite("\x1b[2J");
        try self.bufferWrite("\x1b[H");
    }

    /// Clear a rectangular region by writing spaces with reset colors
    pub fn clearRegion(self: *Terminal, x: u16, y: u16, w: u16, h: u16) !void {
        var spaces: [256]u8 = undefined;
        const fill_len = @min(w, 256);
        @memset(spaces[0..fill_len], ' ');
        var row: u16 = 0;
        while (row < h) : (row += 1) {
            try self.setCursor(x, y + row);
            try self.bufferWrite("\x1b[0m"); // reset colors
            try self.bufferWrite(spaces[0..fill_len]);
        }
    }

    pub fn hideCursor(self: *Terminal) !void {
        try self.bufferWrite("\x1b[?25l");
    }

    pub fn showCursor(self: *Terminal) !void {
        try self.bufferWrite("\x1b[?25h");
    }

    pub fn enterAlternateScreen(self: *Terminal) !void {
        try self.writeAllStdout("\x1b[?1049h");
        try self.writeAllStdout("\x1b[?25l"); // Hide cursor immediately
        // Disable autowrap (DECAWM): every cell is positioned explicitly, so a
        // write that reaches the last column must NOT wrap to col 0 of the next
        // row — that bleeds overflow into the box's left border. Clip instead.
        try self.writeAllStdout("\x1b[?7l");
        // Mouse: button tracking (1000) with SGR extended coordinates (1006).
        // 1000 reports press/release only (no motion spam), which is all we need.
        try self.writeAllStdout("\x1b[?1000h");
        try self.writeAllStdout("\x1b[?1006h");
    }

    pub fn exitAlternateScreen(self: *Terminal) !void {
        try self.writeAllStdout("\x1b[?1006l");
        try self.writeAllStdout("\x1b[?1000l"); // disable mouse before leaving
        try self.writeAllStdout("\x1b[?7h"); // restore autowrap
        try self.writeAllStdout("\x1b[?25h"); // Show cursor before exit
        try self.writeAllStdout("\x1b[?1049l");
    }

    pub fn setCursor(self: *Terminal, x: u16, y: u16) !void {
        var buf: [32]u8 = undefined;
        const s = try std.fmt.bufPrint(&buf, "\x1b[{};{}H", .{ y + 1, x + 1 });
        try self.bufferWrite(s);
    }

    pub fn writeString(self: *Terminal, x: u16, y: u16, text: []const u8) !void {
        try self.setCursor(x, y);
        try self.bufferWrite(text);
    }

    pub fn writeStringWithColor(self: *Terminal, x: u16, y: u16, text: []const u8, fg: Color, bg: Color) !void {
        try self.setCursor(x, y);
        try self.setColor(fg, bg);
        try self.bufferWrite(text);
        try self.resetColor();
    }

    pub fn setColor(self: *Terminal, fg: Color, bg: Color) !void {
        var buf: [32]u8 = undefined;
        const fg_code: u8 = @intFromEnum(fg);
        const raw_bg: u8 = @intFromEnum(bg);
        const bg_code: u8 = if (raw_bg == 39) 49 else (raw_bg - 30 + 40);
        const s = try std.fmt.bufPrint(&buf, "\x1b[{};{}m", .{ fg_code, bg_code });
        try self.bufferWrite(s);
    }

    pub fn resetColor(self: *Terminal) !void {
        try self.bufferWrite("\x1b[0m");
    }

    pub fn beginSyncOutput(self: *Terminal) !void {
        // DEC Synchronized Output Mode - terminal buffers until endSyncOutput
        try self.writeAllStdout("\x1b[?2026h");
    }

    pub fn endSyncOutput(self: *Terminal) !void {
        // End synchronized output - terminal displays buffered content atomically
        try self.writeAllStdout("\x1b[?2026l");
    }

    pub fn flush(self: *Terminal) !void {
        // Write entire buffer to stdout at once for flicker-free rendering
        if (self.write_buffer.items.len > 0) {
            try self.writeAllStdout(self.write_buffer.items);
            self.write_buffer.clearRetainingCapacity();
        }
    }

    pub fn fillRow(self: *Terminal, x: u16, y: u16, width: u16, fg_color: []const u8, bg_color: []const u8) !void {
        if (width == 0) return;

        try self.setCursor(x, y);

        // Write color codes once
        try self.bufferWrite(fg_color);
        try self.bufferWrite(bg_color);

        // Fill with spaces in chunks for efficiency
        var spaces_buf: [256]u8 = undefined;
        @memset(&spaces_buf, ' ');

        var remaining: usize = width;
        while (remaining > 0) {
            const chunk = @min(remaining, spaces_buf.len);
            try self.bufferWrite(spaces_buf[0..chunk]);
            remaining -= chunk;
        }

        // Reset colors
        try self.bufferWrite("\x1b[0m");
    }

    pub fn readKey(self: *Terminal) !?Key {
        var buf: [32]u8 = undefined;

        // Read first byte (VMIN=0 means this returns immediately)
        const n = posix.read(self.stdin.handle, buf[0..1]) catch return null;
        if (n == 0) return null;

        const first = buf[0];
        switch (first) {
            0x01 => return Key.ctrl_a,
            0x02 => return Key.ctrl_b,
            0x03 => return Key.ctrl_c,
            0x04 => return Key.ctrl_d,
            0x05 => return Key.ctrl_e,
            0x06 => return Key.ctrl_f,
            0x0b => return Key.ctrl_k,
            0x10 => return Key.ctrl_p,
            0x7f => return Key.backspace,
            '\r', '\n' => return Key.enter,
            0x1b => {
                // Escape sequence - read remaining bytes
                var bytes_read: usize = 1;

                // Read remaining bytes. SGR mouse reports (ESC [ < b ; x ; y M|m)
                // can run ~13 bytes, so allow more than arrow/tilde sequences need.
                var attempts: u8 = 0;
                while (bytes_read < buf.len and attempts < 24) : (attempts += 1) {
                    const n_read = posix.read(self.stdin.handle, buf[bytes_read .. bytes_read + 1]) catch break;
                    if (n_read == 0) break;
                    bytes_read += n_read;

                    // SGR mouse sequence: read until the M (press) / m (release) terminator.
                    if (bytes_read >= 3 and buf[1] == '[' and buf[2] == '<') {
                        const last = buf[bytes_read - 1];
                        if (last == 'M' or last == 'm') break;
                        continue;
                    }

                    // Check if we have a complete arrow key sequence
                    if (bytes_read >= 3 and buf[1] == '[') {
                        const code = buf[2];
                        // Simple sequences: ESC[A, ESC[B, ESC[C, ESC[D, ESC[H, ESC[F
                        if (code == 'A' or code == 'B' or code == 'C' or code == 'D' or code == 'H' or code == 'F') {
                            break;
                        }
                        // Tilde sequences need one more character: ESC[5~, ESC[6~, etc.
                        if (bytes_read >= 4 and buf[3] == '~') {
                            break;
                        }
                    }
                }

                return try decodeCsi(buf[0..bytes_read]);
            },
            ':' => return Key.colon,
            '?' => return Key.question_mark,
            'G' => return Key.shift_g,
            else => return Key{ .char = first },
        }
    }

    fn decodeCsi(seq: []const u8) !Key {
        if (seq.len < 2) return Key.escape;

        // ESC [ sequences
        if (seq[1] == '[') {
            if (seq.len == 2) return Key.escape;

            const code = seq[2];

            // SGR mouse report: ESC [ < b ; x ; y (M=press | m=release).
            // We surface only left-button presses as a Key.mouse with 0-based coords.
            if (code == '<') {
                const term = seq[seq.len - 1];
                if ((term == 'M' or term == 'm') and seq.len > 4) {
                    const body = seq[3 .. seq.len - 1]; // "b;x;y"
                    var it = std.mem.splitScalar(u8, body, ';');
                    const b = std.fmt.parseInt(u16, it.next() orelse return Key.unsupported, 10) catch return Key.unsupported;
                    const xs = it.next() orelse return Key.unsupported;
                    const ys = it.next() orelse return Key.unsupported;
                    const mx = std.fmt.parseInt(u16, xs, 10) catch return Key.unsupported;
                    const my = std.fmt.parseInt(u16, ys, 10) catch return Key.unsupported;
                    if (term == 'M') {
                        // Scroll wheel (buttons 64/65) → up/down, restoring the
                        // arrow emulation the terminal did before mouse mode.
                        if (b == 64) return Key.up;
                        if (b == 65) return Key.down;
                        // Left-button press → click (0-based coords).
                        if (b == 0 and mx >= 1 and my >= 1) {
                            return Key{ .mouse = .{ .x = mx - 1, .y = my - 1 } };
                        }
                    }
                }
                return Key.unsupported;
            }

            // Simple single-character codes
            switch (code) {
                'A' => return Key.up,
                'B' => return Key.down,
                'C' => return Key.right,
                'D' => return Key.left,
                'H' => return Key.home,
                'F' => return Key.end,
                else => {},
            }

            // Tilde sequences: ESC[X~
            if (seq.len >= 4 and seq[seq.len - 1] == '~') {
                const num_code = seq[2];
                return switch (num_code) {
                    '1', '7' => Key.home, // ESC[1~ or ESC[7~ = Home
                    '4', '8' => Key.end, // ESC[4~ or ESC[8~ = End
                    '5' => Key.page_up, // ESC[5~ = Page Up
                    '6' => Key.page_down, // ESC[6~ = Page Down
                    else => Key.unsupported,
                };
            }

            // Modified keys: ESC[1;XY where X is modifier, Y is key
            // Examples: ESC[1;5A = Ctrl+Up, ESC[1;2A = Shift+Up
            if (seq.len >= 6 and seq[2] == '1' and seq[3] == ';') {
                // Normalize modified arrow keys to plain arrow keys
                const key_code = seq[5];
                return switch (key_code) {
                    'A' => Key.up,
                    'B' => Key.down,
                    'C' => Key.right,
                    'D' => Key.left,
                    'H' => Key.home,
                    'F' => Key.end,
                    else => Key.unsupported,
                };
            }

            return Key.unsupported;
        }

        // ESC O sequences (alternate encoding)
        if (seq[1] == 'O') {
            if (seq.len < 3) return Key.escape;
            const code = seq[2];
            return switch (code) {
                'H' => Key.home,
                'F' => Key.end,
                else => Key.unsupported,
            };
        }

        // Just ESC with no valid sequence
        return Key.escape;
    }
};

pub const Key = union(enum) {
    char: u8,
    up,
    down,
    left,
    right,
    home,
    end,
    page_up,
    page_down,
    escape,
    ctrl_a,
    ctrl_c,
    ctrl_d,
    ctrl_e,
    shift_g,
    ctrl_f,
    ctrl_b,
    ctrl_k,
    ctrl_p,
    question_mark,
    colon,
    backspace,
    enter,
    /// Left-button press at 0-based screen coordinates (SGR mouse mode).
    mouse: Mouse,
    unsupported,

    pub const Mouse = struct { x: u16, y: u16 };
};

pub const Color = enum(u8) {
    default = 39,
    black = 30,
    red = 31,
    green = 32,
    yellow = 33,
    blue = 34,
    magenta = 35,
    cyan = 36,
    white = 37,
};

const testing = std.testing;

test "terminal initialization and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test that terminal was initialized successfully
    // Note: We can't directly compare allocators, so we just check that terminal exists
    // The terminal should have been created without errors
}

test "terminal size query" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    const size = try terminal.getSize();
    try testing.expect(size.width > 0);
    try testing.expect(size.height > 0);
}

test "terminal screen control" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test basic screen control
    try terminal.clear();
    try terminal.hideCursor();
    try terminal.showCursor();
    try terminal.setCursor(0, 0);
}

/// Tests that flush() must NOT write to the real stdout: under `zig build
/// test` fd 1 is the build runner's IPC pipe, and raw ANSI bytes on it desync
/// the zig server protocol — runner and test binary then deadlock waiting for
/// each other. Point the terminal's stdout at /dev/null instead.
fn redirectStdoutToDevNull(terminal: *Terminal) !std.Io.File {
    const sink = try std.Io.Dir.cwd().openFile(testing.io, "/dev/null", .{ .mode = .write_only });
    terminal.stdout = sink;
    return sink;
}

test "terminal text writing" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();
    const sink = try redirectStdoutToDevNull(&terminal);
    defer sink.close(testing.io);

    // Test basic text output
    try terminal.writeString(0, 0, "Hello, World!");
    try terminal.flush();
}

test "terminal color support" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test color setting
    try terminal.setColor(.red, .black);
    try terminal.resetColor();

    // Test all color combinations
    const colors = [_]Color{ .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white };

    for (colors, 0..) |fg, i| {
        const bg = colors[i];
        try terminal.setColor(fg, bg);
        try terminal.resetColor();
    }
}

test "terminal colored text writing" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();
    const sink = try redirectStdoutToDevNull(&terminal);
    defer sink.close(testing.io);

    // Test colored text output
    try terminal.writeStringWithColor(0, 0, "Red text", .red, .black);
    try terminal.writeStringWithColor(0, 1, "Green text", .green, .black);
    try terminal.writeStringWithColor(0, 2, "Blue text", .blue, .black);
    try terminal.flush();
}

test "terminal raw mode" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // These tests can't run in automated environment as they require a terminal
    // Just verify they exist and can be called with proper error handling
    _ = terminal.enableRawMode() catch {};
    terminal.disableRawMode();
}

test "terminal buffer operations" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();
    const sink = try redirectStdoutToDevNull(&terminal);
    defer sink.close(testing.io);

    // Test buffer operations
    try terminal.writeString(0, 0, "Test");
    try terminal.flush();
}

// Mock terminal for testing key parsing without actual stdin
const MockTerminal = struct {
    buffer: []const u8,
    pos: usize = 0,

    pub fn init(buffer: []const u8) MockTerminal {
        return .{ .buffer = buffer };
    }

    pub fn readByte(self: *MockTerminal) ?u8 {
        if (self.pos >= self.buffer.len) return null;
        const b = self.buffer[self.pos];
        self.pos += 1;
        return b;
    }
};

// These tests are placeholders documenting the intended key-decoding behavior.
// Terminal.readKey reads directly from a raw-mode fd and has no injection seam
// yet, so the mock is constructed but not yet exercised. Keeping the mock alive
// via a discard so the file compiles under Zig 0.16 (unused locals are errors).
// Referenced types are kept for when injection lands.
comptime {
    _ = Terminal;
    _ = Key;
}

fn placeholder(seq: []const u8) void {
    var mock = MockTerminal.init(seq);
    _ = &mock;
    // Expected behavior is documented per call site below.
    // const key = try terminal.readKey();
    // try testing.expectEqual(expected, key);
}

test "arrow up key decoded" {
    placeholder("\x1b[A"); // Expected: Key.up
}

test "arrow down key decoded" {
    placeholder("\x1b[B"); // Expected: Key.down
}

test "arrow right key decoded" {
    placeholder("\x1b[C"); // Expected: Key.right
}

test "arrow left key decoded" {
    placeholder("\x1b[D"); // Expected: Key.left
}

test "single escape key" {
    placeholder("\x1b"); // Expected: Key.escape (no hang waiting for more bytes)
}

test "home key with ESC[H" {
    placeholder("\x1b[H"); // Expected: Key.home
}

test "home key with ESC[1~" {
    placeholder("\x1b[1~"); // Expected: Key.home
}

test "end key with ESC[F" {
    placeholder("\x1b[F"); // Expected: Key.end
}

test "end key with ESC[4~" {
    placeholder("\x1b[4~"); // Expected: Key.end
}

test "page up key" {
    placeholder("\x1b[5~"); // Expected: Key.page_up
}

test "page down key" {
    placeholder("\x1b[6~"); // Expected: Key.page_down
}

test "ctrl+arrow up normalized" {
    placeholder("\x1b[1;5A"); // Expected: Key.up (modifier ignored)
}

test "shift+arrow up normalized" {
    placeholder("\x1b[1;2A"); // Expected: Key.up (modifier ignored)
}

test "ctrl+c" {
    placeholder("\x03"); // Expected: Key.ctrl_c
}

test "ctrl+d" {
    placeholder("\x04"); // Expected: Key.ctrl_d
}

test "ctrl+e" {
    placeholder("\x05"); // Expected: Key.ctrl_e
}

test "ctrl+f" {
    placeholder("\x06"); // Expected: Key.ctrl_f
}

test "ctrl+b" {
    placeholder("\x02"); // Expected: Key.ctrl_b
}

test "unsupported escape sequence" {
    placeholder("\x1b[99Z"); // Expected: Key.unsupported
}

test "regular character" {
    placeholder("a"); // Expected: Key{ .char = 'a' }
}

test "question mark" {
    placeholder("?"); // Expected: Key.question_mark
}

test "colon" {
    placeholder(":"); // Expected: Key.colon
}

test "shift+g" {
    placeholder("G"); // Expected: Key.shift_g
}
