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

    // If all visible columns fit at max width, use max widths
    if (total_max <= available_width) {
        for (max_widths, visible, 0..) |max, vis, i| {
            final_widths[i] = if (vis) max else 0;
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
