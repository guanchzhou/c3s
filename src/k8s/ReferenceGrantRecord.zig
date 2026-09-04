const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");
const support = @import("GatewayRecordSupport.zig");

pub const ReferenceGrantRecord = @This();

key: keys.ObjectKey,
from_kind: []u8,
to_kind: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromReferenceGrant(allocator: std.mem.Allocator, value: klient.ReferenceGrant) !ReferenceGrantRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = value.metadata.namespace orelse "default",
        .name = value.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const from_kind = try support.firstObjectString(
        allocator,
        if (value.spec) |spec| spec.from else null,
        "kind",
    );
    errdefer allocator.free(from_kind);
    const to_kind = try support.firstObjectString(
        allocator,
        if (value.spec) |spec| spec.to else null,
        "kind",
    );
    errdefer allocator.free(to_kind);
    const creation_timestamp = try support.dupeTimestamp(allocator, value.metadata.creationTimestamp);
    return .{
        .key = key,
        .from_kind = from_kind,
        .to_kind = to_kind,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: ReferenceGrantRecord, allocator: std.mem.Allocator) !ReferenceGrantRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const from_kind = try allocator.dupe(u8, self.from_kind);
    errdefer allocator.free(from_kind);
    const to_kind = try allocator.dupe(u8, self.to_kind);
    errdefer allocator.free(to_kind);
    const creation_timestamp = try support.dupeTimestamp(allocator, self.creation_timestamp);
    return .{
        .key = key,
        .from_kind = from_kind,
        .to_kind = to_kind,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *ReferenceGrantRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.from_kind);
    allocator.free(self.to_kind);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const ReferenceGrantRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    var result: [5][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer support.freeColumns(allocator, result[0..initialized]);
    inline for (.{ self.key.namespace, self.key.name, self.from_kind, self.to_kind }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[4] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}
