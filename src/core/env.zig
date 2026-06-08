//! Environment variable helpers.
//!
//! Zig 0.16 removed `std.process.getEnvVarOwned` (env access moved behind
//! `std.process.Init` / `std.Io`). c3s links libc, so this provides the same
//! owned-string contract via `getenv` for the handful of leaf call sites
//! (XDG paths, TERM, C3S_FORCE_PROXY) without threading an env map around.
const std = @import("std");

pub const GetError = error{ EnvironmentVariableNotFound, OutOfMemory };

/// Returns a freshly allocated copy of the environment variable `name`, or
/// `error.EnvironmentVariableNotFound` if unset. Caller owns the result.
pub fn getOwned(allocator: std.mem.Allocator, name: [:0]const u8) GetError![]u8 {
    const value = std.c.getenv(name.ptr) orelse return error.EnvironmentVariableNotFound;
    return allocator.dupe(u8, std.mem.span(value));
}
