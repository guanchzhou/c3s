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

// ============================================================================
// Writing the theme back
//
// This lived in App.saveThemeToConfig as ~100 lines of inline YAML rewriting, which
// made it untestable (it needed an App) and hid a bug that survived in shipped code:
// see the tests below. It belongs here -- App is the controller; serialising config is
// the config model's job -- and as a pure string transformation it is trivially
// testable.
// ============================================================================

/// Rewrite `content` so the `ui:` section's `theme:` is `theme_name`. Caller owns.
pub fn withTheme(
    allocator: std.mem.Allocator,
    content: []const u8,
    theme_name: []const u8,
) ![]u8 {
    if (std.mem.trim(u8, content, " \t\r\n").len == 0) {
        return std.fmt.allocPrint(
            allocator,
            "c3s:\n  ui:\n    compact: false\n    theme: {s}\n",
            .{theme_name},
        );
    }

    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);

    var in_ui = false;
    var ui_indent: usize = 0;
    var wrote_theme = false;
    var saw_ui = false;

    // Keep the source's own line endings rather than normalising them.
    const ends_with_newline = content.len > 0 and content[content.len - 1] == '\n';
    // Every piece splitScalar yields is emitted, including the empty one that trails
    // content ending in '\n'. Skipping it looked right and was worse: it swallowed the
    // user's trailing blank lines, and made the whole function non-idempotent for a file
    // ending in more than one newline -- each save removed one, so repeated saves kept
    // rewriting the file. Found by mutation: deleting the skip made every case
    // idempotent, which is the opposite of what a surviving mutant usually means.
    var it = std.mem.splitScalar(u8, content, '\n');
    var first = true;
    while (it.next()) |raw| {
        if (!first) try out.append(allocator, '\n');
        first = false;

        const line = std.mem.trimEnd(u8, raw, "\r");
        const trimmed = std.mem.trim(u8, line, " \t");
        const indent = line.len - std.mem.trimStart(u8, line, " \t").len;

        // startsWith, not indexOf: `# gui: x` or `refresh_ui: true` must not open the
        // section. config.zig's parser was already fixed for exactly this.
        if (std.mem.startsWith(u8, trimmed, "ui:")) {
            in_ui = true;
            saw_ui = true;
            ui_indent = indent;
            try out.appendSlice(allocator, raw);
            continue;
        }

        if (in_ui) {
            // Leaving the section: a non-blank line indented no deeper than `ui:`.
            // The original compared trimmed[0] != ' ' on an already-trimmed string,
            // which can never be a space -- so it "left" the section on the FIRST
            // line inside it, and stopped replacing the real theme line.
            if (trimmed.len > 0 and indent <= ui_indent) {
                if (!wrote_theme) {
                    try writeThemeLine(allocator, &out, ui_indent + 2, theme_name);
                    try out.append(allocator, '\n');
                    wrote_theme = true;
                }
                in_ui = false;
            } else if (std.mem.startsWith(u8, trimmed, "theme:")) {
                // Replace in place, preserving this line's own indentation. The old
                // code emitted the new value and then let the old line through, so the
                // file ended up with both -- and config.zig's parser takes the LAST
                // one, so the change silently did not stick across a restart.
                try writeThemeLine(allocator, &out, indent, theme_name);
                wrote_theme = true;
                continue;
            }
        }

        try out.appendSlice(allocator, raw);
    }

    if (!saw_ui) {
        // No ui section at all: add one rather than a stray top-level theme key.
        if (!first) try out.append(allocator, '\n');
        try out.appendSlice(allocator, "  ui:\n");
        try writeThemeLine(allocator, &out, 4, theme_name);
        wrote_theme = true;
    } else if (!wrote_theme) {
        // Section ran to end of file without a theme line.
        if (!first) try out.append(allocator, '\n');
        try writeThemeLine(allocator, &out, ui_indent + 2, theme_name);
        wrote_theme = true;
    }

    if (ends_with_newline and (out.items.len == 0 or out.items[out.items.len - 1] != '\n')) {
        try out.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}

fn writeThemeLine(
    allocator: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(u8),
    indent: usize,
    theme_name: []const u8,
) !void {
    try out.appendNTimes(allocator, ' ', indent);
    try out.appendSlice(allocator, "theme: ");
    try out.appendSlice(allocator, theme_name);
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

// ---------------------------------------------------------------------------
// withTheme
//
// The first two tests below are regressions for a bug that shipped: choosing a theme
// applied for the session and silently reverted on restart. App.saveThemeToConfig
// emitted the new `theme:` line and then let the OLD one through, and parseUiConfig
// takes the LAST match -- so the stale value won, and the file gained a line every save.
//
// Root cause was a section-exit test that could never be true:
//     if (in_ui_section and trimmed.len > 0 and trimmed[0] != ' ')
// `trimmed` is already space-trimmed, so trimmed[0] is never ' '. The branch fired on
// the FIRST line inside `ui:` rather than on leaving it, so the real theme line was
// never reached.
// ---------------------------------------------------------------------------

fn countThemeLines(s: []const u8) usize {
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, s, '\n');
    while (it.next()) |l| {
        const t = std.mem.trim(u8, l, " \t\r");
        if (std.mem.startsWith(u8, t, "theme:")) n += 1;
    }
    return n;
}

