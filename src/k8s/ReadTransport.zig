const std = @import("std");
const klient = @import("klient");
const task15 = @import("../task15_diagnostics.zig");

pub const PaginationFallback = enum {
    disabled,
    response_size_only,
};

pub const default_max_list_pages: usize = 10_000;

pub const PaginationGuard = struct {
    allocator: std.mem.Allocator,
    max_pages: usize,
    pages: usize = 0,
    seen: std.StringHashMapUnmanaged(void) = .empty,

    pub fn init(allocator: std.mem.Allocator, max_pages: usize) PaginationGuard {
        return .{ .allocator = allocator, .max_pages = max_pages };
    }

    pub fn deinit(self: *PaginationGuard) void {
        var iterator = self.seen.keyIterator();
        while (iterator.next()) |token| self.allocator.free(token.*);
        self.seen.deinit(self.allocator);
    }

    /// Records one completed page and returns whether another page is allowed.
    pub fn advance(self: *PaginationGuard, continue_token: []const u8) !bool {
        self.pages +|= 1;
        if (continue_token.len == 0) return false;
        if (self.pages >= self.max_pages) return error.ListPageLimitExceeded;
        if (self.seen.contains(continue_token)) return error.RepeatedContinueToken;
        const owned = try self.allocator.dupe(u8, continue_token);
        errdefer self.allocator.free(owned);
        try self.seen.put(self.allocator, owned, {});
        return true;
    }
};

pub const ReadRequest = struct {
    path: []const u8,
    pagination_fallback: PaginationFallback = .disabled,
    audit_method: task15.Method = .GET,

    pub fn init(path: []const u8) PathError!ReadRequest {
        try validateReadPath(path);
        return .{ .path = path };
    }

    pub fn watch(path: []const u8) PathError!ReadRequest {
        try validateReadPath(path);
        return .{ .path = path, .audit_method = .WATCH };
    }

    pub fn mayPaginateAfter(self: ReadRequest, err: anyerror) bool {
        return self.pagination_fallback == .response_size_only and err == error.ResponseTooLarge;
    }
};

pub const ResponseMeta = klient.StreamResponseMeta;

pub const ReadCallback = *const fn (
    context: *anyopaque,
    meta: ResponseMeta,
    reader: *std.Io.Reader,
) anyerror!void;

pub const ReadTransport = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        get: *const fn (
            ptr: *anyopaque,
            request: ReadRequest,
            context: *anyopaque,
            callback: ReadCallback,
        ) anyerror!void,
    };

    pub fn get(
        self: ReadTransport,
        request: ReadRequest,
        context: *anyopaque,
        callback: ReadCallback,
    ) !void {
        return self.vtable.get(self.ptr, request, context, callback);
    }
};

