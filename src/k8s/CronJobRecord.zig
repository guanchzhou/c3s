const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const CronJobRecord = @This();

key: keys.ObjectKey,
schedule: []u8,
@"suspend": bool,
active: i32,
active_sort_key: [20]u8 = [_]u8{'0'} ** 20,
last_schedule_time: ?[]u8 = null,
creation_timestamp: ?[]u8 = null,

pub fn fromCronJob(allocator: std.mem.Allocator, cron_job: klient.CronJob) !CronJobRecord {
    var key = try keys.fromMetadata(allocator, cron_job.metadata, "default");
    errdefer key.deinit(allocator);
    const schedule = try allocator.dupe(
        u8,
        if (cron_job.spec) |spec| spec.schedule orelse "" else "",
    );
    errdefer allocator.free(schedule);
    const last_schedule_time = try cloneOptional(
        allocator,
        statusStr(cron_job.status, "lastScheduleTime"),
    );
    errdefer if (last_schedule_time) |value| allocator.free(value);
    const creation_timestamp = try cloneOptional(allocator, cron_job.metadata.creationTimestamp);
    errdefer if (creation_timestamp) |value| allocator.free(value);

    return .{
        .key = key,
        .schedule = schedule,
        .@"suspend" = if (cron_job.spec) |spec| spec.@"suspend" orelse false else false,
        .active = activeCount(cron_job.status),
        .active_sort_key = countSortKey(activeCount(cron_job.status)),
        .last_schedule_time = last_schedule_time,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn clone(self: CronJobRecord, allocator: std.mem.Allocator) !CronJobRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const schedule = try allocator.dupe(u8, self.schedule);
    errdefer allocator.free(schedule);
    const last_schedule_time = try cloneOptional(allocator, self.last_schedule_time);
    errdefer if (last_schedule_time) |value| allocator.free(value);
    const creation_timestamp = try cloneOptional(allocator, self.creation_timestamp);
    errdefer if (creation_timestamp) |value| allocator.free(value);

    return .{
        .key = key,
        .schedule = schedule,
        .@"suspend" = self.@"suspend",
        .active = self.active,
        .active_sort_key = self.active_sort_key,
        .last_schedule_time = last_schedule_time,
        .creation_timestamp = creation_timestamp,
    };
}

pub fn deinit(self: *CronJobRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.schedule);
    if (self.last_schedule_time) |value| allocator.free(value);
    if (self.creation_timestamp) |value| allocator.free(value);
    self.* = undefined;
}

pub fn columns(self: *const CronJobRecord, allocator: std.mem.Allocator) ![6][]const u8 {
    var result: [6][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);

    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[2] = try allocator.dupe(u8, self.schedule);
    initialized += 1;
    result[3] = try allocator.dupe(u8, if (self.@"suspend") "True" else "False");
    initialized += 1;
    result[4] = try std.fmt.allocPrint(allocator, "{d}", .{self.active});
    initialized += 1;
    result[5] = if (self.last_schedule_time) |timestamp|
        try age_util.calculateAge(allocator, timestamp)
    else
        try allocator.dupe(u8, "-");
    return result;
}

pub fn countSortKey(value: i32) [20]u8 {
    var result = [_]u8{'0'} ** 20;
    var buffer: [20]u8 = undefined;
    const text = std.fmt.bufPrint(&buffer, "{d}", .{@max(value, 0)}) catch unreachable;
    @memcpy(result[result.len - text.len ..], text);
    return result;
}

