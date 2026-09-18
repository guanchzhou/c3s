const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const NodeRecord = @This();

key: keys.ObjectKey,
status: []u8,
roles: []u8,
version: []u8,
version_sort_key: []u8 = &.{},
internal_ip: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromNode(allocator: std.mem.Allocator, node: klient.Node) !NodeRecord {
    var key = try keys.fromMetadata(allocator, node.metadata, "");
    errdefer key.deinit(allocator);

    const status = try nodeStatus(allocator, node);
    errdefer allocator.free(status);
    const roles = try nodeRoles(allocator, node);
    errdefer allocator.free(roles);
    const version = try allocator.dupe(u8, nodeVersion(node));
    errdefer allocator.free(version);
    const version_sort_key = try kubernetesVersionSortKey(allocator, version);
    errdefer allocator.free(version_sort_key);
    const internal_ip = try allocator.dupe(u8, nodeInternalIp(node));
    errdefer allocator.free(internal_ip);
    const creation_timestamp = if (node.metadata.creationTimestamp) |value|
        try allocator.dupe(u8, value)
    else
        null;

    return .{
        .key = key,
        .status = status,
        .roles = roles,
        .version = version,
        .version_sort_key = version_sort_key,
        .internal_ip = internal_ip,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: NodeRecord, allocator: std.mem.Allocator) !NodeRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const status = try allocator.dupe(u8, self.status);
    errdefer allocator.free(status);
    const roles = try allocator.dupe(u8, self.roles);
    errdefer allocator.free(roles);
    const version = try allocator.dupe(u8, self.version);
    errdefer allocator.free(version);
    const version_sort_key = try kubernetesVersionSortKey(allocator, version);
    errdefer allocator.free(version_sort_key);
    const internal_ip = try allocator.dupe(u8, self.internal_ip);
    errdefer allocator.free(internal_ip);
    const creation_timestamp = if (self.creation_timestamp) |value|
        try allocator.dupe(u8, value)
    else
        null;
    return .{
        .key = key,
        .status = status,
        .roles = roles,
        .version = version,
        .version_sort_key = version_sort_key,
        .internal_ip = internal_ip,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *NodeRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.status);
    allocator.free(self.roles);
    allocator.free(self.version);
    if (self.version_sort_key.len > 0) allocator.free(self.version_sort_key);
    allocator.free(self.internal_ip);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const NodeRecord, allocator: std.mem.Allocator) ![6][]const u8 {
    var result: [6][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.status);
    initialized += 1;
    result[2] = try allocator.dupe(u8, self.roles);
    initialized += 1;
    result[3] = try allocator.dupe(u8, self.version);
    initialized += 1;
    result[4] = try allocator.dupe(u8, self.internal_ip);
    initialized += 1;
    result[5] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn nodeStatus(allocator: std.mem.Allocator, node: klient.Node) ![]u8 {
    const base = blk: {
        if (node.status) |status| {
            if (status.conditions) |conditions| {
                for (conditions) |condition| {
                    if (!std.mem.eql(u8, condition.type, "Ready")) continue;
                    break :blk if (std.mem.eql(u8, condition.status, "True"))
                        "Ready"
                    else
                        "NotReady";
                }
            }
        }
        break :blk "Unknown";
    };
    const unschedulable = if (node.spec) |spec| spec.unschedulable orelse false else false;
    return if (unschedulable)
        std.fmt.allocPrint(allocator, "{s},SchedulingDisabled", .{base})
    else
        allocator.dupe(u8, base);
}

fn nodeRoles(allocator: std.mem.Allocator, node: klient.Node) ![]u8 {
    const labels = node.metadata.labels orelse return allocator.dupe(u8, "<none>");
    if (labels != .object) return allocator.dupe(u8, "<none>");

    var iterator = labels.object.iterator();
    const prefix = "node-role.kubernetes.io/";
    var buffer: [256]u8 = undefined;
    var length: usize = 0;
    while (iterator.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.startsWith(u8, key, prefix) and key.len > prefix.len) {
            if (length > 0 and length < buffer.len) {
                buffer[length] = ',';
                length += 1;
            }
            const role = key[prefix.len..];
            const copy_length = @min(role.len, buffer.len - length);
            @memcpy(buffer[length..][0..copy_length], role[0..copy_length]);
            length += copy_length;
        }
    }
    return if (length == 0)
        allocator.dupe(u8, "<none>")
    else
        allocator.dupe(u8, buffer[0..length]);
}

fn nodeInternalIp(node: klient.Node) []const u8 {
    if (node.status) |status| {
        if (status.addresses) |addresses| {
            for (addresses) |address| {
                if (std.mem.eql(u8, address.type, "InternalIP")) return address.address;
            }
        }
    }
    return "<unknown>";
}

fn nodeVersion(node: klient.Node) []const u8 {
    if (node.status) |status| {
        if (status.nodeInfo) |info| {
            if (info.kubeletVersion) |value| return value;
        }
    }
    return "unknown";
}

const KubernetesVersion = struct {
    major: u64,
    minor: u64,
    patch: u64,
};

