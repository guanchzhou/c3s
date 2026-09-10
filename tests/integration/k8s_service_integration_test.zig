const std = @import("std");
const testing = std.testing;
const K8sService = @import("c3s").K8sService;

// Integration tests for K8sService with real Kubernetes cluster
//
// Requirements:
// - Valid kubeconfig at ~/.kube/config
// - Accessible Kubernetes cluster
// - Proper RBAC permissions
//
// Run with: zig build test-integration
//
// Note: These tests will be skipped if no cluster is available (expected in CI)

test "K8sService - basic lifecycle" {
    const allocator = testing.allocator;

    // Test initialization
    var service = K8sService.init(allocator) catch |err| {
        std.debug.print("Skipping integration test - init failed: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer service.deinit();

    // Verify initial state
    try testing.expect(!service.connected);
    try testing.expect(service.sessionSlot() == null);
}

test "K8sService - connect and disconnect" {
    const allocator = testing.allocator;

    var service = K8sService.init(allocator) catch |err| {
        std.debug.print("Skipping integration test - init failed: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer service.deinit();

    // Try to connect
    service.connect(null) catch |err| {
        std.debug.print("Skipping integration test - no cluster available: {}\n", .{err});
        return error.SkipZigTest;
    };

    // Verify connected state
    try testing.expect(service.connected);
    try testing.expect(service.sessionSlot() != null);

    std.debug.print("Successfully connected to cluster: {s}\n", .{service.cluster_name});

    // Note: K8sService doesn't have a disconnect method
    // Connection is cleaned up in deinit()
}

test "K8sService - context management" {
    const allocator = testing.allocator;

    var service = K8sService.init(allocator) catch |err| {
        std.debug.print("Skipping integration test - init failed: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer service.deinit();

    // listContexts marks `is_current` relative to the *connected* context
    // (set during connect(); defaults to "unknown" otherwise), so a live
    // connection is required to assert that a current context is flagged.
    service.connect(null) catch |err| {
        std.debug.print("Skipping integration test - no cluster available: {}\n", .{err});
        return error.SkipZigTest;
    };

    // List contexts
    const contexts = service.listContexts() catch |err| {
        std.debug.print("Failed to list contexts: {}\n", .{err});
        return err;
    };
    defer {
        for (contexts) |ctx| {
            allocator.free(ctx.name);
            allocator.free(ctx.cluster);
            allocator.free(ctx.user);
            if (ctx.namespace) |ns| allocator.free(ns);
        }
        allocator.free(contexts);
    }

    std.debug.print("Found {} contexts\n", .{contexts.len});
    try testing.expect(contexts.len > 0); // Should have at least one context

    // Verify current context is marked
    var has_current = false;
    for (contexts) |ctx| {
        if (ctx.is_current) {
            has_current = true;
            std.debug.print("Current context: {s}\n", .{ctx.name});
        }
    }
    try testing.expect(has_current);
}

// Note: Additional tests for other resources (deployments, services, etc.)
// can be added following the same pattern. The key is to gracefully skip
// when no cluster is available, which allows these tests to pass in CI.
