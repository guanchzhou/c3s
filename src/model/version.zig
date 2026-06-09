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

const testing = std.testing;

test "version.string returns formatted version without build suffix when build_number is 0" {
    // The version module should return base_version when build_number is "0" or empty
    const ver = string();

    // Should start with "v0." and be in format v0.YYYY.MM.DD.HH.MM
    try testing.expect(std.mem.startsWith(u8, ver, "v0."));

    // Should NOT contain "+0" suffix
    try testing.expect(!std.mem.containsAtLeast(u8, ver, 1, "+0"));
}

test "version.string returns cached value on repeated calls" {
    const ver1 = string();
    const ver2 = string();

    // Both should point to the same memory
    try testing.expectEqual(ver1.ptr, ver2.ptr);
    try testing.expectEqual(ver1.len, ver2.len);
}

test "version.ownedString allocates new copy" {
    const allocator = testing.allocator;

    const ver1 = try ownedString(allocator);
    defer allocator.free(ver1);

    const ver2 = try ownedString(allocator);
    defer allocator.free(ver2);

    // Content should be equal
    try testing.expectEqualStrings(ver1, ver2);

    // But pointers should be different (different allocations)
    try testing.expect(ver1.ptr != ver2.ptr);
}

test "version format matches expected pattern" {
    const ver = string();

    // Should be in format: v0.YYYY.MM.DD.HH.MM
    // Minimum length: v0.2025.01.01.00.00 = 19 chars
    try testing.expect(ver.len >= 19);

    // Check for valid separators
    var dot_count: usize = 0;
    for (ver) |c| {
        if (c == '.') dot_count += 1;
    }

    // Should have at least 5 dots (v0.YYYY.MM.DD.HH.MM)
    try testing.expect(dot_count >= 5);
}
