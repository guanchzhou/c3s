const std = @import("std");
const testing = std.testing;
const Header = @import("c3s").Header;
const Terminal = @import("c3s").Terminal;
const theme_loader = @import("c3s").theme_loader;

test "header initialization and cleanup with debug mode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try allocator.create(theme_loader.ThemeColors);
    theme.* = try theme_loader.defaultTheme(allocator);
    defer {
        theme_loader.deinitTheme(theme);
        allocator.destroy(theme);
    }

    var header = try Header.init(allocator, theme, true); // debug = true
    defer header.deinit();

    // Test that header was initialized with debug values
    try testing.expect(std.mem.eql(u8, header.context, "rancher-desktop [RW]"));
    try testing.expect(std.mem.eql(u8, header.cluster, "rancher-desktop"));
    try testing.expect(std.mem.eql(u8, header.user, "rancher-desktop"));
    try testing.expect(std.mem.eql(u8, header.k8s_version, "v1.33.3+k3s1"));
    try testing.expect(header.cpu_usage == 2);
    try testing.expect(header.mem_usage == 27);
}

test "header initialization without debug mode" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try allocator.create(theme_loader.ThemeColors);
    theme.* = try theme_loader.defaultTheme(allocator);
    defer {
        theme_loader.deinitTheme(theme);
        allocator.destroy(theme);
    }

    var header = try Header.init(allocator, theme, false); // debug = false
    defer header.deinit();

    // Test that header was initialized with n/a values
    try testing.expect(std.mem.eql(u8, header.context, "n/a"));
    try testing.expect(std.mem.eql(u8, header.cluster, "n/a"));
    try testing.expect(std.mem.eql(u8, header.user, "n/a"));
    try testing.expect(std.mem.eql(u8, header.k8s_version, "n/a"));
    try testing.expect(std.mem.eql(u8, header.cpu_str, "n/a"));
    try testing.expect(std.mem.eql(u8, header.mem_str, "n/a"));
    try testing.expect(header.cpu_usage == 0);
    try testing.expect(header.mem_usage == 0);
}

test "header rendering" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try allocator.create(theme_loader.ThemeColors);
    theme.* = try theme_loader.defaultTheme(allocator);
    defer {
        theme_loader.deinitTheme(theme);
        allocator.destroy(theme);
    }

    var header = try Header.init(allocator, theme, true);
    defer header.deinit();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test that rendering doesn't crash
    try header.render(&terminal, 0, 0, 80, 8);
    
    // Test rendering at different positions
    try header.render(&terminal, 10, 5, 100, 8);
    
    // Test rendering with different sizes
    try header.render(&terminal, 0, 0, 120, 10);
}

test "header data validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try allocator.create(theme_loader.ThemeColors);
    theme.* = try theme_loader.defaultTheme(allocator);
    defer {
        theme_loader.deinitTheme(theme);
        allocator.destroy(theme);
    }

    var header = try Header.init(allocator, theme, true);
    defer header.deinit();

    // Test that all string fields are non-empty
    try testing.expect(header.context.len > 0);
    try testing.expect(header.cluster.len > 0);
    try testing.expect(header.user.len > 0);
    try testing.expect(header.k9s_version.len > 0);
    try testing.expect(header.k8s_version.len > 0);
    
    // Test that numeric values are within reasonable ranges
    try testing.expect(header.cpu_usage >= 0 and header.cpu_usage <= 100);
    try testing.expect(header.mem_usage >= 0 and header.mem_usage <= 100);
}

test "header memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try allocator.create(theme_loader.ThemeColors);
    theme.* = try theme_loader.defaultTheme(allocator);
    defer {
        theme_loader.deinitTheme(theme);
        allocator.destroy(theme);
    }

    // Test multiple initialization and cleanup cycles
    for (0..10) |_| {
        var header = try Header.init(allocator, theme, true);
        header.deinit();
    }
    
    // Test that no memory leaks occurred
    const allocated = gpa.deinit();
    try testing.expect(allocated == .ok);
}
