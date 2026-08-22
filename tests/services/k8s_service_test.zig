// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Comprehensive tests for K8sService: init/deinit, connection state,
// namespace management, version caching, kubectl mode, authorization,
// and type structure verification.

const std = @import("std");
const testing = std.testing;
const c3s = @import("c3s");
const K8sService = c3s.K8sService;
const ClusterInfo = c3s.ClusterInfo;

// =========================================================================
// Initialization and cleanup
// =========================================================================

test "k8s_service: initialization and cleanup" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expect(service.client == null);
    try testing.expectEqual(false, service.connected);
    try testing.expectEqualStrings("default", service.current_namespace);
    try testing.expectEqualStrings("unknown", service.context_name);
    try testing.expectEqualStrings("unknown", service.cluster_name);
    try testing.expectEqualStrings("unknown", service.user_name);
}

test "k8s_service: multiple init/deinit cycles do not leak" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak in k8s_service init/deinit cycle");
    }
    const allocator = gpa.allocator();

    for (0..10) |_| {
        var service = try K8sService.init(allocator);
        service.deinit();
    }
}

// =========================================================================
// isConnected
// =========================================================================

test "k8s_service: isConnected returns false initially" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectEqual(false, service.isConnected());
}

test "k8s_service: isConnected returns true when connected with client" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    // Simulate connected state (no real client, but flags set)
    service.connected = true;
    // Without a client or use_kubectl, still false
    try testing.expectEqual(false, service.isConnected());
}

test "k8s_service: isConnected returns true in kubectl mode" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    service.connected = true;
    service.use_kubectl = true;
    try testing.expectEqual(true, service.isConnected());
}

// =========================================================================
// hasAttemptedConnect
// =========================================================================

test "k8s_service: hasAttemptedConnect initially false" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectEqual(false, service.hasAttemptedConnect());
}

test "k8s_service: connect_attempted flag tracks connect attempts" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    service.connect_attempted = true;
    try testing.expectEqual(true, service.hasAttemptedConnect());
}

// =========================================================================
// kubectl mode flag
// =========================================================================

test "k8s_service: use_kubectl defaults to false" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectEqual(false, service.use_kubectl);
}

test "k8s_service: use_kubectl can be set" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    service.use_kubectl = true;
    try testing.expectEqual(true, service.use_kubectl);
}

// =========================================================================
// version_fetch_failed flag
// =========================================================================

test "k8s_service: version_fetch_failed defaults to false" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectEqual(false, service.version_fetch_failed);
}

// =========================================================================
// getServerVersion caching
// =========================================================================

test "k8s_service: getServerVersion returns n/a when not connected" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const ver = service.getServerVersion();
    try testing.expectEqualStrings("n/a", ver);
}

test "k8s_service: getServerVersion returns cached version" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    // Manually set cached version
    service.cached_k8s_version = try allocator.dupe(u8, "v1.30.0");
    const ver = service.getServerVersion();
    try testing.expectEqualStrings("v1.30.0", ver);
}

test "k8s_service: getServerVersion returns unknown after fetch failure" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    // Simulate connected + fetch failed
    service.connected = true;
    service.use_kubectl = true;
    service.version_fetch_failed = true;

    const ver = service.getServerVersion();
    try testing.expectEqualStrings("unknown", ver);
}

// =========================================================================
// Namespace management
// =========================================================================

test "k8s_service: getCurrentNamespace returns default initially" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectEqualStrings("default", service.getCurrentNamespace());
}

test "k8s_service: setCurrentNamespace updates namespace" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try service.setCurrentNamespace("kube-system");
    try testing.expectEqualStrings("kube-system", service.getCurrentNamespace());
}

test "k8s_service: setCurrentNamespace multiple times does not leak" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak in setCurrentNamespace test");
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try service.setCurrentNamespace("ns1");
    try service.setCurrentNamespace("ns2");
    try service.setCurrentNamespace("ns3");
    try testing.expectEqualStrings("ns3", service.getCurrentNamespace());
}

// =========================================================================
// getClusterInfo
// =========================================================================

test "k8s_service: getClusterInfo returns correct info" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const info = service.getClusterInfo();

    try testing.expectEqualStrings("unknown", info.context);
    try testing.expectEqualStrings("unknown", info.cluster);
    try testing.expectEqualStrings("unknown", info.user);
    try testing.expectEqualStrings("default", info.namespace);
    try testing.expectEqual(false, info.connected);
}

// =========================================================================
// Resource operations require connection
// =========================================================================

