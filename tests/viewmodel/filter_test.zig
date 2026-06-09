const std = @import("std");
const testing = std.testing;
const universal_filter = @import("src").filter;

// Test data structure
const TestItem = struct {
    name: []const u8,
    value: i32,
};

fn nameMatchFn(item: *const TestItem, filter: []const u8) bool {
    return std.mem.indexOf(u8, item.name, filter) != null;
}

test "filter with empty filter text shows all items" {
    const allocator = testing.allocator;

    const items = [_]TestItem{
        .{ .name = "apple", .value = 1 },
        .{ .name = "banana", .value = 2 },
        .{ .name = "cherry", .value = 3 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    var selected_row: u32 = 0;
    var scroll_offset: u32 = 0;

    try universal_filter.applyFilter(
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

    try testing.expectEqual(@as(usize, 3), filtered_indices.items.len);
    try testing.expectEqual(@as(usize, 0), filtered_indices.items[0]);
    try testing.expectEqual(@as(usize, 1), filtered_indices.items[1]);
    try testing.expectEqual(@as(usize, 2), filtered_indices.items[2]);
}

test "filter with matching text returns subset" {
    const allocator = testing.allocator;

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

    try universal_filter.applyFilter(
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

    try testing.expectEqual(@as(usize, 2), filtered_indices.items.len);
    try testing.expectEqual(@as(usize, 0), filtered_indices.items[0]); // apple
    try testing.expectEqual(@as(usize, 2), filtered_indices.items[1]); // apricot
}

test "filter with no matches returns empty list" {
    const allocator = testing.allocator;

    const items = [_]TestItem{
        .{ .name = "apple", .value = 1 },
        .{ .name = "banana", .value = 2 },
        .{ .name = "cherry", .value = 3 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    var selected_row: u32 = 0;
    var scroll_offset: u32 = 0;

    try universal_filter.applyFilter(
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

    try testing.expectEqual(@as(usize, 0), filtered_indices.items.len);
}

test "filter preserves selection when item still visible" {
    const allocator = testing.allocator;

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
    try universal_filter.applyFilter(
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
    try testing.expectEqual(@as(u32, 1), selected_row);
    try testing.expectEqual(@as(usize, 2), filtered_indices.items.len);
}

test "filter resets selection when item not in filtered list" {
    const allocator = testing.allocator;

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
    try universal_filter.applyFilter(
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
    try testing.expectEqual(@as(u32, 0), selected_row);
    try testing.expectEqual(@as(u32, 0), scroll_offset);
}

test "filter adjusts scroll offset when selection moves" {
    const allocator = testing.allocator;

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
    try universal_filter.applyFilter(
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
    try testing.expectEqual(@as(u32, 8), selected_row);
    // Scroll should be adjusted to keep selection visible
    try testing.expect(scroll_offset <= selected_row);
    try testing.expect(selected_row < scroll_offset + 5);
}

test "filter clears and repopulates filtered indices" {
    const allocator = testing.allocator;

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
    try universal_filter.applyFilter(
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

    try testing.expectEqual(@as(usize, 2), filtered_indices.items.len);

    // Second filter - should clear and repopulate
    try universal_filter.applyFilter(
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

    try testing.expectEqual(@as(usize, 1), filtered_indices.items.len);
    try testing.expectEqual(@as(usize, 1), filtered_indices.items[0]); // banana
}