pub const KlientTransport = struct {
    client: *klient.K8sClient,
    io: std.Io,
    context_name: []const u8 = "",
    cancel_requested: ?*const std.atomic.Value(bool) = null,

    pub fn transport(self: *KlientTransport) ReadTransport {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: ReadTransport.VTable = .{ .get = get };

    fn get(
        erased: *anyopaque,
        request: ReadRequest,
        context: *anyopaque,
        callback: ReadCallback,
    ) anyerror!void {
        const self: *KlientTransport = @ptrCast(@alignCast(erased));
        try validateReadPath(request.path);
        if (task15.isLiveMode() and self.context_name.len == 0)
            return error.Task15ContextRequired;
        const sanitized = try task15.enforceRequest(request.audit_method, request.path);
        var writer = task15.Writer.initFromEnv();
        writer.emit(.{
            .event = .request_audit,
            .context = self.context_name,
            .scope = sanitized.scope,
            .family = task15.familyForResource(sanitized.resource),
            .method = request.audit_method,
            .api_group = sanitized.api_group,
            .resource = sanitized.resource,
            .subresource = sanitized.subresource,
            .endpoint_class = sanitized.endpoint_class,
            .identity_fingerprint = sanitized.identity_fingerprint,
            .query_fingerprint = sanitized.query_fingerprint,
            .retry_class = "start",
        });
        const Adapter = struct {
            context: *anyopaque,
            callback: ReadCallback,
            writer: *task15.Writer,
            context_name: []const u8,
            sanitized: task15.SanitizedRequest,
            audit_method: task15.Method,
            cancel_requested: ?*const std.atomic.Value(bool),
            response_seen: bool = false,

            fn receive(
                adapter: *@This(),
                meta: klient.StreamResponseMeta,
                reader: *std.Io.Reader,
            ) anyerror!void {
                adapter.response_seen = true;
                const response = ResponseMeta{
                    .status = meta.status,
                    .retry_after_seconds = meta.retry_after_seconds,
                    .content_type = meta.content_type,
                };
                const retry_class = if (meta.status.class() == .success)
                    "none"
                else
                    "terminal-or-retry";
                if (meta.status.class() == .success) {
                    adapter.callback(adapter.context, response, reader) catch |err| {
                        adapter.emitStatus(
                            meta.status,
                            if (err == error.Canceled or adapter.isCanceled())
                                "canceled"
                            else
                                "callback-terminal",
                        );
                        return err;
                    };
                } else {
                    adapter.emitStatus(meta.status, retry_class);
                    return adapter.callback(adapter.context, response, reader);
                }
                adapter.emitStatus(meta.status, retry_class);
            }

            fn emitStatus(
                adapter: *@This(),
                status: std.http.Status,
                retry_class: []const u8,
            ) void {
                adapter.writer.emit(.{
                    .event = .request_audit,
                    .context = adapter.context_name,
                    .scope = adapter.sanitized.scope,
                    .family = task15.familyForResource(adapter.sanitized.resource),
                    .method = adapter.audit_method,
                    .api_group = adapter.sanitized.api_group,
                    .resource = adapter.sanitized.resource,
                    .subresource = adapter.sanitized.subresource,
                    .endpoint_class = adapter.sanitized.endpoint_class,
                    .identity_fingerprint = adapter.sanitized.identity_fingerprint,
                    .query_fingerprint = adapter.sanitized.query_fingerprint,
                    .status = @intFromEnum(status),
                    .retry_class = retry_class,
                });
            }

            fn isCanceled(adapter: *@This()) bool {
                const flag = adapter.cancel_requested orelse return false;
                return flag.load(.acquire);
            }
        };
        var adapter: Adapter = .{
            .context = context,
            .callback = callback,
            .writer = &writer,
            .context_name = self.context_name,
            .sanitized = sanitized,
            .audit_method = request.audit_method,
            .cancel_requested = self.cancel_requested,
        };
        self.client.streamGet(
            self.io,
            request.path,
            .{ .pretty = false },
            &adapter,
            Adapter.receive,
        ) catch |err| {
            if (adapter.response_seen) return err;
            writer.emit(.{
                .event = .request_audit,
                .context = self.context_name,
                .scope = sanitized.scope,
                .family = task15.familyForResource(sanitized.resource),
                .method = request.audit_method,
                .api_group = sanitized.api_group,
                .resource = sanitized.resource,
                .subresource = sanitized.subresource,
                .endpoint_class = sanitized.endpoint_class,
                .identity_fingerprint = sanitized.identity_fingerprint,
                .query_fingerprint = sanitized.query_fingerprint,
                .retry_class = if (err == error.Canceled or
                    (self.cancel_requested != null and
                        self.cancel_requested.?.load(.acquire)))
                    "canceled"
                else
                    "transport-terminal",
            });
            return err;
        };
    }
};

pub const CurlConfig = struct {
    server: []const u8,
    token: ?[]const u8 = null,
    ca_pem: ?[]const u8 = null,
    client_cert_pem: ?[]const u8 = null,
    client_key_pem: ?[]const u8 = null,
};

pub const TransportAdapter = union(enum) {
    klient: KlientTransport,
    curl: CurlTransport,
    fallback: FallbackTransport,

    pub fn transport(self: *TransportAdapter) ReadTransport {
        return switch (self.*) {
            .klient => |*adapter| adapter.transport(),
            .curl => |*adapter| adapter.transport(),
            .fallback => |*adapter| adapter.transport(),
        };
    }
};

pub const FallbackTransport = struct {
    context: *anyopaque,
    io: std.Io,
    cancel_requested: *const std.atomic.Value(bool),
    get_fn: *const fn (
        *anyopaque,
        std.Io,
        *const std.atomic.Value(bool),
        ReadRequest,
        *anyopaque,
        ReadCallback,
    ) anyerror!void,

    pub fn transport(self: *FallbackTransport) ReadTransport {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: ReadTransport.VTable = .{ .get = get };

    fn get(
        erased: *anyopaque,
        request: ReadRequest,
        callback_context: *anyopaque,
        callback: ReadCallback,
    ) anyerror!void {
        const self: *FallbackTransport = @ptrCast(@alignCast(erased));
        return self.get_fn(
            self.context,
            self.io,
            self.cancel_requested,
            request,
            callback_context,
            callback,
        );
    }
};

pub const CurlTransport = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: CurlConfig,
    context_name: []const u8 = "",
    cancel_requested: ?*const std.atomic.Value(bool) = null,
    callback_error_out: ?*?anyerror = null,
    recoverable_transport_errors: bool = false,

    pub fn transport(self: *CurlTransport) ReadTransport {
        return .{ .ptr = self, .vtable = &vtable };
    }

    const vtable: ReadTransport.VTable = .{ .get = get };

    fn get(
        erased: *anyopaque,
        request: ReadRequest,
        context: *anyopaque,
        callback: ReadCallback,
    ) anyerror!void {
        const self: *CurlTransport = @ptrCast(@alignCast(erased));
        try validateReadPath(request.path);
        if (task15.isLiveMode() and self.context_name.len == 0)
            return error.Task15ContextRequired;
        if (isCanceled(self.cancel_requested)) return error.Canceled;

        const sanitized = try task15.enforceRequest(request.audit_method, request.path);
        var audit_writer = task15.Writer.initFromEnv();
        emitCurlAudit(
            &audit_writer,
            self.context_name,
            request.audit_method,
            sanitized,
            null,
            "start",
        );

        var material = CurlMaterial.stage(self.allocator, self.io, self.config) catch |err| {
            emitCurlAudit(
                &audit_writer,
                self.context_name,
                request.audit_method,
                sanitized,
                null,
                transportFailureClass(self),
            );
            return err;
        };
        defer material.deinit();

        const server = std.mem.trimEnd(u8, self.config.server, "/");
        if (!std.mem.startsWith(u8, server, "https://") or
            std.mem.findScalar(u8, server, '?') != null or
            std.mem.findScalar(u8, server, '#') != null)
        {
            emitCurlAudit(
                &audit_writer,
                self.context_name,
                request.audit_method,
                sanitized,
                null,
                "transport-terminal",
            );
            return error.InvalidApiServer;
        }
        const authority = server["https://".len..][0 .. std.mem.indexOfScalar(
            u8,
            server["https://".len..],
            '/',
        ) orelse server["https://".len..].len];
        if (authority.len == 0 or std.mem.findScalar(u8, authority, '@') != null)
            return error.InvalidApiServer;
        const url = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ server, request.path });
        defer self.allocator.free(url);

        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(self.allocator);
        try argv.appendSlice(self.allocator, &.{
            "curl",
            "-q",
            "--silent",
            "--show-error",
            "--no-buffer",
            "--compressed",
            "--http1.1",
            "--include",
            "--globoff",
            "--proto",
            "=https",
            "--proto-redir",
            "=https",
            "--max-redirs",
            "0",
            "--connect-timeout",
            "0.4",
            "--noproxy",
            "*",
            "--config",
            "-",
        });
        if (material.ca_path) |path| {
            try argv.append(self.allocator, "--cacert");
            try argv.append(self.allocator, path);
        }
        if (material.cert_path) |path| {
            try argv.append(self.allocator, "--cert");
            try argv.append(self.allocator, path);
        }
        if (material.key_path) |path| {
            try argv.append(self.allocator, "--key");
            try argv.append(self.allocator, path);
        }
        try argv.append(self.allocator, url);

        var child = std.process.spawn(self.io, .{
            .argv = argv.items,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .ignore,
            .create_no_window = true,
        }) catch |err| {
            emitCurlAudit(&audit_writer, self.context_name, request.audit_method, sanitized, null, transportFailureClass(self));
            return err;
        };
        defer child.kill(self.io);

        var stdin_buffer: [1024]u8 = undefined;
        var stdin_writer = child.stdin.?.writerStreaming(self.io, &stdin_buffer);
        writeCurlConfig(&stdin_writer.interface, self.config.token) catch |err| {
            emitCurlAudit(&audit_writer, self.context_name, request.audit_method, sanitized, null, transportFailureClass(self));
            return err;
        };
        stdin_writer.flush() catch |err| {
            emitCurlAudit(&audit_writer, self.context_name, request.audit_method, sanitized, null, transportFailureClass(self));
            return err;
        };
        child.stdin.?.close(self.io);
        child.stdin = null;

        var stdout_buffer: [64 << 10]u8 = undefined;
        var stdout_reader = child.stdout.?.readerStreaming(self.io, &stdout_buffer);
        var content_type_buffer: [256]u8 = undefined;
        const meta = parseCurlResponseHeaders(
            &stdout_reader.interface,
            &content_type_buffer,
        ) catch |err| {
            emitCurlAudit(
                &audit_writer,
                self.context_name,
                request.audit_method,
                sanitized,
                null,
                if (err == error.Canceled or isCanceled(self.cancel_requested))
                    "canceled"
                else
                    transportFailureClass(self),
            );
            return err;
        };

        callback(context, meta, &stdout_reader.interface) catch |err| {
            if (self.callback_error_out) |destination| destination.* = err;
            emitCurlAudit(
                &audit_writer,
                self.context_name,
                request.audit_method,
                sanitized,
                @intFromEnum(meta.status),
                if (err == error.Canceled or isCanceled(self.cancel_requested))
                    "canceled"
                else
                    "callback-terminal",
            );
            return err;
        };

        const term = child.wait(self.io) catch |err| {
            emitCurlAudit(
                &audit_writer,
                self.context_name,
                request.audit_method,
                sanitized,
                @intFromEnum(meta.status),
                if (err == error.Canceled or isCanceled(self.cancel_requested))
                    "canceled"
                else
                    transportFailureClass(self),
            );
            return err;
        };
        if (term != .exited or term.exited != 0) {
            emitCurlAudit(
                &audit_writer,
                self.context_name,
                request.audit_method,
                sanitized,
                @intFromEnum(meta.status),
                transportFailureClass(self),
            );
            return if (isCanceled(self.cancel_requested)) error.Canceled else error.CurlFailed;
        }
        emitCurlAudit(
            &audit_writer,
            self.context_name,
            request.audit_method,
            sanitized,
            @intFromEnum(meta.status),
            if (meta.status.class() == .success) "none" else "terminal-or-retry",
        );
    }
};

