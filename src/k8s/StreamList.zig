const std = @import("std");
const klient = @import("klient");
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
        const Self = @This();

        allocator: std.mem.Allocator,
        options: Options,
        batch_context: @TypeOf(batch_context),
        result: ?Result = null,
        responses: usize = 0,

        fn receive(
            erased: *anyopaque,
            meta: transport_mod.ResponseMeta,
            body_reader: *std.Io.Reader,
        ) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(erased));
            self.responses += 1;
            if (self.responses > 1 and meta.page == .first) try restartBatches(self.batch_context);
            if (self.result) |*previous| {
                previous.deinit();
                self.result = null;
            }
            try self.parseResponse(meta, body_reader);
            if (meta.continue_sink) |sink| sink.* = self.result.?.continue_token;
        }

        fn notifyBusy(erased: *anyopaque, seconds: u32) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(erased));
            try self.batch_context.busy(seconds);
        }

        fn parseResponse(
            self: *@This(),
            meta: transport_mod.ResponseMeta,
            body_reader: *std.Io.Reader,
        ) anyerror!void {
            if (meta.status == .payload_too_large) return error.ResponseTooLarge;
            if (meta.status.class() != .success) return switch (meta.status) {
                .unauthorized => error.HttpUnauthorized,
                .forbidden => error.HttpForbidden,
                .not_found => error.HttpNotFound,
                .gone => error.HttpGone,
                .too_many_requests => error.HttpThrottled,
                else => error.HttpStatus,
            };
            if (meta.content_type) |value| {
                if (klient.protobuf.isContentType(value)) {
                    if (comptime !klient.protobuf.supports(T)) return error.UnsupportedContentType;
                    self.result = try self.parseProtobuf(body_reader);
                    return;
                }
            }
            self.result = try self.parse(body_reader);
        }

        /// Collects decoded objects and hands them to `on_batch` every
        /// `batch_size` objects or `batch_interval`, whichever comes first.
        /// Objects are allocated from `objects`, which is reset after each batch.
        const Batcher = struct {
            parser: *Self,
            items: std.ArrayList(T) = .empty,
            objects: std.heap.ArenaAllocator,
            started: u64,

            fn init(parser: *Self) Batcher {
                return .{
                    .parser = parser,
                    .objects = .init(parser.allocator),
                    .started = parser.options.clock.nowNs(),
                };
            }

            fn deinit(self: *Batcher) void {
                self.items.deinit(self.parser.allocator);
                self.objects.deinit();
            }

            fn add(self: *Batcher, item: T) !void {
                try self.items.append(self.parser.allocator, item);
                const now = self.parser.options.clock.nowNs();
                if (self.items.items.len >= self.parser.options.batch_size or
                    now -| self.started >= self.parser.options.batch_interval)
                {
                    try on_batch(self.parser.batch_context, self.items.items);
                    self.items.clearRetainingCapacity();
                    _ = self.objects.reset(.{ .retain_with_limit = self.parser.options.max_object_size });
                    self.started = now;
                }
            }

            fn finish(self: *Batcher) !void {
                if (self.items.items.len != 0) try on_batch(self.parser.batch_context, self.items.items);
            }
        };

        fn parseProtobuf(self: *@This(), body_reader: *std.Io.Reader) !Result {
            var batcher: Batcher = .init(self);
            defer batcher.deinit();
            var decoder = klient.protobuf.ListDecoder(T).init(
                self.allocator,
                body_reader,
                .{ .max_object_size = self.options.max_object_size },
            ) catch |err| return mapProtobufError(err);
            defer decoder.deinit();
            while (decoder.next(batcher.objects.allocator()) catch |err| return mapProtobufError(err)) |item| {
                try batcher.add(item);
            }
            try batcher.finish();

            const list_meta = decoder.listMeta();
            const resource_version = try self.allocator.dupe(
                u8,
                list_meta.resource_version orelse return error.MissingResourceVersion,
            );
            errdefer self.allocator.free(resource_version);
            return .{
                .allocator = self.allocator,
                .resource_version = resource_version,
                .continue_token = try self.allocator.dupe(u8, list_meta.continue_token orelse ""),
            };
        }

        fn parse(self: *@This(), body_reader: *std.Io.Reader) !Result {
            var json_reader = std.json.Reader.init(self.allocator, body_reader);
            defer json_reader.deinit();
            var diagnostics: std.json.Diagnostics = .{};
            json_reader.enableDiagnostics(&diagnostics);

            var outer_arena = std.heap.ArenaAllocator.init(self.allocator);
            defer outer_arena.deinit();
            var batcher: Batcher = .init(self);
            defer batcher.deinit();

            var resource_version: ?[]u8 = null;
            errdefer if (resource_version) |rv| self.allocator.free(rv);
            var continue_token: ?[]u8 = null;
            errdefer if (continue_token) |token| self.allocator.free(token);
            var saw_items = false;

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
                            batcher.objects.allocator(),
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
                        try batcher.add(item);
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
            try batcher.finish();

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
    var routed = request;
    routed.accepts_protobuf = comptime klient.protobuf.supports(T);
    if (comptime batchHas(@TypeOf(batch_context), "busy"))
        routed.busy = .{ .context = &parser, .notify_fn = Parser.notifyBusy };
    transport.get(routed, &parser, Parser.receive) catch |err| {
        if (parser.result) |*result| result.deinit();
        return err;
    };
    return parser.result orelse error.CallbackNotInvoked;
}

