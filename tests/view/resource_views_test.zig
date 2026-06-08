// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for Resource Views (HPAView, ContextsView, EventsView, etc.)

const std = @import("std");
const testing = std.testing;
const src = @import("src");
const HPAView = src.HPAView;
const ContextsView = src.ContextsView;
const EventsView = src.EventsView;
const ResourceQuotasView = src.ResourceQuotasView;
const theme_loader = src.theme_loader;
const K8sService = src.K8sService;

// Test HPAView initialization and cleanup
test "hpa_view: init and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in hpa_view init/cleanup test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Load theme
    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    // Initialize K8sService (will fail to connect, but that's ok for testing structure)
    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    // Initialize HPAView
    var hpa_view = try HPAView.init(allocator, &theme, &k8s_service);
    defer hpa_view.deinit();

    // Verify initial state (state lives under .table on config-generated views)
    try testing.expectEqual(@as(usize, 0), hpa_view.table.items.items.len);
    try testing.expectEqual(@as(u32, 0), hpa_view.table.selected_row);
    try testing.expectEqual(@as(u32, 0), hpa_view.table.scroll_offset);
    try testing.expectEqual(false, hpa_view.table.loading);
    try testing.expect(hpa_view.table.error_message == null);
}

// Test ContextsView initialization and cleanup
test "contexts_view: init and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in contexts_view init/cleanup test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var contexts_view = try ContextsView.init(allocator, &theme, &k8s_service);
    defer contexts_view.deinit();

    // ContextsView is a standalone view with direct state fields.
    try testing.expectEqual(@as(usize, 0), contexts_view.items.items.len);
    try testing.expectEqual(@as(u32, 0), contexts_view.selected_row);
    try testing.expectEqual(false, contexts_view.loading);
}

// Test EventsView initialization and cleanup
test "events_view: init and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in events_view init/cleanup test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var events_view = try EventsView.init(allocator, &theme, &k8s_service);
    defer events_view.deinit();

    try testing.expectEqual(@as(usize, 0), events_view.table.items.items.len);
    try testing.expectEqual(@as(u32, 0), events_view.table.selected_row);
    try testing.expectEqual(false, events_view.table.loading);
}

// Test ResourceQuotasView initialization and cleanup
test "resourcequotas_view: init and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in resourcequotas_view init/cleanup test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try ResourceQuotasView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    try testing.expectEqual(@as(usize, 0), view.table.items.items.len);
    try testing.expectEqual(@as(u32, 0), view.table.selected_row);
    try testing.expectEqual(false, view.table.loading);
}

// Test view creation (createView method)
test "hpa_view: create view interface" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in hpa_view create view test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var hpa_view = try HPAView.init(allocator, &theme, &k8s_service);
    defer hpa_view.deinit();

    // Create view interface
    const view = hpa_view.createView();

    // Verify view interface
    const name = view.getName();
    try testing.expect(std.mem.eql(u8, name, "hpa"));
}

// Test contexts view creation
test "contexts_view: create view interface" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in contexts_view create view test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var contexts_view = try ContextsView.init(allocator, &theme, &k8s_service);
    defer contexts_view.deinit();

    const view = contexts_view.createView();
    const name = view.getName();
    try testing.expect(std.mem.eql(u8, name, "contexts"));
}

// Test multiple init/deinit cycles for memory leaks
test "hpa_view: multiple init/deinit cycles" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in hpa_view multiple cycles test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

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
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in contexts_view multiple cycles test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    for (0..10) |_| {
        var contexts_view = try ContextsView.init(allocator, &theme, &k8s_service);
        contexts_view.deinit();
    }
}

// Test events view multiple init/deinit cycles
test "events_view: multiple init/deinit cycles" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in events_view multiple cycles test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    for (0..10) |_| {
        var events_view = try EventsView.init(allocator, &theme, &k8s_service);
        events_view.deinit();
    }
}