fn parseKubernetesVersion(value: []const u8) ?KubernetesVersion {
    if (value.len < 2 or value[0] != 'v') return null;
    var cursor: usize = 1;
    const major = parseVersionComponent(value, &cursor) orelse return null;
    if (cursor >= value.len or value[cursor] != '.') return null;
    cursor += 1;
    const minor = parseVersionComponent(value, &cursor) orelse return null;
    if (cursor >= value.len or value[cursor] != '.') return null;
    cursor += 1;
    const patch = parseVersionComponent(value, &cursor) orelse return null;
    if (cursor < value.len and value[cursor] != '+' and value[cursor] != '-') return null;
    if (cursor + 1 == value.len) return null;
    return .{ .major = major, .minor = minor, .patch = patch };
}

fn parseVersionComponent(value: []const u8, cursor: *usize) ?u64 {
    const start = cursor.*;
    while (cursor.* < value.len and std.ascii.isDigit(value[cursor.*])) cursor.* += 1;
    if (cursor.* == start) return null;
    return std.fmt.parseInt(u64, value[start..cursor.*], 10) catch null;
}

pub fn compareKubernetesVersions(left: []const u8, right: []const u8) std.math.Order {
    const left_version = parseKubernetesVersion(left) orelse return std.mem.order(u8, left, right);
    const right_version = parseKubernetesVersion(right) orelse return std.mem.order(u8, left, right);
    inline for (.{ "major", "minor", "patch" }) |field| {
        const order = std.math.order(@field(left_version, field), @field(right_version, field));
        if (order != .eq) return order;
    }
    return .eq;
}

pub fn kubernetesVersionSortKey(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    const parsed = parseKubernetesVersion(value) orelse {
        const result = try allocator.alloc(u8, value.len + 1);
        result[0] = '0';
        @memcpy(result[1..], value);
        return result;
    };
    const result = try allocator.alloc(u8, 61);
    result[0] = '1';
    writeNumericSortComponent(result[1..21], parsed.major);
    writeNumericSortComponent(result[21..41], parsed.minor);
    writeNumericSortComponent(result[41..61], parsed.patch);
    return result;
}

fn writeNumericSortComponent(result: []u8, value: u64) void {
    @memset(result, '0');
    var buffer: [20]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable;
    @memcpy(result[result.len - text.len ..], text);
}

test "node record preserves scheduling status and display columns" {
    const allocator = std.testing.allocator;
    var conditions = [_]klient.types.NodeCondition{
        .{ .type = "Ready", .status = "True" },
    };
    var addresses = [_]klient.types.NodeAddress{
        .{ .type = "InternalIP", .address = "10.0.0.1" },
    };
    const node = klient.Node{
        .metadata = .{
            .uid = "node-uid",
            .name = "worker-1",
            .creationTimestamp = "2024-01-01T00:00:00Z",
        },
        .spec = .{ .unschedulable = true },
        .status = .{
            .conditions = &conditions,
            .addresses = &addresses,
            .nodeInfo = .{ .kubeletVersion = "v1.31.0" },
        },
    };
    var record = try fromNode(allocator, node);
    defer record.deinit(allocator);
    try std.testing.expectEqualStrings("Ready,SchedulingDisabled", record.status);
    const display = try record.columns(allocator);
    defer for (display) |column| allocator.free(column);
    try std.testing.expectEqualStrings("worker-1", display[0]);
    try std.testing.expectEqualStrings("10.0.0.1", display[4]);
}

test "UID-less node is malformed" {
    const node = klient.Node{ .metadata = .{ .name = "worker" } };
    try std.testing.expectError(error.MissingUid, fromNode(std.testing.allocator, node));
}

test "Kubernetes versions sort by numeric core and accept vendor suffixes" {
    try std.testing.expectEqual(
        std.math.Order.lt,
        compareKubernetesVersions("v1.9.9", "v1.30.0"),
    );
    try std.testing.expectEqual(
        std.math.Order.lt,
        compareKubernetesVersions("v1.35.2+k3s9", "v1.35.3+k3s1"),
    );
    try std.testing.expectEqual(
        std.math.Order.lt,
        compareKubernetesVersions("v1.31.3-eks-ffff", "v1.31.4-eks-abc123"),
    );
    try std.testing.expectEqual(
        std.math.Order.eq,
        compareKubernetesVersions("v1.31.4", "v1.31.4-eks-abc123"),
    );
    try std.testing.expectEqual(
        std.math.Order.lt,
        compareKubernetesVersions("not-a-version", "unknown"),
    );
}

test "Kubernetes version sort keys preserve semantic ordering" {
    const allocator = std.testing.allocator;
    const old = try kubernetesVersionSortKey(allocator, "v1.9.9");
    defer allocator.free(old);
    const new = try kubernetesVersionSortKey(allocator, "v1.30.0");
    defer allocator.free(new);
    const k3s = try kubernetesVersionSortKey(allocator, "v1.35.3+k3s1");
    defer allocator.free(k3s);
    const eks = try kubernetesVersionSortKey(allocator, "v1.31.4-eks-abc123");
    defer allocator.free(eks);

    try std.testing.expectEqual(std.math.Order.lt, std.mem.order(u8, old, new));
    try std.testing.expectEqual(std.math.Order.lt, std.mem.order(u8, eks, k3s));
}
