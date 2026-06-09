const std = @import("std");

/// Universal filter helper that works with any list view
///
/// This function applies a filter to a list of items and updates the filtered_indices array.
/// It also preserves the selection by trying to keep the same item selected after filtering.
///
/// Parameters:
/// - allocator: Memory allocator
/// - items: Slice of all items
/// - filtered_indices: ArrayList to store indices of items that match the filter
/// - filter_text: The filter string to apply
/// - current_selected_row: Pointer to the current selected row (will be updated)
/// - current_scroll_offset: Pointer to the current scroll offset (will be updated)
/// - visible_rows: Number of visible rows in the view
/// - matchFn: Function that returns true if an item matches the filter
///
pub fn applyFilter(
    comptime T: type,
    allocator: std.mem.Allocator,
    items: []const T,
    filtered_indices: *std.ArrayListUnmanaged(usize),
    filter_text: []const u8,
    current_selected_row: *u32,
    current_scroll_offset: *u32,
    visible_rows: u32,
    comptime matchFn: fn (item: *const T, filter: []const u8) bool,
) !void {
    // Remember the currently selected item's original index (if any)
    const old_selected_idx = if (filtered_indices.items.len > 0 and current_selected_row.* < filtered_indices.items.len)
        filtered_indices.items[current_selected_row.*]
    else
        null;

    // Clear filtered indices
    filtered_indices.clearRetainingCapacity();

    if (filter_text.len == 0) {
        // No filter - show all items
        for (0..items.len) |i| {
            try filtered_indices.append(allocator, i);
        }
    } else {
        // Apply filter
        for (items, 0..) |*item, i| {
            if (matchFn(item, filter_text)) {
                try filtered_indices.append(allocator, i);
            }
        }
    }

    // Try to restore selection to the same item if it's still in the filtered list
    if (old_selected_idx) |item_idx| {
        for (filtered_indices.items, 0..) |filtered_idx, i| {
            if (filtered_idx == item_idx) {
                current_selected_row.* = @intCast(i);
                // Adjust scroll to keep selection visible
                if (current_selected_row.* < current_scroll_offset.*) {
                    current_scroll_offset.* = current_selected_row.*;
                } else if (current_selected_row.* >= current_scroll_offset.* + visible_rows) {
                    current_scroll_offset.* = if (current_selected_row.* >= visible_rows)
                        current_selected_row.* - visible_rows + 1
                    else
                        0;
                }
                return;
            }
        }
    }

    // If we couldn't restore the selection, reset to top
    current_selected_row.* = 0;
    current_scroll_offset.* = 0;
}

// --- Tests ---

// Test data structure
const TestItem = struct {
    name: []const u8,
    value: i32,
};

fn nameMatchFn(item: *const TestItem, filter: []const u8) bool {
    return std.mem.indexOf(u8, item.name, filter) != null;
}