test "k8s_service: resource operations return NotConnected" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectError(error.NotConnected, service.listAllHPAs());
    try testing.expectError(error.NotConnected, service.listAllEvents());
    try testing.expectError(error.NotConnected, service.listAllResourceQuotas());
    try testing.expectError(error.NotConnected, service.listAllLimitRanges());
    try testing.expectError(error.NotConnected, service.listAllPodDisruptionBudgets());
    try testing.expectError(error.NotConnected, service.listAllDeployments());
    try testing.expectError(error.NotConnected, service.listAllServices());
    try testing.expectError(error.NotConnected, service.listNodes());
    try testing.expectError(error.NotConnected, service.listAllConfigMaps());
    try testing.expectError(error.NotConnected, service.listAllSecrets());
    try testing.expectError(error.NotConnected, service.listAllStatefulSets());
    try testing.expectError(error.NotConnected, service.listAllDaemonSets());
    try testing.expectError(error.NotConnected, service.listAllReplicaSets());
    try testing.expectError(error.NotConnected, service.listAllJobs());
    try testing.expectError(error.NotConnected, service.listAllCronJobs());
    try testing.expectError(error.NotConnected, service.listAllRoles());
    try testing.expectError(error.NotConnected, service.listAllRoleBindings());
    try testing.expectError(error.NotConnected, service.listAllClusterRoles());
    try testing.expectError(error.NotConnected, service.listAllClusterRoleBindings());
    try testing.expectError(error.NotConnected, service.listAllPersistentVolumes());
    try testing.expectError(error.NotConnected, service.listAllPersistentVolumeClaims());
    try testing.expectError(error.NotConnected, service.listAllIngresses());
    try testing.expectError(error.NotConnected, service.listAllNetworkPolicies());
    try testing.expectError(error.NotConnected, service.listAllServiceAccounts());
    try testing.expectError(error.NotConnected, service.listAllEndpoints());
    try testing.expectError(error.NotConnected, service.listAllStorageClasses());
}

test "k8s_service: namespaced list operations return NotConnected" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectError(error.NotConnected, service.listDeployments(null));
    try testing.expectError(error.NotConnected, service.listServices(null));
    try testing.expectError(error.NotConnected, service.listConfigMaps(null));
    try testing.expectError(error.NotConnected, service.listSecrets(null));
    try testing.expectError(error.NotConnected, service.listPods(null));
}

// =========================================================================
// Authorization tests
// =========================================================================

test "k8s_service: authorization operations require connection" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectError(error.NotConnected, service.checkAccess("get", "", "pods", "default"));
    try testing.expectError(error.NotConnected, service.getAuthorizationConditions("pods", "", "default"));
    try testing.expectError(error.NotConnected, service.listCedarPolicies());
    try testing.expectError(error.NotConnected, service.listRBACPolicies());
}

test "k8s_service: detectConditionalAuth returns false when not connected" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const result = try service.detectConditionalAuth();
    try testing.expectEqual(false, result);
}

test "k8s_service: detectCedarAuth returns false when not connected" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const result = try service.detectCedarAuth();
    try testing.expectEqual(false, result);
}

// =========================================================================
// Pod metrics (disconnected)
// =========================================================================

test "k8s_service: getPodMetrics returns null when not connected" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const metrics = try service.getPodMetrics(true);
    try testing.expect(metrics == null);
}

// =========================================================================
// Raw JSON / delete / logs require connection
// =========================================================================

test "k8s_service: getRawJson returns NotConnected" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectError(error.NotConnected, service.getRawJson(.pods, "test", "default"));
}

test "k8s_service: deleteResource returns NotConnected" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectError(error.NotConnected, service.deleteResource(.pods, "test", "default", false));
}

test "k8s_service: getPodLogs returns NotConnected" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectError(error.NotConnected, service.getPodLogs("test", null, false));
}

// =========================================================================
// listContexts (reads kubeconfig, may fail in CI)
// =========================================================================

test "k8s_service: listContexts without connection" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const contexts = service.listContexts() catch |err| {
        // Expected errors when kubeconfig doesn't exist
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

    try testing.expect(contexts.len > 0);
    for (contexts) |ctx| {
        try testing.expect(ctx.name.len > 0);
        try testing.expect(ctx.cluster.len > 0);
        try testing.expect(ctx.user.len > 0);
    }
}

// =========================================================================
// Type structure tests
// =========================================================================

test "k8s_service: ClusterInfo structure" {
    const allocator = testing.allocator;

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

    try testing.expectEqualStrings("test-ctx", info.context);
    try testing.expectEqualStrings("test-cluster", info.cluster);
    try testing.expectEqualStrings("test-user", info.user);
    try testing.expectEqualStrings("default", info.namespace);
    try testing.expectEqual(true, info.connected);
}

