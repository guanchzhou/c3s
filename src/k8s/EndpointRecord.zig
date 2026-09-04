const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const EndpointRecord = @This();

key: keys.ObjectKey,
endpoints: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromEndpoints(allocator: std.mem.Allocator, value: klient.Endpoints) !EndpointRecord {
    const uid = value.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = value.metadata.namespace orelse "default",
        .name = value.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const endpoints = if (value.subsets) |subsets|
        try std.fmt.allocPrint(allocator, "{d}", .{subsets.len})
    else
        try allocator.dupe(u8, "<none>");
    errdefer allocator.free(endpoints);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .endpoints = endpoints, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: EndpointRecord, allocator: std.mem.Allocator) !EndpointRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const endpoints = try allocator.dupe(u8, self.endpoints);
    errdefer allocator.free(endpoints);
    const creation_timestamp = if (self.creation_timestamp) |value|
        try allocator.dupe(u8, value)
    else
        null;
    errdefer if (creation_timestamp) |value| allocator.free(value);
    return .{
        .key = key,
        .endpoints = endpoints,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *EndpointRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.endpoints);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const EndpointRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try allocator.dupe(u8, self.endpoints);
    initialized += 1;
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "endpoint record preserves exact endpoint count" {
    var parsed = try std.json.parseFromSlice(
        klient.Endpoints,
        std.testing.allocator,
        \\{"metadata":{"uid":"ep-1","namespace":"team","name":"api"},"subsets":[{},{}]}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromEndpoints(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("2", record.endpoints);
}

test "UID-less endpoints are malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromEndpoints(std.testing.allocator, .{ .metadata = .{ .name = "api" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "endpoint-uid",
            .namespace = "team",
            .name = "api",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const endpoints = try allocator.dupe(u8, "2");
        errdefer allocator.free(endpoints);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk EndpointRecord{
            .key = key,
            .endpoints = endpoints,
            .creation_timestamp = timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "endpoint clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}
