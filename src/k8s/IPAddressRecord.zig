const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const IPAddressRecord = @This();

key: keys.ObjectKey,
parent: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromIPAddress(allocator: std.mem.Allocator, value: klient.IPAddress) !IPAddressRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{ .uid = uid, .namespace = "", .name = value.metadata.name }).clone(allocator);
    errdefer key.deinit(allocator);
    const parent = try allocator.dupe(u8, parentName(value));
    errdefer allocator.free(parent);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .parent = parent, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: IPAddressRecord, allocator: std.mem.Allocator) !IPAddressRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const parent = try allocator.dupe(u8, self.parent);
    errdefer allocator.free(parent);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .parent = parent, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *IPAddressRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.parent);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const IPAddressRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    var result: [3][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.parent);
    initialized += 1;
    result[2] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn parentName(value: klient.IPAddress) []const u8 {
    const spec = value.spec orelse return "<none>";
    if (spec.parentRef != .object) return "<none>";
    const name = spec.parentRef.object.get("name") orelse return "<none>";
    return if (name == .string) name.string else "<none>";
}

test "IP address columns preserve legacy transform parity" {
    var parsed = try std.json.parseFromSlice(
        klient.IPAddress,
        std.testing.allocator,
        \\{"metadata":{"uid":"ip-1","name":"10.0.0.8"},"spec":{"parentRef":{"name":"service-a"}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromIPAddress(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "10.0.0.8", "service-a", "n/a" };
    for (actual, expected) |got, want| try std.testing.expectEqualStrings(want, got);
}

test "UID-less IP address is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromIPAddress(std.testing.allocator, .{ .metadata = .{ .name = "10.0.0.8" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var parsed = try std.json.parseFromSlice(
        klient.IPAddress,
        allocator,
        \\{"metadata":{"uid":"ip-1","name":"10.0.0.8","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"parentRef":{"name":"service-a"}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var source = try fromIPAddress(allocator, parsed.value);
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "IP address clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
