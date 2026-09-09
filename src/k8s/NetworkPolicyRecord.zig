const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const NetworkPolicyRecord = @This();

key: keys.ObjectKey,
pod_selector: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromNetworkPolicy(allocator: std.mem.Allocator, value: klient.NetworkPolicy) !NetworkPolicyRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "default");
    errdefer key.deinit(allocator);
    const selector = try formatMatchLabels(
        allocator,
        if (value.spec) |spec| spec.podSelector else null,
    );
    errdefer allocator.free(selector);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .pod_selector = selector, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: NetworkPolicyRecord, allocator: std.mem.Allocator) !NetworkPolicyRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const selector = try allocator.dupe(u8, self.pod_selector);
    errdefer allocator.free(selector);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .pod_selector = selector, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *NetworkPolicyRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.pod_selector);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const NetworkPolicyRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    inline for (.{ self.key.namespace, self.key.name, self.pod_selector }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn formatMatchLabels(allocator: std.mem.Allocator, selector: ?std.json.Value) ![]u8 {
    const value = selector orelse return allocator.dupe(u8, "<none>");
    if (value != .object) return allocator.dupe(u8, "<none>");
    const labels = value.object.get("matchLabels") orelse return allocator.dupe(u8, "<none>");
    if (labels != .object or labels.object.count() == 0) return allocator.dupe(u8, "<none>");
    var result: std.ArrayListUnmanaged(u8) = .empty;
    defer result.deinit(allocator);
    var entries = labels.object.iterator();
    var first = true;
    while (entries.next()) |entry| {
        if (!first) try result.append(allocator, ',');
        first = false;
        try result.appendSlice(allocator, entry.key_ptr.*);
        try result.append(allocator, '=');
        if (entry.value_ptr.* == .string) try result.appendSlice(allocator, entry.value_ptr.*.string);
    }
    return result.toOwnedSlice(allocator);
}

test "network policy columns preserve legacy transform parity" {
    var parsed = try std.json.parseFromSlice(
        klient.NetworkPolicy,
        std.testing.allocator,
        \\{"metadata":{"uid":"np-1","namespace":"team","name":"allow-web"},"spec":{"podSelector":{"matchLabels":{"app":"web"}}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromNetworkPolicy(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "team", "allow-web", "app=web", "n/a" };
    for (actual, expected) |got, want| try std.testing.expectEqualStrings(want, got);
}

test "UID-less network policy is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromNetworkPolicy(std.testing.allocator, .{ .metadata = .{ .name = "allow-web" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var parsed = try std.json.parseFromSlice(
        klient.NetworkPolicy,
        allocator,
        \\{"metadata":{"uid":"np-1","namespace":"team","name":"allow-web","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"podSelector":{"matchLabels":{"app":"web"}}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var source = try fromNetworkPolicy(allocator, parsed.value);
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "network policy clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
