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

/// Join `status.loadBalancer.ingress[].ip`/`.hostname` (k9s ADDRESS/EXTERNAL-IP
/// for LoadBalancer Services and Ingresses). Returns `<pending>` when the
/// loadBalancer block exists but has no ingress entries; null when absent.
fn loadBalancerAddresses(alloc: std.mem.Allocator, status: ?std.json.Value) !?[]const u8 {
    const s = status orelse return null;
    if (s != .object) return null;
    const lb = s.object.get("loadBalancer") orelse return null;
    if (lb != .object) return null;
    const ingress = lb.object.get("ingress") orelse return try alloc.dupe(u8, "<pending>");
    if (ingress != .array) return null;
    if (ingress.array.items.len == 0) return try alloc.dupe(u8, "<pending>");

    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(alloc);
    var wrote = false;
    for (ingress.array.items) |entry| {
        if (entry != .object) continue;
        const addr = jsonValStr(entry, "ip") orelse jsonValStr(entry, "hostname") orelse continue;
        if (wrote) try buf.append(alloc, ',');
        try buf.appendSlice(alloc, addr);
        wrote = true;
    }
    if (!wrote) return try alloc.dupe(u8, "<pending>");
    return try buf.toOwnedSlice(alloc);
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
    // ConfigMap has no `spec` — `data` is top-level. Reading it through the old
    // `cm.spec` always yielded null, so this column showed 0 for every ConfigMap.
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
    // Ready condition, plus kubectl's `,SchedulingDisabled` when spec.unschedulable
    // is set -- the nodes `u` toggle keys off that substring.
    const unschedulable = if (node.spec) |spec| spec.unschedulable orelse false else false;
    const status = blk: {
        const base = inner: {
            if (node.status) |node_status| {
                if (node_status.conditions) |conditions| {
                    for (conditions) |condition| {
                        if (!std.mem.eql(u8, condition.type, "Ready")) continue;
                        const ready = std.mem.eql(u8, condition.status, "True");
                        break :inner try alloc.dupe(u8, if (ready) "Ready" else "NotReady");
                    }
                }
            }
            break :inner try alloc.dupe(u8, "Unknown");
        };
        if (!unschedulable) break :blk base;
        defer alloc.free(base);
        break :blk try std.fmt.allocPrint(alloc, "{s},SchedulingDisabled", .{base});
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

    // Extract internal IP from status.addresses
    const internal_ip = blk: {
        if (node.status) |node_status| {
            if (node_status.addresses) |addresses| {
                for (addresses) |addr| {
                    if (std.mem.eql(u8, addr.type, "InternalIP")) {
                        break :blk try alloc.dupe(u8, addr.address);
                    }
                }
            }
        }
        break :blk try alloc.dupe(u8, "<unknown>");
    };

    // Extract version from status.nodeInfo.kubeletVersion
    const version = blk: {
        if (node.status) |node_status| {
            if (node_status.nodeInfo) |node_info| {
                if (node_info.kubeletVersion) |v| break :blk try alloc.dupe(u8, v);
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
pub const ResourceClaimsView = modern.ResourceClaimsView;
pub const DeviceClassesView = modern.DeviceClassesView;
pub const PriorityClassesView = modern.PriorityClassesView;
pub const RuntimeClassesView = modern.RuntimeClassesView;
pub const LeasesView = modern.LeasesView;
pub const CertificateSigningRequestsView = modern.CertificateSigningRequestsView;
pub const StorageVersionMigrationsView = modern.StorageVersionMigrationsView;
