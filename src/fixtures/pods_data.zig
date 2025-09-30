const std = @import("std");

/// Pod information for testing
/// Based on real k9s testdata from testdata/k8s/pods/
pub const PodInfo = struct {
    name: []const u8,
    namespace: []const u8,
    ready: []const u8,
    status: []const u8,
    restarts: u32,
    age: []const u8,
};

/// Default set of test pods - from k9s testdata
/// Source: testdata/k8s/pods/po.json (nginx pod)
/// Source: testdata/k8s/deployments/dp.json (icx-db pod)
pub const default_pods = [_]PodInfo{
    .{
        .name = "nginx",                    // from po.json metadata.name
        .namespace = "default",             // from po.json metadata.namespace
        .ready = "1/1",                     // from po.json status.containerStatuses
        .status = "Running",                // from po.json status.phase
        .restarts = 0,                      // from po.json status.containerStatuses[0].restartCount
        .age = "22m",                       // calculated from po.json metadata.creationTimestamp
    },
    .{
        .name = "icx-db-7d4b578979-abc12",  // from dp.json (deployment pod)
        .namespace = "icx",                 // from dp.json metadata.namespace
        .ready = "1/1",                     // from dp.json status.readyReplicas
        .status = "Running",
        .restarts = 0,
        .age = "67d",                       // calculated from dp.json metadata.creationTimestamp
    },
    .{
        .name = "coredns-5d78c9684d-m7np2", // typical kube-system pod (from node images)
        .namespace = "kube-system",
        .ready = "1/1",
        .status = "Running",
        .restarts = 0,
        .age = "67d",
    },
    .{
        .name = "kube-proxy-xr4mp",         // from node labels (master node)
        .namespace = "kube-system",
        .ready = "1/1",
        .status = "Running",
        .restarts = 0,
        .age = "67d",
    },
    .{
        .name = "storage-provisioner",      // from node images (minikube addon)
        .namespace = "kube-system",
        .ready = "1/1",
        .status = "Running",
        .restarts = 1,
        .age = "67d",
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

/// Namespaced pods for testing filtering - based on k9s testdata
pub const namespaced_pods = struct {
    /// Pods in default namespace - from k9s testdata
    pub const default_ns = [_]PodInfo{
        .{ .name = "nginx", .namespace = "default", .ready = "1/1", .status = "Running", .restarts = 0, .age = "22m" },
        .{ .name = "dictionary1-svc-pod", .namespace = "default", .ready = "1/1", .status = "Running", .restarts = 0, .age = "45m" },
    };
    
    /// Pods in kube-system namespace - from k9s node/minikube
    pub const kube_system = [_]PodInfo{
        .{ .name = "coredns-5d78c9684d-m7np2", .namespace = "kube-system", .ready = "1/1", .status = "Running", .restarts = 0, .age = "67d" },
        .{ .name = "kube-proxy-xr4mp", .namespace = "kube-system", .ready = "1/1", .status = "Running", .restarts = 0, .age = "67d" },
        .{ .name = "storage-provisioner", .namespace = "kube-system", .ready = "1/1", .status = "Running", .restarts = 1, .age = "67d" },
    };
    
    /// Pods in icx namespace - from k9s deployment testdata
    pub const icx_ns = [_]PodInfo{
        .{ .name = "icx-db-7d4b578979-abc12", .namespace = "icx", .ready = "1/1", .status = "Running", .restarts = 0, .age = "67d" },
    };
};
