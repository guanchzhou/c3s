const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const EndpointSliceRecord = @This();

key: keys.ObjectKey,
address_type: []u8,
endpoints: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromEndpointSlice(allocator: std.mem.Allocator, value: klient.EndpointSlice) !EndpointSliceRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = value.metadata.namespace orelse "default",
        .name = value.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const address_type = try allocator.dupe(u8, value.addressType);
    errdefer allocator.free(address_type);
    const endpoints = try std.fmt.allocPrint(allocator, "{d}", .{
        if (value.endpoints) |endpoints| endpoints.len else 0,
    });
    errdefer allocator.free(endpoints);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .address_type = address_type,
        .endpoints = endpoints,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: EndpointSliceRecord, allocator: std.mem.Allocator) !EndpointSliceRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const address_type = try allocator.dupe(u8, self.address_type);
    errdefer allocator.free(address_type);
    const endpoints = try allocator.dupe(u8, self.endpoints);
    errdefer allocator.free(endpoints);
    const creation_timestamp = if (self.creation_timestamp) |value|
        try allocator.dupe(u8, value)
    else
        null;
    errdefer if (creation_timestamp) |value| allocator.free(value);
    return .{
        .key = key,
        .address_type = address_type,
        .endpoints = endpoints,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *EndpointSliceRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.address_type);
    allocator.free(self.endpoints);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const EndpointSliceRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    var result: [5][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    inline for (.{ self.key.namespace, self.key.name, self.address_type, self.endpoints }, 0..) |value, index| {
        result[index] = try allocator.dupe(u8, value);
        initialized += 1;
    }
    result[4] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "endpoint slice record preserves address type and endpoint count" {
    var parsed = try std.json.parseFromSlice(
        klient.EndpointSlice,
        std.testing.allocator,
        \\{"metadata":{"uid":"slice-1","namespace":"team","name":"api-abc"},"addressType":"IPv4","endpoints":[{},{}]}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromEndpointSlice(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("IPv4", record.address_type);
    try std.testing.expectEqualStrings("2", record.endpoints);
}

test "UID-less endpoint slice is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromEndpointSlice(std.testing.allocator, .{
            .metadata = .{ .name = "api" },
            .addressType = "IPv4",
        }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "slice-uid",
            .namespace = "team",
            .name = "api-abc",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const address_type = try allocator.dupe(u8, "IPv4");
        errdefer allocator.free(address_type);
        const endpoints = try allocator.dupe(u8, "2");
        errdefer allocator.free(endpoints);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk EndpointSliceRecord{
            .key = key,
            .address_type = address_type,
            .endpoints = endpoints,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "endpoint slice clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}