test "withTheme replaces the theme when another ui key precedes it" {
    // The exact shipped bug, on the exact layout c3s itself writes.
    const a = testing.allocator;
    const out = try withTheme(a, "c3s:\n  ui:\n    compact: false\n    theme: dracula\n", "gruvbox");
    defer a.free(out);

    try testing.expectEqual(@as(usize, 1), countThemeLines(out));
    try testing.expect(std.mem.indexOf(u8, out, "theme: gruvbox") != null);
    try testing.expect(std.mem.indexOf(u8, out, "dracula") == null);
    // And the sibling key survives.
    try testing.expect(std.mem.indexOf(u8, out, "compact: false") != null);
}

test "withTheme round-trips through the real parser" {
    // The strongest form: write it, then read it back with parseUiConfig and confirm the
    // NEW theme wins. The old code passed a naive "did we write the name" check while
    // still losing to the stale line here, because the parser takes the last match.
    const a = testing.allocator;
    const out = try withTheme(a, "c3s:\n  ui:\n    compact: false\n    theme: dracula\n", "gruvbox");
    defer a.free(out);

    const ui = try parseUiConfig(a, out);
    defer if (ui.theme_allocated) |t| a.free(t);
    try testing.expectEqualStrings("gruvbox", ui.theme);
}

test "withTheme is idempotent, so saving does not grow the file" {
    // Two separate growth bugs: the duplicated theme line, and splitScalar's empty tail
    // piece for content ending in a newline, which the old code emitted as a blank line
    // on every single save.
    const a = testing.allocator;
    const once = try withTheme(a, "c3s:\n  ui:\n    compact: false\n    theme: dracula\n", "gruvbox");
    defer a.free(once);
    const twice = try withTheme(a, once, "gruvbox");
    defer a.free(twice);
    try testing.expectEqualStrings(once, twice);
}

test "withTheme handles a config with no ui section" {
    const a = testing.allocator;
    const out = try withTheme(a, "c3s:\n  cluster:\n    refresh: 5\n", "gruvbox");
    defer a.free(out);

    try testing.expectEqual(@as(usize, 1), countThemeLines(out));
    try testing.expect(std.mem.indexOf(u8, out, "ui:") != null);
    // The unrelated section is preserved, not clobbered.
    try testing.expect(std.mem.indexOf(u8, out, "refresh: 5") != null);

    const ui = try parseUiConfig(a, out);
    defer if (ui.theme_allocated) |t| a.free(t);
    try testing.expectEqualStrings("gruvbox", ui.theme);
}

test "withTheme creates a whole config from nothing" {
    const a = testing.allocator;
    for ([_][]const u8{ "", "\n", "   \n\t\n" }) |empty| {
        const out = try withTheme(a, empty, "gruvbox");
        defer a.free(out);
        try testing.expectEqual(@as(usize, 1), countThemeLines(out));

        const ui = try parseUiConfig(a, out);
        defer if (ui.theme_allocated) |t| a.free(t);
        try testing.expectEqualStrings("gruvbox", ui.theme);
    }
}

test "withTheme does not mistake a commented-out theme for the real one" {
    const a = testing.allocator;
    const out = try withTheme(a, "c3s:\n  ui:\n    # theme: old-commented\n    theme: dracula\n", "gruvbox");
    defer a.free(out);

    // The comment is left alone, and the live line is the one replaced.
    try testing.expect(std.mem.indexOf(u8, out, "# theme: old-commented") != null);
    try testing.expect(std.mem.indexOf(u8, out, "theme: gruvbox") != null);
    try testing.expect(std.mem.indexOf(u8, out, "theme: dracula") == null);

    const ui = try parseUiConfig(a, out);
    defer if (ui.theme_allocated) |t| a.free(t);
    try testing.expectEqualStrings("gruvbox", ui.theme);
}

