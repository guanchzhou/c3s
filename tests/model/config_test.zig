const std = @import("std");
const testing = std.testing;
const Config = @import("config");

test "config loads default values when file missing" {
    const allocator = testing.allocator;
    
    // Create temp directory
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    // Set XDG_CONFIG_HOME to temp (no config file exists)
    try std.process.setEnvVar("XDG_CONFIG_HOME", tmp_path);
    
    // Load config - should return defaults
    const config = try Config.load(allocator);
    defer config.deinit();
    
    // Default should have compact = false
    try testing.expectEqual(false, config.ui.compact);
}

test "config loads compact mode from YAML" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    // Create c3s directory
    const c3s_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "c3s" });
    defer allocator.free(c3s_dir);
    
    try std.fs.cwd().makePath(c3s_dir);
    
    // Write config file
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ c3s_dir, "config.yaml" });
    defer allocator.free(config_path);
    
    const config_content =
        \\c3s:
        \\  ui:
        \\    compact: true
    ;
    
    try std.fs.cwd().writeFile(.{
        .sub_path = config_path,
        .data = config_content,
    });
    
    // Set XDG_CONFIG_HOME
    try std.process.setEnvVar("XDG_CONFIG_HOME", tmp_path);
    
    // Load config
    const config = try Config.load(allocator);
    defer config.deinit();
    
    // Should load compact = true
    try testing.expectEqual(true, config.ui.compact);
}

test "config handles compact false" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    const c3s_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "c3s" });
    defer allocator.free(c3s_dir);
    
    try std.fs.cwd().makePath(c3s_dir);
    
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ c3s_dir, "config.yaml" });
    defer allocator.free(config_path);
    
    const config_content =
        \\c3s:
        \\  ui:
        \\    compact: false
    ;
    
    try std.fs.cwd().writeFile(.{
        .sub_path = config_path,
        .data = config_content,
    });
    
    try std.process.setEnvVar("XDG_CONFIG_HOME", tmp_path);
    
    const config = try Config.load(allocator);
    defer config.deinit();
    
    try testing.expectEqual(false, config.ui.compact);
}

test "config ignores malformed YAML gracefully" {
    const allocator = testing.allocator;
    
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    
    const tmp_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(tmp_path);
    
    const c3s_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "c3s" });
    defer allocator.free(c3s_dir);
    
    try std.fs.cwd().makePath(c3s_dir);
    
    const config_path = try std.fs.path.join(allocator, &[_][]const u8{ c3s_dir, "config.yaml" });
    defer allocator.free(config_path);
    
    // Write invalid YAML
    const config_content = "this is not valid yaml {}[]";
    
    try std.fs.cwd().writeFile(.{
        .sub_path = config_path,
        .data = config_content,
    });
    
    try std.process.setEnvVar("XDG_CONFIG_HOME", tmp_path);
    
    // Should fall back to defaults
    const config = try Config.load(allocator);
    defer config.deinit();
    
    try testing.expectEqual(false, config.ui.compact);
}
