const std = @import("std");
const testing = std.testing;
const Config = @import("src").Config;

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
    }

    /// Removes config.yaml so `Config.load` exercises the missing-file path.
    fn removeConfig() !void {
        const d = try dir();
        d.deleteFile(testing.io, "c3s/config.yaml") catch {};
    }
};

test "config loads default values when file missing" {
    const allocator = testing.allocator;

    try SharedEnv.removeConfig();

    // Load config - should return defaults
    const config = try Config.load(allocator);
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

    const config = try Config.load(allocator);
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

    const config = try Config.load(allocator);
    defer config.deinit();

    try testing.expectEqual(false, config.ui.compact);
}

test "config ignores malformed YAML gracefully" {
    const allocator = testing.allocator;

    try SharedEnv.writeConfig("this is not valid yaml {}[]");

    // Should fall back to defaults
    const config = try Config.load(allocator);
    defer config.deinit();

    try testing.expectEqual(false, config.ui.compact);
}
