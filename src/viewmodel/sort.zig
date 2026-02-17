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
