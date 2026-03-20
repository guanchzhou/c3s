const std = @import("std");
const posix = std.posix;
const Logger = @import("logger.zig");
const c = @cImport({
    @cInclude("termios.h");
});

pub const Terminal = struct {
    allocator: std.mem.Allocator,
    stdin: std.fs.File,
    stdout: std.fs.File,
    stderr: std.fs.File,
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
        const stdin = std.fs.File.stdin();
        const stdout = std.fs.File.stdout();
        const stderr = std.fs.File.stderr();

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
        if (!std.posix.isatty(self.stdin.handle)) {
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
        _ = self;
        // 0) ioctl path omitted to avoid platform differences
        // 1) Try environment variables (often accurate in interactive shells)
        if (std.process.getEnvVarOwned(std.heap.page_allocator, "COLUMNS")) |cols_str| {
            defer std.heap.page_allocator.free(cols_str);
            if (std.process.getEnvVarOwned(std.heap.page_allocator, "LINES")) |lines_str| {
                defer std.heap.page_allocator.free(lines_str);
                const cols = std.fmt.parseInt(u16, std.mem.trim(u8, cols_str, " \n\r\t"), 10) catch 0;
                const lines = std.fmt.parseInt(u16, std.mem.trim(u8, lines_str, " \n\r\t"), 10) catch 0;
                if (cols > 0 and lines > 0) return .{ .width = cols, .height = lines };
            } else |_| {}
        } else |_| {}

        // 2) Try `stty size` (rows cols)
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        const alloc = arena.allocator();
        var stty = std.process.Child.init(&[_][]const u8{ "stty", "size" }, alloc);
        stty.stdout_behavior = .Pipe;
        stty.stderr_behavior = .Close;
        if (stty.spawn() catch null) |_| {
            const out = stty.stdout.?.readToEndAlloc(alloc, 64) catch null;
            _ = stty.wait() catch {};
            if (out) |buf| {
                const trimmed = std.mem.trim(u8, buf, " \n\r\t");
                if (std.mem.indexOfScalar(u8, trimmed, ' ')) |sp| {
                    const rows_str = trimmed[0..sp];
                    const cols_str = trimmed[sp + 1 ..];
                    const rows = std.fmt.parseInt(u16, rows_str, 10) catch 0;
                    const cols = std.fmt.parseInt(u16, cols_str, 10) catch 0;
                    if (rows > 0 and cols > 0) return .{ .width = cols, .height = rows };
                }
            }
        }

        // 3) Fallback to tput
        var cols_proc = std.process.Child.init(&[_][]const u8{ "tput", "cols" }, alloc);
        cols_proc.stdout_behavior = .Pipe;
        cols_proc.stderr_behavior = .Close;
        if (cols_proc.spawn() catch null) |_| {
            const cols_out = cols_proc.stdout.?.readToEndAlloc(alloc, 64) catch null;
            _ = cols_proc.wait() catch {};
            var lines_proc = std.process.Child.init(&[_][]const u8{ "tput", "lines" }, alloc);
            lines_proc.stdout_behavior = .Pipe;
            lines_proc.stderr_behavior = .Close;
            if (lines_proc.spawn() catch null) |_| {
                const lines_out = lines_proc.stdout.?.readToEndAlloc(alloc, 64) catch null;
                _ = lines_proc.wait() catch {};
                const cols = if (cols_out) |cols_buffer|
                    std.fmt.parseInt(u16, std.mem.trim(u8, cols_buffer, " \n\r\t"), 10) catch 0
                else
                    0;
                const lines = if (lines_out) |lines_buffer|
                    std.fmt.parseInt(u16, std.mem.trim(u8, lines_buffer, " \n\r\t"), 10) catch 0
                else
                    0;
                if (cols > 0 and lines > 0) return .{ .width = cols, .height = lines };
            }
        }

        // 4) Hard fallback
        return .{ .width = 120, .height = 40 };
    }

    fn bufferWrite(self: *Terminal, data: []const u8) !void {
        try self.write_buffer.appendSlice(self.allocator, data);
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

    pub fn hideCursor(self: *Terminal) !void {
        try self.bufferWrite("\x1b[?25l");
    }

    pub fn showCursor(self: *Terminal) !void {
        try self.bufferWrite("\x1b[?25h");
    }

    pub fn enterAlternateScreen(self: *Terminal) !void {
        try self.stdout.writeAll("\x1b[?1049h");
        try self.stdout.writeAll("\x1b[?25l"); // Hide cursor immediately
    }

    pub fn exitAlternateScreen(self: *Terminal) !void {
        try self.stdout.writeAll("\x1b[?25h"); // Show cursor before exit
        try self.stdout.writeAll("\x1b[?1049l");
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
        try self.stdout.writeAll("\x1b[?2026h");
    }

    pub fn endSyncOutput(self: *Terminal) !void {
        // End synchronized output - terminal displays buffered content atomically
        try self.stdout.writeAll("\x1b[?2026l");
    }

    pub fn flush(self: *Terminal) !void {
        // Write entire buffer to stdout at once for flicker-free rendering
        if (self.write_buffer.items.len > 0) {
            try self.stdout.writeAll(self.write_buffer.items);
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
        var buf: [16]u8 = undefined;

        // Read first byte (VMIN=0 means this returns immediately)
        const n = posix.read(self.stdin.handle, buf[0..1]) catch return null;
        if (n == 0) return null;

        const first = buf[0];
        switch (first) {
            0x02 => return Key.ctrl_b,
            0x03 => return Key.ctrl_c,
            0x04 => return Key.ctrl_d,
            0x05 => return Key.ctrl_e,
            0x06 => return Key.ctrl_f,
            0x7f => return Key.backspace,
            '\r', '\n' => return Key.enter,
            0x1b => {
                // Escape sequence - read remaining bytes
                var bytes_read: usize = 1;

                // Try to read up to 10 more bytes for escape sequence
                var attempts: u8 = 0;
                while (bytes_read < buf.len and attempts < 10) : (attempts += 1) {
                    const n_read = posix.read(self.stdin.handle, buf[bytes_read .. bytes_read + 1]) catch break;
                    if (n_read == 0) break;
                    bytes_read += n_read;

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
    ctrl_c,
    ctrl_d,
    ctrl_e,
    shift_g,
    ctrl_f,
    ctrl_b,
    question_mark,
    colon,
    backspace,
    enter,
    unsupported,
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
