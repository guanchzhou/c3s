const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const clock = @import("../core/clock.zig");
const keys = @import("ResourceKey.zig");

pub const JobRecord = @This();

key: keys.ObjectKey,
succeeded: i32,
desired: i32,
completions_sort_key: [41]u8 = [_]u8{'0'} ** 41,
start_time: ?[]u8 = null,
completion_time: ?[]u8 = null,
creation_timestamp: ?[]u8 = null,

pub fn fromJob(allocator: std.mem.Allocator, job: klient.Job) !JobRecord {
    const uid = job.metadata.uid orelse return error.MissingUid;
    var key = try (keys.ObjectKey{
        .uid = uid,
        .namespace = job.metadata.namespace orelse "default",
        .name = job.metadata.name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    const start_time = try cloneOptional(allocator, statusStr(job.status, "startTime"));
    errdefer if (start_time) |value| allocator.free(value);
    const completion_time = try cloneOptional(allocator, statusStr(job.status, "completionTime"));
    errdefer if (completion_time) |value| allocator.free(value);
    const creation_timestamp = try cloneOptional(allocator, job.metadata.creationTimestamp);
    errdefer if (creation_timestamp) |value| allocator.free(value);

    return .{
        .key = key,
        .succeeded = statusInt(job.status, "succeeded"),
        .desired = if (job.spec) |spec| spec.completions orelse 1 else 1,
        .completions_sort_key = ratioSortKey(
            statusInt(job.status, "succeeded"),
            if (job.spec) |spec| spec.completions orelse 1 else 1,
        ),
        .start_time = start_time,
        .completion_time = completion_time,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: JobRecord, allocator: std.mem.Allocator) !JobRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const start_time = try cloneOptional(allocator, self.start_time);
    errdefer if (start_time) |value| allocator.free(value);
    const completion_time = try cloneOptional(allocator, self.completion_time);
    errdefer if (completion_time) |value| allocator.free(value);
    const creation_timestamp = try cloneOptional(allocator, self.creation_timestamp);
    errdefer if (creation_timestamp) |value| allocator.free(value);

    return .{
        .key = key,
        .succeeded = self.succeeded,
        .desired = self.desired,
        .completions_sort_key = self.completions_sort_key,
        .start_time = start_time,
        .completion_time = completion_time,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *JobRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.start_time) |value| allocator.free(value);
    if (self.completion_time) |value| allocator.free(value);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const JobRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    var result: [5][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);

    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try std.fmt.allocPrint(allocator, "{d}/{d}", .{ self.succeeded, self.desired });
    initialized += 1;
    result[3] = try duration(allocator, self.start_time, self.completion_time);
    initialized += 1;
    result[4] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

pub fn ratioSortKey(succeeded: i32, desired: i32) [41]u8 {
    var result = [_]u8{'0'} ** 41;
    result[20] = '/';
    writeCount(result[0..20], succeeded);
    writeCount(result[21..41], desired);
    return result;
}

fn writeCount(destination: []u8, value: i32) void {
    var buffer: [20]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{@max(value, 0)}) catch unreachable;
    @memcpy(destination[destination.len - text.len ..], text);
}

fn duration(
    allocator: std.mem.Allocator,
    start_time: ?[]const u8,
    completion_time: ?[]const u8,
) ![]const u8 {
    const start_epoch = age_util.parseTimestampToEpoch(start_time) orelse
        return allocator.dupe(u8, "-");
    const end_epoch = age_util.parseTimestampToEpoch(completion_time) orelse clock.timestamp();
    const diff = end_epoch - start_epoch;
    if (diff < 0) return allocator.dupe(u8, "0s");
    return age_util.formatDuration(allocator, @intCast(diff));
}

fn statusInt(status: ?std.json.Value, field: []const u8) i32 {
    const value = status orelse return 0;
    if (value != .object) return 0;
    const member = value.object.get(field) orelse return 0;
    return if (member == .integer) @intCast(member.integer) else 0;
}

fn statusStr(status: ?std.json.Value, field: []const u8) ?[]const u8 {
    const value = status orelse return null;
    if (value != .object) return null;
    const member = value.object.get(field) orelse return null;
    return if (member == .string) member.string else null;
}

fn cloneOptional(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |bytes| try allocator.dupe(u8, bytes) else null;
}

fn freeColumns(allocator: std.mem.Allocator, values: []const []const u8) void {
    for (values) |value| allocator.free(value);
}

test "job columns match legacy transform output" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(
        klient.Job,
        allocator,
        \\{"metadata":{"uid":"job-1","namespace":"team","name":"backup"},"spec":{"completions":3},"status":{"succeeded":2,"startTime":"2024-01-01T00:00:00Z","completionTime":"2024-01-01T01:00:00Z"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromJob(allocator, parsed.value);
    defer record.deinit(allocator);
    const actual = try record.columns(allocator);
    defer freeColumns(allocator, &actual);
    const expected = [_][]const u8{ "team", "backup", "2/3", "1h", "n/a" };
    for (expected, actual) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "UID-less job is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromJob(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "job-1",
            .namespace = "team",
            .name = "backup",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const start_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        errdefer allocator.free(start_time);
        const completion_time = try allocator.dupe(u8, "2024-01-01T01:00:00Z");
        errdefer allocator.free(completion_time);
        const creation_timestamp = try allocator.dupe(u8, "2023-12-31T23:59:00Z");
        errdefer allocator.free(creation_timestamp);
        break :blk JobRecord{
            .key = key,
            .succeeded = 2,
            .desired = 3,
            .start_time = start_time,
            .completion_time = completion_time,
            .creation_timestamp = creation_timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "job clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}
