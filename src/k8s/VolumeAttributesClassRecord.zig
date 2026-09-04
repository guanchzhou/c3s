const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const VolumeAttributesClassRecord = @This();

key: keys.ObjectKey,
driver: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromVolumeAttributesClass(allocator: std.mem.Allocator, value: klient.VolumeAttributesClass) !VolumeAttributesClassRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{ .uid = uid, .namespace = "", .name = value.metadata.name }).clone(allocator);
    errdefer key.deinit(allocator);
    const driver = try allocator.dupe(u8, value.driverName);
    errdefer allocator.free(driver);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .driver = driver, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: VolumeAttributesClassRecord, allocator: std.mem.Allocator) !VolumeAttributesClassRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const driver = try allocator.dupe(u8, self.driver);
    errdefer allocator.free(driver);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .driver = driver, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *VolumeAttributesClassRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.driver);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const VolumeAttributesClassRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    var result: [3][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.driver);
    initialized += 1;
    result[2] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "volume attributes class columns preserve legacy transform parity" {
    var parsed = try std.json.parseFromSlice(
        klient.VolumeAttributesClass,
        std.testing.allocator,
        \\{"metadata":{"uid":"vac-1","name":"gold"},"driverName":"csi.example"}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromVolumeAttributesClass(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "gold", "csi.example", "n/a" };
    inline for (expected, 0..) |column, index| try std.testing.expectEqualStrings(column, actual[index]);
}

test "UID-less volume attributes class is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromVolumeAttributesClass(std.testing.allocator, .{
            .metadata = .{ .name = "bad" },
            .driverName = "csi.example",
        }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var parsed = try std.json.parseFromSlice(
        klient.VolumeAttributesClass,
        allocator,
        \\{"metadata":{"uid":"vac-1","name":"gold"},"driverName":"csi.example"}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var source = try fromVolumeAttributesClass(allocator, parsed.value);
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "volume attributes class clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
