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

test "k8s_service: connected flag cannot bypass an empty session slot" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    service.connected = true;
    service.use_kubectl = true;
    try testing.expectEqual(false, service.isConnected());
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

test "k8s_service: stale cached version is hidden while disconnected" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    // Manually set cached version
    service.cached_k8s_version = try allocator.dupe(u8, "v1.30.0");
    try testing.expectEqualStrings("n/a", service.getServerVersion());
}

test "k8s_service: disconnected state wins over a stale fetch failure" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    service.version_fetch_failed = true;

    const ver = service.getServerVersion();
    try testing.expectEqualStrings("n/a", ver);
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

test "k8s_service: setCurrentNamespace requires an active session" {
    const allocator = testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    try testing.expectError(
        error.NotConnected,
        service.setCurrentNamespace("kube-system"),
    );
    try testing.expectEqualStrings("default", service.getCurrentNamespace());
}

test "k8s_service: connected namespace changes update facade and client" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) @panic("Memory leak in setCurrentNamespace test");
    }
    const allocator = gpa.allocator();

    var service = try K8sService.init(allocator);
    defer service.deinit();
    var shared_event: std.Io.Event = .unset;
    var slot = ActiveSessionSlot4A.init(c3s.runtime.io(), &shared_event);
    var harness = SessionHarness4A{};
    service.bindSessionSlot(&slot);
    service.session_factory = harness.factory();
    try service.connect("namespace-context");
    defer releaseInstalledSession4A(&service, &slot);

    try service.setCurrentNamespace("ns1");
    try service.setCurrentNamespace("ns2");
    try service.setCurrentNamespace("ns3");
    try testing.expectEqualStrings("ns3", service.getCurrentNamespace());

    var lease = (try service.acquireRequest(.command)).?;
    defer lease.release();
    try testing.expectEqualStrings("ns3", (try lease.client()).namespace);
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

fn exerciseConfiguredContextAllocations(
    allocator: std.mem.Allocator,
    path: []const u8,
) !void {
    var service = try K8sService.init(allocator);
    defer service.deinit();
    service.kubeconfig_parser_allocator = testing.allocator;
    service.setKubeconfigPath(path);
    const contexts = try service.listContexts();
    defer {
        for (contexts) |context| {
            allocator.free(context.name);
            allocator.free(context.cluster);
            allocator.free(context.user);
            if (context.namespace) |namespace| allocator.free(namespace);
        }
        allocator.free(contexts);
    }
    try testing.expectEqual(@as(usize, 1), contexts.len);
    try testing.expectEqualStrings("configured", contexts[0].name);
}

test "k8s_service: configured listContexts unwinds every output allocation" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "config",
        .data =
        \\apiVersion: v1
        \\kind: Config
        \\clusters:
        \\  - name: cluster
        \\    cluster:
        \\      server: http://127.0.0.1
        \\users:
        \\  - name: user
        \\    user:
        \\      token: test
        \\contexts:
        \\  - name: configured
        \\    context:
        \\      cluster: cluster
        \\      user: user
        \\      namespace: custom
        \\current-context: configured
        ,
    });
    const path = try std.fmt.allocPrint(
        testing.allocator,
        ".zig-cache/tmp/{s}/config",
        .{tmp.sub_path},
    );
    defer testing.allocator.free(path);
    try testing.checkAllAllocationFailures(
        testing.allocator,
        exerciseConfiguredContextAllocations,
        .{path},
    );
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

// --- Phase 1: pod log container handling ------------------------------------

test "getPodLogs: the container-aware entry point exists and stays NotConnected-safe" {
    // getPodLogs sent no container= parameter, so the API answered 400
    // "a container name must be specified" for any pod with a sidecar -- logs simply
    // failed on Istio-injected or init-heavy workloads. It now delegates to a
    // container-aware variant that falls back to the pod's first container.
    const allocator = std.testing.allocator;
    var svc = try K8sService.init(allocator);
    defer svc.deinit();

    // Both entry points must still reject cleanly when disconnected, and the
    // fallback must not be attempted in that state.
    try std.testing.expectError(error.NotConnected, svc.getPodLogs("p", "default", false));
    try std.testing.expectError(error.NotConnected, svc.getPodLogsForContainer("p", "default", false, null));
    try std.testing.expectError(error.NotConnected, svc.getPodLogsForContainer("p", "default", false, "istio-proxy"));
}

