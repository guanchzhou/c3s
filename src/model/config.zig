const std = @import("std");
const xdg = @import("../core/xdg.zig");
const runtime = @import("../core/runtime.zig");

pub const UiConfig = struct {
    compact: bool = false,
    footer: bool = true,
    theme: []const u8 = "tokyo-night",
    theme_allocated: ?[]u8 = null,
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    ui: UiConfig,
    theme_owned: ?[]u8 = null,

    pub fn deinit(self: *const Config) void {
        if (self.theme_owned) |theme| {
            self.allocator.free(theme);
        }
    }
};

pub fn load(allocator: std.mem.Allocator) !Config {
    // Get XDG paths
    const paths = xdg.ensurePaths() catch {
        // If XDG paths fail, return defaults
        return Config{
            .allocator = allocator,
            .ui = UiConfig{},
        };
    };

    // Try to read config file
    const config_content = std.Io.Dir.cwd().readFileAlloc(
        runtime.io(),
        paths.config_file,
        allocator,
        .limited(1024 * 1024), // 1MB max
    ) catch {
        // File not found or read error - return defaults
        return Config{
            .allocator = allocator,
            .ui = UiConfig{},
        };
    };
    defer allocator.free(config_content);

    // Parse the YAML (simple parser for our use case)
    const ui_config = try parseUiConfig(allocator, config_content);

    const Logger = @import("../core/logger.zig");
    Logger.info("Config loaded - compact: {}, footer: {}", .{ ui_config.compact, ui_config.footer });

    return Config{
        .allocator = allocator,
        .ui = ui_config,
        .theme_owned = ui_config.theme_allocated,
    };
}

fn parseUiConfig(allocator: std.mem.Allocator, content: []const u8) !UiConfig {
    var ui_config = UiConfig{};

    // Simple line-by-line parser
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Keys are matched with startsWith, not indexOf. `trimmed` has already lost
        // its indentation, so nested YAML keys still match -- but a commented-out
        // line no longer does. With indexOf, "# theme: dracula" was parsed as live
        // config, which is the opposite of what commenting a line out means.
        if (std.mem.startsWith(u8, trimmed, "compact:")) {
            if (std.mem.indexOf(u8, trimmed, "true")) |_| {
                ui_config.compact = true;
            } else if (std.mem.indexOf(u8, trimmed, "false")) |_| {
                ui_config.compact = false;
            }
        }

        // Look for "footer:" line
        if (std.mem.startsWith(u8, trimmed, "footer:")) {
            // Check if it's set to true or false
            if (std.mem.indexOf(u8, trimmed, "true")) |_| {
                ui_config.footer = true;
            } else if (std.mem.indexOf(u8, trimmed, "false")) |_| {
                ui_config.footer = false;
            }
        }

        // Look for "theme:" line
        if (std.mem.startsWith(u8, trimmed, "theme:")) {
            const after_colon = std.mem.trim(u8, trimmed["theme:".len..], " \t");
            if (after_colon.len > 0) {
                // Strip surrounding quotes. The length check MUST be >= 2: with only
                // `len > 0`, a single `"` satisfied both the first- and last-byte
                // tests (they are the same byte), and the slice below became [1..0] --
                // start > end, which panics. A config line of `theme: "` therefore
                // killed the app at launch, and not behind any catch.
                var theme_name = after_colon;
                if (theme_name.len >= 2 and theme_name[0] == '"' and theme_name[theme_name.len - 1] == '"') {
                    theme_name = theme_name[1 .. theme_name.len - 1];
                }
                // Allocate the theme name since it points into content buffer.
                // Free any previous value first: a file with two theme: lines used to
                // leak the first one by overwriting theme_allocated.
                const owned = try allocator.dupe(u8, theme_name);
                if (ui_config.theme_allocated) |prev| allocator.free(prev);
                ui_config.theme = owned;
                ui_config.theme_allocated = owned;
            }
        }
    }

    return ui_config;
}

const testing = std.testing;

// Zig 0.16 removed `std.process.setEnvVar`; c3s reads env via libc `getenv`
// (src/core/env.zig), so set it the same way here. libc is linked.
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

// The XDG layer (src/core/xdg.zig) caches the resolved config dir process-wide on
// the *first* `ensurePaths()` call and ignores later XDG_CONFIG_HOME changes, so
// every test in this binary necessarily shares one config directory. We therefore
// set up a single shared temp config dir lazily and reuse it across tests.
// `Config.load` re-reads `config.yaml` from the (cached) dir on every call, so
// tests stay independent by rewriting/removing the file before each load.
//
// The shared dir uses the page allocator and intentionally lives for the whole
// process (it backs the cached XDG path), so it is never torn down.
const SharedEnv = struct {
    var tmp_dir: testing.TmpDir = undefined;
    var initialized = false;

    /// Returns the shared temp config dir, creating it (and pinning the cached
    /// XDG path) on first use.
    fn dir() !std.Io.Dir {
        if (!initialized) {
            tmp_dir = testing.tmpDir(.{});

            const alloc = std.heap.page_allocator;

            // XDG_CONFIG_HOME must be absolute; build it from cwd + tmp sub_path.
            const cwd_path = try std.process.currentPathAlloc(testing.io, alloc);
            defer alloc.free(cwd_path);

            const xdg_home = try std.fs.path.joinZ(alloc, &.{
                cwd_path, ".zig-cache", "tmp", &tmp_dir.sub_path,
            });
            defer alloc.free(xdg_home);
            _ = setenv("XDG_CONFIG_HOME", xdg_home.ptr, 1);

            // resolveConfigDir appends the app name ("c3s") to XDG_CONFIG_HOME.
            try tmp_dir.dir.createDirPath(testing.io, "c3s");

            initialized = true;
        }
        return tmp_dir.dir;
    }

    fn writeConfig(content: []const u8) !void {
        const d = try dir();
        try d.writeFile(testing.io, .{ .sub_path = "c3s/config.yaml", .data = content });
        repinXdgCache();
    }

    /// Removes config.yaml so `Config.load` exercises the missing-file path.
    fn removeConfig() !void {
        const d = try dir();
        d.deleteFile(testing.io, "c3s/config.yaml") catch {};
        repinXdgCache();
    }

    /// Any earlier test that touched ensurePaths() pinned the process-wide
    /// XDG cache to the REAL ~/.config/c3s — Config.load would then read the
    /// user's actual config instead of the fixture written above. Drop the
    /// cache so the next load re-resolves from our XDG_CONFIG_HOME.
    fn repinXdgCache() void {
        xdg.resetCachedPathsForTests();
    }
};

