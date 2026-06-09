const std = @import("std");
const mem = std.mem;
const build_options = @import("build_options");
const xdg = @import("xdg.zig");
const runtime = @import("runtime.zig");
const clock = @import("clock.zig");
const sys = @import("sys.zig");
const posix = std.posix;

var gpa = std.heap.DebugAllocator(.{}){};
const global_allocator = gpa.allocator();

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
};

pub const Logger = struct {
    allocator: std.mem.Allocator,
    // Zig 0.16: std.fs.File writes go through a buffered io Writer. The logger
    // owns a raw fd opened O_APPEND and writes via libc (sys.zig), keeping the
    // per-log hot path io-free (only the one-time createDirPath uses std.Io).
    log_fd: ?posix.fd_t = null,
    level: LogLevel = .info,
    log_dir: []const u8,
    log_file_path: []const u8,

    pub fn init(level: LogLevel) !Logger {
        const paths = try xdg.ensurePaths();
        const log_dir = paths.log_dir;
        const log_file_path = paths.log_file;

        std.Io.Dir.cwd().createDirPath(runtime.io(), log_dir) catch |path_err| switch (path_err) {
            error.PathAlreadyExists => {},
            else => return path_err,
        };

        // Open (creating if needed) with append semantics; O_APPEND removes the
        // need to seek to end before each write. Needs a null-terminated path.
        const path_z = try global_allocator.dupeZ(u8, log_file_path);
        defer global_allocator.free(path_z);
        const log_fd = sys.openAppend(path_z) orelse return error.LogFileOpenFailed;

        return Logger{
            .allocator = global_allocator,
            .log_fd = log_fd,
            .level = level,
            .log_dir = try global_allocator.dupe(u8, log_dir),
            .log_file_path = try global_allocator.dupe(u8, log_file_path),
        };
    }

    pub fn deinit(self: *Logger) void {
        if (self.log_fd) |fd| {
            sys.close(fd);
        }
        self.allocator.free(self.log_dir);
        self.allocator.free(self.log_file_path);
    }

    pub fn debug(self: *Logger, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.debug)) {
            self.log("DEBUG", format, args);
        }
    }

    pub fn info(self: *Logger, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.info)) {
            self.log("INFO", format, args);
        }
    }

    pub fn warn(self: *Logger, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.warn)) {
            self.log("WARN", format, args);
        }
    }

    pub fn err(self: *Logger, comptime format: []const u8, args: anytype) void {
        if (@intFromEnum(self.level) <= @intFromEnum(LogLevel.err)) {
            self.log("ERROR", format, args);
        }
    }

    fn log(self: *Logger, level: []const u8, comptime format: []const u8, args: anytype) void {
        if (self.log_fd) |fd| {
            const timestamp = clock.timestamp();
            const timestamp_str = std.fmt.allocPrint(global_allocator, "{}", .{timestamp}) catch return;
            defer global_allocator.free(timestamp_str);

            const log_line = std.fmt.allocPrint(
                global_allocator,
                "[{s}] {s}: " ++ format ++ "\n",
                .{ timestamp_str, level } ++ args,
            ) catch return;
            defer global_allocator.free(log_line);

            // O_APPEND fd: each write appends atomically. Best-effort.
            sys.writeAll(fd, log_line) catch {};
        }
    }

    pub fn getLogFilePath(self: *Logger) []const u8 {
        return self.log_file_path;
    }
};

// Global logger instance
var global_logger: ?Logger = null;

pub fn initGlobalLogger(level: LogLevel) !void {
    global_logger = try Logger.init(level);
}

pub fn deinitGlobalLogger() void {
    if (global_logger) |*logger| {
        logger.deinit();
        global_logger = null;
    }
}

pub fn debug(comptime format: []const u8, args: anytype) void {
    if (global_logger) |*logger| {
        logger.debug(format, args);
    }
}

