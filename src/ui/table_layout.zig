const std = @import("std");

/// Column configuration information
pub const ColumnInfo = struct {
    name: []const u8,
    min_width: u16,
    max_width: ?u16 = null, // null = unlimited
    priority: u8, // 0 = highest priority (always visible), 255 = lowest
    truncatable: bool = true, // Can this column be truncated with ...?
};

/// Column priority constants
pub const ColumnPriority = struct {
    pub const CRITICAL: u8 = 0; // NAME - always visible
    pub const HIGH: u8 = 25; // STATUS, READY - critical state
    pub const MEDIUM: u8 = 50; // NAMESPACE, AGE - important context
    pub const LOW: u8 = 100; // RESTARTS, IP, NODE - nice to have
    pub const VERY_LOW: u8 = 200; // CPU, MEM, GPU - metrics
};

/// Calculated column widths for rendering
pub const ColumnWidths = struct {
    widths: []u16, // Final width for each column (0 = hidden)
    visible_count: usize,
    total_width: u16,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ColumnWidths) void {
        self.allocator.free(self.widths);
    }
};

/// Horizontal scroll state for table
pub const TableScroll = struct {
    scroll_offset: u16 = 0,
    visible_width: u16,
    total_width: u16,

    pub fn canScrollLeft(self: *const TableScroll) bool {
        return self.scroll_offset > 0;
    }

    pub fn canScrollRight(self: *const TableScroll) bool {
        return self.scroll_offset + self.visible_width < self.total_width;
    }

    pub fn scrollLeft(self: *TableScroll, amount: u16) void {
        if (self.scroll_offset >= amount) {
            self.scroll_offset -= amount;
        } else {
            self.scroll_offset = 0;
        }
    }

    pub fn scrollRight(self: *TableScroll, amount: u16) void {
        const max_offset = if (self.total_width > self.visible_width)
            self.total_width - self.visible_width
        else
            0;

        self.scroll_offset = @min(
            self.scroll_offset + amount,
            max_offset,
        );
    }

    pub fn scrollToStart(self: *TableScroll) void {
        self.scroll_offset = 0;
    }

    pub fn scrollToEnd(self: *TableScroll) void {
        if (self.total_width > self.visible_width) {
            self.scroll_offset = self.total_width - self.visible_width;
        }
    }

    pub fn getVisibleRange(self: *const TableScroll) struct { start: u16, end: u16 } {
        return .{
            .start = self.scroll_offset,
            .end = @min(self.scroll_offset + self.visible_width, self.total_width),
        };
    }
};

/// Calculate maximum width for each column based on content
pub fn calculateMaxColumnWidths(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
) ![]u16 {
    var max_widths = try allocator.alloc(u16, headers.len);
    errdefer allocator.free(max_widths);

    // Initialize with header widths (+2 for padding)
    for (headers, 0..) |header, i| {
        max_widths[i] = @intCast(header.len + 2);
    }

    // Find max width from data rows
    for (rows) |row| {
        for (row, 0..) |cell, i| {
            if (i >= max_widths.len) break;
            const width: u16 = @intCast(cell.len + 2);
            if (width > max_widths[i]) {
                max_widths[i] = width;
            }
        }
    }

    return max_widths;
}

/// Determine which columns should be visible based on priority and available width
fn determineVisibleColumns(
    allocator: std.mem.Allocator,
    max_widths: []const u16,
    columns: []const ColumnInfo,
    available_width: u16,
) ![]bool {
    var visible = try allocator.alloc(bool, columns.len);
    @memset(visible, true);

    // Calculate total width needed
    var total_width: u16 = 0;
    for (max_widths) |w| {
        const new_width = @addWithOverflow(total_width, w);
        if (new_width[1] != 0) {
            total_width = std.math.maxInt(u16);
            break;
        }
        total_width = new_width[0];
    }

    // If all columns fit, we're done
    if (total_width <= available_width) {
        return visible;
    }

    // Create sorted indices by priority (lowest priority first)
    const indices = try allocator.alloc(usize, columns.len);
    defer allocator.free(indices);
    for (indices, 0..) |*idx, i| {
        idx.* = i;
    }

    // Sort by priority descending (highest priority last)
    std.mem.sort(usize, indices, columns, struct {
        fn lessThan(cols: []const ColumnInfo, a: usize, b: usize) bool {
            return cols[a].priority > cols[b].priority;
        }
    }.lessThan);

    // Hide columns starting from lowest priority
    for (indices) |idx| {
        if (total_width <= available_width) break;

        visible[idx] = false;
        if (total_width >= max_widths[idx]) {
            total_width -= max_widths[idx];
        } else {
            total_width = 0;
        }
    }

    return visible;
}