fn transportFailureClass(self: *const CurlTransport) []const u8 {
    if (isCanceled(self.cancel_requested)) return "canceled";
    return if (self.recoverable_transport_errors) "transport-retry" else "transport-terminal";
}

pub const WatchStream = struct {
    transport: ReadTransport,

    pub fn get(
        self: WatchStream,
        path: []const u8,
        context: *anyopaque,
        callback: ReadCallback,
    ) anyerror!void {
        return self.transport.get(try ReadRequest.watch(path), context, callback);
    }
};

fn isCanceled(flag: ?*const std.atomic.Value(bool)) bool {
    return if (flag) |value| value.load(.acquire) else false;
}

fn emitCurlAudit(
    writer: *task15.Writer,
    context_name: []const u8,
    method: task15.Method,
    sanitized: task15.SanitizedRequest,
    status: ?u16,
    retry_class: []const u8,
) void {
    writer.emit(.{
        .event = .request_audit,
        .context = context_name,
        .scope = sanitized.scope,
        .family = task15.familyForResource(sanitized.resource),
        .method = method,
        .api_group = sanitized.api_group,
        .resource = sanitized.resource,
        .subresource = sanitized.subresource,
        .endpoint_class = sanitized.endpoint_class,
        .identity_fingerprint = sanitized.identity_fingerprint,
        .query_fingerprint = sanitized.query_fingerprint,
        .status = status,
        .retry_class = retry_class,
    });
}

fn writeCurlConfig(writer: *std.Io.Writer, token: ?[]const u8) !void {
    const value = token orelse return;
    try writer.writeAll("header = \"Authorization: Bearer ");
    for (value) |byte| switch (byte) {
        0...31, 127 => return error.InvalidCredential,
        '\\', '"' => {
            try writer.writeByte('\\');
            try writer.writeByte(byte);
        },
        else => try writer.writeByte(byte),
    };
    try writer.writeAll("\"\n");
}

fn parseCurlResponseHeaders(
    reader: *std.Io.Reader,
    content_type_buffer: *[256]u8,
) !ResponseMeta {
    while (true) {
        const raw_status_line = (try reader.takeDelimiter('\n')) orelse
            return error.InvalidHttpResponse;
        const status_line = std.mem.trimEnd(u8, raw_status_line, "\r");
        if (!std.mem.startsWith(u8, status_line, "HTTP/"))
            return error.InvalidHttpResponse;
        var fields = std.mem.tokenizeScalar(u8, status_line, ' ');
        _ = fields.next() orelse return error.InvalidHttpResponse;
        const status_code = try std.fmt.parseInt(u16, fields.next() orelse
            return error.InvalidHttpResponse, 10);
        if (status_code < 100 or status_code > 599) return error.InvalidHttpResponse;

        var retry_after_seconds: ?u32 = null;
        var content_type_len: usize = 0;
        while (true) {
            const raw_line = (try reader.takeDelimiter('\n')) orelse
                return error.InvalidHttpResponse;
            const line = std.mem.trimEnd(u8, raw_line, "\r");
            if (line.len == 0) break;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const name = line[0..colon];
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(name, "retry-after")) {
                retry_after_seconds = std.fmt.parseInt(u32, value, 10) catch null;
            } else if (std.ascii.eqlIgnoreCase(name, "content-type")) {
                content_type_len = @min(value.len, content_type_buffer.len);
                @memcpy(content_type_buffer[0..content_type_len], value[0..content_type_len]);
            }
        }
        if (status_code >= 100 and status_code < 200) continue;
        return .{
            .status = @enumFromInt(status_code),
            .retry_after_seconds = retry_after_seconds,
            .content_type = if (content_type_len > 0)
                content_type_buffer[0..content_type_len]
            else
                null,
        };
    }
}

