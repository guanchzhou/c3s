const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const ServiceAccountRecord = @This();

key: keys.ObjectKey,
secret_count: usize,
secret_sort_key: [20]u8 = [_]u8{'0'} ** 20,
creation_timestamp: ?[]u8 = null,

pub fn fromServiceAccount(allocator: std.mem.Allocator, value: klient.ServiceAccount) !ServiceAccountRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "default");
    errdefer key.deinit(allocator);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    return .{
        .key = key,
        .secret_count = if (value.secrets) |secrets| secrets.len else 0,
        .secret_sort_key = @import("ConfigMapRecord.zig").numericSortKey(
            if (value.secrets) |secrets| secrets.len else 0,
        ),
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: ServiceAccountRecord, allocator: std.mem.Allocator) !ServiceAccountRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .secret_count = self.secret_count,
        .secret_sort_key = self.secret_sort_key,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *ServiceAccountRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const ServiceAccountRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try std.fmt.allocPrint(allocator, "{d}", .{self.secret_count});
    initialized += 1;
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "service account record preserves secret count and rejects missing UID" {
    var parsed = try std.json.parseFromSlice(
        klient.ServiceAccount,
        std.testing.allocator,
        \\{"metadata":{"uid":"sa-1","namespace":"team","name":"builder"},"secrets":[{"name":"one"},{"name":"two"}]}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromServiceAccount(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), record.secret_count);
    try std.testing.expectError(
        error.MissingUid,
        fromServiceAccount(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "sa-1",
            .namespace = "team",
            .name = "builder",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk ServiceAccountRecord{
            .key = key,
            .secret_count = 2,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "service account clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}
