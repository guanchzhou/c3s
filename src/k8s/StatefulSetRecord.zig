const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const StatefulSetRecord = @This();

key: keys.ObjectKey,
ready_replicas: i32,
desired_replicas: i32,
ready_sort_key: [41]u8 = [_]u8{'0'} ** 41,
creation_timestamp: ?[]u8 = null,

pub fn fromStatefulSet(allocator: std.mem.Allocator, value: klient.StatefulSet) !StatefulSetRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = value.metadata.namespace orelse "default",
        .name = value.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    const ready_replicas = statusInt(value.status, "readyReplicas");
    const desired_replicas = if (value.spec) |spec| spec.replicas orelse 0 else 0;
    return .{
        .key = key,
        .ready_replicas = ready_replicas,
        .desired_replicas = desired_replicas,
        .ready_sort_key = @import("DeploymentRecord.zig").ratioSortKey(ready_replicas, desired_replicas),
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: StatefulSetRecord, allocator: std.mem.Allocator) !StatefulSetRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .ready_replicas = self.ready_replicas,
        .desired_replicas = self.desired_replicas,
        .ready_sort_key = self.ready_sort_key,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *StatefulSetRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const StatefulSetRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try std.fmt.allocPrint(allocator, "{d}/{d}", .{ self.ready_replicas, self.desired_replicas });
    initialized += 1;
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn statusInt(status: ?std.json.Value, field: []const u8) i32 {
    const value = status orelse return 0;
    if (value != .object) return 0;
    const member = value.object.get(field) orelse return 0;
    return if (member == .integer) @intCast(member.integer) else 0;
}

test "stateful set record preserves workload columns and rejects missing UID" {
    var parsed = try std.json.parseFromSlice(
        klient.StatefulSet,
        std.testing.allocator,
        \\{"metadata":{"uid":"sts-1","namespace":"team","name":"db"},"spec":{"replicas":3},"status":{"readyReplicas":2}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromStatefulSet(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 2), record.ready_replicas);
    try std.testing.expectEqual(@as(i32, 3), record.desired_replicas);
    try std.testing.expectError(
        error.MissingUid,
        fromStatefulSet(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "sts-1", .namespace = "team", .name = "db" }).clone(allocator);
        errdefer key.deinit(allocator);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk StatefulSetRecord{
            .key = key,
            .ready_replicas = 2,
            .desired_replicas = 3,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "stateful set clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
