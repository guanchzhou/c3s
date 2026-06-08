const std = @import("std");
const testing = std.testing;
const xdg = @import("src").xdg;

test "xdg Paths struct has all required fields" {
    const paths = xdg.Paths{
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
    const paths = try xdg.ensurePaths();
    
    // Verify paths are not empty
    try testing.expect(paths.config_dir.len > 0);
    try testing.expect(paths.config_file.len > 0);
    try testing.expect(paths.log_file.len > 0);
    
    // Verify that subsequent calls return the same cached instance
    const paths2 = try xdg.ensurePaths();
    try testing.expect(paths == paths2); // Same pointer
}

test "getPaths returns cached paths after ensurePaths" {
    _ = try xdg.ensurePaths();
    
    const maybe_paths = xdg.getPaths();
    try testing.expect(maybe_paths != null);
    
    const paths = maybe_paths.?;
    try testing.expect(paths.config_dir.len > 0);
}

test "config paths end with correct filenames" {
    const paths = try xdg.ensurePaths();
    
    try testing.expect(std.mem.endsWith(u8, paths.config_file, "config.yaml"));
    try testing.expect(std.mem.endsWith(u8, paths.hotkeys_file, "hotkeys.yaml"));
    try testing.expect(std.mem.endsWith(u8, paths.aliases_file, "aliases.yaml"));
    try testing.expect(std.mem.endsWith(u8, paths.plugins_file, "plugins.yaml"));
    try testing.expect(std.mem.endsWith(u8, paths.views_file, "views.yaml"));
    try testing.expect(std.mem.endsWith(u8, paths.log_file, "c3s.log"));
}

test "directory paths contain c3s" {
    const paths = try xdg.ensurePaths();
    
    try testing.expect(std.mem.indexOf(u8, paths.config_dir, "c3s") != null);
    try testing.expect(std.mem.indexOf(u8, paths.data_dir, "c3s") != null);
    try testing.expect(std.mem.indexOf(u8, paths.state_dir, "c3s") != null);
}

test "skins directory is under config" {
    const paths = try xdg.ensurePaths();
    
    try testing.expect(std.mem.startsWith(u8, paths.skins_dir, paths.config_dir));
    try testing.expect(std.mem.endsWith(u8, paths.skins_dir, "skins"));
}

test "contexts directory is under data" {
    const paths = try xdg.ensurePaths();
    
    try testing.expect(std.mem.startsWith(u8, paths.contexts_dir, paths.data_dir));
    try testing.expect(std.mem.endsWith(u8, paths.contexts_dir, "clusters"));
}

test "dumps and benchmarks directories are under state" {
    const paths = try xdg.ensurePaths();
    
    try testing.expect(std.mem.startsWith(u8, paths.dumps_dir, paths.state_dir));
    try testing.expect(std.mem.endsWith(u8, paths.dumps_dir, "screen-dumps"));
    
    try testing.expect(std.mem.startsWith(u8, paths.benchmarks_dir, paths.state_dir));
    try testing.expect(std.mem.endsWith(u8, paths.benchmarks_dir, "benchmarks"));
}

test "log directory equals state directory" {
    const paths = try xdg.ensurePaths();
    
    try testing.expect(std.mem.eql(u8, paths.log_dir, paths.state_dir));
}

test "all paths are absolute" {
    const paths = try xdg.ensurePaths();
    
    try testing.expect(std.fs.path.isAbsolute(paths.config_dir));
    try testing.expect(std.fs.path.isAbsolute(paths.config_file));
    try testing.expect(std.fs.path.isAbsolute(paths.data_dir));
    try testing.expect(std.fs.path.isAbsolute(paths.state_dir));
    try testing.expect(std.fs.path.isAbsolute(paths.log_file));
}
