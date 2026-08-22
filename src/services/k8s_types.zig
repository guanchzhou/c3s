/// Kubernetes Type Definitions
///
/// Shared type definitions used by K8sService and views.
/// Extracted from K8sService.zig for better modularity.
const std = @import("std");

/// Cluster information structure
pub const ClusterInfo = struct {
    context: []const u8,
    cluster: []const u8,
    user: []const u8,
    namespace: []const u8,
    connected: bool,
};

/// Resource type enum for generic operations (describe, delete, etc.)
pub const ResourceType = enum {
    pods,
    deployments,
    services,
    namespaces,
    nodes,
    statefulsets,
    daemonsets,
    replicasets,
    jobs,
    cronjobs,
    configmaps,
    secrets,
    persistentvolumes,
    persistentvolumeclaims,
    ingresses,
    networkpolicies,
    serviceaccounts,
    roles,
    rolebindings,
    clusterroles,
    clusterrolebindings,
    events,
    resourcequotas,
    limitranges,
    poddisruptionbudgets,
    hpa,
    // Views for these two existed in resource_configs.zig with no ResourceType
    // member, so stringToEnum returned null and describe / yaml / delete were dead
    // in both -- views that looked functional and were not.
    endpoints,
    storageclasses,
    contexts,

    pub fn apiPath(self: ResourceType) []const u8 {
        return switch (self) {
            .pods,
            .services,
            .namespaces,
            .nodes,
            .configmaps,
            .secrets,
            .persistentvolumes,
            .persistentvolumeclaims,
            .serviceaccounts,
            .events,
            .resourcequotas,
            .limitranges,
            .endpoints,
            => "/api/v1",
            .deployments, .statefulsets, .daemonsets, .replicasets => "/apis/apps/v1",
            .jobs, .cronjobs => "/apis/batch/v1",
            .ingresses, .networkpolicies => "/apis/networking.k8s.io/v1",
            .roles, .rolebindings, .clusterroles, .clusterrolebindings => "/apis/rbac.authorization.k8s.io/v1",
            .poddisruptionbudgets => "/apis/policy/v1",
            .hpa => "/apis/autoscaling/v2",
            .storageclasses => "/apis/storage.k8s.io/v1",
            .contexts => "/api/v1", // not a real K8s resource
        };
    }

    pub fn resourceName(self: ResourceType) []const u8 {
        return switch (self) {
            .pods => "pods",
            .deployments => "deployments",
            .services => "services",
            .namespaces => "namespaces",
            .nodes => "nodes",
            .statefulsets => "statefulsets",
            .daemonsets => "daemonsets",
            .replicasets => "replicasets",
            .jobs => "jobs",
            .cronjobs => "cronjobs",
            .configmaps => "configmaps",
            .secrets => "secrets",
            .persistentvolumes => "persistentvolumes",
            .persistentvolumeclaims => "persistentvolumeclaims",
            .ingresses => "ingresses",
            .networkpolicies => "networkpolicies",
            .serviceaccounts => "serviceaccounts",
            .roles => "roles",
            .rolebindings => "rolebindings",
            .clusterroles => "clusterroles",
            .clusterrolebindings => "clusterrolebindings",
            .events => "events",
            .resourcequotas => "resourcequotas",
            .limitranges => "limitranges",
            .poddisruptionbudgets => "poddisruptionbudgets",
            .hpa => "horizontalpodautoscalers",
            .endpoints => "endpoints",
            .storageclasses => "storageclasses",
            .contexts => "contexts",
        };
    }

    pub fn isClusterScoped(self: ResourceType) bool {
        return switch (self) {
            .namespaces, .nodes, .persistentvolumes, .clusterroles, .clusterrolebindings, .storageclasses => true,
            else => false,
        };
    }
};

/// Resource info returned by views for generic operations
pub const ResourceInfo = struct {
    name: []const u8,
    namespace: []const u8,
};

/// Aggregated CPU + memory usage for a single pod (sum of all containers)
pub const PodMetric = struct {
    cpu: []const u8, // e.g. "100m", "2", "n/a"
    mem: []const u8, // e.g. "45Mi", "1Gi", "n/a"
    cpu_milli: u64 = 0, // raw usage in millicores, for %-of-request math
    mem_bytes: u64 = 0, // raw usage in bytes, for %-of-request math
};

/// Context information structure
pub const ContextInfo = struct {
    name: []const u8,
    cluster: []const u8,
    user: []const u8,
    namespace: ?[]const u8,
    is_current: bool,
};

/// Result of an access check (SelfSubjectAccessReview)
pub const AccessCheckResult = struct {
    allowed: bool,
    conditional: bool,
    condition_count: u32,
};

/// Policy info from RBAC aggregation
pub const PolicyInfo = struct {
    source: []const u8,
    resource: []const u8,
    verbs: []const u8,
    subjects: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *PolicyInfo) void {
        self.allocator.free(self.source);
        self.allocator.free(self.resource);
        self.allocator.free(self.verbs);
        self.allocator.free(self.subjects);
    }
};

/// Condition info from AuthorizationConditionsReview
pub const ConditionInfo = struct {
    effect: []const u8,
    authorizer: []const u8,
    expression: []const u8,
    description: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ConditionInfo) void {
        self.allocator.free(self.effect);
        self.allocator.free(self.authorizer);
        self.allocator.free(self.expression);
        self.allocator.free(self.description);
    }
};
