const std = @import("std");
const klient = @import("klient");

pub const schema_version: u8 = 2;
pub const max_record_bytes: usize = 1024;
pub const max_manifest_bytes: usize = 16 * 1024;
pub const allowed_contexts = [_][]const u8{ "dev4.as", "rc.alpha-sense.org" };
pub const ssar_path = "/apis/authorization.k8s.io/v1/selfsubjectaccessreviews";
pub const diagnostic_fd_env = "C3S_DIAGNOSTIC_FD";
pub const perf_fd_env = "C3S_PERF_FD";

var live_mode: std.atomic.Value(bool) = .init(false);

pub fn setLiveMode(enabled: bool) void {
    live_mode.store(enabled, .release);
}

pub fn isLiveMode() bool {
    return live_mode.load(.acquire);
}

pub const Family = enum {
    pod,
    node,
    namespace,
    services,
    config,
    workloads,
    batch,
    networking,
    storage,
    gateway_core,
    gateway_ext,
    rbac,
    admission,
    dra,
    platform,
};

pub const DiagnosticControl = union(enum) {
    reconnect: Family,
    stale_rv: Family,
};

var stale_rv_mask: std.atomic.Value(u32) = .init(0);

pub fn armStaleRv(family: Family) void {
    _ = stale_rv_mask.fetchOr(@as(u32, 1) << @intFromEnum(family), .acq_rel);
}

pub fn consumeStaleRv(family: Family) bool {
    const bit = @as(u32, 1) << @intFromEnum(family);
    const previous = stale_rv_mask.fetchAnd(~bit, .acq_rel);
    return previous & bit != 0;
}

pub fn parseFamily(value: []const u8) !Family {
    return std.meta.stringToEnum(Family, value) orelse error.InvalidDiagnosticFamily;
}

pub fn familyForResource(resource: []const u8) ?Family {
    const groups = .{
        .{ Family.pod, &[_][]const u8{"pods"} },
        .{ Family.node, &[_][]const u8{"nodes"} },
        .{ Family.namespace, &[_][]const u8{"namespaces"} },
        .{ Family.services, &[_][]const u8{ "services", "endpoints", "endpointslices" } },
        .{ Family.config, &[_][]const u8{ "configmaps", "secrets", "serviceaccounts", "resourcequotas", "limitranges" } },
        .{ Family.workloads, &[_][]const u8{ "deployments", "statefulsets", "daemonsets", "replicasets" } },
        .{ Family.batch, &[_][]const u8{ "jobs", "cronjobs", "horizontalpodautoscalers", "poddisruptionbudgets" } },
        .{ Family.networking, &[_][]const u8{ "ingresses", "ingressclasses", "networkpolicies", "ipaddresses", "servicecidrs" } },
        .{ Family.storage, &[_][]const u8{ "persistentvolumes", "persistentvolumeclaims", "storageclasses", "volumeattributesclasses", "csidrivers" } },
        .{ Family.gateway_core, &[_][]const u8{ "gatewayclasses", "gateways", "httproutes", "grpcroutes", "referencegrants" } },
        .{ Family.gateway_ext, &[_][]const u8{ "tcproutes", "tlsroutes", "udproutes", "backendtlspolicies", "listenersets" } },
        .{ Family.rbac, &[_][]const u8{ "roles", "rolebindings", "clusterroles", "clusterrolebindings" } },
        .{ Family.admission, &[_][]const u8{ "validatingadmissionpolicies", "validatingadmissionpolicybindings", "mutatingadmissionpolicies", "mutatingadmissionpolicybindings", "validatingwebhookconfigurations", "mutatingwebhookconfigurations" } },
        .{ Family.dra, &[_][]const u8{ "resourceclaims", "deviceclasses" } },
        .{ Family.platform, &[_][]const u8{ "priorityclasses", "runtimeclasses", "leases", "certificatesigningrequests", "storageversionmigrations", "events" } },
    };
    inline for (groups) |group| {
        for (group[1]) |candidate| {
            if (std.mem.eql(u8, resource, candidate)) return group[0];
        }
    }
    return null;
}

