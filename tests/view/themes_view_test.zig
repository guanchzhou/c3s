// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for ThemesView

const std = @import("std");
const testing = std.testing;
const ThemesView = @import("../../src/view/themes_view.zig").ThemesView;
const theme_loader = @import("../../src/model/theme_loader.zig");

test "themes_view: init and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(theme);

    var themes_view = try ThemesView.init(allocator, &.{}, &theme);
    defer themes_view.cleanup();

    try testing.expect(themes_view.selected_row == 0);
    try testing.expect(themes_view.scroll_offset == 0);
}

test "themes_view: navigation functions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(theme);

    // Create mock theme names for testing
    const mock_themes = [_][]const u8{ "theme1", "theme2", "theme3" };
    
    var themes_view = try ThemesView.init(allocator, &mock_themes, &theme);
    defer themes_view.cleanup();

    // Test navigation
    try testing.expectEqual(@as(u32, 0), themes_view.selected_row);
    
    try themes_view.navigateDown();
    try testing.expectEqual(@as(u32, 1), themes_view.selected_row);
    
    try themes_view.navigateDown();
    try testing.expectEqual(@as(u32, 2), themes_view.selected_row);
    
    // Should not go beyond last item
    try themes_view.navigateDown();
    try testing.expectEqual(@as(u32, 2), themes_view.selected_row);
    
    try themes_view.navigateUp();
    try testing.expectEqual(@as(u32, 1), themes_view.selected_row);
    
    try themes_view.navigateUp();
    try testing.expectEqual(@as(u32, 0), themes_view.selected_row);
    
    // Should not go below 0
    try themes_view.navigateUp();
    try testing.expectEqual(@as(u32, 0), themes_view.selected_row);
}

test "themes_view: goto functions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(theme);

    const mock_themes = [_][]const u8{ "t1", "t2", "t3", "t4", "t5" };
    
    var themes_view = try ThemesView.init(allocator, &mock_themes, &theme);
    defer themes_view.cleanup();

    try themes_view.gotoBottom();
    try testing.expectEqual(@as(u32, 4), themes_view.selected_row);
    
    try themes_view.gotoTop();
    try testing.expectEqual(@as(u32, 0), themes_view.selected_row);
}

test "themes_view: filter functionality" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(theme);

    const mock_themes = [_][]const u8{ "dracula", "monokai", "nord", "tokyo-night" };
    
    var themes_view = try ThemesView.init(allocator, &mock_themes, &theme);
    defer themes_view.cleanup();

    // Filter for "tokyo"
    try themes_view.applyFilter("tokyo");
    try testing.expectEqual(@as(usize, 1), themes_view.filtered_indices.items.len);
    
    // Filter for "o" (should match monokai, nord, tokyo-night)
    try themes_view.applyFilter("o");
    try testing.expectEqual(@as(usize, 3), themes_view.filtered_indices.items.len);
    
    // Clear filter
    try themes_view.applyFilter("");
    try testing.expectEqual(@as(usize, 4), themes_view.filtered_indices.items.len);
}

test "themes_view: page up/down" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(theme);

    const mock_themes = [_][]const u8{ "t1", "t2", "t3", "t4", "t5", "t6", "t7", "t8", "t9", "t10" };
    
    var themes_view = try ThemesView.init(allocator, &mock_themes, &theme);
    defer themes_view.cleanup();

    themes_view.visible_rows = 5; // Simulate visible rows
    
    try themes_view.pageDown();
    try testing.expect(themes_view.selected_row > 0);
    
    try themes_view.pageUp();
    try testing.expectEqual(@as(u32, 0), themes_view.selected_row);
}