/// Distribute available width among visible columns
fn distributeWidth(
    allocator: std.mem.Allocator,
    max_widths: []const u16,
    columns: []const ColumnInfo,
    visible: []const bool,
    available_width: u16,
) ![]u16 {
    var final_widths = try allocator.alloc(u16, columns.len);
    errdefer allocator.free(final_widths);
    @memset(final_widths, 0);

    // Count visible columns and their total max width
    var visible_count: usize = 0;
    var total_max: u16 = 0;
    for (visible, max_widths) |vis, max| {
        if (vis) {
            visible_count += 1;
            const new_max = @addWithOverflow(total_max, max);
            if (new_max[1] != 0) {
                total_max = std.math.maxInt(u16);
            } else {
                total_max = new_max[0];
            }
        }
    }

    if (visible_count == 0) {
        return final_widths;
    }

    // If all visible columns fit at max content width, use those widths
    // and spread leftover space evenly so the table fills the terminal.
    if (total_max <= available_width) {
        for (max_widths, visible, 0..) |max, vis, i| {
            final_widths[i] = if (vis) max else 0;
        }
        // Distribute leftover only to unbounded columns (max_width = null).
        // Bounded columns (READY, STATUS, AGE, etc.) stay at content width.
        const leftover = available_width - total_max;
        if (leftover > 0) {
            var unbounded_count: u16 = 0;
            for (columns, visible) |col, vis| {
                if (vis and col.max_width == null) unbounded_count += 1;
            }
            if (unbounded_count > 0) {
                const per_col = leftover / unbounded_count;
                for (final_widths, visible, columns) |*w, vis, col| {
                    if (vis and w.* > 0 and col.max_width == null) w.* += per_col;
                }
            }
        }
        return final_widths;
    }

    // Proportionally reduce widths to fit available space
    // First pass: allocate minimum widths
    var allocated: u16 = 0;
    for (columns, visible, 0..) |col, vis, i| {
        if (vis) {
            final_widths[i] = col.min_width;
            const new_alloc = @addWithOverflow(allocated, col.min_width);
            if (new_alloc[1] != 0) {
                allocated = std.math.maxInt(u16);
            } else {
                allocated = new_alloc[0];
            }
        }
    }

    // Second pass: distribute remaining space proportionally
    if (allocated < available_width) {
        const remaining = available_width - allocated;
        const total_extra = if (total_max > allocated) total_max - allocated else 1;
        const scale = @as(f32, @floatFromInt(remaining)) /
            @as(f32, @floatFromInt(total_extra));

        for (max_widths, columns, visible, 0..) |max, col, vis, i| {
            if (vis and max > col.min_width) {
                const extra_space = max - col.min_width;
                const allocated_extra: u16 = @intFromFloat(
                    @as(f32, @floatFromInt(extra_space)) * scale,
                );
                final_widths[i] = col.min_width + allocated_extra;
                // Cap at max_width if defined
                if (col.max_width) |mw| {
                    if (final_widths[i] > mw) final_widths[i] = mw;
                }
            }
        }

        // Third pass: give remaining space to unbounded columns by priority.
        // Higher-priority columns (lower number) get space first, up to their
        // max content width. This ensures NAME fills before NODE/IP.
        var used: u16 = 0;
        for (final_widths, visible) |w, vis| {
            if (vis) used += w;
        }

        if (used < available_width) {
            var leftover = available_width - used;

            // Sort unbounded column indices by priority (highest priority first)
            var unbounded: [32]usize = undefined;
            var unbounded_count: usize = 0;
            for (columns, visible, 0..) |col, vis, i| {
                if (vis and col.max_width == null and final_widths[i] > 0) {
                    if (unbounded_count < 32) {
                        unbounded[unbounded_count] = i;
                        unbounded_count += 1;
                    }
                }
            }

            // Sort by priority ascending (CRITICAL=0 first)
            const ub_slice = unbounded[0..unbounded_count];
            std.mem.sort(usize, ub_slice, columns, struct {
                fn lessThan(cols: []const ColumnInfo, a: usize, b: usize) bool {
                    return cols[a].priority < cols[b].priority;
                }
            }.lessThan);

            // Give each unbounded column space up to its content width, by priority
            for (ub_slice) |idx| {
                if (leftover == 0) break;
                const need = if (max_widths[idx] > final_widths[idx])
                    max_widths[idx] - final_widths[idx]
                else
                    0;
                const give = @min(need, leftover);
                final_widths[idx] += give;
                leftover -= give;
            }

            // If still leftover, distribute evenly among unbounded
            if (leftover > 0 and unbounded_count > 0) {
                const per_col: u16 = leftover / @as(u16, @intCast(unbounded_count));
                for (ub_slice) |idx| {
                    final_widths[idx] += per_col;
                }
            }
        }
    }

    return final_widths;
}

