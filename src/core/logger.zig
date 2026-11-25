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
        return initAt(level, null);
    }

    /// `path` overrides the XDG log file (--logFile).
    pub fn initAt(level: LogLevel, path: ?[]const u8) !Logger {
        const log_file_path = path orelse (try xdg.ensurePaths()).log_file;
        const log_dir = std.fs.path.dirname(log_file_path) orelse ".";

        std.Io.Dir.cwd().createDirPath(runtime.io(), log_dir) catch |path_err| switch (path_err) {
            error.PathAlreadyExists => {},
            else => return path_err,
        };

        // Open (creating if needed) with append semantics; O_APPEND removes the
        // need to seek to end before each write. Needs a null-terminated path.
        const path_z = try global_allocator.dupeSentinel(u8, log_file_path, 0);
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

    pub fn debug(self: *const Logger, comptime format: []const u8, args: anytype) void {
        if (@backingInt(self.level) <= @backingInt(LogLevel.debug)) {
            self.log("DEBUG", format, args);
        }
    }

    pub fn info(self: *const Logger, comptime format: []const u8, args: anytype) void {
        if (@backingInt(self.level) <= @backingInt(LogLevel.info)) {
            self.log("INFO", format, args);
        }
    }

    pub fn warn(self: *const Logger, comptime format: []const u8, args: anytype) void {
        if (@backingInt(self.level) <= @backingInt(LogLevel.warn)) {
            self.log("WARN", format, args);
        }
    }

    pub fn err(self: *const Logger, comptime format: []const u8, args: anytype) void {
        if (@backingInt(self.level) <= @backingInt(LogLevel.err)) {
            self.log("ERROR", format, args);
        }
    }

    const FormattedLine = struct {
        line: []const u8,
        owned: ?[]u8,
    };

    fn formatLogLine(
        stack_buf: *[1024]u8,
        allocator: std.mem.Allocator,
        timestamp: i64,
        level: []const u8,
        comptime format: []const u8,
        args: anytype,
    ) !FormattedLine {
        if (std.fmt.bufPrint(
            stack_buf,
            "[{d}] {s}: " ++ format ++ "\n",
            .{ timestamp, level } ++ args,
        )) |line| {
            return .{ .line = line, .owned = null };
        } else |fmt_err| switch (fmt_err) {
            error.NoSpaceLeft => {
                const owned = try std.fmt.allocPrint(
                    allocator,
                    "[{d}] {s}: " ++ format ++ "\n",
                    .{ timestamp, level } ++ args,
                );
                return .{ .line = owned, .owned = owned };
            },
        }
    }

    fn log(self: *const Logger, level: []const u8, comptime format: []const u8, args: anytype) void {
        if (self.log_fd) |fd| {
            const timestamp = clock.timestamp();
            var stack_buf: [1024]u8 = undefined;
            const formatted = formatLogLine(&stack_buf, global_allocator, timestamp, level, format, args) catch return;
            defer if (formatted.owned) |owned| global_allocator.free(owned);

            // O_APPEND fd: each write appends atomically. Best-effort.
            sys.writeAll(fd, formatted.line) catch {};
        }
    }

    pub fn getLogFilePath(self: *const Logger) []const u8 {
        return self.log_file_path;
    }
};

// Global logger instance synchronized via an atomic pointer.
var global_logger: std.atomic.Value(?*Logger) = .init(null);

pub fn initGlobalLogger(level: LogLevel) !void {
    try initGlobalLoggerAt(level, null);
}

pub fn initGlobalLoggerAt(level: LogLevel, path: ?[]const u8) !void {
    const logger = try global_allocator.create(Logger);
    errdefer global_allocator.destroy(logger);
    logger.* = try Logger.initAt(level, path);
    if (global_logger.swap(logger, .acq_rel)) |prev| {
        prev.deinit();
        global_allocator.destroy(prev);
    }
}

