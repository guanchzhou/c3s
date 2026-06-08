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
// Navigation tests
// =========================================================================

test "navigation: navigateDown from first item moves to second" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    ts.navigateDown();
    try testing.expectEqual(@as(u32, 1), ts.selected_row);
}

test "navigation: navigateDown at last item stays at last" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    ts.gotoBottom();
    try testing.expectEqual(@as(u32, 4), ts.selected_row);
    ts.navigateDown();
    try testing.expectEqual(@as(u32, 4), ts.selected_row);
}

test "navigation: navigateUp from second item moves to first" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    ts.navigateDown();
    try testing.expectEqual(@as(u32, 1), ts.selected_row);
    ts.navigateUp();
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "navigation: navigateUp at first item stays at first" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    ts.navigateUp();
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "navigation: gotoTop resets to 0" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 20);

    ts.gotoBottom();
    try testing.expect(ts.selected_row > 0);
    try testing.expect(ts.scroll_offset > 0);

    ts.gotoTop();
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    try testing.expectEqual(@as(u32, 0), ts.scroll_offset);
}

test "navigation: gotoBottom goes to last item" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    ts.gotoBottom();
    try testing.expectEqual(@as(u32, 19), ts.selected_row);
    try testing.expectEqual(@as(u32, 15), ts.scroll_offset);
}

test "navigation: gotoBottom with empty list does nothing" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    // No items added
    ts.gotoBottom();
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    try testing.expectEqual(@as(u32, 0), ts.scroll_offset);
}

test "navigation: pageDown jumps by visible_rows count" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    ts.pageDown();
    try testing.expectEqual(@as(u32, 5), ts.selected_row);
}

test "navigation: pageUp jumps back by visible_rows count" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    ts.selected_row = 10;
    ts.scroll_offset = 6;
    ts.pageUp();
    try testing.expectEqual(@as(u32, 5), ts.selected_row);
}

test "navigation: pageUp from near top clamps to zero" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 20);

    ts.selected_row = 3;
    ts.scroll_offset = 0;
    ts.pageUp();
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "navigation: navigateDown adjusts scroll_offset when past visible area" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 3;

    try populateTable(&ts, allocator, 10);

    ts.selected_row = 2;
    ts.scroll_offset = 0;
    ts.navigateDown();
    try testing.expectEqual(@as(u32, 3), ts.selected_row);
    try testing.expectEqual(@as(u32, 1), ts.scroll_offset);
}

test "navigation: navigateUp adjusts scroll_offset when above visible area" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 3;

    try populateTable(&ts, allocator, 10);

    ts.selected_row = 5;
    ts.scroll_offset = 5;
    ts.navigateUp();
    try testing.expectEqual(@as(u32, 4), ts.selected_row);
    try testing.expectEqual(@as(u32, 4), ts.scroll_offset);
}

// =========================================================================
// Filtering tests
// =========================================================================

test "filter: applyFilter with empty string shows all items" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "alpha", 1));
    try ts.appendItem(try createTestItem(allocator, "beta", 2));
    try ts.appendItem(try createTestItem(allocator, "gamma", 3));
    try ts.appendItem(try createTestItem(allocator, "delta", 4));
    try ts.appendItem(try createTestItem(allocator, "epsilon", 5));

    try ts.applyFilter("", testMatchFn);
    try testing.expectEqual(@as(usize, 5), ts.filtered_indices.items.len);
}

test "filter: applyFilter matches subset of items" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "apple", 1));
    try ts.appendItem(try createTestItem(allocator, "banana", 2));
    try ts.appendItem(try createTestItem(allocator, "apricot", 3));
    try ts.appendItem(try createTestItem(allocator, "cherry", 4));

    try ts.applyFilter("ap", testMatchFn);
    try testing.expectEqual(@as(usize, 2), ts.filtered_indices.items.len);
    try testing.expectEqual(@as(usize, 0), ts.filtered_indices.items[0]); // apple
    try testing.expectEqual(@as(usize, 2), ts.filtered_indices.items[1]); // apricot
}

test "filter: applyFilter with no matches produces empty filtered list" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "apple", 1));
    try ts.appendItem(try createTestItem(allocator, "banana", 2));
    try ts.appendItem(try createTestItem(allocator, "cherry", 3));

    try ts.applyFilter("xyz", testMatchFn);
    try testing.expectEqual(@as(usize, 0), ts.filtered_indices.items.len);
}

test "filter: applyFilter resets selected_row and scroll_offset" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 20);
    ts.selected_row = 15;
    ts.scroll_offset = 10;

    try ts.applyFilter("item-0", testMatchFn);
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    try testing.expectEqual(@as(u32, 0), ts.scroll_offset);
}

test "filter: filter_text is tracked" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "alpha", 1));

    try testing.expectEqualStrings("", ts.filter_text);

    try ts.applyFilter("alph", testMatchFn);
    try testing.expectEqualStrings("alph", ts.filter_text);

    try ts.applyFilter("", testMatchFn);
    try testing.expectEqualStrings("", ts.filter_text);
}

// =========================================================================
// appendItem / clearItems
// =========================================================================

