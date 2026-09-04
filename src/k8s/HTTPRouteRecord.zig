const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");
const support = @import("GatewayRecordSupport.zig");

pub const HTTPRouteRecord = @This();

key: keys.ObjectKey,
parent: []u8,
hostnames: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromHTTPRoute(allocator: std.mem.Allocator, value: klient.HTTPRoute) !HTTPRouteRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = value.metadata.namespace orelse "default",
        .name = value.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const parent = try support.firstObjectString(
        allocator,
        if (value.spec) |spec| spec.parentRefs else null,
        "name",
    );
    errdefer allocator.free(parent);
    const hostnames = try support.joinStrings(
        allocator,
        if (value.spec) |spec| spec.hostnames else null,
    );
    errdefer allocator.free(hostnames);
    const creation_timestamp = try support.dupeTimestamp(allocator, value.metadata.creationTimestamp);
    return .{ .key = key, .parent = parent, .hostnames = hostnames, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: HTTPRouteRecord, allocator: std.mem.Allocator) !HTTPRouteRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const parent = try allocator.dupe(u8, self.parent);
    errdefer allocator.free(parent);
    const hostnames = try allocator.dupe(u8, self.hostnames);
    errdefer allocator.free(hostnames);
    const creation_timestamp = try support.dupeTimestamp(allocator, self.creation_timestamp);
    return .{ .key = key, .parent = parent, .hostnames = hostnames, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *HTTPRouteRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.parent);
    allocator.free(self.hostnames);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const HTTPRouteRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    var result: [5][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer support.freeColumns(allocator, result[0..initialized]);
    inline for (.{ self.key.namespace, self.key.name, self.parent, self.hostnames }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[4] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}
