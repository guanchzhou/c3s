/// Generic sort utility for resource views.
/// Sorts filtered_indices in place by comparing string fields from the underlying items.
const std = @import("std");

/// Sort filtered_indices by a string field extracted via comptime getField function.
/// Toggle ascending to reverse the order. Repeat press of same column toggles direction.
pub fn sortFilteredIndices(
    comptime T: type,
    items: []const T,
    filtered_indices: *std.ArrayListUnmanaged(usize),
    comptime getField: fn (*const T) []const u8,
    ascending: bool,
) void {
    const Ctx = struct {
        items_slice: []const T,
        asc: bool,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            const fa = getField(&ctx.items_slice[a]);
            const fb = getField(&ctx.items_slice[b]);
            const order = std.mem.order(u8, fa, fb);
            return if (ctx.asc) order == .lt else order == .gt;
        }
    };

    std.sort.pdq(usize, filtered_indices.items, Ctx{
        .items_slice = items,
        .asc = ascending,
    }, Ctx.lessThan);
}

/// Helper to toggle sort state. Returns true if sort was applied (column changed or toggled).
/// Sets sort_column and sort_ascending appropriately.
pub fn toggleSort(sort_column: *?u8, sort_ascending: *bool, column: u8) void {
    if (sort_column.*) |current| {
        if (current == column) {
            sort_ascending.* = !sort_ascending.*;
        } else {
            sort_column.* = column;
            sort_ascending.* = true;
        }
    } else {
        sort_column.* = column;
        sort_ascending.* = true;
    }
}

/// Sort indicator character for column headers.
pub fn sortIndicator(sort_column: ?u8, sort_ascending: bool, column: u8) []const u8 {
    if (sort_column) |current| {
        if (current == column) {
            return if (sort_ascending) " ▲" else " ▼";
        }
    }
    return "";
}

// --- Tests ---

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

    toggleSort(&sort_column, &sort_ascending, 3);

    try std.testing.expectEqual(@as(?u8, 3), sort_column);
    try std.testing.expect(sort_ascending);
}

test "toggleSort on same column flips ascending" {
    var sort_column: ?u8 = 2;
    var sort_ascending: bool = true;

    toggleSort(&sort_column, &sort_ascending, 2);

    try std.testing.expectEqual(@as(?u8, 2), sort_column);
    try std.testing.expect(!sort_ascending);

    // Toggle again: false -> true
    toggleSort(&sort_column, &sort_ascending, 2);

    try std.testing.expectEqual(@as(?u8, 2), sort_column);
    try std.testing.expect(sort_ascending);
}

test "toggleSort on different column sets new column and ascending=true" {
    var sort_column: ?u8 = 1;
    var sort_ascending: bool = false;

    toggleSort(&sort_column, &sort_ascending, 5);

    try std.testing.expectEqual(@as(?u8, 5), sort_column);
    try std.testing.expect(sort_ascending);
}

// --- sortIndicator tests ---

test "sortIndicator returns ascending marker for ascending active column" {
    const result = sortIndicator(@as(?u8, 2), true, 2);
    try std.testing.expectEqualStrings(" \xe2\x96\xb2", result); // " ▲"
}

test "sortIndicator returns descending marker for descending active column" {
    const result = sortIndicator(@as(?u8, 2), false, 2);
    try std.testing.expectEqualStrings(" \xe2\x96\xbc", result); // " ▼"
}

test "sortIndicator returns empty string for inactive column" {
    const result = sortIndicator(@as(?u8, 2), true, 5);
    try std.testing.expectEqualStrings("", result);
}

test "sortIndicator returns empty string when no column is sorted" {
    const result = sortIndicator(@as(?u8, null), true, 0);
    try std.testing.expectEqualStrings("", result);
}

// --- sortFilteredIndices tests ---

test "sortFilteredIndices sorts items by name ascending" {
    const allocator = std.testing.allocator;

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

    sortFilteredIndices(TestItem, &items, &filtered_indices, getName, true);

    // After ascending sort by name: apple(1), banana(2), cherry(0)
    try std.testing.expectEqual(@as(usize, 1), filtered_indices.items[0]);
    try std.testing.expectEqual(@as(usize, 2), filtered_indices.items[1]);
    try std.testing.expectEqual(@as(usize, 0), filtered_indices.items[2]);
}

test "sortFilteredIndices sorts items by name descending" {
    const allocator = std.testing.allocator;

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

    sortFilteredIndices(TestItem, &items, &filtered_indices, getName, false);

    // After descending sort by name: cherry(0), banana(2), apple(1)
    try std.testing.expectEqual(@as(usize, 0), filtered_indices.items[0]);
    try std.testing.expectEqual(@as(usize, 2), filtered_indices.items[1]);
    try std.testing.expectEqual(@as(usize, 1), filtered_indices.items[2]);
}

test "sortFilteredIndices handles empty list" {
    const allocator = std.testing.allocator;

    const items = [_]TestItem{
        .{ .name = "apple", .value = 1 },
    };

    var filtered_indices = std.ArrayListUnmanaged(usize).empty;
    defer filtered_indices.deinit(allocator);

    // Empty filtered_indices -- should not crash
    sortFilteredIndices(TestItem, &items, &filtered_indices, getName, true);

    try std.testing.expectEqual(@as(usize, 0), filtered_indices.items.len);
}
