/// Kubernetes 1.33–1.37 and Gateway API resource views.
///
/// Kept out of resource_configs.zig so the original 28 views stay readable.
/// Each view is the same ResourceView comptime template; describe/yaml/delete
/// work when ResourceType has a matching tag (see k8s_types.zig).
const std = @import("std");
const klient = @import("klient");
const resource_view = @import("resource_view.zig");
const ResourceView = resource_view.ResourceView;
const age_util = @import("../viewmodel/age.zig");
const table_layout = @import("../ui/table_layout.zig");

const P = table_layout.ColumnPriority;

fn dupe(alloc: std.mem.Allocator, s: []const u8) ![]const u8 {
    return alloc.dupe(u8, s);
}

fn none(alloc: std.mem.Allocator) ![]const u8 {
    return alloc.dupe(u8, "<none>");
}

fn nsOf(alloc: std.mem.Allocator, ns: ?[]const u8) ![]const u8 {
    return dupe(alloc, ns orelse "default");
}

fn ageOf(alloc: std.mem.Allocator, ts: ?[]const u8) ![]const u8 {
    return age_util.calculateAge(alloc, ts);
}

fn joinStrs(alloc: std.mem.Allocator, items: anytype) ![]const u8 {
    const arr = items orelse return none(alloc);
    if (arr.len == 0) return none(alloc);
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(alloc);
    for (arr, 0..) |s, i| {
        if (i > 0) try buf.append(alloc, ',');
        try buf.appendSlice(alloc, s);
    }
    return buf.toOwnedSlice(alloc);
}

fn firstObjStr(alloc: std.mem.Allocator, items: ?[]const std.json.Value, key: []const u8) ![]const u8 {
    const arr = items orelse return none(alloc);
    if (arr.len == 0) return none(alloc);
    if (arr[0] != .object) return none(alloc);
    if (arr[0].object.get(key)) |v| {
        if (v == .string) return dupe(alloc, v.string);
    }
    return none(alloc);
}

fn countItems(alloc: std.mem.Allocator, items: anytype) ![]const u8 {
    const n: usize = if (items) |a| a.len else 0;
    return std.fmt.allocPrint(alloc, "{d}", .{n});
}

fn jsonStrField(v: ?std.json.Value, key: []const u8) ?[]const u8 {
    const s = v orelse return null;
    if (s != .object) return null;
    if (s.object.get(key)) |inner| {
        if (inner == .string) return inner.string;
    }
    return null;
}

fn joinObjField(alloc: std.mem.Allocator, status: ?std.json.Value, array_key: []const u8, field: []const u8) ![]const u8 {
    const s = status orelse return none(alloc);
    if (s != .object) return none(alloc);
    const arr_v = s.object.get(array_key) orelse return none(alloc);
    if (arr_v != .array or arr_v.array.items.len == 0) return none(alloc);
    var buf = std.ArrayListUnmanaged(u8).empty;
    defer buf.deinit(alloc);
    var wrote = false;
    for (arr_v.array.items) |entry| {
        if (entry != .object) continue;
        const val = entry.object.get(field) orelse continue;
        if (val != .string) continue;
        if (wrote) try buf.append(alloc, ',');
        try buf.appendSlice(alloc, val.string);
        wrote = true;
    }
    if (!wrote) return none(alloc);
    return buf.toOwnedSlice(alloc);
}

// ============================================================================
// Gateway API
// ============================================================================

