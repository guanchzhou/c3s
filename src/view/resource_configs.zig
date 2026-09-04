/// Resource Configs - Declarative definitions for Kubernetes resource views.
/// Each resource defines a transform function and a ResourceView instantiation.
/// Kubernetes 1.33–1.37 + Gateway API views are re-exported from modern_resources.zig.
const std = @import("std");
const klient = @import("klient");
const resource_view = @import("resource_view.zig");
const ResourceView = resource_view.ResourceView;
const ColumnDef = resource_view.ColumnDef;
const Config = resource_view.Config;
const age_util = @import("../viewmodel/age.zig");
const table_layout = @import("../ui/table_layout.zig");
const clock = @import("../core/clock.zig");
const NodeRecord = @import("../k8s/NodeRecord.zig");
const loadBalancerAddresses = @import("../k8s/LoadBalancerAddress.zig").format;

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

/// Read a string at obj[key] from a nested JSON object (e.g. capacity.storage).
fn jsonValStr(v: std.json.Value, key: []const u8) ?[]const u8 {
    if (v == .object) {
        if (v.object.get(key)) |inner| {
            if (inner == .string) return inner.string;
        }
    }
    return null;
}

/// Stringify a scalar JSON value (int or string) into `alloc`, or null.
fn jsonScalarToStr(alloc: std.mem.Allocator, v: std.json.Value) !?[]const u8 {
    return switch (v) {
        .integer => |i| try std.fmt.allocPrint(alloc, "{d}", .{i}),
        .string => |s| try alloc.dupe(u8, s),
        else => null,
    };
}

/// k9s-style access-mode abbreviations.
fn abbrevAccessMode(mode: []const u8) []const u8 {
    if (std.mem.eql(u8, mode, "ReadWriteOnce")) return "RWO";
    if (std.mem.eql(u8, mode, "ReadOnlyMany")) return "ROX";
    if (std.mem.eql(u8, mode, "ReadWriteMany")) return "RWX";
    if (std.mem.eql(u8, mode, "ReadWriteOncePod")) return "RWOP";
    return mode;
}

/// Join `[]const []const u8` with `,` into `alloc`; abbreviate each via `xform`.
fn joinStrings(
    alloc: std.mem.Allocator,
    items: []const []const u8,
    comptime xform: fn ([]const u8) []const u8,
) ![]const u8 {
    if (items.len == 0) return alloc.dupe(u8, "<none>");
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(alloc);
    for (items, 0..) |it, i| {
        if (i > 0) try buf.append(alloc, ',');
        try buf.appendSlice(alloc, xform(it));
    }
    return buf.toOwnedSlice(alloc);
}

fn identity(s: []const u8) []const u8 {
    return s;
}

/// Format `spec.podSelector.matchLabels` as `k=v,k=v`, or `<none>` when empty
/// (matchExpressions-only selectors also render `<none>`, matching k9s which
/// only surfaces matchLabels in the POD-SELECTOR column).
fn formatMatchLabels(alloc: std.mem.Allocator, selector: ?std.json.Value) ![]const u8 {
    const sel = selector orelse return alloc.dupe(u8, "<none>");
    if (sel != .object) return alloc.dupe(u8, "<none>");
    const ml = sel.object.get("matchLabels") orelse return alloc.dupe(u8, "<none>");
    if (ml != .object or ml.object.count() == 0) return alloc.dupe(u8, "<none>");

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(alloc);
    var it = ml.object.iterator();
    var first = true;
    while (it.next()) |entry| {
        if (!first) try buf.append(alloc, ',');
        first = false;
        try buf.appendSlice(alloc, entry.key_ptr.*);
        try buf.append(alloc, '=');
        if (entry.value_ptr.* == .string) {
            try buf.appendSlice(alloc, entry.value_ptr.*.string);
        }
    }
    return buf.toOwnedSlice(alloc);
}

// ============================================================================
// === Pods ===
// ============================================================================
fn transformPod(pod: klient.types.Pod, alloc: std.mem.Allocator) ![12][]const u8 {
    // klient 0.4.0 types PodStatus, so these are plain field reads.
    const phase = if (pod.status) |status| status.phase orelse "Unknown" else "Unknown";
    const pod_ip = if (pod.status) |status| status.podIP orelse "-" else "-";

    // ready/total + restart total from status.containerStatuses.
    var ready_count: u32 = 0;
    var total_count: u32 = 0;
    var restarts: i64 = 0;
    if (pod.status) |status| {
        if (status.containerStatuses) |container_statuses| {
            total_count = @intCast(container_statuses.len);
            for (container_statuses) |container_status| {
                if (container_status.ready) ready_count += 1;
                restarts += container_status.restartCount;
            }
        }
    }

    // Sum container resource requests so the metrics hook can compute %CPU/R and
    // %MEM/R. Stored as raw millicores / bytes integers; the hook rewrites these
    // two cells to "<pct>" or "n/a" before they are ever displayed.
    var req_cpu_milli: u64 = 0;
    var req_mem_bytes: u64 = 0;
    if (pod.spec) |spec| {
        if (spec.containers) |containers| {
            for (containers) |container| {
                const reqs = (container.resources orelse continue).requests orelse continue;
                if (reqs != .object) continue;
                if (reqs.object.get("cpu")) |c| {
                    if (c == .string) {
                        if (klient.MetricsClient.parseCpuMillicores(c.string)) |mc| req_cpu_milli += mc;
                    }
                }
                if (reqs.object.get("memory")) |m| {
                    if (m == .string) {
                        if (klient.MetricsClient.parseMemoryBytes(m.string)) |b| req_mem_bytes += b;
                    }
                }
            }
        }
    }

    const node = if (pod.spec) |spec| spec.nodeName orelse "-" else "-";

    return .{
        try alloc.dupe(u8, pod.metadata.namespace orelse "default"),
        try alloc.dupe(u8, pod.metadata.name),
        try std.fmt.allocPrint(alloc, "{d}/{d}", .{ ready_count, total_count }),
        try alloc.dupe(u8, phase),
        try std.fmt.allocPrint(alloc, "{d}", .{restarts}),
        try alloc.dupe(u8, "-"), // CPU placeholder; filled by metrics_columns hook
        try alloc.dupe(u8, "-"), // MEM placeholder; filled by metrics_columns hook
        try std.fmt.allocPrint(alloc, "{d}", .{req_cpu_milli}), // %CPU/R request; hook converts
        try std.fmt.allocPrint(alloc, "{d}", .{req_mem_bytes}), // %MEM/R request; hook converts
        try alloc.dupe(u8, pod_ip),
        try alloc.dupe(u8, node),
        try age_util.calculateAge(alloc, pod.metadata.creationTimestamp),
    };
}

pub const PodsView = ResourceView(klient.types.Pod, klient.resources.Pods, .{
    .name = "pods",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .metrics_columns = .{ .cpu = 5, .mem = 6, .cpu_pct = 7, .mem_pct = 8 },
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 24, .priority = P.MEDIUM, .sort_key = 'P', .searchable = true },
        .{ .name = "NAME", .min_width = 15, .max_width = null, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "READY", .min_width = 6, .max_width = 8, .priority = P.HIGH, .sort_key = 'R' },
        .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = P.HIGH, .sort_key = 'S' },
        .{ .name = "RESTARTS", .min_width = 8, .max_width = 10, .priority = P.LOW, .sort_key = 'T' },
        .{ .name = "CPU", .min_width = 6, .max_width = 10, .priority = P.VERY_LOW, .sort_key = 'C' },
        .{ .name = "MEM", .min_width = 6, .max_width = 10, .priority = P.VERY_LOW, .sort_key = 'M' },
        .{ .name = "%CPU/R", .min_width = 7, .max_width = 9, .priority = P.VERY_LOW },
        .{ .name = "%MEM/R", .min_width = 7, .max_width = 9, .priority = P.VERY_LOW },
        .{ .name = "IP", .min_width = 10, .max_width = null, .priority = P.LOW, .sort_key = 'I' },
        .{ .name = "NODE", .min_width = 10, .max_width = null, .priority = P.LOW, .sort_key = 'O' },
        .{ .name = "AGE", .min_width = 5, .max_width = 8, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformPod);