test "appendItem adds items correctly" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.appendItem(try createTestItem(allocator, "first", 1));
    try ts.appendItem(try createTestItem(allocator, "second", 2));
    try ts.appendItem(try createTestItem(allocator, "third", 3));

    try testing.expectEqual(@as(usize, 3), ts.items.items.len);
    try testing.expectEqualStrings("first", ts.items.items[0].name);
    try testing.expectEqualStrings("second", ts.items.items[1].name);
    try testing.expectEqualStrings("third", ts.items.items[2].name);
}

test "clearItems removes all items and resets error" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "alpha", 1));
    try ts.appendItem(try createTestItem(allocator, "beta", 2));
    try ts.setError("something went wrong");

    try testing.expectEqual(@as(usize, 2), ts.items.items.len);
    try testing.expect(ts.error_message != null);

    ts.clearItems();

    try testing.expectEqual(@as(usize, 0), ts.items.items.len);
    try testing.expect(ts.error_message == null);
}

// =========================================================================
// Error messages
// =========================================================================

test "setError stores error message" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setError("connection refused");

    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("connection refused", ts.error_message.?);
}

test "setError replaces previous error" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setError("first error");
    try testing.expectEqualStrings("first error", ts.error_message.?);

    try ts.setError("second error");
    try testing.expectEqualStrings("second error", ts.error_message.?);
}

test "setErrorFmt formats error message" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setErrorFmt("error {d}: {s}", .{ 404, "not found" });

    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("error 404: not found", ts.error_message.?);
}

test "setConnectionError maps TlsInitializationFailed" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setConnectionError("pods", error.TlsInitializationFailed);
    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("TLS connection failed. Try: C3S_FORCE_PROXY=1 c3s", ts.error_message.?);
}

test "setConnectionError maps ConnectionRefused" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setConnectionError("pods", error.ConnectionRefused);
    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("Connection refused. Is the cluster reachable?", ts.error_message.?);
}

test "setConnectionError maps ConnectionResetByPeer" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setConnectionError("pods", error.ConnectionResetByPeer);
    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("Connection reset. Check cluster status.", ts.error_message.?);
}

test "setConnectionError formats unknown error with resource name" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setConnectionError("deployments", error.OutOfMemory);
    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("Failed to list deployments: error.OutOfMemory", ts.error_message.?);
}

// =========================================================================
// Sorting tests
// =========================================================================

test "toggleSort sets sort column and ascending true" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try testing.expect(ts.sort_column == null);
    ts.toggleSort(3);
    try testing.expectEqual(@as(?u8, 3), ts.sort_column);
    try testing.expect(ts.sort_ascending);
}

test "toggleSort on same column flips ascending" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    ts.toggleSort(2);
    try testing.expect(ts.sort_ascending);
    ts.toggleSort(2);
    try testing.expectEqual(@as(?u8, 2), ts.sort_column);
    try testing.expect(!ts.sort_ascending);
}

test "toggleSort on different column resets to ascending" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    ts.toggleSort(1);
    ts.toggleSort(1);
    try testing.expect(!ts.sort_ascending);

    ts.toggleSort(5);
    try testing.expectEqual(@as(?u8, 5), ts.sort_column);
    try testing.expect(ts.sort_ascending);
}

test "sortBy sorts filtered indices by name ascending" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "cherry", 1));
    try ts.appendItem(try createTestItem(allocator, "apple", 2));
    try ts.appendItem(try createTestItem(allocator, "banana", 3));

    try ts.applyFilter("", testMatchFn);

    ts.sort_ascending = true;
    ts.sortBy(TestItem.getName);

    // After ascending sort: apple(1), banana(2), cherry(0)
    try testing.expectEqual(@as(usize, 1), ts.filtered_indices.items[0]);
    try testing.expectEqual(@as(usize, 2), ts.filtered_indices.items[1]);
    try testing.expectEqual(@as(usize, 0), ts.filtered_indices.items[2]);
}

test "sortBy sorts filtered indices by name descending" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "cherry", 1));
    try ts.appendItem(try createTestItem(allocator, "apple", 2));
    try ts.appendItem(try createTestItem(allocator, "banana", 3));

    try ts.applyFilter("", testMatchFn);

    ts.sort_ascending = false;
    ts.sortBy(TestItem.getName);

    // After descending sort: cherry(0), banana(2), apple(1)
    try testing.expectEqual(@as(usize, 0), ts.filtered_indices.items[0]);
    try testing.expectEqual(@as(usize, 2), ts.filtered_indices.items[1]);
    try testing.expectEqual(@as(usize, 1), ts.filtered_indices.items[2]);
}

// =========================================================================
// Selection tests
// =========================================================================

test "getSelectedItem returns correct item" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    ts.navigateDown();
    ts.navigateDown();
    try testing.expectEqual(@as(u32, 2), ts.selected_row);

    const selected = ts.getSelectedItem();
    try testing.expect(selected != null);
    try testing.expectEqualStrings("item-2", selected.?.name);
}

test "getSelectedItem returns null when empty" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    const selected = ts.getSelectedItem();
    try testing.expect(selected == null);
}