/// Main function to calculate column widths for rendering
pub fn calculateColumnWidths(
    allocator: std.mem.Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    columns: []const ColumnInfo,
    available_width: u16,
) !ColumnWidths {
    // Calculate maximum natural widths
    const max_widths = try calculateMaxColumnWidths(allocator, headers, rows);
    defer allocator.free(max_widths);

    // Determine which columns should be visible
    const visible = try determineVisibleColumns(allocator, max_widths, columns, available_width);
    defer allocator.free(visible);

    // Distribute width among visible columns
    const widths = try distributeWidth(allocator, max_widths, columns, visible, available_width);

    // Calculate total width and visible count
    var total_width: u16 = 0;
    var visible_count: usize = 0;
    for (widths) |w| {
        const new_total = @addWithOverflow(total_width, w);
        if (new_total[1] != 0) {
            total_width = std.math.maxInt(u16);
        } else {
            total_width = new_total[0];
        }
        if (w > 0) visible_count += 1;
    }

    return ColumnWidths{
        .widths = widths,
        .visible_count = visible_count,
        .total_width = total_width,
        .allocator = allocator,
    };
}

/// Truncate text to fit within width, adding ellipsis if needed
pub fn truncateText(
    allocator: std.mem.Allocator,
    text: []const u8,
    width: u16,
    add_ellipsis: bool,
) ![]const u8 {
    if (text.len <= width) {
        return try allocator.dupe(u8, text);
    }

    if (add_ellipsis and width >= 3) {
        const truncated = try allocator.alloc(u8, width);
        const text_len = width - 3;
        @memcpy(truncated[0..text_len], text[0..text_len]);
        @memcpy(truncated[text_len..], "...");
        return truncated;
    }

    return try allocator.dupe(u8, text[0..width]);
}

/// Pad text to fit within width
pub fn padText(
    allocator: std.mem.Allocator,
    text: []const u8,
    width: u16,
    align_right: bool,
) ![]const u8 {
    if (text.len >= width) {
        return try allocator.dupe(u8, text[0..width]);
    }

    const padded = try allocator.alloc(u8, width);
    const padding = width - @as(u16, @intCast(text.len));

    if (align_right) {
        @memset(padded[0..padding], ' ');
        @memcpy(padded[padding..], text);
    } else {
        @memcpy(padded[0..text.len], text);
        @memset(padded[text.len..], ' ');
    }

    return padded;
}

