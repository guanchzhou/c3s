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