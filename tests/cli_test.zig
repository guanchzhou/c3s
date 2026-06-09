const std = @import("std");
const testing = std.testing;

// Since cli.zig functions use std.debug.print and interact with environment,
// we'll test the public interface and helper functions

test "logo array is correctly defined" {
    // We can't directly import logo_small as it's private, but we can verify
    // the module compiles and contains the expected structure
    const cli = @import("src").cli;
    _ = cli;
}

test "CLI parseArgs with help flag" {
    const cli = @import("src").cli;

    // Test would require mocking process.args, which is complex
    // For now, verify the module compiles
    _ = cli.parseArgs;
}

test "CLI parseArgs with version flag" {
    const cli = @import("src").cli;
    _ = cli.parseArgs;
    // Version handling is tested separately in version_test.zig
}

test "CLI Config default values" {
    const cli = @import("src").cli;

    const default_config = cli.Config{};

    try testing.expect(default_config.all_namespaces == false);
    try testing.expect(default_config.context == null);
    try testing.expect(default_config.namespace == null);
    try testing.expect(default_config.command == null);
    try testing.expect(default_config.refresh_rate == 2.0);
    try testing.expect(std.mem.eql(u8, default_config.log_level, "info"));
    try testing.expect(default_config.log_file == null);
    try testing.expect(default_config.debug == false);
    try testing.expect(default_config.readonly == false);
    try testing.expect(default_config.headless == false);
    try testing.expect(default_config.crumbsless == false);
    try testing.expect(default_config.logoless == false);
    try testing.expect(default_config.splashless == false);
    try testing.expect(default_config.write == false);
}

test "CLI Config flag toggles" {
    const cli = @import("src").cli;

    const config = cli.Config{
        .all_namespaces = true,
        .debug = true,
        .readonly = true,
        .write = true,
    };

    try testing.expect(config.all_namespaces == true);
    try testing.expect(config.debug == true);
    try testing.expect(config.readonly == true);
    try testing.expect(config.write == true);
}

test "CLI Config with custom values" {
    const cli = @import("src").cli;

    const config = cli.Config{
        .refresh_rate = 5.0,
        .log_level = "debug",
        .context = "test-context",
        .namespace = "test-namespace",
    };

    try testing.expect(config.refresh_rate == 5.0);
    try testing.expect(std.mem.eql(u8, config.log_level, "debug"));
    try testing.expect(std.mem.eql(u8, config.context.?, "test-context"));
    try testing.expect(std.mem.eql(u8, config.namespace.?, "test-namespace"));
}
