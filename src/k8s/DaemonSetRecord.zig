const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const DaemonSetRecord = @This();

key: keys.ObjectKey,
desired: i32,
current: i32,
ready: i32,
updated: i32,
desired_sort_key: [20]u8 = @splat('0'),
current_sort_key: [20]u8 = @splat('0'),
ready_sort_key: [20]u8 = @splat('0'),
updated_sort_key: [20]u8 = @splat('0'),
creation_timestamp: ?[]u8 = null,

pub fn fromDaemonSet(allocator: std.mem.Allocator, value: klient.DaemonSet) !DaemonSetRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "default");
    errdefer key.deinit(allocator);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    const desired = statusInt(value.status, "desiredNumberScheduled");
    const current = statusInt(value.status, "currentNumberScheduled");
    const ready = statusInt(value.status, "numberReady");
    const updated = statusInt(value.status, "updatedNumberScheduled");
    return .{
        .key = key,
        .desired = desired,
        .current = current,
        .ready = ready,
        .updated = updated,
        .desired_sort_key = @import("DeploymentRecord.zig").countSortKey(desired),
        .current_sort_key = @import("DeploymentRecord.zig").countSortKey(current),
        .ready_sort_key = @import("DeploymentRecord.zig").countSortKey(ready),
        .updated_sort_key = @import("DeploymentRecord.zig").countSortKey(updated),
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: DaemonSetRecord, allocator: std.mem.Allocator) !DaemonSetRecord {
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
        .updated = self.updated,
        .desired_sort_key = self.desired_sort_key,
        .current_sort_key = self.current_sort_key,
        .ready_sort_key = self.ready_sort_key,
        .updated_sort_key = self.updated_sort_key,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *DaemonSetRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const DaemonSetRecord, allocator: std.mem.Allocator) ![7][]const u8 {
    var result: [7][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    inline for (.{ self.desired, self.current, self.ready, self.updated }, 2..) |value, index| {
        result[index] = try std.fmt.allocPrint(allocator, "{d}", .{value});
        initialized += 1;
    }
    result[6] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn statusInt(status: ?std.json.Value, field: []const u8) i32 {
    const value = status orelse return 0;
    if (value != .object) return 0;
    const member = value.object.get(field) orelse return 0;
    return if (member == .integer) @intCast(member.integer) else 0;
}

test "daemon set record preserves workload columns and rejects missing UID" {
    var parsed = try std.json.parseFromSlice(
        klient.DaemonSet,
        std.testing.allocator,
        \\{"metadata":{"uid":"ds-1","namespace":"team","name":"agent"},"status":{"desiredNumberScheduled":5,"currentNumberScheduled":4,"numberReady":3,"updatedNumberScheduled":2}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromDaemonSet(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 5), record.desired);
    try std.testing.expectEqual(@as(i32, 2), record.updated);
    try std.testing.expectError(
        error.MissingUid,
        fromDaemonSet(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "ds-1", .namespace = "team", .name = "agent" }).clone(allocator);
        errdefer key.deinit(allocator);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk DaemonSetRecord{
            .key = key,
            .desired = 5,
            .current = 4,
            .ready = 3,
            .updated = 2,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "daemon set clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
