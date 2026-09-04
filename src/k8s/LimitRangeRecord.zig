const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const LimitRangeRecord = @This();

key: keys.ObjectKey,
creation_timestamp: ?[]u8 = null,

pub fn fromLimitRange(allocator: std.mem.Allocator, value: klient.LimitRange) !LimitRangeRecord {
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
    return .{ .key = key, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: LimitRangeRecord, allocator: std.mem.Allocator) !LimitRangeRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *LimitRangeRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const LimitRangeRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    var result: [3][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "limit range record preserves identity and rejects missing UID" {
    var parsed = try std.json.parseFromSlice(
        klient.LimitRange,
        std.testing.allocator,
        \\{"metadata":{"uid":"limit-1","namespace":"team","name":"defaults"},"spec":{"limits":[]}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromLimitRange(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("defaults", record.key.name);
    try std.testing.expectError(
        error.MissingUid,
        fromLimitRange(std.testing.allocator, .{
            .metadata = .{ .name = "bad" },
            .spec = .{ .limits = &.{} },
        }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "limit-1",
            .namespace = "team",
            .name = "defaults",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk LimitRangeRecord{ .key = key, .creation_timestamp = timestamp };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "limit range clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}
