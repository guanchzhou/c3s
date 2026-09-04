const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");
const support = @import("GatewayRecordSupport.zig");

pub const ListenerSetRecord = @This();

key: keys.ObjectKey,
parent: []u8,
listener_count: usize,
creation_timestamp: ?[]u8 = null,

pub fn fromListenerSet(allocator: std.mem.Allocator, value: klient.ListenerSet) !ListenerSetRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = value.metadata.namespace orelse "default",
        .name = value.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const parent = try support.objectString(
        allocator,
        if (value.spec) |spec| spec.parentRef else null,
        "name",
    );
    errdefer allocator.free(parent);
    const creation_timestamp = try support.dupeTimestamp(allocator, value.metadata.creationTimestamp);
    return .{
        .key = key,
        .parent = parent,
        .listener_count = if (value.spec) |spec|
            if (spec.listeners) |listeners| listeners.len else 0
        else
            0,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: ListenerSetRecord, allocator: std.mem.Allocator) !ListenerSetRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const parent = try allocator.dupe(u8, self.parent);
    errdefer allocator.free(parent);
    const creation_timestamp = try support.dupeTimestamp(allocator, self.creation_timestamp);
    return .{
        .key = key,
        .parent = parent,
        .listener_count = self.listener_count,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *ListenerSetRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.parent);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const ListenerSetRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    var result: [5][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer support.freeColumns(allocator, result[0..initialized]);
    inline for (.{ self.key.namespace, self.key.name, self.parent }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[3] = try std.fmt.allocPrint(allocator, "{d}", .{self.listener_count});
    initialized += 1;
    result[4] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}