const CurlMaterial = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    dir_path: []u8,
    ca_path: ?[]u8 = null,
    cert_path: ?[]u8 = null,
    key_path: ?[]u8 = null,

    fn stage(
        allocator: std.mem.Allocator,
        io: std.Io,
        config: CurlConfig,
    ) !CurlMaterial {
        var random: [16]u8 = undefined;
        try io.randomSecure(&random);
        const hex = std.fmt.bytesToHex(random, .lower);
        const dir_path = try std.fmt.allocPrint(allocator, "/tmp/c3s-curl-{s}", .{&hex});
        errdefer allocator.free(dir_path);
        try std.Io.Dir.createDirAbsolute(
            io,
            dir_path,
            std.Io.File.Permissions.fromMode(0o700),
        );
        var result = CurlMaterial{
            .allocator = allocator,
            .io = io,
            .dir_path = dir_path,
        };
        errdefer result.deinit();
        result.ca_path = try result.writeOptional("ca.pem", config.ca_pem);
        result.cert_path = try result.writeOptional("client.crt", config.client_cert_pem);
        result.key_path = try result.writeOptional("client.key", config.client_key_pem);
        return result;
    }

    fn writeOptional(
        self: *CurlMaterial,
        basename: []const u8,
        contents: ?[]const u8,
    ) !?[]u8 {
        const bytes = contents orelse return null;
        const path = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}",
            .{ self.dir_path, basename },
        );
        errdefer self.allocator.free(path);
        const file = try std.Io.Dir.createFileAbsolute(self.io, path, .{
            .exclusive = true,
            .permissions = std.Io.File.Permissions.fromMode(0o600),
        });
        defer file.close(self.io);
        var buffer: [4096]u8 = undefined;
        var writer = file.writerStreaming(self.io, &buffer);
        try writer.interface.writeAll(bytes);
        try writer.flush();
        return path;
    }

    fn deinit(self: *CurlMaterial) void {
        inline for (.{ &self.ca_path, &self.cert_path, &self.key_path }) |path_ptr| {
            if (path_ptr.*) |path| {
                std.Io.Dir.deleteFileAbsolute(self.io, path) catch {};
                self.allocator.free(path);
                path_ptr.* = null;
            }
        }
        std.Io.Dir.deleteDirAbsolute(self.io, self.dir_path) catch {};
        self.allocator.free(self.dir_path);
        self.* = undefined;
    }
};

pub fn apiGroup(path: []const u8) []const u8 {
    if (std.mem.startsWith(u8, path, "/api/")) return "core";
    if (!std.mem.startsWith(u8, path, "/apis/")) return "unknown";
    const rest = path["/apis/".len..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return "unknown";
    return rest[0..slash];
}

pub const ResourceDescriptor = struct {
    api_path: []const u8,
    resource_name: []const u8,
    scope: klient.resource_registry.Scope,

    pub fn forType(comptime T: type) ResourceDescriptor {
        const meta = klient.resource_registry.metaFor(T);
        return .{
            .api_path = meta.api_path,
            .resource_name = meta.resource_name,
            .scope = meta.scope,
        };
    }

    /// A null `namespace` selects the all-namespace collection, which is how the
    /// cold load reads pods; cluster-scoped kinds have only that form.
    pub fn listPath(
        self: ResourceDescriptor,
        allocator: std.mem.Allocator,
        namespace: ?[]const u8,
    ) error{ InvalidNamespace, OutOfMemory, WriteFailed }![]u8 {
        const scoped_namespace: ?[]const u8 = switch (self.scope) {
            .cluster => null,
            .namespaced => namespace,
        };
        const ns = scoped_namespace orelse return std.fmt.allocPrint(
            allocator,
            "{s}/{s}",
            .{ self.api_path, self.resource_name },
        );
        if (!validPathSegment(ns)) return error.InvalidNamespace;
        return std.fmt.allocPrint(
            allocator,
            "{s}/namespaces/{s}/{s}",
            .{ self.api_path, ns, self.resource_name },
        );
    }
};

pub const PathError = error{InvalidReadPath};

/// Accept any origin-relative Kubernetes read path, including read-only
/// subresources such as `status`, `log`, and GET `scale`. Method safety is a
/// property of this module's API — a mutation entry point does not exist — so
/// resource names are never inspected here. What is rejected are URI forms that
/// would resolve somewhere other than the configured API origin, or that could
/// smuggle a second request line, since klient builds its request URL by
/// concatenating this path onto `api_server`.
pub fn validateReadPath(path: []const u8) PathError!void {
    if (path.len == 0 or path[0] != '/') return error.InvalidReadPath;
    // A network-path reference (`//host/...`) carries its own authority.
    if (path.len > 1 and path[1] == '/') return error.InvalidReadPath;
    if (std.mem.find(u8, path, "://") != null) return error.InvalidReadPath;

    for (path) |byte| {
        // Controls and spaces terminate or split the HTTP request line;
        // backslashes are folded to '/' by some proxies, reintroducing `//host`.
        if (byte <= ' ' or byte == 0x7f or byte == '#' or byte == '\\')
            return error.InvalidReadPath;
    }

    const query_start = std.mem.findScalar(u8, path, '?') orelse path.len;
    var segments = std.mem.splitScalar(u8, path[1..query_start], '/');
    while (segments.next()) |segment| {
        // Empty and dot segments make the effective path depend on whoever
        // normalizes it, so the prefix we think we requested is not guaranteed.
        if (segment.len == 0) return error.InvalidReadPath;
        if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, ".."))
            return error.InvalidReadPath;
        if (std.mem.findScalar(u8, segment, '%') != null) return error.InvalidReadPath;
    }
}

pub fn validPathSegment(segment: []const u8) bool {
    if (segment.len == 0) return false;
    if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return false;
    for (segment) |byte| {
        if (byte <= ' ' or byte >= 0x7f) return false;
        if (byte == '/' or byte == '?' or byte == '#' or byte == '\\') return false;
    }
    return true;
}

pub fn validQueryValue(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte)) continue;
        if (byte != '-' and byte != '.' and byte != '_' and byte != '~') return false;
    }
    return true;
}

pub fn paginatedListPath(
    allocator: std.mem.Allocator,
    base: []const u8,
    continue_token: []const u8,
) ![]u8 {
    try validateReadPath(base);
    if (continue_token.len == 0)
        return std.fmt.allocPrint(allocator, "{s}?limit=2000&pretty=false", .{base});
    var encoded: std.ArrayList(u8) = .empty;
    defer encoded.deinit(allocator);
    const hex = "0123456789ABCDEF";
    for (continue_token) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '.' or byte == '_' or byte == '~') {
            try encoded.append(allocator, byte);
        } else {
            try encoded.appendSlice(allocator, &.{ '%', hex[byte >> 4], hex[byte & 0x0f] });
        }
    }
    return std.fmt.allocPrint(
        allocator,
        "{s}?limit=2000&continue={s}&pretty=false",
        .{ base, encoded.items },
    );
}

pub fn compactListPath(
    allocator: std.mem.Allocator,
    base: []const u8,
) ![]u8 {
    try validateReadPath(base);
    return std.fmt.allocPrint(
        allocator,
        "{s}{s}pretty=false",
        .{ base, if (std.mem.findScalar(u8, base, '?') == null) "?" else "&" },
    );
}