pub fn info(comptime format: []const u8, args: anytype) void {
    if (global_logger) |*logger| {
        logger.info(format, args);
    }
}

pub fn warn(comptime format: []const u8, args: anytype) void {
    if (global_logger) |*logger| {
        logger.warn(format, args);
    }
}

pub fn err(comptime format: []const u8, args: anytype) void {
    if (global_logger) |*logger| {
        logger.err(format, args);
    }
}

pub fn getLogFilePath() ?[]const u8 {
    if (global_logger) |*logger| {
        return logger.getLogFilePath();
    }
    return null;
}

const testing = std.testing;

// Zig 0.16 exposes neither std.process.setEnvVar nor std.c.setenv; declare the libc symbol.
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

// Sets XDG_STATE_HOME so the logger resolves its log file under `dir`.
// Note: xdg.ensurePaths() caches the resolved paths process-wide on first call,
// so the first logger init in this test binary fixes the state dir for the rest
// of the run. Each test therefore reads back the *actual* resolved log path via
// getLogFilePath() rather than reconstructing it from a per-test tmp dir.
// xdg.zig requires an absolute XDG_STATE_HOME, so we resolve cwd via libc getcwd
// (Zig 0.16 has no std getcwd) and join the tmp dir's relative sub_path.
fn setStateHome(dir: [:0]const u8) void {
    _ = setenv("XDG_STATE_HOME", dir.ptr, 1);
}

// Builds an absolute path to the testing tmp dir: <cwd>/.zig-cache/tmp/<sub_path>.
fn absTmpPath(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir) ![:0]u8 {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.GetCwdFailed;
    const cwd = std.mem.sliceTo(cwd_ptr, 0);
    return std.fs.path.joinZ(allocator, &.{ cwd, ".zig-cache", "tmp", &tmp.sub_path });
}

fn readLog(allocator: std.mem.Allocator) ![]u8 {
    const log_path = getLogFilePath() orelse return error.NoLogPath;
    return std.Io.Dir.cwd().readFileAlloc(runtime.io(), log_path, allocator, .limited(1024 * 1024));
}

test "logger writes to file" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path_z = try absTmpPath(allocator, &tmp_dir);
    defer allocator.free(tmp_path_z);

    setStateHome(tmp_path_z);

    try initGlobalLogger(.info);
    defer deinitGlobalLogger();

    info("Test log message: {s}", .{"hello"});

    const log_content = try readLog(allocator);
    defer allocator.free(log_content);

    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "INFO"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "Test log message: hello"));
}

test "logger respects log level" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path_z = try absTmpPath(allocator, &tmp_dir);
    defer allocator.free(tmp_path_z);

    setStateHome(tmp_path_z);

    try initGlobalLogger(.warn);
    defer deinitGlobalLogger();

    // Debug and Info should not be logged at WARN level.
    debug("level-test debug message", .{});
    info("level-test info message", .{});

    // Warn and Error should be logged.
    warn("level-test warn message", .{});
    err("level-test error message", .{});

    const log_content = try readLog(allocator);
    defer allocator.free(log_content);

    try testing.expect(!std.mem.containsAtLeast(u8, log_content, 1, "level-test debug message"));
    try testing.expect(!std.mem.containsAtLeast(u8, log_content, 1, "level-test info message"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "level-test warn message"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "level-test error message"));
}

test "logger appends to existing file" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path_z = try absTmpPath(allocator, &tmp_dir);
    defer allocator.free(tmp_path_z);

    setStateHome(tmp_path_z);

    // First logger session.
    try initGlobalLogger(.info);
    info("append-test first message", .{});
    deinitGlobalLogger();

    // Second logger session — opens the same file in append mode.
    try initGlobalLogger(.info);
    defer deinitGlobalLogger();
    info("append-test second message", .{});

    const log_content = try readLog(allocator);
    defer allocator.free(log_content);

    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "append-test first message"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "append-test second message"));
}
