//! Process-wide runtime singletons for Zig 0.16's `std.Io` model.
//!
//! Zig 0.16 routes file, subprocess, and socket I/O through a `std.Io`
//! instance that must outlive every operation that uses it. c3s resolves one
//! `std.Io` here so leaf modules (logger, xdg, config, theme loader, k8s
//! service) can reach it without threading an `io` parameter through every
//! call site — mirroring the existing global-logger pattern.
//!
//! `main()` calls `set()` with the runtime-provided io (thread pool + leak
//! checking in debug). Contexts that never run `main()` — unit tests, headless
//! tooling — get a lazily created fallback `Threaded` on first `io()` use, so
//! code paths that do file I/O work without explicit setup.
//!
//! Hot/crash paths (terminal render output, panic hook) deliberately bypass
//! this and write to file descriptors via libc (see `sys.zig`), so they
//! neither depend on `io` being initialized nor touch the thread pool.
const std = @import("std");

var current: ?std.Io = null;
var fallback: std.Io.Threaded = undefined;
var fallback_initialized = false;

/// Publish the process io. Called once from `main()` before logging/app init.
pub fn set(io_impl: std.Io) void {
    current = io_impl;
}

/// The process io. Lazily initializes a fallback thread-pool io if `set()` was
/// never called (e.g. in unit tests). The fallback uses a process-lifetime
/// allocator and is intentionally never deinitialized.
pub fn io() std.Io {
    if (current) |c| return c;
    if (!fallback_initialized) {
        fallback = std.Io.Threaded.init(std.heap.smp_allocator, .{});
        fallback_initialized = true;
        current = fallback.io();
    }
    return current.?;
}
