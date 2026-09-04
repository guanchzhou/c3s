const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const PVRecord = @This();

key: keys.ObjectKey,
capacity: []u8,
capacity_sort_key: [32]u8,
access: []u8,
reclaim: []u8,
status: []u8,
claim: []u8,
storage_class: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromPersistentVolume(allocator: std.mem.Allocator, value: klient.PersistentVolume) !PVRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = "",
        .name = value.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const capacity = try allocator.dupe(u8, capacityValue(value));
    errdefer allocator.free(capacity);
    const access = try accessModes(allocator, if (value.spec) |spec| spec.accessModes else null);
    errdefer allocator.free(access);
    const reclaim = try allocator.dupe(u8, if (value.spec) |spec| spec.persistentVolumeReclaimPolicy orelse "<none>" else "<none>");
    errdefer allocator.free(reclaim);
    const status = try allocator.dupe(u8, jsonString(value.status, "phase") orelse "<unknown>");
    errdefer allocator.free(status);
    const claim = try claimValue(allocator, value);
    errdefer allocator.free(claim);
    const storage_class = try allocator.dupe(u8, if (value.spec) |spec| spec.storageClassName orelse "<none>" else "<none>");
    errdefer allocator.free(storage_class);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .capacity = capacity,
        .capacity_sort_key = capacitySortKey(capacity),
        .access = access,
        .reclaim = reclaim,
        .status = status,
        .claim = claim,
        .storage_class = storage_class,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: PVRecord, allocator: std.mem.Allocator) !PVRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const capacity = try allocator.dupe(u8, self.capacity);
    errdefer allocator.free(capacity);
    const access = try allocator.dupe(u8, self.access);
    errdefer allocator.free(access);
    const reclaim = try allocator.dupe(u8, self.reclaim);
    errdefer allocator.free(reclaim);
    const status = try allocator.dupe(u8, self.status);
    errdefer allocator.free(status);
    const claim = try allocator.dupe(u8, self.claim);
    errdefer allocator.free(claim);
    const storage_class = try allocator.dupe(u8, self.storage_class);
    errdefer allocator.free(storage_class);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .capacity = capacity,
        .capacity_sort_key = self.capacity_sort_key,
        .access = access,
        .reclaim = reclaim,
        .status = status,
        .claim = claim,
        .storage_class = storage_class,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *PVRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.capacity);
    allocator.free(self.access);
    allocator.free(self.reclaim);
    allocator.free(self.status);
    allocator.free(self.claim);
    allocator.free(self.storage_class);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const PVRecord, allocator: std.mem.Allocator) ![8][]const u8 {
    var result: [8][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    inline for (.{ self.key.name, self.capacity, self.access, self.reclaim, self.status, self.claim, self.storage_class }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[7] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

pub fn accessModes(allocator: std.mem.Allocator, modes: ?[][]const u8) ![]u8 {
    const values = modes orelse return allocator.dupe(u8, "<none>");
    if (values.len == 0) return allocator.dupe(u8, "<none>");
    var result: std.ArrayListUnmanaged(u8) = .empty;
    defer result.deinit(allocator);
    for (values, 0..) |mode, index| {
        if (index > 0) try result.append(allocator, ',');
        try result.appendSlice(allocator, abbreviateAccessMode(mode));
    }
    return result.toOwnedSlice(allocator);
}

pub fn jsonString(value: ?std.json.Value, field: []const u8) ?[]const u8 {
    const object = value orelse return null;
    if (object != .object) return null;
    const member = object.object.get(field) orelse return null;
    return if (member == .string) member.string else null;
}

fn capacityValue(value: klient.PersistentVolume) []const u8 {
    const spec = value.spec orelse return "<unknown>";
    const capacity = spec.capacity orelse return "<unknown>";
    return jsonString(capacity, "storage") orelse "<unknown>";
}

fn claimValue(allocator: std.mem.Allocator, value: klient.PersistentVolume) ![]u8 {
    const spec = value.spec orelse return allocator.dupe(u8, "<none>");
    const reference = spec.claimRef orelse return allocator.dupe(u8, "<none>");
    const name = reference.name orelse return allocator.dupe(u8, "<none>");
    if (reference.namespace) |namespace| {
        return std.fmt.allocPrint(allocator, "{s}/{s}", .{ namespace, name });
    }
    return allocator.dupe(u8, name);
}

fn abbreviateAccessMode(mode: []const u8) []const u8 {
    if (std.mem.eql(u8, mode, "ReadWriteOnce")) return "RWO";
    if (std.mem.eql(u8, mode, "ReadOnlyMany")) return "ROX";
    if (std.mem.eql(u8, mode, "ReadWriteMany")) return "RWX";
    if (std.mem.eql(u8, mode, "ReadWriteOncePod")) return "RWOP";
    return mode;
}

pub fn capacitySortKey(value: []const u8) [32]u8 {
    var result = [_]u8{'0'} ** 32;
    var digits: usize = 0;
    while (digits < value.len and std.ascii.isDigit(value[digits])) : (digits += 1) {}
    const copy_len = @min(digits, result.len);
    @memcpy(result[result.len - copy_len ..], value[digits - copy_len .. digits]);
    return result;
}

test "PV columns preserve legacy transform parity" {
    var parsed = try std.json.parseFromSlice(
        klient.PersistentVolume,
        std.testing.allocator,
        \\{"metadata":{"uid":"pv-1","name":"data"},"spec":{"capacity":{"storage":"10Gi"},"accessModes":["ReadWriteOnce","ReadOnlyMany"],"persistentVolumeReclaimPolicy":"Retain","claimRef":{"namespace":"team","name":"cache"},"storageClassName":"fast"},"status":{"phase":"Bound"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromPersistentVolume(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "data", "10Gi", "RWO,ROX", "Retain", "Bound", "team/cache", "fast", "n/a" };
    inline for (expected, 0..) |column, index| try std.testing.expectEqualStrings(column, actual[index]);
}

test "UID-less PV is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromPersistentVolume(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var parsed = try std.json.parseFromSlice(
        klient.PersistentVolume,
        allocator,
        \\{"metadata":{"uid":"pv-1","name":"data"},"spec":{"capacity":{"storage":"10Gi"},"accessModes":["ReadWriteOnce"],"persistentVolumeReclaimPolicy":"Retain","claimRef":{"namespace":"team","name":"cache"},"storageClassName":"fast"},"status":{"phase":"Bound"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var source = try fromPersistentVolume(allocator, parsed.value);
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "PV clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}

test "capacity sort key orders 2Gi before 10Gi" {
    try std.testing.expect(std.mem.order(
        u8,
        &capacitySortKey("2Gi"),
        &capacitySortKey("10Gi"),
    ) == .lt);
}
