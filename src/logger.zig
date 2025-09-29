const std = @import("std");
const build_options = @import("build_options");

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

    pub fn init(allocator: std.mem.Allocator, level: LogLevel) !Logger {
        // Create log directory structure like k9s
        const home_dir = std.process.getEnvVarOwned(allocator, "HOME") catch return error.NoHomeDir;
        defer allocator.free(home_dir);
        const log_dir = try std.fmt.allocPrint(allocator, "{s}/Library/Application Support/c3s", .{home_dir});
        const log_file_path = try std.fmt.allocPrint(allocator, "{s}/c3s.log", .{log_dir});

        // Ensure log directory exists
        std.fs.cwd().makePath(log_dir) catch |path_err| switch (path_err) {
            error.PathAlreadyExists => {},
            else => return path_err,
        };

        // Open log file for writing (create if doesn't exist, append if exists)
        const log_file = std.fs.cwd().openFile(log_file_path, .{ .mode = .write_only }) catch |file_err| switch (file_err) {
            error.FileNotFound => try std.fs.cwd().createFile(log_file_path, .{}),
            else => return file_err,
        };

        return Logger{
            .allocator = allocator,
            .log_file = log_file,
            .level = level,
            .log_dir = log_dir,
            .log_file_path = log_file_path,
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
            const timestamp_str = std.fmt.allocPrint(self.allocator, "{}", .{timestamp}) catch return;
            defer self.allocator.free(timestamp_str);

            const log_line = std.fmt.allocPrint(self.allocator, "[{s}] {s}: {s}\n", .{ timestamp_str, level, format }) catch return;
            defer self.allocator.free(log_line);

            _ = file.writeAll(log_line) catch {};
            _ = file.writeAll(std.fmt.allocPrint(self.allocator, "{}\n", .{args}) catch return) catch {};
        }
    }

    pub fn getLogFilePath(self: *Logger) []const u8 {
        return self.log_file_path;
    }
};

// Global logger instance
var global_logger: ?Logger = null;

pub fn initGlobalLogger(allocator: std.mem.Allocator, level: LogLevel) !void {
    global_logger = try Logger.init(allocator, level);
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
