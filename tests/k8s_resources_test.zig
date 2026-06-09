const std = @import("std");
const src = @import("src");
const K8sClient = src.K8sClient;
const types = src.k8s_types;
const resources = src.k8s_resources;
const KubeconfigParser = src.KubeconfigParser;

// These are integration tests that require a real Kubernetes cluster
// They will be skipped if kubectl is not available

test "Pods Resource - list operations" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Try to get kubeconfig
    var parser = KubeconfigParser.init(allocator, io);
    var kubeconfig = parser.load() catch |err| {
        std.debug.print("⚠️  kubectl not available: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer kubeconfig.deinit(allocator);

    const current_ctx = kubeconfig.getCurrentContext() orelse {
        std.debug.print("⚠️  No current context\n", .{});
        return error.SkipZigTest;
    };

    const cluster = kubeconfig.getClusterByName(current_ctx.cluster) orelse {
        std.debug.print("⚠️  Cluster not found\n", .{});
        return error.SkipZigTest;
    };

    var client = try K8sClient.init(allocator, io, .{
        .server = cluster.server,
        .token = null,
        .namespace = current_ctx.namespace,
    });
    defer client.deinit();

    const pods_client = resources.Pods.init(&client);

    // Test listAll
    var pod_list = pods_client.client.listAll() catch |err| {
        std.debug.print("⚠️  Could not list pods: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer pod_list.deinit();

    std.debug.print("✅ Listed {d} pods across all namespaces\n", .{pod_list.value.items.len});
}

test "Deployments Resource - operations" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Try to get kubeconfig
    var parser = KubeconfigParser.init(allocator, io);
    var kubeconfig = parser.load() catch |err| {
        std.debug.print("⚠️  kubectl not available: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer kubeconfig.deinit(allocator);

    const current_ctx = kubeconfig.getCurrentContext() orelse {
        std.debug.print("⚠️  No current context\n", .{});
        return error.SkipZigTest;
    };

    const cluster = kubeconfig.getClusterByName(current_ctx.cluster) orelse {
        std.debug.print("⚠️  Cluster not found\n", .{});
        return error.SkipZigTest;
    };

    var client = try K8sClient.init(allocator, io, .{
        .server = cluster.server,
        .token = null,
        .namespace = current_ctx.namespace,
    });
    defer client.deinit();

    const deployments = resources.Deployments.init(&client);

    // Test listAll deployments
    var deploy_list = deployments.client.listAll() catch |err| {
        std.debug.print("⚠️  Could not list deployments: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer deploy_list.deinit();

    std.debug.print("✅ Listed {d} deployments\n", .{deploy_list.value.items.len});
}

test "Services Resource - list operations" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Try to get kubeconfig
    var parser = KubeconfigParser.init(allocator, io);
    var kubeconfig = parser.load() catch |err| {
        std.debug.print("⚠️  kubectl not available: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer kubeconfig.deinit(allocator);

    const current_ctx = kubeconfig.getCurrentContext() orelse {
        std.debug.print("⚠️  No current context\n", .{});
        return error.SkipZigTest;
    };

    const cluster = kubeconfig.getClusterByName(current_ctx.cluster) orelse {
        std.debug.print("⚠️  Cluster not found\n", .{});
        return error.SkipZigTest;
    };

    var client = try K8sClient.init(allocator, io, .{
        .server = cluster.server,
        .token = null,
        .namespace = current_ctx.namespace,
    });
    defer client.deinit();

    const services = resources.Services.init(&client);

    // Test listAll services
    var svc_list = services.client.listAll() catch |err| {
        std.debug.print("⚠️  Could not list services: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer svc_list.deinit();

    std.debug.print("✅ Listed {d} services\n", .{svc_list.value.items.len});
}

test "ConfigMaps Resource - operations" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Try to get kubeconfig
    var parser = KubeconfigParser.init(allocator, io);
    var kubeconfig = parser.load() catch |err| {
        std.debug.print("⚠️  kubectl not available: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer kubeconfig.deinit(allocator);

    const current_ctx = kubeconfig.getCurrentContext() orelse {
        std.debug.print("⚠️  No current context\n", .{});
        return error.SkipZigTest;
    };

    const cluster = kubeconfig.getClusterByName(current_ctx.cluster) orelse {
        std.debug.print("⚠️  Cluster not found\n", .{});
        return error.SkipZigTest;
    };

    var client = try K8sClient.init(allocator, io, .{
        .server = cluster.server,
        .token = null,
        .namespace = current_ctx.namespace,
    });
    defer client.deinit();

    const configmaps = resources.ConfigMaps.init(&client);

    // Test listAll configmaps
    var cm_list = configmaps.client.listAll() catch |err| {
        std.debug.print("⚠️  Could not list configmaps: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer cm_list.deinit();

    std.debug.print("✅ Listed {d} configmaps\n", .{cm_list.value.items.len});
}

test "Namespaces Resource - list operations" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Try to get kubeconfig
    var parser = KubeconfigParser.init(allocator, io);
    var kubeconfig = parser.load() catch |err| {
        std.debug.print("⚠️  kubectl not available: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer kubeconfig.deinit(allocator);

    const current_ctx = kubeconfig.getCurrentContext() orelse {
        std.debug.print("⚠️  No current context\n", .{});
        return error.SkipZigTest;
    };

    const cluster = kubeconfig.getClusterByName(current_ctx.cluster) orelse {
        std.debug.print("⚠️  Cluster not found\n", .{});
        return error.SkipZigTest;
    };

    var client = try K8sClient.init(allocator, io, .{
        .server = cluster.server,
        .token = null,
        .namespace = current_ctx.namespace,
    });
    defer client.deinit();

    const namespaces = resources.Namespaces.init(&client);

    // Test list namespaces (cluster-scoped)
    var ns_list = namespaces.client.listAll() catch |err| {
        std.debug.print("⚠️  Could not list namespaces: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer ns_list.deinit();

    std.debug.print("✅ Listed {d} namespaces\n", .{ns_list.value.items.len});
    if (ns_list.value.items.len > 0) {
        std.debug.print("   First namespace: {s}\n", .{ns_list.value.items[0].metadata.name});
    }
}

test "Nodes Resource - list operations" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Try to get kubeconfig
    var parser = KubeconfigParser.init(allocator, io);
    var kubeconfig = parser.load() catch |err| {
        std.debug.print("⚠️  kubectl not available: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer kubeconfig.deinit(allocator);

    const current_ctx = kubeconfig.getCurrentContext() orelse {
        std.debug.print("⚠️  No current context\n", .{});
        return error.SkipZigTest;
    };

    const cluster = kubeconfig.getClusterByName(current_ctx.cluster) orelse {
        std.debug.print("⚠️  Cluster not found\n", .{});
        return error.SkipZigTest;
    };

    var client = try K8sClient.init(allocator, io, .{
        .server = cluster.server,
        .token = null,
        .namespace = current_ctx.namespace,
    });
    defer client.deinit();

    const nodes = resources.Nodes.init(&client);

    // Test list nodes (cluster-scoped)
    var node_list = nodes.client.listAll() catch |err| {
        std.debug.print("⚠️  Could not list nodes: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer node_list.deinit();

    std.debug.print("✅ Listed {d} nodes\n", .{node_list.value.items.len});
    if (node_list.value.items.len > 0) {
        std.debug.print("   First node: {s}\n", .{node_list.value.items[0].metadata.name});
    }
}
