const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");
const pv_record = @import("PVRecord.zig");

pub const PVCRecord = @This();

key: keys.ObjectKey,
status: []u8,
volume: []u8,
capacity: []u8,
capacity_sort_key: [32]u8,
access: []u8,
storage_class: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromPersistentVolumeClaim(allocator: std.mem.Allocator, value: klient.PersistentVolumeClaim) !PVCRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = value.metadata.namespace orelse "default",
        .name = value.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const status = try allocator.dupe(u8, pv_record.jsonString(value.status, "phase") orelse "<unknown>");
    errdefer allocator.free(status);
    const volume = try allocator.dupe(u8, if (value.spec) |spec| spec.volumeName orelse "" else "");
    errdefer allocator.free(volume);
    const capacity = try allocator.dupe(u8, boundCapacity(value));
    errdefer allocator.free(capacity);
    const access = try pv_record.accessModes(allocator, if (value.spec) |spec| spec.accessModes else null);
    errdefer allocator.free(access);
    const storage_class = try allocator.dupe(u8, if (value.spec) |spec| spec.storageClassName orelse "<none>" else "<none>");
    errdefer allocator.free(storage_class);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .status = status,
        .volume = volume,
        .capacity = capacity,
        .capacity_sort_key = pv_record.capacitySortKey(capacity),
        .access = access,
        .storage_class = storage_class,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: PVCRecord, allocator: std.mem.Allocator) !PVCRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const status = try allocator.dupe(u8, self.status);
    errdefer allocator.free(status);
    const volume = try allocator.dupe(u8, self.volume);
    errdefer allocator.free(volume);
    const capacity = try allocator.dupe(u8, self.capacity);
    errdefer allocator.free(capacity);
    const access = try allocator.dupe(u8, self.access);
    errdefer allocator.free(access);
    const storage_class = try allocator.dupe(u8, self.storage_class);
    errdefer allocator.free(storage_class);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .status = status,
        .volume = volume,
        .capacity = capacity,
        .capacity_sort_key = self.capacity_sort_key,
        .access = access,
        .storage_class = storage_class,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *PVCRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.status);
    allocator.free(self.volume);
    allocator.free(self.capacity);
    allocator.free(self.access);
    allocator.free(self.storage_class);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const PVCRecord, allocator: std.mem.Allocator) ![8][]const u8 {
    var result: [8][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    inline for (.{ self.key.namespace, self.key.name, self.status, self.volume, self.capacity, self.access, self.storage_class }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[7] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn boundCapacity(value: klient.PersistentVolumeClaim) []const u8 {
    const status = value.status orelse return "<none>";
    if (status != .object) return "<none>";
    const capacity = status.object.get("capacity") orelse return "<none>";
    return pv_record.jsonString(capacity, "storage") orelse "<none>";
}

test "PVC columns preserve legacy transform parity" {
    var parsed = try std.json.parseFromSlice(
        klient.PersistentVolumeClaim,
        std.testing.allocator,
        \\{"metadata":{"uid":"pvc-1","namespace":"team","name":"cache"},"spec":{"volumeName":"pv-1","accessModes":["ReadWriteMany"],"storageClassName":"fast"},"status":{"phase":"Bound","capacity":{"storage":"20Gi"}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromPersistentVolumeClaim(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "team", "cache", "Bound", "pv-1", "20Gi", "RWX", "fast", "n/a" };
    inline for (expected, 0..) |column, index| try std.testing.expectEqualStrings(column, actual[index]);
}

test "UID-less PVC is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromPersistentVolumeClaim(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var parsed = try std.json.parseFromSlice(
        klient.PersistentVolumeClaim,
        allocator,
        \\{"metadata":{"uid":"pvc-1","namespace":"team","name":"cache"},"spec":{"volumeName":"pv-1","accessModes":["ReadWriteMany"],"storageClassName":"fast"},"status":{"phase":"Bound","capacity":{"storage":"20Gi"}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var source = try fromPersistentVolumeClaim(allocator, parsed.value);
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "PVC clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
