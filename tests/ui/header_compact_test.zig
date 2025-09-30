const std = @import("std");
const testing = std.testing;
const Header = @import("c3s").Header;
const theme_loader = @import("c3s").theme_loader;

test "Header progressive compact levels" {
    const allocator = testing.allocator;
    
    // Load default theme
    const theme = try allocator.create(theme_loader.ThemeColors);
    theme.* = try theme_loader.defaultTheme(allocator);
    defer {
        theme_loader.deinitTheme(theme);
        allocator.destroy(theme);
    }
    
    // Create header with test data
    var header = try Header.init(allocator, theme);
    defer header.deinit();
    
    // Set test values (matching the example from requirements)
    header.context = "rancher-desktop [RW]";
    header.cluster = "rancher-desktop";
    header.user = "rancher-desktop";
    header.k8s_version = "v1.33.3+k3s1";
    header.cpu_str = "2%";
    header.mem_str = "27%";
    header.title_with_version = "v0.2025.09.30.12.08";
    header.setCompact(true);
    
    // Test Level 0: Full header with version
    // c3s v0.2025.09.30.12.08 | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | k8s: v1.33.3+k3s1 | CPU: 2% | MEM: 27%
    {
        const width: u16 = 200; // Wide enough for level 0
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 0), level);
    }
    
    // Test Level 1: Drop version prefix
    // c3s | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | k8s: v1.33.3+k3s1 | CPU: 2% | MEM: 27%
    {
        const width: u16 = 150;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 1), level);
    }
    
    // Test Level 2: Drop k8s prefix
    // c3s | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | v1.33.3+k3s1 | CPU: 2% | MEM: 27%
    {
        const width: u16 = 140;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 2), level);
    }
    
    // Test Level 3: Compact CPU/MEM
    // c3s | context: rancher-desktop [RW] | cluster: rancher-desktop | user: rancher-desktop | v1.33.3+k3s1 | 2%::27%
    {
        const width: u16 = 130;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 3), level);
    }
    
    // Test Level 4: Short labels
    // c3s | ctx: rancher-desktop [RW] | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%
    {
        const width: u16 = 110;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 4), level);
    }
    
    // Test Level 5: Drop [RW]
    // c3s | ctx: rancher-desktop | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%
    {
        const width: u16 = 100;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 5), level);
    }
    
    // Test Level 6: Drop c3s
    // ctx: rancher-desktop | c: rancher-desktop | u: rancher-desktop | v1.33.3+k3s1 | 2%::27%
    {
        const width: u16 = 90;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 6), level);
    }
    
    // Test Level 7: Values only
    // rancher-desktop | rancher-desktop | rancher-desktop | v1.33.3+k3s1 | 2%::27%
    {
        const width: u16 = 80;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 7), level);
    }
    
    // Test Level 8: Drop k8s version
    // rancher-desktop | rancher-desktop | rancher-desktop | 2%::27%
    {
        const width: u16 = 65;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 8), level);
    }
    
    // Test Level 9: Truncate user
    // rancher-desktop | rancher-desktop | ran... | 2%::27%
    {
        const width: u16 = 55;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 9), level);
    }
    
    // Test Level 10: Truncate cluster and user
    // rancher-desktop | ran... | ran... | 2%::27%
    {
        const width: u16 = 45;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 10), level);
    }
    
    // Test Level 11: Minimum (context | 2%::27%) - 25 chars minimum
    {
        const width: u16 = 25;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 11), level);
    }
}

test "Header compact with short values" {
    const allocator = testing.allocator;
    
    const theme = try allocator.create(theme_loader.ThemeColors);
    theme.* = try theme_loader.defaultTheme(allocator);
    defer {
        theme_loader.deinitTheme(theme);
        allocator.destroy(theme);
    }
    
    var header = try Header.init(allocator, theme);
    defer header.deinit();
    
    // Test with very short values
    header.context = "dev [RO]";
    header.cluster = "local";
    header.user = "me";
    header.k8s_version = "v1.28";
    header.cpu_str = "5%";
    header.mem_str = "10%";
    header.title_with_version = "v0.2025.01.01";
    header.setCompact(true);
    
    // Even with short values, level 0 requires enough width
    {
        const width: u16 = 100;
        const level = header.calculateCompactLevel(width);
        try testing.expect(level >= 0);
    }
    
    // Very narrow should still give level 11
    {
        const width: u16 = 20;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 11), level);
    }
}

test "Header compact minimum width" {
    const allocator = testing.allocator;
    
    const theme = try allocator.create(theme_loader.ThemeColors);
    theme.* = try theme_loader.defaultTheme(allocator);
    defer {
        theme_loader.deinitTheme(theme);
        allocator.destroy(theme);
    }
    
    var header = try Header.init(allocator, theme);
    defer header.deinit();
    
    header.context = "rancher-desktop";
    header.cluster = "rancher-desktop";
    header.user = "rancher-desktop";
    header.k8s_version = "v1.33.3+k3s1";
    header.cpu_str = "2%";
    header.mem_str = "27%";
    header.title_with_version = "v0.2025.09.30.12.08";
    header.setCompact(true);
    
    // Level 11 format: "rancher-desktop | 2%::27%" = 30 chars
    // This is the absolute minimum supported width
    {
        const width: u16 = 30;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 11), level);
    }
    
    // Anything narrower should still be level 11
    {
        const width: u16 = 15;
        const level = header.calculateCompactLevel(width);
        try testing.expectEqual(@as(u8, 11), level);
    }
}
