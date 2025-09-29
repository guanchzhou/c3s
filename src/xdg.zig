const std = @import("std");

const path_allocator = std.heap.page_allocator;
const AppName = "c3s";

pub const Paths = struct {
    config_dir: []const u8,
    config_file: []const u8,
    hotkeys_file: []const u8,
    aliases_file: []const u8,
    plugins_file: []const u8,
    views_file: []const u8,
    skins_dir: []const u8,
    data_dir: []const u8,
    contexts_dir: []const u8,
    state_dir: []const u8,
    dumps_dir: []const u8,
    benchmarks_dir: []const u8,
    log_dir: []const u8,
    log_file: []const u8,
};

var cached: ?Paths = null;

pub fn ensurePaths() !*const Paths {
    if (cached) |*p| return p;

    cached = try computePaths();
    return &cached.?;
}

pub fn getPaths() ?*const Paths {
    return cached;
}

fn computePaths() !Paths {
    const home_dir = try std.process.getEnvVarOwned(path_allocator, "HOME");
    if (home_dir.len == 0) return error.MissingHomeDirectory;

    const config_dir = try resolveConfigDir(home_dir);
    try ensureDirExists(config_dir);

    const config_file = try join(&[_][]const u8{ config_dir, "config.yaml" });
    const hotkeys_file = try join(&[_][]const u8{ config_dir, "hotkeys.yaml" });
    const aliases_file = try join(&[_][]const u8{ config_dir, "aliases.yaml" });
    const plugins_file = try join(&[_][]const u8{ config_dir, "plugins.yaml" });
    const views_file = try join(&[_][]const u8{ config_dir, "views.yaml" });

    const skins_dir = try join(&[_][]const u8{ config_dir, "skins" });
    try ensureDirExists(skins_dir);

    const data_dir = try resolveDataDir(home_dir);
    try ensureDirExists(data_dir);

    const contexts_dir = try join(&[_][]const u8{ data_dir, "clusters" });
    try ensureDirExists(contexts_dir);

    const state_dir = try resolveStateDir(home_dir);
    try ensureDirExists(state_dir);

    const dumps_dir = try join(&[_][]const u8{ state_dir, "screen-dumps" });
    try ensureDirExists(dumps_dir);

    const benchmarks_dir = try join(&[_][]const u8{ state_dir, "benchmarks" });
    try ensureDirExists(benchmarks_dir);

    const log_dir = state_dir;
    const log_file = try join(&[_][]const u8{ log_dir, "c3s.log" });

    return Paths{
        .config_dir = config_dir,
        .config_file = config_file,
        .hotkeys_file = hotkeys_file,
        .aliases_file = aliases_file,
        .plugins_file = plugins_file,
        .views_file = views_file,
        .skins_dir = skins_dir,
        .data_dir = data_dir,
        .contexts_dir = contexts_dir,
        .state_dir = state_dir,
        .dumps_dir = dumps_dir,
        .benchmarks_dir = benchmarks_dir,
        .log_dir = log_dir,
        .log_file = log_file,
    };
}

fn resolveConfigDir(home: []const u8) ![]const u8 {
    if (try getValidEnvPath("XDG_CONFIG_HOME")) |path| {
        return try join(&[_][]const u8{ path, AppName });
    }
    return try join(&[_][]const u8{ home, ".config", AppName });
}

fn resolveDataDir(home: []const u8) ![]const u8 {
    if (try getValidEnvPath("XDG_DATA_HOME")) |path| {
        return try join(&[_][]const u8{ path, AppName });
    }
    return try join(&[_][]const u8{ home, ".local", "share", AppName });
}

fn resolveStateDir(home: []const u8) ![]const u8 {
    if (try getValidEnvPath("XDG_STATE_HOME")) |path| {
        return try join(&[_][]const u8{ path, AppName });
    }
    return try join(&[_][]const u8{ home, ".local", "state", AppName });
}

fn getValidEnvPath(key: []const u8) !?[]const u8 {
    const value = std.process.getEnvVarOwned(path_allocator, key) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => null,
        else => return err,
    };
    if (value == null) return null;

    if (value.?.len == 0) {
        return null;
    }
    if (!std.fs.path.isAbsolute(value.?)) {
        return error.InvalidXdgDirectory;
    }
    if (containsTraversal(value.?)) {
        return error.InvalidXdgDirectory;
    }

    return value;
}

fn join(parts: []const []const u8) ![]const u8 {
    return std.fs.path.join(path_allocator, parts);
}

fn ensureDirExists(path: []const u8) !void {
    std.fs.cwd().makePath(path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

fn containsTraversal(path: []const u8) bool {
    var it = std.mem.splitScalar(u8, path, std.fs.path.sep);
    while (it.next()) |segment| {
        if (std.mem.eql(u8, segment, "..")) return true;
    }
    return false;
}
