//! Streamed list reads over a shared HTTP/2 connection with the list retry
//! policy applied. Requests that are not streamed lists are rejected so the
//! caller routes them elsewhere.

const std = @import("std");
const klient = @import("klient");
const klient_list = @import("klient-list");
const task15 = @import("../task15_diagnostics.zig");
const transport_mod = @import("ReadTransport.zig");
const stream_list = @import("StreamList.zig");

const policy = klient.list_policy;
const ReadTransport = transport_mod.ReadTransport;
const ReadRequest = transport_mod.ReadRequest;
const ReadCallback = transport_mod.ReadCallback;

pub const ListClient = klient_list.ListClient;
pub const Credentials = klient_list.Credentials;

pub const RefreshHook = struct {
    context: *anyopaque,
    /// Returned credentials stay valid until the next call on the same context.
    refresh_fn: *const fn (*anyopaque) anyerror!Credentials,
};

pub const ListClientTransport = struct {
    client: *ListClient,
    allocator: std.mem.Allocator,
    io: std.Io,
    context_name: []const u8 = "",
    cancel_requested: ?*const std.atomic.Value(bool) = null,
    refresh: ?RefreshHook = null,

    pub fn transport(self: *ListClientTransport) ReadTransport {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: ReadTransport.VTable = .{ .get = get };

    fn get(
        erased: *anyopaque,
        request: ReadRequest,
        context: *anyopaque,
        callback: ReadCallback,
    ) anyerror!void {
        const self: *ListClientTransport = @ptrCast(@alignCast(erased));
        try transport_mod.validateReadPath(request.path);
        if (task15.isLiveMode() and self.context_name.len == 0)
            return error.Task15ContextRequired;
        if (request.audit_method != .GET or !request.streamed_list) return error.UnsupportedListRequest;
        const sanitized = try task15.enforceRequest(.GET, request.path);
        var writer = task15.Writer.initFromEnv();
        var audit: Audit = .{ .writer = &writer, .context_name = self.context_name, .sanitized = sanitized };
        audit.emit(null, "start");

        var consumer: Consumer = .{
            .transport = self,
            .context = context,
            .callback = callback,
            .audit = &audit,
        };
        var driver: klient_list.Driver(Hooks) = .{
            .client = self.client,
            .hooks = .{ .transport = self, .busy = request.busy },
        };
        const accept: policy.Accept = if (request.accepts_protobuf) .protobuf_first else .json;
        policy.runWithAccept(self.allocator, request.path, accept, &driver, &consumer) catch |err| {
            if (!consumer.delivered) audit.emit(null, if (err == error.Canceled or self.isCanceled())
                "canceled"
            else
                "transport-terminal");
            return err;
        };
    }

    fn isCanceled(self: *const ListClientTransport) bool {
        const flag = self.cancel_requested orelse return false;
        return flag.load(.acquire);
    }

    const Consumer = struct {
        transport: *ListClientTransport,
        context: *anyopaque,
        callback: ReadCallback,
        audit: *Audit,
        delivered: bool = false,
        continue_token: []const u8 = "",

        pub fn page(
            self: *Consumer,
            start: policy.PageStart,
            meta: policy.Meta,
            reader: *std.Io.Reader,
        ) anyerror![]const u8 {
            if (self.transport.isCanceled()) return error.Canceled;
            self.delivered = true;
            self.continue_token = "";
            const success = meta.status.class() == .success;
            self.callback(self.context, .{
                .status = meta.status,
                .retry_after_seconds = meta.retry_after_seconds,
                .content_type = meta.content_type,
                .page = if (start.first_page) .first else .next,
                .continue_sink = &self.continue_token,
            }, reader) catch |err| {
                self.audit.emit(@backingInt(meta.status), if (!success)
                    "terminal-or-retry"
                else if (err == error.Canceled or self.transport.isCanceled())
                    "canceled"
                else
                    "callback-terminal");
                return err;
            };
            self.audit.emit(@backingInt(meta.status), if (success) "none" else "terminal-or-retry");
            return self.continue_token;
        }

        pub fn isHttp1Retryable(_: *Consumer, err: anyerror) bool {
            return stream_list.isHttp1Retryable(err);
        }
    };

    const Hooks = struct {
        transport: *ListClientTransport,
        busy: ?transport_mod.BusyNotice = null,

        pub fn refresh(self: Hooks) !Credentials {
            const hook = self.transport.refresh orelse return error.HttpUnauthorized;
            return hook.refresh_fn(hook.context);
        }

        pub fn wait(self: Hooks, seconds: u32) !void {
            const slice_ms = 100;
            var remaining: u64 = @as(u64, seconds) * std.time.ms_per_s;
            var shown: ?u64 = null;
            while (remaining > 0) : (remaining -|= slice_ms) {
                if (self.transport.isCanceled()) return error.Canceled;
                const left = (remaining + std.time.ms_per_s - 1) / std.time.ms_per_s;
                if (self.busy) |busy| if (shown != left) {
                    try busy.notify(@intCast(left));
                    shown = left;
                };
                try self.transport.io.sleep(.{ .nanoseconds = slice_ms * std.time.ns_per_ms }, .awake);
            }
            if (self.busy) |busy| try busy.notify(0);
        }
    };
};

/// Errors after which another transport may still serve the list.
pub fn isTransportFailure(err: anyerror) bool {
    return switch (err) {
        error.ConnectionRefused,
        error.UnknownHost,
        error.Timeout,
        error.TlsFailure,
        error.ConnectionReset,
        error.Http2ProtocolError,
        error.HttpStreamReset,
        error.TruncatedResponse,
        error.NoCaBundle,
        error.ClientShutDown,
        error.CurlFailed,
        error.NoResponse,
        => true,
        else => false,
    };
}

const Audit = struct {
    writer: *task15.Writer,
    context_name: []const u8,
    sanitized: task15.SanitizedRequest,

    fn emit(self: *Audit, status: ?u16, retry_class: []const u8) void {
        self.writer.emit(.{
            .event = .request_audit,
            .context = self.context_name,
            .scope = self.sanitized.scope,
            .family = task15.familyForResource(self.sanitized.resource),
            .method = .GET,
            .api_group = self.sanitized.api_group,
            .resource = self.sanitized.resource,
            .subresource = self.sanitized.subresource,
            .endpoint_class = self.sanitized.endpoint_class,
            .identity_fingerprint = self.sanitized.identity_fingerprint,
            .query_fingerprint = self.sanitized.query_fingerprint,
            .status = status,
            .retry_class = retry_class,
        });
    }
};

test "requests that are not streamed lists are left to other transports" {
    var adapter: ListClientTransport = .{
        .client = undefined,
        .allocator = std.testing.allocator,
        .io = std.testing.io,
        .context_name = "contract",
    };
    const Callback = struct {
        fn receive(_: *anyopaque, _: transport_mod.ResponseMeta, _: *std.Io.Reader) anyerror!void {
            return error.CallbackReached;
        }
    };
    var callback_context: u8 = 0;
    try std.testing.expectError(error.UnsupportedListRequest, adapter.transport().get(
        try ReadRequest.init("/api/v1/pods"),
        &callback_context,
        Callback.receive,
    ));
    try std.testing.expectError(error.UnsupportedListRequest, adapter.transport().get(
        try ReadRequest.watch("/api/v1/pods"),
        &callback_context,
        Callback.receive,
    ));
}

test "a throttled wait counts down whole seconds and then clears" {
    var adapter: ListClientTransport = .{
        .client = undefined,
        .allocator = std.testing.allocator,
        .io = std.testing.io,
    };
    const Capture = struct {
        seen: [8]u32 = undefined,
        len: usize = 0,

        fn notify(raw: *anyopaque, seconds: u32) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.seen[self.len] = seconds;
            self.len += 1;
        }
    };
    var capture: Capture = .{};
    const hooks: ListClientTransport.Hooks = .{
        .transport = &adapter,
        .busy = .{ .context = &capture, .notify_fn = Capture.notify },
    };
    try hooks.wait(2);
    try std.testing.expectEqualSlices(u32, &.{ 2, 1, 0 }, capture.seen[0..capture.len]);
}

test "only connection-level failures fall through to another transport" {
    try std.testing.expect(isTransportFailure(error.ConnectionRefused));
    try std.testing.expect(isTransportFailure(error.Http2ProtocolError));
    try std.testing.expect(!isTransportFailure(error.Canceled));
    try std.testing.expect(!isTransportFailure(error.HttpForbidden));
    try std.testing.expect(!isTransportFailure(error.MalformedItem));
}
