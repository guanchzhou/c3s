/// Resource Configs - Declarative definitions for all 25 K8s resource views.
/// Each resource defines a transform function and a ResourceView instantiation.
const std = @import("std");
const klient = @import("klient");
const resource_view = @import("resource_view.zig");
const ResourceView = resource_view.ResourceView;
const ColumnDef = resource_view.ColumnDef;
const Config = resource_view.Config;
const age_util = @import("../viewmodel/age.zig");
const table_layout = @import("../ui/table_layout.zig");
const clock = @import("../core/clock.zig");

const P = table_layout.ColumnPriority;

// ============================================================================
// Helper: extract an integer from a JSON Value object field
// ============================================================================
fn jsonInt(obj: std.json.ObjectMap, key: []const u8) i32 {
    if (obj.get(key)) |val| {
        if (val == .integer) return @intCast(val.integer);
    }
    return 0;
}

fn jsonStr(obj: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    if (obj.get(key)) |val| {
        if (val == .string) return val.string;
    }
    return null;
}

fn statusInt(status: ?std.json.Value, key: []const u8) i32 {
    if (status) |s| {
        if (s == .object) return jsonInt(s.object, key);
    }
    return 0;
}

fn statusStr(status: ?std.json.Value, key: []const u8) ?[]const u8 {
    if (status) |s| {
        if (s == .object) return jsonStr(s.object, key);
    }
    return null;
}

fn intToStr(alloc: std.mem.Allocator, val: i32) ![]const u8 {
    return std.fmt.allocPrint(alloc, "{d}", .{val});
}

// ============================================================================
// === Deployments ===
// ============================================================================
fn transformDeployment(dep: klient.types.Deployment, alloc: std.mem.Allocator) ![5][]const u8 {
    const ready_replicas = statusInt(dep.status, "readyReplicas");
    const available_replicas = statusInt(dep.status, "availableReplicas");
    const replicas: i32 = if (dep.spec) |s| s.replicas orelse 0 else 0;

    return .{
        try alloc.dupe(u8, if (dep.metadata.namespace) |ns| ns else "default"),
        try alloc.dupe(u8, dep.metadata.name),
        try std.fmt.allocPrint(alloc, "{d}/{d}", .{ ready_replicas, replicas }),
        try intToStr(alloc, available_replicas),
        try age_util.calculateAge(alloc, dep.metadata.creationTimestamp),
    };
}

