// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Comprehensive unit tests for TableState generic component.

const std = @import("std");
const testing = std.testing;
const c3s = @import("c3s");
const TableState = c3s.TableState;
const theme_loader = c3s.theme_loader;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const TestItem = struct {
    name: []const u8,
    value: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TestItem) void {
        self.allocator.free(self.name);
    }

    fn getName(self: *const TestItem) []const u8 {
        return self.name;
    }
};

fn createTestItem(allocator: std.mem.Allocator, name: []const u8, value: u32) !TestItem {
    return TestItem{
        .name = try allocator.dupe(u8, name),
        .value = value,
        .allocator = allocator,
    };
}

fn testMatchFn(item: *const TestItem, filter: []const u8) bool {
    return std.mem.indexOf(u8, item.name, filter) != null;
}

/// Populate a TableState with N items named "item-0" .. "item-(N-1)" and
/// apply an empty filter so that filtered_indices is fully populated.
fn populateTable(ts: *TableState(TestItem), allocator: std.mem.Allocator, count: u32) !void {
    for (0..count) |i| {
        var buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "item-{d}", .{i});
        try ts.appendItem(try createTestItem(allocator, name, @intCast(i)));
    }
    try ts.applyFilter("", testMatchFn);
}

// =========================================================================
// Navigation tests (1-10)
// =========================================================================

// 1. navigateDown from first item moves to second
test "navigation: navigateDown from first item moves to second" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    // Arrange: selected_row starts at 0
    try testing.expectEqual(@as(u32, 0), ts.selected_row);

    // Act
    ts.navigateDown();

    // Assert
    try testing.expectEqual(@as(u32, 1), ts.selected_row);
}

// 2. navigateDown at last item stays at last
test "navigation: navigateDown at last item stays at last" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    // Arrange: go to last item
    ts.gotoBottom();
    try testing.expectEqual(@as(u32, 4), ts.selected_row);

    // Act
    ts.navigateDown();

    // Assert: should stay at 4
    try testing.expectEqual(@as(u32, 4), ts.selected_row);
}

// 3. navigateUp from second item moves to first
test "navigation: navigateUp from second item moves to first" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    // Arrange: move to second item
    ts.navigateDown();
    try testing.expectEqual(@as(u32, 1), ts.selected_row);

    // Act
    ts.navigateUp();

    // Assert
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

// 4. navigateUp at first item stays at first
test "navigation: navigateUp at first item stays at first" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    // Arrange: already at row 0
    try testing.expectEqual(@as(u32, 0), ts.selected_row);

    // Act
    ts.navigateUp();

    // Assert
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

// 5. gotoTop resets to 0
test "navigation: gotoTop resets to 0" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 20);

    // Arrange: navigate somewhere in the middle
    ts.gotoBottom();
    try testing.expect(ts.selected_row > 0);
    try testing.expect(ts.scroll_offset > 0);

    // Act
    ts.gotoTop();

    // Assert
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    try testing.expectEqual(@as(u32, 0), ts.scroll_offset);
}

// 6. gotoBottom goes to last item
test "navigation: gotoBottom goes to last item" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    // Act
    ts.gotoBottom();

    // Assert
    try testing.expectEqual(@as(u32, 19), ts.selected_row);
    // Scroll offset should ensure the last item is visible
    // selected_row (19) >= visible_rows (5), so offset = 19 - 5 + 1 = 15
    try testing.expectEqual(@as(u32, 15), ts.scroll_offset);
}

// 7. pageDown jumps by visible_rows count
test "navigation: pageDown jumps by visible_rows count" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    // Arrange: at row 0
    try testing.expectEqual(@as(u32, 0), ts.selected_row);

    // Act
    ts.pageDown();

    // Assert: should jump by visible_rows (5)
    try testing.expectEqual(@as(u32, 5), ts.selected_row);
}

// 8. pageUp jumps back by visible_rows count
test "navigation: pageUp jumps back by visible_rows count" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    // Arrange: go to row 10
    ts.selected_row = 10;
    ts.scroll_offset = 6;

    // Act
    ts.pageUp();

    // Assert: should jump back by visible_rows (5)
    try testing.expectEqual(@as(u32, 5), ts.selected_row);
}

