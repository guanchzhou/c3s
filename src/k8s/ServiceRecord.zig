const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const load_balancer = @import("LoadBalancerAddress.zig");
const keys = @import("ResourceKey.zig");

pub const ServiceRecord = @This();

key: keys.ObjectKey,
service_type: []u8,
cluster_ip: []u8,
external_ip: []u8,
ports: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromService(allocator: std.mem.Allocator, service: klient.Service) !ServiceRecord {
    const uid = service.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = service.metadata.namespace orelse "default",
        .name = service.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);

    const service_type = try allocator.dupe(
        u8,
        if (service.spec) |spec| spec.type orelse "ClusterIP" else "ClusterIP",
    );
    errdefer allocator.free(service_type);
    const cluster_ip = try allocator.dupe(
        u8,
        if (service.spec) |spec| spec.clusterIP orelse "<none>" else "<none>",
    );
    errdefer allocator.free(cluster_ip);
    const external_ip = try externalIp(allocator, service, service_type);
    errdefer allocator.free(external_ip);
    const ports = try formatPorts(allocator, service);
    errdefer allocator.free(ports);
    const creation_timestamp = if (service.metadata.creationTimestamp) |value|
        try allocator.dupe(u8, value)
    else
        null;

    return .{
        .key = key,
        .service_type = service_type,
        .cluster_ip = cluster_ip,
        .external_ip = external_ip,
        .ports = ports,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: ServiceRecord, allocator: std.mem.Allocator) !ServiceRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const service_type = try allocator.dupe(u8, self.service_type);
    errdefer allocator.free(service_type);
    const cluster_ip = try allocator.dupe(u8, self.cluster_ip);
    errdefer allocator.free(cluster_ip);
    const external_ip = try allocator.dupe(u8, self.external_ip);
    errdefer allocator.free(external_ip);
    const ports = try allocator.dupe(u8, self.ports);
    errdefer allocator.free(ports);
    const creation_timestamp = if (self.creation_timestamp) |value|
        try allocator.dupe(u8, value)
    else
        null;
    errdefer if (creation_timestamp) |value| allocator.free(value);
    return .{
        .key = key,
        .service_type = service_type,
        .cluster_ip = cluster_ip,
        .external_ip = external_ip,
        .ports = ports,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *ServiceRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.service_type);
    allocator.free(self.cluster_ip);
    allocator.free(self.external_ip);
    allocator.free(self.ports);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const ServiceRecord, allocator: std.mem.Allocator) ![7][]const u8 {
    var result: [7][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    inline for (.{ self.key.namespace, self.key.name, self.service_type, self.cluster_ip, self.external_ip, self.ports }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[6] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn externalIp(allocator: std.mem.Allocator, service: klient.Service, service_type: []const u8) ![]u8 {
    if (std.mem.eql(u8, service_type, "LoadBalancer")) {
        return (try load_balancer.format(allocator, service.status)) orelse
            allocator.dupe(u8, "<pending>");
    }
    if (service.spec) |spec| {
        if (spec.externalIPs) |addresses| {
            if (addresses.len > 0) {
                var result: std.ArrayListUnmanaged(u8) = .empty;
                defer result.deinit(allocator);
                for (addresses, 0..) |address, index| {
                    if (index > 0) try result.append(allocator, ',');
                    try result.appendSlice(allocator, address);
                }
                return result.toOwnedSlice(allocator);
            }
        }
    }
    return allocator.dupe(u8, "<none>");
}

fn formatPorts(allocator: std.mem.Allocator, service: klient.Service) ![]u8 {
    const spec = service.spec orelse return allocator.dupe(u8, "<none>");
    const ports = spec.ports orelse return allocator.dupe(u8, "<none>");
    if (ports.len == 0) return allocator.dupe(u8, "<none>");
    var result: std.ArrayListUnmanaged(u8) = .empty;
    defer result.deinit(allocator);
    for (ports, 0..) |port, index| {
        if (index > 0) try result.append(allocator, ',');
        const number: i64 = if (port.port) |value|
            if (value == .integer) value.integer else 0
        else
            0;
        const formatted = try std.fmt.allocPrint(
            allocator,
            "{d}/{s}",
            .{ number, port.protocol orelse "TCP" },
        );
        defer allocator.free(formatted);
        try result.appendSlice(allocator, formatted);
    }
    return result.toOwnedSlice(allocator);
}

test "service record preserves ports and load balancer columns" {
    var parsed = try std.json.parseFromSlice(
        klient.Service,
        std.testing.allocator,
        \\{"metadata":{"uid":"svc-1","namespace":"team","name":"api","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"type":"LoadBalancer","clusterIP":"10.96.0.1","ports":[{"port":80,"protocol":"TCP"},{"port":53,"protocol":"UDP"}]},"status":{"loadBalancer":{"ingress":[{"ip":"1.2.3.4"},{"hostname":"lb.example"}]}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromService(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("80/TCP,53/UDP", record.ports);
    try std.testing.expectEqualStrings("1.2.3.4,lb.example", record.external_ip);
}

test "UID-less service is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromService(std.testing.allocator, .{ .metadata = .{ .name = "api" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "service-uid",
            .namespace = "team",
            .name = "api",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const service_type = try allocator.dupe(u8, "LoadBalancer");
        errdefer allocator.free(service_type);
        const cluster_ip = try allocator.dupe(u8, "10.96.0.1");
        errdefer allocator.free(cluster_ip);
        const external_ip = try allocator.dupe(u8, "lb.example");
        errdefer allocator.free(external_ip);
        const ports = try allocator.dupe(u8, "80/TCP");
        errdefer allocator.free(ports);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk ServiceRecord{
            .key = key,
            .service_type = service_type,
            .cluster_ip = cluster_ip,
            .external_ip = external_ip,
            .ports = ports,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "service clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}
