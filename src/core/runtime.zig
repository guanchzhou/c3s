//! Process-wide runtime singletons for Zig 0.16's `std.Io` model.
//!
//! Zig 0.16 routes file, subprocess, and socket I/O through a `std.Io`
//! instance that must outlive every operation that uses it. c3s owns a single
//! `std.Io.Threaded` in `main()` and publishes its `io` here so leaf modules
//! (logger, xdg, config, theme loader, k8s service) can reach it without
//! threading an `io` parameter through every call site — mirroring the
//! existing global-logger pattern.
//!
//! Hot/crash paths (terminal render output, panic hook) deliberately bypass
//! this and write to file descriptors via `std.posix.write`, so they neither
//! depend on `io` being initialized nor touch the thread pool.
const std = @import("std");

/// Assigned exactly once in `main()` before any logging or I/O is performed.
/// Reading this before it is set is a programming error.
pub var io: std.Io = undefined;
