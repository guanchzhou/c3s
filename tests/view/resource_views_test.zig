// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for Resource Views (HPAView, ContextsView, EventsView, etc.)

const std = @import("std");
const testing = std.testing;
const HPAView = @import("../../src/view/hpa_view.zig").HPAView;
const ContextsView = @import("../../src/view/contexts_view.zig").ContextsView;
const EventsView = @import("../../src/view/events_view.zig").EventsView;
const ResourceQuotasView = @import("../../src/view/resourcequotas_view.zig").ResourceQuotasView;
const theme_loader = @import("../../src/model/theme_loader.zig");
const K8sService = @import("../../src/services/k8s_service.zig").K8sService;

// Test HPAView initialization and cleanup
test "hpa_view: init and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in hpa_view init/cleanup test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Load theme
    const theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(theme, allocator);

    // Initialize K8sService (will fail to connect, but that's ok for testing structure)
    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    // Initialize HPAView
    var hpa_view = try HPAView.init(allocator, &theme, &k8s_service);
    defer hpa_view.deinit();

    // Verify initial state
    try testing.expectEqual(@as(usize, 0), hpa_view.items.items.len);
    try testing.expectEqual(@as(usize, 0), hpa_view.selected_row);
    try testing.expectEqual(@as(usize, 0), hpa_view.scroll_offset);
    try testing.expectEqual(false, hpa_view.loading);
    try testing.expect(hpa_view.error_message == null);
}

// Test ContextsView initialization and cleanup
test "contexts_view: init and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in contexts_view init/cleanup test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(theme, allocator);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var contexts_view = try ContextsView.init(allocator, &theme, &k8s_service);
    defer contexts_view.deinit();

    try testing.expectEqual(@as(usize, 0), contexts_view.items.items.len);
    try testing.expectEqual(@as(usize, 0), contexts_view.selected_row);
    try testing.expectEqual(false, contexts_view.loading);
}

// Test EventsView initialization and cleanup
test "events_view: init and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in events_view init/cleanup test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(theme, allocator);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var events_view = try EventsView.init(allocator, &theme, &k8s_service);
    defer events_view.deinit();

    try testing.expectEqual(@as(usize, 0), events_view.items.items.len);
    try testing.expectEqual(@as(usize, 0), events_view.selected_row);
    try testing.expectEqual(false, events_view.loading);
}

// Test ResourceQuotasView initialization and cleanup
test "resourcequotas_view: init and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in resourcequotas_view init/cleanup test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(theme, allocator);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try ResourceQuotasView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    try testing.expectEqual(@as(usize, 0), view.items.items.len);
    try testing.expectEqual(@as(usize, 0), view.selected_row);
    try testing.expectEqual(false, view.loading);
}

// Test view creation (createView method)
test "hpa_view: create view interface" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in hpa_view create view test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(theme, allocator);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var hpa_view = try HPAView.init(allocator, &theme, &k8s_service);
    defer hpa_view.deinit();

    // Create view interface
    const view = hpa_view.createView();

    // Verify view interface
    const name = view.getName();
    try testing.expect(std.mem.eql(u8, name, "HorizontalPodAutoscalers"));
}

// Test contexts view creation
test "contexts_view: create view interface" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in contexts_view create view test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(theme, allocator);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var contexts_view = try ContextsView.init(allocator, &theme, &k8s_service);
    defer contexts_view.deinit();

    const view = contexts_view.createView();
    const name = view.getName();
    try testing.expect(std.mem.eql(u8, name, "Contexts"));
}

// Test multiple init/deinit cycles for memory leaks
test "hpa_view: multiple init/deinit cycles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in hpa_view multiple cycles test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(theme, allocator);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    // Test 10 init/deinit cycles
    for (0..10) |_| {
        var hpa_view = try HPAView.init(allocator, &theme, &k8s_service);
        hpa_view.deinit();
    }
}

// Test contexts view multiple init/deinit cycles
test "contexts_view: multiple init/deinit cycles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in contexts_view multiple cycles test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(theme, allocator);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    for (0..10) |_| {
        var contexts_view = try ContextsView.init(allocator, &theme, &k8s_service);
        contexts_view.deinit();
    }
}

// Test events view multiple init/deinit cycles
test "events_view: multiple init/deinit cycles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in events_view multiple cycles test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(theme, allocator);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    for (0..10) |_| {
        var events_view = try EventsView.init(allocator, &theme, &k8s_service);
        events_view.deinit();
    }
}