pub fn contextAllowed(context: []const u8) bool {
    for (allowed_contexts) |allowed| {
        if (std.mem.eql(u8, context, allowed)) return true;
    }
    return false;
}

pub const LaunchSafety = struct {
    readonly: bool,
    context: ?[]const u8,
    manifest_path: ?[]const u8 = null,
    headless: bool = false,
    write: bool = false,
    cluster: ?[]const u8 = null,
    user: ?[]const u8 = null,
    token: ?[]const u8 = null,
    impersonate: ?[]const u8 = null,
    impersonate_group: ?[]const u8 = null,
    certificate_authority: ?[]const u8 = null,
    client_certificate: ?[]const u8 = null,
    client_key: ?[]const u8 = null,
    insecure_skip_tls_verify: bool = false,
};

pub fn validateDiagnosticLaunch(safety: LaunchSafety) !void {
    if (!safety.readonly) return error.DiagnosticRequiresReadonly;
    if (safety.headless) return error.Task15SafetyBannerRequired;
    const context = safety.context orelse return error.DiagnosticRequiresExplicitContext;
    if (!contextAllowed(context)) return error.ContextNotAllowlisted;
    if (safety.manifest_path == null) return error.Task15ManifestRequired;
    if (safety.write) return error.ReadonlyWriteConflict;
    if (safety.cluster != null or safety.user != null or safety.token != null or
        safety.impersonate != null or safety.impersonate_group != null or
        safety.certificate_authority != null or safety.client_certificate != null or
        safety.client_key != null or
        safety.insecure_skip_tls_verify)
    {
        return error.UnsafeClusterOverride;
    }
    try requireEvidenceFd(diagnostic_fd_env);
    try requireEvidenceFd(perf_fd_env);
}

pub const Method = enum { GET, WATCH, POST };

pub fn requestAllowed(method: Method, path: []const u8) bool {
    const sanitized = sanitizeRequest(method, path) catch return false;
    return method != .POST or std.mem.eql(u8, sanitized.endpoint_class, "ssar");
}

pub fn enforceRequest(method: Method, path: []const u8) !SanitizedRequest {
    const sanitized = try sanitizeRequest(method, path);
    if (isLiveMode() and method == .POST and
        !std.mem.eql(u8, sanitized.endpoint_class, "ssar"))
    {
        return error.Task15RequestRejected;
    }
    return sanitized;
}

pub const SanitizedRequest = struct {
    api_group: []const u8,
    resource: []const u8,
    subresource: []const u8,
    scope: []const u8,
    endpoint_class: []const u8,
    identity_fingerprint: u64,
    query_fingerprint: u64,
};

