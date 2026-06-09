const std = @import("std");
const testing = std.testing;
const Footer = @import("src").Footer;
const Terminal = @import("src").Terminal;
const theme_loader = @import("src").theme_loader;

test "footer initialization and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var footer = try Footer.init(allocator, &theme);
    defer footer.deinit();

    // Test that footer was initialized with default values
    try testing.expect(std.mem.eql(u8, footer.current_resource, "pod"));
}

test "footer rendering" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var footer = try Footer.init(allocator, &theme);
    defer footer.deinit();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test that rendering doesn't crash
    try footer.render(&terminal, 0, 0, 80, 1);

    // Test rendering at different positions
    try footer.render(&terminal, 10, 5, 100, 1);

    // Test rendering with different sizes
    try footer.render(&terminal, 0, 0, 120, 1);
}

test "footer data validation" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var footer = try Footer.init(allocator, &theme);
    defer footer.deinit();

    // Test that current_resource is non-empty
    try testing.expect(footer.current_resource.len > 0);
}

test "footer memory management" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    // Test multiple initialization and cleanup cycles
    for (0..10) |_| {
        var footer = try Footer.init(allocator, &theme);
        footer.deinit();
    }

    // No explicit gpa.deinit() here: the deferred gpa.deinit() runs after the
    // theme's defer frees its allocation, and DebugAllocator reports any leak
    // from the footer init/deinit cycles at that point.
}