// 9. navigateDown adjusts scroll_offset when past visible area
test "navigation: navigateDown adjusts scroll_offset when past visible area" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 3;

    try populateTable(&ts, allocator, 10);

    // Arrange: position at last visible row (row 2 with offset 0, visible_rows 3)
    ts.selected_row = 2;
    ts.scroll_offset = 0;

    // Act: navigate down past visible area
    ts.navigateDown();

    // Assert: scroll_offset should have incremented
    try testing.expectEqual(@as(u32, 3), ts.selected_row);
    try testing.expectEqual(@as(u32, 1), ts.scroll_offset);
}

// 10. navigateUp adjusts scroll_offset when above visible area
test "navigation: navigateUp adjusts scroll_offset when above visible area" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 3;

    try populateTable(&ts, allocator, 10);

    // Arrange: scroll_offset is 5, selected_row is 5 (at top of visible area)
    ts.selected_row = 5;
    ts.scroll_offset = 5;

    // Act: navigate up above visible area
    ts.navigateUp();

    // Assert: scroll_offset should follow selected_row
    try testing.expectEqual(@as(u32, 4), ts.selected_row);
    try testing.expectEqual(@as(u32, 4), ts.scroll_offset);
}

// =========================================================================
// Filtering tests (11-15)
// =========================================================================

// 11. applyFilter with empty string shows all items
test "filter: applyFilter with empty string shows all items" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    // Arrange: add 5 items
    try ts.appendItem(try createTestItem(allocator, "alpha", 1));
    try ts.appendItem(try createTestItem(allocator, "beta", 2));
    try ts.appendItem(try createTestItem(allocator, "gamma", 3));
    try ts.appendItem(try createTestItem(allocator, "delta", 4));
    try ts.appendItem(try createTestItem(allocator, "epsilon", 5));

    // Act
    try ts.applyFilter("", testMatchFn);

    // Assert
    try testing.expectEqual(@as(usize, 5), ts.filtered_indices.items.len);
}

// 12. applyFilter matches subset of items
test "filter: applyFilter matches subset of items" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    // Arrange
    try ts.appendItem(try createTestItem(allocator, "apple", 1));
    try ts.appendItem(try createTestItem(allocator, "banana", 2));
    try ts.appendItem(try createTestItem(allocator, "apricot", 3));
    try ts.appendItem(try createTestItem(allocator, "cherry", 4));

    // Act: filter for "ap"
    try ts.applyFilter("ap", testMatchFn);

    // Assert: should match "apple" and "apricot"
    try testing.expectEqual(@as(usize, 2), ts.filtered_indices.items.len);
    try testing.expectEqual(@as(usize, 0), ts.filtered_indices.items[0]); // apple
    try testing.expectEqual(@as(usize, 2), ts.filtered_indices.items[1]); // apricot
}

// 13. applyFilter with no matches produces empty filtered list
test "filter: applyFilter with no matches produces empty filtered list" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    // Arrange
    try ts.appendItem(try createTestItem(allocator, "apple", 1));
    try ts.appendItem(try createTestItem(allocator, "banana", 2));
    try ts.appendItem(try createTestItem(allocator, "cherry", 3));

    // Act
    try ts.applyFilter("xyz", testMatchFn);

    // Assert
    try testing.expectEqual(@as(usize, 0), ts.filtered_indices.items.len);
}

// 14. applyFilter resets selected_row and scroll_offset
test "filter: applyFilter resets selected_row and scroll_offset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    // Arrange: add items and navigate away from top
    try populateTable(&ts, allocator, 20);
    ts.selected_row = 15;
    ts.scroll_offset = 10;

    // Act: apply a filter that won't include the previously selected item's original index
    try ts.applyFilter("item-0", testMatchFn);

    // Assert: selected_row and scroll_offset should be reset to 0
    // (because the previously selected item "item-15" is no longer in the filtered list)
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    try testing.expectEqual(@as(u32, 0), ts.scroll_offset);
}

