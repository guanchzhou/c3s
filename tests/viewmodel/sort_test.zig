const std = @import("std");
const testing = std.testing;
const c3s = @import("c3s");
const sort = c3s.sort;

// Test data structure
const TestItem = struct {
    name: []const u8,
    value: i32,
};

fn getName(item: *const TestItem) []const u8 {
    return item.name;
}

// --- toggleSort tests ---

test "toggleSort on null column sets column and ascending=true" {
    var sort_column: ?u8 = null;
    var sort_ascending: bool = false;

    sort.toggleSort(&sort_column, &sort_ascending, 3);

    try testing.expectEqual(@as(?u8, 3), sort_column);
    try testing.expect(sort_ascending);
}

test "toggleSort on same column flips ascending" {
    var sort_column: ?u8 = 2;
    var sort_ascending: bool = true;

    sort.toggleSort(&sort_column, &sort_ascending, 2);

    try testing.expectEqual(@as(?u8, 2), sort_column);
    try testing.expect(!sort_ascending);

    // Toggle again: false -> true
    sort.toggleSort(&sort_column, &sort_ascending, 2);

    try testing.expectEqual(@as(?u8, 2), sort_column);
    try testing.expect(sort_ascending);
}

test "toggleSort on different column sets new column and ascending=true" {
    var sort_column: ?u8 = 1;
    var sort_ascending: bool = false;

    sort.toggleSort(&sort_column, &sort_ascending, 5);

    try testing.expectEqual(@as(?u8, 5), sort_column);
    try testing.expect(sort_ascending);
}

// --- sortIndicator tests ---

test "sortIndicator returns ascending marker for ascending active column" {
    const result = sort.sortIndicator(@as(?u8, 2), true, 2);
    try testing.expectEqualStrings(" \xe2\x96\xb2", result); // " ▲"
}

test "sortIndicator returns descending marker for descending active column" {
    const result = sort.sortIndicator(@as(?u8, 2), false, 2);
    try testing.expectEqualStrings(" \xe2\x96\xbc", result); // " ▼"
}

test "sortIndicator returns empty string for inactive column" {
    const result = sort.sortIndicator(@as(?u8, 2), true, 5);
    try testing.expectEqualStrings("", result);
}

test "sortIndicator returns empty string when no column is sorted" {
    const result = sort.sortIndicator(@as(?u8, null), true, 0);
    try testing.expectEqualStrings("", result);
}

// --- sortFilteredIndices tests ---

test "sortFilteredIndices sorts items by name ascending" {
    const allocator = testing.allocator;

    const items = [_]TestItem{
        .{ .name = "cherry", .value = 3 },
        .{ .name = "apple", .value = 1 },
        .{ .name = "banana", .value = 2 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    try filtered_indices.append(allocator, 0);
    try filtered_indices.append(allocator, 1);
    try filtered_indices.append(allocator, 2);

    sort.sortFilteredIndices(TestItem, &items, &filtered_indices, getName, true);

    // After ascending sort by name: apple(1), banana(2), cherry(0)
    try testing.expectEqual(@as(usize, 1), filtered_indices.items[0]);
    try testing.expectEqual(@as(usize, 2), filtered_indices.items[1]);
    try testing.expectEqual(@as(usize, 0), filtered_indices.items[2]);
}

test "sortFilteredIndices sorts items by name descending" {
    const allocator = testing.allocator;

    const items = [_]TestItem{
        .{ .name = "cherry", .value = 3 },
        .{ .name = "apple", .value = 1 },
        .{ .name = "banana", .value = 2 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    try filtered_indices.append(allocator, 0);
    try filtered_indices.append(allocator, 1);
    try filtered_indices.append(allocator, 2);

    sort.sortFilteredIndices(TestItem, &items, &filtered_indices, getName, false);

    // After descending sort by name: cherry(0), banana(2), apple(1)
    try testing.expectEqual(@as(usize, 0), filtered_indices.items[0]);
    try testing.expectEqual(@as(usize, 2), filtered_indices.items[1]);
    try testing.expectEqual(@as(usize, 1), filtered_indices.items[2]);
}

test "sortFilteredIndices handles empty list" {
    const allocator = testing.allocator;

    const items = [_]TestItem{
        .{ .name = "apple", .value = 1 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    // Empty filtered_indices -- should not crash
    sort.sortFilteredIndices(TestItem, &items, &filtered_indices, getName, true);

    try testing.expectEqual(@as(usize, 0), filtered_indices.items.len);
}