test "ReadRequest carries pagination opt-in without a mutating counterpart" {
    const request = try ReadRequest.init("/api/v1/pods?limit=10");
    try std.testing.expectEqual(PaginationFallback.disabled, request.pagination_fallback);
    try std.testing.expect(!request.mayPaginateAfter(error.ResponseTooLarge));

    var fallback = request;
    fallback.pagination_fallback = .response_size_only;
    try std.testing.expect(fallback.mayPaginateAfter(error.ResponseTooLarge));
    try std.testing.expect(!fallback.mayPaginateAfter(error.ReadFailed));
}

test "pagination path encodes opaque continue tokens" {
    const first = try paginatedListPath(std.testing.allocator, "/api/v1/pods", "");
    defer std.testing.allocator.free(first);
    try std.testing.expectEqualStrings("/api/v1/pods?limit=2000&pretty=false", first);
    const next = try paginatedListPath(std.testing.allocator, "/api/v1/pods", "a/b+c=");
    defer std.testing.allocator.free(next);
    try std.testing.expectEqualStrings(
        "/api/v1/pods?limit=2000&continue=a%2Fb%2Bc%3D&pretty=false",
        next,
    );
}

test "compact list path explicitly disables pretty JSON" {
    const plain = try compactListPath(std.testing.allocator, "/api/v1/pods");
    defer std.testing.allocator.free(plain);
    try std.testing.expectEqualStrings("/api/v1/pods?pretty=false", plain);

    const queried = try compactListPath(std.testing.allocator, "/api/v1/pods?limit=500");
    defer std.testing.allocator.free(queried);
    try std.testing.expectEqualStrings(
        "/api/v1/pods?limit=500&pretty=false",
        queried,
    );
}

test "ReadTransport offers exactly one operation, and it is a GET" {
    const vtable_fields = @typeInfo(ReadTransport.VTable).@"struct".fields;
    try std.testing.expectEqual(@as(usize, 1), vtable_fields.len);
    try std.testing.expectEqualStrings("get", vtable_fields[0].name);

    inline for (.{ "post", "put", "patch", "delete", "write", "send", "request", "mutate" }) |name| {
        try std.testing.expect(!@hasDecl(ReadTransport, name));
        try std.testing.expect(!@hasField(ReadTransport.VTable, name));
        try std.testing.expect(!@hasDecl(KlientTransport, name));
    }

    // Analyze the concrete adapter so its delegation to the released
    // callback-scoped streamGet is type-checked by this suite.
    _ = &KlientTransport.transport;
}

test "read-only GET subresources stay reachable" {
    const scale = "/apis/apps/v1/namespaces/ns/deployments/name/scale";
    try std.testing.expectEqualStrings(scale, (try ReadRequest.init(scale)).path);
    _ = try ReadRequest.init("/api/v1/namespaces/ns/pods/name/status");
    _ = try ReadRequest.init("/api/v1/namespaces/ns/pods/name/log?container=app&tailLines=10");
    _ = try ReadRequest.init("/apis/apps/v1/namespaces/ns/deployments/name");
}

test "paths that could leave the API origin or encode another request are rejected" {
    const invalid = [_][]const u8{
        "",
        "api/v1/pods",
        "//evil.example.com/api/v1/pods",
        "https://evil.example.com/api/v1/pods",
        "/\\evil.example.com/api/v1/pods",
        "/api/v1/pods#items",
        "/api/v1/pods\r\nGET /api/v1/secrets HTTP/1.1",
        "/api/v1/pods\tlimit=1",
        "/api/v1/pods?labelSelector=a b",
        "/api/v1/../../healthz",
        "/api/v1/./pods",
        "/api/v1//pods",
        "/api/v1/%2e%2e/healthz",
        "/api/v1/namespaces/default/pods%2flog",
    };
    for (invalid) |path| {
        try std.testing.expectError(error.InvalidReadPath, ReadRequest.init(path));
    }
}

test "ResourceDescriptor delegates to the klient registry" {
    const pod = ResourceDescriptor.forType(klient.Pod);
    try std.testing.expectEqualStrings("/api/v1", pod.api_path);
    try std.testing.expectEqualStrings("pods", pod.resource_name);
    try std.testing.expectEqual(klient.resource_registry.Scope.namespaced, pod.scope);

    const node = ResourceDescriptor.forType(klient.Node);
    try std.testing.expectEqualStrings("/api/v1", node.api_path);
    try std.testing.expectEqualStrings("nodes", node.resource_name);
    try std.testing.expectEqual(klient.resource_registry.Scope.cluster, node.scope);
}

test "namespaced listPath serves the all-namespace cold load and a single namespace" {
    const pod = ResourceDescriptor.forType(klient.Pod);

    const all_namespaces = try pod.listPath(std.testing.allocator, null);
    defer std.testing.allocator.free(all_namespaces);
    try std.testing.expectEqualStrings("/api/v1/pods", all_namespaces);
    _ = try ReadRequest.init(all_namespaces);

    const single = try pod.listPath(std.testing.allocator, "kube-system");
    defer std.testing.allocator.free(single);
    try std.testing.expectEqualStrings("/api/v1/namespaces/kube-system/pods", single);
    _ = try ReadRequest.init(single);
}

test "services family namespaced paths preserve API groups and scopes" {
    const cases = .{
        .{ klient.Service, "/api/v1/services", "/api/v1/namespaces/team-a/services" },
        .{ klient.Endpoints, "/api/v1/endpoints", "/api/v1/namespaces/team-a/endpoints" },
        .{ klient.EndpointSlice, "/apis/discovery.k8s.io/v1/endpointslices", "/apis/discovery.k8s.io/v1/namespaces/team-a/endpointslices" },
    };
    inline for (cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        const all = try descriptor.listPath(std.testing.allocator, null);
        defer std.testing.allocator.free(all);
        try std.testing.expectEqualStrings(case[1], all);
        const namespaced = try descriptor.listPath(std.testing.allocator, "team-a");
        defer std.testing.allocator.free(namespaced);
        try std.testing.expectEqualStrings(case[2], namespaced);
    }
}

