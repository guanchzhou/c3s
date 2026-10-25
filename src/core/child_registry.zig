//! Helper processes that must not outlive c3s, even when it panics: an orphaned
//! `kubectl proxy` keeps serving the user's credentials on a local port.
//!
//! Lock-free so the panic handler can drain it from any thread without touching
//! the io thread pool.
const std = @import("std");

const capacity = 16;
var slots: [capacity]std.atomic.Value(std.c.pid_t) = @splat(.init(0));

/// Track `pid`. Returns false when every slot is taken; the process is then
/// still cleaned up by its owner on a normal exit, only not on a panic.
pub fn register(pid: std.c.pid_t) bool {
    for (&slots) |*slot| {
        if (slot.cmpxchgStrong(0, pid, .acq_rel, .acquire) == null) return true;
    }
    return false;
}

pub fn unregister(pid: std.c.pid_t) void {
    for (&slots) |*slot| {
        _ = slot.cmpxchgStrong(pid, 0, .acq_rel, .acquire);
    }
}

/// SIGTERM every tracked process. Safe on the panic path.
pub fn terminateAll() void {
    for (&slots) |*slot| {
        const pid = slot.swap(0, .acq_rel);
        if (pid > 0) _ = std.c.kill(pid, .TERM);
    }
}

test "terminateAll stops a registered child and forgets it" {
    const io = std.testing.io;
    var child = try std.process.spawn(io, .{
        .argv = &.{ "/bin/sh", "-c", "sleep 30" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    const pid = child.id.?;
    try std.testing.expect(register(pid));

    terminateAll();
    const term = try child.wait(io);
    try std.testing.expect(term == .signal);
    try std.testing.expectEqual(std.posix.SIG.TERM, term.signal);
    for (&slots) |*slot| try std.testing.expect(slot.load(.acquire) != pid);
}

test "unregister leaves other children tracked" {
    try std.testing.expect(register(4_000_001));
    try std.testing.expect(register(4_000_002));
    unregister(4_000_001);
    var found_other = false;
    for (&slots) |*slot| {
        try std.testing.expect(slot.load(.acquire) != 4_000_001);
        if (slot.load(.acquire) == 4_000_002) found_other = true;
    }
    try std.testing.expect(found_other);
    unregister(4_000_002);
}
