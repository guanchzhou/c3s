const std = @import("std");
const transport_mod = @import("ReadTransport.zig");

pub const max_object_bytes: usize = 4 << 20;
pub const batch_object_limit: usize = 128;
pub const batch_interval_ns: u64 = 25 * std.time.ns_per_ms;

pub const Clock = struct {
    ptr: *anyopaque,
    now_ns_fn: *const fn (*anyopaque) u64,

    pub fn nowNs(self: Clock) u64 {
        return self.now_ns_fn(self.ptr);
    }
};

pub const Options = struct {
    clock: Clock,
    max_object_size: usize = max_object_bytes,
    batch_size: usize = batch_object_limit,
    batch_interval: u64 = batch_interval_ns,
};

pub const Result = struct {
    allocator: std.mem.Allocator,
    resource_version: []u8,
    continue_token: []u8,

    pub fn deinit(self: *Result) void {
        self.allocator.free(self.resource_version);
        self.allocator.free(self.continue_token);
        self.* = undefined;
    }
};

pub fn stream(
    comptime T: type,
    allocator: std.mem.Allocator,
    transport: transport_mod.ReadTransport,
    request: transport_mod.ReadRequest,
    options: Options,
    batch_context: anytype,
    comptime on_batch: fn (@TypeOf(batch_context), []const T) anyerror!void,
) !Result {
    if (options.max_object_size == 0 or options.batch_size == 0)
        return error.InvalidStreamOptions;

    const Parser = struct {
        allocator: std.mem.Allocator,
        options: Options,
        batch_context: @TypeOf(batch_context),
        result: ?Result = null,

        fn receive(
            erased: *anyopaque,
            meta: transport_mod.ResponseMeta,
            body_reader: *std.Io.Reader,
        ) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(erased));
            if (meta.status == .payload_too_large) return error.ResponseTooLarge;
            if (meta.status.class() != .success) return switch (meta.status) {
                .unauthorized => error.HttpUnauthorized,
                .forbidden => error.HttpForbidden,
                .not_found => error.HttpNotFound,
                .gone => error.HttpGone,
                .too_many_requests => error.HttpThrottled,
                else => error.HttpStatus,
            };
            self.result = try self.parse(body_reader);
        }

        fn parse(self: *@This(), body_reader: *std.Io.Reader) !Result {
            var json_reader = std.json.Reader.init(self.allocator, body_reader);
            defer json_reader.deinit();
            var diagnostics: std.json.Diagnostics = .{};
            json_reader.enableDiagnostics(&diagnostics);

            var outer_arena = std.heap.ArenaAllocator.init(self.allocator);
            defer outer_arena.deinit();
            var object_arena = std.heap.ArenaAllocator.init(self.allocator);
            defer object_arena.deinit();
            var batch: std.ArrayList(T) = .empty;
            defer batch.deinit(self.allocator);

            var resource_version: ?[]u8 = null;
            errdefer if (resource_version) |rv| self.allocator.free(rv);
            var continue_token: ?[]u8 = null;
            errdefer if (continue_token) |token| self.allocator.free(token);
            var saw_items = false;
            var batch_started = self.options.clock.nowNs();

            const first = nextOuter(&json_reader) catch |err| return mapOuterError(err);
            if (first != .object_begin) return error.MalformedOuterJson;

            while (true) {
                const key_token = json_reader.nextAllocMax(
                    outer_arena.allocator(),
                    .alloc_if_needed,
                    self.options.max_object_size,
                ) catch |err| return mapOuterError(err);
                defer freeAllocatedToken(outer_arena.allocator(), key_token);
                const key = switch (key_token) {
                    .string, .allocated_string => |value| value,
                    .object_end => break,
                    else => return error.MalformedOuterJson,
                };

                if (std.mem.eql(u8, key, "items")) {
                    if (saw_items) return error.MalformedOuterJson;
                    saw_items = true;
                    if ((json_reader.next() catch |err| return mapOuterError(err)) != .array_begin)
                        return error.ItemsNotArray;

                    while (true) {
                        const token_type = json_reader.peekNextTokenType() catch |err|
                            return mapOuterError(err);
                        if (token_type == .array_end) {
                            _ = json_reader.next() catch |err| return mapOuterError(err);
                            break;
                        }

                        const object_start = diagnostics.getByteOffset();
                        const item = std.json.innerParse(
                            T,
                            object_arena.allocator(),
                            &json_reader,
                            .{
                                .ignore_unknown_fields = true,
                                .max_value_len = self.options.max_object_size,
                                .allocate = .alloc_always,
                            },
                        ) catch |err| return mapItemError(err);
                        const object_end = diagnostics.getByteOffset();
                        if (object_end - object_start > self.options.max_object_size)
                            return error.ObjectTooLarge;
                        try batch.append(self.allocator, item);

                        const now = self.options.clock.nowNs();
                        if (batch.items.len >= self.options.batch_size or
                            now -| batch_started >= self.options.batch_interval)
                        {
                            try on_batch(self.batch_context, batch.items);
                            batch.clearRetainingCapacity();
                            _ = object_arena.reset(.{ .retain_with_limit = self.options.max_object_size });
                            batch_started = now;
                        }
                    }
                } else if (std.mem.eql(u8, key, "metadata")) {
                    if (resource_version != null) return error.MalformedOuterJson;
                    const Metadata = struct {
                        resourceVersion: ?[]const u8 = null,
                        @"continue": ?[]const u8 = null,
                    };
                    const metadata = std.json.innerParse(
                        Metadata,
                        outer_arena.allocator(),
                        &json_reader,
                        .{
                            .ignore_unknown_fields = true,
                            .max_value_len = self.options.max_object_size,
                            .allocate = .alloc_always,
                        },
                    ) catch |err| return mapOuterError(err);
                    if (metadata.resourceVersion) |rv| {
                        // An empty string is not a resumable version; treat it
                        // exactly like an absent one rather than storing "".
                        if (rv.len == 0) return error.MissingResourceVersion;
                        resource_version = try self.allocator.dupe(u8, rv);
                    }
                    if (metadata.@"continue") |token| {
                        continue_token = try self.allocator.dupe(u8, token);
                    }
                } else {
                    json_reader.skipValue() catch |err| return mapOuterError(err);
                }
            }

            if (!saw_items) return error.MissingItems;
            const final = json_reader.next() catch |err| return mapOuterError(err);
            if (final != .end_of_document) return error.MalformedOuterJson;
            if (batch.items.len != 0) try on_batch(self.batch_context, batch.items);

            return .{
                .allocator = self.allocator,
                .resource_version = resource_version orelse return error.MissingResourceVersion,
                .continue_token = continue_token orelse try self.allocator.dupe(u8, ""),
            };
        }
    };

    var parser: Parser = .{
        .allocator = allocator,
        .options = options,
        .batch_context = batch_context,
    };
    try transport.get(request, &parser, Parser.receive);
    return parser.result orelse error.CallbackNotInvoked;
}

