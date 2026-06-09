const std = @import("std");
const src = @import("src");
const K8sClient = src.K8sClient;
const types = src.k8s_types;
const resources = src.k8s_resources;

test "K8sClient - HTTP Methods" {
    // Test Method enum
    try std.testing.expectEqual(K8sClient.Method.GET, .GET);
    try std.testing.expectEqual(K8sClient.Method.POST, .POST);
    try std.testing.expectEqual(K8sClient.Method.PUT, .PUT);
    try std.testing.expectEqual(K8sClient.Method.DELETE, .DELETE);
    try std.testing.expectEqual(K8sClient.Method.PATCH, .PATCH);

    std.debug.print("✅ HTTP Methods enum test passed\n", .{});
}

test "K8sClient - Config" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = try K8sClient.init(allocator, io, .{
        .server = "https://api.cluster.example.com",
        .token = "test-bearer-token",
        .namespace = "test-namespace",
    });
    defer client.deinit();

    try std.testing.expectEqualStrings("https://api.cluster.example.com", client.api_server);
    try std.testing.expectEqualStrings("test-bearer-token", client.token.?);
    try std.testing.expectEqualStrings("test-namespace", client.namespace);

    std.debug.print("✅ K8sClient Config test passed\n", .{});
}

test "K8sClient - Default namespace" {
    const allocator = std.testing.allocator;

    var threaded = std.Io.Threaded.init(std.testing.allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = try K8sClient.init(allocator, io, .{
        .server = "https://api.cluster.example.com",
    });
    defer client.deinit();

    try std.testing.expectEqualStrings("default", client.namespace);
    try std.testing.expect(client.token == null);

    std.debug.print("✅ Default namespace test passed\n", .{});
}

test "Resource Types - ObjectMeta" {
    const meta = types.ObjectMeta{
        .name = "test-pod",
        .namespace = "default",
        .uid = "123-456-789",
    };

    try std.testing.expectEqualStrings("test-pod", meta.name);
    try std.testing.expectEqualStrings("default", meta.namespace.?);
    try std.testing.expectEqualStrings("123-456-789", meta.uid.?);

    std.debug.print("✅ ObjectMeta test passed\n", .{});
}

test "Resource Types - PodSpec" {
    var ports = [_]types.ContainerPort{.{ .containerPort = 80 }};
    var containers = [_]types.Container{
        .{
            .name = "nginx",
            .image = "nginx:latest",
            .ports = @as(?[]types.ContainerPort, &ports),
        },
    };

    const spec = types.PodSpec{
        .containers = &containers,
        .restartPolicy = "Always",
    };

    try std.testing.expectEqual(1, spec.containers.?.len);
    try std.testing.expectEqualStrings("nginx", spec.containers.?[0].name.?);
    try std.testing.expectEqualStrings("nginx:latest", spec.containers.?[0].image.?);
    try std.testing.expectEqualStrings("Always", spec.restartPolicy.?);

    std.debug.print("✅ PodSpec test passed\n", .{});
}

test "Resource Types - ServiceSpec" {
    var ports = [_]types.ServicePort{
        .{
            .name = "http",
            .protocol = "TCP",
            .port = .{ .integer = 80 },
            .targetPort = .{ .integer = 8080 },
        },
    };

    const spec = types.ServiceSpec{
        .ports = &ports,
        .type = "ClusterIP",
    };

    try std.testing.expectEqual(1, spec.ports.?.len);
    try std.testing.expectEqualStrings("http", spec.ports.?[0].name.?);
    try std.testing.expectEqual(80, spec.ports.?[0].port.?.integer);
    try std.testing.expectEqualStrings("ClusterIP", spec.type.?);

    std.debug.print("✅ ServiceSpec test passed\n", .{});
}

test "Resource Types - DeploymentSpec" {
    // selector/template are now std.json.Value in klient v0.3.2; only replicas
    // is a typed scalar we can assert on here.
    const spec = types.DeploymentSpec{
        .replicas = 3,
        .selector = null,
        .template = null,
    };

    try std.testing.expectEqual(3, spec.replicas.?);

    std.debug.print("✅ DeploymentSpec test passed\n", .{});
}

test "Pod Structure" {
    var containers = [_]types.Container{
        .{
            .name = "nginx",
            .image = "nginx:1.21",
        },
    };

    const pod = types.Pod{
        .apiVersion = "v1",
        .kind = "Pod",
        .metadata = .{
            .name = "test-pod",
            .namespace = "default",
        },
        .spec = .{
            .containers = &containers,
        },
    };

    // Test structure
    try std.testing.expectEqualStrings("v1", pod.apiVersion.?);
    try std.testing.expectEqualStrings("Pod", pod.kind.?);
    try std.testing.expectEqualStrings("test-pod", pod.metadata.name);
    try std.testing.expectEqualStrings("default", pod.metadata.namespace.?);
    try std.testing.expectEqualStrings("nginx", pod.spec.?.containers.?[0].name.?);
    try std.testing.expectEqualStrings("nginx:1.21", pod.spec.?.containers.?[0].image.?);

    std.debug.print("✅ Pod structure test passed\n", .{});
}
