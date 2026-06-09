/// Shared age calculation utility for resource views.
/// Parses ISO 8601 timestamps and returns human-readable age strings (e.g. "5d", "3h", "12m").
const std = @import("std");
const epoch = std.time.epoch;
const clock = @import("../core/clock.zig");

/// Parse an ISO 8601 timestamp (e.g. "2024-01-15T10:30:00Z") into epoch seconds.
/// Returns null if the timestamp is null, too short, or contains invalid values.
pub fn parseTimestampToEpoch(timestamp: ?[]const u8) ?i64 {
    const ts = timestamp orelse return null;
    if (ts.len < 19) return null;

    const year_i32 = std.fmt.parseInt(i32, ts[0..4], 10) catch return null;
    const month_u8 = std.fmt.parseInt(u8, ts[5..7], 10) catch return null;
    const day = std.fmt.parseInt(u8, ts[8..10], 10) catch return null;
    const hour = std.fmt.parseInt(u8, ts[11..13], 10) catch return null;
    const minute = std.fmt.parseInt(u8, ts[14..16], 10) catch return null;
    const second = std.fmt.parseInt(u8, ts[17..19], 10) catch return null;

    // Validate ranges
    if (year_i32 < 1970 or month_u8 < 1 or month_u8 > 12 or day < 1 or day > 31)
        return null;
    if (hour > 23 or minute > 59 or second > 59)
        return null;

    const year: epoch.Year = @intCast(year_i32);

    // Calculate days from epoch (1970-01-01) to the given date
    var total_days: u64 = 0;

    // Add days for complete years from 1970 to year-1
    var y: epoch.Year = epoch.epoch_year;
    while (y < year) : (y += 1) {
        total_days += epoch.getDaysInYear(y);
    }

    // Add days for complete months in the target year
    var m: u8 = 1;
    while (m < month_u8) : (m += 1) {
        total_days += epoch.getDaysInMonth(year, @enumFromInt(m));
    }

    // Add remaining days (day is 1-based, so subtract 1)
    total_days += day - 1;

    return @intCast(total_days * 86400 + @as(u64, hour) * 3600 + @as(u64, minute) * 60 + @as(u64, second));
}

/// Format a duration in seconds as a human-readable string (e.g. "5d", "3h", "12m", "45s").
/// Caller owns the returned memory.
pub fn formatDuration(allocator: std.mem.Allocator, seconds: u64) ![]const u8 {
    if (seconds < 60) {
        return try std.fmt.allocPrint(allocator, "{d}s", .{seconds});
    } else if (seconds < 3600) {
        return try std.fmt.allocPrint(allocator, "{d}m", .{seconds / 60});
    } else if (seconds < 86400) {
        return try std.fmt.allocPrint(allocator, "{d}h", .{seconds / 3600});
    } else {
        return try std.fmt.allocPrint(allocator, "{d}d", .{seconds / 86400});
    }
}

/// Calculate age string from an ISO 8601 timestamp (e.g. "2024-01-15T10:30:00Z").
/// Returns an allocated string like "5d", "3h", "12m", "45s", or "n/a" on failure.
/// Caller owns the returned memory.
pub fn calculateAge(allocator: std.mem.Allocator, timestamp: ?[]const u8) ![]const u8 {
    const created_sec = parseTimestampToEpoch(timestamp) orelse return try allocator.dupe(u8, "n/a");
    const now_sec = clock.timestamp();
    const diff = now_sec - created_sec;

    if (diff < 0) return try allocator.dupe(u8, "0s");

    return try formatDuration(allocator, @intCast(diff));
}

// =============================================================================
// parseTimestampToEpoch tests
// =============================================================================

test "parseTimestampToEpoch: valid timestamp returns epoch seconds" {
    // 2024-01-01T00:00:00Z = known epoch value
    const result = parseTimestampToEpoch("2024-01-01T00:00:00Z");
    try std.testing.expect(result != null);
    // 2024-01-01 is 19723 days after 1970-01-01 = 1704067200
    try std.testing.expectEqual(@as(i64, 1704067200), result.?);
}

