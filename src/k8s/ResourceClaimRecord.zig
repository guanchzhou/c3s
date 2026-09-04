const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const ResourceClaimRecord = @This();

key: keys.ObjectKey,
status: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromResourceClaim(allocator: std.mem.Allocator, value: klient.ResourceClaim) !ResourceClaimRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = value.metadata.namespace orelse "default",
        .name = value.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const status = try allocator.dupe(u8, allocationStatus(value.status));
    errdefer allocator.free(status);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    return .{ .key = key, .status = status, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: ResourceClaimRecord, allocator: std.mem.Allocator) !ResourceClaimRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const status = try allocator.dupe(u8, self.status);
    errdefer allocator.free(status);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .status = status, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *ResourceClaimRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.status);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const ResourceClaimRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try allocator.dupe(u8, self.status);
    initialized += 1;
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn allocationStatus(status: ?std.json.Value) []const u8 {
    const actual = status orelse return "pending";
    if (actual != .object) return "pending";
    return if (actual.object.get("allocation") != null) "bound" else "pending";
}

test "resource claim columns match current transform and UID is required" {
    var parsed = try std.json.parseFromSlice(
        klient.ResourceClaim,
        std.testing.allocator,
        \\{"metadata":{"uid":"claim-1","namespace":"team","name":"gpu"},"spec":{},"status":{"allocation":{}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromResourceClaim(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "team", "gpu", "bound", "n/a" };
    for (actual, expected) |column, want| try std.testing.expectEqualStrings(want, column);
    try std.testing.expectError(
        error.MissingUid,
        fromResourceClaim(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "claim-1", .namespace = "team", .name = "gpu" }).clone(allocator);
        errdefer key.deinit(allocator);
        const status = try allocator.dupe(u8, "bound");
        errdefer allocator.free(status);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk ResourceClaimRecord{ .key = key, .status = status, .creation_timestamp = timestamp };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "resource claim clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
