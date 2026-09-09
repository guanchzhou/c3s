const std = @import("std");
const klient = @import("klient");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const IngressClassRecord = @This();

key: keys.ObjectKey,
controller: []u8,
creation_timestamp: ?[]u8 = null,

pub fn fromIngressClass(allocator: std.mem.Allocator, value: klient.IngressClass) !IngressClassRecord {
    // IngressClassSpec.controller is required by the Kubernetes API. A missing
    // spec is malformed rather than an empty controller displayed as valid data.
    const spec = value.spec orelse return error.MissingController;
    var key = try keys.fromMetadata(allocator, value.metadata, "");
    errdefer key.deinit(allocator);
    const controller = try allocator.dupe(u8, spec.controller);
    errdefer allocator.free(controller);
    const creation_timestamp = if (value.metadata.creationTimestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .controller = controller, .creation_timestamp = creation_timestamp };
}

pub fn clone(self: IngressClassRecord, allocator: std.mem.Allocator) !IngressClassRecord {
    var key = try self.key.clone(allocator);
    errdefer key.deinit(allocator);
    const controller = try allocator.dupe(u8, self.controller);
    errdefer allocator.free(controller);
    const creation_timestamp = if (self.creation_timestamp) |timestamp|
        try allocator.dupe(u8, timestamp)
    else
        null;
    errdefer if (creation_timestamp) |timestamp| allocator.free(timestamp);
    return .{ .key = key, .controller = controller, .creation_timestamp = creation_timestamp };
}

pub fn deinit(self: *IngressClassRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    allocator.free(self.controller);
    if (self.creation_timestamp) |timestamp| allocator.free(timestamp);
    self.* = undefined;
}

pub fn columns(self: *const IngressClassRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    var result: [3][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (result[0..initialized]) |column| allocator.free(column);
    result[0] = try allocator.dupe(u8, self.key.name);
    initialized += 1;
    result[1] = try allocator.dupe(u8, self.controller);
    initialized += 1;
    result[2] = try age_util.calculateAge(allocator, self.creation_timestamp);
    return result;
}

test "ingress class columns preserve legacy transform parity" {
    var record = try fromIngressClass(std.testing.allocator, .{
        .metadata = .{ .uid = "class-1", .name = "nginx" },
        .spec = .{ .controller = "k8s.io/ingress-nginx" },
    });
    defer record.deinit(std.testing.allocator);
    const actual = try record.columns(std.testing.allocator);
    defer for (actual) |column| std.testing.allocator.free(column);
    const expected = [_][]const u8{ "nginx", "k8s.io/ingress-nginx", "n/a" };
    for (actual, expected) |got, want| try std.testing.expectEqualStrings(want, got);
}

test "UID-less ingress class is malformed" {
    try std.testing.expectError(
        error.MissingUid,
        fromIngressClass(std.testing.allocator, .{
            .metadata = .{ .name = "nginx" },
            .spec = .{ .controller = "k8s.io/ingress-nginx" },
        }),
    );
}

test "ingress class without spec is malformed" {
    try std.testing.expectError(
        error.MissingController,
        fromIngressClass(std.testing.allocator, .{
            .metadata = .{ .uid = "class-1", .name = "nginx" },
        }),
    );
}

test "real-shaped ingress class LIST decodes into projected controller" {
    const stream_list = @import("StreamList.zig");
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const ResponseScript = @import("FakeTransport.zig").ResponseScript;
    const read_transport = @import("ReadTransport.zig");
    const Capture = struct {
        allocator: std.mem.Allocator,
        controller: ?[]u8 = null,

        fn deinit(self: *@This()) void {
            if (self.controller) |controller| self.allocator.free(controller);
        }

        fn receive(self: *@This(), items: []const klient.IngressClass) !void {
            try std.testing.expectEqual(@as(usize, 1), items.len);
            var record = try fromIngressClass(self.allocator, items[0]);
            defer record.deinit(self.allocator);
            self.controller = try self.allocator.dupe(u8, record.controller);
        }
    };
    const Clock = struct {
        fn now(_: *anyopaque) u64 {
            return 0;
        }
    };
    const scripts = [_]ResponseScript{.{
        .body =
        \\{"apiVersion":"networking.k8s.io/v1","kind":"IngressClassList","metadata":{"resourceVersion":"17"},"items":[{"metadata":{"uid":"class-1","name":"nginx"},"spec":{"controller":"k8s.io/ingress-nginx"}}]}
        ,
    }};
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    var capture: Capture = .{ .allocator = std.testing.allocator };
    defer capture.deinit();
    var clock_context: u8 = 0;
    var result = try stream_list.stream(
        klient.IngressClass,
        std.testing.allocator,
        fake.transport(),
        try read_transport.ReadRequest.init("/apis/networking.k8s.io/v1/ingressclasses"),
        .{ .clock = .{ .ptr = &clock_context, .now_ns_fn = Clock.now } },
        &capture,
        Capture.receive,
    );
    defer result.deinit();

    try std.testing.expectEqualStrings("17", result.resource_version);
    try std.testing.expectEqualStrings("k8s.io/ingress-nginx", capture.controller.?);
}

test "real-shaped ingress class WATCH ADDED and MODIFIED decode into records" {
    const Envelope = klient.Watcher(klient.IngressClass).WatchEnvelope;
    const cases = [_][]const u8{
        \\{"type":"ADDED","object":{"metadata":{"uid":"class-1","name":"nginx"},"spec":{"controller":"k8s.io/ingress-nginx"}}}
        ,
        \\{"type":"MODIFIED","object":{"metadata":{"uid":"class-1","name":"nginx"},"spec":{"controller":"k8s.io/ingress-nginx"}}}
        ,
    };

    for (cases) |json| {
        var parsed = try std.json.parseFromSlice(
            Envelope,
            std.testing.allocator,
            json,
            .{ .ignore_unknown_fields = true },
        );
        defer parsed.deinit();
        try std.testing.expect(
            std.mem.eql(u8, parsed.value.type, "ADDED") or
                std.mem.eql(u8, parsed.value.type, "MODIFIED"),
        );
        var record = try fromIngressClass(std.testing.allocator, parsed.value.object.?);
        defer record.deinit(std.testing.allocator);
        try std.testing.expectEqualStrings("k8s.io/ingress-nginx", record.controller);
    }
}

fn cloneAllocationExercise(allocator: std.mem.Allocator) !void {
    var source = try fromIngressClass(allocator, .{
        .metadata = .{ .uid = "class-1", .name = "nginx", .creationTimestamp = "2024-01-01T00:00:00Z" },
        .spec = .{ .controller = "k8s.io/ingress-nginx" },
    });
    defer source.deinit(allocator);
    var copy = try source.clone(allocator);
    copy.deinit(allocator);
}

test "ingress class clone is allocation-failure safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, cloneAllocationExercise, .{});
}
