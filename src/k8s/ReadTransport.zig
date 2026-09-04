const std = @import("std");
const klient = @import("klient");

pub const PaginationFallback = enum {
    disabled,
    response_size_only,
};

pub const ReadRequest = struct {
    path: []const u8,
    pagination_fallback: PaginationFallback = .disabled,

    pub fn init(path: []const u8) PathError!ReadRequest {
        try validateReadPath(path);
        return .{ .path = path };
    }

    pub fn mayPaginateAfter(self: ReadRequest, err: anyerror) bool {
        return self.pagination_fallback == .response_size_only and err == error.ResponseTooLarge;
    }
};

pub const ResponseMeta = struct {
    status: std.http.Status,
    retry_after_seconds: ?u32 = null,
    content_type: ?[]const u8 = null,
};

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
        const Adapter = struct {
            context: *anyopaque,
            callback: ReadCallback,

            fn receive(
                adapter: *@This(),
                meta: klient.StreamResponseMeta,
                reader: *std.Io.Reader,
            ) anyerror!void {
                return adapter.callback(adapter.context, .{
                    .status = meta.status,
                    .retry_after_seconds = meta.retry_after_seconds,
                    .content_type = meta.content_type,
                }, reader);
            }
        };
        var adapter: Adapter = .{ .context = context, .callback = callback };
        return self.client.streamGet(
            self.io,
            request.path,
            .{ .pretty = false },
            &adapter,
            Adapter.receive,
        );
    }
};

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
    }
}

fn validPathSegment(segment: []const u8) bool {
    if (segment.len == 0) return false;
    if (std.mem.eql(u8, segment, ".") or std.mem.eql(u8, segment, "..")) return false;
    for (segment) |byte| {
        if (byte <= ' ' or byte >= 0x7f) return false;
        if (byte == '/' or byte == '?' or byte == '#' or byte == '\\') return false;
    }
    return true;
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
