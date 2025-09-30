const std = @import("std");

/// Dummy Kubernetes data for testing and development
pub const K8sData = struct {
    context: []const u8,
    cluster: []const u8,
    user: []const u8,
    k8s_version: []const u8,
    cpu_usage: u8,
    mem_usage: u8,
};

/// Default test data set - typical dev environment
pub const default_data = K8sData{
    .context = "rancher-desktop [RW]",
    .cluster = "rancher-desktop",
    .user = "rancher-desktop",
    .k8s_version = "v1.33.3+k3s1",
    .cpu_usage = 2,
    .mem_usage = 27,
};

/// Minimal test data - very short values for testing compression
pub const minimal_data = K8sData{
    .context = "dev [RO]",
    .cluster = "local",
    .user = "me",
    .k8s_version = "v1.28",
    .cpu_usage = 5,
    .mem_usage = 10,
};

/// Production-like test data - longer realistic names
pub const production_data = K8sData{
    .context = "production-us-east-1 [RW]",
    .cluster = "eks-prod-cluster-01",
    .user = "admin@company.com",
    .k8s_version = "v1.29.2+eks.1",
    .cpu_usage = 67,
    .mem_usage = 82,
};

/// High load test data - testing with high resource usage
pub const high_load_data = K8sData{
    .context = "staging-cluster [RW]",
    .cluster = "gke-staging-us-central1",
    .user = "devops-team",
    .k8s_version = "v1.30.0-rc.1",
    .cpu_usage = 95,
    .mem_usage = 98,
};

/// Multi-cluster test data - for testing cluster switching
pub const multi_cluster_data = [_]K8sData{
    .{
        .context = "minikube [RW]",
        .cluster = "minikube",
        .user = "minikube",
        .k8s_version = "v1.28.3",
        .cpu_usage = 15,
        .mem_usage = 25,
    },
    .{
        .context = "kind-dev [RW]",
        .cluster = "kind-dev",
        .user = "kind-dev",
        .k8s_version = "v1.29.1",
        .cpu_usage = 8,
        .mem_usage = 18,
    },
    .{
        .context = "docker-desktop [RW]",
        .cluster = "docker-desktop",
        .user = "docker-desktop",
        .k8s_version = "v1.29.2",
        .cpu_usage = 12,
        .mem_usage = 22,
    },
};

/// Empty/N/A data - for when not connected to cluster
pub const empty_data = K8sData{
    .context = "n/a",
    .cluster = "n/a",
    .user = "n/a",
    .k8s_version = "n/a",
    .cpu_usage = 0,
    .mem_usage = 0,
};

/// Get formatted CPU string
pub fn getCpuString(allocator: std.mem.Allocator, cpu_usage: u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{}%", .{cpu_usage});
}

/// Get formatted memory string
pub fn getMemString(allocator: std.mem.Allocator, mem_usage: u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{}%", .{mem_usage});
}

/// Get data based on debug flag
pub fn getData(debug: bool) K8sData {
    return if (debug) default_data else empty_data;
}
