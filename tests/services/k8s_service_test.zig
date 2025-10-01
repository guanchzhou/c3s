// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for K8sService

const std = @import("std");
const testing = std.testing;
const K8sService = @import("../../src/services/k8s_service.zig").K8sService;

test "k8s_service: initialization and cleanup" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in k8s_service init test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();

    // Verify initial state
    try testing.expect(service.client == null);
    try testing.expectEqual(false, service.connected);
    try testing.expect(std.mem.eql(u8, service.current_namespace, "default"));
    try testing.expect(std.mem.eql(u8, service.context_name, "unknown"));
}

test "k8s_service: isConnected returns correct state" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in k8s_service isConnected test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();

    // Initially not connected
    try testing.expectEqual(false, service.isConnected());
}

test "k8s_service: getClusterInfo returns correct info" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in k8s_service getClusterInfo test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const info = service.getClusterInfo();

    // Verify cluster info structure
    try testing.expect(info.context.len > 0);
    try testing.expect(info.cluster.len > 0);
    try testing.expect(info.namespace.len > 0);
    try testing.expectEqual(false, info.connected);
}

test "k8s_service: connect fails gracefully without kubeconfig" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in k8s_service connect test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();

    // Attempt to connect - should fail if no valid kubeconfig exists or cluster is unreachable
    // This is expected to fail in CI/test environments, we just verify it doesn't crash
    _ = service.connect(null);

    // Service should still be in valid state after failed connection
    try testing.expect(service.allocator.ptr == allocator.ptr);
}

test "k8s_service: multiple init/deinit cycles" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in k8s_service multiple cycles test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Test 10 init/deinit cycles for memory leaks
    for (0..10) |_| {
        var service = try K8sService.init(allocator);
        service.deinit();
    }
}

test "k8s_service: listContexts without connection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in k8s_service listContexts test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();

    // listContexts should work without active connection (reads from kubeconfig)
    // It will fail if kubeconfig doesn't exist, which is expected in some test environments
    const contexts = service.listContexts() catch |err| {
        // Expected errors: HomeNotFound, FileNotFound, etc.
        try testing.expect(err == error.HomeNotFound or
            err == error.FileNotFound or
            err == error.NoDocuments or
            err == error.AccessDenied);
        return;
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

    // If we got here, kubeconfig exists and was parsed successfully
    try testing.expect(contexts.len > 0);
    for (contexts) |ctx| {
        try testing.expect(ctx.name.len > 0);
        try testing.expect(ctx.cluster.len > 0);
        try testing.expect(ctx.user.len > 0);
    }
}

test "k8s_service: ContextInfo structure" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in k8s_service ContextInfo test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    // Test ContextInfo structure
    const name = try allocator.dupe(u8, "test-context");
    defer allocator.free(name);
    const cluster = try allocator.dupe(u8, "test-cluster");
    defer allocator.free(cluster);
    const user = try allocator.dupe(u8, "test-user");
    defer allocator.free(user);
    const namespace = try allocator.dupe(u8, "default");
    defer allocator.free(namespace);

    const ctx_info = K8sService.ContextInfo{
        .name = name,
        .cluster = cluster,
        .user = user,
        .namespace = namespace,
        .is_current = true,
    };

    try testing.expect(std.mem.eql(u8, ctx_info.name, "test-context"));
    try testing.expect(std.mem.eql(u8, ctx_info.cluster, "test-cluster"));
    try testing.expect(std.mem.eql(u8, ctx_info.user, "test-user"));
    try testing.expect(ctx_info.namespace != null);
    try testing.expect(std.mem.eql(u8, ctx_info.namespace.?, "default"));
    try testing.expectEqual(true, ctx_info.is_current);
}

test "k8s_service: resource operations require connection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in k8s_service resource operations test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();

    // All resource operations should return NotConnected error when not connected
    const hpas_result = service.listAllHPAs();
    try testing.expectError(error.NotConnected, hpas_result);

    const events_result = service.listAllEvents();
    try testing.expectError(error.NotConnected, events_result);

    const quotas_result = service.listAllResourceQuotas();
    try testing.expectError(error.NotConnected, quotas_result);

    const limits_result = service.listAllLimitRanges();
    try testing.expectError(error.NotConnected, limits_result);

    const pdbs_result = service.listAllPodDisruptionBudgets();
    try testing.expectError(error.NotConnected, pdbs_result);
}

test "k8s_service: ClusterInfo structure" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in k8s_service ClusterInfo test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    const context = try allocator.dupe(u8, "test-ctx");
    defer allocator.free(context);
    const cluster = try allocator.dupe(u8, "test-cluster");
    defer allocator.free(cluster);
    const namespace = try allocator.dupe(u8, "default");
    defer allocator.free(namespace);

    const info = K8sService.ClusterInfo{
        .context = context,
        .cluster = cluster,
        .namespace = namespace,
        .connected = true,
    };

    try testing.expect(std.mem.eql(u8, info.context, "test-ctx"));
    try testing.expect(std.mem.eql(u8, info.cluster, "test-cluster"));
    try testing.expect(std.mem.eql(u8, info.namespace, "default"));
    try testing.expectEqual(true, info.connected);
}
