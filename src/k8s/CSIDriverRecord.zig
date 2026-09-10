const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const CSIDriverRecord = @This();

key: keys.ObjectKey,
attach_required: bool,
pod_info: bool,
creation_timestamp: ?[]u8 = null,

pub fn fromCSIDriver(allocator: std.mem.Allocator, value: klient.CSIDriver) !CSIDriverRecord {
    var key = try keys.fromMetadata(allocator, value.metadata, "");
    errdefer key.deinit(allocator);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .attach_required = value.spec.attachRequired orelse true,
        .pod_info = value.spec.podInfoOnMount orelse false,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: CSIDriverRecord, allocator: std.mem.Allocator) !CSIDriverRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{
        .key = key,
        .attach_required = self.attach_required,
        .pod_info = self.pod_info,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *CSIDriverRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const CSIDriverRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try allocator.dupe(u8, if (self.attach_required) "true" else "false");
    initialized += 1;
    result[2] = try allocator.dupe(u8, if (self.pod_info) "true" else "false");
    initialized += 1;
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "CSI driver columns preserve legacy transform parity" {
    var parsed = try std.json.parseFromSlice(
        klient.CSIDriver,
        std.testing.allocator,
        \\{"metadata":{"uid":"csi-1","name":"csi.example"},"spec":{"attachRequired":false,"podInfoOnMount":true}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromCSIDriver(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "csi.example", "false", "true", "n/a" };
    inline for (expected, 0..) |column, index| try std.testing.expectEqualStrings(column, actual[index]);
}

test "UID-less CSI driver is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromCSIDriver(std.testing.allocator, .{
            .metadata = .{ .name = "bad" },
            .spec = .{},
        }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var parsed = try std.json.parseFromSlice(
        klient.CSIDriver,
        allocator,
        \\{"metadata":{"uid":"csi-1","name":"csi.example"},"spec":{"attachRequired":false,"podInfoOnMount":true}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var source = try fromCSIDriver(allocator, parsed.value);
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "CSI driver clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
