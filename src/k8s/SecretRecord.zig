const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const SecretRecord = @This();

key: keys.ObjectKey,
secret_type: []u8,
data_count: usize,
data_sort_key: [20]u8 = [_]u8{'0'} ** 20,
creation_timestamp: ?[]u8 = null,

pub fn fromSecret(allocator: std.mem.Allocator, value: klient.Secret) !SecretRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "default");
    errdefer key.deinit(allocator);
    const secret_type = try allocator.dupe(u8, value.type orelse "Opaque");
    errdefer allocator.free(secret_type);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    return .{
        .key = key,
        .secret_type = secret_type,
        .data_count = objectCount(value.data),
        .data_sort_key = @import("ConfigMapRecord.zig").numericSortKey(objectCount(value.data)),
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: SecretRecord, allocator: std.mem.Allocator) !SecretRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const secret_type = try allocator.dupe(u8, self.secret_type);
    errdefer allocator.free(secret_type);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .secret_type = secret_type,
        .data_count = self.data_count,
        .data_sort_key = self.data_sort_key,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *SecretRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.secret_type);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const SecretRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    var result: [5][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try allocator.dupe(u8, self.secret_type);
    initialized += 1;
    result[3] = try std.fmt.allocPrint(allocator, "{d}", .{self.data_count});
    initialized += 1;
    result[4] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn objectCount(value: ?std.json.Value) usize {
    const actual = value orelse return 0;
    return if (actual == .object) actual.object.count() else 0;
}

test "secret record preserves legacy type and data columns" {
    var parsed = try std.json.parseFromSlice(
        klient.Secret,
        std.testing.allocator,
        \\{"metadata":{"uid":"secret-1","namespace":"team","name":"token"},"data":{"one":"MQ==","two":"Mg=="}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromSecret(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("Opaque", record.secret_type);
    try std.testing.expectEqual(@as(usize, 2), record.data_count);
    try std.testing.expectError(
        error.MissingUid,
        fromSecret(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "secret-1",
            .namespace = "team",
            .name = "token",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const secret_type = try allocator.dupe(u8, "Opaque");
        errdefer allocator.free(secret_type);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk SecretRecord{
            .key = key,
            .secret_type = secret_type,
            .data_count = 2,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "secret clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}
