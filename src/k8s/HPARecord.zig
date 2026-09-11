const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const HPARecord = @This();

key: keys.ObjectKey,
min_replicas: i32,
max_replicas: i32,
current_replicas: i32,
min_sort_key: [20]u8 = @splat('0'),
max_sort_key: [20]u8 = @splat('0'),
current_sort_key: [20]u8 = @splat('0'),
creation_timestamp: ?[]u8 = null,

pub fn fromHorizontalPodAutoscaler(
    allocator: std.mem.Allocator,
    hpa: klient.HorizontalPodAutoscaler,
) !HPARecord {
    var key = try keys.fromMetadata(allocator, hpa.metadata, "default");
    errdefer key.deinit(allocator);
    const creation_timestamp = try cloneOptional(allocator, hpa.metadata.creationTimestamp);
    errdefer if (creation_timestamp) |value| allocator.free(value);

    return .{
        .key = key,
        .min_replicas = if (hpa.spec) |spec| spec.minReplicas orelse 1 else 1,
        .max_replicas = if (hpa.spec) |spec| spec.maxReplicas else 1,
        .current_replicas = statusInt(hpa.status, "currentReplicas"),
        .min_sort_key = countSortKey(if (hpa.spec) |spec| spec.minReplicas orelse 1 else 1),
        .max_sort_key = countSortKey(if (hpa.spec) |spec| spec.maxReplicas else 1),
        .current_sort_key = countSortKey(statusInt(hpa.status, "currentReplicas")),
        .creation_timestamp = creation_timestamp,
    };
}

pub fn fromHPA(allocator: std.mem.Allocator, hpa: klient.HorizontalPodAutoscaler) !HPARecord {
    return fromHorizontalPodAutoscaler(allocator, hpa);
}

pub fn clone(self: HPARecord, allocator: std.mem.Allocator) !HPARecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const creation_timestamp = try cloneOptional(allocator, self.creation_timestamp);
    errdefer if (creation_timestamp) |value| allocator.free(value);

    return .{
        .key = key,
        .min_replicas = self.min_replicas,
        .max_replicas = self.max_replicas,
        .current_replicas = self.current_replicas,
        .min_sort_key = self.min_sort_key,
        .max_sort_key = self.max_sort_key,
        .current_sort_key = self.current_sort_key,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *HPARecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const HPARecord, allocator: std.mem.Allocator) ![6][]const u8 {
    var result: [6][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);

    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try std.fmt.allocPrint(allocator, "{d}", .{self.min_replicas});
    initialized += 1;
    result[3] = try std.fmt.allocPrint(allocator, "{d}", .{self.max_replicas});
    initialized += 1;
    result[4] = try std.fmt.allocPrint(allocator, "{d}", .{self.current_replicas});
    initialized += 1;
    result[5] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

pub fn countSortKey(value: i32) [20]u8 {
    var result: [20]u8 = @splat('0');
    var buffer: [20]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{@max(value, 0)}) catch unreachable;
    @memcpy(result[result.len - text.len ..], text);
    return result;
}

fn statusInt(status: ?std.json.Value, field: []const u8) i32 {
    const value = status orelse return 0;
    if (value != .object) return 0;
    const member = value.object.get(field) orelse return 0;
    return if (member == .integer) @intCast(member.integer) else 0;
}

fn cloneOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |bytes| try allocator.dupe(u8, bytes) else null;
}

fn freeColumns(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
}

test "HPA columns match legacy transform output" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(
        klient.HorizontalPodAutoscaler,
        allocator,
        \\{"metadata":{"uid":"hpa-1","namespace":"team","name":"api"},"spec":{"minReplicas":2,"maxReplicas":10,"scaleTargetRef":{"apiVersion":"apps/v1","kind":"Deployment","name":"api"}},"status":{"currentReplicas":4}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromHorizontalPodAutoscaler(allocator, parsed.value);
    defer record.deinit(allocator);
    const actual = try record.columns(allocator);
    defer freeColumns(allocator, &actual);
    const expected = [_][]const u8{ "team", "api", "2", "10", "4", "n/a" };
    for (expected, actual) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "UID-less HPA is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromHorizontalPodAutoscaler(
            std.testing.allocator,
            .{ .metadata = .{ .name = "bad" } },
        ),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "hpa-1",
            .namespace = "team",
            .name = "api",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const creation_timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        errdefer allocator.free(creation_timestamp);
        break :blk HPARecord{
            .key = key,
            .min_replicas = 2,
            .max_replicas = 10,
            .current_replicas = 4,
            .creation_timestamp = creation_timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "HPA clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}
