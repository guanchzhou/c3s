const std = @import("std");

/// Pod information for testing
pub const PodInfo = struct {
    name: []const u8,
    namespace: []const u8,
    ready: []const u8,
    status: []const u8,
    restarts: u32,
    age: []const u8,
};

/// Default set of test pods - typical application pods
pub const default_pods = [_]PodInfo{
    .{
        .name = "nginx-deployment-7d64c9d5d9-x8k2p",
        .namespace = "default",
        .ready = "1/1",
        .status = "Running",
        .restarts = 0,
        .age = "2d",
    },
    .{
        .name = "redis-master-0",
        .namespace = "default",
        .ready = "1/1",
        .status = "Running",
        .restarts = 1,
        .age = "5d",
    },
    .{
        .name = "postgres-statefulset-0",
        .namespace = "database",
        .ready = "1/1",
        .status = "Running",
        .restarts = 0,
        .age = "12d",
    },
    .{
        .name = "api-server-5c8d9b7f4-jh9kl",
        .namespace = "production",
        .ready = "2/2",
        .status = "Running",
        .restarts = 0,
        .age = "3h",
    },
    .{
        .name = "worker-processor-6d7f8c9-m4n2p",
        .namespace = "production",
        .ready = "1/1",
        .status = "Running",
        .restarts = 5,
        .age = "1d",
    },
};

/// Pods with various statuses for testing
pub const mixed_status_pods = [_]PodInfo{
    .{
        .name = "running-pod-abc123",
        .namespace = "default",
        .ready = "1/1",
        .status = "Running",
        .restarts = 0,
        .age = "10m",
    },
    .{
        .name = "pending-pod-def456",
        .namespace = "default",
        .ready = "0/1",
        .status = "Pending",
        .restarts = 0,
        .age = "2m",
    },
    .{
        .name = "crashloop-pod-ghi789",
        .namespace = "default",
        .ready = "0/1",
        .status = "CrashLoopBackOff",
        .restarts = 15,
        .age = "30m",
    },
    .{
        .name = "error-pod-jkl012",
        .namespace = "default",
        .ready = "0/1",
        .status = "Error",
        .restarts = 3,
        .age = "5m",
    },
    .{
        .name = "completed-job-mno345",
        .namespace = "jobs",
        .ready = "0/1",
        .status = "Succeeded",
        .restarts = 0,
        .age = "1h",
    },
    .{
        .name = "init-pod-pqr678",
        .namespace = "default",
        .ready = "0/2",
        .status = "Init:0/1",
        .restarts = 0,
        .age = "15s",
    },
};

/// Large set of pods for testing scrolling and performance
pub fn generateManyPods(allocator: std.mem.Allocator, count: usize) ![]PodInfo {
    const pods = try allocator.alloc(PodInfo, count);
    
    for (pods, 0..) |*pod, i| {
        const name = try std.fmt.allocPrint(allocator, "pod-{d}-{s}", .{ i, randomId() });
        const namespace = if (i % 3 == 0) "default" else if (i % 3 == 1) "kube-system" else "production";
        const ready = if (i % 5 == 0) "0/1" else "1/1";
        const status = if (i % 7 == 0) "Pending" else if (i % 11 == 0) "CrashLoopBackOff" else "Running";
        const restarts: u32 = @intCast(i % 10);
        const age = if (i % 4 == 0) "10m" else if (i % 4 == 1) "2h" else if (i % 4 == 2) "3d" else "1w";
        
        pod.* = PodInfo{
            .name = name,
            .namespace = namespace,
            .ready = ready,
            .status = status,
            .restarts = restarts,
            .age = age,
        };
    }
    
    return pods;
}

/// Helper to generate random-looking IDs
fn randomId() []const u8 {
    const ids = [_][]const u8{
        "a1b2c3", "d4e5f6", "g7h8i9", "j0k1l2", "m3n4o5",
        "p6q7r8", "s9t0u1", "v2w3x4", "y5z6a7", "b8c9d0",
    };
    return ids[@import("std").crypto.random.intRangeAtMost(usize, 0, ids.len - 1)];
}

/// Namespaced pods for testing filtering
pub const namespaced_pods = struct {
    pub const default_ns = [_]PodInfo{
        .{ .name = "app-1", .namespace = "default", .ready = "1/1", .status = "Running", .restarts = 0, .age = "1d" },
        .{ .name = "app-2", .namespace = "default", .ready = "1/1", .status = "Running", .restarts = 0, .age = "1d" },
    };
    
    pub const kube_system = [_]PodInfo{
        .{ .name = "coredns-1", .namespace = "kube-system", .ready = "1/1", .status = "Running", .restarts = 0, .age = "30d" },
        .{ .name = "kube-proxy", .namespace = "kube-system", .ready = "1/1", .status = "Running", .restarts = 0, .age = "30d" },
    };
    
    pub const production = [_]PodInfo{
        .{ .name = "api-server", .namespace = "production", .ready = "2/2", .status = "Running", .restarts = 0, .age = "5d" },
        .{ .name = "worker-pool", .namespace = "production", .ready = "1/1", .status = "Running", .restarts = 2, .age = "3d" },
    };
};
