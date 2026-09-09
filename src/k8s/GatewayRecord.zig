const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");
const support = @import("GatewayRecordSupport.zig");

pub const GatewayRecord = @This();

key: keys.ObjectKey,
gateway_class: []u8,
address: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromGateway(allocator: std.mem.Allocator, value: klient.Gateway) !GatewayRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "default");
    errdefer key.deinit(allocator);
    const gateway_class = try support.dupeOrNone(
        allocator,
        if (value.spec) |spec| spec.gatewayClassName else null,
    );
    errdefer allocator.free(gateway_class);
    const address = try support.joinObjectStrings(allocator, value.status, "addresses", "value");
    errdefer allocator.free(address);
    const creation_timestamp = try support.dupeTimestamp(allocator, value.metadata.creationTimestamp);
    return .{
        .key = key,
        .gateway_class = gateway_class,
        .address = address,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: GatewayRecord, allocator: std.mem.Allocator) !GatewayRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const gateway_class = try allocator.dupe(u8, self.gateway_class);
    errdefer allocator.free(gateway_class);
    const address = try allocator.dupe(u8, self.address);
    errdefer allocator.free(address);
    const creation_timestamp = try support.dupeTimestamp(allocator, self.creation_timestamp);
    return .{
        .key = key,
        .gateway_class = gateway_class,
        .address = address,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *GatewayRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.gateway_class);
    allocator.free(self.address);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const GatewayRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    var result: [5][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer support.freeColumns(allocator, result[0..initialized]);
    inline for (.{ self.key.namespace, self.key.name, self.gateway_class, self.address }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[4] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}