test "withTheme is not fooled by a key merely containing ui:" {
    // The old code used indexOf(trimmed, "ui:"), so `refresh_ui: true` opened the
    // section early. parseUiConfig was already fixed for the same class of mistake.
    const a = testing.allocator;
    const out = try withTheme(a, "c3s:\n  refresh_ui: true\n  ui:\n    theme: dracula\n", "gruvbox");
    defer a.free(out);

    try testing.expectEqual(@as(usize, 1), countThemeLines(out));
    try testing.expect(std.mem.indexOf(u8, out, "refresh_ui: true") != null);
    // The theme must sit under the REAL `ui:` section, not be nested under
    // refresh_ui. Asserting only "the name is in the file" passed even with indexOf,
    // which opened the section on the wrong line.
    const ui_at = std.mem.indexOf(u8, out, "  ui:\n").?;
    const theme_at = std.mem.indexOf(u8, out, "theme: gruvbox").?;
    try testing.expect(theme_at > ui_at);

    const ui = try parseUiConfig(a, out);
    defer if (ui.theme_allocated) |t| a.free(t);
    try testing.expectEqualStrings("gruvbox", ui.theme);
}

test "withTheme handles CRLF and a missing trailing newline" {
    const a = testing.allocator;
    for ([_][]const u8{
        "c3s:\r\n  ui:\r\n    compact: false\r\n    theme: dracula\r\n",
        "c3s:\n  ui:\n    theme: dracula",
    }) |input| {
        const out = try withTheme(a, input, "gruvbox");
        defer a.free(out);
        try testing.expectEqual(@as(usize, 1), countThemeLines(out));

        const ui = try parseUiConfig(a, out);
        defer if (ui.theme_allocated) |t| a.free(t);
        try testing.expectEqualStrings("gruvbox", ui.theme);
    }
}

test "withTheme keeps a section that follows ui" {
    const a = testing.allocator;
    const out = try withTheme(
        a,
        "c3s:\n  ui:\n    compact: false\n    theme: dracula\n  cluster:\n    refresh: 5\n",
        "gruvbox",
    );
    defer a.free(out);

    try testing.expectEqual(@as(usize, 1), countThemeLines(out));
    try testing.expect(std.mem.indexOf(u8, out, "cluster:") != null);
    try testing.expect(std.mem.indexOf(u8, out, "refresh: 5") != null);
}

test "withTheme preserves trailing blank lines and stays idempotent" {
    // Regression for a bug introduced during this very fix: an "obviously right" skip of
    // splitScalar's empty tail piece ate the user's trailing blank lines, and made the
    // function non-idempotent for files ending in more than one newline -- each save
    // dropped one. A mutation deleting that skip fixed every case, which is how it
    // surfaced.
    const a = testing.allocator;
    for ([_][]const u8{
        "c3s:\n  ui:\n    theme: dracula\n",
        "c3s:\n  ui:\n    theme: dracula\n\n",
        "c3s:\n  ui:\n    theme: dracula\n\n\n",
        "c3s:\n  ui:\n    theme: dracula",
    }) |input| {
        const once = try withTheme(a, input, "gruvbox");
        defer a.free(once);
        const twice = try withTheme(a, once, "gruvbox");
        defer a.free(twice);
        // Idempotent for every trailing shape, so saving repeatedly never rewrites.
        try testing.expectEqualStrings(once, twice);
        try testing.expectEqual(@as(usize, 1), countThemeLines(once));
    }

    // And the blank lines really are kept rather than collapsed.
    const kept = try withTheme(a, "c3s:\n  ui:\n    theme: dracula\n\n", "gruvbox");
    defer a.free(kept);
    try testing.expect(std.mem.endsWith(u8, kept, "\n\n"));
}

fn countOccurrences(haystack: []const u8, needle: []const u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, i, needle)) |at| : (i = at + needle.len) n += 1;
    return n;
}

test "withTheme writes the theme exactly once, even with a misleading key and an unrelated theme" {
    // A sharper fixture than the refresh_ui one, which turned out not to distinguish:
    // there, the real `ui:` line reset the section indent to the same value, so
    // indexOf and startsWith produced identical output and the mutant survived.
    //
    // Here the misleading key is followed by a DIFFERENT section that itself contains a
    // `theme:` key. With indexOf, `refresh_ui: true` opens the ui section early,
    // `plugins:` then closes it and gets a theme line inserted before it, and the real
    // one is rewritten too -- so the new value lands twice and the file grows.
    const a = testing.allocator;
    const out = try withTheme(
        a,
        "c3s:\n  refresh_ui: true\n  plugins:\n    theme: keep-me\n  ui:\n    theme: dracula\n",
        "gruvbox",
    );
    defer a.free(out);

    // Written exactly once. This is the assertion that distinguishes the two.
    try testing.expectEqual(@as(usize, 1), countOccurrences(out, "theme: gruvbox"));
    // The unrelated section's own key is untouched.
    try testing.expect(std.mem.indexOf(u8, out, "theme: keep-me") != null);
    // And the value we replaced is gone.
    try testing.expect(std.mem.indexOf(u8, out, "dracula") == null);
}
