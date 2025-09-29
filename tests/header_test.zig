const std = @import("std");
const testing = std.testing;
const Header = @import("../src/header.zig").Header;
const Terminal = @import("../src/terminal.zig").Terminal;

test "header initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var header = try Header.init(allocator);
    defer header.deinit();

    // Test that header was initialized with default values
    try testing.expect(std.mem.eql(u8, header.context, "rancher-desktop [RW]"));
    try testing.expect(std.mem.eql(u8, header.cluster, "rancher-desktop"));
    try testing.expect(std.mem.eql(u8, header.user, "rancher-desktop"));
    try testing.expect(std.mem.eql(u8, header.k9s_version, "v0.50.13"));
    try testing.expect(std.mem.eql(u8, header.k8s_version, "v1.33.3+k3s1"));
    try testing.expect(header.cpu_usage == 2);
    try testing.expect(header.mem_usage == 27);
}

test "header rendering" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var header = try Header.init(allocator);
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

    var header = try Header.init(allocator);
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

    // Test multiple initialization and cleanup cycles
    for (0..10) |_| {
        var header = try Header.init(allocator);
        header.deinit();
    }
    
    // Test that no memory leaks occurred
    const allocated = gpa.deinit();
    try testing.expect(allocated == .ok);
}