pub fn sanitizeRequest(method: Method, path: []const u8) !SanitizedRequest {
    if (path.len == 0 or path[0] != '/' or
        std.mem.indexOfAny(u8, path, " \r\n\t#\\") != null or
        std.mem.startsWith(u8, path, "//") or
        std.mem.indexOf(u8, path, "://") != null)
    {
        return error.UnsafeRequestPath;
    }
    if (method == .POST) {
        if (!std.mem.eql(u8, path, ssar_path)) return error.Task15RequestRejected;
        return .{
            .api_group = "authorization.k8s.io",
            .resource = "selfsubjectaccessreviews",
            .subresource = "",
            .scope = "cluster",
            .endpoint_class = "ssar",
            .identity_fingerprint = 0,
            .query_fingerprint = 0,
        };
    }

    const query_index = std.mem.indexOfScalar(u8, path, '?') orelse path.len;
    const path_only = path[0..query_index];
    const query = if (query_index < path.len) path[query_index + 1 ..] else "";
    if (std.mem.eql(u8, path_only, "/version")) return .{
        .api_group = "core",
        .resource = "version",
        .subresource = "",
        .scope = "cluster",
        .endpoint_class = "version",
        .identity_fingerprint = 0,
        .query_fingerprint = if (query.len == 0) 0 else fingerprint(query),
    };

    var segments: [12][]const u8 = undefined;
    var count: usize = 0;
    var iterator = std.mem.splitScalar(u8, path_only[1..], '/');
    while (iterator.next()) |segment| {
        if (segment.len == 0 or count == segments.len) return error.UnsafeRequestPath;
        segments[count] = segment;
        count += 1;
    }

    var api_group: []const u8 = undefined;
    var resource_index: usize = undefined;
    if (count >= 3 and std.mem.eql(u8, segments[0], "api")) {
        api_group = "core";
        resource_index = 2;
    } else if (count >= 4 and std.mem.eql(u8, segments[0], "apis")) {
        api_group = segments[1];
        resource_index = 3;
    } else {
        return error.UnsafeRequestPath;
    }

    var scope: []const u8 = "cluster-or-all";
    var sensitive_start: usize = resource_index + 1;
    if (resource_index + 2 < count and
        std.mem.eql(u8, segments[resource_index], "namespaces"))
    {
        scope = "namespaced";
        sensitive_start = resource_index + 1;
        resource_index += 2;
    }
    if (resource_index >= count) return error.UnsafeRequestPath;

    const resource = segments[resource_index];
    var subresource: []const u8 = "";
    if (resource_index + 2 < count) subresource = segments[resource_index + 2];
    var identity_hasher = std.hash.Wyhash.init(0x6333732d6964656e);
    for (segments[sensitive_start..count], 0..) |segment, index| {
        if (index > 0) identity_hasher.update(&.{0});
        identity_hasher.update(segment);
    }
    return .{
        .api_group = api_group,
        .resource = resource,
        .subresource = subresource,
        .scope = scope,
        .endpoint_class = "resource",
        .identity_fingerprint = if (sensitive_start < count) identity_hasher.final() else 0,
        .query_fingerprint = if (query.len == 0) 0 else fingerprint(query),
    };
}

pub const TerminalState = enum {
    ready,
    absent,
    forbidden,
    unauthorized,
    transport_retry,
    transport_terminal,
};

pub fn stateForStatus(status: u16, retrying: bool) TerminalState {
    return switch (status) {
        401 => .unauthorized,
        403 => .forbidden,
        404 => .absent,
        else => if (retrying) .transport_retry else .transport_terminal,
    };
}

pub const EventKind = enum {
    readonly_status,
    list_start,
    list_page,
    list_continue,
    list_complete,
    watch_http_established,
    watch_event,
    watch_bookmark,
    watch_disconnect,
    reconnect_attempt,
    reconnect_success,
    gone_410,
    relist,
    terminal_forbidden,
    terminal_unauthorized,
    terminal_absent,
    terminal_malformed,
    retries_exhausted,
    transport_retry,
    first_usable_paint,
    complete_sync_paint,
    diagnostics_snapshot,
    diagnostic_reconnect,
    diagnostic_stale_rv,
    request_audit,
};

pub const QueueSnapshot = struct {
    count: usize = 0,
    bytes: usize = 0,
    high_water_count: usize = 0,
    high_water_bytes: usize = 0,
    retries: u64 = 0,
    drops: u64 = 0,
};

pub const SupervisorSnapshot = struct {
    live: usize = 0,
    launched: usize = 0,
    reaped: usize = 0,
    canceled: usize = 0,
    max_live: usize = 0,
    active_identities: usize = 0,
};

pub const LeaseSnapshot = struct {
    active: usize = 0,
    retiring: usize = 0,
};

pub const Snapshot = struct {
    queue: QueueSnapshot = .{},
    supervisor: SupervisorSnapshot = .{},
    leases: LeaseSnapshot = .{},
};

