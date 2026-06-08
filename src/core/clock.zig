//! Wall-clock helpers.
//!
//! Zig 0.16 removed `std.time.timestamp` / `milliTimestamp` / `nanoTimestamp`
//! (time now flows through `std.Io`). c3s links libc, so these drop-in
//! replacements read the wall clock via `clock_gettime` without requiring a
//! `std.Io` at every call site (logging, age columns, frame timing).
const std = @import("std");

fn realtime() std.c.timespec {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.REALTIME, &ts);
    return ts;
}

/// Seconds since the Unix epoch.
pub fn timestamp() i64 {
    return @intCast(realtime().sec);
}

/// Milliseconds since the Unix epoch.
pub fn milliTimestamp() i64 {
    const ts = realtime();
    return @as(i64, @intCast(ts.sec)) * 1000 + @divFloor(@as(i64, @intCast(ts.nsec)), 1_000_000);
}

/// Nanoseconds since the Unix epoch.
pub fn nanoTimestamp() i128 {
    const ts = realtime();
    return @as(i128, @intCast(ts.sec)) * 1_000_000_000 + @as(i128, @intCast(ts.nsec));
}