test "config family namespaced paths use exact current and all namespace collections" {
    const cases = .{
        .{ klient.ConfigMap, "/api/v1/configmaps", "/api/v1/namespaces/team-a/configmaps" },
        .{ klient.Secret, "/api/v1/secrets", "/api/v1/namespaces/team-a/secrets" },
        .{ klient.ServiceAccount, "/api/v1/serviceaccounts", "/api/v1/namespaces/team-a/serviceaccounts" },
        .{ klient.ResourceQuota, "/api/v1/resourcequotas", "/api/v1/namespaces/team-a/resourcequotas" },
        .{ klient.LimitRange, "/api/v1/limitranges", "/api/v1/namespaces/team-a/limitranges" },
    };
    inline for (cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        const all = try descriptor.listPath(std.testing.allocator, null);
        defer std.testing.allocator.free(all);
        try std.testing.expectEqualStrings(case[1], all);
        const namespaced = try descriptor.listPath(std.testing.allocator, "team-a");
        defer std.testing.allocator.free(namespaced);
        try std.testing.expectEqualStrings(case[2], namespaced);
    }
}

test "workload family namespaced paths use exact current and all namespace collections" {
    const cases = .{
        .{ klient.Deployment, "/apis/apps/v1/deployments", "/apis/apps/v1/namespaces/team-a/deployments" },
        .{ klient.StatefulSet, "/apis/apps/v1/statefulsets", "/apis/apps/v1/namespaces/team-a/statefulsets" },
        .{ klient.DaemonSet, "/apis/apps/v1/daemonsets", "/apis/apps/v1/namespaces/team-a/daemonsets" },
        .{ klient.ReplicaSet, "/apis/apps/v1/replicasets", "/apis/apps/v1/namespaces/team-a/replicasets" },
    };
    inline for (cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        const all = try descriptor.listPath(std.testing.allocator, null);
        defer std.testing.allocator.free(all);
        try std.testing.expectEqualStrings(case[1], all);
        const namespaced = try descriptor.listPath(std.testing.allocator, "team-a");
        defer std.testing.allocator.free(namespaced);
        try std.testing.expectEqualStrings(case[2], namespaced);
    }
}

test "batch family namespaced paths use exact current and all namespace collections" {
    const cases = .{
        .{ klient.Job, "/apis/batch/v1/jobs", "/apis/batch/v1/namespaces/team-a/jobs" },
        .{ klient.CronJob, "/apis/batch/v1/cronjobs", "/apis/batch/v1/namespaces/team-a/cronjobs" },
        .{ klient.HorizontalPodAutoscaler, "/apis/autoscaling/v2/horizontalpodautoscalers", "/apis/autoscaling/v2/namespaces/team-a/horizontalpodautoscalers" },
        .{ klient.PodDisruptionBudget, "/apis/policy/v1/poddisruptionbudgets", "/apis/policy/v1/namespaces/team-a/poddisruptionbudgets" },
    };
    inline for (cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        const all = try descriptor.listPath(std.testing.allocator, null);
        defer std.testing.allocator.free(all);
        try std.testing.expectEqualStrings(case[1], all);
        const namespaced = try descriptor.listPath(std.testing.allocator, "team-a");
        defer std.testing.allocator.free(namespaced);
        try std.testing.expectEqualStrings(case[2], namespaced);
    }
}

test "networking family paths use exact registry groups and scopes" {
    const namespaced_cases = .{
        .{ klient.types.Ingress, "/apis/networking.k8s.io/v1/ingresses", "/apis/networking.k8s.io/v1/namespaces/team-a/ingresses" },
        .{ klient.NetworkPolicy, "/apis/networking.k8s.io/v1/networkpolicies", "/apis/networking.k8s.io/v1/namespaces/team-a/networkpolicies" },
    };
    inline for (namespaced_cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        try std.testing.expectEqual(klient.resource_registry.Scope.namespaced, descriptor.scope);
        const all = try descriptor.listPath(std.testing.allocator, null);
        defer std.testing.allocator.free(all);
        try std.testing.expectEqualStrings(case[1], all);
        const namespaced = try descriptor.listPath(std.testing.allocator, "team-a");
        defer std.testing.allocator.free(namespaced);
        try std.testing.expectEqualStrings(case[2], namespaced);
    }
    const cluster_cases = .{
        .{ klient.IngressClass, "/apis/networking.k8s.io/v1/ingressclasses" },
        .{ klient.IPAddress, "/apis/networking.k8s.io/v1/ipaddresses" },
        .{ klient.ServiceCIDR, "/apis/networking.k8s.io/v1/servicecidrs" },
    };
    inline for (cluster_cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        try std.testing.expectEqual(klient.resource_registry.Scope.cluster, descriptor.scope);
        const path = try descriptor.listPath(std.testing.allocator, "ignored");
        defer std.testing.allocator.free(path);
        try std.testing.expectEqualStrings(case[1], path);
    }
}

test "storage family paths use exact registry groups and scopes" {
    const pvc = ResourceDescriptor.forType(klient.PersistentVolumeClaim);
    try std.testing.expectEqual(klient.resource_registry.Scope.namespaced, pvc.scope);
    const pvc_all = try pvc.listPath(std.testing.allocator, null);
    defer std.testing.allocator.free(pvc_all);
    try std.testing.expectEqualStrings("/api/v1/persistentvolumeclaims", pvc_all);
    const pvc_namespaced = try pvc.listPath(std.testing.allocator, "team-a");
    defer std.testing.allocator.free(pvc_namespaced);
    try std.testing.expectEqualStrings("/api/v1/namespaces/team-a/persistentvolumeclaims", pvc_namespaced);

    const cluster_cases = .{
        .{ klient.PersistentVolume, "/api/v1/persistentvolumes" },
        .{ klient.StorageClass, "/apis/storage.k8s.io/v1/storageclasses" },
        .{ klient.VolumeAttributesClass, "/apis/storage.k8s.io/v1/volumeattributesclasses" },
        .{ klient.CSIDriver, "/apis/storage.k8s.io/v1/csidrivers" },
    };
    inline for (cluster_cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        try std.testing.expectEqual(klient.resource_registry.Scope.cluster, descriptor.scope);
        const path = try descriptor.listPath(std.testing.allocator, "must-be-ignored");
        defer std.testing.allocator.free(path);
        try std.testing.expectEqualStrings(case[1], path);
        try std.testing.expect(std.mem.indexOf(u8, path, "/namespaces/") == null);
    }
}