pub fn deinitGlobalLogger() void {
    if (global_logger.swap(null, .acq_rel)) |logger| {
        logger.deinit();
        global_allocator.destroy(logger);
    }
}

pub fn debug(comptime format: []const u8, args: anytype) void {
    if (global_logger.load(.acquire)) |logger| {
        logger.debug(format, args);
    }
}

pub fn info(comptime format: []const u8, args: anytype) void {
    if (global_logger.load(.acquire)) |logger| {
        logger.info(format, args);
    }
}

pub fn warn(comptime format: []const u8, args: anytype) void {
    if (global_logger.load(.acquire)) |logger| {
        logger.warn(format, args);
    }
}

pub fn err(comptime format: []const u8, args: anytype) void {
    if (global_logger.load(.acquire)) |logger| {
        logger.err(format, args);
    }
}

pub fn getLogFilePath() ?[]const u8 {
    if (global_logger.load(.acquire)) |logger| {
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
    xdg.resetCachedPathsForTests();
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

test "--logFile path is honored and the log is owner-only" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path_z = try absTmpPath(allocator, &tmp_dir);
    defer allocator.free(tmp_path_z);
    const log_path = try std.fs.path.joinZ(allocator, &.{ tmp_path_z, "nested", "custom.log" });
    defer allocator.free(log_path);

    try initGlobalLoggerAt(.info, log_path);
    defer deinitGlobalLogger();
    info("custom-path message", .{});

    try testing.expectEqualStrings(log_path, getLogFilePath().?);
    const log_content = try readLog(allocator);
    defer allocator.free(log_content);
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "custom-path message"));

    const stat = try std.Io.Dir.cwd().statFile(testing.io, log_path, .{});
    try testing.expectEqual(@as(std.posix.mode_t, 0o600), stat.permissions.toMode() & 0o777);
}

test "logger formats short lines on the stack and falls back to heap for long lines" {
    var stack_buf: [1024]u8 = undefined;
    const short = try Logger.formatLogLine(&stack_buf, testing.failing_allocator, 12345, "INFO", "hello {s}", .{"world"});
    try testing.expect(short.owned == null);
    try testing.expectEqualStrings("[12345] INFO: hello world\n", short.line);

    const long_msg: [1200]u8 = @splat('x');
    const long = try Logger.formatLogLine(&stack_buf, testing.allocator, 12345, "WARN", "{s}", .{&long_msg});
    defer if (long.owned) |owned| testing.allocator.free(owned);
    try testing.expect(long.owned != null);
    try testing.expect(std.mem.startsWith(u8, long.line, "[12345] WARN: "));
    try testing.expect(std.mem.endsWith(u8, long.line, "\n"));
    try testing.expect(long.line.len > stack_buf.len);
}

test "global logger supports concurrent writes and atomic deinit" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const tmp_path_z = try absTmpPath(allocator, &tmp_dir);
    defer allocator.free(tmp_path_z);
    const log_path = try std.fs.path.joinZ(allocator, &.{ tmp_path_z, "concurrent.log" });
    defer allocator.free(log_path);

    try initGlobalLoggerAt(.info, log_path);
    errdefer deinitGlobalLogger();

    const Worker = struct {
        fn run(id: usize) void {
            for (0..8) |i| {
                info("worker-{d}-msg-{d}", .{ id, i });
            }
        }
    };

    var threads: [4]std.Thread = undefined;
    for (&threads, 0..) |*t, idx| {
        t.* = try std.Thread.spawn(.{}, Worker.run, .{idx});
    }
    for (&threads) |*t| t.join();

    const log_content = try readLog(allocator);
    defer allocator.free(log_content);
    for (0..4) |idx| {
        var needle_buf: [32]u8 = undefined;
        const needle = try std.fmt.bufPrint(&needle_buf, "worker-{d}-msg-7", .{idx});
        try testing.expect(std.mem.indexOf(u8, log_content, needle) != null);
    }

    deinitGlobalLogger();
    try testing.expect(getLogFilePath() == null);
}