test "config loads default values when file missing" {
    const allocator = testing.allocator;

    try SharedEnv.removeConfig();

    // Load config - should return defaults
    const config = try load(allocator);
    defer config.deinit();

    // Default should have compact = false
    try testing.expectEqual(false, config.ui.compact);
}

test "config loads compact mode from YAML" {
    const allocator = testing.allocator;

    try SharedEnv.writeConfig(
        \\c3s:
        \\  ui:
        \\    compact: true
    );

    const config = try load(allocator);
    defer config.deinit();

    // Should load compact = true
    try testing.expectEqual(true, config.ui.compact);
}

test "config handles compact false" {
    const allocator = testing.allocator;

    try SharedEnv.writeConfig(
        \\c3s:
        \\  ui:
        \\    compact: false
    );

    const config = try load(allocator);
    defer config.deinit();

    try testing.expectEqual(false, config.ui.compact);
}

test "config ignores malformed YAML gracefully" {
    const allocator = testing.allocator;

    try SharedEnv.writeConfig("this is not valid yaml {}[]");

    // Should fall back to defaults
    const config = try load(allocator);
    defer config.deinit();

    try testing.expectEqual(false, config.ui.compact);
}

test "config: a lone quote does not panic at startup" {
    // `theme: "` used to kill the app on launch. theme_name[0] and
    // theme_name[len-1] are the same byte when len == 1, so both quote checks
    // passed with no pair present and the slice became [1..0] -- start > end.
    const cfg = try parseUiConfig(std.testing.allocator, "theme: \"\n");
    defer if (cfg.theme_allocated) |t| std.testing.allocator.free(t);

    // The value survives as-is; the point is that we get here at all.
    try std.testing.expectEqualStrings("\"", cfg.theme);
}

test "config: quotes are stripped only when they are a pair" {
    const a = std.testing.allocator;

    const quoted = try parseUiConfig(a, "theme: \"dracula\"\n");
    defer if (quoted.theme_allocated) |t| a.free(t);
    try std.testing.expectEqualStrings("dracula", quoted.theme);

    const bare = try parseUiConfig(a, "theme: dracula\n");
    defer if (bare.theme_allocated) |t| a.free(t);
    try std.testing.expectEqualStrings("dracula", bare.theme);

    // One leading quote is not a pair and must be left alone, not sliced.
    const half = try parseUiConfig(a, "theme: \"dracula\n");
    defer if (half.theme_allocated) |t| a.free(t);
    try std.testing.expectEqualStrings("\"dracula", half.theme);
}

test "config: a commented-out key is not live config" {
    // indexOf matched "theme:" anywhere in the line, so a commented line was applied.
    // Commenting a setting out is how a user disables it.
    const a = std.testing.allocator;

    const commented = try parseUiConfig(a, "# theme: dracula\n");
    defer if (commented.theme_allocated) |t| a.free(t);
    try std.testing.expect(commented.theme_allocated == null);
    try std.testing.expect(!std.mem.eql(u8, commented.theme, "dracula"));

    // Same for the booleans.
    const c2 = try parseUiConfig(a, "# compact: true\n# footer: false\n");
    defer if (c2.theme_allocated) |t| a.free(t);
    const defaults = UiConfig{};
    try std.testing.expectEqual(defaults.compact, c2.compact);
    try std.testing.expectEqual(defaults.footer, c2.footer);
}

test "config: indented keys still parse" {
    // startsWith operates on the already-trimmed line, so nested YAML keeps working.
    const a = std.testing.allocator;
    const nested = try parseUiConfig(a, "ui:\n  theme: nord\n  compact: true\n");
    defer if (nested.theme_allocated) |t| a.free(t);
    try std.testing.expectEqualStrings("nord", nested.theme);
    try std.testing.expect(nested.compact);
}

test "config: a second theme line does not leak the first" {
    // theme_allocated was overwritten without freeing. testing.allocator fails the
    // test on any leak, so this assertion is the leak check.
    const a = std.testing.allocator;
    const cfg = try parseUiConfig(a, "theme: first\ntheme: second\n");
    defer if (cfg.theme_allocated) |t| a.free(t);
    try std.testing.expectEqualStrings("second", cfg.theme);
}