pub const Record = struct {
    event: EventKind,
    context: []const u8,
    scope: []const u8,
    family: ?Family = null,
    readonly: ?bool = null,
    method: ?Method = null,
    api_group: []const u8 = "",
    resource: []const u8 = "",
    subresource: []const u8 = "",
    endpoint_class: []const u8 = "",
    status: ?u16 = null,
    retry_class: []const u8 = "none",
    token_fingerprint: u64 = 0,
    rv_fingerprint: u64 = 0,
    identity_fingerprint: u64 = 0,
    query_fingerprint: u64 = 0,
    page: usize = 0,
    object_count: usize = 0,
    snapshot: Snapshot = .{},
};

pub fn fingerprint(value: []const u8) u64 {
    return std.hash.Wyhash.hash(0x6333732d7461736b, value);
}

pub fn watchOutcomeStatus(outcome: klient.WatchOutcome) ?u16 {
    return switch (outcome) {
        .http_unauthorized => 401,
        .http_forbidden => 403,
        .http_gone, .status_expired => 410,
        .http_throttled => 429,
        .http_server_error, .http_error => |status| @intFromEnum(status),
        .status_error => |detail| detail.code,
        else => null,
    };
}

pub const Writer = struct {
    fd: ?std.c.fd_t = null,
    dropped: u64 = 0,

    pub fn initFromEnv() Writer {
        const raw = std.c.getenv(diagnostic_fd_env) orelse return .{};
        const fd = std.fmt.parseInt(std.c.fd_t, std.mem.span(raw), 10) catch return .{};
        if (fd < 0) return .{};
        return .{ .fd = fd };
    }

    pub fn emit(self: *Writer, record: Record) void {
        const fd = self.fd orelse return;
        var buffer: [max_record_bytes]u8 = undefined;
        const bytes = encodeRecord(record, &buffer) catch {
            self.dropped +|= 1;
            return;
        };
        const written = std.c.write(fd, bytes.ptr, bytes.len);
        if (written != bytes.len) self.dropped +|= 1;
    }
};

pub fn encodeRecord(record: Record, buffer: []u8) ![]const u8 {
    var output: std.Io.Writer = .fixed(buffer);
    try std.json.Stringify.value(record, .{}, &output);
    try output.writeByte('\n');
    return output.buffered();
}

pub const Manifest = struct {
    schema_version: u8,
    context: []const u8,
    cluster: []const u8,
    server_host: []const u8,
    fingerprint: u64,
};

const ActualIdentity = struct {
    context: []u8,
    cluster: []u8,
    server_host: []u8,
    fingerprint: u64,

    fn deinit(self: *ActualIdentity, allocator: std.mem.Allocator) void {
        allocator.free(self.context);
        allocator.free(self.cluster);
        allocator.free(self.server_host);
    }
};

fn resolveIdentity(
    allocator: std.mem.Allocator,
    io: std.Io,
    context_name: []const u8,
    kubeconfig_path: ?[]const u8,
) !ActualIdentity {
    if (!contextAllowed(context_name)) return error.ContextNotAllowlisted;
    var parser = klient.KubeconfigParser.init(allocator, io);
    var kubeconfig = if (kubeconfig_path) |path|
        try parser.loadFromPath(path)
    else
        try parser.load();
    defer kubeconfig.deinit(allocator);
    const context = kubeconfig.getContextByName(context_name) orelse
        return error.ContextNotFound;
    const cluster = kubeconfig.getClusterByName(context.cluster) orelse
        return error.ClusterNotFound;
    const host = try sanitizedServerHost(cluster.server);
    const context_copy = try allocator.dupe(u8, context.name);
    errdefer allocator.free(context_copy);
    const cluster_copy = try allocator.dupe(u8, cluster.name);
    errdefer allocator.free(cluster_copy);
    const host_copy = try allocator.dupe(u8, host);
    return .{
        .context = context_copy,
        .cluster = cluster_copy,
        .server_host = host_copy,
        .fingerprint = manifestFingerprint(context.name, cluster.name, host),
    };
}

