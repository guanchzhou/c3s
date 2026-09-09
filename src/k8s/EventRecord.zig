const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const EventRecord = @This();

key: keys.ObjectKey,
last_seen_timestamp: ?[]u8 = null,
event_type: []u8,
reason: []u8,
object: []u8,
count: i32,
message: []u8,

pub fn fromEvent(allocator: std.mem.Allocator, event: klient.Event) !EventRecord {
    var key = try keys.fromMetadata(allocator, event.metadata, "default");
    errdefer key.deinit(allocator);
    const last_seen_timestamp = if ((if (event.series) |series| series.lastObservedTime else null) orelse event.lastTimestamp orelse event.eventTime orelse event.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (last_seen_timestamp) |timestamp| allocator.free(timestamp);
    const event_type = try allocator.dupe(u8, event.type orelse "-");
    errdefer allocator.free(event_type);
    const reason = try allocator.dupe(u8, event.reason orelse "-");
    errdefer allocator.free(reason);
    const object = try formatObject(allocator, event.involvedObject);
    errdefer allocator.free(object);
    const message = try allocator.dupe(u8, event.message orelse "");
    return .{
        .key = key,
        .last_seen_timestamp = last_seen_timestamp,
        .event_type = event_type,
        .reason = reason,
        .object = object,
        .count = (if (event.series) |series| series.count else null) orelse event.count orelse 0,
        .message = message,
    };
}

pub fn clone(self: EventRecord, allocator: std.mem.Allocator) !EventRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const last_seen_timestamp = if (self.last_seen_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (last_seen_timestamp) |timestamp| allocator.free(timestamp);
    const event_type = try allocator.dupe(u8, self.event_type);
    errdefer allocator.free(event_type);
    const reason = try allocator.dupe(u8, self.reason);
    errdefer allocator.free(reason);
    const object = try allocator.dupe(u8, self.object);
    errdefer allocator.free(object);
    const message = try allocator.dupe(u8, self.message);
    return .{
        .key = key,
        .last_seen_timestamp = last_seen_timestamp,
        .event_type = event_type,
        .reason = reason,
        .object = object,
        .count = self.count,
        .message = message,
    };
}

pub fn deinit(self: *EventRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    if (self.last_seen_timestamp) |timestamp| allocator.free(timestamp);
    allocator.free(self.event_type);
    allocator.free(self.reason);
    allocator.free(self.object);
    allocator.free(self.message);
    self.* = undefined;
}

pub fn columns(self: *const EventRecord, allocator: std.mem.Allocator) ![7][]const u8 {
    var result: [7][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.namespace);
    initialized += 1;
    result[1] = try age_util.calculateAge(allocator, self.last_seen_timestamp);
    initialized += 1;
    result[2] = try allocator.dupe(u8, self.event_type);
    initialized += 1;
    result[3] = try allocator.dupe(u8, self.reason);
    initialized += 1;
    result[4] = try allocator.dupe(u8, self.object);
    initialized += 1;
    result[5] = try std.fmt.allocPrint(allocator, "{d}", .{self.count});
    initialized += 1;
    result[6] = try allocator.dupe(u8, self.message);
    return result;
}

fn formatObject(allocator: std.mem.Allocator, involved: ?klient.types.EventInvolvedObject) ![]u8 {
    if (involved) |value| {
        const kind = value.kind orelse "";
        const name = value.name orelse "";
        if (kind.len > 0 and name.len > 0)
            return std.fmt.allocPrint(allocator, "{s}/{s}", .{ kind, name });
        if (name.len > 0) return allocator.dupe(u8, name);
    }
    return allocator.dupe(u8, "");
}

test "event columns preserve OBJECT and current LAST-SEEN COUNT MESSAGE behavior" {
    var parsed = try std.json.parseFromSlice(
        klient.Event,
        std.testing.allocator,
        \\{"metadata":{"uid":"event-1","namespace":"team","name":"event-generated"},"involvedObject":{"kind":"Pod","name":"api-1"},"type":"Warning","reason":"BackOff","message":"restarting","count":7}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromEvent(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("event-1", record.key.uid);
    try std.testing.expectEqualStrings("event-generated", record.key.name);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "team", "n/a", "Warning", "BackOff", "Pod/api-1", "7", "restarting" };
    for (actual, expected) |column, want| try std.testing.expectEqualStrings(want, column);
}

test "event series overrides deprecated count and timestamps" {
    var parsed = try std.json.parseFromSlice(
        klient.Event,
        std.testing.allocator,
        \\{"metadata":{"uid":"event-series","namespace":"team","name":"generated","creationTimestamp":"2024-01-01T00:00:00Z"},"involvedObject":{"kind":"Pod","name":"api-1"},"count":2,"lastTimestamp":"2024-01-01T00:01:00Z","eventTime":"2024-01-01T00:00:01Z","series":{"count":9,"lastObservedTime":"2024-01-01T00:05:00Z"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromEvent(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(i32, 9), record.count);
    try std.testing.expectEqualStrings("2024-01-01T00:05:00Z", record.last_seen_timestamp.?);
    try std.testing.expectEqualStrings("Pod/api-1", record.object);
}

test "event UID is required and object remains independent of identity" {
    try std.testing.expectError(
        error.MissingUid,
        fromEvent(std.testing.allocator, .{ .metadata = .{ .name = "bad" } }),
    );
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = blk: {
        var key = try (keys.ObjectKey{ .uid = "event-1", .namespace = "team", .name = "generated" }).clone(allocator);
        errdefer key.deinit(allocator);
        const last_seen = try allocator.dupe(u8, "2024-01-01T00:00:00Z");
        errdefer allocator.free(last_seen);
        const event_type = try allocator.dupe(u8, "Warning");
        errdefer allocator.free(event_type);
        const reason = try allocator.dupe(u8, "BackOff");
        errdefer allocator.free(reason);
        const object = try allocator.dupe(u8, "Pod/api-1");
        errdefer allocator.free(object);
        const message = try allocator.dupe(u8, "restarting");
        break :blk EventRecord{
            .key = key,
            .last_seen_timestamp = last_seen,
            .event_type = event_type,
            .reason = reason,
            .object = object,
            .count = 7,
            .message = message,
        };
    };
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "event clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
