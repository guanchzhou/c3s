const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");
const support = @import("GatewayRecordSupport.zig");

pub const TCPRouteRecord = @This();

key: keys.ObjectKey,
parent: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromTCPRoute(allocator: std.mem.Allocator, value: klient.TCPRoute) !TCPRouteRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "default");
    errdefer key.deinit(allocator);
    const parent = try support.firstObjectString(
        allocator,
        if (value.spec) |spec| spec.parentRefs else null,
        "name",
    );
    errdefer allocator.free(parent);
    const creation_timestamp = try support.dupeTimestamp(allocator, value.metadata.creationTimestamp);
    return .{ .key = key, .parent = parent, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: TCPRouteRecord, allocator: std.mem.Allocator) !TCPRouteRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const parent = try allocator.dupe(u8, self.parent);
    errdefer allocator.free(parent);
    const creation_timestamp = try support.dupeTimestamp(allocator, self.creation_timestamp);
    return .{ .key = key, .parent = parent, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *TCPRouteRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.parent);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const TCPRouteRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer support.freeColumns(allocator, result[0..initialized]);
    inline for (.{ self.key.namespace, self.key.name, self.parent }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}