test "k8s_service: ContextInfo structure" {
    const allocator = testing.allocator;

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

    try testing.expectEqualStrings("test-context", ctx_info.name);
    try testing.expectEqualStrings("test-cluster", ctx_info.cluster);
    try testing.expectEqualStrings("test-user", ctx_info.user);
    try testing.expect(ctx_info.namespace != null);
    try testing.expectEqualStrings("default", ctx_info.namespace.?);
    try testing.expectEqual(true, ctx_info.is_current);
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
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak in PolicyInfo test");
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

        try testing.expectEqualStrings("cluster-admin", policy.source);
        try testing.expectEqualStrings("*.*", policy.resource);
        try testing.expectEqualStrings("*", policy.verbs);
        try testing.expectEqualStrings("system:masters", policy.subjects);

        policy.deinit();
    }
}

test "k8s_service: ConditionInfo structure and memory" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak in ConditionInfo test");
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

        try testing.expectEqualStrings("Deny", cond.effect);
        try testing.expectEqualStrings("cedar-webhook", cond.authorizer);

        cond.deinit();
    }
}

// =========================================================================
// ParsedList type verification
// =========================================================================

test "k8s_service: ParsedList type can be referenced" {
    // Verify the type exists and its methods are accessible at comptime
    const PL = K8sService.ParsedList(c3s.k8s_types.Pod);
    _ = PL;
    // If this compiles, the type is valid
}

// =========================================================================
// PodMetric type
// =========================================================================

test "k8s_service: PodMetric structure" {
    const allocator = testing.allocator;

    const cpu = try allocator.dupe(u8, "100m");
    defer allocator.free(cpu);
    const mem = try allocator.dupe(u8, "256Mi");
    defer allocator.free(mem);

    const metric = K8sService.PodMetric{
        .cpu = cpu,
        .mem = mem,
    };

    try testing.expectEqualStrings("100m", metric.cpu);
    try testing.expectEqualStrings("256Mi", metric.mem);
}

// =========================================================================
// TLS data defaults
// =========================================================================

test "k8s_service: TLS data defaults to null" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expect(service.tls_ca_data == null);
    try testing.expect(service.tls_cert_data == null);
    try testing.expect(service.tls_key_data == null);
}

// --- Phase 0: --readonly must actually block mutations (2026-08-22) ----------
//
// `--readonly` used to be parsed, advertised in --help, covered by two cli tests,
// and consulted NOWHERE outside cli.zig -- so `c3s --readonly` happily deleted.
// These assert the guard at the service boundary, which is where a new caller
// cannot forget it.

test "readonly: every cluster-mutating method is refused" {
    const allocator = std.testing.allocator;
    var svc = try K8sService.init(allocator);
    defer svc.deinit();

    svc.readonly = true;
    // connected=true so the guard, not the connection check, is what rejects.
    svc.connected = true;

    try std.testing.expectError(error.ReadOnlyMode, svc.deletePod("p", "default"));
    try std.testing.expectError(error.ReadOnlyMode, svc.deleteResource(.pods, "p", "default", false));
    try std.testing.expectError(error.ReadOnlyMode, svc.deleteResource(.pods, "p", "default", true));
    try std.testing.expectError(error.ReadOnlyMode, svc.scaleDeployment("d", 3, "default"));
    try std.testing.expectError(error.ReadOnlyMode, svc.scaleStatefulSet("s", 3, "default"));
    try std.testing.expectError(error.ReadOnlyMode, svc.scaleReplicaSet("r", 3, "default"));
    try std.testing.expectError(error.ReadOnlyMode, svc.setCronJobSuspend("c", true, "default"));
}

test "readonly: defaults off, so normal operation is unaffected" {
    const allocator = std.testing.allocator;
    var svc = try K8sService.init(allocator);
    defer svc.deinit();

    try std.testing.expect(!svc.readonly);
    // With readonly off and no connection, the connection check rejects instead --
    // proving the guard is not simply refusing everything unconditionally.
    try std.testing.expectError(error.NotConnected, svc.deleteResource(.pods, "p", "default", false));
}

test "readonly: the guard precedes the connection check" {
    // Ordering matters for the message the user sees: a readonly refusal must not be
    // reported as a connection problem.
    const allocator = std.testing.allocator;
    var svc = try K8sService.init(allocator);
    defer svc.deinit();

    svc.readonly = true;
    svc.connected = false;
    try std.testing.expectError(error.ReadOnlyMode, svc.deleteResource(.pods, "p", "default", false));
}
