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
    try testing.expect(service.client == null);
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
    try testing.expect(service.client != null);

    std.debug.print("Successfully connected to cluster: {s}\n", .{service.cluster_name});

    // Note: K8sService doesn't have a disconnect method
    // Connection is cleaned up in deinit()
}

test "K8sService - list namespaces" {
    const allocator = testing.allocator;

    var service = K8sService.init(allocator) catch |err| {
        std.debug.print("Skipping integration test - init failed: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer service.deinit();

    service.connect(null) catch |err| {
        std.debug.print("Skipping integration test - no cluster available: {}\n", .{err});
        return error.SkipZigTest;
    };
    // Note: Connection cleaned up in service.deinit()

    // List namespaces
    const namespaces = service.listNamespaces() catch |err| {
        std.debug.print("Failed to list namespaces: {}\n", .{err});
        return err;
    };
    defer allocator.free(namespaces);

    std.debug.print("Found {} namespaces\n", .{namespaces.len});
    try testing.expect(namespaces.len > 0); // Should have at least default or kube-system
}

test "K8sService - list nodes" {
    const allocator = testing.allocator;

    var service = K8sService.init(allocator) catch |err| {
        std.debug.print("Skipping integration test - init failed: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer service.deinit();

    service.connect(null) catch |err| {
        std.debug.print("Skipping integration test - no cluster available: {}\n", .{err});
        return error.SkipZigTest;
    };
    // Note: Connection cleaned up in service.deinit()

    // List nodes
    const nodes = service.listNodes() catch |err| {
        std.debug.print("Failed to list nodes: {}\n", .{err});
        return err;
    };
    defer allocator.free(nodes);

    std.debug.print("Found {} nodes\n", .{nodes.len});
    try testing.expect(nodes.len > 0); // Every cluster should have at least one node
}

test "K8sService - list pods" {
    const allocator = testing.allocator;

    var service = K8sService.init(allocator) catch |err| {
        std.debug.print("Skipping integration test - init failed: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer service.deinit();

    service.connect(null) catch |err| {
        std.debug.print("Skipping integration test - no cluster available: {}\n", .{err});
        return error.SkipZigTest;
    };
    // Note: Connection cleaned up in service.deinit()

    // List pods in default namespace
    const pods = service.listPods(null) catch |err| {
        std.debug.print("Failed to list pods: {}\n", .{err});
        return err;
    };
    defer allocator.free(pods);

    std.debug.print("Found {} pods in namespace: {s}\n", .{ pods.len, service.current_namespace });
    try testing.expect(pods.len >= 0); // May be 0 if namespace is empty
}

test "K8sService - list all pods" {
    const allocator = testing.allocator;

    var service = K8sService.init(allocator) catch |err| {
        std.debug.print("Skipping integration test - init failed: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer service.deinit();

    service.connect(null) catch |err| {
        std.debug.print("Skipping integration test - no cluster available: {}\n", .{err});
        return error.SkipZigTest;
    };
    // Note: Connection cleaned up in service.deinit()

    // List all pods across all namespaces
    const pods = service.listAllPods() catch |err| {
        std.debug.print("Failed to list all pods: {}\n", .{err});
        return err;
    };
    defer allocator.free(pods);

    std.debug.print("Found {} pods across all namespaces\n", .{pods.len});
    try testing.expect(pods.len >= 0);
}

test "K8sService - context management" {
    const allocator = testing.allocator;

    var service = K8sService.init(allocator) catch |err| {
        std.debug.print("Skipping integration test - init failed: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer service.deinit();

    // List contexts (doesn't require connection)
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
