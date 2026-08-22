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

/// Sort filtered_indices by a column selected at RUNTIME.
///
/// The comptime-getField variant above forces Zig to emit a separate std.sort.pdq
/// instantiation for every (view, column) pair. Measured at ~130 KB of machine code
/// across 8 views -- for a sort. Taking the accessor as a function POINTER and the
/// column as a value collapses that to one instantiation per item type.
pub fn sortFilteredIndicesAtColumn(
    comptime T: type,
    items: []const T,
    filtered_indices: *std.ArrayListUnmanaged(usize),
    getField: *const fn (*const T, usize) []const u8,
    column: usize,
    ascending: bool,
) void {
    const Ctx = struct {
        items_slice: []const T,
        get: *const fn (*const T, usize) []const u8,
        col: usize,
        asc: bool,

        pub fn lessThan(ctx: @This(), a: usize, b: usize) bool {
            const fa = ctx.get(&ctx.items_slice[a], ctx.col);
            const fb = ctx.get(&ctx.items_slice[b], ctx.col);
            const order = std.mem.order(u8, fa, fb);
            return if (ctx.asc) order == .lt else order == .gt;
        }
    };

    std.sort.pdq(usize, filtered_indices.items, Ctx{
        .items_slice = items,
        .get = getField,
        .col = column,
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

test "runtime-column sort matches the comptime-getter sort exactly" {
    // The runtime variant exists to collapse ~130 KB of per-(view,column) sort
    // instantiations. Behaviour must be identical, so this sorts the same data both
    // ways and compares the resulting index order rather than trusting that it
    // compiled.
    const Row = struct {
        columns: [2][]const u8,
        fn getCol0(self: *const @This()) []const u8 {
            return self.columns[0];
        }
        fn getAt(self: *const @This(), idx: usize) []const u8 {
            return self.columns[idx];
        }
    };

    const rows = [_]Row{
        .{ .columns = .{ "delta", "4" } },
        .{ .columns = .{ "alpha", "1" } },
        .{ .columns = .{ "charlie", "3" } },
        .{ .columns = .{ "bravo", "2" } },
    };

    const a = std.testing.allocator;

    inline for (.{ true, false }) |asc| {
        var comptime_order: std.ArrayListUnmanaged(usize) = .empty;
        defer comptime_order.deinit(a);
        var runtime_order: std.ArrayListUnmanaged(usize) = .empty;
        defer runtime_order.deinit(a);
        for (0..rows.len) |i| {
            try comptime_order.append(a, i);
            try runtime_order.append(a, i);
        }

        sortFilteredIndices(Row, &rows, &comptime_order, Row.getCol0, asc);
        sortFilteredIndicesAtColumn(Row, &rows, &runtime_order, &Row.getAt, 0, asc);

        try std.testing.expectEqualSlices(usize, comptime_order.items, runtime_order.items);
    }

    // And it actually sorts, rather than both agreeing on a no-op.
    var order: std.ArrayListUnmanaged(usize) = .empty;
    defer order.deinit(a);
    for (0..rows.len) |i| try order.append(a, i);
    sortFilteredIndicesAtColumn(Row, &rows, &order, &Row.getAt, 0, true);
    try std.testing.expectEqualStrings("alpha", rows[order.items[0]].columns[0]);
    try std.testing.expectEqualStrings("delta", rows[order.items[3]].columns[0]);

    // A different column must produce a different key, proving `column` is honoured.
    var order2: std.ArrayListUnmanaged(usize) = .empty;
    defer order2.deinit(a);
    for (0..rows.len) |i| try order2.append(a, i);
    sortFilteredIndicesAtColumn(Row, &rows, &order2, &Row.getAt, 1, true);
    try std.testing.expectEqualStrings("1", rows[order2.items[0]].columns[1]);
}
