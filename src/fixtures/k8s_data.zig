const std = @import("std");

/// Kubernetes cluster data for testing and development
/// Based on real k9s testdata from testdata/k8s/
pub const K8sData = struct {
    context: []const u8,
    cluster: []const u8,
    user: []const u8,
    k8s_version: []const u8,
    cpu_usage: u8,
    mem_usage: u8,
};

/// Default test data - from k9s testdata (minikube node, fred context)
/// Source: testdata/k8s/nodes/no.json + testdata/k8s/config/kubeconfig
pub const default_data = K8sData{
    .context = "fred [RW]",           // from kubeconfig current-context
    .cluster = "zorg",                // from fred context cluster
    .user = "fred",                   // from fred context user
    .k8s_version = "v1.15.2",         // from minikube node kubeletVersion
    .cpu_usage = 25,                  // simulated based on 4 CPU capacity
    .mem_usage = 35,                  // simulated based on 8GB capacity
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

/// Blee context test data - from k9s testdata (alternate context)
/// Source: testdata/k8s/config/kubeconfig (blee context)
pub const blee_data = K8sData{
    .context = "blee [RW]",           // from kubeconfig
    .cluster = "blee",                // from blee context cluster
    .user = "blee",                   // from blee context user
    .k8s_version = "v1.15.2",         // same minikube version
    .cpu_usage = 18,
    .mem_usage = 42,
};

/// Minikube test data - from k9s testdata (explicit minikube)
/// Source: testdata/k8s/nodes/no.json (real minikube node)
pub const minikube_data = K8sData{
    .context = "minikube [RW]",
    .cluster = "minikube",
    .user = "minikube",
    .k8s_version = "v1.15.2",         // from no.json kubeletVersion
    .cpu_usage = 22,                  // 4 CPU capacity
    .mem_usage = 48,                  // 8165556Ki capacity (~8GB)
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

/// Multi-cluster test data - from k9s kubeconfig testdata
/// Source: testdata/k8s/config/kubeconfig (all 3 contexts)
pub const multi_cluster_data = [_]K8sData{
    .{
        .context = "fred [RW]",              // current-context from kubeconfig
        .cluster = "zorg",
        .user = "fred",
        .k8s_version = "v1.15.2",
        .cpu_usage = 25,
        .mem_usage = 35,
    },
    .{
        .context = "blee [RW]",              // alternate context (namespace: zorg)
        .cluster = "blee",
        .user = "blee",
        .k8s_version = "v1.15.2",
        .cpu_usage = 18,
        .mem_usage = 42,
    },
    .{
        .context = "duh [RW]",               // third context from kubeconfig
        .cluster = "duh",
        .user = "duh",
        .k8s_version = "v1.15.2",
        .cpu_usage = 12,
        .mem_usage = 28,
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