fn nextOuter(reader: *std.json.Reader) !std.json.Token {
    return reader.next();
}

fn mapOuterError(err: anyerror) anyerror {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ReadFailed => error.ReadFailed,
        error.ValueTooLong => error.ObjectTooLarge,
        else => error.MalformedOuterJson,
    };
}

fn mapItemError(err: anyerror) anyerror {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ReadFailed => error.ReadFailed,
        error.ValueTooLong => error.ObjectTooLarge,
        else => error.MalformedItem,
    };
}

fn freeAllocatedToken(allocator: std.mem.Allocator, token: std.json.Token) void {
    switch (token) {
        .allocated_number, .allocated_string => |value| allocator.free(value),
        else => {},
    }
}

const TestItem = struct {
    metadata: struct {
        name: []const u8,
    },
    padding: ?[]const u8 = null,
};

const ManualClock = struct {
    now: u64 = 0,
    advance_per_read: u64 = 0,

    fn clock(self: *ManualClock) Clock {
        return .{ .ptr = self, .now_ns_fn = read };
    }

    fn read(erased: *anyopaque) u64 {
        const self: *ManualClock = @ptrCast(@alignCast(erased));
        const value = self.now;
        self.now +%= self.advance_per_read;
        return value;
    }
};

const BatchCapture = struct {
    allocator: std.mem.Allocator,
    names: std.ArrayList([]u8) = .empty,
    batch_sizes: std.ArrayList(usize) = .empty,

    fn deinit(self: *BatchCapture) void {
        for (self.names.items) |name| self.allocator.free(name);
        self.names.deinit(self.allocator);
        self.batch_sizes.deinit(self.allocator);
    }

    fn receive(self: *BatchCapture, items: []const TestItem) !void {
        try self.batch_sizes.append(self.allocator, items.len);
        for (items) |item| {
            const name = try self.allocator.dupe(u8, item.metadata.name);
            errdefer self.allocator.free(name);
            try self.names.append(self.allocator, name);
        }
    }
};

