const std = @import("std");
const testing = std.testing;
const table_layout = @import("c3s").ui.table_layout;

test "calculateMaxColumnWidths - basic" {
    const allocator = testing.allocator;

    const headers = [_][]const u8{ "NAME", "STATUS", "AGE" };
    const rows = [_][]const []const u8{
        &[_][]const u8{ "pod-1", "Running", "2d" },
        &[_][]const u8{ "very-long-pod-name", "Pending", "5m" },
        &[_][]const u8{ "pod-3", "Running", "1h" },
    };

    const max_widths = try table_layout.calculateMaxColumnWidths(
        allocator,
        &headers,
        &rows,
    );
    defer allocator.free(max_widths);

    try testing.expectEqual(@as(usize, 3), max_widths.len);
    try testing.expectEqual(@as(u16, 20), max_widths[0]); // "very-long-pod-name" + 2
    try testing.expectEqual(@as(u16, 9), max_widths[1]); // "Running" + 2
    try testing.expectEqual(@as(u16, 5), max_widths[2]); // "AGE" + 2
}

test "calculateColumnWidths - all columns fit" {
    const allocator = testing.allocator;

    const headers = [_][]const u8{ "NAME", "STATUS" };
    const rows = [_][]const []const u8{
        &[_][]const u8{ "pod-1", "Running" },
    };

    const columns = [_]table_layout.ColumnInfo{
        .{ .name = "NAME", .min_width = 10, .priority = 0 },
        .{ .name = "STATUS", .min_width = 8, .priority = 50 },
    };

    var widths = try table_layout.calculateColumnWidths(
        allocator,
        &headers,
        &rows,
        &columns,
        100, // plenty of space
    );
    defer widths.deinit();

    try testing.expectEqual(@as(usize, 2), widths.widths.len);
    try testing.expect(widths.widths[0] > 0); // NAME visible
    try testing.expect(widths.widths[1] > 0); // STATUS visible
    try testing.expectEqual(@as(usize, 2), widths.visible_count);
}

test "calculateColumnWidths - progressive hiding by priority" {
    const allocator = testing.allocator;

    const headers = [_][]const u8{ "NAME", "READY", "STATUS", "RESTARTS", "AGE" };
    const rows = [_][]const []const u8{
        &[_][]const u8{ "pod-1", "1/1", "Running", "0", "2d" },
    };

    const columns = [_]table_layout.ColumnInfo{
        .{ .name = "NAME", .min_width = 8, .priority = table_layout.ColumnPriority.CRITICAL },
        .{ .name = "READY", .min_width = 5, .priority = table_layout.ColumnPriority.HIGH },
        .{ .name = "STATUS", .min_width = 8, .priority = table_layout.ColumnPriority.HIGH },
        .{ .name = "RESTARTS", .min_width = 8, .priority = table_layout.ColumnPriority.LOW },
        .{ .name = "AGE", .min_width = 5, .priority = table_layout.ColumnPriority.VERY_LOW },
    };

    // Test with narrow width - should hide lowest priority columns
    var widths = try table_layout.calculateColumnWidths(
        allocator,
        &headers,
        &rows,
        &columns,
        30, // narrow terminal
    );
    defer widths.deinit();

    // NAME (CRITICAL) should always be visible
    try testing.expect(widths.widths[0] > 0);

    // AGE (VERY_LOW) should be hidden first
    try testing.expectEqual(@as(u16, 0), widths.widths[4]);
}

test "TableScroll - scroll left/right" {
    var scroll = table_layout.TableScroll{
        .scroll_offset = 0,
        .visible_width = 50,
        .total_width = 150,
    };

    try testing.expect(scroll.canScrollRight());
    try testing.expect(!scroll.canScrollLeft());

    scroll.scrollRight(30);
    try testing.expectEqual(@as(u16, 30), scroll.scroll_offset);
    try testing.expect(scroll.canScrollLeft());
    try testing.expect(scroll.canScrollRight());

    scroll.scrollLeft(10);
    try testing.expectEqual(@as(u16, 20), scroll.scroll_offset);

    scroll.scrollToEnd();
    try testing.expectEqual(@as(u16, 100), scroll.scroll_offset); // 150 - 50
    try testing.expect(!scroll.canScrollRight());
    try testing.expect(scroll.canScrollLeft());

    scroll.scrollToStart();
    try testing.expectEqual(@as(u16, 0), scroll.scroll_offset);
}

test "TableScroll - visible range" {
    const scroll = table_layout.TableScroll{
        .scroll_offset = 20,
        .visible_width = 50,
        .total_width = 150,
    };

    const range = scroll.getVisibleRange();
    try testing.expectEqual(@as(u16, 20), range.start);
    try testing.expectEqual(@as(u16, 70), range.end);
}

test "truncateText - basic truncation" {
    const allocator = testing.allocator;

    const text = "very-long-pod-name-here";
    const truncated = try table_layout.truncateText(allocator, text, 10, true);
    defer allocator.free(truncated);

    try testing.expectEqualStrings("very-lo...", truncated);
}

test "truncateText - no truncation needed" {
    const allocator = testing.allocator;

    const text = "short";
    const result = try table_layout.truncateText(allocator, text, 10, true);
    defer allocator.free(result);

    try testing.expectEqualStrings("short", result);
}

test "padText - left aligned" {
    const allocator = testing.allocator;

    const text = "pod";
    const padded = try table_layout.padText(allocator, text, 10, false);
    defer allocator.free(padded);

    try testing.expectEqualStrings("pod       ", padded);
}

test "padText - right aligned" {
    const allocator = testing.allocator;

    const text = "123";
    const padded = try table_layout.padText(allocator, text, 10, true);
    defer allocator.free(padded);

    try testing.expectEqualStrings("       123", padded);
}

test "ColumnPriority constants" {
    try testing.expectEqual(@as(u8, 0), table_layout.ColumnPriority.CRITICAL);
    try testing.expectEqual(@as(u8, 25), table_layout.ColumnPriority.HIGH);
    try testing.expectEqual(@as(u8, 50), table_layout.ColumnPriority.MEDIUM);
    try testing.expectEqual(@as(u8, 100), table_layout.ColumnPriority.LOW);
    try testing.expectEqual(@as(u8, 200), table_layout.ColumnPriority.VERY_LOW);
}
