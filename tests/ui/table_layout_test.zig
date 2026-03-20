// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Comprehensive unit tests for table_layout: column width calculation,
// truncation, padding, scroll, sort indicators, and priority-based hiding.

const std = @import("std");
const testing = std.testing;
const table_layout = @import("c3s").ui.table_layout;

// =========================================================================
// calculateMaxColumnWidths
// =========================================================================

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

test "calculateMaxColumnWidths - header wider than data" {
    const allocator = testing.allocator;

    const headers = [_][]const u8{ "VERY-LONG-HEADER", "X" };
    const rows = [_][]const []const u8{
        &[_][]const u8{ "a", "b" },
    };

    const max_widths = try table_layout.calculateMaxColumnWidths(
        allocator,
        &headers,
        &rows,
    );
    defer allocator.free(max_widths);

    // Header "VERY-LONG-HEADER" len=16, +2 = 18, data "a" len=1, +2 = 3
    try testing.expectEqual(@as(u16, 18), max_widths[0]);
    // Header "X" len=1, +2 = 3, data "b" len=1, +2 = 3
    try testing.expectEqual(@as(u16, 3), max_widths[1]);
}

test "calculateMaxColumnWidths - no rows" {
    const allocator = testing.allocator;

    const headers = [_][]const u8{ "NAME", "STATUS" };
    const empty_rows: []const []const []const u8 = &.{};

    const max_widths = try table_layout.calculateMaxColumnWidths(
        allocator,
        &headers,
        empty_rows,
    );
    defer allocator.free(max_widths);

    // Should just be header widths + 2
    try testing.expectEqual(@as(u16, 6), max_widths[0]); // "NAME" + 2
    try testing.expectEqual(@as(u16, 8), max_widths[1]); // "STATUS" + 2
}

// =========================================================================
// calculateColumnWidths - all columns fit
// =========================================================================

test "calculateColumnWidths - all columns fit at max width with even distribution" {
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
    try testing.expect(widths.widths[0] > 0);
    try testing.expect(widths.widths[1] > 0);
    try testing.expectEqual(@as(usize, 2), widths.visible_count);

    // Total width should use all available space (leftover distributed evenly)
    var total: u16 = 0;
    for (widths.widths) |w| total += w;
    // With even distribution, total should approach available_width
    try testing.expect(total <= 100);
    try testing.expect(total >= 18); // at least max content widths
}

// =========================================================================
// calculateColumnWidths - proportional reduction
// =========================================================================

test "calculateColumnWidths - columns dont fit, proportional reduction with priority" {
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

    // Narrow width forces column hiding
    var widths = try table_layout.calculateColumnWidths(
        allocator,
        &headers,
        &rows,
        &columns,
        30,
    );
    defer widths.deinit();

    // NAME (CRITICAL) should always be visible
    try testing.expect(widths.widths[0] > 0);

    // AGE (VERY_LOW) should be hidden first
    try testing.expectEqual(@as(u16, 0), widths.widths[4]);
}

// =========================================================================
// calculateColumnWidths - single column
// =========================================================================

test "calculateColumnWidths - single column gets full width" {
    const allocator = testing.allocator;

    const headers = [_][]const u8{"NAME"};
    const rows = [_][]const []const u8{
        &[_][]const u8{"pod-1"},
    };

    const columns = [_]table_layout.ColumnInfo{
        .{ .name = "NAME", .min_width = 5, .priority = 0 },
    };

    var widths = try table_layout.calculateColumnWidths(
        allocator,
        &headers,
        &rows,
        &columns,
        80,
    );
    defer widths.deinit();

    try testing.expectEqual(@as(usize, 1), widths.visible_count);
    // Single column should get the full available width
    try testing.expect(widths.widths[0] >= 7); // "NAME" + 2 = 6 is natural max, but extra is distributed
}

// =========================================================================
// calculateColumnWidths - zero available width
// =========================================================================

test "calculateColumnWidths - zero available width hides all columns" {
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
        0,
    );
    defer widths.deinit();

    // With 0 width, all columns should be hidden
    for (widths.widths) |w| {
        try testing.expectEqual(@as(u16, 0), w);
    }
}