pub fn manifestFingerprint(
    context: []const u8,
    cluster: []const u8,
    server_host: []const u8,
) u64 {
    var hasher = std.hash.Wyhash.init(0x6333732d6d616e69);
    hasher.update(context);
    hasher.update(&.{0});
    hasher.update(cluster);
    hasher.update(&.{0});
    hasher.update(server_host);
    return hasher.final();
}

pub fn sanitizedServerHost(server: []const u8) ![]const u8 {
    const prefix_len: usize = if (std.mem.startsWith(u8, server, "https://"))
        "https://".len
    else if (std.mem.startsWith(u8, server, "http://"))
        "http://".len
    else
        return error.UnsafeServerUrl;
    const rest = server[prefix_len..];
    const end = std.mem.indexOfAny(u8, rest, "/?#") orelse rest.len;
    const authority = rest[0..end];
    if (authority.len == 0 or std.mem.indexOfScalar(u8, authority, '@') != null)
        return error.UnsafeServerUrl;
    return authority;
}

pub fn printManifest(
    allocator: std.mem.Allocator,
    io: std.Io,
    context_name: []const u8,
    kubeconfig_path: ?[]const u8,
) !void {
    var actual = try resolveIdentity(allocator, io, context_name, kubeconfig_path);
    defer actual.deinit(allocator);
    var buffer: [max_manifest_bytes]u8 = undefined;
    const encoded = try encodeManifest(.{
        .schema_version = schema_version,
        .context = actual.context,
        .cluster = actual.cluster,
        .server_host = actual.server_host,
        .fingerprint = actual.fingerprint,
    }, &buffer);
    std.debug.print("{s}\n", .{encoded});
}

pub fn encodeManifest(manifest: Manifest, buffer: []u8) ![]const u8 {
    var output: std.Io.Writer = .fixed(buffer);
    try std.json.Stringify.value(manifest, .{}, &output);
    return output.buffered();
}

