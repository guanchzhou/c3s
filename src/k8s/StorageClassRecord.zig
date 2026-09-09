const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const StorageClassRecord = @This();

key: keys.ObjectKey,
provisioner: []u8,
reclaim_policy: []u8,
bind_mode: []u8,
expansion: bool,
creation_timestamp: ?[]u8 = null,

pub fn fromStorageClass(allocator: std.mem.Allocator, value: klient.StorageClass) !StorageClassRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "");
    errdefer key.deinit(allocator);
    const provisioner = try allocator.dupe(u8, value.provisioner);
    errdefer allocator.free(provisioner);
    const reclaim_policy = try allocator.dupe(u8, value.reclaimPolicy orelse "Delete");
    errdefer allocator.free(reclaim_policy);
    const bind_mode = try allocator.dupe(u8, value.volumeBindingMode orelse "Immediate");
    errdefer allocator.free(bind_mode);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .provisioner = provisioner,
        .reclaim_policy = reclaim_policy,
        .bind_mode = bind_mode,
        .expansion = value.allowVolumeExpansion orelse false,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: StorageClassRecord, allocator: std.mem.Allocator) !StorageClassRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const provisioner = try allocator.dupe(u8, self.provisioner);
    errdefer allocator.free(provisioner);
    const reclaim_policy = try allocator.dupe(u8, self.reclaim_policy);
    errdefer allocator.free(reclaim_policy);
    const bind_mode = try allocator.dupe(u8, self.bind_mode);
    errdefer allocator.free(bind_mode);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .provisioner = provisioner,
        .reclaim_policy = reclaim_policy,
        .bind_mode = bind_mode,
        .expansion = self.expansion,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *StorageClassRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.provisioner);
    allocator.free(self.reclaim_policy);
    allocator.free(self.bind_mode);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const StorageClassRecord, allocator: std.mem.Allocator) ![6][]const u8 {
    var result: [6][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    inline for (.{ self.key.name, self.provisioner, self.reclaim_policy, self.bind_mode }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[4] = try allocator.dupe(u8, if (self.expansion) "true" else "false");
    initialized += 1;
    result[5] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "storage class columns preserve legacy transform parity" {
    var parsed = try std.json.parseFromSlice(
        klient.StorageClass,
        std.testing.allocator,
        \\{"metadata":{"uid":"sc-1","name":"fast"},"provisioner":"csi.example","reclaimPolicy":"Retain","volumeBindingMode":"WaitForFirstConsumer","allowVolumeExpansion":true}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromStorageClass(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "fast", "csi.example", "Retain", "WaitForFirstConsumer", "true", "n/a" };
    inline for (expected, 0..) |column, index| try std.testing.expectEqualStrings(column, actual[index]);
}

test "UID-less storage class is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromStorageClass(std.testing.allocator, .{ .metadata = .{ .name = "bad" }, .provisioner = "csi.example" }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var parsed = try std.json.parseFromSlice(
        klient.StorageClass,
        allocator,
        \\{"metadata":{"uid":"sc-1","name":"fast"},"provisioner":"csi.example","reclaimPolicy":"Retain","volumeBindingMode":"WaitForFirstConsumer","allowVolumeExpansion":true}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var source = try fromStorageClass(allocator, parsed.value);
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "storage class clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
