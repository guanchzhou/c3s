const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const RuntimeClassRecord = @This();

key: keys.ObjectKey,
handler: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromRuntimeClass(allocator: std.mem.Allocator, item: klient.RuntimeClass) !RuntimeClassRecord {
    const uid = item.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = item.metadata.namespace orelse "",
        .name = item.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const handler = try allocator.dupe(u8, item.handler);
    errdefer allocator.free(handler);
    const creation_timestamp = if (item.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    return .{ .key = key, .handler = handler, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: RuntimeClassRecord, allocator: std.mem.Allocator) !RuntimeClassRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const handler = try allocator.dupe(u8, self.handler);
    errdefer allocator.free(handler);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .handler = handler, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *RuntimeClassRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.handler);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const RuntimeClassRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    var result: [3][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.handler);
    initialized += 1;
    result[2] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "runtime class columns match current transform and UID is required" {
    var record = try fromRuntimeClass(std.testing.allocator, .{
        .metadata = .{ .uid = "runtime-1", .name = "sandboxed" },
        .handler = "runsc",
    });
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "sandboxed", "runsc", "n/a" };
    for (actual, expected) |column, want| try std.testing.expectEqualStrings(want, column);
    try std.testing.expectError(
        error.MissingUid,
        fromRuntimeClass(std.testing.allocator, .{ .metadata = .{ .name = "bad" }, .handler = "runc" }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "runtime-1", .namespace = "", .name = "sandboxed" }).clone(allocator);
        errdefer key.deinit(allocator);
        const handler = try allocator.dupe(u8, "runsc");
        errdefer allocator.free(handler);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk RuntimeClassRecord{ .key = key, .handler = handler, .creation_timestamp = timestamp };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "runtime class clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
