const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const NamespaceRecord = @This();

key: keys.ObjectKey,
status: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromNamespace(allocator: std.mem.Allocator, namespace: klient.Namespace) !NamespaceRecord {
    var key = try keys.fromMetadata(allocator, namespace.metadata, "");
    errdefer key.deinit(allocator);
    const status = try allocator.dupe(u8, namespaceStatus(namespace));
    errdefer allocator.free(status);
    const creation_timestamp = if (namespace.metadata.creationTimestamp) |value|
        try allocator.dupe(u8, value)
    else
        null;
    return .{
        .key = key,
        .status = status,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: NamespaceRecord, allocator: std.mem.Allocator) !NamespaceRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const status = try allocator.dupe(u8, self.status);
    errdefer allocator.free(status);
    const creation_timestamp = if (self.creation_timestamp) |value|
        try allocator.dupe(u8, value)
    else
        null;
    return .{
        .key = key,
        .status = status,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *NamespaceRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.status);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn age(self: *const NamespaceRecord, allocator: std.mem.Allocator) ![]const u8 {
    return age_util.calculateAge(allocator, self.creation_timestamp);
}

fn namespaceStatus(namespace: klient.Namespace) []const u8 {
    const status = namespace.status orelse return "Unknown";
    if (status != .object) return "Active";
    const phase = status.object.get("phase") orelse return "Active";
    return if (phase == .string) phase.string else "Active";
}

test "namespace record owns compact display state" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(
        klient.Namespace,
        allocator,
        \\{"metadata":{"uid":"namespace-uid","name":"team-a","labels":{"environment":"production"},"creationTimestamp":"2024-01-01T00:00:00Z"},"status":{"phase":"Terminating"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromNamespace(allocator, parsed.value);
    defer record.deinit(allocator);
    try std.testing.expectEqualStrings("namespace-uid", record.key.uid);
    try std.testing.expectEqualStrings("environment=production", record.key.labels);
    try std.testing.expectEqualStrings("Terminating", record.status);
}

test "UID-less namespace is malformed" {
    const namespace = klient.Namespace{ .metadata = .{ .name = "team-a" } };
    try std.testing.expectError(
        error.MissingUid,
        fromNamespace(std.testing.allocator, namespace),
    );
}
