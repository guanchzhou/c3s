//! K9sMigration — one-time, best-effort import of an existing k9s installation.
//!
//! Makes c3s a drop-in replacement for k9s: on launch we look for a k9s config
//! tree ($XDG_CONFIG_HOME/k9s, ~/.config/k9s, or the macOS default
//! ~/Library/Application Support/k9s), copy everything c3s understands into the
//! c3s XDG tree, and translate the active k9s skin into the c3s `theme` key.
//! Skin files need no conversion — the theme loader parses k9s skin YAML
//! (`k9s.*` keys) byte-for-byte.
//!
//! Safety properties:
//! - Idempotent: a marker in the state dir prevents re-runs after success.
//! - Never destructive: existing c3s files are never overwritten (copy only
//!   when absent) and the k9s tree is strictly read-only.
//! - Never fatal: any failure is logged and the app starts normally; the
//!   marker is only written after a successful pass, so a k9s installed
//!   later is still picked up.

const std = @import("std");
const builtin = @import("builtin");
const xdg = @import("../core/xdg.zig");
const env = @import("../core/env.zig");
const runtime = @import("../core/runtime.zig");
const Logger = @import("../core/logger.zig");

/// Per-file copy cap. Real skins are a few KB; this bounds memory while
/// matching the theme loader's tolerance for large files.
const max_file_bytes = 1024 * 1024;

const marker_name = "k9s-import-done";

/// k9s config files c3s also understands, copied verbatim when absent.
const aux_files = [_][]const u8{ "aliases.yaml", "hotkeys.yaml", "plugins.yaml", "views.yaml" };

/// Destination paths, injected so tests can run against a temp tree without
/// touching the process-wide cached XDG paths.
pub const Dest = struct {
    config_dir: []const u8,
    config_file: []const u8,
    skins_dir: []const u8,
};

pub const Summary = struct {
    skins: usize = 0,
    aux: usize = 0,
    config_written: bool = false,

    pub fn imported(self: Summary) bool {
        return self.skins > 0 or self.aux > 0 or self.config_written;
    }
};

/// Entry point — call once at startup, before Config.load. Best-effort:
/// never blocks or fails app startup.
pub fn migrateIfNeeded(allocator: std.mem.Allocator) void {
    const paths = xdg.ensurePaths() catch return;

    const marker_path = std.fs.path.join(allocator, &.{ paths.state_dir, marker_name }) catch return;
    defer allocator.free(marker_path);
    if (fileExists(marker_path)) return;

    const k9s_dir = findK9sConfigDir(allocator) orelse return;
    defer allocator.free(k9s_dir);

    const summary = migrate(allocator, k9s_dir, .{
        .config_dir = paths.config_dir,
        .config_file = paths.config_file,
        .skins_dir = paths.skins_dir,
    }) catch |err| {
        Logger.warn("k9s import from '{s}' failed: {any}; will retry next launch", .{ k9s_dir, err });
        return;
    };

    if (summary.imported()) {
        Logger.info("k9s import from '{s}': {d} skins, {d} config files, theme mapped: {}", .{
            k9s_dir, summary.skins, summary.aux, summary.config_written,
        });
    }

    // Mark done only after a successful pass.
    std.Io.Dir.cwd().writeFile(runtime.io(), .{
        .sub_path = marker_path,
        .data = "k9s configuration imported; delete this file to re-import\n",
    }) catch |err| Logger.warn("k9s import marker write failed: {any}", .{err});
}

/// Locate an existing k9s config dir, mirroring k9s's own resolution order:
/// $XDG_CONFIG_HOME/k9s, then ~/.config/k9s, then the macOS default
/// ~/Library/Application Support/k9s. Caller frees the returned path.
fn findK9sConfigDir(allocator: std.mem.Allocator) ?[]u8 {
    if (env.getOwned(allocator, "XDG_CONFIG_HOME") catch null) |xdg_home| {
        defer allocator.free(xdg_home);
        if (xdg_home.len > 0) {
            if (existingDir(allocator, &.{ xdg_home, "k9s" })) |dir| return dir;
        }
    }

    const home = env.getOwned(allocator, "HOME") catch return null;
    defer allocator.free(home);
    if (home.len == 0) return null;

    if (existingDir(allocator, &.{ home, ".config", "k9s" })) |dir| return dir;
    if (builtin.os.tag == .macos) {
        if (existingDir(allocator, &.{ home, "Library", "Application Support", "k9s" })) |dir| return dir;
    }
    return null;
}

