const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const PriorityClassRecord = @This();

key: keys.ObjectKey,
value: i32,
global_default: bool,
creation_timestamp: ?[]u8 = null,

pub fn fromPriorityClass(allocator: std.mem.Allocator, item: klient.PriorityClass) !PriorityClassRecord {
    var key = try keys.fromMetadata(allocator, item.metadata, "");
    errdefer key.deinit(allocator);
    const creation_timestamp = if (item.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    return .{
        .key = key,
        .value = item.value,
        .global_default = item.globalDefault orelse false,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: PriorityClassRecord, allocator: std.mem.Allocator) !PriorityClassRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .value = self.value,
        .global_default = self.global_default,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *PriorityClassRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const PriorityClassRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try std.fmt.allocPrint(allocator, "{d}", .{self.value});
    initialized += 1;
    result[2] = try allocator.dupe(u8, if (self.global_default) "true" else "false");
    initialized += 1;
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "priority class columns match current transform and UID is required" {
    var record = try fromPriorityClass(std.testing.allocator, .{
        .metadata = .{ .uid = "priority-1", .name = "critical" },
        .value = 1000,
        .globalDefault = true,
    });
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "critical", "1000", "true", "n/a" };
    for (actual, expected) |column, want| try std.testing.expectEqualStrings(want, column);
    try std.testing.expectError(
        error.MissingUid,
        fromPriorityClass(std.testing.allocator, .{ .metadata = .{ .name = "bad" }, .value = 0 }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "priority-1", .namespace = "", .name = "critical" }).clone(allocator);
        errdefer key.deinit(allocator);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk PriorityClassRecord{
            .key = key,
            .value = 1000,
            .global_default = true,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "priority class clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
