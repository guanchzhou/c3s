const std = @import("std");
const runtime = @import("runtime.zig");
const env = @import("env.zig");

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
    return if (cached) |*p| p else null;
}

/// Test-only: drop the process-wide cached paths so the next ensurePaths()
/// re-resolves from the current environment. Tests that point
/// XDG_CONFIG_HOME at a temp tree (e.g. config tests) call this to stay
/// hermetic regardless of which test pinned the cache first.
pub fn resetCachedPathsForTests() void {
    cached = null;
}

fn computePaths() !Paths {
    const home_dir = try env.getOwned(path_allocator, "HOME");
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

fn getValidEnvPath(key: [:0]const u8) !?[]const u8 {
    const value = env.getOwned(path_allocator, key) catch |err| switch (err) {
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
    std.Io.Dir.cwd().createDirPath(runtime.io(), path) catch |err| switch (err) {
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

const testing = std.testing;

test "xdg Paths struct has all required fields" {
    const paths = Paths{
        .config_dir = "/test/config",
        .config_file = "/test/config/config.yaml",
        .hotkeys_file = "/test/config/hotkeys.yaml",
        .aliases_file = "/test/config/aliases.yaml",
        .plugins_file = "/test/config/plugins.yaml",
        .views_file = "/test/config/views.yaml",
        .skins_dir = "/test/config/skins",
        .data_dir = "/test/data",
        .contexts_dir = "/test/data/clusters",
        .state_dir = "/test/state",
        .dumps_dir = "/test/state/screen-dumps",
        .benchmarks_dir = "/test/state/benchmarks",
        .log_dir = "/test/state",
        .log_file = "/test/state/c3s.log",
    };

    try testing.expect(std.mem.eql(u8, paths.config_dir, "/test/config"));
    try testing.expect(std.mem.eql(u8, paths.config_file, "/test/config/config.yaml"));
    try testing.expect(std.mem.eql(u8, paths.log_file, "/test/state/c3s.log"));
}

test "ensurePaths creates and caches paths" {
    // This test will use actual HOME environment
    const paths = try ensurePaths();

    // Verify paths are not empty
    try testing.expect(paths.config_dir.len > 0);
    try testing.expect(paths.config_file.len > 0);
    try testing.expect(paths.log_file.len > 0);

    // Verify that subsequent calls return the same cached instance
    const paths2 = try ensurePaths();
    try testing.expect(paths == paths2); // Same pointer
}

test "getPaths returns cached paths after ensurePaths" {
    _ = try ensurePaths();

    const maybe_paths = getPaths();
    try testing.expect(maybe_paths != null);

    const paths = maybe_paths.?;
    try testing.expect(paths.config_dir.len > 0);
}

test "config paths end with correct filenames" {
    const paths = try ensurePaths();

    try testing.expect(std.mem.endsWith(u8, paths.config_file, "config.yaml"));
    try testing.expect(std.mem.endsWith(u8, paths.hotkeys_file, "hotkeys.yaml"));
    try testing.expect(std.mem.endsWith(u8, paths.aliases_file, "aliases.yaml"));
    try testing.expect(std.mem.endsWith(u8, paths.plugins_file, "plugins.yaml"));
    try testing.expect(std.mem.endsWith(u8, paths.views_file, "views.yaml"));
    try testing.expect(std.mem.endsWith(u8, paths.log_file, "c3s.log"));
}

test "directory paths contain c3s" {
    const paths = try ensurePaths();

    try testing.expect(std.mem.indexOf(u8, paths.config_dir, "c3s") != null);
    try testing.expect(std.mem.indexOf(u8, paths.data_dir, "c3s") != null);
    try testing.expect(std.mem.indexOf(u8, paths.state_dir, "c3s") != null);
}

test "skins directory is under config" {
    const paths = try ensurePaths();

    try testing.expect(std.mem.startsWith(u8, paths.skins_dir, paths.config_dir));
    try testing.expect(std.mem.endsWith(u8, paths.skins_dir, "skins"));
}

test "contexts directory is under data" {
    const paths = try ensurePaths();

    try testing.expect(std.mem.startsWith(u8, paths.contexts_dir, paths.data_dir));
    try testing.expect(std.mem.endsWith(u8, paths.contexts_dir, "clusters"));
}

test "dumps and benchmarks directories are under state" {
    const paths = try ensurePaths();

    try testing.expect(std.mem.startsWith(u8, paths.dumps_dir, paths.state_dir));
    try testing.expect(std.mem.endsWith(u8, paths.dumps_dir, "screen-dumps"));

    try testing.expect(std.mem.startsWith(u8, paths.benchmarks_dir, paths.state_dir));
    try testing.expect(std.mem.endsWith(u8, paths.benchmarks_dir, "benchmarks"));
}

test "log directory equals state directory" {
    const paths = try ensurePaths();

    try testing.expect(std.mem.eql(u8, paths.log_dir, paths.state_dir));
}

test "all paths are absolute" {
    const paths = try ensurePaths();

    try testing.expect(std.fs.path.isAbsolute(paths.config_dir));
    try testing.expect(std.fs.path.isAbsolute(paths.config_file));
    try testing.expect(std.fs.path.isAbsolute(paths.data_dir));
    try testing.expect(std.fs.path.isAbsolute(paths.state_dir));
    try testing.expect(std.fs.path.isAbsolute(paths.log_file));
}