test "readonly does not block reading logs" {
    // Guard against over-broad guarding: --readonly must refuse mutations only.
    // A read path that started failing under --readonly would be a regression.
    const allocator = std.testing.allocator;
    var svc = try K8sService.init(allocator);
    defer svc.deinit();

    svc.readonly = true;
    // NotConnected, not ReadOnlyMode -- the guard is not on this path.
    try std.testing.expectError(error.NotConnected, svc.getPodLogs("p", "default", false));

    // listContexts reads the kubeconfig from disk, so it needs no cluster and may
    // legitimately succeed here. Whatever it returns, it must never be refused for
    // being read-only. Asserting the invariant rather than a specific outcome keeps
    // this from depending on whether the machine has a kubeconfig.
    if (svc.listContexts()) |ctxs| {
        // listContexts hands ownership of each field to the caller and only the
        // slice back; production moves the strings into its item list and frees the
        // slice. A test that keeps nothing must free both.
        defer {
            for (ctxs) |c| {
                allocator.free(c.name);
                allocator.free(c.cluster);
                allocator.free(c.user);
                if (c.namespace) |ns| allocator.free(ns);
            }
            allocator.free(ctxs);
        }
    } else |err| {
        try std.testing.expect(err != error.ReadOnlyMode);
    }
}

// --- Phase 1: unvalidated JSON must not panic ---------------------------------

test "a metav1.Status body has a STRING status field, which .object would panic on" {
    // This pins the shape, not our parser. When the API server rejects a request it
    // answers with metav1.Status, whose own `status` field is the string "Failure" --
    // not an object. checkAccess and getAuthorizationConditions both did
    // `status.object.get(...)` unguarded, so the panic happened on exactly the
    // response most in need of handling. The guards now test the tag first.
    const body =
        \\{"kind":"Status","apiVersion":"v1","metadata":{},"status":"Failure",
        \\ "message":"selfsubjectaccessreviews.authorization.k8s.io is forbidden",
        \\ "reason":"Forbidden","code":403}
    ;
    var parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, body, .{});
    defer parsed.deinit();

    try testing.expect(parsed.value == .object);
    const status = parsed.value.object.get("status").?;

    // The crux: a Status's `status` is a string. Any code reaching for .object here
    // panics, which is why every such access is now tag-checked.
    try testing.expect(status != .object);
    try testing.expect(status == .string);
    try testing.expectEqualStrings("Failure", status.string);
}

// --- Phase 4: the two views that looked functional and were not ---------------

test "endpoints and storageclasses resolve through ResourceType" {
    // resource_configs.zig defined EndpointsView and StorageClassesView, but
    // ResourceType had neither member -- so stringToEnum returned null and describe,
    // yaml and delete were all dead in both views. They rendered rows and then
    // silently ignored every action key.
    //
    // Values cross-checked against zig-klient's own resource_registry rather than
    // derived from memory: Endpoints is core /api/v1 and namespaced;
    // StorageClass is /apis/storage.k8s.io/v1 and CLUSTER-scoped.
    const RT = c3s.k8s_service_types.ResourceType;

    const ep = std.meta.stringToEnum(RT, "endpoints") orelse return error.EndpointsMissing;
    try testing.expectEqualStrings("/api/v1", ep.apiPath());
    try testing.expectEqualStrings("endpoints", ep.resourceName());
    try testing.expect(!ep.isClusterScoped());

    const sc = std.meta.stringToEnum(RT, "storageclasses") orelse return error.StorageClassesMissing;
    try testing.expectEqualStrings("/apis/storage.k8s.io/v1", sc.apiPath());
    try testing.expectEqualStrings("storageclasses", sc.resourceName());
    try testing.expect(sc.isClusterScoped());
}

