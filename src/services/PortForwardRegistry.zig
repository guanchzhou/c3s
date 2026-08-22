// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Registry of `kubectl port-forward` children c3s has spawned.
//
// This exists because port-forwards used to be fire-and-forget: App kept a bare
// `ArrayListUnmanaged(std.process.Child)` that only got touched again at exit, so a
// forward could not be listed or stopped, and a forward whose pod went away lingered
// in the list forever with nothing saying so.
//
// Reaping is done here rather than through `std.process.Child.wait`, which blocks.
// `std.posix.waitpid` no longer exists in Zig 0.16, so `poll()` calls
// `std.c.waitpid` with WNOHANG directly. Consequence: this registry owns the child's
// lifecycle end to end and must never call `child.wait()` -- once we have reaped a
// pid, a later wait would fail with ECHILD. `stop()` therefore does its own blocking
// waitpid after the kill.
const std = @import("std");
const builtin = @import("builtin");
const runtime = @import("../core/runtime.zig");
const Logger = @import("../core/logger.zig");

/// One active (or recently dead) forward.
pub const Entry = struct {
    /// e.g. "pods/nginx-abc" -- the kubectl target, as typed into the argv.
    target: []const u8,
    /// e.g. "8080:80" -- exactly the mapping the user entered.
    ports: []const u8,
    namespace: []const u8,
    child: std.process.Child,
    /// Set by `poll()` once the child has exited and been reaped. A dead forward is
    /// kept in the list rather than dropped: silently vanishing rows would leave the
    /// user wondering whether the forward ever started.
    dead: bool = false,
    /// Exit status, once known. Null while running.
    exit_code: ?u8 = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Entry) void {
        self.allocator.free(self.target);
        self.allocator.free(self.ports);
        self.allocator.free(self.namespace);
    }

    /// What to show in a STATUS column. Only ever reports what has actually been
    /// observed via waitpid -- never a guess.
    pub fn status(self: *const Entry) []const u8 {
        if (!self.dead) return "Running";
        if (self.exit_code) |code| return if (code == 0) "Exited" else "Failed";
        return "Stopped";
    }

    pub fn pid(self: *const Entry) i64 {
        return if (self.child.id) |id| @intCast(id) else -1;
    }
};

pub const PortForwardRegistry = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .empty,

    pub fn init(allocator: std.mem.Allocator) PortForwardRegistry {
        return .{ .allocator = allocator };
    }

    /// Kill and reap everything still running, then free.
    pub fn deinit(self: *PortForwardRegistry) void {
        for (self.entries.items) |*e| {
            if (!e.dead) killAndReap(e);
            e.deinit();
        }
        self.entries.deinit(self.allocator);
    }

    /// Take ownership of a spawned child. The three strings are copied, so callers may
    /// pass borrowed slices (the App prompt buffer, a table row) without ceremony.
    pub fn add(
        self: *PortForwardRegistry,
        target: []const u8,
        ports: []const u8,
        namespace: []const u8,
        child: std.process.Child,
    ) !void {
        const t = try self.allocator.dupe(u8, target);
        errdefer self.allocator.free(t);
        const p = try self.allocator.dupe(u8, ports);
        errdefer self.allocator.free(p);
        const n = try self.allocator.dupe(u8, namespace);
        errdefer self.allocator.free(n);

        try self.entries.append(self.allocator, .{
            .target = t,
            .ports = p,
            .namespace = n,
            .child = child,
            .allocator = self.allocator,
        });
    }

    pub fn count(self: *const PortForwardRegistry) usize {
        return self.entries.items.len;
    }

    /// Number still believed to be running. Only meaningful right after `poll()`.
    pub fn liveCount(self: *const PortForwardRegistry) usize {
        var n: usize = 0;
        for (self.entries.items) |e| {
            if (!e.dead) n += 1;
        }
        return n;
    }

    /// Non-blocking reap. Marks any child that has exited as dead and records its
    /// status. Safe to call every refresh; costs one waitpid per live entry.
    pub fn poll(self: *PortForwardRegistry) void {
        if (builtin.os.tag == .windows) return;
        for (self.entries.items) |*e| {
            if (e.dead) continue;
            const id = e.child.id orelse {
                // No pid to wait on: it never really started. Do not claim it is
                // running.
                e.dead = true;
                continue;
            };
            var wstatus: c_int = 0;
            const r = std.c.waitpid(@intCast(id), &wstatus, @intCast(std.c.W.NOHANG));
            if (r == 0) continue; // still running
            if (r < 0) {
                // ECHILD and friends: we cannot learn anything more about this pid,
                // so stop claiming it is alive.
                e.dead = true;
                continue;
            }
            e.dead = true;
            e.exit_code = decodeExitCode(wstatus);
        }
    }

    /// Stop the forward at `index`, then drop it from the list.
    ///
    /// Removing rather than keeping it as "Stopped" is deliberate: the user asked for
    /// it to go away, so leaving a row behind would invite pressing stop twice.
    pub fn stop(self: *PortForwardRegistry, index: usize) !void {
        if (index >= self.entries.items.len) return error.NoSuchPortForward;
        var e = self.entries.orderedRemove(index);
        if (!e.dead) killAndReap(&e);
        e.deinit();
    }

    /// Kill the child, leaving no zombie behind.
    ///
    /// `std.process.Child.kill` already reaps -- it asserts `child.id == null` on
    /// return -- so there is deliberately no waitpid here. An earlier version added
    /// one "to be safe"; it was unreachable, which a mutation test caught by surviving
    /// its removal.
    ///
    /// Only ever called on an entry with `dead == false`. That matters: `poll()` reaps
    /// through `std.c.waitpid` behind Child's back, so calling kill on an
    /// already-polled entry would mean killing a pid we no longer own.
    fn killAndReap(e: *Entry) void {
        std.debug.assert(!e.dead);
        e.child.kill(runtime.io());
        e.dead = true;
    }
};