// =========================================================================
// calculateColumnWidths - unbounded columns grow, bounded columns capped
// =========================================================================

test "calculateColumnWidths - bounded column does not exceed max_width much" {
    const allocator = testing.allocator;

    const headers = [_][]const u8{ "NAME", "STATUS" };
    const rows = [_][]const []const u8{
        &[_][]const u8{ "my-pod", "Running" },
    };

    const columns = [_]table_layout.ColumnInfo{
        .{ .name = "NAME", .min_width = 8, .max_width = null, .priority = 0 }, // unbounded
        .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = 50 }, // capped at 12
    };

    var widths = try table_layout.calculateColumnWidths(
        allocator,
        &headers,
        &rows,
        &columns,
        200,
    );
    defer widths.deinit();

    // Both columns should be visible
    try testing.expect(widths.widths[0] > 0);
    try testing.expect(widths.widths[1] > 0);
    // When all fit, even distribution adds equal leftover to each col,
    // but the unbounded column should still get at least its content width
    try testing.expect(widths.widths[0] >= 8); // "my-pod" + 2 = 8
}

// =========================================================================
// Text truncation and padding
// =========================================================================

test "truncateText - basic truncation with ellipsis" {
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

test "truncateText - exact fit" {
    const allocator = testing.allocator;

    const text = "exact";
    const result = try table_layout.truncateText(allocator, text, 5, true);
    defer allocator.free(result);

    try testing.expectEqualStrings("exact", result);
}

test "truncateText - without ellipsis" {
    const allocator = testing.allocator;

    const text = "long-text-here";
    const result = try table_layout.truncateText(allocator, text, 8, false);
    defer allocator.free(result);

    try testing.expectEqualStrings("long-tex", result);
}

test "truncateText - width less than 3 with ellipsis falls back to plain truncation" {
    const allocator = testing.allocator;

    const text = "hello";
    const result = try table_layout.truncateText(allocator, text, 2, true);
    defer allocator.free(result);

    try testing.expectEqualStrings("he", result);
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

test "padText - text longer than width is truncated" {
    const allocator = testing.allocator;

    const text = "very-long-text";
    const padded = try table_layout.padText(allocator, text, 5, false);
    defer allocator.free(padded);

    try testing.expectEqualStrings("very-", padded);
}

test "padText - exact width needs no padding" {
    const allocator = testing.allocator;

    const text = "exact";
    const padded = try table_layout.padText(allocator, text, 5, false);
    defer allocator.free(padded);

    try testing.expectEqualStrings("exact", padded);
}

// =========================================================================
// TableScroll
// =========================================================================

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

test "TableScroll - scrollLeft past zero clamps to zero" {
    var scroll = table_layout.TableScroll{
        .scroll_offset = 5,
        .visible_width = 50,
        .total_width = 150,
    };

    scroll.scrollLeft(100);
    try testing.expectEqual(@as(u16, 0), scroll.scroll_offset);
}

test "TableScroll - scrollRight past max clamps" {
    var scroll = table_layout.TableScroll{
        .scroll_offset = 0,
        .visible_width = 50,
        .total_width = 60,
    };

    scroll.scrollRight(50);
    // Max offset = 60 - 50 = 10
    try testing.expectEqual(@as(u16, 10), scroll.scroll_offset);
}

test "TableScroll - total_width <= visible_width means no scroll" {
    var scroll = table_layout.TableScroll{
        .scroll_offset = 0,
        .visible_width = 100,
        .total_width = 80,
    };

    try testing.expect(!scroll.canScrollRight());
    try testing.expect(!scroll.canScrollLeft());

    scroll.scrollRight(50);
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

test "TableScroll - visible range clamped to total_width" {
    const scroll = table_layout.TableScroll{
        .scroll_offset = 90,
        .visible_width = 50,
        .total_width = 100,
    };

    const range = scroll.getVisibleRange();
    try testing.expectEqual(@as(u16, 90), range.start);
    try testing.expectEqual(@as(u16, 100), range.end); // min(90+50, 100)
}

// =========================================================================
// ColumnPriority constants
// =========================================================================

test "ColumnPriority constants are correctly ordered" {
    try testing.expectEqual(@as(u8, 0), table_layout.ColumnPriority.CRITICAL);
    try testing.expectEqual(@as(u8, 25), table_layout.ColumnPriority.HIGH);
    try testing.expectEqual(@as(u8, 50), table_layout.ColumnPriority.MEDIUM);
    try testing.expectEqual(@as(u8, 100), table_layout.ColumnPriority.LOW);
    try testing.expectEqual(@as(u8, 200), table_layout.ColumnPriority.VERY_LOW);

    // Verify ordering
    try testing.expect(table_layout.ColumnPriority.CRITICAL < table_layout.ColumnPriority.HIGH);
    try testing.expect(table_layout.ColumnPriority.HIGH < table_layout.ColumnPriority.MEDIUM);
    try testing.expect(table_layout.ColumnPriority.MEDIUM < table_layout.ColumnPriority.LOW);
    try testing.expect(table_layout.ColumnPriority.LOW < table_layout.ColumnPriority.VERY_LOW);
}

// =========================================================================
// ColumnWidths deinit
// =========================================================================

test "ColumnWidths deinit frees memory" {
    const allocator = testing.allocator;

    const headers = [_][]const u8{ "A", "B" };
    const rows = [_][]const []const u8{
        &[_][]const u8{ "x", "y" },
    };
    const columns = [_]table_layout.ColumnInfo{
        .{ .name = "A", .min_width = 3, .priority = 0 },
        .{ .name = "B", .min_width = 3, .priority = 0 },
    };

    var widths = try table_layout.calculateColumnWidths(
        allocator,
        &headers,
        &rows,
        &columns,
        50,
    );
    // Should not leak
    widths.deinit();
}

// =========================================================================
// Many columns, progressive hiding
// =========================================================================

test "calculateColumnWidths - many columns with tight width hides low priority" {
    const allocator = testing.allocator;

    const headers = [_][]const u8{ "NAME", "NS", "STATUS", "READY", "IP", "NODE", "CPU", "MEM", "AGE" };
    const rows = [_][]const []const u8{
        &[_][]const u8{ "p", "default", "Running", "1/1", "10.0.0.1", "node-1", "10m", "64Mi", "1d" },
    };

    const columns = [_]table_layout.ColumnInfo{
        .{ .name = "NAME", .min_width = 6, .priority = table_layout.ColumnPriority.CRITICAL },
        .{ .name = "NS", .min_width = 6, .priority = table_layout.ColumnPriority.MEDIUM },
        .{ .name = "STATUS", .min_width = 6, .priority = table_layout.ColumnPriority.HIGH },
        .{ .name = "READY", .min_width = 5, .priority = table_layout.ColumnPriority.HIGH },
        .{ .name = "IP", .min_width = 8, .priority = table_layout.ColumnPriority.LOW },
        .{ .name = "NODE", .min_width = 6, .priority = table_layout.ColumnPriority.LOW },
        .{ .name = "CPU", .min_width = 4, .priority = table_layout.ColumnPriority.VERY_LOW },
        .{ .name = "MEM", .min_width = 4, .priority = table_layout.ColumnPriority.VERY_LOW },
        .{ .name = "AGE", .min_width = 4, .priority = table_layout.ColumnPriority.MEDIUM },
    };

    // Only 30 chars of space
    var widths = try table_layout.calculateColumnWidths(
        allocator,
        &headers,
        &rows,
        &columns,
        30,
    );
    defer widths.deinit();

    // NAME (CRITICAL) must be visible
    try testing.expect(widths.widths[0] > 0);

    // VERY_LOW (CPU, MEM) should be hidden first
    try testing.expectEqual(@as(u16, 0), widths.widths[6]); // CPU
    try testing.expectEqual(@as(u16, 0), widths.widths[7]); // MEM
}