test "every view name in resource_configs resolves to a ResourceType" {
    // The general form of the bug above: a view whose name does not resolve gets
    // dead action keys, silently. Rather than spot-check, assert the whole set --
    // this is the check that would have caught endpoints/storageclasses.
    const RT = c3s.k8s_service_types.ResourceType;
    const names = [_][]const u8{
        "pods",                            "deployments",                       "services",                  "namespaces",
        "nodes",                           "statefulsets",                      "daemonsets",                "replicasets",
        "jobs",                            "cronjobs",                          "configmaps",                "secrets",
        "persistentvolumes",               "persistentvolumeclaims",            "ingresses",                 "networkpolicies",
        "serviceaccounts",                 "roles",                             "rolebindings",              "clusterroles",
        "clusterrolebindings",             "events",                            "resourcequotas",            "limitranges",
        "poddisruptionbudgets",            "hpa",                               "endpoints",                 "storageclasses",
        "gatewayclasses",                  "gateways",                          "httproutes",                "grpcroutes",
        "referencegrants",                 "tcproutes",                         "tlsroutes",                 "udproutes",
        "backendtlspolicies",              "listenersets",                      "endpointslices",            "ingressclasses",
        "ipaddresses",                     "servicecidrs",                      "volumeattributesclasses",   "csidrivers",
        "validatingadmissionpolicies",     "validatingadmissionpolicybindings", "mutatingadmissionpolicies", "mutatingadmissionpolicybindings",
        "validatingwebhookconfigurations", "mutatingwebhookconfigurations",     "resourceclaims",            "deviceclasses",
        "priorityclasses",                 "runtimeclasses",                    "leases",                    "certificatesigningrequests",
        "storageversionmigrations",
    };
    for (names) |n| {
        if (std.meta.stringToEnum(RT, n) == null) {
            std.debug.print("view name does not resolve to a ResourceType: {s}\n", .{n});
            return error.UnresolvedViewName;
        }
    }
}

test "setNodeSchedulable respects --readonly and the connection check" {
    // cordon/uncordon are mutations, so they must be refused under --readonly like
    // every other. Worth an explicit test because this method takes the kubectl path
    // on BOTH transports rather than the direct-HTTP one, and it would be easy to add
    // a mutation there that forgot the guard entirely.
    const allocator = std.testing.allocator;
    var svc = try K8sService.init(allocator);
    defer svc.deinit();

    svc.readonly = true;
    svc.connected = true;
    try std.testing.expectError(error.ReadOnlyMode, svc.setNodeSchedulable("node-1", false));
    try std.testing.expectError(error.ReadOnlyMode, svc.setNodeSchedulable("node-1", true));

    // With readonly off, the connection check rejects instead -- so the guard is not
    // simply refusing unconditionally.
    svc.readonly = false;
    svc.connected = false;
    try std.testing.expectError(error.NotConnected, svc.setNodeSchedulable("node-1", false));
}