/// Lists that a transport may retry from the start after delivering rows need
/// a batch context with `restart`, which discards the rows delivered so far.
fn restartBatches(batch_context: anytype) !void {
    if (comptime batchHas(@TypeOf(batch_context), "restart")) {
        try batch_context.restart();
    } else {
        return error.ListRestartUnsupported;
    }
}

fn batchHas(comptime Context: type, comptime name: []const u8) bool {
    const Base = switch (@typeInfo(Context)) {
        .pointer => |pointer| pointer.child,
        else => Context,
    };
    return @typeInfo(Base) == .@"struct" and @hasDecl(Base, name);
}

pub fn isHttp1Retryable(err: anyerror) bool {
    return switch (err) {
        error.ProtobufMagicMismatch, error.MalformedProtobuf, error.UnsupportedContentType => true,
        else => false,
    };
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

fn mapProtobufError(err: klient.protobuf.ListError) anyerror {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ReadFailed => error.ReadFailed,
        error.ObjectTooLarge => error.ObjectTooLarge,
        error.BadMagic => error.ProtobufMagicMismatch,
        else => error.MalformedProtobuf,
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
        &(comptime @as([8]usize, @splat(1))),
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
    const padding: [4096]u8 = @splat('x');
    for (0..1536) |index| {
        if (index != 0) try body.append(std.testing.allocator, ',');
        try body.appendSlice(std.testing.allocator, "{\"metadata\":{\"name\":\"p\"},\"padding\":\"");
        try body.appendSlice(std.testing.allocator, &padding);
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

const PodCapture = struct {
    allocator: std.mem.Allocator,
    names: std.ArrayList([]u8) = .empty,
    batch_sizes: std.ArrayList(usize) = .empty,

    fn deinit(self: *PodCapture) void {
        for (self.names.items) |name| self.allocator.free(name);
        self.names.deinit(self.allocator);
        self.batch_sizes.deinit(self.allocator);
    }

    fn receive(self: *PodCapture, pods: []const klient.Pod) !void {
        try self.batch_sizes.append(self.allocator, pods.len);
        for (pods) |pod| {
            const name = try self.allocator.dupe(u8, pod.metadata.name);
            errdefer self.allocator.free(name);
            try self.names.append(self.allocator, name);
        }
    }
};

fn appendVarint(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u64) !void {
    var v = value;
    while (v >= 0x80) : (v >>= 7) try out.append(allocator, @as(u8, @truncate(v)) | 0x80);
    try out.append(allocator, @truncate(v));
}

fn appendBytesField(out: *std.ArrayList(u8), allocator: std.mem.Allocator, number: u32, bytes: []const u8) !void {
    try appendVarint(out, allocator, (@as(u64, number) << 3) | 2);
    try appendVarint(out, allocator, bytes.len);
    try out.appendSlice(allocator, bytes);
}

/// `k8s\x00` + runtime.Unknown{raw: PodList{metadata, items}}, each Pod
/// carrying only metadata.name.
fn protobufPodList(allocator: std.mem.Allocator, names: []const []const u8, resource_version: []const u8, continue_token: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    var scratch: std.ArrayList(u8) = .empty;
    defer scratch.deinit(allocator);
    try appendBytesField(&scratch, allocator, 2, resource_version);
    if (continue_token.len != 0) try appendBytesField(&scratch, allocator, 3, continue_token);
    try appendBytesField(&list, allocator, 1, scratch.items);
    for (names) |name| {
        scratch.clearRetainingCapacity();
        var meta: std.ArrayList(u8) = .empty;
        defer meta.deinit(allocator);
        try appendBytesField(&meta, allocator, 1, name);
        try appendBytesField(&scratch, allocator, 1, meta.items);
        try appendBytesField(&list, allocator, 2, scratch.items);
    }
    var body: std.ArrayList(u8) = .empty;
    errdefer body.deinit(allocator);
    try body.appendSlice(allocator, klient.protobuf.magic);
    try appendBytesField(&body, allocator, 2, list.items);
    return body.toOwnedSlice(allocator);
}

const protobuf_content_type = "application/vnd.kubernetes.protobuf";

fn runPodBody(allocator: std.mem.Allocator, script: @import("FakeTransport.zig").ResponseScript, capture: *PodCapture) !Result {
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const scripts = [_]@import("FakeTransport.zig").ResponseScript{script};
    var fake = FakeTransport.init(allocator, &scripts);
    defer fake.deinit();
    var clock: ManualClock = .{};
    return stream(
        klient.Pod,
        allocator,
        fake.transport(),
        try transport_mod.ReadRequest.init("/api/v1/pods"),
        .{ .clock = clock.clock() },
        capture,
        PodCapture.receive,
    );
}

test "Protobuf list bodies stream into the same batches as JSON" {
    const allocator = std.testing.allocator;
    var names: [129][]const u8 = undefined;
    var name_buffers: [129][8]u8 = undefined;
    for (&names, &name_buffers, 0..) |*name, *buffer, index| name.* = try std.fmt.bufPrint(buffer, "p{d}", .{index});
    const body = try protobufPodList(allocator, &names, "77", "next-page");
    defer allocator.free(body);

    var capture: PodCapture = .{ .allocator = allocator };
    defer capture.deinit();
    var result = try runPodBody(allocator, .{
        .body = body,
        .content_type = protobuf_content_type,
        .chunk_sizes = &.{ 1, 3, 5, 64, 7 },
    }, &capture);
    defer result.deinit();
    try std.testing.expectEqualSlices(usize, &.{ 128, 1 }, capture.batch_sizes.items);
    try std.testing.expectEqualStrings("p0", capture.names.items[0]);
    try std.testing.expectEqualStrings("p128", capture.names.items[128]);
    try std.testing.expectEqualStrings("77", result.resource_version);
    try std.testing.expectEqualStrings("next-page", result.continue_token);
}

test "Protobuf decode failures are distinct from JSON ones" {
    const allocator = std.testing.allocator;
    const body = try protobufPodList(allocator, &.{ "a", "b" }, "5", "");
    defer allocator.free(body);
    const no_version = try protobufPodList(allocator, &.{"a"}, "", "");
    defer allocator.free(no_version);

    const Case = struct { script: @import("FakeTransport.zig").ResponseScript, expected: anyerror };
    const cases = [_]Case{
        .{ .script = .{ .body = "{\"items\":[]}", .content_type = protobuf_content_type }, .expected = error.ProtobufMagicMismatch },
        .{ .script = .{ .body = body[0 .. body.len - 2], .content_type = protobuf_content_type }, .expected = error.MalformedProtobuf },
        .{ .script = .{ .body = no_version, .content_type = protobuf_content_type }, .expected = error.MissingResourceVersion },
    };
    for (cases) |case| {
        var capture: PodCapture = .{ .allocator = allocator };
        defer capture.deinit();
        try std.testing.expectError(case.expected, runPodBody(allocator, case.script, &capture));
    }

    var clock: ManualClock = .{};
    var capture: BatchCapture = .{ .allocator = allocator };
    defer capture.deinit();
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const scripts = [_]@import("FakeTransport.zig").ResponseScript{.{ .body = body, .content_type = protobuf_content_type }};
    var fake = FakeTransport.init(allocator, &scripts);
    defer fake.deinit();
    try std.testing.expectError(error.UnsupportedContentType, stream(
        TestItem,
        allocator,
        fake.transport(),
        try transport_mod.ReadRequest.init("/api/v1/pods"),
        .{ .clock = clock.clock() },
        &capture,
        BatchCapture.receive,
    ));
}

test "Protobuf path cleans up on every allocation failure" {
    const body = try protobufPodList(std.testing.allocator, &.{ "a", "b", "c" }, "9", "tok");
    defer std.testing.allocator.free(body);
    const AllocationTest = struct {
        fn run(allocator: std.mem.Allocator, bytes: []const u8) !void {
            var capture: PodCapture = .{ .allocator = allocator };
            defer capture.deinit();
            var result = try runPodBody(allocator, .{ .body = bytes, .content_type = protobuf_content_type, .chunk_sizes = &.{ 2, 5 } }, &capture);
            result.deinit();
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, AllocationTest.run, .{body});
}

const ScriptedPage = struct {
    page: @FieldType(transport_mod.ResponseMeta, "page"),
    body: []const u8,
    fail: bool = false,
};

/// Replays several responses into one `get`, the way a paging or retrying
/// list transport does, and records the continue token each page reported.
const PagedTransport = struct {
    pages: []const ScriptedPage,
    token_bytes: [4][16]u8 = undefined,
    tokens: [4][]const u8 = undefined,
    token_count: usize = 0,
    busy_seconds: ?u32 = null,
    accepts_protobuf: ?bool = null,

    fn transport(self: *PagedTransport) transport_mod.ReadTransport {
        return .{ .ptr = self, .vtable = &.{ .get = get } };
    }

    fn get(
        erased: *anyopaque,
        request: transport_mod.ReadRequest,
        context: *anyopaque,
        callback: transport_mod.ReadCallback,
    ) anyerror!void {
        const self: *PagedTransport = @ptrCast(@alignCast(erased));
        self.accepts_protobuf = request.accepts_protobuf;
        if (self.busy_seconds) |seconds| if (request.busy) |busy| try busy.notify(seconds);
        for (self.pages) |scripted| {
            var token: []const u8 = "";
            var reader: std.Io.Reader = .fixed(scripted.body);
            callback(context, .{
                .status = .ok,
                .content_type = "application/json",
                .page = scripted.page,
                .continue_sink = &token,
            }, &reader) catch |err| {
                if (!scripted.fail) return err;
                continue;
            };
            const copy = self.token_bytes[self.token_count][0..token.len];
            @memcpy(copy, token);
            self.tokens[self.token_count] = copy;
            self.token_count += 1;
        }
    }
};

const RestartCapture = struct {
    inner: BatchCapture,
    restarts: usize = 0,
    busy_seconds: ?u32 = null,

    fn receive(self: *RestartCapture, items: []const TestItem) !void {
        try self.inner.receive(items);
    }

    pub fn restart(self: *RestartCapture) !void {
        self.restarts += 1;
        for (self.inner.names.items) |name| self.inner.allocator.free(name);
        self.inner.names.clearRetainingCapacity();
    }

    pub fn busy(self: *RestartCapture, seconds: u32) !void {
        self.busy_seconds = seconds;
    }
};

test "continued pages append rows and report each page's continue token" {
    const allocator = std.testing.allocator;
    var paged: PagedTransport = .{ .pages = &.{
        .{ .page = .first, .body = "{\"metadata\":{\"resourceVersion\":\"1\",\"continue\":\"t1\"},\"items\":[{\"metadata\":{\"name\":\"a\"}}]}" },
        .{ .page = .next, .body = "{\"metadata\":{\"resourceVersion\":\"2\"},\"items\":[{\"metadata\":{\"name\":\"b\"}}]}" },
    } };
    var clock: ManualClock = .{};
    var capture: RestartCapture = .{ .inner = .{ .allocator = allocator } };
    defer capture.inner.deinit();
    var result = try stream(TestItem, allocator, paged.transport(), try transport_mod.ReadRequest.list("/api/v1/pods"), .{ .clock = clock.clock() }, &capture, RestartCapture.receive);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 0), capture.restarts);
    try std.testing.expectEqual(@as(usize, 2), capture.inner.names.items.len);
    try std.testing.expectEqualStrings("2", result.resource_version);
    try std.testing.expectEqual(@as(usize, 2), paged.token_count);
    try std.testing.expectEqualStrings("t1", paged.tokens[0]);
    try std.testing.expectEqualStrings("", paged.tokens[1]);
}

test "a new first page after delivered rows restarts the row set" {
    const allocator = std.testing.allocator;
    var paged: PagedTransport = .{ .pages = &.{
        .{ .page = .first, .body = "{\"items\":[{\"metadata\":{\"name\":\"stale\"}},", .fail = true },
        .{ .page = .first, .body = "{\"metadata\":{\"resourceVersion\":\"7\"},\"items\":[{\"metadata\":{\"name\":\"fresh\"}}]}" },
    } };
    var clock: ManualClock = .{};
    var capture: RestartCapture = .{ .inner = .{ .allocator = allocator } };
    defer capture.inner.deinit();
    var result = try stream(TestItem, allocator, paged.transport(), try transport_mod.ReadRequest.list("/api/v1/pods"), .{ .clock = clock.clock() }, &capture, RestartCapture.receive);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), capture.restarts);
    try std.testing.expectEqual(@as(usize, 1), capture.inner.names.items.len);
    try std.testing.expectEqualStrings("fresh", capture.inner.names.items[0]);
    try std.testing.expectEqualStrings("7", result.resource_version);
}

