const std = @import("std");
const mem = std.mem;
const build_options = @import("build_options");
const xdg = @import("xdg.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const global_allocator = gpa.allocator();

pub const LogLevel = enum {
    debug,
    info,
    warn,
    err,
};

pub const Logger = struct {
    allocator: std.mem.Allocator,
    log_file: ?std.fs.File = null,
    level: LogLevel = .info,
    log_dir: []const u8,
    log_file_path: []const u8,

    pub fn init(level: LogLevel) !Logger {
        const paths = try xdg.ensurePaths();
        const log_dir = paths.log_dir;
        const log_file_path = paths.log_file;

        std.fs.cwd().makePath(log_dir) catch |path_err| switch (path_err) {
            error.PathAlreadyExists => {},
            else => return path_err,
        };

        // Open in read-write mode with append semantics
        const log_file = std.fs.cwd().openFile(log_file_path, .{ 
            .mode = .read_write 
        }) catch |file_err| switch (file_err) {
            error.FileNotFound => blk: {
                // Create file if it doesn't exist
                const new_file = try std.fs.cwd().createFile(log_file_path, .{ .read = true });
                break :blk new_file;
            },
            else => return file_err,
        };
        
        // Seek to end for append mode
        try log_file.seekFromEnd(0);

        return Logger{
            .allocator = global_allocator,
            .log_file = log_file,
            .level = level,
            .log_dir = try global_allocator.dupe(u8, log_dir),
            .log_file_path = try global_allocator.dupe(u8, log_file_path),
        };
    }

    pub fn deinit(self: *Logger) void {
        if (self.log_file) |file| {
            file.close();
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
        if (self.log_file) |file| {
            const timestamp = std.time.timestamp();
            const timestamp_str = std.fmt.allocPrint(global_allocator, "{}", .{timestamp}) catch return;
            defer global_allocator.free(timestamp_str);

            const log_line = std.fmt.allocPrint(global_allocator,
                "[{s}] {s}: " ++ format ++ "\n",
                .{ timestamp_str, level } ++ args,
            ) catch return;
            defer global_allocator.free(log_line);

            _ = file.writeAll(log_line) catch {};
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
