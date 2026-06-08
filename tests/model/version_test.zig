const std = @import("std");
const testing = std.testing;
const version = @import("src").version;

test "version.string returns formatted version without build suffix when build_number is 0" {
    // The version module should return base_version when build_number is "0" or empty
    const ver = version.string();
    
    // Should start with "v0." and be in format v0.YYYY.MM.DD.HH.MM
    try testing.expect(std.mem.startsWith(u8, ver, "v0."));
    
    // Should NOT contain "+0" suffix
    try testing.expect(!std.mem.containsAtLeast(u8, ver, 1, "+0"));
}

test "version.string returns cached value on repeated calls" {
    const ver1 = version.string();
    const ver2 = version.string();
    
    // Both should point to the same memory
    try testing.expectEqual(ver1.ptr, ver2.ptr);
    try testing.expectEqual(ver1.len, ver2.len);
}

test "version.ownedString allocates new copy" {
    const allocator = testing.allocator;
    
    const ver1 = try version.ownedString(allocator);
    defer allocator.free(ver1);
    
    const ver2 = try version.ownedString(allocator);
    defer allocator.free(ver2);
    
    // Content should be equal
    try testing.expectEqualStrings(ver1, ver2);
    
    // But pointers should be different (different allocations)
    try testing.expect(ver1.ptr != ver2.ptr);
}

test "version format matches expected pattern" {
    const ver = version.string();
    
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
