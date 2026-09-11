const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const k9s_query = @import("../viewmodel/k9s_query.zig");
const keys = @import("ResourceKey.zig");

pub const ConfigMapRecord = @This();

key: keys.ObjectKey,
data_count: usize,
data_sort_key: [20]u8 = @splat('0'),
creation_timestamp: ?[]u8 = null,

pub fn fromConfigMap(allocator: std.mem.Allocator, value: klient.ConfigMap) !ConfigMapRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "default");
    errdefer key.deinit(allocator);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    return .{
        .key = key,
        .data_count = objectCount(value.data),
        .data_sort_key = numericSortKey(objectCount(value.data)),
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: ConfigMapRecord, allocator: std.mem.Allocator) !ConfigMapRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .data_count = self.data_count,
        .data_sort_key = self.data_sort_key,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *ConfigMapRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const ConfigMapRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try std.fmt.allocPrint(allocator, "{d}", .{self.data_count});
    initialized += 1;
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn objectCount(value: ?std.json.Value) usize {
    const actual = value orelse return 0;
    return if (actual == .object) actual.object.count() else 0;
}

pub fn numericSortKey(value: usize) [20]u8 {
    var result: [20]u8 = @splat('0');
    var buffer: [20]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{value}) catch unreachable;
    @memcpy(result[result.len - text.len ..], text);
    return result;
}

test "config map record preserves legacy columns and rejects missing UID" {
    var parsed = try std.json.parseFromSlice(
        klient.ConfigMap,
        std.testing.allocator,
        \\{"metadata":{"uid":"cm-1","namespace":"team","name":"settings","labels":{"app":"web"},"creationTimestamp":"2024-01-01T00:00:00Z"},"data":{"one":"1","two":"2"},"binaryData":{"ignored":"AA=="}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromConfigMap(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), record.data_count);
    try std.testing.expectEqualStrings("app=web", record.key.labels);
    try std.testing.expect(k9s_query.matchSearchable(
        &.{ record.key.namespace, record.key.name },
        record.key.labels,
        "-l app=web",
    ));
    try std.testing.expectError(
        error.MissingUid,
        fromConfigMap(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "cm-1",
            .namespace = "team",
            .name = "settings",
            .labels = "app=web,env=prod",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk ConfigMapRecord{
            .key = key,
            .data_count = 2,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    defer copy.deinit(allocator);
    try std.testing.expectEqualStrings("app=web,env=prod", copy.key.labels);
}

test "config map clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}

fn labeledDecodeExercise(allocator: std.mem.Allocator, value: klient.ConfigMap) !void {
    var record = try fromConfigMap(allocator, value);
    defer record.deinit(allocator);
    try std.testing.expectEqualStrings("app=web,env=prod", record.key.labels);
}

test "labeled config map decode is allocation-failure safe" {
    var parsed = try std.json.parseFromSlice(
        klient.ConfigMap,
        std.testing.allocator,
        \\{"metadata":{"uid":"cm-1","namespace":"team","name":"settings","labels":{"app":"web","env":"prod"},"creationTimestamp":"2024-01-01T00:00:00Z"},"data":{"one":"1"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        labeledDecodeExercise,
        .{parsed.value},
    );
}
