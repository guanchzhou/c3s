const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const DeviceClassRecord = @This();

key: keys.ObjectKey,
selector_count: usize,
creation_timestamp: ?[]u8 = null,

pub fn fromDeviceClass(allocator: std.mem.Allocator, value: klient.DeviceClass) !DeviceClassRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "");
    errdefer key.deinit(allocator);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    return .{
        .key = key,
        .selector_count = if (value.spec) |spec| if (spec.selectors) |selectors| selectors.len else 0 else 0,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: DeviceClassRecord, allocator: std.mem.Allocator) !DeviceClassRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .selector_count = self.selector_count, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *DeviceClassRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const DeviceClassRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    var result: [3][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try std.fmt.allocPrint(allocator, "{d}", .{self.selector_count});
    initialized += 1;
    result[2] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "device class columns match current transform and UID is required" {
    var parsed = try std.json.parseFromSlice(
        klient.DeviceClass,
        std.testing.allocator,
        \\{"metadata":{"uid":"class-1","name":"gpu"},"spec":{"selectors":[{},{}]}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromDeviceClass(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "gpu", "2", "n/a" };
    for (actual, expected) |column, want| try std.testing.expectEqualStrings(want, column);
    try std.testing.expectError(
        error.MissingUid,
        fromDeviceClass(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "class-1", .namespace = "", .name = "gpu" }).clone(allocator);
        errdefer key.deinit(allocator);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk DeviceClassRecord{ .key = key, .selector_count = 2, .creation_timestamp = timestamp };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "device class clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