fn runBody(
    allocator: std.mem.Allocator,
    body: []const u8,
    chunks: []const usize,
    clock: *ManualClock,
    capture: *BatchCapture,
) !Result {
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const ResponseScript = @import("FakeTransport.zig").ResponseScript;
    const scripts = [_]ResponseScript{.{ .body = body, .chunk_sizes = chunks }};
    var fake = FakeTransport.init(allocator, &scripts);
    defer fake.deinit();
    return stream(
        TestItem,
        allocator,
        fake.transport(),
        try transport_mod.ReadRequest.init("/api/v1/pods"),
        .{ .clock = clock.clock() },
        capture,
        BatchCapture.receive,
    );
}

test "empty list and metadata before or after items return owned resourceVersion" {
    var clock: ManualClock = .{};
    var capture: BatchCapture = .{ .allocator = std.testing.allocator };
    defer capture.deinit();

    var first = try runBody(
        std.testing.allocator,
        "{\"metadata\":{\"resourceVersion\":\"10\"},\"items\":[]}",
        &.{ 1, 2, 3, 1, 7 },
        &clock,
        &capture,
    );
    defer first.deinit();
    try std.testing.expectEqualStrings("10", first.resource_version);
    try std.testing.expectEqual(@as(usize, 0), capture.batch_sizes.items.len);

    var second = try runBody(
        std.testing.allocator,
        "{\"unknown\":{\"deep\":[1,2]},\"items\":[],\"metadata\":{\"resourceVersion\":\"11\"}}",
        &([_]usize{1} ** 8),
        &clock,
        &capture,
    );
    defer second.deinit();
    try std.testing.expectEqualStrings("11", second.resource_version);
}