test "the pod-log query asks for timestamps, previous and container" {
    // Regression guard with real teeth: LogsView always fetches with timestamps and
    // strips them for display, so losing `timestamps=true` here silently turns the `t`
    // toggle into a no-op -- there would be no timestamps to reveal and nothing would
    // fail. A mutation deleting it survived the entire suite before this test existed.
    const allocator = std.testing.allocator;

    const plain = try K8sService.logQuery(allocator, false, null);
    defer allocator.free(plain);
    try std.testing.expect(std.mem.indexOf(u8, plain, "timestamps=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, plain, "tailLines=1000") != null);
    try std.testing.expect(std.mem.indexOf(u8, plain, "previous") == null);
    try std.testing.expect(std.mem.indexOf(u8, plain, "container") == null);

    const prev = try K8sService.logQuery(allocator, true, "sidecar");
    defer allocator.free(prev);
    try std.testing.expect(std.mem.indexOf(u8, prev, "timestamps=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, prev, "previous=true") != null);
    try std.testing.expect(std.mem.indexOf(u8, prev, "container=sidecar") != null);

    // Parameters must be & separated after the first, or the API server sees one
    // malformed key.
    try std.testing.expect(std.mem.indexOf(u8, prev, "&timestamps=true") != null);
}

test "runKubectl and spawnKubectl refuse under --readonly" {
    // These two used to skip assertMutable, so `set image` / `cp` / port-forward
    // ran under --readonly. The guard must fire before any subprocess is spawned.
    const allocator = std.testing.allocator;
    var svc = try K8sService.init(allocator);
    defer svc.deinit();

    svc.readonly = true;
    svc.connected = true;
    try std.testing.expectError(error.ReadOnlyMode, svc.runKubectl(&.{"version"}));
    try std.testing.expectError(error.ReadOnlyMode, svc.spawnKubectl(&.{ "port-forward", "svc/x", "80:80" }));
}

// =========================================================================
// Synchronous active-session foundation
// =========================================================================

const ActiveContextSession4A = c3s.ActiveContextSession;
const ActiveSessionSlot4A = c3s.ActiveSessionSlot;
const ContextSpec4A = c3s.ContextSpec;
const SessionFactory4A = c3s.k8s_active_context.SessionFactory;
const LifecycleEvent4A = c3s.k8s_active_context.LifecycleEvent;
const LifecycleObserver4A = c3s.k8s_active_context.LifecycleObserver;
const ProxyOwner4A = c3s.k8s_active_context.ProxyOwner;
const ProxyStarter4A = c3s.k8s_active_context.ProxyStarter;
const FallbackProbe4A = c3s.k8s_active_context.FallbackProbe;
const ReadinessProbe4A = c3s.k8s_active_context.ReadinessProbe;

const SessionHarness4A = struct {
    session_deinits: usize = 0,
    client_deinits: usize = 0,
    fallback_calls: usize = 0,
    proxy_start_calls: usize = 0,

    fn observe(context: *anyopaque, event: LifecycleEvent4A) void {
        const self: *SessionHarness4A = @ptrCast(@alignCast(context));
        switch (event) {
            .client_deinit => self.client_deinits += 1,
            .session_deinit => self.session_deinits += 1,
            else => {},
        }
    }

    fn readiness(context: *anyopaque, session: *ActiveContextSession4A) anyerror!void {
        _ = context;
        if (std.mem.eql(u8, session.spec.context_name, "bad") or
            std.mem.eql(u8, session.spec.context_name, "fallback"))
        {
            return error.DirectProbeFailed;
        }
    }

    fn startProxy(
        context: *anyopaque,
        _: *ActiveContextSession4A,
    ) anyerror!ProxyOwner4A {
        const self: *SessionHarness4A = @ptrCast(@alignCast(context));
        self.proxy_start_calls += 1;
        return error.ProxyStartFailed;
    }

    fn fallback(context: *anyopaque, session: *ActiveContextSession4A) anyerror!void {
        const self: *SessionHarness4A = @ptrCast(@alignCast(context));
        self.fallback_calls += 1;
        if (!std.mem.eql(u8, session.spec.context_name, "fallback")) {
            return error.ReadinessFailed;
        }
    }

    fn prepare(
        context: *anyopaque,
        allocator: std.mem.Allocator,
        io: std.Io,
        shared_event: *std.Io.Event,
        generation: u64,
        spec: ContextSpec4A,
    ) anyerror!*ActiveContextSession4A {
        const self: *SessionHarness4A = @ptrCast(@alignCast(context));
        const client = try allocator.create(c3s.K8sClient);
        errdefer allocator.destroy(client);
        client.* = try c3s.K8sClient.init(testing.allocator, io, .{
            .server = "http://127.0.0.1",
            .namespace = spec.default_namespace,
        });
        errdefer client.deinit();

        return ActiveContextSession4A.adopt(allocator, io, generation, spec, .{
            .shared_event = shared_event,
            .client = client,
            .cluster_name = spec.context_name,
            .user_name = "user",
            .readiness = ReadinessProbe4A.init(self, readiness),
            .proxy_starter = ProxyStarter4A.init(self, startProxy),
            .fallback_probe = FallbackProbe4A.init(self, fallback),
            .observer = LifecycleObserver4A.init(self, observe),
        });
    }

    fn factory(self: *SessionHarness4A) SessionFactory4A {
        return SessionFactory4A.init(self, prepare);
    }
};

fn releaseInstalledSession4A(
    service: *K8sService,
    slot: *ActiveSessionSlot4A,
) void {
    const session = slot.invalidate(null) catch unreachable orelse return;
    service.detachSession();
    session.deinit();
}

test "active session copies every ContextSpec slice" {
    const allocator = testing.allocator;
    const context_name = try allocator.dupe(u8, "copied-context");
    const kubeconfig_path = try allocator.dupe(u8, "/tmp/copied-config");
    const default_namespace = try allocator.dupe(u8, "copied-namespace");

    var shared_event: std.Io.Event = .unset;
    var harness = SessionHarness4A{};
    const session = try harness.factory().prepare(
        allocator,
        c3s.runtime.io(),
        &shared_event,
        7,
        .{
            .context_name = context_name,
            .kubeconfig_path = kubeconfig_path,
            .default_namespace = default_namespace,
            .force_proxy = false,
            .readonly = true,
        },
    );
    defer session.deinit();

    allocator.free(context_name);
    allocator.free(kubeconfig_path);
    allocator.free(default_namespace);

    try testing.expectEqualStrings("copied-context", session.spec.context_name);
    try testing.expectEqualStrings("/tmp/copied-config", session.spec.kubeconfig_path.?);
    try testing.expectEqualStrings("copied-namespace", session.spec.default_namespace);
    try testing.expect(session.spec.readonly);
}

test "slot acquisition checks generation and signals the shared Event on release" {
    var shared_event: std.Io.Event = .unset;
    var slot = ActiveSessionSlot4A.init(c3s.runtime.io(), &shared_event);
    var harness = SessionHarness4A{};
    const session = try harness.factory().prepare(
        testing.allocator,
        c3s.runtime.io(),
        &shared_event,
        11,
        .{
            .context_name = "one",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = false,
        },
    );
    try session.ensureReady();
    try testing.expect((try slot.commit(session)) == null);

    try testing.expectError(error.GenerationMismatch, slot.acquire(12, .command));
    var lease = (try slot.acquire(11, .command)).?;
    try testing.expectEqual(@as(usize, 1), session.leaseCount());
    try testing.expectEqual(@as(u64, 0), session.leaseEpoch());
    try testing.expect(lease.shared_event == &shared_event);
    _ = try lease.client();

    shared_event.reset();
    lease.release();
    try testing.expectEqual(@as(usize, 0), session.leaseCount());
    try testing.expectEqual(@as(u64, 1), session.leaseEpoch());
    try testing.expect(shared_event.isSet());
    try testing.expectError(error.LeaseReleased, lease.client());

    lease.release();
    try testing.expectEqual(@as(u64, 1), session.leaseEpoch());

    const removed = (try slot.invalidate(11)).?;
    try testing.expect((try slot.acquire(null, .command)) == null);
    removed.deinit();
}

test "teardown rejects a live caller lease and succeeds after release" {
    var shared_event: std.Io.Event = .unset;
    var slot = ActiveSessionSlot4A.init(c3s.runtime.io(), &shared_event);
    var harness = SessionHarness4A{};
    const session = try harness.factory().prepare(
        testing.allocator,
        c3s.runtime.io(),
        &shared_event,
        12,
        .{
            .context_name = "held",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = false,
        },
    );
    try session.ensureReady();
    _ = try slot.commit(session);
    try testing.expectError(error.SessionStillActive, session.checkTeardownReady());
    var lease = (try slot.acquire(null, .detail)).?;
    const removed = (try slot.invalidate(null)).?;

    try testing.expectError(error.LeasesOutstanding, removed.checkTeardownReady());
    lease.release();
    try removed.checkTeardownReady();
    removed.deinit();
}

test "K8sService installs once and all facade leases resolve one client generation" {
    var shared_event: std.Io.Event = .unset;
    var slot = ActiveSessionSlot4A.init(c3s.runtime.io(), &shared_event);
    var harness = SessionHarness4A{};
    var service = try K8sService.init(testing.allocator);
    defer service.deinit();
    service.bindSessionSlot(&slot);
    service.session_factory = harness.factory();
    service.setKubeconfigPath("/tmp/configured-kubeconfig");

    try service.connect("A");
    defer releaseInstalledSession4A(&service, &slot);

    var first = (try service.acquireRequest(.command)).?;
    defer first.release();
    var second = (try service.acquireRequest(.detail)).?;
    defer second.release();

    try testing.expectEqual(first.generation, second.generation);
    try testing.expect((try first.client()) == (try second.client()));
    try testing.expectEqual(@as(u64, 1), first.generation);
    try testing.expectEqualStrings("A", service.context_name);
    try testing.expect(service.isConnected());
    service.version_fetch_failed = true;
    try testing.expectEqualStrings("unknown", service.getServerVersion());
    service.version_fetch_failed = false;
    service.cached_k8s_version = try testing.allocator.dupe(u8, "v1.active");
    try testing.expectEqualStrings("v1.active", service.getServerVersion());
    try testing.expectEqualStrings(
        "/tmp/configured-kubeconfig",
        first.session.spec.kubeconfig_path.?,
    );
    try testing.expect(service.sessionSlot() == &slot);
}

test "readiness failure preserves the old slot facade and cache" {
    var shared_event: std.Io.Event = .unset;
    var slot = ActiveSessionSlot4A.init(c3s.runtime.io(), &shared_event);
    var harness = SessionHarness4A{};
    var service = try K8sService.init(testing.allocator);
    defer service.deinit();
    service.bindSessionSlot(&slot);
    service.session_factory = harness.factory();

    try service.connect("A");
    defer releaseInstalledSession4A(&service, &slot);
    service.cached_k8s_version = try testing.allocator.dupe(u8, "v1.cached");
    const before = slot.view();
    const deinits_before = harness.session_deinits;

    try testing.expectError(error.ReadinessFailed, service.switchContext("bad"));
    const after = slot.view();
    try testing.expectEqual(before.generation, after.generation);
    try testing.expectEqualStrings("A", service.context_name);
    try testing.expectEqualStrings("v1.cached", service.cached_k8s_version.?);
    try testing.expectEqual(deinits_before + 1, harness.session_deinits);
}

test "synchronous context switch changes slot and facade then tears down old" {
    var shared_event: std.Io.Event = .unset;
    var slot = ActiveSessionSlot4A.init(c3s.runtime.io(), &shared_event);
    var harness = SessionHarness4A{};
    var service = try K8sService.init(testing.allocator);
    defer service.deinit();
    service.bindSessionSlot(&slot);
    service.session_factory = harness.factory();

    try service.connect("A");
    defer releaseInstalledSession4A(&service, &slot);
    const generation_a = slot.view().generation;
    const deinits_before = harness.session_deinits;

    try service.switchContext("B");
    const generation_b = slot.view().generation;
    try testing.expect(generation_b > generation_a);
    try testing.expectEqualStrings("B", service.context_name);
    try testing.expectEqual(deinits_before + 1, harness.session_deinits);

    var first = (try service.acquireRequest(.command)).?;
    defer first.release();
    var second = (try service.acquireRequest(.detail)).?;
    defer second.release();
    try testing.expectEqual(generation_b, first.generation);
    try testing.expectEqual(first.generation, second.generation);
    try testing.expect((try first.client()) == (try second.client()));
}

test "slot invalidation blocks facade access before old session teardown" {
    var shared_event: std.Io.Event = .unset;
    var slot = ActiveSessionSlot4A.init(c3s.runtime.io(), &shared_event);
    var harness = SessionHarness4A{};
    var service = try K8sService.init(testing.allocator);
    defer service.deinit();
    service.bindSessionSlot(&slot);
    service.session_factory = harness.factory();

    try service.connect("A");
    service.cached_k8s_version = try testing.allocator.dupe(u8, "v1.stale");
    const namespace_before = try testing.allocator.dupe(
        u8,
        service.getCurrentNamespace(),
    );
    defer testing.allocator.free(namespace_before);
    const retired = (try slot.invalidate(null)).?;
    defer {
        service.detachSession();
        retired.deinit();
    }

    try testing.expect(!service.isConnected());
    try testing.expect((try service.acquireRequest(.detail)) == null);
    try testing.expectEqualStrings("n/a", service.getServerVersion());
    try testing.expectError(
        error.NotConnected,
        service.setCurrentNamespace("must-not-stick"),
    );
    try testing.expectEqualStrings(namespace_before, service.getCurrentNamespace());
    try testing.expect((try service.getPodMetrics(true)) == null);
    try testing.expectError(
        error.NotConnected,
        service.getRawJson(.pods, "pod-a", "default"),
    );
    try testing.expectError(
        error.NotConnected,
        service.deleteResource(.pods, "pod-a", "default", false),
    );
    try testing.expectEqual(@as(usize, 0), harness.client_deinits);
}

test "K8sService source has no raw session client alias or fallback" {
    const source = try std.Io.Dir.cwd().readFileAlloc(
        c3s.runtime.io(),
        "src/services/K8sService.zig",
        testing.allocator,
        .limited(1024 * 1024),
    );
    defer testing.allocator.free(source);

    try testing.expect(std.mem.indexOf(u8, source, "self." ++ "client") == null);
    try testing.expect(
        std.mem.indexOf(u8, source, ".client = session." ++ "client") == null,
    );
}

test "synchronous switch refuses to strand an old lease" {
    var shared_event: std.Io.Event = .unset;
    var slot = ActiveSessionSlot4A.init(c3s.runtime.io(), &shared_event);
    var harness = SessionHarness4A{};
    var service = try K8sService.init(testing.allocator);
    defer service.deinit();
    service.bindSessionSlot(&slot);
    service.session_factory = harness.factory();

    try service.connect("A");
    defer releaseInstalledSession4A(&service, &slot);
    var lease = (try service.acquireRequest(.command)).?;
    const generation_a = slot.view().generation;

    try testing.expectError(error.LeasesOutstanding, service.switchContext("B"));
    try testing.expectEqual(generation_a, slot.view().generation);
    try testing.expectEqualStrings("A", service.context_name);

    lease.release();
    try service.switchContext("B");
    try testing.expect(slot.view().generation > generation_a);
}

test "direct and proxy failure uses one verified fallback" {
    var shared_event: std.Io.Event = .unset;
    var harness = SessionHarness4A{};
    const session = try harness.factory().prepare(
        testing.allocator,
        c3s.runtime.io(),
        &shared_event,
        21,
        .{
            .context_name = "fallback",
            .kubeconfig_path = "/tmp/configured",
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = false,
        },
    );
    defer session.deinit();

    try session.ensureReady();
    try session.ensureReady();
    try testing.expect(session.isReady());
    try testing.expect(session.use_kubectl);
    try testing.expectEqual(@as(usize, 1), harness.proxy_start_calls);
    try testing.expectEqual(@as(usize, 1), harness.fallback_calls);
}

const ProxyHarness4A = struct {
    kills: usize = 0,
    deinits: usize = 0,

    fn kill(context: *anyopaque, _: std.Io) void {
        const self: *ProxyHarness4A = @ptrCast(@alignCast(context));
        self.kills += 1;
    }

    fn deinit(context: *anyopaque, _: std.mem.Allocator) void {
        const self: *ProxyHarness4A = @ptrCast(@alignCast(context));
        self.deinits += 1;
    }

    fn owner(self: *ProxyHarness4A, port: u16) ProxyOwner4A {
        return ProxyOwner4A.init(self, port, kill, deinit);
    }
};

const SuccessfulProxyStarter4A = struct {
    proxy: *ProxyHarness4A,
    entered: std.Io.Event = .unset,
    proceed: std.Io.Event = .unset,
    calls: std.atomic.Value(usize) = .init(0),

    fn start(
        context: *anyopaque,
        _: *ActiveContextSession4A,
    ) anyerror!ProxyOwner4A {
        const self: *SuccessfulProxyStarter4A = @ptrCast(@alignCast(context));
        _ = self.calls.fetchAdd(1, .acq_rel);
        self.entered.set(c3s.runtime.io());
        self.proceed.waitUncancelable(c3s.runtime.io());
        return self.proxy.owner(43124);
    }
};

fn startSessionProxy4A(session: *ActiveContextSession4A) !void {
    try session.startProxy();
}

test "concurrent proxy requests share one child owner" {
    var shared_event: std.Io.Event = .unset;
    var proxy = ProxyHarness4A{};
    var starter = SuccessfulProxyStarter4A{ .proxy = &proxy };
    const client = try testing.allocator.create(c3s.K8sClient);
    errdefer testing.allocator.destroy(client);
    client.* = try c3s.K8sClient.init(testing.allocator, c3s.runtime.io(), .{
        .server = "http://127.0.0.1",
        .namespace = "default",
    });
    errdefer client.deinit();
    const session = try ActiveContextSession4A.adopt(
        testing.allocator,
        c3s.runtime.io(),
        30,
        .{
            .context_name = "proxy-race",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = true,
            .readonly = false,
        },
        .{
            .shared_event = &shared_event,
            .client = client,
            .cluster_name = "cluster",
            .user_name = "user",
            .proxy_starter = ProxyStarter4A.init(&starter, SuccessfulProxyStarter4A.start),
        },
    );

    var first = try std.Io.concurrent(c3s.runtime.io(), startSessionProxy4A, .{session});
    try starter.entered.wait(c3s.runtime.io());
    var second = try std.Io.concurrent(c3s.runtime.io(), startSessionProxy4A, .{session});
    starter.proceed.set(c3s.runtime.io());
    try first.await(c3s.runtime.io());
    try second.await(c3s.runtime.io());

    try testing.expectEqual(@as(usize, 1), starter.calls.load(.acquire));
    session.deinit();
    try testing.expectEqual(@as(usize, 1), proxy.kills);
    try testing.expectEqual(@as(usize, 1), proxy.deinits);
}

test "session teardown kills its only proxy child exactly once" {
    var shared_event: std.Io.Event = .unset;
    var proxy = ProxyHarness4A{};
    const client = try testing.allocator.create(c3s.K8sClient);
    errdefer testing.allocator.destroy(client);
    client.* = try c3s.K8sClient.init(testing.allocator, c3s.runtime.io(), .{
        .server = "http://127.0.0.1",
        .namespace = "default",
    });
    errdefer client.deinit();
    const session = try ActiveContextSession4A.adopt(
        testing.allocator,
        c3s.runtime.io(),
        31,
        .{
            .context_name = "proxy",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = true,
            .readonly = false,
        },
        .{
            .shared_event = &shared_event,
            .client = client,
            .cluster_name = "cluster",
            .user_name = "user",
            .proxy = proxy.owner(43123),
            .readiness_verified = true,
        },
    );

    var slot = ActiveSessionSlot4A.init(c3s.runtime.io(), &shared_event);
    _ = try slot.commit(session);
    const removed = (try slot.invalidate(null)).?;
    removed.deinit();
    try testing.expectEqual(@as(usize, 1), proxy.kills);
    try testing.expectEqual(@as(usize, 1), proxy.deinits);
}

fn exerciseTask4ASetupAllocations(allocator: std.mem.Allocator) !void {
    const shared_event = try allocator.create(std.Io.Event);
    shared_event.* = .unset;
    defer allocator.destroy(shared_event);

    const slot = try allocator.create(ActiveSessionSlot4A);
    slot.* = ActiveSessionSlot4A.init(c3s.runtime.io(), shared_event);
    defer allocator.destroy(slot);

    const service = try allocator.create(K8sService);
    service.* = K8sService.init(allocator) catch |err| {
        allocator.destroy(service);
        return err;
    };
    defer {
        releaseInstalledSession4A(service, slot);
        service.deinit();
        allocator.destroy(service);
    }

    var harness = SessionHarness4A{};
    service.bindSessionSlot(slot);
    service.session_factory = harness.factory();
    try service.connect("allocation-context");
}

test "session slot context and facade setup unwind every allocation ordinal" {
    try testing.checkAllAllocationFailures(
        testing.allocator,
        exerciseTask4ASetupAllocations,
        .{},
    );
}
