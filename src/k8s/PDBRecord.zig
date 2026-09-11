const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const PDBRecord = @This();

key: keys.ObjectKey,
min_available: []u8,
max_unavailable: []u8,
min_available_sort_key: [21]u8 = @splat('0'),
max_unavailable_sort_key: [21]u8 = @splat('0'),
allowed_disruptions: i32,
allowed_sort_key: [20]u8 = @splat('0'),
creation_timestamp: ?[]u8 = null,

pub fn fromPodDisruptionBudget(
    allocator: std.mem.Allocator,
    pdb: klient.PodDisruptionBudget,
) !PDBRecord {
    var key = try keys.fromMetadata(allocator, pdb.metadata, "default");
    errdefer key.deinit(allocator);
    const min_available = try intOrString(
        allocator,
        if (pdb.spec) |spec| spec.minAvailable else null,
    );
    errdefer allocator.free(min_available);
    const max_unavailable = try intOrString(
        allocator,
        if (pdb.spec) |spec| spec.maxUnavailable else null,
    );
    errdefer allocator.free(max_unavailable);
    const creation_timestamp = try cloneOptional(allocator, pdb.metadata.creationTimestamp);
    errdefer if (creation_timestamp) |value| allocator.free(value);

    return .{
        .key = key,
        .min_available = min_available,
        .max_unavailable = max_unavailable,
        .min_available_sort_key = intOrStringSortKey(min_available),
        .max_unavailable_sort_key = intOrStringSortKey(max_unavailable),
        .allowed_disruptions = statusInt(pdb.status, "disruptionsAllowed"),
        .allowed_sort_key = countSortKey(statusInt(pdb.status, "disruptionsAllowed")),
        .creation_timestamp = creation_timestamp,
    };
}

pub fn fromPDB(allocator: std.mem.Allocator, pdb: klient.PodDisruptionBudget) !PDBRecord {
    return fromPodDisruptionBudget(allocator, pdb);
}

pub fn clone(self: PDBRecord, allocator: std.mem.Allocator) !PDBRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const min_available = try allocator.dupe(u8, self.min_available);
    errdefer allocator.free(min_available);
    const max_unavailable = try allocator.dupe(u8, self.max_unavailable);
    errdefer allocator.free(max_unavailable);
    const creation_timestamp = try cloneOptional(allocator, self.creation_timestamp);
    errdefer if (creation_timestamp) |value| allocator.free(value);

    return .{
        .key = key,
        .min_available = min_available,
        .max_unavailable = max_unavailable,
        .min_available_sort_key = self.min_available_sort_key,
        .max_unavailable_sort_key = self.max_unavailable_sort_key,
        .allowed_disruptions = self.allowed_disruptions,
        .allowed_sort_key = self.allowed_sort_key,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *PDBRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.min_available);
    allocator.free(self.max_unavailable);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const PDBRecord, allocator: std.mem.Allocator) ![6][]const u8 {
    var result: [6][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);

    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try allocator.dupe(u8, self.min_available);
    initialized += 1;
    result[3] = try allocator.dupe(u8, self.max_unavailable);
    initialized += 1;
    result[4] = try std.fmt.allocPrint(allocator, "{d}", .{self.allowed_disruptions});
    initialized += 1;
    result[5] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

pub fn countSortKey(value: i32) [20]u8 {
    var result: [20]u8 = @splat('0');
    var buffer: [20]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{@max(value, 0)}) catch unreachable;
    @memcpy(result[result.len - text.len ..], text);
    return result;
}

pub fn intOrStringSortKey(value: []const u8) [21]u8 {
    var result: [21]u8 = @splat('0');
    const is_percent = value.len > 1 and value[value.len - 1] == '%';
    const numeric = if (is_percent) value[0 .. value.len - 1] else value;
    if (std.fmt.parseInt(u64, numeric, 10)) |number| {
        result[0] = if (is_percent) '%' else '#';
        var buffer: [20]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{d}", .{number}) catch unreachable;
        @memcpy(result[result.len - text.len ..], text);
        return result;
    } else |_| {
        result[0] = '~';
        const len = @min(value.len, result.len - 1);
        @memcpy(result[1 .. 1 + len], value[0..len]);
        return result;
    }
}

fn intOrString(allocator: std.mem.Allocator, value: ?std.json.Value) ![]u8 {
    const scalar = value orelse return allocator.dupe(u8, "-");
    return switch (scalar) {
        .integer => |number| std.fmt.allocPrint(allocator, "{d}", .{number}),
        .string => |bytes| allocator.dupe(u8, bytes),
        else => allocator.dupe(u8, "-"),
    };
}

fn statusInt(status: ?std.json.Value, field: []const u8) i32 {
    const value = status orelse return 0;
    if (value != .object) return 0;
    const member = value.object.get(field) orelse return 0;
    return if (member == .integer) @intCast(member.integer) else 0;
}

fn cloneOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |bytes| try allocator.dupe(u8, bytes) else null;
}

fn freeColumns(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
}

test "PDB columns match legacy transform output" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(
        klient.PodDisruptionBudget,
        allocator,
        \\{"metadata":{"uid":"pdb-1","namespace":"team","name":"api"},"spec":{"minAvailable":"50%","maxUnavailable":1,"selector":{"matchLabels":{"app":"api"}}},"status":{"disruptionsAllowed":2}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromPodDisruptionBudget(allocator, parsed.value);
    defer record.deinit(allocator);
    const actual = try record.columns(allocator);
    defer freeColumns(allocator, &actual);
    const expected = [_][]const u8{ "team", "api", "50%", "1", "2", "n/a" };
    for (expected, actual) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "UID-less PDB is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromPodDisruptionBudget(
            std.testing.allocator,
            .{ .metadata = .{ .name = "bad" } },
        ),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "pdb-1",
            .namespace = "team",
            .name = "api",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const min_available = try allocator.dupe(u8, "50%");
        errdefer allocator.free(min_available);
        const max_unavailable = try allocator.dupe(u8, "1");
        errdefer allocator.free(max_unavailable);
        const creation_timestamp = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        errdefer allocator.free(creation_timestamp);
        break :blk PDBRecord{
            .key = key,
            .min_available = min_available,
            .max_unavailable = max_unavailable,
            .allowed_disruptions = 2,
            .creation_timestamp = creation_timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "PDB clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}

test "PDB IntOrString sort keys order integers numerically and distinguish percentages" {
    const two = intOrStringSortKey("2");
    const ten = intOrStringSortKey("10");
    const fifty_percent = intOrStringSortKey("50%");
    try std.testing.expect(std.mem.order(u8, &two, &ten) == .lt);
    try std.testing.expect(!std.mem.eql(u8, &ten, &fifty_percent));
    try std.testing.expectEqual(@as(u8, '#'), ten[0]);
    try std.testing.expectEqual(@as(u8, '%'), fifty_percent[0]);
}
