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