pub const DeploymentsView = ResourceView(klient.types.Deployment, klient.resources.Deployments, .{
    .name = "deployments",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "READY", .min_width = 7, .max_width = 12, .priority = P.HIGH },
        .{ .name = "AVAILABLE", .min_width = 5, .max_width = 10, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformDeployment);

// ============================================================================
// === Services ===
// ============================================================================
fn transformService(svc: klient.types.Service, alloc: std.mem.Allocator) ![7][]const u8 {
    const ports_str = if (svc.spec) |spec| blk: {
        if (spec.ports) |ports| {
            if (ports.len > 0) {
                const port_num = if (ports[0].port) |p| blk2: {
                    if (p == .integer) break :blk2 @as(i64, @intCast(p.integer));
                    break :blk2 @as(i64, 0);
                } else 0;

                var buf: [64]u8 = undefined;
                const port_str = try std.fmt.bufPrint(
                    &buf,
                    "{d}/{s}",
                    .{ port_num, ports[0].protocol orelse "TCP" },
                );
                break :blk try alloc.dupe(u8, port_str);
            }
        }
        break :blk try alloc.dupe(u8, "<none>");
    } else try alloc.dupe(u8, "<none>");

    return .{
        try alloc.dupe(u8, if (svc.metadata.namespace) |ns| ns else "default"),
        try alloc.dupe(u8, svc.metadata.name),
        if (svc.spec) |spec|
            try alloc.dupe(u8, spec.type orelse "ClusterIP")
        else
            try alloc.dupe(u8, "Unknown"),
        if (svc.spec) |spec|
            try alloc.dupe(u8, spec.clusterIP orelse "<none>")
        else
            try alloc.dupe(u8, "<none>"),
        try alloc.dupe(u8, "<pending>"),
        ports_str,
        try age_util.calculateAge(alloc, svc.metadata.creationTimestamp),
    };
}

pub const ServicesView = ResourceView(klient.types.Service, klient.resources.Services, .{
    .name = "services",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "TYPE", .min_width = 8, .max_width = 14, .priority = P.HIGH },
        .{ .name = "CLUSTER-IP", .min_width = 10, .max_width = 16, .priority = P.MEDIUM },
        .{ .name = "EXTERNAL-IP", .min_width = 10, .max_width = 16, .priority = P.LOW },
        .{ .name = "PORTS", .min_width = 8, .max_width = 16, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformService);

// ============================================================================
// === ConfigMaps ===
// ============================================================================
fn transformConfigMap(cm: klient.types.ConfigMap, alloc: std.mem.Allocator) ![4][]const u8 {
    const keys: usize = if (cm.spec) |spec| blk: {
        if (spec.data) |data_json| {
            if (data_json == .object) break :blk data_json.object.count();
        }
        break :blk 0;
    } else 0;

    return .{
        try alloc.dupe(u8, cm.metadata.namespace orelse "default"),
        try alloc.dupe(u8, cm.metadata.name),
        try std.fmt.allocPrint(alloc, "{d}", .{keys}),
        try age_util.calculateAge(alloc, cm.metadata.creationTimestamp),
    };
}

pub const ConfigMapsView = ResourceView(klient.types.ConfigMap, klient.resources.ConfigMaps, .{
    .name = "configmaps",
    .is_namespaced = true,
    .default_all_namespaces = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "KEYS", .min_width = 5, .max_width = 8, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformConfigMap);

// ============================================================================
// === Secrets ===
// ============================================================================
fn transformSecret(secret: klient.types.Secret, alloc: std.mem.Allocator) ![5][]const u8 {
    const keys: usize = if (secret.data) |data_json| blk: {
        if (data_json == .object) break :blk data_json.object.count();
        break :blk 0;
    } else 0;

    return .{
        try alloc.dupe(u8, secret.metadata.namespace orelse "default"),
        try alloc.dupe(u8, secret.metadata.name),
        if (secret.type) |t| try alloc.dupe(u8, t) else try alloc.dupe(u8, "Opaque"),
        try std.fmt.allocPrint(alloc, "{d}", .{keys}),
        try age_util.calculateAge(alloc, secret.metadata.creationTimestamp),
    };
}

pub const SecretsView = ResourceView(klient.types.Secret, klient.resources.Secrets, .{
    .name = "secrets",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "TYPE", .min_width = 8, .max_width = 20, .priority = P.HIGH },
        .{ .name = "KEYS", .min_width = 5, .max_width = 8, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformSecret);

// ============================================================================
// === StatefulSets ===
// ============================================================================
fn transformStatefulSet(sts: klient.types.StatefulSet, alloc: std.mem.Allocator) ![4][]const u8 {
    const ready = statusInt(sts.status, "readyReplicas");
    const desired: i32 = if (sts.spec) |s| s.replicas orelse 0 else 0;

    return .{
        try alloc.dupe(u8, sts.metadata.namespace orelse "default"),
        try alloc.dupe(u8, sts.metadata.name),
        try std.fmt.allocPrint(alloc, "{d}/{d}", .{ ready, desired }),
        try age_util.calculateAge(alloc, sts.metadata.creationTimestamp),
    };
}

pub const StatefulSetsView = ResourceView(klient.types.StatefulSet, klient.resources.StatefulSets, .{
    .name = "statefulsets",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "READY", .min_width = 7, .max_width = 12, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformStatefulSet);

// ============================================================================
// === DaemonSets ===
// ============================================================================
fn transformDaemonSet(ds: klient.types.DaemonSet, alloc: std.mem.Allocator) ![7][]const u8 {
    const desired = statusInt(ds.status, "desiredNumberScheduled");
    const current = statusInt(ds.status, "currentNumberScheduled");
    const ready = statusInt(ds.status, "numberReady");
    const up_to_date = statusInt(ds.status, "updatedNumberScheduled");

    return .{
        try alloc.dupe(u8, ds.metadata.namespace orelse "default"),
        try alloc.dupe(u8, ds.metadata.name),
        try intToStr(alloc, desired),
        try intToStr(alloc, current),
        try intToStr(alloc, ready),
        try intToStr(alloc, up_to_date),
        try age_util.calculateAge(alloc, ds.metadata.creationTimestamp),
    };
}

pub const DaemonSetsView = ResourceView(klient.types.DaemonSet, klient.resources.DaemonSets, .{
    .name = "daemonsets",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 24, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "DESIRED", .min_width = 7, .max_width = 8, .priority = P.HIGH },
        .{ .name = "CURRENT", .min_width = 7, .max_width = 8, .priority = P.HIGH },
        .{ .name = "READY", .min_width = 5, .max_width = 8, .priority = P.HIGH },
        .{ .name = "UP-TO-DATE", .min_width = 8, .max_width = 12, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformDaemonSet);

// ============================================================================
// === ReplicaSets ===
// ============================================================================
fn transformReplicaSet(rs: klient.types.ReplicaSet, alloc: std.mem.Allocator) ![6][]const u8 {
    const desired: i32 = if (rs.spec) |s| s.replicas orelse 0 else 0;
    const current = statusInt(rs.status, "replicas");
    const ready = statusInt(rs.status, "readyReplicas");

    return .{
        try alloc.dupe(u8, rs.metadata.namespace orelse "default"),
        try alloc.dupe(u8, rs.metadata.name),
        try intToStr(alloc, desired),
        try intToStr(alloc, current),
        try intToStr(alloc, ready),
        try age_util.calculateAge(alloc, rs.metadata.creationTimestamp),
    };
}

pub const ReplicaSetsView = ResourceView(klient.types.ReplicaSet, klient.resources.ReplicaSets, .{
    .name = "replicasets",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "DESIRED", .min_width = 7, .max_width = 8, .priority = P.HIGH },
        .{ .name = "CURRENT", .min_width = 7, .max_width = 8, .priority = P.HIGH },
        .{ .name = "READY", .min_width = 5, .max_width = 8, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformReplicaSet);

// ============================================================================
// === Jobs ===
// ============================================================================
fn transformJob(job: klient.types.Job, alloc: std.mem.Allocator) ![5][]const u8 {
    const succeeded = statusInt(job.status, "succeeded");
    const desired: i32 = if (job.spec) |s| s.completions orelse 1 else 1;
    const completions = try std.fmt.allocPrint(alloc, "{d}/{d}", .{ succeeded, desired });

    // Calculate duration from startTime/completionTime in status JSON
    const start_time_str = statusStr(job.status, "startTime");
    const completion_time_str = statusStr(job.status, "completionTime");

    const duration = blk: {
        const start_epoch = age_util.parseTimestampToEpoch(start_time_str) orelse
            break :blk try alloc.dupe(u8, "-");

        const end_epoch = if (age_util.parseTimestampToEpoch(completion_time_str)) |ce|
            ce
        else
            clock.timestamp();

        const diff = end_epoch - start_epoch;
        if (diff < 0) break :blk try alloc.dupe(u8, "0s");
        break :blk try age_util.formatDuration(alloc, @intCast(diff));
    };

    return .{
        try alloc.dupe(u8, job.metadata.namespace orelse "default"),
        try alloc.dupe(u8, job.metadata.name),
        completions,
        duration,
        try age_util.calculateAge(alloc, job.metadata.creationTimestamp),
    };
}

pub const JobsView = ResourceView(klient.types.Job, klient.resources.Jobs, .{
    .name = "jobs",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "COMPLETIONS", .min_width = 8, .max_width = 14, .priority = P.HIGH },
        .{ .name = "DURATION", .min_width = 8, .max_width = 12, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformJob);

// ============================================================================
// === CronJobs ===
// ============================================================================
fn transformCronJob(cj: klient.types.CronJob, alloc: std.mem.Allocator) ![6][]const u8 {
    const schedule = if (cj.spec) |s|
        if (s.schedule) |sched| try alloc.dupe(u8, sched) else try alloc.dupe(u8, "")
    else
        try alloc.dupe(u8, "");
    const suspended = if (cj.spec) |s| s.suspended orelse false else false;

    // Extract active from JSON Value (it's an array of references)
    const active: i32 = if (cj.status) |status_json| blk: {
        if (status_json == .object) {
            if (status_json.object.get("active")) |val| {
                if (val == .array) break :blk @intCast(val.array.items.len);
            }
        }
        break :blk 0;
    } else 0;

    // Calculate last schedule age from lastScheduleTime in status JSON
    const last_schedule_str = statusStr(cj.status, "lastScheduleTime");
    const last_schedule = if (last_schedule_str != null)
        try age_util.calculateAge(alloc, last_schedule_str)
    else
        try alloc.dupe(u8, "-");

    return .{
        try alloc.dupe(u8, cj.metadata.namespace orelse "default"),
        try alloc.dupe(u8, cj.metadata.name),
        schedule,
        if (suspended) try alloc.dupe(u8, "True") else try alloc.dupe(u8, "False"),
        try intToStr(alloc, active),
        last_schedule,
    };
}

pub const CronJobsView = ResourceView(klient.types.CronJob, klient.resources.CronJobs, .{
    .name = "cronjobs",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 25, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "SCHEDULE", .min_width = 10, .max_width = 16, .priority = P.HIGH },
        .{ .name = "SUSPEND", .min_width = 6, .max_width = 8, .priority = P.MEDIUM },
        .{ .name = "ACTIVE", .min_width = 6, .max_width = 8, .priority = P.HIGH },
        .{ .name = "LAST", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformCronJob);

// ============================================================================
// === Ingresses ===
// ============================================================================
fn transformIngress(ing: klient.types.Ingress, alloc: std.mem.Allocator) ![6][]const u8 {
    return .{
        try alloc.dupe(u8, ing.metadata.namespace orelse "default"),
        try alloc.dupe(u8, ing.metadata.name),
        try alloc.dupe(u8, "nginx"),
        try alloc.dupe(u8, "*"),
        try alloc.dupe(u8, "10.0.0.1"),
        try age_util.calculateAge(alloc, ing.metadata.creationTimestamp),
    };
}

pub const IngressesView = ResourceView(klient.types.Ingress, klient.resources.Ingresses, .{
    .name = "ingresses",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 22, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "CLASS", .min_width = 6, .max_width = 12, .priority = P.HIGH },
        .{ .name = "HOSTS", .min_width = 6, .max_width = 12, .priority = P.MEDIUM },
        .{ .name = "ADDRESS", .min_width = 8, .max_width = 16, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformIngress);

// ============================================================================
// === NetworkPolicies ===
// ============================================================================
fn transformNetworkPolicy(np: klient.types.NetworkPolicy, alloc: std.mem.Allocator) ![4][]const u8 {
    return .{
        try alloc.dupe(u8, np.metadata.namespace orelse "default"),
        try alloc.dupe(u8, np.metadata.name),
        try alloc.dupe(u8, "<all>"),
        try age_util.calculateAge(alloc, np.metadata.creationTimestamp),
    };
}

pub const NetworkPoliciesView = ResourceView(klient.types.NetworkPolicy, klient.resources.NetworkPolicies, .{
    .name = "networkpolicies",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "POD-SELECTOR", .min_width = 10, .max_width = 20, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformNetworkPolicy);

// ============================================================================
// === ServiceAccounts ===
// ============================================================================
fn transformServiceAccount(sa: klient.types.ServiceAccount, alloc: std.mem.Allocator) ![4][]const u8 {
    return .{
        try alloc.dupe(u8, sa.metadata.namespace orelse "default"),
        try alloc.dupe(u8, sa.metadata.name),
        try alloc.dupe(u8, "1"),
        try age_util.calculateAge(alloc, sa.metadata.creationTimestamp),
    };
}

pub const ServiceAccountsView = ResourceView(klient.types.ServiceAccount, klient.resources.ServiceAccounts, .{
    .name = "serviceaccounts",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "SECRETS", .min_width = 6, .max_width = 10, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformServiceAccount);

// ============================================================================
// === Roles ===
// ============================================================================
fn transformRole(role: klient.types.Role, alloc: std.mem.Allocator) ![3][]const u8 {
    return .{
        try alloc.dupe(u8, role.metadata.namespace orelse "default"),
        try alloc.dupe(u8, role.metadata.name),
        try age_util.calculateAge(alloc, role.metadata.creationTimestamp),
    };
}

pub const RolesView = ResourceView(klient.types.Role, klient.resources.Roles, .{
    .name = "roles",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformRole);

// ============================================================================
// === RoleBindings ===
// ============================================================================
fn transformRoleBinding(rb: klient.types.RoleBinding, alloc: std.mem.Allocator) ![4][]const u8 {
    return .{
        try alloc.dupe(u8, rb.metadata.namespace orelse "default"),
        try alloc.dupe(u8, rb.metadata.name),
        try alloc.dupe(u8, "role"),
        try age_util.calculateAge(alloc, rb.metadata.creationTimestamp),
    };
}

pub const RoleBindingsView = ResourceView(klient.types.RoleBinding, klient.resources.RoleBindings, .{
    .name = "rolebindings",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 22, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "ROLE", .min_width = 8, .max_width = 14, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformRoleBinding);

// ============================================================================
// === ClusterRoles ===
// ============================================================================
fn transformClusterRole(cr: klient.types.ClusterRole, alloc: std.mem.Allocator) ![2][]const u8 {
    return .{
        try alloc.dupe(u8, cr.metadata.name),
        try age_util.calculateAge(alloc, cr.metadata.creationTimestamp),
    };
}

pub const ClusterRolesView = ResourceView(klient.types.ClusterRole, klient.resources.ClusterRoles, .{
    .name = "clusterroles",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 16, .max_width = 42, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformClusterRole);

// ============================================================================
// === ClusterRoleBindings ===
// ============================================================================
fn transformClusterRoleBinding(crb: klient.types.ClusterRoleBinding, alloc: std.mem.Allocator) ![3][]const u8 {
    return .{
        try alloc.dupe(u8, crb.metadata.name),
        try alloc.dupe(u8, "role"),
        try age_util.calculateAge(alloc, crb.metadata.creationTimestamp),
    };
}

pub const ClusterRoleBindingsView = ResourceView(klient.types.ClusterRoleBinding, klient.resources.ClusterRoleBindings, .{
    .name = "clusterrolebindings",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 16, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "ROLE", .min_width = 10, .max_width = 22, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformClusterRoleBinding);

// ============================================================================
// === Events ===
// ============================================================================
fn transformEvent(ev: klient.types.Event, alloc: std.mem.Allocator) ![6][]const u8 {
    return .{
        try alloc.dupe(u8, ev.metadata.namespace orelse "default"),
        try alloc.dupe(u8, ev.metadata.name),
        try alloc.dupe(u8, "Normal"),
        try alloc.dupe(u8, "Created"),
        try alloc.dupe(u8, "Event message"),
        try age_util.calculateAge(alloc, ev.metadata.creationTimestamp),
    };
}

pub const EventsView = ResourceView(klient.types.Event, klient.resources.Events, .{
    .name = "events",
    .is_namespaced = true,
    .default_all_namespaces = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 18, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 10, .max_width = 18, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "TYPE", .min_width = 6, .max_width = 10, .priority = P.HIGH },
        .{ .name = "REASON", .min_width = 8, .max_width = 14, .priority = P.HIGH },
        .{ .name = "MESSAGE", .min_width = 10, .max_width = 18, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformEvent);

// ============================================================================
// === Nodes ===
// ============================================================================
fn transformNode(node: klient.types.Node, alloc: std.mem.Allocator) ![6][]const u8 {
    // Determine node status from conditions array
    const status = blk: {
        if (node.status) |status_json| {
            if (status_json == .object) {
                if (status_json.object.get("conditions")) |conditions| {
                    if (conditions == .array) {
                        for (conditions.array.items) |condition| {
                            if (condition == .object) {
                                const cond_type = if (condition.object.get("type")) |t|
                                    (if (t == .string) t.string else null)
                                else
                                    null;
                                if (cond_type) |ct| {
                                    if (std.mem.eql(u8, ct, "Ready")) {
                                        const cond_status = if (condition.object.get("status")) |s|
                                            (if (s == .string) s.string else null)
                                        else
                                            null;
                                        if (cond_status) |cs| {
                                            if (std.mem.eql(u8, cs, "True")) {
                                                break :blk try alloc.dupe(u8, "Ready");
                                            } else {
                                                break :blk try alloc.dupe(u8, "NotReady");
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        break :blk try alloc.dupe(u8, "Unknown");
    };

    // Get node roles from labels
    const roles = blk: {
        if (node.metadata.labels) |labels_json| {
            if (labels_json == .object) {
                const role_prefix = "node-role.kubernetes.io/";
                var roles_buf: [256]u8 = undefined;
                var roles_len: usize = 0;
                var it = labels_json.object.iterator();
                while (it.next()) |entry| {
                    const key_str = entry.key_ptr.*;
                    if (std.mem.startsWith(u8, key_str, role_prefix)) {
                        const role_name = key_str[role_prefix.len..];
                        if (role_name.len > 0) {
                            if (roles_len > 0) {
                                if (roles_len + 1 < roles_buf.len) {
                                    roles_buf[roles_len] = ',';
                                    roles_len += 1;
                                }
                            }
                            const copy_len = @min(role_name.len, roles_buf.len - roles_len);
                            @memcpy(roles_buf[roles_len..][0..copy_len], role_name[0..copy_len]);
                            roles_len += copy_len;
                        }
                    }
                }
                if (roles_len > 0) {
                    break :blk try alloc.dupe(u8, roles_buf[0..roles_len]);
                }
            }
        }
        break :blk try alloc.dupe(u8, "<none>");
    };

    // Extract internal IP from status.addresses array
    const internal_ip = blk: {
        if (node.status) |status_json| {
            if (status_json == .object) {
                if (status_json.object.get("addresses")) |addresses| {
                    if (addresses == .array) {
                        for (addresses.array.items) |addr| {
                            if (addr == .object) {
                                const addr_type = if (addr.object.get("type")) |t|
                                    (if (t == .string) t.string else null)
                                else
                                    null;
                                if (addr_type) |at| {
                                    if (std.mem.eql(u8, at, "InternalIP")) {
                                        if (addr.object.get("address")) |a| {
                                            if (a == .string) {
                                                break :blk try alloc.dupe(u8, a.string);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        break :blk try alloc.dupe(u8, "<unknown>");
    };

    // Extract version from status.nodeInfo.kubeletVersion
    const version = blk: {
        if (node.status) |status_json| {
            if (status_json == .object) {
                if (status_json.object.get("nodeInfo")) |node_info| {
                    if (node_info == .object) {
                        if (node_info.object.get("kubeletVersion")) |v| {
                            if (v == .string) {
                                break :blk try alloc.dupe(u8, v.string);
                            }
                        }
                    }
                }
            }
        }
        break :blk try alloc.dupe(u8, "unknown");
    };

    return .{
        try alloc.dupe(u8, node.metadata.name),
        status,
        roles,
        version,
        internal_ip,
        try age_util.calculateAge(alloc, node.metadata.creationTimestamp),
    };
}

pub const NodesView = ResourceView(klient.types.Node, klient.resources.Nodes, .{
    .name = "nodes",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 28, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = P.HIGH, .sort_key = 'S' },
        .{ .name = "ROLES", .min_width = 8, .max_width = 16, .priority = P.HIGH },
        .{ .name = "VERSION", .min_width = 8, .max_width = 16, .priority = P.MEDIUM },
        .{ .name = "INTERNAL-IP", .min_width = 10, .max_width = 20, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformNode);

// ============================================================================
// === ResourceQuotas ===
// ============================================================================
fn transformResourceQuota(rq: klient.types.ResourceQuota, alloc: std.mem.Allocator) ![3][]const u8 {
    return .{
        try alloc.dupe(u8, rq.metadata.namespace orelse "default"),
        try alloc.dupe(u8, rq.metadata.name),
        try age_util.calculateAge(alloc, rq.metadata.creationTimestamp),
    };
}

pub const ResourceQuotasView = ResourceView(klient.types.ResourceQuota, klient.resources.ResourceQuotas, .{
    .name = "resourcequotas",
    .is_namespaced = true,
    .default_all_namespaces = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformResourceQuota);

// ============================================================================
// === LimitRanges ===
// ============================================================================
fn transformLimitRange(lr: klient.types.LimitRange, alloc: std.mem.Allocator) ![3][]const u8 {
    return .{
        try alloc.dupe(u8, lr.metadata.namespace orelse "default"),
        try alloc.dupe(u8, lr.metadata.name),
        try age_util.calculateAge(alloc, lr.metadata.creationTimestamp),
    };
}

pub const LimitRangesView = ResourceView(klient.types.LimitRange, klient.resources.LimitRanges, .{
    .name = "limitranges",
    .is_namespaced = true,
    .default_all_namespaces = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformLimitRange);

// ============================================================================
// === PodDisruptionBudgets ===
// ============================================================================
fn transformPodDisruptionBudget(pdb: klient.types.PodDisruptionBudget, alloc: std.mem.Allocator) ![4][]const u8 {
    return .{
        try alloc.dupe(u8, pdb.metadata.namespace orelse "default"),
        try alloc.dupe(u8, pdb.metadata.name),
        try alloc.dupe(u8, "1"),
        try age_util.calculateAge(alloc, pdb.metadata.creationTimestamp),
    };
}

pub const PodDisruptionBudgetsView = ResourceView(klient.types.PodDisruptionBudget, klient.resources.PodDisruptionBudgets, .{
    .name = "poddisruptionbudgets",
    .is_namespaced = true,
    .default_all_namespaces = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 22, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "MIN-AVAILABLE", .min_width = 8, .max_width = 14, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformPodDisruptionBudget);

// ============================================================================
// === HPA (HorizontalPodAutoscalers) ===
// ============================================================================
fn transformHPA(hpa: klient.types.HorizontalPodAutoscaler, alloc: std.mem.Allocator) ![6][]const u8 {
    const current: i32 = blk: {
        if (hpa.status) |status_val| {
            if (status_val == .object) {
                const status_obj = status_val.object;
                if (status_obj.get("currentReplicas")) |val| {
                    if (val == .integer) {
                        break :blk @as(i32, @intCast(val.integer));
                    }
                }
            }
        }
        break :blk @as(i32, 0);
    };
    const min: i32 = if (hpa.spec) |spec| if (spec.minReplicas) |m| m else 1 else 1;
    const max: i32 = if (hpa.spec) |spec| spec.maxReplicas else 1;

    return .{
        try alloc.dupe(u8, hpa.metadata.namespace orelse "default"),
        try alloc.dupe(u8, hpa.metadata.name),
        try intToStr(alloc, min),
        try intToStr(alloc, max),
        try intToStr(alloc, current),
        try age_util.calculateAge(alloc, hpa.metadata.creationTimestamp),
    };
}

pub const HPAView = ResourceView(klient.types.HorizontalPodAutoscaler, klient.resources.HorizontalPodAutoscalers, .{
    .name = "hpa",
    .is_namespaced = true,
    .default_all_namespaces = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 28, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "MIN", .min_width = 4, .max_width = 6, .priority = P.HIGH },
        .{ .name = "MAX", .min_width = 4, .max_width = 6, .priority = P.HIGH },
        .{ .name = "CURRENT", .min_width = 6, .max_width = 8, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformHPA);

// ============================================================================
// === PersistentVolumes ===
// ============================================================================
fn transformPersistentVolume(pv: klient.types.PersistentVolume, alloc: std.mem.Allocator) ![6][]const u8 {
    return .{
        try alloc.dupe(u8, pv.metadata.name),
        try alloc.dupe(u8, "10Gi"),
        try alloc.dupe(u8, "RWO"),
        try alloc.dupe(u8, "Retain"),
        try alloc.dupe(u8, "Available"),
        try age_util.calculateAge(alloc, pv.metadata.creationTimestamp),
    };
}

pub const PersistentVolumesView = ResourceView(klient.types.PersistentVolume, klient.resources.PersistentVolumes, .{
    .name = "persistentvolumes",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "CAPACITY", .min_width = 8, .max_width = 12, .priority = P.HIGH },
        .{ .name = "ACCESS", .min_width = 6, .max_width = 10, .priority = P.MEDIUM },
        .{ .name = "RECLAIM", .min_width = 6, .max_width = 10, .priority = P.MEDIUM },
        .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = P.HIGH, .sort_key = 'S' },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformPersistentVolume);

// ============================================================================
// === PersistentVolumeClaims ===
// ============================================================================
fn transformPersistentVolumeClaim(pvc: klient.types.PersistentVolumeClaim, alloc: std.mem.Allocator) ![7][]const u8 {
    return .{
        try alloc.dupe(u8, pvc.metadata.namespace orelse "default"),
        try alloc.dupe(u8, pvc.metadata.name),
        try alloc.dupe(u8, "Bound"),
        try alloc.dupe(u8, "pv-001"),
        try alloc.dupe(u8, "10Gi"),
        try alloc.dupe(u8, "RWO"),
        try age_util.calculateAge(alloc, pvc.metadata.creationTimestamp),
    };
}

pub const PersistentVolumeClaimsView = ResourceView(klient.types.PersistentVolumeClaim, klient.resources.PersistentVolumeClaims, .{
    .name = "persistentvolumeclaims",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 22, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "STATUS", .min_width = 6, .max_width = 10, .priority = P.HIGH, .sort_key = 'S' },
        .{ .name = "VOLUME", .min_width = 6, .max_width = 10, .priority = P.MEDIUM },
        .{ .name = "CAPACITY", .min_width = 6, .max_width = 10, .priority = P.MEDIUM },
        .{ .name = "ACCESS", .min_width = 5, .max_width = 8, .priority = P.LOW },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformPersistentVolumeClaim);

// ============================================================================
// === Endpoints ===
// ============================================================================
fn transformEndpoints(ep: klient.types.Endpoints, alloc: std.mem.Allocator) ![4][]const u8 {
    const endpoints_str = if (ep.spec) |spec| blk: {
        if (spec.subsets) |subsets| {
            var buf: [32]u8 = undefined;
            const count_str = try std.fmt.bufPrint(&buf, "{d}", .{subsets.len});
            break :blk try alloc.dupe(u8, count_str);
        }
        break :blk try alloc.dupe(u8, "<none>");
    } else try alloc.dupe(u8, "<none>");

    return .{
        try alloc.dupe(u8, if (ep.metadata.namespace) |ns| ns else "default"),
        try alloc.dupe(u8, ep.metadata.name),
        endpoints_str,
        try age_util.calculateAge(alloc, ep.metadata.creationTimestamp),
    };
}

pub const EndpointsView = ResourceView(klient.types.Endpoints, klient.resources.EndpointsClient, .{
    .name = "endpoints",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 16, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "ENDPOINTS", .min_width = 8, .max_width = 20, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformEndpoints);

// ============================================================================
// === StorageClasses ===
// ============================================================================
fn transformStorageClass(sc: klient.types.StorageClass, alloc: std.mem.Allocator) ![6][]const u8 {
    return .{
        try alloc.dupe(u8, sc.metadata.name),
        try alloc.dupe(u8, sc.provisioner),
        try alloc.dupe(u8, sc.reclaimPolicy orelse "Delete"),
        try alloc.dupe(u8, sc.volumeBindingMode orelse "Immediate"),
        try alloc.dupe(u8, if (sc.allowVolumeExpansion orelse false) "true" else "false"),
        try age_util.calculateAge(alloc, sc.metadata.creationTimestamp),
    };
}

pub const StorageClassesView = ResourceView(klient.types.StorageClass, klient.resources.StorageClasses, .{
    .name = "storageclasses",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "PROVISIONER", .min_width = 12, .max_width = 30, .priority = P.HIGH },
        .{ .name = "RECLAIMPOLICY", .min_width = 8, .max_width = 14, .priority = P.MEDIUM },
        .{ .name = "BINDMODE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM },
        .{ .name = "EXPANSION", .min_width = 6, .max_width = 10, .priority = P.LOW },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformStorageClass);