fn existingDir(allocator: std.mem.Allocator, parts: []const []const u8) ?[]u8 {
    const path = std.fs.path.join(allocator, parts) catch return null;
    var dir = std.Io.Dir.cwd().openDir(runtime.io(), path, .{}) catch {
        allocator.free(path);
        return null;
    };
    dir.close(runtime.io());
    return path;
}

/// Import everything c3s understands from `k9s_dir` into `dest`. Read-only on
/// the k9s side; copy-if-absent on the c3s side. Per-file failures are logged
/// and skipped so one bad file cannot abort the rest of the import.
pub fn migrate(allocator: std.mem.Allocator, k9s_dir: []const u8, dest: Dest) !Summary {
    var summary = Summary{};

    // 1) Skins are byte-for-byte compatible — copy them straight in.
    const k9s_skins = try std.fs.path.join(allocator, &.{ k9s_dir, "skins" });
    defer allocator.free(k9s_skins);
    summary.skins = copySkins(allocator, k9s_skins, dest.skins_dir);

    // 2) Aux config files c3s reads at the same relative location.
    for (aux_files) |name| {
        const src = try std.fs.path.join(allocator, &.{ k9s_dir, name });
        defer allocator.free(src);
        const dst = try std.fs.path.join(allocator, &.{ dest.config_dir, name });
        defer allocator.free(dst);
        if (copyIfAbsent(allocator, src, dst)) summary.aux += 1;
    }

    // 3) Main config: only the active skin maps onto c3s settings, and only
    //    when the user has no c3s config yet (never clobber).
    if (!fileExists(dest.config_file)) {
        const k9s_config = try std.fs.path.join(allocator, &.{ k9s_dir, "config.yaml" });
        defer allocator.free(k9s_config);
        if (readSmall(allocator, k9s_config)) |content| {
            defer allocator.free(content);
            if (extractUiSkin(content)) |skin| {
                const c3s_config = try std.fmt.allocPrint(
                    allocator,
                    "# generated by c3s from {s}\nc3s:\n  ui:\n    theme: {s}\n",
                    .{ k9s_config, skin },
                );
                defer allocator.free(c3s_config);
                std.Io.Dir.cwd().writeFile(runtime.io(), .{
                    .sub_path = dest.config_file,
                    .data = c3s_config,
                }) catch |err| {
                    Logger.warn("k9s import: writing '{s}' failed: {any}", .{ dest.config_file, err });
                    return summary;
                };
                summary.config_written = true;
            }
        }
    }

    return summary;
}

/// Copy every regular `*.yaml`/`*.yml` file from `src_dir` that is not
/// already present in `dst_dir`. Returns the number of files copied.
fn copySkins(allocator: std.mem.Allocator, src_dir: []const u8, dst_dir: []const u8) usize {
    var dir = std.Io.Dir.cwd().openDir(runtime.io(), src_dir, .{ .iterate = true }) catch return 0;
    defer dir.close(runtime.io());

    var copied: usize = 0;
    var iterator = dir.iterate();
    while (iterator.next(runtime.io()) catch null) |e| {
        if (e.kind != .file) continue;
        const is_yaml = std.mem.endsWith(u8, e.name, ".yaml") or std.mem.endsWith(u8, e.name, ".yml");
        if (!is_yaml) continue;

        const src = std.fs.path.join(allocator, &.{ src_dir, e.name }) catch continue;
        defer allocator.free(src);
        const dst = std.fs.path.join(allocator, &.{ dst_dir, e.name }) catch continue;
        defer allocator.free(dst);
        if (copyIfAbsent(allocator, src, dst)) copied += 1;
    }
    return copied;
}

