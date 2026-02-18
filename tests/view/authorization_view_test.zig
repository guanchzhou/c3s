// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for AuthorizationView (three-tab authorization view)

const std = @import("std");
const testing = std.testing;
const c3s = @import("c3s");
const AuthorizationView = c3s.AuthorizationView;
const theme_loader = c3s.theme_loader;
const K8sService = c3s.K8sService;

// Test AuthorizationView initialization and cleanup
test "authorization_view: init and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in authorization_view init/cleanup test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    // Verify initial state
    try testing.expectEqual(@as(usize, 0), view.access_tab.table.items.items.len);
    try testing.expectEqual(@as(usize, 0), view.policy_tab.table.items.items.len);
    try testing.expectEqual(@as(usize, 0), view.condition_tab.table.items.items.len);
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);
    try testing.expectEqual(@as(u32, 0), view.policy_tab.table.selected_row);
    try testing.expectEqual(@as(u32, 0), view.condition_tab.table.selected_row);
    try testing.expectEqual(false, view.loading);
    try testing.expect(view.error_message == null);
    try testing.expect(view.condition_tab.condition_resource == null);
    try testing.expectEqual(AuthorizationView.Tab.access_review, view.active_tab);
}

// Test view creation
test "authorization_view: create view interface" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in authorization_view create view test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    const v = view.createView();
    const name = v.getName();
    try testing.expect(std.mem.eql(u8, name, "authorization"));
}

// Test multiple init/deinit cycles for memory leaks
test "authorization_view: multiple init/deinit cycles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in authorization_view multiple cycles test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    // Test 10 init/deinit cycles
    for (0..10) |_| {
        var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
        view.deinit();
    }
}

// Test tab switching
test "authorization_view: tab switching via keys" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in authorization_view tab switching test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    const v = view.createView();

    // Default tab
    try testing.expectEqual(AuthorizationView.Tab.access_review, view.active_tab);

    // Switch to tab 2
    _ = try v.handleKey(.{ .char = '2' });
    try testing.expectEqual(AuthorizationView.Tab.policy_browser, view.active_tab);

    // Switch to tab 3
    _ = try v.handleKey(.{ .char = '3' });
    try testing.expectEqual(AuthorizationView.Tab.condition_inspector, view.active_tab);

    // Switch back to tab 1
    _ = try v.handleKey(.{ .char = '1' });
    try testing.expectEqual(AuthorizationView.Tab.access_review, view.active_tab);
}

// Test tab cycling via Tab key
test "authorization_view: tab cycling" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in authorization_view tab cycling test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    const v = view.createView();

    try testing.expectEqual(AuthorizationView.Tab.access_review, view.active_tab);
    _ = try v.handleKey(.{ .char = '\t' });
    try testing.expectEqual(AuthorizationView.Tab.policy_browser, view.active_tab);
    _ = try v.handleKey(.{ .char = '\t' });
    try testing.expectEqual(AuthorizationView.Tab.condition_inspector, view.active_tab);
    _ = try v.handleKey(.{ .char = '\t' });
    try testing.expectEqual(AuthorizationView.Tab.access_review, view.active_tab);
}

// Test refresh without connection sets error
test "authorization_view: refresh without connection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in authorization_view refresh test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    // Refresh each tab type
    try view.refreshAccessReview();
    try testing.expect(view.error_message != null);
    try testing.expect(std.mem.eql(u8, view.error_message.?, "Not connected to Kubernetes cluster"));

    try view.refreshPolicies();
    try testing.expect(view.error_message != null);

    try view.refreshConditions("pods", "");
    try testing.expect(view.error_message != null);
    try testing.expect(view.condition_tab.condition_resource != null);
    try testing.expect(std.mem.eql(u8, view.condition_tab.condition_resource.?, "pods"));
}

// Test data row init/deinit
test "authorization_view: AccessRow memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in AccessRow test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    for (0..10) |_| {
        var row = AuthorizationView.AccessRow{
            .resource = try allocator.dupe(u8, "test-resource"),
            .group = try allocator.dupe(u8, "test-group"),
            .get = .allowed,
            .list = .denied,
            .create = .conditional,
            .update = .denied,
            .delete = .denied,
            .watch = .allowed,
            .condition_count = 5,
            .allocator = allocator,
        };
        row.deinit();
    }
}

