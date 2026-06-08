// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for PodsView.
//
// PodsView no longer owns sample data via a standalone `Body` type; it is a
// TableState-backed view that needs a theme and a K8sService. Without a live
// cluster the pod list stays empty, so these tests exercise structure,
// navigation bounds-safety, the View interface, and memory hygiene.

const std = @import("std");
const testing = std.testing;
const src = @import("src");
const PodsView = src.PodsView;
const Terminal = src.Terminal;
const theme_loader = src.theme_loader;
const K8sService = src.K8sService;

test "pods_view: init and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var pods_view = try PodsView.init(allocator, &theme, &k8s_service);
    defer pods_view.deinit();

    // No cluster connection in tests -> empty list, default cursor/scroll.
    try testing.expectEqual(@as(usize, 0), pods_view.table.items.items.len);
    try testing.expectEqual(@as(u32, 0), pods_view.table.selected_row);
    try testing.expectEqual(@as(u32, 0), pods_view.table.scroll_offset);
}

test "pods_view: getName via View interface" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var pods_view = try PodsView.init(allocator, &theme, &k8s_service);
    defer pods_view.deinit();

    const view = pods_view.createView();
    try testing.expect(std.mem.eql(u8, view.getName(), "pods"));
}

test "pods_view: navigation is bounds-safe" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var pods_view = try PodsView.init(allocator, &theme, &k8s_service);
    defer pods_view.deinit();

    // Navigation must never crash or move out of bounds on an empty list.
    pods_view.table.navigateDown();
    try testing.expectEqual(@as(u32, 0), pods_view.table.selected_row);

    pods_view.table.navigateUp();
    try testing.expectEqual(@as(u32, 0), pods_view.table.selected_row);

    pods_view.table.gotoBottom();
    pods_view.table.gotoTop();
    try testing.expectEqual(@as(u32, 0), pods_view.table.selected_row);
    try testing.expect(pods_view.table.scroll_offset >= 0);
}

test "pods_view: rendering does not crash" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var pods_view = try PodsView.init(allocator, &theme, &k8s_service);
    defer pods_view.deinit();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    const view = pods_view.createView();

    // Render at a few positions/sizes; each must succeed without crashing.
    try view.render(&terminal, 0, 0, 80, 20);
    try view.render(&terminal, 10, 5, 100, 25);
    try view.render(&terminal, 0, 0, 120, 30);
}

test "pods_view: applyFilter is safe on empty list" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var pods_view = try PodsView.init(allocator, &theme, &k8s_service);
    defer pods_view.deinit();

    try pods_view.applyFilter("nginx");
    try testing.expectEqual(@as(usize, 0), pods_view.table.filtered_indices.items.len);

    try pods_view.applyFilter("");
    try testing.expectEqual(@as(usize, 0), pods_view.table.filtered_indices.items.len);
}

test "pods_view: memory management across cycles" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    // Multiple init/deinit cycles must not leak (gpa.deinit() asserts on leak).
    for (0..10) |_| {
        var pods_view = try PodsView.init(allocator, &theme, &k8s_service);
        pods_view.deinit();
    }
}
