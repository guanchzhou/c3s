/// Shared age calculation utility for resource views.
/// Parses ISO 8601 timestamps and returns human-readable age strings (e.g. "5d", "3h", "12m").
const std = @import("std");
const epoch = std.time.epoch;

/// Calculate age string from an ISO 8601 timestamp (e.g. "2024-01-15T10:30:00Z").
/// Returns an allocated string like "5d", "3h", "12m", "45s", or "n/a" on failure.
/// Caller owns the returned memory.
pub fn calculateAge(allocator: std.mem.Allocator, timestamp: ?[]const u8) ![]const u8 {
    const ts = timestamp orelse return try allocator.dupe(u8, "n/a");
    if (ts.len < 19) return try allocator.dupe(u8, "n/a");

    const year_i32 = std.fmt.parseInt(i32, ts[0..4], 10) catch return try allocator.dupe(u8, "n/a");
    const month_u8 = std.fmt.parseInt(u8, ts[5..7], 10) catch return try allocator.dupe(u8, "n/a");
    const day = std.fmt.parseInt(u8, ts[8..10], 10) catch return try allocator.dupe(u8, "n/a");
    const hour = std.fmt.parseInt(u8, ts[11..13], 10) catch return try allocator.dupe(u8, "n/a");
    const minute = std.fmt.parseInt(u8, ts[14..16], 10) catch return try allocator.dupe(u8, "n/a");
    const second = std.fmt.parseInt(u8, ts[17..19], 10) catch return try allocator.dupe(u8, "n/a");

    // Validate ranges
    if (year_i32 < 1970 or month_u8 < 1 or month_u8 > 12 or day < 1 or day > 31)
        return try allocator.dupe(u8, "n/a");
    if (hour > 23 or minute > 59 or second > 59)
        return try allocator.dupe(u8, "n/a");

    const year: epoch.Year = @intCast(year_i32);

    // Calculate days from epoch (1970-01-01) to the given date
    var total_days: u64 = 0;

    // Add days for complete years from 1970 to year-1
    var y: epoch.Year = epoch.epoch_year;
    while (y < year) : (y += 1) {
        total_days += epoch.getDaysInYear(y);
    }

    // Add days for complete months in the target year
    const month: epoch.Month = @enumFromInt(month_u8);
    var m: u8 = 1;
    while (m < month_u8) : (m += 1) {
        total_days += epoch.getDaysInMonth(year, @enumFromInt(m));
    }

    // Add remaining days (day is 1-based, so subtract 1)
    _ = month;
    total_days += day - 1;

    const created_sec: i64 = @intCast(total_days * 86400 + @as(u64, hour) * 3600 + @as(u64, minute) * 60 + @as(u64, second));
    const now_sec = std.time.timestamp();
    const diff = now_sec - created_sec;

    if (diff < 0) return try allocator.dupe(u8, "0s");

    const udiff: u64 = @intCast(diff);
    if (udiff < 60) {
        return try std.fmt.allocPrint(allocator, "{d}s", .{udiff});
    } else if (udiff < 3600) {
        return try std.fmt.allocPrint(allocator, "{d}m", .{udiff / 60});
    } else if (udiff < 86400) {
        return try std.fmt.allocPrint(allocator, "{d}h", .{udiff / 3600});
    } else {
        return try std.fmt.allocPrint(allocator, "{d}d", .{udiff / 86400});
    }
}
