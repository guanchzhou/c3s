const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");
const support = @import("GatewayRecordSupport.zig");

pub const GatewayClassRecord = @This();

key: keys.ObjectKey,
controller: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromGatewayClass(allocator: std.mem.Allocator, value: klient.GatewayClass) !GatewayClassRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "");
    errdefer key.deinit(allocator);
    const controller = try support.dupeOrNone(
        allocator,
        if (value.spec) |spec| spec.controllerName else null,
    );
    errdefer allocator.free(controller);
    const creation_timestamp = try support.dupeTimestamp(allocator, value.metadata.creationTimestamp);
    return .{ .key = key, .controller = controller, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: GatewayClassRecord, allocator: std.mem.Allocator) !GatewayClassRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const controller = try allocator.dupe(u8, self.controller);
    errdefer allocator.free(controller);
    const creation_timestamp = try support.dupeTimestamp(allocator, self.creation_timestamp);
    return .{ .key = key, .controller = controller, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *GatewayClassRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.controller);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const GatewayClassRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    var result: [3][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer support.freeColumns(allocator, result[0..initialized]);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.controller);
    initialized += 1;
    result[2] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}
