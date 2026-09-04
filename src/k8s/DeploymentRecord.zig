const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const DeploymentRecord = @This();

key: keys.ObjectKey,
ready_replicas: i32,
desired_replicas: i32,
updated_replicas: i32,
available_replicas: i32,
ready_sort_key: [41]u8 = [_]u8{'0'} ** 41,
updated_sort_key: [20]u8 = [_]u8{'0'} ** 20,
available_sort_key: [20]u8 = [_]u8{'0'} ** 20,
creation_timestamp: ?[]u8 = null,

pub fn fromDeployment(allocator: std.mem.Allocator, value: klient.Deployment) !DeploymentRecord {
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
    const updated_replicas = statusInt(value.status, "updatedReplicas");
    const available_replicas = statusInt(value.status, "availableReplicas");
    return .{
        .key = key,
        .ready_replicas = ready_replicas,
        .desired_replicas = desired_replicas,
        .updated_replicas = updated_replicas,
        .available_replicas = available_replicas,
        .ready_sort_key = ratioSortKey(ready_replicas, desired_replicas),
        .updated_sort_key = countSortKey(updated_replicas),
        .available_sort_key = countSortKey(available_replicas),
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: DeploymentRecord, allocator: std.mem.Allocator) !DeploymentRecord {
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
        .updated_replicas = self.updated_replicas,
        .available_replicas = self.available_replicas,
        .ready_sort_key = self.ready_sort_key,
        .updated_sort_key = self.updated_sort_key,
        .available_sort_key = self.available_sort_key,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *DeploymentRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const DeploymentRecord, allocator: std.mem.Allocator) ![6][]const u8 {
    var result: [6][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try std.fmt.allocPrint(allocator, "{d}/{d}", .{ self.ready_replicas, self.desired_replicas });
    initialized += 1;
    result[3] = try std.fmt.allocPrint(allocator, "{d}", .{self.updated_replicas});
    initialized += 1;
    result[4] = try std.fmt.allocPrint(allocator, "{d}", .{self.available_replicas});
    initialized += 1;
    result[5] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn statusInt(status: ?std.json.Value, field: []const u8) i32 {
    const value = status orelse return 0;
    if (value != .object) return 0;
    const member = value.object.get(field) orelse return 0;
    return if (member == .integer) @intCast(member.integer) else 0;
}

pub fn countSortKey(value: i32) [20]u8 {
    return @import("ConfigMapRecord.zig").numericSortKey(@intCast(@max(value, 0)));
}

pub fn ratioSortKey(ready: i32, desired: i32) [41]u8 {
    var result: [41]u8 = undefined;
    const ready_key = countSortKey(ready);
    const desired_key = countSortKey(desired);
    @memcpy(result[0..20], &ready_key);
    result[20] = '/';
    @memcpy(result[21..], &desired_key);
    return result;
}

test "deployment record preserves workload columns and rejects missing UID" {
    var parsed = try std.json.parseFromSlice(
        klient.Deployment,
        std.testing.allocator,
        \\{"metadata":{"uid":"dep-1","namespace":"team","name":"api","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"replicas":4},"status":{"readyReplicas":2,"updatedReplicas":3,"availableReplicas":1}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromDeployment(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 2), record.ready_replicas);
    try std.testing.expectEqual(@as(i32, 4), record.desired_replicas);
    try std.testing.expectError(
        error.MissingUid,
        fromDeployment(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "dep-1", .namespace = "team", .name = "api" }).clone(allocator);
        errdefer key.deinit(allocator);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk DeploymentRecord{
            .key = key,
            .ready_replicas = 2,
            .desired_replicas = 4,
            .updated_replicas = 3,
            .available_replicas = 1,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "deployment clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
