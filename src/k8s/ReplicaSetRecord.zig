const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const ReplicaSetRecord = @This();

key: keys.ObjectKey,
desired: i32,
current: i32,
ready: i32,
desired_sort_key: [20]u8 = [_]u8{'0'} ** 20,
current_sort_key: [20]u8 = [_]u8{'0'} ** 20,
ready_sort_key: [20]u8 = [_]u8{'0'} ** 20,
creation_timestamp: ?[]u8 = null,

pub fn fromReplicaSet(allocator: std.mem.Allocator, value: klient.ReplicaSet) !ReplicaSetRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "default");
    errdefer key.deinit(allocator);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    const desired = if (value.spec) |spec| spec.replicas orelse 0 else 0;
    const current = statusInt(value.status, "replicas");
    const ready = statusInt(value.status, "readyReplicas");
    return .{
        .key = key,
        .desired = desired,
        .current = current,
        .ready = ready,
        .desired_sort_key = @import("DeploymentRecord.zig").countSortKey(desired),
        .current_sort_key = @import("DeploymentRecord.zig").countSortKey(current),
        .ready_sort_key = @import("DeploymentRecord.zig").countSortKey(ready),
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: ReplicaSetRecord, allocator: std.mem.Allocator) !ReplicaSetRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .desired = self.desired,
        .current = self.current,
        .ready = self.ready,
        .desired_sort_key = self.desired_sort_key,
        .current_sort_key = self.current_sort_key,
        .ready_sort_key = self.ready_sort_key,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *ReplicaSetRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const ReplicaSetRecord, allocator: std.mem.Allocator) ![6][]const u8 {
    var result: [6][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    inline for (.{ self.desired, self.current, self.ready }, 2..) |value, index| {
        result[index] = try std.fmt.allocPrint(allocator, "{d}", .{value});
        initialized += 1;
    }
    result[5] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn statusInt(status: ?std.json.Value, field: []const u8) i32 {
    const value = status orelse return 0;
    if (value != .object) return 0;
    const member = value.object.get(field) orelse return 0;
    return if (member == .integer) @intCast(member.integer) else 0;
}

test "replica set record preserves workload columns and rejects missing UID" {
    var parsed = try std.json.parseFromSlice(
        klient.ReplicaSet,
        std.testing.allocator,
        \\{"metadata":{"uid":"rs-1","namespace":"team","name":"api-abc"},"spec":{"replicas":4},"status":{"replicas":3,"readyReplicas":2}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromReplicaSet(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 4), record.desired);
    try std.testing.expectEqual(@as(i32, 2), record.ready);
    try std.testing.expectError(
        error.MissingUid,
        fromReplicaSet(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "rs-1", .namespace = "team", .name = "api-abc" }).clone(allocator);
        errdefer key.deinit(allocator);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk ReplicaSetRecord{
            .key = key,
            .desired = 4,
            .current = 3,
            .ready = 2,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "replica set clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
