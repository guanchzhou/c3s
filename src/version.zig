const std = @import("std");
const build = @import("c3s_build");

var cached_slice: []const u8 = &[_]u8{};
var initialized: bool = false;
var buffer: [128]u8 = undefined;

fn ensure() []const u8 {
    if (initialized) return cached_slice;

    if (build.build_number.len == 0 or std.mem.eql(u8, build.build_number, "0")) {
        const len = build.base_version.len;
        std.mem.copyForwards(u8, buffer[0..len], build.base_version);
        cached_slice = buffer[0..len];
    } else {
        const slice = std.fmt.bufPrint(&buffer, "{s}+{s}", .{ build.base_version, build.build_number }) catch {
            const len = build.base_version.len;
            std.mem.copyForwards(u8, buffer[0..len], build.base_version);
            cached_slice = buffer[0..len];
            initialized = true;
            return cached_slice;
        };
        cached_slice = slice;
    }

    initialized = true;
    return cached_slice;
}

pub fn string() []const u8 {
    return ensure();
}

pub fn ownedString(allocator: std.mem.Allocator) ![]const u8 {
    return allocator.dupe(u8, ensure());
}