pub fn validateManifest(
    allocator: std.mem.Allocator,
    io: std.Io,
    manifest_path: []const u8,
    context_name: []const u8,
    kubeconfig_path: ?[]const u8,
) !void {
    const content = try std.Io.Dir.cwd().readFileAlloc(
        io,
        manifest_path,
        allocator,
        .limited(max_manifest_bytes),
    );
    defer allocator.free(content);
    var parsed = try std.json.parseFromSlice(Manifest, allocator, content, .{
        .ignore_unknown_fields = false,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();
    if (parsed.value.schema_version != schema_version)
        return error.ManifestSchemaMismatch;
    var actual = try resolveIdentity(allocator, io, context_name, kubeconfig_path);
    defer actual.deinit(allocator);
    if (!std.mem.eql(u8, parsed.value.context, actual.context) or
        !std.mem.eql(u8, parsed.value.cluster, actual.cluster) or
        !std.mem.eql(u8, parsed.value.server_host, actual.server_host) or
        parsed.value.fingerprint != actual.fingerprint)
    {
        return error.KubeconfigIdentityMismatch;
    }
}

fn requireEvidenceFd(name: [:0]const u8) !void {
    const raw = std.c.getenv(name.ptr) orelse return error.Task15EvidenceFdRequired;
    const fd = std.fmt.parseInt(std.c.fd_t, std.mem.span(raw), 10) catch
        return error.InvalidTask15EvidenceFd;
    if (fd < 0) return error.InvalidTask15EvidenceFd;
}

pub fn printPreflight() void {
    std.debug.print(
        "{{\"schema_version\":{d},\"network_access\":false,\"live_contact\":false,\"live_mode\":\"--task15-live\",\"manifest_required\":true,\"manifest_fields\":[\"context\",\"cluster\",\"server_host\",\"fingerprint\"],\"evidence_fds\":[\"{s}\",\"{s}\"],\"contexts\":[\"dev4.as\",\"rc.alpha-sense.org\"],\"families\":15,\"diagnostic_controls\":[\"reconnect\",\"stale_rv\"],\"methods\":[\"GET\",\"WATCH\",\"POST:{s}\"],\"audit_redaction\":\"identifiers-and-query-values-fingerprinted\",\"zero_state\":{{\"queue\":0,\"live_children\":0,\"active_identities\":0,\"active_leases\":0,\"retiring_leases\":0}}}}\n",
        .{ schema_version, diagnostic_fd_env, perf_fd_env, ssar_path },
    );
}

test "diagnostic launch requires readonly exact context and no identity override" {
    try std.testing.expectError(error.DiagnosticRequiresReadonly, validateDiagnosticLaunch(.{
        .readonly = false,
        .context = "dev4.as",
    }));
    try std.testing.expectError(error.ContextNotAllowlisted, validateDiagnosticLaunch(.{
        .readonly = true,
        .context = "dev4.as.example",
    }));
    try std.testing.expectError(error.UnsafeClusterOverride, validateDiagnosticLaunch(.{
        .readonly = true,
        .context = "dev4.as",
        .manifest_path = "frozen.json",
        .token = "not-recorded",
    }));
}

test "request allowlist has only fixed SSAR POST exception" {
    try std.testing.expect(requestAllowed(.GET, "/api/v1/pods"));
    try std.testing.expect(requestAllowed(.WATCH, "/api/v1/pods?watch=true"));
    try std.testing.expect(requestAllowed(.POST, ssar_path));
    try std.testing.expect(!requestAllowed(.POST, "/api/v1/namespaces"));
}

test "sanitized audit target removes names namespaces and query values" {
    const target = try sanitizeRequest(
        .GET,
        "/api/v1/namespaces/customer-secret/pods/object-secret/log?container=private",
    );
    try std.testing.expectEqualStrings("core", target.api_group);
    try std.testing.expectEqualStrings("pods", target.resource);
    try std.testing.expectEqualStrings("log", target.subresource);
    try std.testing.expectEqualStrings("namespaced", target.scope);
    var output: [max_record_bytes]u8 = undefined;
    const encoded = try encodeRecord(.{
        .event = .request_audit,
        .context = "dev4.as",
        .scope = target.scope,
        .method = .GET,
        .api_group = target.api_group,
        .resource = target.resource,
        .subresource = target.subresource,
        .identity_fingerprint = target.identity_fingerprint,
        .query_fingerprint = target.query_fingerprint,
    }, &output);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "customer-secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "object-secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "private") == null);
}

test "terminal states distinguish absence RBAC auth and retry" {
    try std.testing.expectEqual(TerminalState.absent, stateForStatus(404, false));
    try std.testing.expectEqual(TerminalState.forbidden, stateForStatus(403, true));
    try std.testing.expectEqual(TerminalState.unauthorized, stateForStatus(401, true));
    try std.testing.expectEqual(TerminalState.transport_retry, stateForStatus(503, true));
}

test "fingerprints do not expose raw RV or continue tokens" {
    try std.testing.expect(fingerprint("rv-secret") != 0);
    try std.testing.expect(fingerprint("rv-secret") != fingerprint("continue-secret"));
    try std.testing.expectEqual(fingerprint("rv-secret"), fingerprint("rv-secret"));
}

test "manifest encoding is valid JSON without doubled quotes" {
    var buffer: [512]u8 = undefined;
    const encoded = try encodeManifest(.{
        .schema_version = schema_version,
        .context = "dev4.as",
        .cluster = "k8s-dev",
        .server_host = "approved.example.test:6443",
        .fingerprint = 42,
    }, &buffer);
    var parsed = try std.json.parseFromSlice(Manifest, std.testing.allocator, encoded, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("dev4.as", parsed.value.context);
    try std.testing.expectEqualStrings("k8s-dev", parsed.value.cluster);
}

test "stale RV control is one-shot and family scoped" {
    _ = consumeStaleRv(.pod);
    _ = consumeStaleRv(.node);
    armStaleRv(.pod);
    try std.testing.expect(!consumeStaleRv(.node));
    try std.testing.expect(consumeStaleRv(.pod));
    try std.testing.expect(!consumeStaleRv(.pod));
}