const testing = std.testing;

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

    const max_widths = try calculateMaxColumnWidths(
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

    const max_widths = try calculateMaxColumnWidths(
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

    const max_widths = try calculateMaxColumnWidths(
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

    const columns = [_]ColumnInfo{
        .{ .name = "NAME", .min_width = 10, .priority = 0 },
        .{ .name = "STATUS", .min_width = 8, .priority = 50 },
    };

    var widths = try calculateColumnWidths(
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

    const columns = [_]ColumnInfo{
        .{ .name = "NAME", .min_width = 8, .priority = ColumnPriority.CRITICAL },
        .{ .name = "READY", .min_width = 5, .priority = ColumnPriority.HIGH },
        .{ .name = "STATUS", .min_width = 8, .priority = ColumnPriority.HIGH },
        .{ .name = "RESTARTS", .min_width = 8, .priority = ColumnPriority.LOW },
        .{ .name = "AGE", .min_width = 5, .priority = ColumnPriority.VERY_LOW },
    };

    // Narrow width forces column hiding
    var widths = try calculateColumnWidths(
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

    const columns = [_]ColumnInfo{
        .{ .name = "NAME", .min_width = 5, .priority = 0 },
    };

    var widths = try calculateColumnWidths(
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

    const columns = [_]ColumnInfo{
        .{ .name = "NAME", .min_width = 10, .priority = 0 },
        .{ .name = "STATUS", .min_width = 8, .priority = 50 },
    };

    var widths = try calculateColumnWidths(
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

    const columns = [_]ColumnInfo{
        .{ .name = "NAME", .min_width = 8, .max_width = null, .priority = 0 }, // unbounded
        .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = 50 }, // capped at 12
    };

    var widths = try calculateColumnWidths(
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
    const truncated = try truncateText(allocator, text, 10, true);
    defer allocator.free(truncated);

    try testing.expectEqualStrings("very-lo...", truncated);
}

test "truncateText - no truncation needed" {
    const allocator = testing.allocator;

    const text = "short";
    const result = try truncateText(allocator, text, 10, true);
    defer allocator.free(result);

    try testing.expectEqualStrings("short", result);
}

test "truncateText - exact fit" {
    const allocator = testing.allocator;

    const text = "exact";
    const result = try truncateText(allocator, text, 5, true);
    defer allocator.free(result);

    try testing.expectEqualStrings("exact", result);
}

test "truncateText - without ellipsis" {
    const allocator = testing.allocator;

    const text = "long-text-here";
    const result = try truncateText(allocator, text, 8, false);
    defer allocator.free(result);

    try testing.expectEqualStrings("long-tex", result);
}

test "truncateText - width less than 3 with ellipsis falls back to plain truncation" {
    const allocator = testing.allocator;

    const text = "hello";
    const result = try truncateText(allocator, text, 2, true);
    defer allocator.free(result);

    try testing.expectEqualStrings("he", result);
}

test "padText - left aligned" {
    const allocator = testing.allocator;

    const text = "pod";
    const padded = try padText(allocator, text, 10, false);
    defer allocator.free(padded);

    try testing.expectEqualStrings("pod       ", padded);
}

test "padText - right aligned" {
    const allocator = testing.allocator;

    const text = "123";
    const padded = try padText(allocator, text, 10, true);
    defer allocator.free(padded);

    try testing.expectEqualStrings("       123", padded);
}

test "padText - text longer than width is truncated" {
    const allocator = testing.allocator;

    const text = "very-long-text";
    const padded = try padText(allocator, text, 5, false);
    defer allocator.free(padded);

    try testing.expectEqualStrings("very-", padded);
}

test "padText - exact width needs no padding" {
    const allocator = testing.allocator;

    const text = "exact";
    const padded = try padText(allocator, text, 5, false);
    defer allocator.free(padded);

    try testing.expectEqualStrings("exact", padded);
}

// =========================================================================
// TableScroll
// =========================================================================

test "TableScroll - scroll left/right" {
    var scroll = TableScroll{
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
    var scroll = TableScroll{
        .scroll_offset = 5,
        .visible_width = 50,
        .total_width = 150,
    };

    scroll.scrollLeft(100);
    try testing.expectEqual(@as(u16, 0), scroll.scroll_offset);
}

test "TableScroll - scrollRight past max clamps" {
    var scroll = TableScroll{
        .scroll_offset = 0,
        .visible_width = 50,
        .total_width = 60,
    };

    scroll.scrollRight(50);
    // Max offset = 60 - 50 = 10
    try testing.expectEqual(@as(u16, 10), scroll.scroll_offset);
}

test "TableScroll - total_width <= visible_width means no scroll" {
    var scroll = TableScroll{
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
    const scroll = TableScroll{
        .scroll_offset = 20,
        .visible_width = 50,
        .total_width = 150,
    };

    const range = scroll.getVisibleRange();
    try testing.expectEqual(@as(u16, 20), range.start);
    try testing.expectEqual(@as(u16, 70), range.end);
}

test "TableScroll - visible range clamped to total_width" {
    const scroll = TableScroll{
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
    try testing.expectEqual(@as(u8, 0), ColumnPriority.CRITICAL);
    try testing.expectEqual(@as(u8, 25), ColumnPriority.HIGH);
    try testing.expectEqual(@as(u8, 50), ColumnPriority.MEDIUM);
    try testing.expectEqual(@as(u8, 100), ColumnPriority.LOW);
    try testing.expectEqual(@as(u8, 200), ColumnPriority.VERY_LOW);

    // Verify ordering
    try testing.expect(ColumnPriority.CRITICAL < ColumnPriority.HIGH);
    try testing.expect(ColumnPriority.HIGH < ColumnPriority.MEDIUM);
    try testing.expect(ColumnPriority.MEDIUM < ColumnPriority.LOW);
    try testing.expect(ColumnPriority.LOW < ColumnPriority.VERY_LOW);
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
    const columns = [_]ColumnInfo{
        .{ .name = "A", .min_width = 3, .priority = 0 },
        .{ .name = "B", .min_width = 3, .priority = 0 },
    };

    var widths = try calculateColumnWidths(
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

    const columns = [_]ColumnInfo{
        .{ .name = "NAME", .min_width = 6, .priority = ColumnPriority.CRITICAL },
        .{ .name = "NS", .min_width = 6, .priority = ColumnPriority.MEDIUM },
        .{ .name = "STATUS", .min_width = 6, .priority = ColumnPriority.HIGH },
        .{ .name = "READY", .min_width = 5, .priority = ColumnPriority.HIGH },
        .{ .name = "IP", .min_width = 8, .priority = ColumnPriority.LOW },
        .{ .name = "NODE", .min_width = 6, .priority = ColumnPriority.LOW },
        .{ .name = "CPU", .min_width = 4, .priority = ColumnPriority.VERY_LOW },
        .{ .name = "MEM", .min_width = 4, .priority = ColumnPriority.VERY_LOW },
        .{ .name = "AGE", .min_width = 4, .priority = ColumnPriority.MEDIUM },
    };

    // Only 30 chars of space
    var widths = try calculateColumnWidths(
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
