const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const LeaseRecord = @This();

key: keys.ObjectKey,
holder: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromLease(allocator: std.mem.Allocator, item: klient.Lease) !LeaseRecord {
    var key = try keys.fromMetadata(allocator, item.metadata, "default");
    errdefer key.deinit(allocator);
    const holder = try allocator.dupe(u8, if (item.spec) |spec| spec.holderIdentity orelse "<none>" else "<none>");
    errdefer allocator.free(holder);
    const creation_timestamp = if (item.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    return .{ .key = key, .holder = holder, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: LeaseRecord, allocator: std.mem.Allocator) !LeaseRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const holder = try allocator.dupe(u8, self.holder);
    errdefer allocator.free(holder);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .holder = holder, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *LeaseRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.holder);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const LeaseRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try allocator.dupe(u8, self.holder);
    initialized += 1;
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "lease columns match current transform and UID is required" {
    var record = try fromLease(std.testing.allocator, .{
        .metadata = .{ .uid = "lease-1", .namespace = "kube-system", .name = "leader" },
        .spec = .{ .holderIdentity = "controller-a" },
    });
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "kube-system", "leader", "controller-a", "n/a" };
    for (actual, expected) |column, want| try std.testing.expectEqualStrings(want, column);
    try std.testing.expectError(
        error.MissingUid,
        fromLease(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "lease-1", .namespace = "kube-system", .name = "leader" }).clone(allocator);
        errdefer key.deinit(allocator);
        const holder = try allocator.dupe(u8, "controller-a");
        errdefer allocator.free(holder);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk LeaseRecord{ .key = key, .holder = holder, .creation_timestamp = timestamp };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "lease clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
