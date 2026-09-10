const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const CSRRecord = @This();

key: keys.ObjectKey,
signer: []u8,
issued: bool,
creation_timestamp: ?[]u8 = null,

pub fn fromCSR(allocator: std.mem.Allocator, item: klient.CertificateSigningRequest) !CSRRecord {
    var key = try keys.fromMetadata(allocator, item.metadata, "");
    errdefer key.deinit(allocator);
    const signer = try allocator.dupe(u8, if (item.spec) |spec| spec.signerName else "<none>");
    errdefer allocator.free(signer);
    const creation_timestamp = if (item.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    return .{
        .key = key,
        .signer = signer,
        .issued = jsonStringField(item.status, "certificate") != null,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: CSRRecord, allocator: std.mem.Allocator) !CSRRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const signer = try allocator.dupe(u8, self.signer);
    errdefer allocator.free(signer);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .signer = signer, .issued = self.issued, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *CSRRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.signer);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const CSRRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    var result: [4][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.signer);
    initialized += 1;
    result[2] = try allocator.dupe(u8, if (self.issued) "Issued" else "Pending");
    initialized += 1;
    result[3] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

fn jsonStringField(value: ?std.json.Value, field: []const u8) ?[]const u8 {
    const actual = value orelse return null;
    if (actual != .object) return null;
    const member = actual.object.get(field) orelse return null;
    return if (member == .string) member.string else null;
}

test "CSR columns match current transform and UID is required" {
    var parsed = try std.json.parseFromSlice(
        klient.CertificateSigningRequest,
        std.testing.allocator,
        \\{"metadata":{"uid":"csr-1","name":"node"},"spec":{"request":"abc","signerName":"kubernetes.io/kubelet-serving"},"status":{"certificate":"cert"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromCSR(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "node", "kubernetes.io/kubelet-serving", "Issued", "n/a" };
    for (actual, expected) |column, want| try std.testing.expectEqualStrings(want, column);
    try std.testing.expectError(
        error.MissingUid,
        fromCSR(std.testing.allocator, .{
            .metadata = .{ .name = "bad" },
            .spec = .{ .request = "abc", .signerName = "example.com/signer" },
        }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "csr-1", .namespace = "", .name = "node" }).clone(allocator);
        errdefer key.deinit(allocator);
        const signer = try allocator.dupe(u8, "kubernetes.io/kubelet-serving");
        errdefer allocator.free(signer);
        const timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        break :blk CSRRecord{ .key = key, .signer = signer, .issued = true, .creation_timestamp = timestamp };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "CSR clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