test "a restart without a restart hook fails instead of mixing row sets" {
    const allocator = std.testing.allocator;
    var paged: PagedTransport = .{ .pages = &.{
        .{ .page = .first, .body = "{\"items\":[", .fail = true },
        .{ .page = .first, .body = "{\"metadata\":{\"resourceVersion\":\"7\"},\"items\":[]}" },
    } };
    var clock: ManualClock = .{};
    var capture: BatchCapture = .{ .allocator = allocator };
    defer capture.deinit();
    try std.testing.expectError(error.ListRestartUnsupported, stream(TestItem, allocator, paged.transport(), try transport_mod.ReadRequest.list("/api/v1/pods"), .{ .clock = clock.clock() }, &capture, BatchCapture.receive));
}

test "a throttled wait reaches the batch context" {
    const allocator = std.testing.allocator;
    var paged: PagedTransport = .{ .busy_seconds = 3, .pages = &.{
        .{ .page = .first, .body = "{\"metadata\":{\"resourceVersion\":\"1\"},\"items\":[]}" },
    } };
    var clock: ManualClock = .{};
    var capture: RestartCapture = .{ .inner = .{ .allocator = allocator } };
    defer capture.inner.deinit();
    var result = try stream(TestItem, allocator, paged.transport(), try transport_mod.ReadRequest.list("/api/v1/pods"), .{ .clock = clock.clock() }, &capture, RestartCapture.receive);
    defer result.deinit();

    try std.testing.expectEqual(@as(?u32, 3), capture.busy_seconds);
}

test "only types with a Protobuf schema offer Protobuf" {
    const Discard = struct {
        fn run(comptime T: type) !?bool {
            var paged: PagedTransport = .{ .pages = &.{
                .{ .page = .first, .body = "{\"metadata\":{\"resourceVersion\":\"1\"},\"items\":[]}" },
            } };
            var clock: ManualClock = .{};
            var sink: u8 = 0;
            var result = try stream(T, std.testing.allocator, paged.transport(), try transport_mod.ReadRequest.list("/apis/x"), .{ .clock = clock.clock() }, &sink, receive(T));
            result.deinit();
            return paged.accepts_protobuf;
        }

        fn receive(comptime T: type) fn (*u8, []const T) anyerror!void {
            return struct {
                fn f(_: *u8, _: []const T) anyerror!void {}
            }.f;
        }
    };
    try std.testing.expectEqual(@as(?bool, true), try Discard.run(klient.Pod));
    try std.testing.expectEqual(@as(?bool, true), try Discard.run(klient.types.Service));
    try std.testing.expectEqual(@as(?bool, false), try Discard.run(klient.Gateway));
}
