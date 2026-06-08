const std = @import("std");
const testing = std.testing;
const src = @import("src");
const Logger = src.Logger;
const runtime = src.runtime;

// Zig 0.16 exposes neither std.process.setEnvVar nor std.c.setenv; declare the libc symbol.
extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

// Sets XDG_STATE_HOME so the logger resolves its log file under `dir`.
// Note: xdg.ensurePaths() caches the resolved paths process-wide on first call,
// so the first logger init in this test binary fixes the state dir for the rest
// of the run. Each test therefore reads back the *actual* resolved log path via
// Logger.getLogFilePath() rather than reconstructing it from a per-test tmp dir.
// xdg.zig requires an absolute XDG_STATE_HOME, so we resolve cwd via libc getcwd
// (Zig 0.16 has no std getcwd) and join the tmp dir's relative sub_path.
fn setStateHome(dir: [:0]const u8) void {
    _ = setenv("XDG_STATE_HOME", dir.ptr, 1);
}

// Builds an absolute path to the testing tmp dir: <cwd>/.zig-cache/tmp/<sub_path>.
fn absTmpPath(allocator: std.mem.Allocator, tmp: *std.testing.TmpDir) ![:0]u8 {
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse return error.GetCwdFailed;
    const cwd = std.mem.sliceTo(cwd_ptr, 0);
    return std.fs.path.joinZ(allocator, &.{ cwd, ".zig-cache", "tmp", &tmp.sub_path });
}

fn readLog(allocator: std.mem.Allocator) ![]u8 {
    const log_path = Logger.getLogFilePath() orelse return error.NoLogPath;
    return std.Io.Dir.cwd().readFileAlloc(runtime.io(), log_path, allocator, .limited(1024 * 1024));
}

test "logger writes to file" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path_z = try absTmpPath(allocator, &tmp_dir);
    defer allocator.free(tmp_path_z);

    setStateHome(tmp_path_z);

    try Logger.initGlobalLogger(.info);
    defer Logger.deinitGlobalLogger();

    Logger.info("Test log message: {s}", .{"hello"});

    const log_content = try readLog(allocator);
    defer allocator.free(log_content);

    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "INFO"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "Test log message: hello"));
}

test "logger respects log level" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path_z = try absTmpPath(allocator, &tmp_dir);
    defer allocator.free(tmp_path_z);

    setStateHome(tmp_path_z);

    try Logger.initGlobalLogger(.warn);
    defer Logger.deinitGlobalLogger();

    // Debug and Info should not be logged at WARN level.
    Logger.debug("level-test debug message", .{});
    Logger.info("level-test info message", .{});

    // Warn and Error should be logged.
    Logger.warn("level-test warn message", .{});
    Logger.err("level-test error message", .{});

    const log_content = try readLog(allocator);
    defer allocator.free(log_content);

    try testing.expect(!std.mem.containsAtLeast(u8, log_content, 1, "level-test debug message"));
    try testing.expect(!std.mem.containsAtLeast(u8, log_content, 1, "level-test info message"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "level-test warn message"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "level-test error message"));
}

test "logger appends to existing file" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path_z = try absTmpPath(allocator, &tmp_dir);
    defer allocator.free(tmp_path_z);

    setStateHome(tmp_path_z);

    // First logger session.
    try Logger.initGlobalLogger(.info);
    Logger.info("append-test first message", .{});
    Logger.deinitGlobalLogger();

    // Second logger session — opens the same file in append mode.
    try Logger.initGlobalLogger(.info);
    defer Logger.deinitGlobalLogger();
    Logger.info("append-test second message", .{});

    const log_content = try readLog(allocator);
    defer allocator.free(log_content);

    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "append-test first message"));
    try testing.expect(std.mem.containsAtLeast(u8, log_content, 1, "append-test second message"));
}