// 15. clearItems removes all items and resets error
test "filter: clearItems removes all items and resets error" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    // Arrange
    try ts.appendItem(try createTestItem(allocator, "alpha", 1));
    try ts.appendItem(try createTestItem(allocator, "beta", 2));
    try ts.setError("something went wrong");

    try testing.expectEqual(@as(usize, 2), ts.items.items.len);
    try testing.expect(ts.error_message != null);

    // Act
    ts.clearItems();

    // Assert
    try testing.expectEqual(@as(usize, 0), ts.items.items.len);
    try testing.expect(ts.error_message == null);
}

// =========================================================================
// Sorting tests (16-18)
// =========================================================================

// 16. toggleSort sets sort column and ascending=true
test "sort: toggleSort sets sort column and ascending true" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    // Arrange: no sort column set
    try testing.expect(ts.sort_column == null);

    // Act
    ts.toggleSort(3);

    // Assert
    try testing.expectEqual(@as(?u8, 3), ts.sort_column);
    try testing.expect(ts.sort_ascending);
}

// 17. toggleSort on same column flips ascending
test "sort: toggleSort on same column flips ascending" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    // Arrange: set sort on column 2
    ts.toggleSort(2);
    try testing.expect(ts.sort_ascending);

    // Act: toggle same column
    ts.toggleSort(2);

    // Assert: should flip to descending
    try testing.expectEqual(@as(?u8, 2), ts.sort_column);
    try testing.expect(!ts.sort_ascending);
}

// 18. toggleSort on different column resets to ascending
test "sort: toggleSort on different column resets to ascending" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    // Arrange: set sort on column 1 and flip to descending
    ts.toggleSort(1);
    ts.toggleSort(1);
    try testing.expect(!ts.sort_ascending);

    // Act: switch to column 5
    ts.toggleSort(5);

    // Assert: new column, ascending reset
    try testing.expectEqual(@as(?u8, 5), ts.sort_column);
    try testing.expect(ts.sort_ascending);
}

// =========================================================================
// Selection tests (19-22)
// =========================================================================

// 19. getSelectedItem returns correct item
test "selection: getSelectedItem returns correct item" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    // Arrange: navigate to third item
    ts.navigateDown();
    ts.navigateDown();
    try testing.expectEqual(@as(u32, 2), ts.selected_row);

    // Act
    const selected = ts.getSelectedItem();

    // Assert
    try testing.expect(selected != null);
    try testing.expectEqualStrings("item-2", selected.?.name);
}

// 20. getSelectedItem returns null when empty
test "selection: getSelectedItem returns null when empty" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    // Act: no items at all
    const selected = ts.getSelectedItem();

    // Assert
    try testing.expect(selected == null);
}

// 21. getVisibleRange returns correct start/end
test "selection: getVisibleRange returns correct start and end" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    // Arrange: set scroll_offset to 3
    ts.scroll_offset = 3;

    // Act
    const range = ts.getVisibleRange();

    // Assert: start=3, end=min(3+5, 20) = 8
    try testing.expectEqual(@as(u32, 3), range.start);
    try testing.expectEqual(@as(u32, 8), range.end);
}

// 22. isSelected returns true for selected row offset
test "selection: isSelected returns true for selected row offset" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 10);

    // Arrange: selected_row = 3, scroll_offset = 1
    ts.selected_row = 3;
    ts.scroll_offset = 1;

    // Act / Assert
    // display_offset 2 means scroll_offset(1) + 2 = 3 == selected_row
    try testing.expect(ts.isSelected(2));
    // display_offset 0 means scroll_offset(1) + 0 = 1 != 3
    try testing.expect(!ts.isSelected(0));
    // display_offset 3 means scroll_offset(1) + 3 = 4 != 3
    try testing.expect(!ts.isSelected(3));
}

// =========================================================================
// Status tests (23-25)
// =========================================================================

// 23. setError stores error message
test "status: setError stores error message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    // Act
    try ts.setError("connection refused");

    // Assert
    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("connection refused", ts.error_message.?);
}

// 24. setErrorFmt formats error message
test "status: setErrorFmt formats error message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    // Act
    try ts.setErrorFmt("error {d}: {s}", .{ 404, "not found" });

    // Assert
    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("error 404: not found", ts.error_message.?);
}

