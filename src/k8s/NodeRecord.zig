const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const NodeRecord = @This();

key: keys.ObjectKey,
status: []u8,
roles: []u8,
version: []u8,
internal_ip: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromNode(allocator: std.mem.Allocator, node: klient.Node) !NodeRecord {
    const uid = node.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = "",
        .name = node.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);

    const status = try nodeStatus(allocator, node);
    errdefer allocator.free(status);
    const roles = try nodeRoles(allocator, node);
    errdefer allocator.free(roles);
    const version = try allocator.dupe(u8, nodeVersion(node));
    errdefer allocator.free(version);
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
        .internal_ip = internal_ip,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *NodeRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.status);
    allocator.free(self.roles);
    allocator.free(self.version);
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