test "parseTimestampToEpoch: epoch start returns 0" {
    const result = parseTimestampToEpoch("1970-01-01T00:00:00Z");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 0), result.?);
}

test "parseTimestampToEpoch: with time components" {
    // 1970-01-01T01:00:00Z = 3600
    const result = parseTimestampToEpoch("1970-01-01T01:00:00Z");
    try std.testing.expect(result != null);
    try std.testing.expectEqual(@as(i64, 3600), result.?);
}

test "parseTimestampToEpoch: null input returns null" {
    const result = parseTimestampToEpoch(null);
    try std.testing.expect(result == null);
}

test "parseTimestampToEpoch: too short string returns null" {
    const result = parseTimestampToEpoch("2024-01");
    try std.testing.expect(result == null);
}

test "parseTimestampToEpoch: invalid year returns null" {
    const result = parseTimestampToEpoch("1969-01-01T00:00:00Z");
    try std.testing.expect(result == null);
}

test "parseTimestampToEpoch: invalid month returns null" {
    const result = parseTimestampToEpoch("2024-13-01T00:00:00Z");
    try std.testing.expect(result == null);
}

test "parseTimestampToEpoch: month zero returns null" {
    const result = parseTimestampToEpoch("2024-00-01T00:00:00Z");
    try std.testing.expect(result == null);
}

test "parseTimestampToEpoch: invalid hour returns null" {
    const result = parseTimestampToEpoch("2024-01-01T24:00:00Z");
    try std.testing.expect(result == null);
}

test "parseTimestampToEpoch: non-numeric input returns null" {
    const result = parseTimestampToEpoch("XXXX-XX-XXTXX:XX:XXZ");
    try std.testing.expect(result == null);
}

// =============================================================================
// formatDuration tests
// =============================================================================

test "formatDuration: seconds (< 60)" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try formatDuration(a, 45);
    defer a.free(result);
    try std.testing.expectEqualStrings("45s", result);
}

test "formatDuration: zero seconds" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try formatDuration(a, 0);
    defer a.free(result);
    try std.testing.expectEqualStrings("0s", result);
}

test "formatDuration: minutes (60-3599)" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try formatDuration(a, 300);
    defer a.free(result);
    try std.testing.expectEqualStrings("5m", result);
}

test "formatDuration: exactly 60 seconds is 1m" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try formatDuration(a, 60);
    defer a.free(result);
    try std.testing.expectEqualStrings("1m", result);
}

test "formatDuration: hours (3600-86399)" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try formatDuration(a, 7200);
    defer a.free(result);
    try std.testing.expectEqualStrings("2h", result);
}

test "formatDuration: days (>= 86400)" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try formatDuration(a, 432000);
    defer a.free(result);
    try std.testing.expectEqualStrings("5d", result);
}

test "formatDuration: exactly 1 day" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try formatDuration(a, 86400);
    defer a.free(result);
    try std.testing.expectEqualStrings("1d", result);
}

// =============================================================================
// calculateAge tests
// =============================================================================

test "calculateAge: null timestamp returns n/a" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try calculateAge(a, null);
    defer a.free(result);
    try std.testing.expectEqualStrings("n/a", result);
}

test "calculateAge: invalid timestamp returns n/a" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    const result = try calculateAge(a, "not-a-timestamp");
    defer a.free(result);
    try std.testing.expectEqualStrings("n/a", result);
}

test "calculateAge: valid old timestamp returns days" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();

    // Use a very old timestamp to ensure we get days
    const result = try calculateAge(a, "2020-01-01T00:00:00Z");
    defer a.free(result);
    // Should end with 'd' for days
    try std.testing.expect(result.len > 0);
    try std.testing.expectEqual(@as(u8, 'd'), result[result.len - 1]);
}

test "calculateAge: no memory leaks across multiple calls" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const check = gpa.deinit();
        if (check == .leak) @panic("Memory leak in calculateAge test");
    }
    const a = gpa.allocator();

    for (0..100) |_| {
        const result = try calculateAge(a, "2024-06-15T12:00:00Z");
        a.free(result);
    }

    for (0..100) |_| {
        const result = try calculateAge(a, null);
        a.free(result);
    }
}
