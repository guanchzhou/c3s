const std = @import("std");
const testing = std.testing;
const HelpView = @import("src").HelpView;
const theme_loader = @import("src").theme_loader;

test "HelpView initialization" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var help_view = try HelpView.init(allocator, &theme);
    defer help_view.deinit();

    // View should be created successfully
    const view = help_view.createView();
    try testing.expect(std.mem.eql(u8, view.getName(), "help"));
}

test "HelpView implements View interface" {
    const allocator = testing.allocator;
    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var help_view = try HelpView.init(allocator, &theme);
    defer help_view.deinit();

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
    defer help_view.deinit();

    const view = help_view.createView();
    try testing.expect(std.mem.eql(u8, view.getName(), "help"));
}