/// Extract the exit code from a raw wait status. Signal deaths report the signal
/// number, which is enough to render "Failed" and is what kubectl-killed forwards look
/// like.
fn decodeExitCode(wstatus: c_int) u8 {
    const s: u32 = @bitCast(wstatus);
    if ((s & 0x7f) == 0) return @truncate((s >> 8) & 0xff); // exited normally
    return @truncate(s & 0x7f); // died on a signal
}

// ===========================================================================
// Tests -- these spawn real short-lived processes rather than kubectl, so they
// exercise the actual reap path without needing a cluster.
// ===========================================================================

test "poll reaps an exited child and reports its code, instead of claiming Running" {
    // The bug this guards: without a reap, an exited `kubectl port-forward` becomes a
    // zombie that still answers kill(pid, 0), so any liveness check built on signal
    // probing would keep reporting the dead forward as Running forever.
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = std.testing.allocator;

    var reg = PortForwardRegistry.init(a);
    defer reg.deinit();

    const child = try std.process.spawn(runtime.io(), .{
        .argv = &.{ "/bin/sh", "-c", "exit 3" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    try reg.add("pods/nginx", "8080:80", "default", child);

    try std.testing.expectEqual(@as(usize, 1), reg.count());
    try std.testing.expectEqualStrings("Running", reg.entries.items[0].status());

    // The child needs a moment to exit; poll until it is reaped rather than sleeping a
    // fixed amount, so the test is not racy on a loaded machine.
    var attempts: usize = 0;
    while (reg.liveCount() > 0 and attempts < 200) : (attempts += 1) {
        reg.poll();
        if (reg.liveCount() == 0) break;
        runtime.io().sleep(.{ .nanoseconds = 10 * std.time.ns_per_ms }, .awake) catch {};
    }

    try std.testing.expectEqual(@as(usize, 0), reg.liveCount());
    try std.testing.expect(reg.entries.items[0].dead);
    try std.testing.expectEqual(@as(?u8, 3), reg.entries.items[0].exit_code);
    try std.testing.expectEqualStrings("Failed", reg.entries.items[0].status());
    // A dead forward stays listed -- vanishing rows would be worse than a stale one.
    try std.testing.expectEqual(@as(usize, 1), reg.count());
}

test "poll is idempotent and does not re-wait a pid it already reaped" {
    // Calling poll() on every refresh must not turn into a waitpid on a reaped pid,
    // which would return -1/ECHILD and could clobber the recorded exit code.
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = std.testing.allocator;

    var reg = PortForwardRegistry.init(a);
    defer reg.deinit();

    const child = try std.process.spawn(runtime.io(), .{
        .argv = &.{ "/bin/sh", "-c", "exit 0" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    try reg.add("svc/api", "9090:9090", "prod", child);

    var attempts: usize = 0;
    while (reg.liveCount() > 0 and attempts < 200) : (attempts += 1) {
        reg.poll();
        if (reg.liveCount() == 0) break;
        runtime.io().sleep(.{ .nanoseconds = 10 * std.time.ns_per_ms }, .awake) catch {};
    }
    try std.testing.expectEqual(@as(?u8, 0), reg.entries.items[0].exit_code);
    try std.testing.expectEqualStrings("Exited", reg.entries.items[0].status());

    // Many more polls must not change what we learned.
    for (0..5) |_| reg.poll();
    try std.testing.expectEqual(@as(?u8, 0), reg.entries.items[0].exit_code);
    try std.testing.expectEqualStrings("Exited", reg.entries.items[0].status());
}

test "stop kills a running forward, removes the row, and leaves no zombie" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = std.testing.allocator;

    var reg = PortForwardRegistry.init(a);
    defer reg.deinit();

    // Long-lived, like a real port-forward: it must be killed, not waited out.
    const child = try std.process.spawn(runtime.io(), .{
        .argv = &.{ "/bin/sh", "-c", "sleep 300" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    try reg.add("pods/db", "5432:5432", "default", child);
    const pid = reg.entries.items[0].pid();
    try std.testing.expect(pid > 0);

    try reg.stop(0);
    try std.testing.expectEqual(@as(usize, 0), reg.count());

    // If stop() had killed without reaping, the pid would survive as a zombie and
    // still answer signal 0. A reaped pid does not.
    std.posix.kill(@intCast(pid), .CHLD) catch |err| {
        try std.testing.expectEqual(error.ProcessNotFound, err);
        return;
    };
    return error.PidStillExistsAfterStop;
}

test "stop rejects an out-of-range index rather than corrupting the list" {
    const a = std.testing.allocator;
    var reg = PortForwardRegistry.init(a);
    defer reg.deinit();

    try std.testing.expectError(error.NoSuchPortForward, reg.stop(0));
    try std.testing.expectError(error.NoSuchPortForward, reg.stop(99));
}

test "add copies its strings, so callers may pass borrowed buffers" {
    // App builds the target with allocPrint and frees it immediately; if add() only
    // stored the slice, every row would be reading freed memory.
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = std.testing.allocator;

    var reg = PortForwardRegistry.init(a);
    defer reg.deinit();

    var scratch: [64]u8 = undefined;
    const target = try std.fmt.bufPrint(&scratch, "pods/{s}", .{"ephemeral"});

    const child = try std.process.spawn(runtime.io(), .{
        .argv = &.{ "/bin/sh", "-c", "sleep 300" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    try reg.add(target, "1:1", "ns", child);

    @memset(&scratch, 0xaa); // poison the caller's buffer
    try std.testing.expectEqualStrings("pods/ephemeral", reg.entries.items[0].target);
}
