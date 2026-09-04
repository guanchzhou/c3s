const std = @import("std");
const transport_mod = @import("ReadTransport.zig");

const ReadCallback = transport_mod.ReadCallback;
const ReadRequest = transport_mod.ReadRequest;
const ReadTransport = transport_mod.ReadTransport;
const ResponseMeta = transport_mod.ResponseMeta;

pub const BeforeCallbackError = enum {
    none,
    canceled,
    scripted,
};

pub const ReadFailure = enum {
    none,
    truncated,
    canceled,
};

pub const ResponseScript = struct {
    status: std.http.Status = .ok,
    body: []const u8 = "",
    content_type: ?[]const u8 = "application/json",
    retry_after_seconds: ?u32 = null,
    chunk_sizes: []const usize = &.{},
    before_callback_error: BeforeCallbackError = .none,
    read_failure: ReadFailure = .none,
    fail_after: ?usize = null,
};

pub const RecordedRequest = struct {
    path: []u8,
    pagination_fallback: transport_mod.PaginationFallback,

    fn deinit(self: RecordedRequest, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }
};

pub const FakeTransport = struct {
    allocator: std.mem.Allocator,
    scripts: []const ResponseScript,
    next_script: usize = 0,
    requests: std.ArrayList(RecordedRequest) = .empty,
    last_read_failure: ReadFailure = .none,

    pub fn init(allocator: std.mem.Allocator, scripts: []const ResponseScript) FakeTransport {
        return .{ .allocator = allocator, .scripts = scripts };
    }

    pub fn deinit(self: *FakeTransport) void {
        for (self.requests.items) |request| request.deinit(self.allocator);
        self.requests.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn transport(self: *FakeTransport) ReadTransport {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: ReadTransport.VTable = .{ .get = get };

    fn get(
        erased: *anyopaque,
        request: ReadRequest,
        context: *anyopaque,
        callback: ReadCallback,
    ) anyerror!void {
        const self: *FakeTransport = @ptrCast(@alignCast(erased));

        try self.record(request);

        try transport_mod.validateReadPath(request.path);
        if (self.next_script >= self.scripts.len) return error.NoScriptedResponse;
        const script = self.scripts[self.next_script];
        self.next_script += 1;
        self.last_read_failure = .none;

        switch (script.before_callback_error) {
            .none => {},
            .canceled => return error.Canceled,
            .scripted => return error.ScriptedTransportFailure,
        }

        var reader = ScriptReader.init(script, &self.last_read_failure);
        reader.bindBuffer();
        return callback(context, .{
            .status = script.status,
            .retry_after_seconds = script.retry_after_seconds,
            .content_type = script.content_type,
        }, &reader.interface);
    }

    fn record(self: *FakeTransport, request: ReadRequest) !void {
        const path_copy = try self.allocator.dupe(u8, request.path);
        errdefer self.allocator.free(path_copy);
        try self.requests.append(self.allocator, .{
            .path = path_copy,
            .pagination_fallback = request.pagination_fallback,
        });
    }
};

const ScriptReader = struct {
    interface: std.Io.Reader,
    body: []const u8,
    position: usize = 0,
    chunk_sizes: []const usize,
    chunk_index: usize = 0,
    failure: ReadFailure,
    fail_after: ?usize,
    observed_failure: *ReadFailure,
    scratch: [4096]u8 = undefined,

    fn init(script: ResponseScript, observed_failure: *ReadFailure) ScriptReader {
        return .{
            .interface = .{
                .vtable = &.{ .stream = stream },
                .buffer = &.{},
                .seek = 0,
                .end = 0,
            },
            .body = script.body,
            .chunk_sizes = script.chunk_sizes,
            .failure = script.read_failure,
            .fail_after = script.fail_after,
            .observed_failure = observed_failure,
        };
    }

    fn bindBuffer(self: *ScriptReader) void {
        self.interface.buffer = &self.scratch;
    }

    fn stream(reader: *std.Io.Reader, writer: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *ScriptReader = @fieldParentPtr("interface", reader);
        const failure_at = self.fail_after orelse self.body.len;
        if (self.position >= failure_at and self.failure != .none) {
            self.observed_failure.* = self.failure;
            return error.ReadFailed;
        }
        if (self.position >= self.body.len) return error.EndOfStream;

        const requested = limit.toInt() orelse self.body.len - self.position;
        const scripted_chunk = if (self.chunk_index < self.chunk_sizes.len)
            self.chunk_sizes[self.chunk_index]
        else
            self.body.len - self.position;
        if (self.chunk_index < self.chunk_sizes.len) self.chunk_index += 1;

        const before_failure = failure_at -| self.position;
        const count = @min(
            requested,
            @min(scripted_chunk, @min(before_failure, self.body.len - self.position)),
        );
        if (count == 0) {
            if (self.failure != .none) {
                self.observed_failure.* = self.failure;
                return error.ReadFailed;
            }
            return error.EndOfStream;
        }

        const written = try writer.write(self.body[self.position..][0..count]);
        self.position += written;
        return written;
    }
};

test "fake records every request and only ever serves the GET vtable entry" {
    const scripts = [_]ResponseScript{ .{}, .{} };
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();

    const vtable_fields = @typeInfo(ReadTransport.VTable).@"struct".fields;
    try std.testing.expectEqual(@as(usize, 1), vtable_fields.len);
    try std.testing.expectEqualStrings("get", vtable_fields[0].name);

    const Capture = struct {
        fn receive(_: *anyopaque, _: ResponseMeta, reader: *std.Io.Reader) anyerror!void {
            try std.testing.expectError(error.EndOfStream, reader.takeByte());
        }
    };
    var byte: u8 = 0;
    try fake.transport().get(try ReadRequest.init("/api/v1/pods"), &byte, Capture.receive);
    try fake.transport().get(
        try ReadRequest.init("/apis/apps/v1/namespaces/ns/deployments/d/scale"),
        &byte,
        Capture.receive,
    );
    try std.testing.expectEqual(@as(usize, 2), fake.requests.items.len);
    try std.testing.expectEqualStrings("/api/v1/pods", fake.requests.items[0].path);
    try std.testing.expectEqualStrings(
        "/apis/apps/v1/namespaces/ns/deployments/d/scale",
        fake.requests.items[1].path,
    );
}

test "fake records and rejects paths that are not origin-relative reads" {
    var fake = FakeTransport.init(std.testing.allocator, &.{.{}});
    defer fake.deinit();

    const Capture = struct {
        fn receive(_: *anyopaque, _: ResponseMeta, _: *std.Io.Reader) anyerror!void {
            return error.CallbackMustNotRun;
        }
    };
    var byte: u8 = 0;
    const invalid = [_][]const u8{
        "//evil.example.com/api/v1/pods",
        "/api/v1/pods#items",
        "/api/v1/pods\r\nGET /api/v1/secrets HTTP/1.1",
        "api/v1/pods",
    };
    for (invalid, 0..) |path, index| {
        try std.testing.expectError(
            error.InvalidReadPath,
            fake.transport().get(.{ .path = path }, &byte, Capture.receive),
        );
        try std.testing.expectEqual(index + 1, fake.requests.items.len);
        try std.testing.expectEqualStrings(path, fake.requests.items[index].path);
    }
}

test "fake exposes status, deterministic chunks, truncation, and cancellation" {
    const scripts = [_]ResponseScript{
        .{
            .status = .partial_content,
            .body = "abcdef",
            .chunk_sizes = &.{ 1, 2, 1, 2 },
        },
        .{
            .body = "abcdef",
            .read_failure = .truncated,
            .fail_after = 3,
        },
        .{ .before_callback_error = .canceled },
    };
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();

    const Capture = struct {
        expected_status: std.http.Status,
        expected_body: []const u8,

        fn receive(erased: *anyopaque, meta: ResponseMeta, reader: *std.Io.Reader) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(erased));
            try std.testing.expectEqual(self.expected_status, meta.status);
            var body: std.ArrayList(u8) = .empty;
            defer body.deinit(std.testing.allocator);
            try reader.appendRemaining(std.testing.allocator, &body, .limited(64));
            try std.testing.expectEqualStrings(self.expected_body, body.items);
        }
    };

    var complete: Capture = .{ .expected_status = .partial_content, .expected_body = "abcdef" };
    try fake.transport().get(try ReadRequest.init("/complete"), &complete, Capture.receive);

    var truncated: Capture = .{ .expected_status = .ok, .expected_body = "" };
    try std.testing.expectError(
        error.ReadFailed,
        fake.transport().get(try ReadRequest.init("/truncated"), &truncated, Capture.receive),
    );
    try std.testing.expectEqual(ReadFailure.truncated, fake.last_read_failure);

    try std.testing.expectError(
        error.Canceled,
        fake.transport().get(try ReadRequest.init("/canceled"), &complete, Capture.receive),
    );
}