// 25. clearItems clears error message
test "status: clearItems clears error message" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    // Arrange
    try ts.setError("something bad");
    try testing.expect(ts.error_message != null);

    // Act
    ts.clearItems();

    // Assert
    try testing.expect(ts.error_message == null);
}

// =========================================================================
// Row colors tests (26-27)
// =========================================================================

// 26. rowColors returns selected colors for selected row
test "row_colors: returns selected colors for selected row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    // Arrange: selected_row = 0, scroll_offset = 0
    // display_offset 0 => scroll_offset(0) + 0 = 0 == selected_row(0)
    const colors = theme_loader.ThemeColors{
        .main_bg = "bg",
        .main_fg = "fg",
        .title = "",
        .hi_fg = "",
        .selected_bg = "sel_bg",
        .selected_fg = "sel_fg",
        .inactive_fg = "",
        .proc_box = "",
        .div_line = "",
        .status_running = "",
        .status_pending = "",
        .status_failed = "",
        .status_succeeded = "",
        .key_highlight = "",
        .title_highlight = "",
        .app_name = "",
        .prompt_fg = "",
        .prompt_bg = "",
        .allocator = allocator,
    };

    // Act
    const rc = ts.rowColors(0, &colors);

    // Assert
    try testing.expectEqualStrings("sel_fg", rc.fg);
    try testing.expectEqualStrings("sel_bg", rc.bg);
}

// 27. rowColors returns normal colors for non-selected row
test "row_colors: returns normal colors for non-selected row" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    // Arrange: selected_row = 0, scroll_offset = 0
    // display_offset 1 => scroll_offset(0) + 1 = 1 != selected_row(0)
    const colors = theme_loader.ThemeColors{
        .main_bg = "bg",
        .main_fg = "fg",
        .title = "",
        .hi_fg = "",
        .selected_bg = "sel_bg",
        .selected_fg = "sel_fg",
        .inactive_fg = "",
        .proc_box = "",
        .div_line = "",
        .status_running = "",
        .status_pending = "",
        .status_failed = "",
        .status_succeeded = "",
        .key_highlight = "",
        .title_highlight = "",
        .app_name = "",
        .prompt_fg = "",
        .prompt_bg = "",
        .allocator = allocator,
    };

    // Act
    const rc = ts.rowColors(1, &colors);

    // Assert
    try testing.expectEqualStrings("fg", rc.fg);
    try testing.expectEqualStrings("bg", rc.bg);
}

// =========================================================================
// Memory tests (28-29)
// =========================================================================

// 28. init/deinit with items doesn't leak
test "memory: init and deinit with items does not leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected in init/deinit test");
        }
    }
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    ts.visible_rows = 10;

    // Add items (each allocates a name string)
    try ts.appendItem(try createTestItem(allocator, "one", 1));
    try ts.appendItem(try createTestItem(allocator, "two", 2));
    try ts.appendItem(try createTestItem(allocator, "three", 3));
    try ts.applyFilter("", testMatchFn);

    // Also set an error to exercise that path
    try ts.setError("test error");

    // deinit should free everything: items, filtered_indices, error_message
    ts.deinit();
}

// 29. multiple clearItems cycles don't leak
test "memory: multiple clearItems cycles do not leak" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected in clearItems cycle test");
        }
    }
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    // Cycle 1
    try ts.appendItem(try createTestItem(allocator, "a", 1));
    try ts.appendItem(try createTestItem(allocator, "b", 2));
    try ts.setError("error 1");
    ts.clearItems();

    try testing.expectEqual(@as(usize, 0), ts.items.items.len);
    try testing.expect(ts.error_message == null);

    // Cycle 2
    try ts.appendItem(try createTestItem(allocator, "c", 3));
    try ts.appendItem(try createTestItem(allocator, "d", 4));
    try ts.appendItem(try createTestItem(allocator, "e", 5));
    try ts.setError("error 2");
    ts.clearItems();

    try testing.expectEqual(@as(usize, 0), ts.items.items.len);
    try testing.expect(ts.error_message == null);

    // Cycle 3: add items without error, ensure deinit handles empty error_message
    try ts.appendItem(try createTestItem(allocator, "f", 6));
}