// Test PolicyRow memory management
test "authorization_view: PolicyRow memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in PolicyRow test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    for (0..10) |_| {
        var row = AuthorizationView.PolicyRow{
            .source = try allocator.dupe(u8, "admin"),
            .policy_type = .rbac,
            .resource = try allocator.dupe(u8, "*.*"),
            .verbs = try allocator.dupe(u8, "*"),
            .subjects = try allocator.dupe(u8, "system:masters"),
            .allocator = allocator,
        };
        row.deinit();
    }
}

// Test ConditionRow memory management
test "authorization_view: ConditionRow memory management" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in ConditionRow test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    for (0..10) |_| {
        var row = AuthorizationView.ConditionRow{
            .index = 1,
            .effect = try allocator.dupe(u8, "Deny"),
            .authorizer = try allocator.dupe(u8, "cedar-webhook"),
            .expression = try allocator.dupe(u8, "resource.metadata.labels[\"protected\"]"),
            .description = try allocator.dupe(u8, "Block protected pods"),
            .allocator = allocator,
        };
        row.deinit();
    }
}

// Test filter application
test "authorization_view: filter with data" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in authorization_view filter test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    // Add test data
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "pods"),
        .group = try allocator.dupe(u8, ""),
        .allocator = allocator,
    });
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "deployments"),
        .group = try allocator.dupe(u8, "apps"),
        .allocator = allocator,
    });
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "secrets"),
        .group = try allocator.dupe(u8, ""),
        .allocator = allocator,
    });

    // No filter shows all
    try view.applyFilter("");
    try testing.expectEqual(@as(usize, 3), view.access_tab.table.filtered_indices.items.len);

    // Filter matches subset
    try view.applyFilter("pod");
    try testing.expectEqual(@as(usize, 1), view.access_tab.table.filtered_indices.items.len);

    // Filter matches nothing
    try view.applyFilter("zzz");
    try testing.expectEqual(@as(usize, 0), view.access_tab.table.filtered_indices.items.len);

    // Clear filter
    try view.applyFilter("");
    try testing.expectEqual(@as(usize, 3), view.access_tab.table.filtered_indices.items.len);
}

// Test navigation with data
test "authorization_view: navigation with rows" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in authorization_view navigation test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    // Add rows
    for ([_][]const u8{ "pods", "deployments", "secrets", "nodes", "services" }) |name| {
        try view.access_tab.table.appendItem(.{
            .resource = try allocator.dupe(u8, name),
            .group = try allocator.dupe(u8, ""),
            .allocator = allocator,
        });
    }
    try view.rebuildAccessFilter();
    view.access_tab.table.visible_rows = 10;

    try testing.expectEqual(@as(usize, 5), view.access_tab.table.filtered_indices.items.len);
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);

    // Navigate down
    const v = view.createView();
    _ = try v.handleKey(.{ .char = 'j' });
    try testing.expectEqual(@as(u32, 1), view.access_tab.table.selected_row);

    _ = try v.handleKey(.{ .char = 'j' });
    _ = try v.handleKey(.{ .char = 'j' });
    try testing.expectEqual(@as(u32, 3), view.access_tab.table.selected_row);

    // Navigate up
    _ = try v.handleKey(.{ .char = 'k' });
    try testing.expectEqual(@as(u32, 2), view.access_tab.table.selected_row);

    // Jump to top
    _ = try v.handleKey(.{ .char = 'g' });
    try testing.expectEqual(@as(u32, 0), view.access_tab.table.selected_row);

    // Jump to bottom
    _ = try v.handleKey(.{ .char = 'G' });
    try testing.expectEqual(@as(u32, 4), view.access_tab.table.selected_row);
}

// Test getSelectedResourceInfo
test "authorization_view: getSelectedResourceInfo returns null" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in getSelectedResourceInfo test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    // Authorization view doesn't select k8s resources for describe/yaml
    try testing.expect(view.getSelectedResourceInfo() == null);
}

// Test hints
test "authorization_view: hints are valid" {
    const hints = AuthorizationView.authorizationHints();
    try testing.expect(hints.hints.len > 0);
    try testing.expectEqual(@as(usize, 8), hints.hints.len);
    try testing.expectEqual(@as(usize, 0), hints.quick_commands.len);

    for (hints.hints) |hint| {
        const rt = @intFromEnum(hint.render_fn);
        try testing.expect(rt == 0 or rt == 1);
    }
}

