const std = @import("std");
const KubeconfigParser = @import("../src/k8s/kubeconfig_json.zig").KubeconfigParser;
const K8sClient = @import("../src/k8s/client.zig").K8sClient;

test "kubectl JSON parser works" {
    const allocator = std.testing.allocator;

    var parser = KubeconfigParser.init(allocator);
    var kubeconfig = parser.load() catch |err| {
        std.debug.print("⚠️  kubectl not available or no kubeconfig: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer kubeconfig.deinit(allocator);

    try std.testing.expect(kubeconfig.clusters.len > 0);
    try std.testing.expect(kubeconfig.contexts.len > 0);
    try std.testing.expect(kubeconfig.current_context.len > 0);

    std.debug.print("✅ Found {d} clusters, {d} contexts\n", .{
        kubeconfig.clusters.len,
        kubeconfig.contexts.len,
    });
    std.debug.print("✅ Current context: {s}\n", .{kubeconfig.current_context});
}

test "kubectl API client can fetch version" {
    const allocator = std.testing.allocator;

    // Parse kubeconfig
    var parser = KubeconfigParser.init(allocator);
    var kubeconfig = parser.load() catch |err| {
        std.debug.print("⚠️  kubectl not available: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer kubeconfig.deinit(allocator);

    // Get current context
    const current_ctx = kubeconfig.getCurrentContext() orelse {
        std.debug.print("⚠️  No current context\n", .{});
        return error.SkipZigTest;
    };

    const cluster = kubeconfig.getCluster(current_ctx.cluster) orelse {
        std.debug.print("⚠️  Cluster not found\n", .{});
        return error.SkipZigTest;
    };

    // Create client
    var client = try K8sClient.init(allocator, .{
        .server = cluster.server,
        .token = null,
        .namespace = current_ctx.namespace,
    });
    defer client.deinit();

    // Try to get cluster info
    const info = client.getClusterInfo() catch |err| {
        std.debug.print("⚠️  Could not get cluster info (cluster may be unreachable): {}\n", .{err});
        return error.SkipZigTest;
    };
    defer allocator.free(info.k8s_version);

    try std.testing.expect(info.k8s_version.len > 0);
    std.debug.print("✅ Kubernetes version: {s}\n", .{info.k8s_version});
    std.debug.print("✅ CPU: {d}%, MEM: {d}%\n", .{ info.cpu_usage, info.mem_usage });
}

test "kubectl API client can list pods" {
    const allocator = std.testing.allocator;

    // Parse kubeconfig
    var parser = KubeconfigParser.init(allocator);
    var kubeconfig = parser.load() catch |err| {
        std.debug.print("⚠️  kubectl not available: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer kubeconfig.deinit(allocator);

    // Get current context
    const current_ctx = kubeconfig.getCurrentContext() orelse {
        std.debug.print("⚠️  No current context\n", .{});
        return error.SkipZigTest;
    };

    const cluster = kubeconfig.getCluster(current_ctx.cluster) orelse {
        std.debug.print("⚠️  Cluster not found\n", .{});
        return error.SkipZigTest;
    };

    // Create client
    var client = try K8sClient.init(allocator, .{
        .server = cluster.server,
        .token = null,
        .namespace = current_ctx.namespace,
    });
    defer client.deinit();

    // Try to list all pods
    const pods = client.listAllPods() catch |err| {
        std.debug.print("⚠️  Could not list pods (cluster may be unreachable): {}\n", .{err});
        return error.SkipZigTest;
    };
    defer {
        for (pods) |pod| {
            allocator.free(pod.name);
            allocator.free(pod.namespace);
            allocator.free(pod.ready);
            allocator.free(pod.status);
            allocator.free(pod.age);
            allocator.free(pod.node);
            allocator.free(pod.ip);
        }
        allocator.free(pods);
    }

    std.debug.print("✅ Found {d} pods\n", .{pods.len});
    if (pods.len > 0) {
        std.debug.print("✅ First pod: {s}/{s}\n", .{ pods[0].namespace, pods[0].name });
    }
}
