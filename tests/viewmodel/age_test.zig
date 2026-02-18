const std = @import("std");
const testing = std.testing;
const age_util = @import("../src/viewmodel/age.zig");

// =============================================================================
// parseTimestampToEpoch tests
// =============================================================================

test "parseTimestampToEpoch: valid timestamp returns epoch seconds" {
    // 2024-01-01T00:00:00Z = known epoch value
    const result = age_util.parseTimestampToEpoch("2024-01-01T00:00:00Z");
    try testing.expect(result != null);
    // 2024-01-01 is 19723 days after 1970-01-01 = 1704067200
    try testing.expectEqual(@as(i64, 1704067200), result.?);
}

test "parseTimestampToEpoch: epoch start returns 0" {
    const result = age_util.parseTimestampToEpoch("1970-01-01T00:00:00Z");
    try testing.expect(result != null);
    try testing.expectEqual(@as(i64, 0), result.?);
}

test "parseTimestampToEpoch: with time components" {
    // 1970-01-01T01:00:00Z = 3600
    const result = age_util.parseTimestampToEpoch("1970-01-01T01:00:00Z");
    try testing.expect(result != null);
    try testing.expectEqual(@as(i64, 3600), result.?);
}

test "parseTimestampToEpoch: null input returns null" {
    const result = age_util.parseTimestampToEpoch(null);
    try testing.expect(result == null);
}

test "parseTimestampToEpoch: too short string returns null" {
    const result = age_util.parseTimestampToEpoch("2024-01");
    try testing.expect(result == null);
}

test "parseTimestampToEpoch: invalid year returns null" {
    const result = age_util.parseTimestampToEpoch("1969-01-01T00:00:00Z");
    try testing.expect(result == null);
}

test "parseTimestampToEpoch: invalid month returns null" {
    const result = age_util.parseTimestampToEpoch("2024-13-01T00:00:00Z");
    try testing.expect(result == null);
}

test "parseTimestampToEpoch: month zero returns null" {
    const result = age_util.parseTimestampToEpoch("2024-00-01T00:00:00Z");
    try testing.expect(result == null);
}

test "parseTimestampToEpoch: invalid hour returns null" {
    const result = age_util.parseTimestampToEpoch("2024-01-01T24:00:00Z");
    try testing.expect(result == null);
}

test "parseTimestampToEpoch: non-numeric input returns null" {
    const result = age_util.parseTimestampToEpoch("XXXX-XX-XXTXX:XX:XXZ");
    try testing.expect(result == null);
}

// =============================================================================
// formatDuration tests
// =============================================================================

test "formatDuration: seconds (< 60)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try age_util.formatDuration(a, 45);
    defer a.free(result);
    try testing.expectEqualStrings("45s", result);
}

test "formatDuration: zero seconds" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try age_util.formatDuration(a, 0);
    defer a.free(result);
    try testing.expectEqualStrings("0s", result);
}

test "formatDuration: minutes (60-3599)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try age_util.formatDuration(a, 300);
    defer a.free(result);
    try testing.expectEqualStrings("5m", result);
}

test "formatDuration: exactly 60 seconds is 1m" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try age_util.formatDuration(a, 60);
    defer a.free(result);
    try testing.expectEqualStrings("1m", result);
}

test "formatDuration: hours (3600-86399)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try age_util.formatDuration(a, 7200);
    defer a.free(result);
    try testing.expectEqualStrings("2h", result);
}

test "formatDuration: days (>= 86400)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try age_util.formatDuration(a, 432000);
    defer a.free(result);
    try testing.expectEqualStrings("5d", result);
}

test "formatDuration: exactly 1 day" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try age_util.formatDuration(a, 86400);
    defer a.free(result);
    try testing.expectEqualStrings("1d", result);
}

// =============================================================================
// calculateAge tests
// =============================================================================

test "calculateAge: null timestamp returns n/a" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try age_util.calculateAge(a, null);
    defer a.free(result);
    try testing.expectEqualStrings("n/a", result);
}

test "calculateAge: invalid timestamp returns n/a" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try age_util.calculateAge(a, "not-a-timestamp");
    defer a.free(result);
    try testing.expectEqualStrings("n/a", result);
}

test "calculateAge: valid old timestamp returns days" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    // Use a very old timestamp to ensure we get days
    const result = try age_util.calculateAge(a, "2020-01-01T00:00:00Z");
    defer a.free(result);
    // Should end with 'd' for days
    try testing.expect(result.len > 0);
    try testing.expectEqual(@as(u8, 'd'), result[result.len - 1]);
}

test "calculateAge: no memory leaks across multiple calls" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("Memory leak in calculateAge test");
    }
    const a = gpa.allocator();

    for (0..100) |_| {
        const result = try age_util.calculateAge(a, "2024-06-15T12:00:00Z");
        a.free(result);
    }

    for (0..100) |_| {
        const result = try age_util.calculateAge(a, null);
        a.free(result);
    }
}