test "Gateway API core and extension paths use exact registry groups and scopes" {
    const gateway_class = ResourceDescriptor.forType(klient.GatewayClass);
    try std.testing.expectEqual(klient.resource_registry.Scope.cluster, gateway_class.scope);
    const class_path = try gateway_class.listPath(std.testing.allocator, "must-be-ignored");
    defer std.testing.allocator.free(class_path);
    try std.testing.expectEqualStrings("/apis/gateway.networking.k8s.io/v1/gatewayclasses", class_path);
    try std.testing.expect(std.mem.indexOf(u8, class_path, "/namespaces/") == null);

    const cases = .{
        .{ klient.Gateway, "/apis/gateway.networking.k8s.io/v1/gateways", "/apis/gateway.networking.k8s.io/v1/namespaces/team-a/gateways" },
        .{ klient.HTTPRoute, "/apis/gateway.networking.k8s.io/v1/httproutes", "/apis/gateway.networking.k8s.io/v1/namespaces/team-a/httproutes" },
        .{ klient.GRPCRoute, "/apis/gateway.networking.k8s.io/v1/grpcroutes", "/apis/gateway.networking.k8s.io/v1/namespaces/team-a/grpcroutes" },
        .{ klient.ReferenceGrant, "/apis/gateway.networking.k8s.io/v1beta1/referencegrants", "/apis/gateway.networking.k8s.io/v1beta1/namespaces/team-a/referencegrants" },
        .{ klient.TCPRoute, "/apis/gateway.networking.k8s.io/v1/tcproutes", "/apis/gateway.networking.k8s.io/v1/namespaces/team-a/tcproutes" },
        .{ klient.TLSRoute, "/apis/gateway.networking.k8s.io/v1/tlsroutes", "/apis/gateway.networking.k8s.io/v1/namespaces/team-a/tlsroutes" },
        .{ klient.UDPRoute, "/apis/gateway.networking.k8s.io/v1/udproutes", "/apis/gateway.networking.k8s.io/v1/namespaces/team-a/udproutes" },
        .{ klient.BackendTLSPolicy, "/apis/gateway.networking.k8s.io/v1/backendtlspolicies", "/apis/gateway.networking.k8s.io/v1/namespaces/team-a/backendtlspolicies" },
        .{ klient.ListenerSet, "/apis/gateway.networking.k8s.io/v1/listenersets", "/apis/gateway.networking.k8s.io/v1/namespaces/team-a/listenersets" },
    };
    inline for (cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        try std.testing.expectEqual(klient.resource_registry.Scope.namespaced, descriptor.scope);
        const all = try descriptor.listPath(std.testing.allocator, null);
        defer std.testing.allocator.free(all);
        try std.testing.expectEqualStrings(case[1], all);
        const namespaced = try descriptor.listPath(std.testing.allocator, "team-a");
        defer std.testing.allocator.free(namespaced);
        try std.testing.expectEqualStrings(case[2], namespaced);
    }
}

test "RBAC family paths use exact registry groups and scopes" {
    const namespaced_cases = .{
        .{ klient.Role, "/apis/rbac.authorization.k8s.io/v1/roles", "/apis/rbac.authorization.k8s.io/v1/namespaces/team-a/roles" },
        .{ klient.RoleBinding, "/apis/rbac.authorization.k8s.io/v1/rolebindings", "/apis/rbac.authorization.k8s.io/v1/namespaces/team-a/rolebindings" },
    };
    inline for (namespaced_cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        try std.testing.expectEqual(klient.resource_registry.Scope.namespaced, descriptor.scope);
        const all = try descriptor.listPath(std.testing.allocator, null);
        defer std.testing.allocator.free(all);
        try std.testing.expectEqualStrings(case[1], all);
        const namespaced = try descriptor.listPath(std.testing.allocator, "team-a");
        defer std.testing.allocator.free(namespaced);
        try std.testing.expectEqualStrings(case[2], namespaced);
    }

    const cluster_cases = .{
        .{ klient.ClusterRole, "/apis/rbac.authorization.k8s.io/v1/clusterroles" },
        .{ klient.ClusterRoleBinding, "/apis/rbac.authorization.k8s.io/v1/clusterrolebindings" },
    };
    inline for (cluster_cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        try std.testing.expectEqual(klient.resource_registry.Scope.cluster, descriptor.scope);
        const path = try descriptor.listPath(std.testing.allocator, "must-be-ignored");
        defer std.testing.allocator.free(path);
        try std.testing.expectEqualStrings(case[1], path);
        try std.testing.expect(std.mem.indexOf(u8, path, "/namespaces/") == null);
    }
}

test "admission family paths use exact registry groups and cluster scope" {
    const cases = .{
        .{ klient.ValidatingAdmissionPolicy, "/apis/admissionregistration.k8s.io/v1/validatingadmissionpolicies" },
        .{ klient.ValidatingAdmissionPolicyBinding, "/apis/admissionregistration.k8s.io/v1/validatingadmissionpolicybindings" },
        .{ klient.MutatingAdmissionPolicy, "/apis/admissionregistration.k8s.io/v1/mutatingadmissionpolicies" },
        .{ klient.MutatingAdmissionPolicyBinding, "/apis/admissionregistration.k8s.io/v1/mutatingadmissionpolicybindings" },
        .{ klient.ValidatingWebhookConfiguration, "/apis/admissionregistration.k8s.io/v1/validatingwebhookconfigurations" },
        .{ klient.MutatingWebhookConfiguration, "/apis/admissionregistration.k8s.io/v1/mutatingwebhookconfigurations" },
    };
    inline for (cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        try std.testing.expectEqual(klient.resource_registry.Scope.cluster, descriptor.scope);
        const path = try descriptor.listPath(std.testing.allocator, "must-be-ignored");
        defer std.testing.allocator.free(path);
        try std.testing.expectEqualStrings(case[1], path);
        try std.testing.expect(std.mem.indexOf(u8, path, "/namespaces/") == null);
    }
}

