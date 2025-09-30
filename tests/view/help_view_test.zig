const std = @import("std");
const testing = std.testing;
const HelpView = @import("../src/view/help_view.zig").HelpView;
const theme_loader = @import("../src/model/theme_loader.zig");

test "HelpView initialization" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));
    
    var help_view = try HelpView.init(allocator, &theme);
    defer help_view.cleanup();
    
    // View should be created successfully
    const view = help_view.createView();
    try testing.expect(std.mem.eql(u8, view.getName(), "help"));
}

test "HelpView implements View interface" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));
    
    var help_view = try HelpView.init(allocator, &theme);
    defer help_view.cleanup();
    
    const view = help_view.createView();
    
    // Test getName
    const name = view.getName();
    try testing.expect(name.len > 0);
    
    // Test onShow and onHide don't crash
    view.onShow();
    view.onHide();
}

test "HelpView getName returns help" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));
    
    var help_view = try HelpView.init(allocator, &theme);
    defer help_view.cleanup();
    
    try testing.expect(std.mem.eql(u8, help_view.getName(), "help"));
}
