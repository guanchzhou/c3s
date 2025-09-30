const std = @import("std");
const testing = std.testing;
const theme_loader = @import("theme_loader");

test "default theme loads successfully" {
    const allocator = testing.allocator;
    
    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);
    
    // Verify all color fields are allocated and non-empty
    try testing.expect(theme.main_bg.len > 0);
    try testing.expect(theme.main_fg.len > 0);
    try testing.expect(theme.title.len > 0);
    try testing.expect(theme.hi_fg.len > 0);
    try testing.expect(theme.selected_bg.len > 0);
    try testing.expect(theme.selected_fg.len > 0);
    try testing.expect(theme.proc_box.len > 0);
    try testing.expect(theme.div_line.len > 0);
}

test "load tokyo-night skin" {
    const allocator = testing.allocator;
    
    var theme = try theme_loader.loadTheme(allocator, "tokyo-night");
    defer theme_loader.deinitTheme(&theme);
    
    // Verify theme loaded
    try testing.expect(theme.main_fg.len > 0);
    try testing.expect(theme.hi_fg.len > 0);
}

test "load non-existent skin falls back to default" {
    const allocator = testing.allocator;
    
    var theme = try theme_loader.loadTheme(allocator, "nonexistent-theme-12345");
    defer theme_loader.deinitTheme(&theme);
    
    // Should load default theme without error
    try testing.expect(theme.main_fg.len > 0);
}

test "deinitTheme frees all allocations" {
    const allocator = testing.allocator;
    
    var theme = try theme_loader.defaultTheme(allocator);
    theme_loader.deinitTheme(&theme);
    
    // If there were leaks, the testing allocator would catch them
}