fn activeCount(status: ?std.json.Value) i32 {
    const value = status orelse return 0;
    if (value != .object) return 0;
    const active = value.object.get("active") orelse return 0;
    return if (active == .array) @intCast(active.array.items.len) else 0;
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

test "cron job columns match legacy transform output" {
    const allocator = std.testing.allocator;
    var parsed = try std.json.parseFromSlice(
        klient.CronJob,
        allocator,
        \\{"metadata":{"uid":"cron-1","namespace":"team","name":"nightly"},"spec":{"schedule":"0 0 * * *","suspend":true},"status":{"active":[{"name":"one"},{"name":"two"}]}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromCronJob(allocator, parsed.value);
    defer record.deinit(allocator);
    const actual = try record.columns(allocator);
    defer freeColumns(allocator, &actual);
    const expected = [_][]const u8{ "team", "nightly", "0 0 * * *", "True", "2", "-" };
    for (expected, actual) |want, got| try std.testing.expectEqualStrings(want, got);
}

test "cron job LIST decode renders real suspend states" {
    const allocator = std.testing.allocator;
    const cases = [_]struct {
        json: []const u8,
        expected: []const u8,
    }{
        .{
            .json =
            \\{"apiVersion":"batch/v1","kind":"CronJobList","metadata":{"resourceVersion":"1"},"items":[{"metadata":{"uid":"cron-true","namespace":"team","name":"nightly"},"spec":{"schedule":"0 0 * * *","suspend":true}}]}
            ,
            .expected = "True",
        },
        .{
            .json =
            \\{"apiVersion":"batch/v1","kind":"CronJobList","metadata":{"resourceVersion":"2"},"items":[{"metadata":{"uid":"cron-false","namespace":"team","name":"nightly"},"spec":{"schedule":"0 0 * * *","suspend":false}}]}
            ,
            .expected = "False",
        },
        .{
            .json =
            \\{"apiVersion":"batch/v1","kind":"CronJobList","metadata":{"resourceVersion":"3"},"items":[{"metadata":{"uid":"cron-absent","namespace":"team","name":"nightly"},"spec":{"schedule":"0 0 * * *"}}]}
            ,
            .expected = "False",
        },
    };

    for (cases) |case| {
        var parsed = try std.json.parseFromSlice(
            klient.types.List(klient.CronJob),
            allocator,
            case.json,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        try std.testing.expectEqual(@as(usize, 1), parsed.value.items.len);
        var record = try fromCronJob(allocator, parsed.value.items[0]);
        defer record.deinit(allocator);
        const rendered = try record.columns(allocator);
        defer freeColumns(allocator, &rendered);
        try std.testing.expectEqualStrings(case.expected, rendered[3]);
    }
}

fn projectionMatch(record: *const CronJobRecord, filter: []const u8) bool {
    return std.mem.indexOf(u8, record.key.name, filter) != null;
}

fn projectionSortKey(record: *const CronJobRecord, column: u8) []const u8 {
    return switch (column) {
        2 => record.schedule,
        3 => if (record.@"suspend") "True" else "False",
        else => record.key.name,
    };
}

test "cron job WATCH MODIFIED updates projected suspend column" {
    const allocator = std.testing.allocator;
    const Projection = @import("ResourceProjection.zig").ResourceProjection(CronJobRecord);
    var projection = Projection.init(allocator, .{
        .matchFn = projectionMatch,
        .sortKeyFn = projectionSortKey,
    });
    defer projection.deinit();

    var list = try std.json.parseFromSlice(
        klient.types.List(klient.CronJob),
        allocator,
        \\{"apiVersion":"batch/v1","kind":"CronJobList","metadata":{"resourceVersion":"10"},"items":[{"metadata":{"uid":"cron-1","namespace":"team","name":"nightly"},"spec":{"schedule":"0 0 * * *","suspend":false}}]}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer list.deinit();
    var initial_changes = [_]keys.TypedChange(CronJobRecord){.{
        .initial_upsert = try fromCronJob(allocator, list.value.items[0]),
    }};
    defer initial_changes[0].deinit(allocator);
    var initial_batch = keys.TypedBatch(CronJobRecord){
        .generation = 1,
        .subscription_id = 1,
        .revision = 1,
        .changes = &initial_changes,
        .sync = null,
        .owned_bytes = 1,
    };
    var initial_plan = try Projection.handler().preflight(@ptrCast(&projection), &initial_batch, allocator);
    Projection.handler().commit(@ptrCast(&projection), &initial_batch, &initial_plan);
    initial_plan.deinit(allocator);

    const initial = projection.record("cron-1") orelse return error.MissingProjectedCronJob;
    var initial_columns = try initial.columns(allocator);
    defer freeColumns(allocator, &initial_columns);
    try std.testing.expectEqualStrings("False", initial_columns[3]);

    const WatchEnvelope = struct {
        type: []const u8,
        object: klient.CronJob,
    };
    var watch = try std.json.parseFromSlice(
        WatchEnvelope,
        allocator,
        \\{"type":"MODIFIED","object":{"metadata":{"uid":"cron-1","namespace":"team","name":"nightly"},"spec":{"schedule":"0 0 * * *","suspend":true}}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer watch.deinit();
    try std.testing.expectEqualStrings("MODIFIED", watch.value.type);
    var modified_changes = [_]keys.TypedChange(CronJobRecord){.{
        .watch_upsert = try fromCronJob(allocator, watch.value.object),
    }};
    defer modified_changes[0].deinit(allocator);
    var modified_batch = keys.TypedBatch(CronJobRecord){
        .generation = 1,
        .subscription_id = 1,
        .revision = 2,
        .changes = &modified_changes,
        .sync = null,
        .owned_bytes = 1,
    };
    var modified_plan = try Projection.handler().preflight(@ptrCast(&projection), &modified_batch, allocator);
    Projection.handler().commit(@ptrCast(&projection), &modified_batch, &modified_plan);
    modified_plan.deinit(allocator);

    const modified = projection.record("cron-1") orelse return error.MissingProjectedCronJob;
    var modified_columns = try modified.columns(allocator);
    defer freeColumns(allocator, &modified_columns);
    try std.testing.expectEqualStrings("True", modified_columns[3]);
}

test "UID-less cron job is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromCronJob(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{
            .uid = "cron-1",
            .namespace = "team",
            .name = "nightly",
        }).clone(allocator);
        errdefer key.deinit(allocator);
        const schedule = try allocator.dupe(u8, "0 0 * * *");
        errdefer allocator.free(schedule);
        const last_schedule_time = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        errdefer allocator.free(last_schedule_time);
        const creation_timestamp = try allocator.dupe(u8, "2023-12-01T00:00:00Z");
        errdefer allocator.free(creation_timestamp);
        break :blk CronJobRecord{
            .key = key,
            .schedule = schedule,
            .@"suspend" = true,
            .active = 2,
            .last_schedule_time = last_schedule_time,
            .creation_timestamp = creation_timestamp,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "cron job clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        cloneAllocationExercise,
        .{},
    );
}