// Test AccessStatus symbols
test "authorization_view: AccessStatus symbols" {
    try testing.expect(std.unicode.utf8ValidateSlice(AuthorizationView.AccessStatus.allowed.symbol()));
    try testing.expect(std.unicode.utf8ValidateSlice(AuthorizationView.AccessStatus.denied.symbol()));
    try testing.expect(std.unicode.utf8ValidateSlice(AuthorizationView.AccessStatus.conditional.symbol()));

    // Verify specific symbols
    try testing.expect(std.mem.eql(u8, "\xe2\x9c\x93", AuthorizationView.AccessStatus.allowed.symbol()));
    try testing.expect(std.mem.eql(u8, "\xe2\x9c\x97", AuthorizationView.AccessStatus.denied.symbol()));
    try testing.expect(std.mem.eql(u8, "~", AuthorizationView.AccessStatus.conditional.symbol()));
}

// Test PolicyType labels
test "authorization_view: PolicyType labels" {
    try testing.expect(std.mem.eql(u8, "RBAC", AuthorizationView.PolicyRow.PolicyType.rbac.label()));
    try testing.expect(std.mem.eql(u8, "Cedar", AuthorizationView.PolicyRow.PolicyType.cedar.label()));
}

// Test clear operations
test "authorization_view: clear operations" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in clear operations test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    // Add and clear access rows
    try view.access_tab.table.appendItem(.{
        .resource = try allocator.dupe(u8, "pods"),
        .group = try allocator.dupe(u8, ""),
        .allocator = allocator,
    });
    try testing.expectEqual(@as(usize, 1), view.access_tab.table.items.items.len);
    view.clearAccessRows();
    try testing.expectEqual(@as(usize, 0), view.access_tab.table.items.items.len);

    // Add and clear policy rows
    try view.policy_tab.table.appendItem(.{
        .source = try allocator.dupe(u8, "admin"),
        .policy_type = .rbac,
        .resource = try allocator.dupe(u8, "*"),
        .verbs = try allocator.dupe(u8, "*"),
        .subjects = try allocator.dupe(u8, "system:masters"),
        .allocator = allocator,
    });
    try testing.expectEqual(@as(usize, 1), view.policy_tab.table.items.items.len);
    view.clearPolicyRows();
    try testing.expectEqual(@as(usize, 0), view.policy_tab.table.items.items.len);

    // Add and clear condition rows
    try view.condition_tab.table.appendItem(.{
        .index = 1,
        .effect = try allocator.dupe(u8, "Deny"),
        .authorizer = try allocator.dupe(u8, "webhook"),
        .expression = try allocator.dupe(u8, "expr"),
        .description = try allocator.dupe(u8, "desc"),
        .allocator = allocator,
    });
    try testing.expectEqual(@as(usize, 1), view.condition_tab.table.items.items.len);
    view.clearConditionRows();
    try testing.expectEqual(@as(usize, 0), view.condition_tab.table.items.items.len);
}

// Test describe/yaml only works on policy tab
test "authorization_view: describe/yaml tab restriction" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in describe/yaml test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.loadTheme(allocator, "dracula");
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var view = try AuthorizationView.init(allocator, &theme, &k8s_service);
    defer view.deinit();

    const View = c3s.View;
    const v = view.createView();

    // Tab 1: d/y not handled
    try testing.expectEqual(View.KeyResult.not_handled, try v.handleKey(.{ .char = 'd' }));
    try testing.expectEqual(View.KeyResult.not_handled, try v.handleKey(.{ .char = 'y' }));

    // Tab 2: d/y request describe/yaml
    _ = try v.handleKey(.{ .char = '2' });
    try testing.expectEqual(View.KeyResult.request_describe, try v.handleKey(.{ .char = 'd' }));
    try testing.expectEqual(View.KeyResult.request_yaml, try v.handleKey(.{ .char = 'y' }));

    // Tab 3: d/y not handled
    _ = try v.handleKey(.{ .char = '3' });
    try testing.expectEqual(View.KeyResult.not_handled, try v.handleKey(.{ .char = 'd' }));
    try testing.expectEqual(View.KeyResult.not_handled, try v.handleKey(.{ .char = 'y' }));
}