fn transformGatewayClass(item: klient.types.GatewayClass, alloc: std.mem.Allocator) ![3][]const u8 {
    const controller: []const u8 = if (item.spec) |spec| spec.controllerName else "<none>";
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, controller),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const GatewayClassesView = ResourceView(klient.types.GatewayClass, klient.resources.GatewayClasses, .{
    .name = "gatewayclasses",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "CONTROLLER", .min_width = 16, .max_width = 48, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformGatewayClass);

fn transformGateway(item: klient.types.Gateway, alloc: std.mem.Allocator) ![5][]const u8 {
    const class: []const u8 = if (item.spec) |spec| spec.gatewayClassName else "<none>";
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, class),
        try joinObjField(alloc, item.status, "addresses", "value"),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const GatewaysView = ResourceView(klient.types.Gateway, klient.resources.Gateways, .{
    .name = "gateways",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "CLASS", .min_width = 10, .max_width = 24, .priority = P.HIGH, .searchable = true },
        .{ .name = "ADDRESS", .min_width = 12, .max_width = 40, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformGateway);

fn transformHTTPRoute(item: klient.types.HTTPRoute, alloc: std.mem.Allocator) ![5][]const u8 {
    const parent = if (item.spec) |spec| spec.parentRefs else null;
    const hosts = if (item.spec) |spec| spec.hostnames else null;
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try firstObjStr(alloc, parent, "name"),
        try joinStrs(alloc, hosts),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const HTTPRoutesView = ResourceView(klient.types.HTTPRoute, klient.resources.HTTPRoutes, .{
    .name = "httproutes",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "PARENT", .min_width = 10, .max_width = 28, .priority = P.HIGH, .searchable = true },
        .{ .name = "HOSTNAMES", .min_width = 12, .max_width = 40, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformHTTPRoute);

fn transformGRPCRoute(item: klient.types.GRPCRoute, alloc: std.mem.Allocator) ![5][]const u8 {
    const parent = if (item.spec) |spec| spec.parentRefs else null;
    const hosts = if (item.spec) |spec| spec.hostnames else null;
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try firstObjStr(alloc, parent, "name"),
        try joinStrs(alloc, hosts),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const GRPCRoutesView = ResourceView(klient.types.GRPCRoute, klient.resources.GRPCRoutes, .{
    .name = "grpcroutes",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "PARENT", .min_width = 10, .max_width = 28, .priority = P.HIGH, .searchable = true },
        .{ .name = "HOSTNAMES", .min_width = 12, .max_width = 40, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformGRPCRoute);

fn transformReferenceGrant(item: klient.types.ReferenceGrant, alloc: std.mem.Allocator) ![5][]const u8 {
    const from: ?[]const std.json.Value = if (item.spec) |spec| spec.from else null;
    const to: ?[]const std.json.Value = if (item.spec) |spec| spec.to else null;
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try firstObjStr(alloc, from, "kind"),
        try firstObjStr(alloc, to, "kind"),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const ReferenceGrantsView = ResourceView(klient.types.ReferenceGrant, klient.resources.ReferenceGrants, .{
    .name = "referencegrants",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "FROM", .min_width = 8, .max_width = 20, .priority = P.HIGH },
        .{ .name = "TO", .min_width = 8, .max_width = 20, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformReferenceGrant);

fn transformTCPRoute(item: klient.types.TCPRoute, alloc: std.mem.Allocator) ![4][]const u8 {
    const parent = if (item.spec) |spec| spec.parentRefs else null;
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try firstObjStr(alloc, parent, "name"),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const TCPRoutesView = ResourceView(klient.types.TCPRoute, klient.resources.TCPRoutes, .{
    .name = "tcproutes",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "PARENT", .min_width = 10, .max_width = 28, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformTCPRoute);

fn transformTLSRoute(item: klient.types.TLSRoute, alloc: std.mem.Allocator) ![5][]const u8 {
    const parent = if (item.spec) |spec| spec.parentRefs else null;
    const hosts = if (item.spec) |spec| spec.hostnames else null;
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try firstObjStr(alloc, parent, "name"),
        try joinStrs(alloc, hosts),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const TLSRoutesView = ResourceView(klient.types.TLSRoute, klient.resources.TLSRoutes, .{
    .name = "tlsroutes",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "PARENT", .min_width = 10, .max_width = 28, .priority = P.HIGH, .searchable = true },
        .{ .name = "HOSTNAMES", .min_width = 12, .max_width = 40, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformTLSRoute);

fn transformUDPRoute(item: klient.types.UDPRoute, alloc: std.mem.Allocator) ![4][]const u8 {
    const parent = if (item.spec) |spec| spec.parentRefs else null;
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try firstObjStr(alloc, parent, "name"),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const UDPRoutesView = ResourceView(klient.types.UDPRoute, klient.resources.UDPRoutes, .{
    .name = "udproutes",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "PARENT", .min_width = 10, .max_width = 28, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformUDPRoute);

fn transformBackendTLSPolicy(item: klient.types.BackendTLSPolicy, alloc: std.mem.Allocator) ![4][]const u8 {
    const targets = if (item.spec) |spec| spec.targetRefs else null;
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try firstObjStr(alloc, targets, "name"),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const BackendTLSPoliciesView = ResourceView(klient.types.BackendTLSPolicy, klient.resources.BackendTLSPolicies, .{
    .name = "backendtlspolicies",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "TARGET", .min_width = 10, .max_width = 28, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformBackendTLSPolicy);

fn transformListenerSet(item: klient.types.ListenerSet, alloc: std.mem.Allocator) ![5][]const u8 {
    const parent_name = blk: {
        const spec = item.spec orelse break :blk "<none>";
        const ref = spec.parentRef orelse break :blk "<none>";
        if (ref != .object) break :blk "<none>";
        if (ref.object.get("name")) |v| {
            if (v == .string) break :blk v.string;
        }
        break :blk "<none>";
    };
    const n_listeners: usize = if (item.spec) |spec| (if (spec.listeners) |l| l.len else 0) else 0;
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, parent_name),
        try std.fmt.allocPrint(alloc, "{d}", .{n_listeners}),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const ListenerSetsView = ResourceView(klient.types.ListenerSet, klient.resources.ListenerSets, .{
    .name = "listenersets",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "PARENT", .min_width = 10, .max_width = 28, .priority = P.HIGH, .searchable = true },
        .{ .name = "LISTENERS", .min_width = 8, .max_width = 12, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformListenerSet);

// ============================================================================
// Networking extras
// ============================================================================

fn transformEndpointSlice(item: klient.types.EndpointSlice, alloc: std.mem.Allocator) ![5][]const u8 {
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, item.addressType),
        try countItems(alloc, item.endpoints),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const EndpointSlicesView = ResourceView(klient.types.EndpointSlice, klient.resources.EndpointSlices, .{
    .name = "endpointslices",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "ADDRESSTYPE", .min_width = 10, .max_width = 14, .priority = P.HIGH },
        .{ .name = "ENDPOINTS", .min_width = 8, .max_width = 12, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformEndpointSlice);

fn transformIngressClass(item: klient.types.IngressClass, alloc: std.mem.Allocator) ![3][]const u8 {
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, item.controller),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const IngressClassesView = ResourceView(klient.types.IngressClass, klient.resources.IngressClasses, .{
    .name = "ingressclasses",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "CONTROLLER", .min_width = 16, .max_width = 48, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformIngressClass);

fn transformIPAddress(item: klient.types.IPAddress, alloc: std.mem.Allocator) ![3][]const u8 {
    const parent = blk: {
        const spec = item.spec orelse break :blk "<none>";
        if (spec.parentRef != .object) break :blk "<none>";
        if (spec.parentRef.object.get("name")) |v| {
            if (v == .string) break :blk v.string;
        }
        break :blk "<none>";
    };
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, parent),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const IPAddressesView = ResourceView(klient.types.IPAddress, klient.resources.IPAddresses, .{
    .name = "ipaddresses",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "PARENT", .min_width = 12, .max_width = 36, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformIPAddress);

fn transformServiceCIDR(item: klient.types.ServiceCIDR, alloc: std.mem.Allocator) ![3][]const u8 {
    const cidrs = if (item.spec) |spec| spec.cidrs else null;
    return .{
        try dupe(alloc, item.metadata.name),
        try joinStrs(alloc, cidrs),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const ServiceCIDRsView = ResourceView(klient.types.ServiceCIDR, klient.resources.ServiceCIDRs, .{
    .name = "servicecidrs",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "CIDRS", .min_width = 16, .max_width = 48, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformServiceCIDR);

// ============================================================================
// Storage / CSI
// ============================================================================

fn transformVolumeAttributesClass(item: klient.types.VolumeAttributesClass, alloc: std.mem.Allocator) ![3][]const u8 {
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, item.driverName),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const VolumeAttributesClassesView = ResourceView(klient.types.VolumeAttributesClass, klient.resources.VolumeAttributesClasses, .{
    .name = "volumeattributesclasses",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "DRIVER", .min_width = 12, .max_width = 40, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformVolumeAttributesClass);

fn transformCSIDriver(item: klient.types.CSIDriver, alloc: std.mem.Allocator) ![4][]const u8 {
    const attach = if (item.spec.attachRequired orelse true) "true" else "false";
    const pod_info = if (item.spec.podInfoOnMount orelse false) "true" else "false";
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, attach),
        try dupe(alloc, pod_info),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const CSIDriversView = ResourceView(klient.types.CSIDriver, klient.resources.CSIDrivers, .{
    .name = "csidrivers",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "ATTACHREQUIRED", .min_width = 8, .max_width = 16, .priority = P.HIGH },
        .{ .name = "PODINFO", .min_width = 6, .max_width = 10, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformCSIDriver);

// ============================================================================
// Admission
// ============================================================================

fn transformVAP(item: klient.types.ValidatingAdmissionPolicy, alloc: std.mem.Allocator) ![4][]const u8 {
    const fail: []const u8 = if (item.spec) |spec| (spec.failurePolicy orelse "Fail") else "Fail";
    const n_val: usize = if (item.spec) |spec| (if (spec.validations) |v| v.len else 0) else 0;
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, fail),
        try std.fmt.allocPrint(alloc, "{d}", .{n_val}),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const ValidatingAdmissionPoliciesView = ResourceView(klient.types.ValidatingAdmissionPolicy, klient.resources.ValidatingAdmissionPolicies, .{
    .name = "validatingadmissionpolicies",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "FAILUREPOLICY", .min_width = 8, .max_width = 14, .priority = P.HIGH },
        .{ .name = "VALIDATIONS", .min_width = 8, .max_width = 14, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformVAP);

fn transformVAPB(item: klient.types.ValidatingAdmissionPolicyBinding, alloc: std.mem.Allocator) ![3][]const u8 {
    const policy: []const u8 = if (item.spec) |spec| spec.policyName else "<none>";
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, policy),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const ValidatingAdmissionPolicyBindingsView = ResourceView(klient.types.ValidatingAdmissionPolicyBinding, klient.resources.ValidatingAdmissionPolicyBindings, .{
    .name = "validatingadmissionpolicybindings",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "POLICY", .min_width = 12, .max_width = 36, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformVAPB);

fn transformMAP(item: klient.types.MutatingAdmissionPolicy, alloc: std.mem.Allocator) ![4][]const u8 {
    const fail: []const u8 = if (item.spec) |spec| (spec.failurePolicy orelse "Fail") else "Fail";
    const n_mut: usize = if (item.spec) |spec| (if (spec.mutations) |m| m.len else 0) else 0;
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, fail),
        try std.fmt.allocPrint(alloc, "{d}", .{n_mut}),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const MutatingAdmissionPoliciesView = ResourceView(klient.types.MutatingAdmissionPolicy, klient.resources.MutatingAdmissionPolicies, .{
    .name = "mutatingadmissionpolicies",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "FAILUREPOLICY", .min_width = 8, .max_width = 14, .priority = P.HIGH },
        .{ .name = "MUTATIONS", .min_width = 8, .max_width = 12, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformMAP);

fn transformMAPB(item: klient.types.MutatingAdmissionPolicyBinding, alloc: std.mem.Allocator) ![3][]const u8 {
    const policy: []const u8 = if (item.spec) |spec| spec.policyName else "<none>";
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, policy),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const MutatingAdmissionPolicyBindingsView = ResourceView(klient.types.MutatingAdmissionPolicyBinding, klient.resources.MutatingAdmissionPolicyBindings, .{
    .name = "mutatingadmissionpolicybindings",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "POLICY", .min_width = 12, .max_width = 36, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformMAPB);

fn transformVWC(item: klient.types.ValidatingWebhookConfiguration, alloc: std.mem.Allocator) ![3][]const u8 {
    return .{
        try dupe(alloc, item.metadata.name),
        try countItems(alloc, item.webhooks),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const ValidatingWebhookConfigurationsView = ResourceView(klient.types.ValidatingWebhookConfiguration, klient.resources.ValidatingWebhookConfigurations, .{
    .name = "validatingwebhookconfigurations",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 48, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "WEBHOOKS", .min_width = 8, .max_width = 12, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformVWC);

fn transformMWC(item: klient.types.MutatingWebhookConfiguration, alloc: std.mem.Allocator) ![3][]const u8 {
    return .{
        try dupe(alloc, item.metadata.name),
        try countItems(alloc, item.webhooks),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const MutatingWebhookConfigurationsView = ResourceView(klient.types.MutatingWebhookConfiguration, klient.resources.MutatingWebhookConfigurations, .{
    .name = "mutatingwebhookconfigurations",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 48, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "WEBHOOKS", .min_width = 8, .max_width = 12, .priority = P.HIGH },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformMWC);

// ============================================================================
// DRA
// ============================================================================

fn transformResourceClaim(item: klient.types.ResourceClaim, alloc: std.mem.Allocator) ![4][]const u8 {
    const status: []const u8 = blk: {
        const st = item.status orelse break :blk "pending";
        if (st != .object) break :blk "pending";
        if (st.object.get("allocation")) |_| break :blk "bound";
        break :blk "pending";
    };
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, status),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const ResourceClaimsView = ResourceView(klient.types.ResourceClaim, klient.resources.ResourceClaims, .{
    .name = "resourceclaims",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = P.HIGH, .sort_key = 'S' },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformResourceClaim);

fn transformDeviceClass(item: klient.types.DeviceClass, alloc: std.mem.Allocator) ![3][]const u8 {
    const n_sel: usize = if (item.spec) |spec| (if (spec.selectors) |s| s.len else 0) else 0;
    return .{
        try dupe(alloc, item.metadata.name),
        try std.fmt.allocPrint(alloc, "{d}", .{n_sel}),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const DeviceClassesView = ResourceView(klient.types.DeviceClass, klient.resources.DeviceClasses, .{
    .name = "deviceclasses",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "SELECTORS", .min_width = 8, .max_width = 12, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformDeviceClass);

// ============================================================================
// Cluster
// ============================================================================

fn transformPriorityClass(item: klient.types.PriorityClass, alloc: std.mem.Allocator) ![4][]const u8 {
    const glob = if (item.globalDefault orelse false) "true" else "false";
    return .{
        try dupe(alloc, item.metadata.name),
        try std.fmt.allocPrint(alloc, "{d}", .{item.value}),
        try dupe(alloc, glob),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const PriorityClassesView = ResourceView(klient.types.PriorityClass, klient.resources.PriorityClasses, .{
    .name = "priorityclasses",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "VALUE", .min_width = 6, .max_width = 12, .priority = P.HIGH, .sort_key = 'V' },
        .{ .name = "GLOBAL", .min_width = 6, .max_width = 10, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformPriorityClass);

fn transformRuntimeClass(item: klient.types.RuntimeClass, alloc: std.mem.Allocator) ![3][]const u8 {
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, item.handler),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const RuntimeClassesView = ResourceView(klient.types.RuntimeClass, klient.resources.RuntimeClasses, .{
    .name = "runtimeclasses",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "HANDLER", .min_width = 10, .max_width = 28, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformRuntimeClass);

fn transformLease(item: klient.types.Lease, alloc: std.mem.Allocator) ![4][]const u8 {
    const holder: []const u8 = if (item.spec) |spec| (spec.holderIdentity orelse "<none>") else "<none>";
    return .{
        try nsOf(alloc, item.metadata.namespace),
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, holder),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const LeasesView = ResourceView(klient.types.Lease, klient.resources.Leases, .{
    .name = "leases",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 36, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "HOLDER", .min_width = 12, .max_width = 40, .priority = P.HIGH, .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformLease);

fn transformCSR(item: klient.types.CertificateSigningRequest, alloc: std.mem.Allocator) ![4][]const u8 {
    const signer: []const u8 = if (item.spec) |spec| spec.signerName else "<none>";
    const cond = jsonStrField(item.status, "certificate");
    const status: []const u8 = if (cond != null) "Issued" else "Pending";
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, signer),
        try dupe(alloc, status),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const CertificateSigningRequestsView = ResourceView(klient.types.CertificateSigningRequest, klient.resources.CertificateSigningRequests, .{
    .name = "certificatesigningrequests",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "SIGNER", .min_width = 16, .max_width = 48, .priority = P.HIGH, .searchable = true },
        .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = P.HIGH, .sort_key = 'S' },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformCSR);

fn transformSVM(item: klient.types.StorageVersionMigration, alloc: std.mem.Allocator) ![3][]const u8 {
    return .{
        try dupe(alloc, item.metadata.name),
        try dupe(alloc, jsonStrField(item.status, "resourceVersion") orelse "<none>"),
        try ageOf(alloc, item.metadata.creationTimestamp),
    };
}

pub const StorageVersionMigrationsView = ResourceView(klient.types.StorageVersionMigration, klient.resources.StorageVersionMigrations, .{
    .name = "storageversionmigrations",
    .is_namespaced = false,
    .name_column = 0,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = P.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "RESOURCEVERSION", .min_width = 10, .max_width = 24, .priority = P.MEDIUM },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = P.MEDIUM, .sort_key = 'A' },
    },
}, transformSVM);

test "joinStrs empty is <none>" {
    const empty: ?[]const []const u8 = &.{};
    const got = try joinStrs(std.testing.allocator, empty);
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("<none>", got);
}

test "firstObjStr reads name from the first object" {
    const parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        \\[{"name":"as-public-gateway"}]
    ,
        .{},
    );
    defer parsed.deinit();
    const items = parsed.value.array.items;
    const got = try firstObjStr(std.testing.allocator, items, "name");
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings("as-public-gateway", got);
}
