const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const StorageVersionMigrationRecord = @This();

key: keys.ObjectKey,
resource_version: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromStorageVersionMigration(
    allocator: std.mem.Allocator,
    item: klient.StorageVersionMigration,
) !StorageVersionMigrationRecord {
    var key = try keys.fromMetadata(allocator, item.metadata, "");
    errdefer key.deinit(allocator);
    const resource_version = try allocator.dupe(u8, jsonStringField(item.status, "resourceVersion") orelse "<none>");
    errdefer allocator.free(resource_version);
    const creation_timestamp = if (item.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    return .{ .key = key, .resource_version = resource_version, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: StorageVersionMigrationRecord, allocator: std.mem.Allocator) !StorageVersionMigrationRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const resource_version = try allocator.dupe(u8, self.resource_version);
    errdefer allocator.free(resource_version);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .resource_version = resource_version, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *StorageVersionMigrationRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.resource_version);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const StorageVersionMigrationRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    var result: [3][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.resource_version);
    initialized += 1;
    result[2] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn jsonStringField(value: ?std.json.Value, field: []const u8) ?[]const u8 {
    const actual = value orelse return null;
    if (actual != .object) return null;
    const member = actual.object.get(field) orelse return null;
    return if (member == .string) member.string else null;
}

test "storage version migration columns match current transform and UID is required" {
    var parsed = try std.json.parseFromSlice(
        klient.StorageVersionMigration,
        std.testing.allocator,
        \\{"metadata":{"uid":"svm-1","name":"pods"},"spec":{"resource":{"resource":"pods"}},"status":{"resourceVersion":"42"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromStorageVersionMigration(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "pods", "42", "n/a" };
    for (actual, expected) |column, want| try std.testing.expectEqualStrings(want, column);

    var missing_uid = try std.json.parseFromSlice(
        klient.StorageVersionMigration,
        std.testing.allocator,
        \\{"metadata":{"name":"bad"},"spec":{"resource":{}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer missing_uid.deinit();
    try std.testing.expectError(error.MissingUid, fromStorageVersionMigration(std.testing.allocator, missing_uid.value));
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "svm-1", .namespace = "", .name = "pods" }).clone(allocator);
        errdefer key.deinit(allocator);
        const resource_version = try allocator.dupe(u8, "42");
        errdefer allocator.free(resource_version);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk StorageVersionMigrationRecord{
            .key = key,
            .resource_version = resource_version,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "storage version migration clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
