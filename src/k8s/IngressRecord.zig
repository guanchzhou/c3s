const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const load_balancer = @import("LoadBalancerAddress.zig");
const keys = @import("ResourceKey.zig");

pub const IngressRecord = @This();

key: keys.ObjectKey,
class: []u8,
hosts: []u8,
address: []u8,
ports: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromIngress(allocator: std.mem.Allocator, value: klient.types.Ingress) !IngressRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = value.metadata.namespace orelse "default",
        .name = value.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const class = try allocator.dupe(
        u8,
        if (value.spec) |spec| spec.ingressClassName orelse "<none>" else "<none>",
    );
    errdefer allocator.free(class);
    const hosts = try formatHosts(allocator, value);
    errdefer allocator.free(hosts);
    const address = (try load_balancer.format(allocator, value.status)) orelse
        try allocator.dupe(u8, "");
    errdefer allocator.free(address);
    const ports = try allocator.dupe(
        u8,
        if (value.spec) |spec|
            if (spec.tls != null and spec.tls.?.len > 0) "80, 443" else "80"
        else
            "80",
    );
    errdefer allocator.free(ports);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .class = class,
        .hosts = hosts,
        .address = address,
        .ports = ports,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: IngressRecord, allocator: std.mem.Allocator) !IngressRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const class = try allocator.dupe(u8, self.class);
    errdefer allocator.free(class);
    const hosts = try allocator.dupe(u8, self.hosts);
    errdefer allocator.free(hosts);
    const address = try allocator.dupe(u8, self.address);
    errdefer allocator.free(address);
    const ports = try allocator.dupe(u8, self.ports);
    errdefer allocator.free(ports);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .class = class,
        .hosts = hosts,
        .address = address,
        .ports = ports,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *IngressRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.class);
    allocator.free(self.hosts);
    allocator.free(self.address);
    allocator.free(self.ports);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const IngressRecord, allocator: std.mem.Allocator) ![7][]const u8 {
    var result: [7][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    inline for (.{ self.key.namespace, self.key.name, self.class, self.hosts, self.address, self.ports }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[6] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn formatHosts(allocator: std.mem.Allocator, value: klient.types.Ingress) ![]u8 {
    if (value.spec) |spec| {
        if (spec.rules) |rules| {
            var result: std.ArrayListUnmanaged(u8) = .empty;
            defer result.deinit(allocator);
            for (rules) |rule| {
                if (rule != .object) continue;
                const host = rule.object.get("host") orelse continue;
                if (host != .string) continue;
                if (result.items.len > 0) try result.append(allocator, ',');
                try result.appendSlice(allocator, host.string);
            }
            if (result.items.len > 0) return result.toOwnedSlice(allocator);
        }
    }
    return allocator.dupe(u8, "*");
}

test "ingress columns preserve legacy transform parity" {
    var parsed = try std.json.parseFromSlice(
        klient.types.Ingress,
        std.testing.allocator,
        \\{"metadata":{"uid":"ing-1","namespace":"team","name":"web"},"spec":{"ingressClassName":"nginx","rules":[{"host":"a.example"},{"host":"b.example"}],"tls":[{}]},"status":{"loadBalancer":{"ingress":[{"ip":"10.0.0.1"},{"hostname":"lb.example"}]}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromIngress(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "team", "web", "nginx", "a.example,b.example", "10.0.0.1,lb.example", "80, 443", "n/a" };
    for (actual, expected) |got, want| try std.testing.expectEqualStrings(want, got);
}

test "UID-less ingress is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromIngress(std.testing.allocator, .{ .metadata = .{ .name = "web" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var parsed = try std.json.parseFromSlice(
        klient.types.Ingress,
        allocator,
        \\{"metadata":{"uid":"ing-1","namespace":"team","name":"web","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"ingressClassName":"nginx","rules":[{"host":"a.example"}]},"status":{"loadBalancer":{"ingress":[{"ip":"10.0.0.1"}]}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var source = try fromIngress(allocator, parsed.value);
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "ingress clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
