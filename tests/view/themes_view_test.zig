// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for ThemesView
//
// ThemesView scans the real filesystem (XDG skins dir, exe-relative skins,
// CWD/skins) for available themes, so the exact item count is environment
// dependent. These tests assert structure and bounds-safe behavior rather than
// a fixed number of injected mock themes (the old mock-injection API is gone).

const std = @import("std");
const testing = std.testing;
const src = @import("src");
const ThemesView = src.ThemesView;
const theme_loader = src.theme_loader;

test "themes_view: init and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var themes_view = try ThemesView.init(allocator, "tokyo-night", &theme);
    defer themes_view.deinit();

    // selected_row stays within bounds (or 0 when no themes are discovered).
    if (themes_view.table.items.items.len == 0) {
        try testing.expectEqual(@as(u32, 0), themes_view.table.selected_row);
    } else {
        try testing.expect(themes_view.table.selected_row < themes_view.table.items.items.len);
    }
    try testing.expectEqual(@as(u32, 0), themes_view.table.scroll_offset);
}

test "themes_view: navigation functions" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var themes_view = try ThemesView.init(allocator, "tokyo-night", &theme);
    defer themes_view.deinit();

    // Navigation operates on filtered_indices via the underlying TableState and
    // must be bounds-safe regardless of how many themes exist on disk.
    const count = themes_view.table.filtered_indices.items.len;

    themes_view.table.gotoTop();
    try testing.expectEqual(@as(u32, 0), themes_view.table.selected_row);

    // navigateDown should never exceed the last valid row.
    themes_view.table.navigateDown();
    if (count > 1) {
        try testing.expectEqual(@as(u32, 1), themes_view.table.selected_row);
    } else {
        try testing.expectEqual(@as(u32, 0), themes_view.table.selected_row);
    }

    // navigateUp should never go below 0.
    themes_view.table.navigateUp();
    try testing.expectEqual(@as(u32, 0), themes_view.table.selected_row);
    themes_view.table.navigateUp();
    try testing.expectEqual(@as(u32, 0), themes_view.table.selected_row);
}

test "themes_view: goto functions" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var themes_view = try ThemesView.init(allocator, "tokyo-night", &theme);
    defer themes_view.deinit();

    const count = themes_view.table.filtered_indices.items.len;

    themes_view.table.gotoBottom();
    if (count > 0) {
        try testing.expectEqual(@as(u32, @intCast(count - 1)), themes_view.table.selected_row);
    } else {
        try testing.expectEqual(@as(u32, 0), themes_view.table.selected_row);
    }

    themes_view.table.gotoTop();
    try testing.expectEqual(@as(u32, 0), themes_view.table.selected_row);
}

test "themes_view: filter functionality" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var themes_view = try ThemesView.init(allocator, "tokyo-night", &theme);
    defer themes_view.deinit();

    const total = themes_view.table.items.items.len;

    // An empty filter matches every theme.
    try themes_view.applyFilter("");
    try testing.expectEqual(total, themes_view.table.filtered_indices.items.len);

    // A narrow filter never matches more than the total set.
    try themes_view.applyFilter("tokyo");
    try testing.expect(themes_view.table.filtered_indices.items.len <= total);

    // A filter that cannot match anything yields zero results.
    try themes_view.applyFilter("zzz-no-such-theme-zzz");
    try testing.expectEqual(@as(usize, 0), themes_view.table.filtered_indices.items.len);

    // Clearing the filter restores the full set.
    try themes_view.applyFilter("");
    try testing.expectEqual(total, themes_view.table.filtered_indices.items.len);
}

test "themes_view: page up/down" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var themes_view = try ThemesView.init(allocator, "tokyo-night", &theme);
    defer themes_view.deinit();

    themes_view.table.visible_rows = 5; // Simulate visible rows
    themes_view.table.gotoTop();

    // pageDown/pageUp must stay in bounds and return to the top.
    themes_view.table.pageDown();
    if (themes_view.table.filtered_indices.items.len > 1) {
        try testing.expect(themes_view.table.selected_row < themes_view.table.filtered_indices.items.len);
    }

    themes_view.table.pageUp();
    try testing.expectEqual(@as(u32, 0), themes_view.table.selected_row);
}
