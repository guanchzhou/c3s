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
