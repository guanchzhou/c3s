// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for K8sService

const std = @import("std");
const testing = std.testing;
const c3s = @import("c3s");
const K8sService = c3s.K8sService;
const ClusterInfo = c3s.ClusterInfo;

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

    const user = try allocator.dupe(u8, "test-user");
    defer allocator.free(user);

    const info = ClusterInfo{
        .context = context,
        .cluster = cluster,
        .user = user,
        .namespace = namespace,
        .connected = true,
    };

    try testing.expect(std.mem.eql(u8, info.context, "test-ctx"));
    try testing.expect(std.mem.eql(u8, info.cluster, "test-cluster"));
    try testing.expect(std.mem.eql(u8, info.user, "test-user"));
    try testing.expect(std.mem.eql(u8, info.namespace, "default"));
    try testing.expectEqual(true, info.connected);
}

// ===== Authorization-related tests =====

test "k8s_service: authorization operations require connection" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in k8s_service authorization test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();

    // checkAccess should return NotConnected
    const check_result = service.checkAccess("get", "", "pods", "default");
    try testing.expectError(error.NotConnected, check_result);

    // getAuthorizationConditions should return NotConnected
    const cond_result = service.getAuthorizationConditions("pods", "", "default");
    try testing.expectError(error.NotConnected, cond_result);

    // listCedarPolicies should return NotConnected
    const cedar_result = service.listCedarPolicies();
    try testing.expectError(error.NotConnected, cedar_result);

    // listRBACPolicies should return NotConnected
    const rbac_result = service.listRBACPolicies();
    try testing.expectError(error.NotConnected, rbac_result);
}

test "k8s_service: detectConditionalAuth returns false when not connected" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in detectConditionalAuth test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const result = try service.detectConditionalAuth();
    try testing.expectEqual(false, result);
}

test "k8s_service: detectCedarAuth returns false when not connected" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in detectCedarAuth test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const result = try service.detectCedarAuth();
    try testing.expectEqual(false, result);
}

test "k8s_service: AccessCheckResult structure" {
    const result = K8sService.AccessCheckResult{
        .allowed = true,
        .conditional = true,
        .condition_count = 3,
    };
    try testing.expectEqual(true, result.allowed);
    try testing.expectEqual(true, result.conditional);
    try testing.expectEqual(@as(u32, 3), result.condition_count);
}

test "k8s_service: PolicyInfo structure and memory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in PolicyInfo test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    for (0..5) |_| {
        var policy = K8sService.PolicyInfo{
            .source = try allocator.dupe(u8, "cluster-admin"),
            .resource = try allocator.dupe(u8, "*.*"),
            .verbs = try allocator.dupe(u8, "*"),
            .subjects = try allocator.dupe(u8, "system:masters"),
            .allocator = allocator,
        };

        try testing.expect(std.mem.eql(u8, policy.source, "cluster-admin"));
        try testing.expect(std.mem.eql(u8, policy.resource, "*.*"));
        try testing.expect(std.mem.eql(u8, policy.verbs, "*"));
        try testing.expect(std.mem.eql(u8, policy.subjects, "system:masters"));

        policy.deinit();
    }
}

test "k8s_service: ConditionInfo structure and memory" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in ConditionInfo test\n", .{});
        }
    }
    const allocator = gpa.allocator();

    for (0..5) |_| {
        var cond = K8sService.ConditionInfo{
            .effect = try allocator.dupe(u8, "Deny"),
            .authorizer = try allocator.dupe(u8, "cedar-webhook"),
            .expression = try allocator.dupe(u8, "resource.metadata.labels[\"protected\"] == \"true\""),
            .description = try allocator.dupe(u8, "Block deletion of protected pods"),
            .allocator = allocator,
        };

        try testing.expect(std.mem.eql(u8, cond.effect, "Deny"));
        try testing.expect(std.mem.eql(u8, cond.authorizer, "cedar-webhook"));

        cond.deinit();
    }
}