test "filter with empty filter text shows all items" {
    const allocator = std.testing.allocator;

    const items = [_]TestItem{
        .{ .name = "apple", .value = 1 },
        .{ .name = "banana", .value = 2 },
        .{ .name = "cherry", .value = 3 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    var selected_row: u32 = 0;
    var scroll_offset: u32 = 0;

    try applyFilter(
        TestItem,
        allocator,
        &items,
        &filtered_indices,
        "",
        &selected_row,
        &scroll_offset,
        10,
        nameMatchFn,
    );

    try std.testing.expectEqual(@as(usize, 3), filtered_indices.items.len);
    try std.testing.expectEqual(@as(usize, 0), filtered_indices.items[0]);
    try std.testing.expectEqual(@as(usize, 1), filtered_indices.items[1]);
    try std.testing.expectEqual(@as(usize, 2), filtered_indices.items[2]);
}

test "filter with matching text returns subset" {
    const allocator = std.testing.allocator;

    const items = [_]TestItem{
        .{ .name = "apple", .value = 1 },
        .{ .name = "banana", .value = 2 },
        .{ .name = "apricot", .value = 3 },
        .{ .name = "cherry", .value = 4 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    var selected_row: u32 = 0;
    var scroll_offset: u32 = 0;

    try applyFilter(
        TestItem,
        allocator,
        &items,
        &filtered_indices,
        "ap",
        &selected_row,
        &scroll_offset,
        10,
        nameMatchFn,
    );

    try std.testing.expectEqual(@as(usize, 2), filtered_indices.items.len);
    try std.testing.expectEqual(@as(usize, 0), filtered_indices.items[0]); // apple
    try std.testing.expectEqual(@as(usize, 2), filtered_indices.items[1]); // apricot
}

test "filter with no matches returns empty list" {
    const allocator = std.testing.allocator;

    const items = [_]TestItem{
        .{ .name = "apple", .value = 1 },
        .{ .name = "banana", .value = 2 },
        .{ .name = "cherry", .value = 3 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    var selected_row: u32 = 0;
    var scroll_offset: u32 = 0;

    try applyFilter(
        TestItem,
        allocator,
        &items,
        &filtered_indices,
        "xyz",
        &selected_row,
        &scroll_offset,
        10,
        nameMatchFn,
    );

    try std.testing.expectEqual(@as(usize, 0), filtered_indices.items.len);
}

test "filter preserves selection when item still visible" {
    const allocator = std.testing.allocator;

    const items = [_]TestItem{
        .{ .name = "apple", .value = 1 },
        .{ .name = "banana", .value = 2 },
        .{ .name = "apricot", .value = 3 },
        .{ .name = "cherry", .value = 4 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    // First, populate with all items
    try filtered_indices.append(allocator, 0);
    try filtered_indices.append(allocator, 1);
    try filtered_indices.append(allocator, 2);
    try filtered_indices.append(allocator, 3);

    // Select "apricot" (index 2 in original, index 2 in filtered)
    var selected_row: u32 = 2;
    var scroll_offset: u32 = 0;

    // Now filter to "ap" - should keep "apple" and "apricot"
    try applyFilter(
        TestItem,
        allocator,
        &items,
        &filtered_indices,
        "ap",
        &selected_row,
        &scroll_offset,
        10,
        nameMatchFn,
    );

    // "apricot" is now at filtered index 1
    try std.testing.expectEqual(@as(u32, 1), selected_row);
    try std.testing.expectEqual(@as(usize, 2), filtered_indices.items.len);
}

test "filter resets selection when item not in filtered list" {
    const allocator = std.testing.allocator;

    const items = [_]TestItem{
        .{ .name = "apple", .value = 1 },
        .{ .name = "banana", .value = 2 },
        .{ .name = "cherry", .value = 3 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    // First, populate with all items
    try filtered_indices.append(allocator, 0);
    try filtered_indices.append(allocator, 1);
    try filtered_indices.append(allocator, 2);

    // Select "banana" (index 1)
    var selected_row: u32 = 1;
    var scroll_offset: u32 = 0;

    // Filter to "ch" - only "cherry" matches, "banana" is gone
    try applyFilter(
        TestItem,
        allocator,
        &items,
        &filtered_indices,
        "ch",
        &selected_row,
        &scroll_offset,
        10,
        nameMatchFn,
    );

    // Selection should reset to top
    try std.testing.expectEqual(@as(u32, 0), selected_row);
    try std.testing.expectEqual(@as(u32, 0), scroll_offset);
}

test "filter adjusts scroll offset when selection moves" {
    const allocator = std.testing.allocator;

    const items = [_]TestItem{
        .{ .name = "item0", .value = 0 },
        .{ .name = "item1", .value = 1 },
        .{ .name = "item2", .value = 2 },
        .{ .name = "item3", .value = 3 },
        .{ .name = "item4", .value = 4 },
        .{ .name = "item5", .value = 5 },
        .{ .name = "item6", .value = 6 },
        .{ .name = "item7", .value = 7 },
        .{ .name = "item8", .value = 8 },
        .{ .name = "item9", .value = 9 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    // Populate with all items
    for (0..items.len) |i| {
        try filtered_indices.append(allocator, i);
    }

    // Select item8 with scroll offset to keep it visible (visible_rows = 5)
    var selected_row: u32 = 8;
    var scroll_offset: u32 = 4; // Shows items 4-8

    // Filter to "" (all items) - should preserve selection and adjust scroll
    try applyFilter(
        TestItem,
        allocator,
        &items,
        &filtered_indices,
        "",
        &selected_row,
        &scroll_offset,
        5, // visible_rows
        nameMatchFn,
    );

    // Selection should be preserved
    try std.testing.expectEqual(@as(u32, 8), selected_row);
    // Scroll should be adjusted to keep selection visible
    try std.testing.expect(scroll_offset <= selected_row);
    try std.testing.expect(selected_row < scroll_offset + 5);
}

test "filter clears and repopulates filtered indices" {
    const allocator = std.testing.allocator;

    const items = [_]TestItem{
        .{ .name = "apple", .value = 1 },
        .{ .name = "banana", .value = 2 },
        .{ .name = "apricot", .value = 3 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    var selected_row: u32 = 0;
    var scroll_offset: u32 = 0;

    // First filter
    try applyFilter(
        TestItem,
        allocator,
        &items,
        &filtered_indices,
        "ap",
        &selected_row,
        &scroll_offset,
        10,
        nameMatchFn,
    );

    try std.testing.expectEqual(@as(usize, 2), filtered_indices.items.len);

    // Second filter - should clear and repopulate
    try applyFilter(
        TestItem,
        allocator,
        &items,
        &filtered_indices,
        "ban",
        &selected_row,
        &scroll_offset,
        10,
        nameMatchFn,
    );

    try std.testing.expectEqual(@as(usize, 1), filtered_indices.items.len);
    try std.testing.expectEqual(@as(usize, 1), filtered_indices.items[0]); // banana
}