test "DRA and platform paths use exact registry groups and scopes" {
    const namespaced_cases = .{
        .{ klient.ResourceClaim, "/apis/resource.k8s.io/v1/resourceclaims", "/apis/resource.k8s.io/v1/namespaces/team/resourceclaims" },
        .{ klient.Lease, "/apis/coordination.k8s.io/v1/leases", "/apis/coordination.k8s.io/v1/namespaces/team/leases" },
        .{ klient.Event, "/api/v1/events", "/api/v1/namespaces/team/events" },
    };
    inline for (namespaced_cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        try std.testing.expectEqual(klient.resource_registry.Scope.namespaced, descriptor.scope);
        const all = try descriptor.listPath(std.testing.allocator, null);
        defer std.testing.allocator.free(all);
        try std.testing.expectEqualStrings(case[1], all);
        const namespaced = try descriptor.listPath(std.testing.allocator, "team");
        defer std.testing.allocator.free(namespaced);
        try std.testing.expectEqualStrings(case[2], namespaced);
    }
    const cluster_cases = .{
        .{ klient.DeviceClass, "/apis/resource.k8s.io/v1/deviceclasses" },
        .{ klient.PriorityClass, "/apis/scheduling.k8s.io/v1/priorityclasses" },
        .{ klient.RuntimeClass, "/apis/node.k8s.io/v1/runtimeclasses" },
        .{ klient.CertificateSigningRequest, "/apis/certificates.k8s.io/v1/certificatesigningrequests" },
        .{ klient.StorageVersionMigration, "/apis/storagemigration.k8s.io/v1/storageversionmigrations" },
    };
    inline for (cluster_cases) |case| {
        const descriptor = ResourceDescriptor.forType(case[0]);
        try std.testing.expectEqual(klient.resource_registry.Scope.cluster, descriptor.scope);
        const path = try descriptor.listPath(std.testing.allocator, "must-be-ignored");
        defer std.testing.allocator.free(path);
        try std.testing.expectEqualStrings(case[1], path);
        try std.testing.expect(std.mem.indexOf(u8, path, "/namespaces/") == null);
    }
}

test "cluster-scoped listPath ignores namespace" {
    const node = ResourceDescriptor.forType(klient.Node);
    const namespace = ResourceDescriptor.forType(klient.Namespace);

    const implicit = try node.listPath(std.testing.allocator, null);
    defer std.testing.allocator.free(implicit);
    try std.testing.expectEqualStrings("/api/v1/nodes", implicit);

    const with_namespace = try node.listPath(std.testing.allocator, "kube-system");
    defer std.testing.allocator.free(with_namespace);
    try std.testing.expectEqualStrings("/api/v1/nodes", with_namespace);

    const namespaces = try namespace.listPath(std.testing.allocator, "ignored");
    defer std.testing.allocator.free(namespaces);
    try std.testing.expectEqualStrings("/api/v1/namespaces", namespaces);
}

test "listPath rejects namespaces that are not a single path segment" {
    const pod = ResourceDescriptor.forType(klient.Pod);
    const invalid = [_][]const u8{
        "",
        ".",
        "..",
        "kube-system/secrets",
        "kube-system?limit=1",
        "kube-system#items",
        "kube-system\\secrets",
        "kube system",
        "kube-system\r\nX: 1",
    };
    for (invalid) |namespace| {
        try std.testing.expectError(
            error.InvalidNamespace,
            pod.listPath(std.testing.allocator, namespace),
        );
    }
}

test "Task 15 rejects klient transports without an audit context" {
    const Callback = struct {
        fn receive(_: *anyopaque, _: ResponseMeta, _: *std.Io.Reader) anyerror!void {}
    };
    task15.setLiveMode(true);
    defer task15.setLiveMode(false);
    var adapter = KlientTransport{
        .client = undefined,
        .io = std.testing.io,
    };
    var callback_context: u8 = 0;
    try std.testing.expectError(
        error.Task15ContextRequired,
        adapter.transport().get(
            try ReadRequest.init("/api/v1/pods"),
            &callback_context,
            Callback.receive,
        ),
    );
}

test "watch requests retain GET-only transport with WATCH audit semantics" {
    const request = try ReadRequest.watch("/api/v1/pods?watch&resourceVersion=7");
    try std.testing.expectEqual(task15.Method.WATCH, request.audit_method);
    try std.testing.expectEqualStrings(
        "/api/v1/pods?watch&resourceVersion=7",
        request.path,
    );
}

test "curl config keeps bearer credentials off argv-compatible data" {
    var storage: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&storage);
    try writeCurlConfig(&writer, "token.with-quote\"");
    try std.testing.expectEqualStrings(
        "header = \"Authorization: Bearer token.with-quote\\\"\"\n",
        writer.buffered(),
    );

    var rejected_storage: [64]u8 = undefined;
    var rejected = std.Io.Writer.fixed(&rejected_storage);
    try std.testing.expectError(
        error.InvalidCredential,
        writeCurlConfig(&rejected, "token\ninjected"),
    );
}

test "curl response headers preserve metadata and leave body streaming" {
    var reader = std.Io.Reader.fixed(
        "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: application/json\r\n" ++
            "Retry-After: 7\r\n" ++
            "\r\n" ++
            "{\"items\":[]}",
    );
    var content_type: [256]u8 = undefined;
    const meta = try parseCurlResponseHeaders(&reader, &content_type);
    try std.testing.expectEqual(std.http.Status.ok, meta.status);
    try std.testing.expectEqual(@as(?u32, 7), meta.retry_after_seconds);
    try std.testing.expectEqualStrings("application/json", meta.content_type.?);
    try std.testing.expectEqualStrings("{\"items\":[]}", reader.buffered());
}

test "curl response parser skips informational headers" {
    var reader = std.Io.Reader.fixed(
        "HTTP/1.1 100 Continue\r\n\r\n" ++
            "HTTP/1.1 410 Gone\r\nContent-Type: application/json\r\n\r\n{}",
    );
    var content_type: [256]u8 = undefined;
    const meta = try parseCurlResponseHeaders(&reader, &content_type);
    try std.testing.expectEqual(std.http.Status.gone, meta.status);
    try std.testing.expectEqualStrings("{}", reader.buffered());
}

test "pagination guard rejects repeated and cyclic continue tokens" {
    var guard = PaginationGuard.init(std.testing.allocator, 100);
    defer guard.deinit();
    try std.testing.expect(try guard.advance("token-a"));
    try std.testing.expect(try guard.advance("token-b"));
    try std.testing.expectError(error.RepeatedContinueToken, guard.advance("token-a"));
}

test "pagination guard permits large valid lists and enforces page cap" {
    var guard = PaginationGuard.init(std.testing.allocator, 1_001);
    defer guard.deinit();
    var buffer: [32]u8 = undefined;
    for (0..1_000) |page| {
        const token = try std.fmt.bufPrint(&buffer, "token-{d}", .{page});
        try std.testing.expect(try guard.advance(token));
    }
    try std.testing.expectError(error.ListPageLimitExceeded, guard.advance("one-too-many"));

    var complete = PaginationGuard.init(std.testing.allocator, 1_001);
    defer complete.deinit();
    for (0..1_000) |page| {
        const token = try std.fmt.bufPrint(&buffer, "token-{d}", .{page});
        try std.testing.expect(try complete.advance(token));
    }
    try std.testing.expect(!try complete.advance(""));
}