test "LIST metadata returns an owned opaque continue token" {
    const allocator = std.testing.allocator;
    var clock = ManualClock{};
    var capture = BatchCapture{ .allocator = allocator };
    defer capture.deinit();
    var result = try runBody(
        allocator,
        "{\"metadata\":{\"resourceVersion\":\"42\",\"continue\":\"a/b+c=\"},\"items\":[]}",
        &.{},
        &clock,
        &capture,
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("42", result.resource_version);
    try std.testing.expectEqualStrings("a/b+c=", result.continue_token);
}

test "batching emits at 128 objects and timer boundary" {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(std.testing.allocator);
    try body.appendSlice(std.testing.allocator, "{\"items\":[");
    for (0..129) |index| {
        if (index != 0) try body.append(std.testing.allocator, ',');
        var item_buffer: [64]u8 = undefined;
        const item = try std.fmt.bufPrint(
            &item_buffer,
            "{{\"metadata\":{{\"name\":\"p{d}\"}}}}",
            .{index},
        );
        try body.appendSlice(std.testing.allocator, item);
    }
    try body.appendSlice(
        std.testing.allocator,
        "],\"metadata\":{\"resourceVersion\":\"20\"}}",
    );

    var clock: ManualClock = .{};
    var capture: BatchCapture = .{ .allocator = std.testing.allocator };
    defer capture.deinit();
    var result = try runBody(std.testing.allocator, body.items, &.{}, &clock, &capture);
    defer result.deinit();
    try std.testing.expectEqualSlices(usize, &.{ 128, 1 }, capture.batch_sizes.items);

    var timer_clock: ManualClock = .{ .advance_per_read = batch_interval_ns };
    var timer_capture: BatchCapture = .{ .allocator = std.testing.allocator };
    defer timer_capture.deinit();
    var timer_result = try runBody(
        std.testing.allocator,
        "{\"items\":[{\"metadata\":{\"name\":\"a\"}},{\"metadata\":{\"name\":\"b\"}}],\"metadata\":{\"resourceVersion\":\"21\"}}",
        &.{},
        &timer_clock,
        &timer_capture,
    );
    defer timer_result.deinit();
    try std.testing.expectEqualSlices(usize, &.{ 1, 1 }, timer_capture.batch_sizes.items);
}

test "malformed outer item shape and missing resourceVersion are bounded errors" {
    const Case = struct { body: []const u8, expected: anyerror };
    const cases = [_]Case{
        .{ .body = "[]", .expected = error.MalformedOuterJson },
        .{ .body = "{\"metadata\":{\"resourceVersion\":\"1\"}}", .expected = error.MissingItems },
        .{ .body = "{\"items\":{},\"metadata\":{\"resourceVersion\":\"1\"}}", .expected = error.ItemsNotArray },
        .{ .body = "{\"items\":[nope],\"metadata\":{\"resourceVersion\":\"1\"}}", .expected = error.MalformedItem },
        .{ .body = "{\"items\":[]}", .expected = error.MissingResourceVersion },
        .{
            .body = "{\"items\":[],\"metadata\":{\"resourceVersion\":\"\"}}",
            .expected = error.MissingResourceVersion,
        },
        .{
            .body = "{\"items\":[],\"metadata\":{\"resourceVersion\":null}}",
            .expected = error.MissingResourceVersion,
        },
        .{ .body = "{\"items\":[],\"metadata\":{}}", .expected = error.MissingResourceVersion },
        .{ .body = "{\"items\":[]", .expected = error.MalformedOuterJson },
    };
    for (cases) |case| {
        var clock: ManualClock = .{};
        var capture: BatchCapture = .{ .allocator = std.testing.allocator };
        defer capture.deinit();
        try std.testing.expectError(
            case.expected,
            runBody(std.testing.allocator, case.body, &.{}, &clock, &capture),
        );
    }
}

test "four MiB object boundary accepts exact and rejects one byte over" {
    const prefix = "{\"metadata\":{\"name\":\"large\"},\"padding\":\"";
    const suffix = "\"}";

    for ([_]usize{ max_object_bytes, max_object_bytes + 1 }) |object_size| {
        var object = try std.ArrayList(u8).initCapacity(std.testing.allocator, object_size);
        defer object.deinit(std.testing.allocator);
        try object.appendSlice(std.testing.allocator, prefix);
        const padding_len = object_size - prefix.len - suffix.len;
        try object.resize(std.testing.allocator, object.items.len + padding_len);
        @memset(object.items[prefix.len..], 'x');
        try object.appendSlice(std.testing.allocator, suffix);

        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(std.testing.allocator);
        try body.appendSlice(std.testing.allocator, "{\"items\":[");
        try body.appendSlice(std.testing.allocator, object.items);
        try body.appendSlice(
            std.testing.allocator,
            "],\"metadata\":{\"resourceVersion\":\"30\"}}",
        );

        var clock: ManualClock = .{};
        var capture: BatchCapture = .{ .allocator = std.testing.allocator };
        defer capture.deinit();
        const result = runBody(std.testing.allocator, body.items, &.{ 17, 4093, 1 }, &clock, &capture);
        if (object_size == max_object_bytes) {
            var accepted = try result;
            accepted.deinit();
            try std.testing.expectEqual(@as(usize, 1), capture.names.items.len);
        } else {
            try std.testing.expectError(error.ObjectTooLarge, result);
        }
    }
}

test "multi-megabyte list streams in bounded batches without retaining objects" {
    var body: std.ArrayList(u8) = .empty;
    defer body.deinit(std.testing.allocator);
    try body.appendSlice(std.testing.allocator, "{\"items\":[");
    const padding = "x" ** 4096;
    for (0..1536) |index| {
        if (index != 0) try body.append(std.testing.allocator, ',');
        try body.appendSlice(std.testing.allocator, "{\"metadata\":{\"name\":\"p\"},\"padding\":\"");
        try body.appendSlice(std.testing.allocator, padding);
        try body.appendSlice(std.testing.allocator, "\"}");
    }
    try body.appendSlice(
        std.testing.allocator,
        "],\"metadata\":{\"resourceVersion\":\"40\"}}",
    );
    try std.testing.expect(body.items.len > 6 << 20);

    var clock: ManualClock = .{};
    var capture: BatchCapture = .{ .allocator = std.testing.allocator };
    defer capture.deinit();
    var result = try runBody(
        std.testing.allocator,
        body.items,
        &.{ 31, 4093, 7, 16381 },
        &clock,
        &capture,
    );
    defer result.deinit();
    try std.testing.expectEqual(@as(usize, 1536), capture.names.items.len);
    try std.testing.expectEqual(@as(usize, 12), capture.batch_sizes.items.len);
}

test "response-size fallback is explicit and cancellation propagates" {
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const ResponseScript = @import("FakeTransport.zig").ResponseScript;
    const scripts = [_]ResponseScript{
        .{ .status = .payload_too_large },
        .{ .before_callback_error = .canceled },
    };
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    var clock: ManualClock = .{};
    var capture: BatchCapture = .{ .allocator = std.testing.allocator };
    defer capture.deinit();

    var request = try transport_mod.ReadRequest.init("/large");
    request.pagination_fallback = .response_size_only;
    try std.testing.expectError(
        error.ResponseTooLarge,
        stream(
            TestItem,
            std.testing.allocator,
            fake.transport(),
            request,
            .{ .clock = clock.clock() },
            &capture,
            BatchCapture.receive,
        ),
    );
    try std.testing.expect(request.mayPaginateAfter(error.ResponseTooLarge));
    try std.testing.expectError(
        error.Canceled,
        stream(
            TestItem,
            std.testing.allocator,
            fake.transport(),
            try transport_mod.ReadRequest.init("/canceled"),
            .{ .clock = clock.clock() },
            &capture,
            BatchCapture.receive,
        ),
    );
}

test "truncated reads propagate and allocation failures clean up" {
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const ResponseScript = @import("FakeTransport.zig").ResponseScript;
    const body = "{\"items\":[{\"metadata\":{\"name\":\"a\"}}],\"metadata\":{\"resourceVersion\":\"1\"}}";
    const scripts = [_]ResponseScript{.{
        .body = body,
        .read_failure = .truncated,
        .fail_after = 20,
    }};
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    var clock: ManualClock = .{};
    var capture: BatchCapture = .{ .allocator = std.testing.allocator };
    defer capture.deinit();
    try std.testing.expectError(
        error.ReadFailed,
        stream(
            TestItem,
            std.testing.allocator,
            fake.transport(),
            try transport_mod.ReadRequest.init("/truncated"),
            .{ .clock = clock.clock() },
            &capture,
            BatchCapture.receive,
        ),
    );

    const AllocationTest = struct {
        fn run(allocator: std.mem.Allocator, json: []const u8) !void {
            var local_clock: ManualClock = .{};
            var local_capture: BatchCapture = .{ .allocator = allocator };
            defer local_capture.deinit();
            var result = try runBody(allocator, json, &.{ 1, 3, 2 }, &local_clock, &local_capture);
            result.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        AllocationTest.run,
        .{body},
    );
}
