const std = @import("std");
const h = @import("data_plane_gate_harness.zig");

test "Gate 7 all resource families permanently use data-plane subscriptions" {
    // Source gate rollback paths have been deleted. This test replaces the old
    // rollback isolation gate: it verifies that every resource family (pods, nodes,
    // namespaces, and all 54 registry families) always produces subscription
    // requests and never falls back to legacy list loading.
    var app = try h.c3s.App.init(std.testing.allocator, .{});
    defer app.deinit();

    // Pods always issues start then restart — no legacy fallback path.
    _ = app.pods_view.takeSubscriptionRequest();
    try app.pods_view.refresh();
    try std.testing.expectEqual(.start, app.pods_view.takeSubscriptionRequest());
    app.pods_view.markSubscriptionStarted();
    try app.pods_view.refresh();
    try std.testing.expectEqual(.restart, app.pods_view.takeSubscriptionRequest());

    // Nodes always issues start then restart.
    _ = app.nodes_view.takeSubscriptionRequest();
    try app.nodes_view.refresh();
    try std.testing.expectEqual(.start, app.nodes_view.takeSubscriptionRequest());
    app.nodes_view.markSubscriptionStarted();
    try app.nodes_view.refresh();
    try std.testing.expectEqual(.restart, app.nodes_view.takeSubscriptionRequest());

    // Namespaces always issues start then restart.
    _ = app.namespaces_view.takeSubscriptionRequest();
    try app.namespaces_view.refresh();
    try std.testing.expectEqual(.start, app.namespaces_view.takeSubscriptionRequest());
    app.namespaces_view.markSubscriptionStarted();
    try app.namespaces_view.refresh();
    try std.testing.expectEqual(.restart, app.namespaces_view.takeSubscriptionRequest());

    // All 54 registry families always issue start then restart.
    const entries = app.resource_families.registry.items();
    for (entries, 0..) |*entry, index| {
        _ = entry.takeRequest();
        try entry.refresh();
        try std.testing.expectEqual(h.c3s.k8s_resource_family_registry.Request.start, entry.takeRequest());
        entry.markStarted(.{ .generation = 1, .subscription_id = @intCast(index + 1) });
        try entry.refresh();
        try std.testing.expectEqual(h.c3s.k8s_resource_family_registry.Request.restart, entry.takeRequest());
        entry.markStopped();
    }
    try h.c3s.runTask14RollbackIsolationGate();
}