/// Copy `src` to `dst` unless `dst` already exists. Returns true on copy.
fn copyIfAbsent(allocator: std.mem.Allocator, src: []const u8, dst: []const u8) bool {
    if (fileExists(dst)) return false;
    const content = readSmall(allocator, src) orelse return false;
    defer allocator.free(content);
    std.Io.Dir.cwd().writeFile(runtime.io(), .{ .sub_path = dst, .data = content }) catch |err| {
        Logger.warn("k9s import: copying to '{s}' failed: {any}", .{ dst, err });
        return false;
    };
    return true;
}

fn fileExists(path: []const u8) bool {
    std.Io.Dir.cwd().access(runtime.io(), path, .{}) catch return false;
    return true;
}

fn readSmall(allocator: std.mem.Allocator, path: []const u8) ?[]u8 {
    return std.Io.Dir.cwd().readFileAlloc(
        runtime.io(),
        path,
        allocator,
        .limited(max_file_bytes),
    ) catch null;
}

/// Extract the value of the `k9s.ui.skin` key from a k9s config.yaml.
/// Line-oriented like the c3s config parser: finds the first line whose
/// trimmed content starts with `skin:` (the only `skin:` key k9s defines)
/// and returns its unquoted value as a slice into `content`.
fn extractUiSkin(content: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.mem.startsWith(u8, trimmed, "skin:")) continue;

        var value = std.mem.trim(u8, trimmed["skin:".len..], " \t");
        if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
            value = value[1 .. value.len - 1];
        }
        if (value.len == 0) return null;
        return value;
    }
    return null;
}

const testing = std.testing;

test "extractUiSkin finds the skin under ui" {
    const config =
        \\k9s:
        \\  refreshRate: 2
        \\  skipLatestRevCheck: false
        \\  ui:
        \\    enableMouse: false
        \\    skin: dracula
        \\  logger:
        \\    tail: 100
    ;
    try testing.expectEqualStrings("dracula", extractUiSkin(config).?);
}

test "extractUiSkin unquotes quoted values" {
    try testing.expectEqualStrings("in-the-navy", extractUiSkin("  skin: \"in-the-navy\"\n").?);
}

test "extractUiSkin returns null when absent or empty" {
    try testing.expectEqual(@as(?[]const u8, null), extractUiSkin("k9s:\n  ui:\n    headless: false\n"));
    try testing.expectEqual(@as(?[]const u8, null), extractUiSkin("  skin:\n"));
    // `skins:`-style keys must not match.
    try testing.expectEqual(@as(?[]const u8, null), extractUiSkin("  skinsDir: /tmp/foo\n"));
}

// Builds disposable absolute-path source/dest trees under .zig-cache/tmp via
// testing.tmpDir, so migrate() is exercised end-to-end without touching the
// process-wide cached XDG paths or the user's real k9s install.
const MigrateFixture = struct {
    tmp: testing.TmpDir,
    root: []u8, // absolute path of the tmp dir; allocator-owned

    fn init(allocator: std.mem.Allocator) !MigrateFixture {
        var tmp = testing.tmpDir(.{});
        errdefer tmp.cleanup();
        const cwd_path = try std.process.currentPathAlloc(testing.io, allocator);
        defer allocator.free(cwd_path);
        const root = try std.fs.path.join(allocator, &.{
            cwd_path, ".zig-cache", "tmp", &tmp.sub_path,
        });
        return .{ .tmp = tmp, .root = root };
    }

    fn deinit(self: *MigrateFixture, allocator: std.mem.Allocator) void {
        allocator.free(self.root);
        self.tmp.cleanup();
    }

    fn abs(self: *MigrateFixture, allocator: std.mem.Allocator, sub: []const u8) ![]u8 {
        return std.fs.path.join(allocator, &.{ self.root, sub });
    }
};

