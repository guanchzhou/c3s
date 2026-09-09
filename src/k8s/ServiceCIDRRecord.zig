const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const ServiceCIDRRecord = @This();

key: keys.ObjectKey,
cidrs: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromServiceCIDR(allocator: std.mem.Allocator, value: klient.ServiceCIDR) !ServiceCIDRRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "");
    errdefer key.deinit(allocator);
    const cidrs = try formatCIDRs(allocator, value);
    errdefer allocator.free(cidrs);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .cidrs = cidrs, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: ServiceCIDRRecord, allocator: std.mem.Allocator) !ServiceCIDRRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const cidrs = try allocator.dupe(u8, self.cidrs);
    errdefer allocator.free(cidrs);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .cidrs = cidrs, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *ServiceCIDRRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.cidrs);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const ServiceCIDRRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    var result: [3][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.cidrs);
    initialized += 1;
    result[2] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn formatCIDRs(allocator: std.mem.Allocator, value: klient.ServiceCIDR) ![]u8 {
    const spec = value.spec orelse return allocator.dupe(u8, "<none>");
    const cidrs = spec.cidrs orelse return allocator.dupe(u8, "<none>");
    if (cidrs.len == 0) return allocator.dupe(u8, "<none>");
    var result: std.ArrayListUnmanaged(u8) = .empty;
    defer result.deinit(allocator);
    for (cidrs, 0..) |cidr, index| {
        if (index > 0) try result.append(allocator, ',');
        try result.appendSlice(allocator, cidr);
    }
    return result.toOwnedSlice(allocator);
}

test "service CIDR columns preserve legacy transform parity" {
    var parsed = try std.json.parseFromSlice(
        klient.ServiceCIDR,
        std.testing.allocator,
        \\{"metadata":{"uid":"cidr-1","name":"kubernetes"},"spec":{"cidrs":["10.96.0.0/12","fd00::/108"]}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromServiceCIDR(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "kubernetes", "10.96.0.0/12,fd00::/108", "n/a" };
    for (actual, expected) |got, want| try std.testing.expectEqualStrings(want, got);
}

test "UID-less service CIDR is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromServiceCIDR(std.testing.allocator, .{ .metadata = .{ .name = "kubernetes" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var parsed = try std.json.parseFromSlice(
        klient.ServiceCIDR,
        allocator,
        \\{"metadata":{"uid":"cidr-1","name":"kubernetes","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"cidrs":["10.96.0.0/12"]}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var source = try fromServiceCIDR(allocator, parsed.value);
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "service CIDR clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