// ============================================================================
// === Deployments ===
// ============================================================================
fn transformDeployment(dep: klient.types.Deployment, alloc: std.mem.Allocator) ![6][]const u8 {
    const ready_replicas = statusInt(dep.status, "readyReplicas");
    const updated_replicas = statusInt(dep.status, "updatedReplicas");
    const available_replicas = statusInt(dep.status, "availableReplicas");
    const replicas: i32 = if (dep.spec) |s| s.replicas orelse 0 else 0;

    return .{
        try alloc.dupe(u8, if (dep.metadata.namespace) |ns| ns else "default"),
        try alloc.dupe(u8, dep.metadata.name),
        try std.fmt.allocPrint(alloc, "{d}/{d}", .{ ready_replicas, replicas }),
        try intToStr(alloc, updated_replicas),
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
        .{ .name = "NAMESPACE", .min_width = 12, .max_width = 24, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 16, .max_width = 40, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "READY", .min_width = 7, .max_width = 12, .priority = P.HIGH },
        .{ .name = "UP-TO-DATE", .min_width = 10, .max_width = 12, .priority = P.HIGH },
        .{ .name = "AVAILABLE", .min_width = 9, .max_width = 12, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformDeployment);

// ============================================================================
// === Services ===
// ============================================================================
fn transformService(svc: klient.types.Service, alloc: std.mem.Allocator) ![7][]const u8 {
    // PORTS: comma-joined "port/proto" for every spec.ports entry (k9s).
    const ports_str = if (svc.spec) |spec| blk: {
        if (spec.ports) |ports| {
            if (ports.len > 0) {
                var buf = std.ArrayListUnmanaged(u8).empty;
                defer buf.deinit(alloc);
                for (ports, 0..) |p, i| {
                    if (i > 0) try buf.append(alloc, ',');
                    const port_num: i64 = if (p.port) |pv|
                        (if (pv == .integer) @intCast(pv.integer) else 0)
                    else
                        0;
                    var pbuf: [64]u8 = undefined;
                    const seg = try std.fmt.bufPrint(&pbuf, "{d}/{s}", .{ port_num, p.protocol orelse "TCP" });
                    try buf.appendSlice(alloc, seg);
                }
                break :blk try buf.toOwnedSlice(alloc);
            }
        }
        break :blk try alloc.dupe(u8, "<none>");
    } else try alloc.dupe(u8, "<none>");

    const svc_type: []const u8 = if (svc.spec) |spec| spec.type orelse "ClusterIP" else "ClusterIP";

    // EXTERNAL-IP: LoadBalancer ingress addrs, else spec.externalIPs, else <none>.
    const external_ip = blk: {
        if (std.mem.eql(u8, svc_type, "LoadBalancer")) {
            if (try loadBalancerAddresses(alloc, svc.status)) |addr| break :blk addr;
            break :blk try alloc.dupe(u8, "<pending>");
        }
        if (svc.spec) |spec| {
            if (spec.externalIPs) |ips| {
                if (ips.len > 0) break :blk try joinStrings(alloc, ips, identity);
            }
        }
        break :blk try alloc.dupe(u8, "<none>");
    };

    return .{
        try alloc.dupe(u8, if (svc.metadata.namespace) |ns| ns else "default"),
        try alloc.dupe(u8, svc.metadata.name),
        try alloc.dupe(u8, svc_type),
        if (svc.spec) |spec|
            try alloc.dupe(u8, spec.clusterIP orelse "<none>")
        else
            try alloc.dupe(u8, "<none>"),
        external_ip,
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
        .{ .name = "TYPE", .min_width = 8, .max_width = 14, .priority = P.HIGH, .sort_key = 'T' },
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
    const keys: usize = if (cm.data) |data_json|
        (if (data_json == .object) data_json.object.count() else 0)
    else
        0;
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
        .{ .name = "DATA", .min_width = 5, .max_width = 8, .priority = P.HIGH },
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
        .{ .name = "DATA", .min_width = 5, .max_width = 8, .priority = P.MEDIUM },
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
    .default_all_namespaces = true,
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
        .{ .name = "COMPLETIONS", .min_width = 8, .max_width = 14, .priority = P.HIGH, .sort_key = 'C' },
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
    const should_suspend = if (cj.spec) |s| s.@"suspend" orelse false else false;

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
        if (should_suspend) try alloc.dupe(u8, "True") else try alloc.dupe(u8, "False"),
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
fn transformIngress(ing: klient.types.Ingress, alloc: std.mem.Allocator) ![7][]const u8 {
    const class: []const u8 = if (ing.spec) |spec| spec.ingressClassName orelse "<none>" else "<none>";

    // HOSTS: comma-joined spec.rules[].host, or "*" when none specify a host.
    const hosts = blk: {
        if (ing.spec) |spec| {
            if (spec.rules) |rules| {
                var buf = std.ArrayListUnmanaged(u8).empty;
                defer buf.deinit(alloc);
                var wrote = false;
                for (rules) |rule| {
                    const h = jsonValStr(rule, "host") orelse continue;
                    if (wrote) try buf.append(alloc, ',');
                    try buf.appendSlice(alloc, h);
                    wrote = true;
                }
                if (wrote) break :blk try buf.toOwnedSlice(alloc);
            }
        }
        break :blk try alloc.dupe(u8, "*");
    };

    const address = (try loadBalancerAddresses(alloc, ing.status)) orelse try alloc.dupe(u8, "");

    // PORTS: 80, plus 443 when spec.tls is present (k9s).
    const has_tls = if (ing.spec) |spec| (spec.tls != null and spec.tls.?.len > 0) else false;
    const ports = if (has_tls) try alloc.dupe(u8, "80, 443") else try alloc.dupe(u8, "80");

    return .{
        try alloc.dupe(u8, ing.metadata.namespace orelse "default"),
        try alloc.dupe(u8, ing.metadata.name),
        try alloc.dupe(u8, class),
        hosts,
        address,
        ports,
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
        .{ .name = "HOSTS", .min_width = 8, .max_width = 30, .priority = P.MEDIUM },
        .{ .name = "ADDRESS", .min_width = 8, .max_width = 30, .priority = P.MEDIUM },
        .{ .name = "PORTS", .min_width = 5, .max_width = 10, .priority = P.LOW },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformIngress);

// ============================================================================
// === NetworkPolicies ===
// ============================================================================
fn transformNetworkPolicy(np: klient.types.NetworkPolicy, alloc: std.mem.Allocator) ![4][]const u8 {
    const selector = if (np.spec) |spec| spec.podSelector else null;
    return .{
        try alloc.dupe(u8, np.metadata.namespace orelse "default"),
        try alloc.dupe(u8, np.metadata.name),
        try formatMatchLabels(alloc, selector),
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
    const secret_count: usize = if (sa.secrets) |s| s.len else 0;
    return .{
        try alloc.dupe(u8, sa.metadata.namespace orelse "default"),
        try alloc.dupe(u8, sa.metadata.name),
        try std.fmt.allocPrint(alloc, "{d}", .{secret_count}),
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
        try std.fmt.allocPrint(alloc, "{s}/{s}", .{ rb.roleRef.kind, rb.roleRef.name }),
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
        try std.fmt.allocPrint(alloc, "{s}/{s}", .{ crb.roleRef.kind, crb.roleRef.name }),
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
fn transformEvent(ev: klient.types.Event, alloc: std.mem.Allocator) ![7][]const u8 {
    // LAST-SEEN: age of lastTimestamp, falling back to eventTime, then creation.
    const last_seen_ts = ev.lastTimestamp orelse ev.eventTime orelse ev.metadata.creationTimestamp;

    // OBJECT: "<kind>/<name>" from involvedObject (k9s).
    const object = blk: {
        if (ev.involvedObject) |io| {
            const kind = io.kind orelse "";
            const name = io.name orelse "";
            if (kind.len > 0 and name.len > 0)
                break :blk try std.fmt.allocPrint(alloc, "{s}/{s}", .{ kind, name });
            if (name.len > 0) break :blk try alloc.dupe(u8, name);
        }
        break :blk try alloc.dupe(u8, "");
    };

    return .{
        try alloc.dupe(u8, ev.metadata.namespace orelse "default"),
        try age_util.calculateAge(alloc, last_seen_ts),
        try alloc.dupe(u8, ev.type orelse "-"),
        try alloc.dupe(u8, ev.reason orelse "-"),
        object,
        try std.fmt.allocPrint(alloc, "{d}", .{ev.count orelse 0}),
        try alloc.dupe(u8, ev.message orelse ""),
    };
}

pub const EventsView = ResourceView(klient.types.Event, klient.resources.Events, .{
    .name = "events",
    .is_namespaced = true,
    .default_all_namespaces = true,
    .name_column = 4,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 18, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "LAST-SEEN", .min_width = 8, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
        .{ .name = "TYPE", .min_width = 6, .max_width = 10, .priority = P.HIGH, .sort_key = 'T' },
        .{ .name = "REASON", .min_width = 8, .max_width = 18, .priority = P.HIGH, .sort_key = 'R' },
        .{ .name = "OBJECT", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "COUNT", .min_width = 5, .max_width = 7, .priority = P.LOW },
        .{ .name = "MESSAGE", .min_width = 16, .max_width = null, .priority = P.MEDIUM, .searchable = true },
    },
}, transformEvent);

// ============================================================================
// === Nodes ===
// ============================================================================
fn transformNode(node: klient.types.Node, alloc: std.mem.Allocator) ![6][]const u8 {
    var record = try NodeRecord.fromNode(alloc, node);
    defer record.deinit(alloc);
    return record.columns(alloc);
}

pub const NodesView = ResourceView(klient.types.Node, klient.resources.Nodes, .{
    .name = "nodes",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 28, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "STATUS", .min_width = 8, .max_width = 28, .priority = P.HIGH, .sort_key = 'S' },
        .{ .name = "ROLES", .min_width = 8, .max_width = 16, .priority = P.HIGH, .sort_key = 'R' },
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
fn transformPodDisruptionBudget(pdb: klient.types.PodDisruptionBudget, alloc: std.mem.Allocator) ![6][]const u8 {
    // minAvailable / maxUnavailable are IntOrString (int or "%") — render either,
    // "-" when absent.
    const min_available = blk: {
        if (pdb.spec) |spec| {
            if (spec.minAvailable) |v| {
                if (try jsonScalarToStr(alloc, v)) |s| break :blk s;
            }
        }
        break :blk try alloc.dupe(u8, "-");
    };
    const max_unavailable = blk: {
        if (pdb.spec) |spec| {
            if (spec.maxUnavailable) |v| {
                if (try jsonScalarToStr(alloc, v)) |s| break :blk s;
            }
        }
        break :blk try alloc.dupe(u8, "-");
    };
    const allowed = intToStr(alloc, statusInt(pdb.status, "disruptionsAllowed"));

    return .{
        try alloc.dupe(u8, pdb.metadata.namespace orelse "default"),
        try alloc.dupe(u8, pdb.metadata.name),
        min_available,
        max_unavailable,
        try allowed,
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
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "MIN-AVAILABLE", .min_width = 8, .max_width = 14, .priority = P.HIGH },
        .{ .name = "MAX-UNAVAILABLE", .min_width = 8, .max_width = 16, .priority = P.HIGH },
        .{ .name = "ALLOWED-DISRUPTIONS", .min_width = 10, .max_width = 20, .priority = P.MEDIUM },
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
        .{ .name = "MINPODS", .min_width = 6, .max_width = 9, .priority = P.HIGH },
        .{ .name = "MAXPODS", .min_width = 6, .max_width = 9, .priority = P.HIGH },
        .{ .name = "REPLICAS", .min_width = 7, .max_width = 10, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformHPA);

// ============================================================================
// === PersistentVolumes ===
// ============================================================================
fn transformPersistentVolume(pv: klient.types.PersistentVolume, alloc: std.mem.Allocator) ![8][]const u8 {
    const capacity = blk: {
        if (pv.spec) |spec| {
            if (spec.capacity) |cap| {
                if (jsonValStr(cap, "storage")) |s| break :blk try alloc.dupe(u8, s);
            }
        }
        break :blk try alloc.dupe(u8, "<unknown>");
    };

    const access = blk: {
        if (pv.spec) |spec| {
            if (spec.accessModes) |modes| break :blk try joinStrings(alloc, modes, abbrevAccessMode);
        }
        break :blk try alloc.dupe(u8, "<none>");
    };

    const reclaim: []const u8 = if (pv.spec) |spec| spec.persistentVolumeReclaimPolicy orelse "<none>" else "<none>";
    const status = statusStr(pv.status, "phase") orelse "<unknown>";

    const claim = blk: {
        if (pv.spec) |spec| {
            if (spec.claimRef) |ref| {
                if (ref.name) |name| {
                    if (ref.namespace) |ns|
                        break :blk try std.fmt.allocPrint(alloc, "{s}/{s}", .{ ns, name });
                    break :blk try alloc.dupe(u8, name);
                }
            }
        }
        break :blk try alloc.dupe(u8, "<none>");
    };

    const storageclass: []const u8 = if (pv.spec) |spec| spec.storageClassName orelse "<none>" else "<none>";

    return .{
        try alloc.dupe(u8, pv.metadata.name),
        capacity,
        access,
        try alloc.dupe(u8, reclaim),
        try alloc.dupe(u8, status),
        claim,
        try alloc.dupe(u8, storageclass),
        try age_util.calculateAge(alloc, pv.metadata.creationTimestamp),
    };
}

pub const PersistentVolumesView = ResourceView(klient.types.PersistentVolume, klient.resources.PersistentVolumes, .{
    .name = "persistentvolumes",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "CAPACITY", .min_width = 8, .max_width = 12, .priority = P.HIGH },
        .{ .name = "ACCESS", .min_width = 6, .max_width = 12, .priority = P.MEDIUM },
        .{ .name = "RECLAIM", .min_width = 7, .max_width = 10, .priority = P.MEDIUM },
        .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = P.HIGH, .sort_key = 'S' },
        .{ .name = "CLAIM", .min_width = 10, .max_width = 36, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "STORAGECLASS", .min_width = 10, .max_width = 20, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformPersistentVolume);

// ============================================================================
// === PersistentVolumeClaims ===
// ============================================================================
fn transformPersistentVolumeClaim(pvc: klient.types.PersistentVolumeClaim, alloc: std.mem.Allocator) ![8][]const u8 {
    const status = statusStr(pvc.status, "phase") orelse "<unknown>";
    const volume: []const u8 = if (pvc.spec) |spec| spec.volumeName orelse "" else "";

    // CAPACITY comes from status.capacity.storage (the bound size), per k9s.
    const capacity = blk: {
        if (pvc.status) |st| {
            if (st == .object) {
                if (st.object.get("capacity")) |cap| {
                    if (jsonValStr(cap, "storage")) |s| break :blk try alloc.dupe(u8, s);
                }
            }
        }
        break :blk try alloc.dupe(u8, "<none>");
    };

    const access = blk: {
        if (pvc.spec) |spec| {
            if (spec.accessModes) |modes| break :blk try joinStrings(alloc, modes, abbrevAccessMode);
        }
        break :blk try alloc.dupe(u8, "<none>");
    };

    const storageclass: []const u8 = if (pvc.spec) |spec| spec.storageClassName orelse "<none>" else "<none>";

    return .{
        try alloc.dupe(u8, pvc.metadata.namespace orelse "default"),
        try alloc.dupe(u8, pvc.metadata.name),
        try alloc.dupe(u8, status),
        try alloc.dupe(u8, volume),
        capacity,
        access,
        try alloc.dupe(u8, storageclass),
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
        .{ .name = "NAME", .min_width = 12, .max_width = 30, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "STATUS", .min_width = 6, .max_width = 10, .priority = P.HIGH, .sort_key = 'S' },
        .{ .name = "VOLUME", .min_width = 10, .max_width = 40, .priority = P.MEDIUM },
        .{ .name = "CAPACITY", .min_width = 8, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'C' },
        .{ .name = "ACCESS", .min_width = 6, .max_width = 12, .priority = P.LOW },
        .{ .name = "STORAGECLASS", .min_width = 10, .max_width = 20, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformPersistentVolumeClaim);

// ============================================================================
// === Endpoints ===
// ============================================================================
fn transformEndpoints(ep: klient.types.Endpoints, alloc: std.mem.Allocator) ![4][]const u8 {
    // Endpoints has no `spec` — `subsets` is top-level. Reading it through the old
    // `ep.spec` always yielded null, so this column showed <none> for every row.
    const endpoints_str = if (ep.subsets) |subsets|
        try std.fmt.allocPrint(alloc, "{d}", .{subsets.len})
    else
        try alloc.dupe(u8, "<none>");

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

// Kubernetes 1.33–1.37 + Gateway API views live in modern_resources.zig so this
// file stays the original 28. Re-exported here so App/index keep a single import.
const modern = @import("modern_resources.zig");
pub const GatewayClassesView = modern.GatewayClassesView;
pub const GatewaysView = modern.GatewaysView;
pub const HTTPRoutesView = modern.HTTPRoutesView;
pub const GRPCRoutesView = modern.GRPCRoutesView;
pub const ReferenceGrantsView = modern.ReferenceGrantsView;
pub const TCPRoutesView = modern.TCPRoutesView;
pub const TLSRoutesView = modern.TLSRoutesView;
pub const UDPRoutesView = modern.UDPRoutesView;
pub const BackendTLSPoliciesView = modern.BackendTLSPoliciesView;
pub const ListenerSetsView = modern.ListenerSetsView;
pub const EndpointSlicesView = modern.EndpointSlicesView;
pub const IngressClassesView = modern.IngressClassesView;
pub const IPAddressesView = modern.IPAddressesView;
pub const ServiceCIDRsView = modern.ServiceCIDRsView;
pub const VolumeAttributesClassesView = modern.VolumeAttributesClassesView;
pub const CSIDriversView = modern.CSIDriversView;
pub const ValidatingAdmissionPoliciesView = modern.ValidatingAdmissionPoliciesView;
pub const ValidatingAdmissionPolicyBindingsView = modern.ValidatingAdmissionPolicyBindingsView;
pub const MutatingAdmissionPoliciesView = modern.MutatingAdmissionPoliciesView;
pub const MutatingAdmissionPolicyBindingsView = modern.MutatingAdmissionPolicyBindingsView;
pub const ValidatingWebhookConfigurationsView = modern.ValidatingWebhookConfigurationsView;
pub const MutatingWebhookConfigurationsView = modern.MutatingWebhookConfigurationsView;

test "pod data-plane onShow requests one subscription" {
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const previous_source = resource_view.active_pod_source;
    defer resource_view.active_pod_source = previous_source;
    resource_view.active_pod_source = .data_plane;

    var service: K8sService = undefined;
    var theme: Theme = undefined;
    var pods = try PodsView.init(std.testing.allocator, &theme, &service);
    defer pods.deinit();
    const view = pods.createView();

    view.onShow();
    try std.testing.expectEqual(.start, pods.takePodSubscriptionRequest());
    pods.markPodSubscriptionStarted();
    view.onShow();
    try std.testing.expectEqual(.none, pods.takePodSubscriptionRequest());
    try pods.refresh();
    try std.testing.expectEqual(.restart, pods.takePodSubscriptionRequest());
}

test "legacy pod rollback source remains selectable" {
    const previous_source = resource_view.active_pod_source;
    defer resource_view.active_pod_source = previous_source;
    resource_view.active_pod_source = .legacy_list;
    try std.testing.expectEqual(resource_view.PodSource.legacy_list, resource_view.active_pod_source);
}

test "nodes projection preserves scheduling actions and UID selection" {
    const keys = @import("../k8s/ResourceKey.zig");
    const NodeProjection = @import("../k8s/ResourceProjection.zig").ResourceProjection(NodeRecord);
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const ProjectionFns = struct {
        fn match(record: *const NodeRecord, filter: []const u8) bool {
            return filter.len == 0 or std.mem.indexOf(u8, record.key.name, filter) != null;
        }
        fn sort(record: *const NodeRecord, column: u8) []const u8 {
            return if (column == 1) record.status else record.key.name;
        }
        fn enabled() bool {
            return true;
        }
        fn columns(
            _: *NodeProjection,
            record: *const NodeRecord,
            allocator: std.mem.Allocator,
        ) ![6][]const u8 {
            return record.columns(allocator);
        }
    };
    const allocator = std.testing.allocator;
    var view_failing = std.testing.FailingAllocator.init(allocator, .{});
    var projection = NodeProjection.init(allocator, .{
        .matchFn = ProjectionFns.match,
        .sortKeyFn = ProjectionFns.sort,
    });
    defer projection.deinit();
    var service: K8sService = undefined;
    var theme: Theme = undefined;
    var nodes = try NodesView.init(view_failing.allocator(), &theme, &service);
    defer nodes.deinit();
    nodes.bindProjection(NodesView.ProjectionAdapter.init(
        NodeRecord,
        &projection,
        ProjectionFns.enabled,
        ProjectionFns.columns,
    ));

    const changes = try allocator.alloc(keys.TypedChange(NodeRecord), 2);
    changes[0] = .{ .initial_upsert = .{
        .key = try (keys.ObjectKey{ .uid = "node-uid", .namespace = "", .name = "worker" }).clone(allocator),
        .status = try allocator.dupe(u8, "Ready,SchedulingDisabled"),
        .roles = try allocator.dupe(u8, "worker"),
        .version = try allocator.dupe(u8, "v1.31.0"),
        .internal_ip = try allocator.dupe(u8, "10.0.0.1"),
    } };
    changes[1] = .{ .initial_upsert = .{
        .key = try (keys.ObjectKey{ .uid = "broken-uid", .namespace = "", .name = "broken" }).clone(allocator),
        .status = try allocator.dupe(u8, "NotReady"),
        .roles = try allocator.dupe(u8, "worker"),
        .version = try allocator.dupe(u8, "v1.31.0"),
        .internal_ip = try allocator.dupe(u8, "10.0.0.2"),
    } };
    var batch = keys.TypedBatch(NodeRecord){
        .generation = 1,
        .subscription_id = 2,
        .revision = 1,
        .changes = changes,
        .sync = .list_started,
        .owned_bytes = 1,
    };
    defer batch.deinit(allocator);
    var plan = try NodeProjection.handler().preflight(@ptrCast(&projection), &batch, allocator);
    NodeProjection.handler().commit(@ptrCast(&projection), &batch, &plan);
    plan.deinit(allocator);
    try nodes.syncProjection();
    try std.testing.expectEqual(@as(usize, 2), nodes.table.items.items.len);
    view_failing.fail_index = view_failing.alloc_index + 2;
    try std.testing.expectError(error.OutOfMemory, nodes.applyFilter("work"));
    try std.testing.expectEqual(@as(usize, 2), nodes.table.items.items.len);
    try std.testing.expectEqual(@as(usize, 2), projection.visibleCount());
    try std.testing.expectEqualStrings("", nodes.table.filter_text);
    view_failing.fail_index = std.math.maxInt(usize);
    nodes.table.selected_row = 1;
    try nodes.syncProjection();
    try std.testing.expectEqual(
        @import("../viewmodel/view.zig").View.KeyResult.request_uncordon,
        try NodesView.handleKey(&nodes, .{ .char = 'u' }),
    );
    try std.testing.expect(projection.selectUid("node-uid"));

    const update = try allocator.alloc(keys.TypedChange(NodeRecord), 1);
    update[0] = .{ .watch_upsert = .{
        .key = try (keys.ObjectKey{ .uid = "node-uid", .namespace = "", .name = "worker" }).clone(allocator),
        .status = try allocator.dupe(u8, "Ready"),
        .roles = try allocator.dupe(u8, "worker"),
        .version = try allocator.dupe(u8, "v1.31.1"),
        .internal_ip = try allocator.dupe(u8, "10.0.0.1"),
    } };
    var update_batch = keys.TypedBatch(NodeRecord){
        .generation = 1,
        .subscription_id = 2,
        .revision = 2,
        .changes = update,
        .sync = null,
        .owned_bytes = 1,
    };
    defer update_batch.deinit(allocator);
    var update_plan = try NodeProjection.handler().preflight(
        @ptrCast(&projection),
        &update_batch,
        allocator,
    );
    NodeProjection.handler().commit(@ptrCast(&projection), &update_batch, &update_plan);
    update_plan.deinit(allocator);
    try nodes.syncProjection();
    try std.testing.expectEqualStrings("node-uid", projection.selectedUid().?);
    try std.testing.expectEqual(
        @import("../viewmodel/view.zig").View.KeyResult.request_cordon,
        try NodesView.handleKey(&nodes, .{ .char = 'u' }),
    );
    _ = try NodesView.handleKey(&nodes, .ctrl_z);
    try std.testing.expectEqual(@as(usize, 1), nodes.table.filtered_indices.items.len);
    try std.testing.expectEqualStrings(
        "broken",
        nodes.table.getSelectedItem().?.columns[0],
    );
    _ = try NodesView.handleKey(&nodes, .{ .char = 'N' });
    try std.testing.expectEqual(@as(usize, 1), nodes.table.filtered_indices.items.len);
}

test "node rollback gate retains legacy refresh path" {
    const previous = resource_view.active_node_source;
    defer resource_view.active_node_source = previous;
    const previous_hook = resource_view.legacy_loader_test_hook;
    defer resource_view.legacy_loader_test_hook = previous_hook;
    const Probe = struct {
        var calls: usize = 0;
        fn load(resource: []const u8) void {
            if (std.mem.eql(u8, resource, "nodes")) calls += 1;
        }
    };
    Probe.calls = 0;
    resource_view.active_node_source = .legacy_list;
    resource_view.legacy_loader_test_hook = Probe.load;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    var nodes = try NodesView.init(std.testing.allocator, &theme, &service);
    defer nodes.deinit();
    try nodes.refresh();
    try std.testing.expectEqual(@as(usize, 1), Probe.calls);
    try std.testing.expectEqual(.none, nodes.takeSubscriptionRequest());
}

test "services family rollback gate executes retained legacy loader seam" {
    const previous = resource_view.active_services_source;
    defer resource_view.active_services_source = previous;
    const previous_hook = resource_view.legacy_loader_test_hook;
    defer resource_view.legacy_loader_test_hook = previous_hook;
    const Probe = struct {
        var calls: usize = 0;
        fn load(resource: []const u8) void {
            if (std.mem.eql(u8, resource, "services") or
                std.mem.eql(u8, resource, "endpoints") or
                std.mem.eql(u8, resource, "endpointslices"))
                calls += 1;
        }
    };
    Probe.calls = 0;
    resource_view.active_services_source = .legacy_list;
    resource_view.legacy_loader_test_hook = Probe.load;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    var services = try ServicesView.init(std.testing.allocator, &theme, &service);
    defer services.deinit();
    var endpoints = try EndpointsView.init(std.testing.allocator, &theme, &service);
    defer endpoints.deinit();
    var endpoint_slices = try EndpointSlicesView.init(std.testing.allocator, &theme, &service);
    defer endpoint_slices.deinit();
    try services.refresh();
    try endpoints.refresh();
    try endpoint_slices.refresh();
    try std.testing.expectEqual(@as(usize, 3), Probe.calls);
    try std.testing.expectEqual(
        resource_view.Source.legacy_list,
        resource_view.familySourceRegistry().sourceFor(.services),
    );
}

test "config family rollback gate executes retained legacy loader seam" {
    const previous = resource_view.active_config_source;
    defer resource_view.active_config_source = previous;
    const previous_hook = resource_view.legacy_loader_test_hook;
    defer resource_view.legacy_loader_test_hook = previous_hook;
    const Probe = struct {
        var calls: usize = 0;
        fn load(resource: []const u8) void {
            inline for (.{ "configmaps", "secrets", "serviceaccounts", "resourcequotas", "limitranges" }) |name| {
                if (std.mem.eql(u8, resource, name)) calls += 1;
            }
        }
    };
    Probe.calls = 0;
    resource_view.active_config_source = .legacy_list;
    resource_view.legacy_loader_test_hook = Probe.load;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    inline for (.{
        ConfigMapsView,
        SecretsView,
        ServiceAccountsView,
        ResourceQuotasView,
        LimitRangesView,
    }) |ViewType| {
        var view = try ViewType.init(std.testing.allocator, &theme, &service);
        defer view.deinit();
        try view.refresh();
        try std.testing.expectEqual(.none, view.takeSubscriptionRequest());
    }
    try std.testing.expectEqual(@as(usize, 5), Probe.calls);
    try std.testing.expectEqual(
        resource_view.Source.legacy_list,
        resource_view.familySourceRegistry().sourceFor(.config),
    );
}

test "workloads family rollback gate executes retained legacy loader seam" {
    const previous = resource_view.active_workloads_source;
    defer resource_view.active_workloads_source = previous;
    const previous_hook = resource_view.legacy_loader_test_hook;
    defer resource_view.legacy_loader_test_hook = previous_hook;
    const Probe = struct {
        var calls: usize = 0;
        fn load(resource: []const u8) void {
            inline for (.{ "deployments", "statefulsets", "daemonsets", "replicasets" }) |name| {
                if (std.mem.eql(u8, resource, name)) calls += 1;
            }
        }
    };
    Probe.calls = 0;
    resource_view.active_workloads_source = .legacy_list;
    resource_view.legacy_loader_test_hook = Probe.load;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    inline for (.{ DeploymentsView, StatefulSetsView, DaemonSetsView, ReplicaSetsView }) |ViewType| {
        var view = try ViewType.init(std.testing.allocator, &theme, &service);
        defer view.deinit();
        try view.refresh();
        try std.testing.expectEqual(.none, view.takeSubscriptionRequest());
    }
    try std.testing.expectEqual(@as(usize, 4), Probe.calls);
    try std.testing.expectEqual(
        resource_view.Source.legacy_list,
        resource_view.familySourceRegistry().sourceFor(.workloads),
    );
}

test "batch family rollback gate executes retained legacy loader seam" {
    const previous = resource_view.active_batch_source;
    defer resource_view.active_batch_source = previous;
    const previous_hook = resource_view.legacy_loader_test_hook;
    defer resource_view.legacy_loader_test_hook = previous_hook;
    const Probe = struct {
        var calls: usize = 0;
        fn load(resource: []const u8) void {
            inline for (.{ "jobs", "cronjobs", "hpa", "poddisruptionbudgets" }) |name| {
                if (std.mem.eql(u8, resource, name)) calls += 1;
            }
        }
    };
    Probe.calls = 0;
    resource_view.active_batch_source = .legacy_list;
    resource_view.legacy_loader_test_hook = Probe.load;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    inline for (.{ JobsView, CronJobsView, HPAView, PodDisruptionBudgetsView }) |ViewType| {
        var view = try ViewType.init(std.testing.allocator, &theme, &service);
        defer view.deinit();
        try view.refresh();
        try std.testing.expectEqual(.none, view.takeSubscriptionRequest());
    }
    try std.testing.expectEqual(@as(usize, 4), Probe.calls);
    try std.testing.expectEqual(
        resource_view.Source.legacy_list,
        resource_view.familySourceRegistry().sourceFor(.batch),
    );
}

test "networking family rollback gate executes retained legacy loader seam" {
    const previous = resource_view.active_networking_source;
    defer resource_view.active_networking_source = previous;
    const previous_hook = resource_view.legacy_loader_test_hook;
    defer resource_view.legacy_loader_test_hook = previous_hook;
    const Probe = struct {
        var calls: usize = 0;
        fn load(resource: []const u8) void {
            inline for (.{ "ingresses", "ingressclasses", "networkpolicies", "ipaddresses", "servicecidrs" }) |name| {
                if (std.mem.eql(u8, resource, name)) calls += 1;
            }
        }
    };
    Probe.calls = 0;
    resource_view.active_networking_source = .legacy_list;
    resource_view.legacy_loader_test_hook = Probe.load;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    inline for (.{
        IngressesView,
        IngressClassesView,
        NetworkPoliciesView,
        IPAddressesView,
        ServiceCIDRsView,
    }) |ViewType| {
        var view = try ViewType.init(std.testing.allocator, &theme, &service);
        defer view.deinit();
        try view.refresh();
        try std.testing.expectEqual(.none, view.takeSubscriptionRequest());
    }
    try std.testing.expectEqual(@as(usize, 5), Probe.calls);
    try std.testing.expectEqual(
        resource_view.Source.legacy_list,
        resource_view.familySourceRegistry().sourceFor(.networking),
    );
}

test "storage family rollback gate executes retained legacy loader seam" {
    const previous = resource_view.active_storage_source;
    defer resource_view.active_storage_source = previous;
    const previous_hook = resource_view.legacy_loader_test_hook;
    defer resource_view.legacy_loader_test_hook = previous_hook;
    const Probe = struct {
        var calls: usize = 0;
        fn load(resource: []const u8) void {
            inline for (.{ "persistentvolumes", "persistentvolumeclaims", "storageclasses", "volumeattributesclasses", "csidrivers" }) |name| {
                if (std.mem.eql(u8, resource, name)) calls += 1;
            }
        }
    };
    Probe.calls = 0;
    resource_view.active_storage_source = .legacy_list;
    resource_view.legacy_loader_test_hook = Probe.load;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    inline for (.{
        PersistentVolumesView,
        PersistentVolumeClaimsView,
        StorageClassesView,
        VolumeAttributesClassesView,
        CSIDriversView,
    }) |ViewType| {
        var view = try ViewType.init(std.testing.allocator, &theme, &service);
        defer view.deinit();
        try view.refresh();
        try std.testing.expectEqual(.none, view.takeSubscriptionRequest());
    }
    try std.testing.expectEqual(@as(usize, 5), Probe.calls);
    try std.testing.expectEqual(
        resource_view.Source.legacy_list,
        resource_view.familySourceRegistry().sourceFor(.storage),
    );
}

fn expectSameColumns(
    comptime count: usize,
    allocator: std.mem.Allocator,
    legacy: [count][]const u8,
    projected: [count][]const u8,
) !void {
    defer for (legacy) |column| allocator.free(column);
    defer for (projected) |column| allocator.free(column);
    for (legacy, projected) |left, right| try std.testing.expectEqualStrings(left, right);
}

test "config records preserve exact legacy transform columns" {
    const allocator = std.testing.allocator;
    {
        var parsed = try std.json.parseFromSlice(
            klient.ConfigMap,
            allocator,
            \\{"metadata":{"uid":"cm-1","namespace":"team","name":"settings","creationTimestamp":"2024-01-01T00:00:00Z"},"data":{"a":"1","b":"2"}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/ConfigMapRecord.zig").fromConfigMap(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(4, allocator, try transformConfigMap(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.Secret,
            allocator,
            \\{"metadata":{"uid":"secret-1","namespace":"team","name":"token","creationTimestamp":"2024-01-01T00:00:00Z"},"type":"kubernetes.io/tls","data":{"tls.crt":"AA==","tls.key":"AA=="}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/SecretRecord.zig").fromSecret(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(5, allocator, try transformSecret(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.ServiceAccount,
            allocator,
            \\{"metadata":{"uid":"sa-1","namespace":"team","name":"builder","creationTimestamp":"2024-01-01T00:00:00Z"},"secrets":[{"name":"one"},{"name":"two"}]}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/ServiceAccountRecord.zig").fromServiceAccount(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(4, allocator, try transformServiceAccount(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.ResourceQuota,
            allocator,
            \\{"metadata":{"uid":"quota-1","namespace":"team","name":"compute","creationTimestamp":"2024-01-01T00:00:00Z"}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/ResourceQuotaRecord.zig").fromResourceQuota(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(3, allocator, try transformResourceQuota(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.LimitRange,
            allocator,
            \\{"metadata":{"uid":"limit-1","namespace":"team","name":"defaults","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"limits":[]}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/LimitRangeRecord.zig").fromLimitRange(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(3, allocator, try transformLimitRange(parsed.value, allocator), try record.columns(allocator));
    }
}

test "workload records preserve exact legacy transform columns" {
    const allocator = std.testing.allocator;
    {
        var parsed = try std.json.parseFromSlice(
            klient.Deployment,
            allocator,
            \\{"metadata":{"uid":"dep-1","namespace":"team","name":"api","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"replicas":4},"status":{"readyReplicas":2,"updatedReplicas":3,"availableReplicas":1}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/DeploymentRecord.zig").fromDeployment(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(6, allocator, try transformDeployment(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.StatefulSet,
            allocator,
            \\{"metadata":{"uid":"sts-1","namespace":"team","name":"db","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"replicas":3},"status":{"readyReplicas":2}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/StatefulSetRecord.zig").fromStatefulSet(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(4, allocator, try transformStatefulSet(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.DaemonSet,
            allocator,
            \\{"metadata":{"uid":"ds-1","namespace":"team","name":"agent","creationTimestamp":"2024-01-01T00:00:00Z"},"status":{"desiredNumberScheduled":5,"currentNumberScheduled":4,"numberReady":3,"updatedNumberScheduled":2}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/DaemonSetRecord.zig").fromDaemonSet(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(7, allocator, try transformDaemonSet(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.ReplicaSet,
            allocator,
            \\{"metadata":{"uid":"rs-1","namespace":"team","name":"api-abc","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"replicas":4},"status":{"replicas":3,"readyReplicas":2}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/ReplicaSetRecord.zig").fromReplicaSet(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(6, allocator, try transformReplicaSet(parsed.value, allocator), try record.columns(allocator));
    }
}

test "batch records preserve exact legacy transform columns" {
    const allocator = std.testing.allocator;
    {
        var parsed = try std.json.parseFromSlice(
            klient.Job,
            allocator,
            \\{"metadata":{"uid":"job-1","namespace":"team","name":"backup","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"completions":3},"status":{"succeeded":2,"startTime":"2024-01-01T00:00:00Z","completionTime":"2024-01-01T01:00:00Z"}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/JobRecord.zig").fromJob(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(5, allocator, try transformJob(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.CronJob,
            allocator,
            \\{"metadata":{"uid":"cron-1","namespace":"team","name":"nightly"},"spec":{"schedule":"0 0 * * *","suspend":true},"status":{"active":[{"name":"one"},{"name":"two"}]}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/CronJobRecord.zig").fromCronJob(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(6, allocator, try transformCronJob(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.HorizontalPodAutoscaler,
            allocator,
            \\{"metadata":{"uid":"hpa-1","namespace":"team","name":"api"},"spec":{"minReplicas":2,"maxReplicas":10,"scaleTargetRef":{"apiVersion":"apps/v1","kind":"Deployment","name":"api"}},"status":{"currentReplicas":4}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/HPARecord.zig").fromHorizontalPodAutoscaler(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(6, allocator, try transformHPA(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.PodDisruptionBudget,
            allocator,
            \\{"metadata":{"uid":"pdb-1","namespace":"team","name":"api"},"spec":{"minAvailable":"50%","maxUnavailable":1,"selector":{"matchLabels":{"app":"api"}}},"status":{"disruptionsAllowed":2}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/PDBRecord.zig").fromPodDisruptionBudget(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(6, allocator, try transformPodDisruptionBudget(parsed.value, allocator), try record.columns(allocator));
    }
}

test "cron job real suspend states preserve legacy projection parity" {
    const allocator = std.testing.allocator;
    const cases = [_]struct {
        json: []const u8,
        expected: []const u8,
    }{
        .{
            .json =
            \\{"metadata":{"uid":"cron-true","namespace":"team","name":"nightly"},"spec":{"schedule":"0 0 * * *","suspend":true}}
            ,
            .expected = "True",
        },
        .{
            .json =
            \\{"metadata":{"uid":"cron-false","namespace":"team","name":"nightly"},"spec":{"schedule":"0 0 * * *","suspend":false}}
            ,
            .expected = "False",
        },
        .{
            .json =
            \\{"metadata":{"uid":"cron-absent","namespace":"team","name":"nightly"},"spec":{"schedule":"0 0 * * *"}}
            ,
            .expected = "False",
        },
    };

    for (cases) |case| {
        var parsed = try std.json.parseFromSlice(
            klient.CronJob,
            allocator,
            case.json,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/CronJobRecord.zig").fromCronJob(allocator, parsed.value);
        defer record.deinit(allocator);
        const legacy = try transformCronJob(parsed.value, allocator);
        const projected = try record.columns(allocator);
        try std.testing.expectEqualStrings(case.expected, legacy[3]);
        try std.testing.expectEqualStrings(case.expected, projected[3]);
        try expectSameColumns(6, allocator, legacy, projected);
    }
}

test "networking records preserve exact retained transform columns" {
    const allocator = std.testing.allocator;
    {
        var parsed = try std.json.parseFromSlice(
            klient.types.Ingress,
            allocator,
            \\{"metadata":{"uid":"ing-1","namespace":"team","name":"web","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"ingressClassName":"nginx","rules":[{"host":"web.example"}],"tls":[{}]},"status":{"loadBalancer":{"ingress":[{"ip":"10.0.0.1"}]}}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/IngressRecord.zig").fromIngress(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(7, allocator, try transformIngress(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.NetworkPolicy,
            allocator,
            \\{"metadata":{"uid":"np-1","namespace":"team","name":"allow-web","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"podSelector":{"matchLabels":{"app":"web"}}}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/NetworkPolicyRecord.zig").fromNetworkPolicy(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(4, allocator, try transformNetworkPolicy(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.IngressClass,
            allocator,
            \\{"metadata":{"uid":"class-1","name":"nginx"},"spec":{"controller":"k8s.io/ingress-nginx"}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/IngressClassRecord.zig").fromIngressClass(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(3, allocator, try modern.transformIngressClass(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.IPAddress,
            allocator,
            \\{"metadata":{"uid":"ip-1","name":"10.0.0.8"},"spec":{"parentRef":{"name":"service-a"}}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/IPAddressRecord.zig").fromIPAddress(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(3, allocator, try modern.transformIPAddress(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(
            klient.ServiceCIDR,
            allocator,
            \\{"metadata":{"uid":"cidr-1","name":"kubernetes"},"spec":{"cidrs":["10.96.0.0/12","fd00::/108"]}}
        ,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        var record = try @import("../k8s/ServiceCIDRRecord.zig").fromServiceCIDR(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(3, allocator, try modern.transformServiceCIDR(parsed.value, allocator), try record.columns(allocator));
    }
}

test "storage real-shaped records preserve exact retained transform columns" {
    const allocator = std.testing.allocator;
    const fixtures = @import("../k8s/storage_records_test.zig");
    {
        var parsed = try std.json.parseFromSlice(klient.PersistentVolume, allocator, fixtures.pv_object_json, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        var record = try @import("../k8s/PVRecord.zig").fromPersistentVolume(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(8, allocator, try transformPersistentVolume(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(klient.PersistentVolumeClaim, allocator, fixtures.pvc_object_json, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        var record = try @import("../k8s/PVCRecord.zig").fromPersistentVolumeClaim(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(8, allocator, try transformPersistentVolumeClaim(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(klient.StorageClass, allocator, fixtures.storage_class_object_json, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        var record = try @import("../k8s/StorageClassRecord.zig").fromStorageClass(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(6, allocator, try transformStorageClass(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(klient.VolumeAttributesClass, allocator, fixtures.volume_attributes_class_object_json, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        var record = try @import("../k8s/VolumeAttributesClassRecord.zig").fromVolumeAttributesClass(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(3, allocator, try modern.transformVolumeAttributesClass(parsed.value, allocator), try record.columns(allocator));
    }
    {
        var parsed = try std.json.parseFromSlice(klient.CSIDriver, allocator, fixtures.csi_driver_object_json, .{ .ignore_unknown_fields = true });
        defer parsed.deinit();
        var record = try @import("../k8s/CSIDriverRecord.zig").fromCSIDriver(allocator, parsed.value);
        defer record.deinit(allocator);
        try expectSameColumns(4, allocator, try modern.transformCSIDriver(parsed.value, allocator), try record.columns(allocator));
    }
}

test "real-shaped ingress class projected columns match retained transform" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(
        klient.IngressClass,
        allocator,
        \\{"metadata":{"uid":"class-1","name":"nginx"},"spec":{"controller":"k8s.io/ingress-nginx"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try @import("../k8s/IngressClassRecord.zig").fromIngressClass(allocator, parsed.value);
    defer record.deinit(allocator);
    try expectSameColumns(
        3,
        allocator,
        try modern.transformIngressClass(parsed.value, allocator),
        try record.columns(allocator),
    );
}

test "config view declarations preserve exact columns scopes and defaults" {
    const Cases = .{
        .{ ConfigMapsView, true, &[_][]const u8{ "NAMESPACE", "NAME", "DATA", "AGE" } },
        .{ SecretsView, false, &[_][]const u8{ "NAMESPACE", "NAME", "TYPE", "DATA", "AGE" } },
        .{ ServiceAccountsView, false, &[_][]const u8{ "NAMESPACE", "NAME", "SECRETS", "AGE" } },
        .{ ResourceQuotasView, true, &[_][]const u8{ "NAMESPACE", "NAME", "AGE" } },
        .{ LimitRangesView, true, &[_][]const u8{ "NAMESPACE", "NAME", "AGE" } },
    };
    inline for (Cases) |case| {
        try std.testing.expect(case[0].view_config.is_namespaced);
        try std.testing.expectEqual(case[1], case[0].view_config.default_all_namespaces);
        try std.testing.expectEqual(case[2].len, case[0].view_config.columns.len);
        inline for (case[2], 0..) |name, index| {
            try std.testing.expectEqualStrings(name, case[0].view_config.columns[index].name);
        }
    }
}

test "workload view declarations preserve exact columns scopes and defaults" {
    const Cases = .{
        .{ DeploymentsView, false, &[_][]const u8{ "NAMESPACE", "NAME", "READY", "UP-TO-DATE", "AVAILABLE", "AGE" } },
        .{ StatefulSetsView, false, &[_][]const u8{ "NAMESPACE", "NAME", "READY", "AGE" } },
        .{ DaemonSetsView, true, &[_][]const u8{ "NAMESPACE", "NAME", "DESIRED", "CURRENT", "READY", "UP-TO-DATE", "AGE" } },
        .{ ReplicaSetsView, false, &[_][]const u8{ "NAMESPACE", "NAME", "DESIRED", "CURRENT", "READY", "AGE" } },
    };
    inline for (Cases) |case| {
        try std.testing.expect(case[0].view_config.is_namespaced);
        try std.testing.expectEqual(case[1], case[0].view_config.default_all_namespaces);
        try std.testing.expectEqual(case[2].len, case[0].view_config.columns.len);
        inline for (case[2], 0..) |name, index| {
            try std.testing.expectEqualStrings(name, case[0].view_config.columns[index].name);
        }
    }
}

test "batch view declarations preserve exact columns scopes and defaults" {
    const Cases = .{
        .{ JobsView, false, &[_][]const u8{ "NAMESPACE", "NAME", "COMPLETIONS", "DURATION", "AGE" } },
        .{ CronJobsView, false, &[_][]const u8{ "NAMESPACE", "NAME", "SCHEDULE", "SUSPEND", "ACTIVE", "LAST" } },
        .{ HPAView, true, &[_][]const u8{ "NAMESPACE", "NAME", "MINPODS", "MAXPODS", "REPLICAS", "AGE" } },
        .{ PodDisruptionBudgetsView, true, &[_][]const u8{ "NAMESPACE", "NAME", "MIN-AVAILABLE", "MAX-UNAVAILABLE", "ALLOWED-DISRUPTIONS", "AGE" } },
    };
    inline for (Cases) |case| {
        try std.testing.expect(case[0].view_config.is_namespaced);
        try std.testing.expectEqual(case[1], case[0].view_config.default_all_namespaces);
        try std.testing.expectEqual(case[2].len, case[0].view_config.columns.len);
        inline for (case[2], 0..) |name, index| {
            try std.testing.expectEqualStrings(name, case[0].view_config.columns[index].name);
        }
    }
}

test "networking view declarations preserve exact columns scopes and defaults" {
    const Cases = .{
        .{ IngressesView, true, false, &[_][]const u8{ "NAMESPACE", "NAME", "CLASS", "HOSTS", "ADDRESS", "PORTS", "AGE" } },
        .{ IngressClassesView, false, false, &[_][]const u8{ "NAME", "CONTROLLER", "AGE" } },
        .{ NetworkPoliciesView, true, false, &[_][]const u8{ "NAMESPACE", "NAME", "POD-SELECTOR", "AGE" } },
        .{ IPAddressesView, false, false, &[_][]const u8{ "NAME", "PARENT", "AGE" } },
        .{ ServiceCIDRsView, false, false, &[_][]const u8{ "NAME", "CIDRS", "AGE" } },
    };
    inline for (Cases) |case| {
        try std.testing.expectEqual(case[1], case[0].view_config.is_namespaced);
        try std.testing.expectEqual(case[2], case[0].view_config.default_all_namespaces);
        try std.testing.expectEqual(case[3].len, case[0].view_config.columns.len);
        inline for (case[3], 0..) |name, index| {
            try std.testing.expectEqualStrings(name, case[0].view_config.columns[index].name);
        }
    }
}

test "storage view declarations preserve exact columns scopes and defaults" {
    const Cases = .{
        .{ PersistentVolumesView, "persistentvolumes", false, &[_][]const u8{ "NAME", "CAPACITY", "ACCESS", "RECLAIM", "STATUS", "CLAIM", "STORAGECLASS", "AGE" } },
        .{ PersistentVolumeClaimsView, "persistentvolumeclaims", true, &[_][]const u8{ "NAMESPACE", "NAME", "STATUS", "VOLUME", "CAPACITY", "ACCESS", "STORAGECLASS", "AGE" } },
        .{ StorageClassesView, "storageclasses", false, &[_][]const u8{ "NAME", "PROVISIONER", "RECLAIMPOLICY", "BINDMODE", "EXPANSION", "AGE" } },
        .{ VolumeAttributesClassesView, "volumeattributesclasses", false, &[_][]const u8{ "NAME", "DRIVER", "AGE" } },
        .{ CSIDriversView, "csidrivers", false, &[_][]const u8{ "NAME", "ATTACHREQUIRED", "PODINFO", "AGE" } },
    };
    inline for (Cases) |case| {
        try std.testing.expectEqualStrings(case[1], case[0].view_config.name);
        try std.testing.expectEqual(case[2], case[0].view_config.is_namespaced);
        try std.testing.expectEqual(case[3].len, case[0].view_config.columns.len);
        inline for (case[3], 0..) |name, index|
            try std.testing.expectEqualStrings(name, case[0].view_config.columns[index].name);
    }
}

test "workload faults-only filter uses READY status" {
    const allocator = std.testing.allocator;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    var view = try DeploymentsView.init(allocator, &theme, &service);
    defer view.deinit();
    try view.table.appendItem(.{
        .columns = .{
            try allocator.dupe(u8, "team"),
            try allocator.dupe(u8, "healthy"),
            try allocator.dupe(u8, "3/3"),
            try allocator.dupe(u8, "3"),
            try allocator.dupe(u8, "3"),
            try allocator.dupe(u8, "1m"),
        },
        .allocator = allocator,
        .uid = try allocator.dupe(u8, "healthy-uid"),
    });
    try view.table.appendItem(.{
        .columns = .{
            try allocator.dupe(u8, "team"),
            try allocator.dupe(u8, "unhealthy"),
            try allocator.dupe(u8, "1/3"),
            try allocator.dupe(u8, "2"),
            try allocator.dupe(u8, "1"),
            try allocator.dupe(u8, "1m"),
        },
        .allocator = allocator,
        .uid = try allocator.dupe(u8, "unhealthy-uid"),
    });
    try view.applyFilter("");
    _ = try DeploymentsView.handleKey(&view, .ctrl_z);
    try std.testing.expectEqual(@as(usize, 1), view.table.filtered_indices.items.len);
    try std.testing.expectEqualStrings(
        "unhealthy",
        view.table.items.items[view.table.filtered_indices.items[0]].columns[1],
    );
}

test "stateful set faults-only filter uses READY status" {
    const allocator = std.testing.allocator;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    var view = try StatefulSetsView.init(allocator, &theme, &service);
    defer view.deinit();
    inline for (.{
        .{ "healthy", "3/3", "healthy-uid" },
        .{ "unhealthy", "1/3", "unhealthy-uid" },
    }) |row| {
        try view.table.appendItem(.{
            .columns = .{
                try allocator.dupe(u8, "team"),
                try allocator.dupe(u8, row[0]),
                try allocator.dupe(u8, row[1]),
                try allocator.dupe(u8, "1m"),
            },
            .allocator = allocator,
            .uid = try allocator.dupe(u8, row[2]),
        });
    }
    try view.applyFilter("");
    _ = try StatefulSetsView.handleKey(&view, .ctrl_z);
    try std.testing.expectEqual(@as(usize, 1), view.table.filtered_indices.items.len);
    try std.testing.expectEqualStrings("unhealthy", view.table.items.items[view.table.filtered_indices.items[0]].columns[1]);
}

test "daemon set faults-only filter compares bare READY to DESIRED" {
    const allocator = std.testing.allocator;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    var view = try DaemonSetsView.init(allocator, &theme, &service);
    defer view.deinit();
    inline for (.{
        .{ "healthy", "3", "healthy-uid" },
        .{ "unhealthy", "1", "unhealthy-uid" },
    }) |row| {
        try view.table.appendItem(.{
            .columns = .{
                try allocator.dupe(u8, "team"),
                try allocator.dupe(u8, row[0]),
                try allocator.dupe(u8, "3"),
                try allocator.dupe(u8, "3"),
                try allocator.dupe(u8, row[1]),
                try allocator.dupe(u8, "3"),
                try allocator.dupe(u8, "1m"),
            },
            .allocator = allocator,
            .uid = try allocator.dupe(u8, row[2]),
        });
    }
    try view.applyFilter("");
    _ = try DaemonSetsView.handleKey(&view, .ctrl_z);
    try std.testing.expectEqual(@as(usize, 1), view.table.filtered_indices.items.len);
    try std.testing.expectEqualStrings("unhealthy", view.table.items.items[view.table.filtered_indices.items[0]].columns[1]);
}

test "replica set faults-only filter compares bare READY to DESIRED" {
    const allocator = std.testing.allocator;
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    var view = try ReplicaSetsView.init(allocator, &theme, &service);
    defer view.deinit();
    inline for (.{
        .{ "healthy", "3", "healthy-uid" },
        .{ "unhealthy", "1", "unhealthy-uid" },
    }) |row| {
        try view.table.appendItem(.{
            .columns = .{
                try allocator.dupe(u8, "team"),
                try allocator.dupe(u8, row[0]),
                try allocator.dupe(u8, "3"),
                try allocator.dupe(u8, "3"),
                try allocator.dupe(u8, row[1]),
                try allocator.dupe(u8, "1m"),
            },
            .allocator = allocator,
            .uid = try allocator.dupe(u8, row[2]),
        });
    }
    try view.applyFilter("");
    _ = try ReplicaSetsView.handleKey(&view, .ctrl_z);
    try std.testing.expectEqual(@as(usize, 1), view.table.filtered_indices.items.len);
    try std.testing.expectEqualStrings("unhealthy", view.table.items.items[view.table.filtered_indices.items[0]].columns[1]);
}

test "services scope toggle requests exact subscription restart" {
    const ServiceRecord = @import("../k8s/ServiceRecord.zig");
    const Projection = @import("../k8s/ResourceProjection.zig").ResourceProjection(ServiceRecord);
    const Fns = struct {
        fn match(_: *const ServiceRecord, _: []const u8) bool {
            return true;
        }
        fn sort(record: *const ServiceRecord, _: u8) []const u8 {
            return record.key.name;
        }
        fn enabled() bool {
            return true;
        }
        fn columns(
            _: *Projection,
            record: *const ServiceRecord,
            allocator: std.mem.Allocator,
        ) ![7][]const u8 {
            return record.columns(allocator);
        }
    };
    var projection = Projection.init(std.testing.allocator, .{
        .matchFn = Fns.match,
        .sortKeyFn = Fns.sort,
    });
    defer projection.deinit();
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    var services = try ServicesView.init(std.testing.allocator, &theme, &service);
    defer services.deinit();
    services.bindProjection(ServicesView.ProjectionAdapter.init(
        ServiceRecord,
        &projection,
        Fns.enabled,
        Fns.columns,
    ));
    services.markSubscriptionStarted();
    _ = try ServicesView.handleKey(&services, .{ .char = '0' });
    try std.testing.expect(services.table.show_all_namespaces);
    try std.testing.expectEqual(.restart, services.takeSubscriptionRequest());
}

fn exerciseFamilyAtomicSync(
    comptime Record: type,
    comptime ViewType: type,
    comptime columns_count: usize,
) !void {
    const Projection = @import("../k8s/ResourceProjection.zig").ResourceProjection(Record);
    const keys = @import("../k8s/ResourceKey.zig");
    const column_count = columns_count;
    const Fns = struct {
        fn match(_: *const Record, _: []const u8) bool {
            return true;
        }
        fn sort(item: *const Record, _: u8) []const u8 {
            return item.key.name;
        }
        fn enabled() bool {
            return true;
        }
        fn columns(
            _: *Projection,
            item: *const Record,
            allocator: std.mem.Allocator,
        ) ![column_count][]const u8 {
            return item.columns(allocator);
        }
        fn makeRecord(allocator: std.mem.Allocator) !Record {
            const ServiceRecord = @import("../k8s/ServiceRecord.zig");
            const EndpointRecord = @import("../k8s/EndpointRecord.zig");
            const ConfigMapRecord = @import("../k8s/ConfigMapRecord.zig");
            const SecretRecord = @import("../k8s/SecretRecord.zig");
            const ServiceAccountRecord = @import("../k8s/ServiceAccountRecord.zig");
            const ResourceQuotaRecord = @import("../k8s/ResourceQuotaRecord.zig");
            const LimitRangeRecord = @import("../k8s/LimitRangeRecord.zig");
            const DeploymentRecord = @import("../k8s/DeploymentRecord.zig");
            const StatefulSetRecord = @import("../k8s/StatefulSetRecord.zig");
            const DaemonSetRecord = @import("../k8s/DaemonSetRecord.zig");
            const ReplicaSetRecord = @import("../k8s/ReplicaSetRecord.zig");
            const JobRecord = @import("../k8s/JobRecord.zig");
            const CronJobRecord = @import("../k8s/CronJobRecord.zig");
            const HPARecord = @import("../k8s/HPARecord.zig");
            const PDBRecord = @import("../k8s/PDBRecord.zig");
            const IngressRecord = @import("../k8s/IngressRecord.zig");
            const IngressClassRecord = @import("../k8s/IngressClassRecord.zig");
            const NetworkPolicyRecord = @import("../k8s/NetworkPolicyRecord.zig");
            const IPAddressRecord = @import("../k8s/IPAddressRecord.zig");
            const ServiceCIDRRecord = @import("../k8s/ServiceCIDRRecord.zig");
            const PVRecord = @import("../k8s/PVRecord.zig");
            const PVCRecord = @import("../k8s/PVCRecord.zig");
            const StorageClassRecord = @import("../k8s/StorageClassRecord.zig");
            const VolumeAttributesClassRecord = @import("../k8s/VolumeAttributesClassRecord.zig");
            const CSIDriverRecord = @import("../k8s/CSIDriverRecord.zig");
            const key = try (keys.ObjectKey{
                .uid = "resource-uid",
                .namespace = if (ViewType.view_config.is_namespaced) "default" else "",
                .name = "api",
            }).clone(allocator);
            if (comptime Record == ServiceRecord) return .{
                .key = key,
                .service_type = try allocator.dupe(u8, "ClusterIP"),
                .cluster_ip = try allocator.dupe(u8, "10.96.0.1"),
                .external_ip = try allocator.dupe(u8, "<none>"),
                .ports = try allocator.dupe(u8, "80/TCP"),
            };
            if (comptime Record == EndpointRecord) return .{
                .key = key,
                .endpoints = try allocator.dupe(u8, "2"),
            };
            if (comptime Record == ConfigMapRecord) return .{
                .key = key,
                .data_count = 2,
            };
            if (comptime Record == SecretRecord) return .{
                .key = key,
                .secret_type = try allocator.dupe(u8, "Opaque"),
                .data_count = 2,
            };
            if (comptime Record == ServiceAccountRecord) return .{
                .key = key,
                .secret_count = 2,
            };
            if (comptime Record == ResourceQuotaRecord or Record == LimitRangeRecord) return .{
                .key = key,
            };
            if (comptime Record == DeploymentRecord) return .{
                .key = key,
                .ready_replicas = 2,
                .desired_replicas = 4,
                .updated_replicas = 3,
                .available_replicas = 1,
            };
            if (comptime Record == StatefulSetRecord) return .{
                .key = key,
                .ready_replicas = 2,
                .desired_replicas = 3,
            };
            if (comptime Record == DaemonSetRecord) return .{
                .key = key,
                .desired = 5,
                .current = 4,
                .ready = 3,
                .updated = 2,
            };
            if (comptime Record == ReplicaSetRecord) return .{
                .key = key,
                .desired = 4,
                .current = 3,
                .ready = 2,
            };
            if (comptime Record == JobRecord) return .{
                .key = key,
                .succeeded = 2,
                .desired = 4,
                .completions_sort_key = JobRecord.ratioSortKey(2, 4),
            };
            if (comptime Record == CronJobRecord) return .{
                .key = key,
                .schedule = try allocator.dupe(u8, "0 0 * * *"),
                .@"suspend" = false,
                .active = 2,
                .active_sort_key = CronJobRecord.countSortKey(2),
            };
            if (comptime Record == HPARecord) return .{
                .key = key,
                .min_replicas = 2,
                .max_replicas = 10,
                .current_replicas = 4,
                .min_sort_key = HPARecord.countSortKey(2),
                .max_sort_key = HPARecord.countSortKey(10),
                .current_sort_key = HPARecord.countSortKey(4),
            };
            if (comptime Record == PDBRecord) return .{
                .key = key,
                .min_available = try allocator.dupe(u8, "1"),
                .max_unavailable = try allocator.dupe(u8, "1"),
                .allowed_disruptions = 2,
                .allowed_sort_key = PDBRecord.countSortKey(2),
            };
            if (comptime Record == IngressRecord) return .{
                .key = key,
                .class = try allocator.dupe(u8, "nginx"),
                .hosts = try allocator.dupe(u8, "api.example"),
                .address = try allocator.dupe(u8, "10.0.0.1"),
                .ports = try allocator.dupe(u8, "80"),
            };
            if (comptime Record == IngressClassRecord) return .{
                .key = key,
                .controller = try allocator.dupe(u8, "k8s.io/ingress-nginx"),
            };
            if (comptime Record == NetworkPolicyRecord) return .{
                .key = key,
                .pod_selector = try allocator.dupe(u8, "app=api"),
            };
            if (comptime Record == IPAddressRecord) return .{
                .key = key,
                .parent = try allocator.dupe(u8, "service-a"),
            };
            if (comptime Record == ServiceCIDRRecord) return .{
                .key = key,
                .cidrs = try allocator.dupe(u8, "10.96.0.0/12"),
            };
            if (comptime Record == PVRecord) return .{
                .key = key,
                .capacity = try allocator.dupe(u8, "10Gi"),
                .capacity_sort_key = PVRecord.capacitySortKey("10Gi"),
                .access = try allocator.dupe(u8, "RWO"),
                .reclaim = try allocator.dupe(u8, "Retain"),
                .status = try allocator.dupe(u8, "Bound"),
                .claim = try allocator.dupe(u8, "default/cache"),
                .storage_class = try allocator.dupe(u8, "fast"),
            };
            if (comptime Record == PVCRecord) return .{
                .key = key,
                .status = try allocator.dupe(u8, "Bound"),
                .volume = try allocator.dupe(u8, "pv-1"),
                .capacity = try allocator.dupe(u8, "10Gi"),
                .capacity_sort_key = PVRecord.capacitySortKey("10Gi"),
                .access = try allocator.dupe(u8, "RWO"),
                .storage_class = try allocator.dupe(u8, "fast"),
            };
            if (comptime Record == StorageClassRecord) return .{
                .key = key,
                .provisioner = try allocator.dupe(u8, "csi.example"),
                .reclaim_policy = try allocator.dupe(u8, "Retain"),
                .bind_mode = try allocator.dupe(u8, "Immediate"),
                .expansion = true,
            };
            if (comptime Record == VolumeAttributesClassRecord) return .{
                .key = key,
                .driver = try allocator.dupe(u8, "csi.example"),
            };
            if (comptime Record == CSIDriverRecord) return .{
                .key = key,
                .attach_required = true,
                .pod_info = false,
            };
            return .{
                .key = key,
                .address_type = try allocator.dupe(u8, "IPv4"),
                .endpoints = try allocator.dupe(u8, "2"),
            };
        }
    };
    const backing = std.testing.allocator;
    var projection = Projection.init(backing, .{
        .matchFn = Fns.match,
        .sortKeyFn = Fns.sort,
    });
    defer projection.deinit();
    var failing = std.testing.FailingAllocator.init(backing, .{});
    var service: @import("../services/K8sService.zig").K8sService = undefined;
    var theme: @import("../model/theme_loader.zig").ThemeColors = undefined;
    var view = try ViewType.init(failing.allocator(), &theme, &service);
    defer view.deinit();
    view.bindProjection(ViewType.ProjectionAdapter.init(
        Record,
        &projection,
        Fns.enabled,
        Fns.columns,
    ));
    const changes = try backing.alloc(keys.TypedChange(Record), 1);
    changes[0] = .{ .initial_upsert = try Fns.makeRecord(backing) };
    var batch = keys.TypedBatch(Record){
        .generation = 1,
        .subscription_id = 1,
        .revision = 1,
        .changes = changes,
        .sync = .list_started,
        .owned_bytes = 1,
    };
    defer batch.deinit(backing);
    var plan = try Projection.handler().preflight(@ptrCast(&projection), &batch, backing);
    Projection.handler().commit(@ptrCast(&projection), &batch, &plan);
    plan.deinit(backing);
    try view.syncProjection();
    try std.testing.expectEqualStrings(
        "api",
        view.table.items.items[0].columns[ViewType.view_config.name_column],
    );

    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(error.OutOfMemory, view.syncProjection());
    try std.testing.expectEqual(@as(usize, 1), view.table.items.items.len);
    try std.testing.expectEqualStrings(
        "api",
        view.table.items.items[0].columns[ViewType.view_config.name_column],
    );
}

test "services family projection table synchronization is allocation atomic" {
    try exerciseFamilyAtomicSync(
        @import("../k8s/ServiceRecord.zig"),
        ServicesView,
        7,
    );
    try exerciseFamilyAtomicSync(
        @import("../k8s/EndpointRecord.zig"),
        EndpointsView,
        4,
    );
    try exerciseFamilyAtomicSync(
        @import("../k8s/EndpointSliceRecord.zig"),
        EndpointSlicesView,
        5,
    );
}

test "config family projection table synchronization is allocation atomic" {
    try exerciseFamilyAtomicSync(
        @import("../k8s/ConfigMapRecord.zig"),
        ConfigMapsView,
        4,
    );
    try exerciseFamilyAtomicSync(
        @import("../k8s/SecretRecord.zig"),
        SecretsView,
        5,
    );
    try exerciseFamilyAtomicSync(
        @import("../k8s/ServiceAccountRecord.zig"),
        ServiceAccountsView,
        4,
    );
    try exerciseFamilyAtomicSync(
        @import("../k8s/ResourceQuotaRecord.zig"),
        ResourceQuotasView,
        3,
    );
    try exerciseFamilyAtomicSync(
        @import("../k8s/LimitRangeRecord.zig"),
        LimitRangesView,
        3,
    );
}

test "workload family projection table synchronization is allocation atomic" {
    try exerciseFamilyAtomicSync(
        @import("../k8s/DeploymentRecord.zig"),
        DeploymentsView,
        6,
    );
    try exerciseFamilyAtomicSync(
        @import("../k8s/StatefulSetRecord.zig"),
        StatefulSetsView,
        4,
    );
    try exerciseFamilyAtomicSync(
        @import("../k8s/DaemonSetRecord.zig"),
        DaemonSetsView,
        7,
    );
    try exerciseFamilyAtomicSync(
        @import("../k8s/ReplicaSetRecord.zig"),
        ReplicaSetsView,
        6,
    );
}

test "batch family projection table synchronization is allocation atomic" {
    try exerciseFamilyAtomicSync(@import("../k8s/JobRecord.zig"), JobsView, 5);
    try exerciseFamilyAtomicSync(@import("../k8s/CronJobRecord.zig"), CronJobsView, 6);
    try exerciseFamilyAtomicSync(@import("../k8s/HPARecord.zig"), HPAView, 6);
    try exerciseFamilyAtomicSync(@import("../k8s/PDBRecord.zig"), PodDisruptionBudgetsView, 6);
}

test "networking family projection table synchronization is allocation atomic" {
    try exerciseFamilyAtomicSync(@import("../k8s/IngressRecord.zig"), IngressesView, 7);
    try exerciseFamilyAtomicSync(@import("../k8s/IngressClassRecord.zig"), IngressClassesView, 3);
    try exerciseFamilyAtomicSync(@import("../k8s/NetworkPolicyRecord.zig"), NetworkPoliciesView, 4);
    try exerciseFamilyAtomicSync(@import("../k8s/IPAddressRecord.zig"), IPAddressesView, 3);
    try exerciseFamilyAtomicSync(@import("../k8s/ServiceCIDRRecord.zig"), ServiceCIDRsView, 3);
}

test "storage family projection table synchronization is allocation atomic" {
    try exerciseFamilyAtomicSync(@import("../k8s/PVRecord.zig"), PersistentVolumesView, 8);
    try exerciseFamilyAtomicSync(@import("../k8s/PVCRecord.zig"), PersistentVolumeClaimsView, 8);
    try exerciseFamilyAtomicSync(@import("../k8s/StorageClassRecord.zig"), StorageClassesView, 6);
    try exerciseFamilyAtomicSync(@import("../k8s/VolumeAttributesClassRecord.zig"), VolumeAttributesClassesView, 3);
    try exerciseFamilyAtomicSync(@import("../k8s/CSIDriverRecord.zig"), CSIDriversView, 4);
}

pub const ResourceClaimsView = modern.ResourceClaimsView;
pub const DeviceClassesView = modern.DeviceClassesView;
pub const PriorityClassesView = modern.PriorityClassesView;
pub const RuntimeClassesView = modern.RuntimeClassesView;
pub const LeasesView = modern.LeasesView;
pub const CertificateSigningRequestsView = modern.CertificateSigningRequestsView;
pub const StorageVersionMigrationsView = modern.StorageVersionMigrationsView;