test "migrate imports skins, aux files, and maps the skin to theme" {
    const allocator = testing.allocator;
    var fx = try MigrateFixture.init(allocator);
    defer fx.deinit(allocator);

    // Fake k9s tree.
    try fx.tmp.dir.createDirPath(testing.io, "k9s/skins");
    try fx.tmp.dir.writeFile(testing.io, .{
        .sub_path = "k9s/config.yaml",
        .data = "k9s:\n  ui:\n    skin: dracula\n",
    });
    try fx.tmp.dir.writeFile(testing.io, .{
        .sub_path = "k9s/skins/dracula.yaml",
        .data = "k9s:\n  body:\n    fgColor: \"#f8f8f2\"\n",
    });
    try fx.tmp.dir.writeFile(testing.io, .{
        .sub_path = "k9s/aliases.yaml",
        .data = "aliases:\n  dp: deployments\n",
    });
    try fx.tmp.dir.writeFile(testing.io, .{ .sub_path = "k9s/skins/notes.txt", .data = "not a skin" });

    // Empty c3s dest tree.
    try fx.tmp.dir.createDirPath(testing.io, "c3s/skins");

    const k9s_dir = try fx.abs(allocator, "k9s");
    defer allocator.free(k9s_dir);
    const dest = Dest{
        .config_dir = try fx.abs(allocator, "c3s"),
        .config_file = try fx.abs(allocator, "c3s/config.yaml"),
        .skins_dir = try fx.abs(allocator, "c3s/skins"),
    };
    defer allocator.free(dest.config_dir);
    defer allocator.free(dest.config_file);
    defer allocator.free(dest.skins_dir);

    const summary = try migrate(allocator, k9s_dir, dest);
    try testing.expectEqual(@as(usize, 1), summary.skins);
    try testing.expectEqual(@as(usize, 1), summary.aux);
    try testing.expect(summary.config_written);

    const written = try fx.tmp.dir.readFileAlloc(testing.io, "c3s/config.yaml", allocator, .limited(4096));
    defer allocator.free(written);
    try testing.expect(std.mem.indexOf(u8, written, "theme: dracula") != null);

    // Second run: everything already present → nothing copied, no clobber.
    const again = try migrate(allocator, k9s_dir, dest);
    try testing.expectEqual(@as(usize, 0), again.skins);
    try testing.expectEqual(@as(usize, 0), again.aux);
    try testing.expect(!again.config_written);
}

test "migrate never overwrites an existing c3s config" {
    const allocator = testing.allocator;
    var fx = try MigrateFixture.init(allocator);
    defer fx.deinit(allocator);

    try fx.tmp.dir.createDirPath(testing.io, "k9s");
    try fx.tmp.dir.writeFile(testing.io, .{
        .sub_path = "k9s/config.yaml",
        .data = "k9s:\n  ui:\n    skin: dracula\n",
    });
    try fx.tmp.dir.createDirPath(testing.io, "c3s/skins");
    try fx.tmp.dir.writeFile(testing.io, .{
        .sub_path = "c3s/config.yaml",
        .data = "c3s:\n  ui:\n    theme: tokyo-night\n",
    });

    const k9s_dir = try fx.abs(allocator, "k9s");
    defer allocator.free(k9s_dir);
    const dest = Dest{
        .config_dir = try fx.abs(allocator, "c3s"),
        .config_file = try fx.abs(allocator, "c3s/config.yaml"),
        .skins_dir = try fx.abs(allocator, "c3s/skins"),
    };
    defer allocator.free(dest.config_dir);
    defer allocator.free(dest.config_file);
    defer allocator.free(dest.skins_dir);

    const summary = try migrate(allocator, k9s_dir, dest);
    try testing.expect(!summary.config_written);

    const kept = try fx.tmp.dir.readFileAlloc(testing.io, "c3s/config.yaml", allocator, .limited(4096));
    defer allocator.free(kept);
    try testing.expect(std.mem.indexOf(u8, kept, "tokyo-night") != null);
}