test "getSelectedItem returns null when selected_row out of range" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "only", 1));
    try ts.applyFilter("", testMatchFn);

    ts.selected_row = 99; // out of bounds
    const selected = ts.getSelectedItem();
    try testing.expect(selected == null);
}

test "getVisibleRange returns correct start and end" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    ts.scroll_offset = 3;
    const range = ts.getVisibleRange();
    try testing.expectEqual(@as(u32, 3), range.start);
    try testing.expectEqual(@as(u32, 8), range.end);
}

test "getVisibleRange clamps end to item count" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 100;

    try populateTable(&ts, allocator, 5);

    ts.scroll_offset = 0;
    const range = ts.getVisibleRange();
    try testing.expectEqual(@as(u32, 0), range.start);
    try testing.expectEqual(@as(u32, 5), range.end);
}

test "isSelected returns true for selected row offset" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 10);

    ts.selected_row = 3;
    ts.scroll_offset = 1;

    try testing.expect(ts.isSelected(2)); // 1 + 2 = 3
    try testing.expect(!ts.isSelected(0)); // 1 + 0 = 1 != 3
    try testing.expect(!ts.isSelected(3)); // 1 + 3 = 4 != 3
}

// =========================================================================
// show_all_namespaces toggle
// =========================================================================

test "show_all_namespaces defaults to false" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try testing.expect(!ts.show_all_namespaces);
}

test "show_all_namespaces can be toggled" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    ts.show_all_namespaces = true;
    try testing.expect(ts.show_all_namespaces);
    ts.show_all_namespaces = false;
    try testing.expect(!ts.show_all_namespaces);
}

// =========================================================================
// Row colors tests
// =========================================================================

test "rowColors returns selected colors for selected row" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

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

    const rc = ts.rowColors(0, &colors);
    try testing.expectEqualStrings("sel_fg", rc.fg);
    try testing.expectEqualStrings("sel_bg", rc.bg);
}

test "rowColors returns normal colors for non-selected row" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

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

    const rc = ts.rowColors(1, &colors);
    try testing.expectEqualStrings("fg", rc.fg);
    try testing.expectEqualStrings("bg", rc.bg);
}

// =========================================================================
// Memory tests
// =========================================================================

test "memory: init and deinit with items does not leak" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected in init/deinit test");
        }
    }
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "one", 1));
    try ts.appendItem(try createTestItem(allocator, "two", 2));
    try ts.appendItem(try createTestItem(allocator, "three", 3));
    try ts.applyFilter("", testMatchFn);
    try ts.setError("test error");

    ts.deinit();
}

test "memory: multiple clearItems cycles do not leak" {
    var gpa = std.heap.DebugAllocator(.{}){};
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

    // Cycle 3
    try ts.appendItem(try createTestItem(allocator, "f", 6));
}

// =========================================================================
// handleNavigationKey tests
// =========================================================================

test "handleNavigationKey: j navigates down" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    const result = ts.handleNavigationKey(.{ .char = 'j' });
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 1), ts.selected_row);
}

test "handleNavigationKey: k navigates up" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);
    ts.navigateDown();

    const result = ts.handleNavigationKey(.{ .char = 'k' });
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "handleNavigationKey: g goes to top" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 20);
    ts.gotoBottom();

    const result = ts.handleNavigationKey(.{ .char = 'g' });
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "handleNavigationKey: G goes to bottom" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    const result = ts.handleNavigationKey(.{ .char = 'G' });
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 19), ts.selected_row);
}

test "handleNavigationKey: unhandled key returns null" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    const result = ts.handleNavigationKey(.{ .char = 'z' });
    try testing.expect(result == null);
}

test "handleNavigationKey: d returns request_describe" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    const result = ts.handleNavigationKey(.{ .char = 'd' });
    try testing.expect(result != null);
    try testing.expectEqual(c3s.View.KeyResult.request_describe, result.?);
}

test "handleNavigationKey: y returns request_yaml" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    const result = ts.handleNavigationKey(.{ .char = 'y' });
    try testing.expect(result != null);
    try testing.expectEqual(c3s.View.KeyResult.request_yaml, result.?);
}

test "handleNavigationKey: colon returns request_command_palette" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    const result = ts.handleNavigationKey(.{ .char = ':' });
    try testing.expect(result != null);
    try testing.expectEqual(c3s.View.KeyResult.request_command_palette, result.?);
}

test "handleNavigationKey: slash returns request_filter" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    const result = ts.handleNavigationKey(.{ .char = '/' });
    try testing.expect(result != null);
    try testing.expectEqual(c3s.View.KeyResult.request_filter, result.?);
}

test "handleNavigationKey: arrow down navigates down" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    const result = ts.handleNavigationKey(.down);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 1), ts.selected_row);
}

test "handleNavigationKey: arrow up navigates up" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);
    ts.navigateDown();

    const result = ts.handleNavigationKey(.up);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

// =========================================================================
// Loading state
// =========================================================================

test "loading defaults to false" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try testing.expect(!ts.loading);
}

test "loading can be set" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    ts.loading = true;
    try testing.expect(ts.loading);
    ts.loading = false;
    try testing.expect(!ts.loading);
}
