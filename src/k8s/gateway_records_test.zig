const std = @import("std");
const klient = @import("klient");
const support = @import("GatewayRecordSupport.zig");
const keys = @import("ResourceKey.zig");
const k9s_query = @import("../viewmodel/k9s_query.zig");

const GatewayClassRecord = @import("GatewayClassRecord.zig");
const GatewayRecord = @import("GatewayRecord.zig");
const HTTPRouteRecord = @import("HTTPRouteRecord.zig");
const GRPCRouteRecord = @import("GRPCRouteRecord.zig");
const ReferenceGrantRecord = @import("ReferenceGrantRecord.zig");
const TCPRouteRecord = @import("TCPRouteRecord.zig");
const TLSRouteRecord = @import("TLSRouteRecord.zig");
const UDPRouteRecord = @import("UDPRouteRecord.zig");
const BackendTLSPolicyRecord = @import("BackendTLSPolicyRecord.zig");
const ListenerSetRecord = @import("ListenerSetRecord.zig");

pub const gateway_class_object_json =
    \\{"apiVersion":"gateway.networking.k8s.io/v1","kind":"GatewayClass","metadata":{"uid":"gc-1","name":"envoy","labels":{"app":"envoy","scope":"cluster"}},"spec":{"controllerName":"gateway.envoyproxy.io/gatewayclass-controller"}}
;
pub const gateway_object_json =
    \\{"apiVersion":"gateway.networking.k8s.io/v1","kind":"Gateway","metadata":{"uid":"gw-1","namespace":"edge","name":"public","labels":{"app":"public","tier":"edge"}},"spec":{"gatewayClassName":"envoy","listeners":[{"name":"https","protocol":"HTTPS","port":443}]},"status":{"addresses":[{"type":"IPAddress","value":"10.0.0.1"},{"type":"Hostname","value":"gw.example.com"}]}}
;
pub const http_route_object_json =
    \\{"apiVersion":"gateway.networking.k8s.io/v1","kind":"HTTPRoute","metadata":{"uid":"http-1","namespace":"edge","name":"web"},"spec":{"parentRefs":[{"name":"public","sectionName":"https"}],"hostnames":["www.example.com","api.example.com"],"rules":[{"backendRefs":[{"name":"web","port":8080}]}]}}
;
pub const grpc_route_object_json =
    \\{"apiVersion":"gateway.networking.k8s.io/v1","kind":"GRPCRoute","metadata":{"uid":"grpc-1","namespace":"edge","name":"rpc"},"spec":{"parentRefs":[{"name":"public"}],"hostnames":["grpc.example.com"],"rules":[{"backendRefs":[{"name":"rpc","port":9090}]}]}}
;
pub const reference_grant_object_json =
    \\{"apiVersion":"gateway.networking.k8s.io/v1beta1","kind":"ReferenceGrant","metadata":{"uid":"grant-1","namespace":"backend","name":"allow-edge"},"spec":{"from":[{"group":"gateway.networking.k8s.io","kind":"HTTPRoute","namespace":"edge"}],"to":[{"group":"","kind":"Service","name":"api"}]}}
;
pub const tcp_route_object_json =
    \\{"apiVersion":"gateway.networking.k8s.io/v1","kind":"TCPRoute","metadata":{"uid":"tcp-1","namespace":"edge","name":"tcp"},"spec":{"parentRefs":[{"name":"public"}],"rules":[{"backendRefs":[{"name":"tcp","port":9000}]}]}}
;
pub const tls_route_object_json =
    \\{"apiVersion":"gateway.networking.k8s.io/v1","kind":"TLSRoute","metadata":{"uid":"tls-1","namespace":"edge","name":"tls"},"spec":{"parentRefs":[{"name":"public"}],"hostnames":["secure.example.com"],"rules":[{"backendRefs":[{"name":"tls","port":443}]}]}}
;
pub const udp_route_object_json =
    \\{"apiVersion":"gateway.networking.k8s.io/v1","kind":"UDPRoute","metadata":{"uid":"udp-1","namespace":"edge","name":"udp"},"spec":{"parentRefs":[{"name":"public"}],"rules":[{"backendRefs":[{"name":"udp","port":5353}]}]}}
;
pub const backend_tls_policy_object_json =
    \\{"apiVersion":"gateway.networking.k8s.io/v1","kind":"BackendTLSPolicy","metadata":{"uid":"btls-1","namespace":"edge","name":"backend-tls"},"spec":{"targetRefs":[{"group":"","kind":"Service","name":"api"}],"validation":{"hostname":"api.example.com","wellKnownCACertificates":"System"}}}
;
pub const listener_set_object_json =
    \\{"apiVersion":"gateway.networking.k8s.io/v1","kind":"ListenerSet","metadata":{"uid":"listeners-1","namespace":"edge","name":"extra"},"spec":{"parentRef":{"name":"public"},"listeners":[{"name":"http","protocol":"HTTP","port":80},{"name":"https","protocol":"HTTPS","port":443}]}}
;

fn parse(comptime T: type, json: []const u8) !std.json.Parsed(T) {
    return std.json.parseFromSlice(T, std.testing.allocator, json, .{ .ignore_unknown_fields = true });
}

fn expectColumns(expected: []const []const u8, actual_value: anytype) !void {
    const actual = actual_value;
    defer support.freeColumns(std.testing.allocator, &actual);
    try std.testing.expectEqual(expected.len + 1, actual.len);
    for (expected, actual[0..expected.len]) |want, got| {
        try std.testing.expectEqualStrings(want, got);
    }
    try std.testing.expect(actual[actual.len - 1].len > 0);
}

fn expectCloneFailureSafe(comptime Record: type, source: Record) !void {
    const Exercise = struct {
        fn run(allocator: std.mem.Allocator, value: Record) !void {
            var copy = try value.clone(allocator);
            copy.deinit(allocator);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Exercise.run, .{source});
}

test "Gateway API core records preserve exact columns" {
    var gateway_class_parsed = try parse(klient.GatewayClass,
        \\{"metadata":{"uid":"gc-1","name":"envoy","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"controllerName":"gateway.envoyproxy.io/gatewayclass-controller"}}
    );
    defer gateway_class_parsed.deinit();
    var gateway_class = try GatewayClassRecord.fromGatewayClass(std.testing.allocator, gateway_class_parsed.value);
    defer gateway_class.deinit(std.testing.allocator);
    try expectColumns(
        &.{ "envoy", "gateway.envoyproxy.io/gatewayclass-controller" },
        try gateway_class.columns(std.testing.allocator),
    );

    var gateway_parsed = try parse(klient.Gateway,
        \\{"metadata":{"uid":"gw-1","namespace":"edge","name":"public","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"gatewayClassName":"envoy","listeners":[]},"status":{"addresses":[{"value":"10.0.0.1"},{"value":"gw.example.com"}]}}
    );
    defer gateway_parsed.deinit();
    var gateway = try GatewayRecord.fromGateway(std.testing.allocator, gateway_parsed.value);
    defer gateway.deinit(std.testing.allocator);
    try expectColumns(
        &.{ "edge", "public", "envoy", "10.0.0.1,gw.example.com" },
        try gateway.columns(std.testing.allocator),
    );

    var http_parsed = try parse(klient.HTTPRoute,
        \\{"metadata":{"uid":"http-1","namespace":"edge","name":"web","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"parentRefs":[{"name":"public"}],"hostnames":["www.example.com","api.example.com"]}}
    );
    defer http_parsed.deinit();
    var http = try HTTPRouteRecord.fromHTTPRoute(std.testing.allocator, http_parsed.value);
    defer http.deinit(std.testing.allocator);
    try expectColumns(
        &.{ "edge", "web", "public", "www.example.com,api.example.com" },
        try http.columns(std.testing.allocator),
    );

    var grpc_parsed = try parse(klient.GRPCRoute,
        \\{"metadata":{"uid":"grpc-1","namespace":"edge","name":"rpc","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"parentRefs":[{"name":"public"}],"hostnames":["grpc.example.com"]}}
    );
    defer grpc_parsed.deinit();
    var grpc = try GRPCRouteRecord.fromGRPCRoute(std.testing.allocator, grpc_parsed.value);
    defer grpc.deinit(std.testing.allocator);
    try expectColumns(
        &.{ "edge", "rpc", "public", "grpc.example.com" },
        try grpc.columns(std.testing.allocator),
    );

    var grant_parsed = try parse(klient.ReferenceGrant,
        \\{"metadata":{"uid":"grant-1","namespace":"backend","name":"allow-edge","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"from":[{"kind":"HTTPRoute"}],"to":[{"kind":"Service"}]}}
    );
    defer grant_parsed.deinit();
    var grant = try ReferenceGrantRecord.fromReferenceGrant(std.testing.allocator, grant_parsed.value);
    defer grant.deinit(std.testing.allocator);
    try expectColumns(
        &.{ "backend", "allow-edge", "HTTPRoute", "Service" },
        try grant.columns(std.testing.allocator),
    );

    try expectCloneFailureSafe(GatewayClassRecord.GatewayClassRecord, gateway_class);
    try expectCloneFailureSafe(GatewayRecord.GatewayRecord, gateway);
    try expectCloneFailureSafe(HTTPRouteRecord.HTTPRouteRecord, http);
    try expectCloneFailureSafe(GRPCRouteRecord.GRPCRouteRecord, grpc);
    try expectCloneFailureSafe(ReferenceGrantRecord.ReferenceGrantRecord, grant);
}

test "Gateway API extension records preserve exact columns" {
    var tcp_parsed = try parse(klient.TCPRoute,
        \\{"metadata":{"uid":"tcp-1","namespace":"edge","name":"tcp","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"parentRefs":[{"name":"public"}]}}
    );
    defer tcp_parsed.deinit();
    var tcp = try TCPRouteRecord.fromTCPRoute(std.testing.allocator, tcp_parsed.value);
    defer tcp.deinit(std.testing.allocator);
    try expectColumns(&.{ "edge", "tcp", "public" }, try tcp.columns(std.testing.allocator));

    var tls_parsed = try parse(klient.TLSRoute,
        \\{"metadata":{"uid":"tls-1","namespace":"edge","name":"tls","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"parentRefs":[{"name":"public"}],"hostnames":["secure.example.com"]}}
    );
    defer tls_parsed.deinit();
    var tls = try TLSRouteRecord.fromTLSRoute(std.testing.allocator, tls_parsed.value);
    defer tls.deinit(std.testing.allocator);
    try expectColumns(
        &.{ "edge", "tls", "public", "secure.example.com" },
        try tls.columns(std.testing.allocator),
    );

    var udp_parsed = try parse(klient.UDPRoute,
        \\{"metadata":{"uid":"udp-1","namespace":"edge","name":"udp","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"parentRefs":[{"name":"public"}]}}
    );
    defer udp_parsed.deinit();
    var udp = try UDPRouteRecord.fromUDPRoute(std.testing.allocator, udp_parsed.value);
    defer udp.deinit(std.testing.allocator);
    try expectColumns(&.{ "edge", "udp", "public" }, try udp.columns(std.testing.allocator));

    var policy_parsed = try parse(klient.BackendTLSPolicy,
        \\{"metadata":{"uid":"btls-1","namespace":"edge","name":"backend-tls","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"targetRefs":[{"name":"api"}]}}
    );
    defer policy_parsed.deinit();
    var policy = try BackendTLSPolicyRecord.fromBackendTLSPolicy(std.testing.allocator, policy_parsed.value);
    defer policy.deinit(std.testing.allocator);
    try expectColumns(&.{ "edge", "backend-tls", "api" }, try policy.columns(std.testing.allocator));

    var listeners_parsed = try parse(klient.ListenerSet,
        \\{"metadata":{"uid":"listeners-1","namespace":"edge","name":"extra","creationTimestamp":"2024-01-01T00:00:00Z"},"spec":{"parentRef":{"name":"public"},"listeners":[{},{}]}}
    );
    defer listeners_parsed.deinit();
    var listeners = try ListenerSetRecord.fromListenerSet(std.testing.allocator, listeners_parsed.value);
    defer listeners.deinit(std.testing.allocator);
    try expectColumns(&.{ "edge", "extra", "public", "2" }, try listeners.columns(std.testing.allocator));

    try expectCloneFailureSafe(TCPRouteRecord.TCPRouteRecord, tcp);
    try expectCloneFailureSafe(TLSRouteRecord.TLSRouteRecord, tls);
    try expectCloneFailureSafe(UDPRouteRecord.UDPRouteRecord, udp);
    try expectCloneFailureSafe(BackendTLSPolicyRecord.BackendTLSPolicyRecord, policy);
    try expectCloneFailureSafe(ListenerSetRecord.ListenerSetRecord, listeners);
}

test "Gateway API records reject UID-less resources" {
    const metadata = klient.ObjectMeta{ .name = "missing-uid" };
    try std.testing.expectError(error.MissingUid, GatewayClassRecord.fromGatewayClass(std.testing.allocator, .{ .metadata = metadata }));
    try std.testing.expectError(error.MissingUid, GatewayRecord.fromGateway(std.testing.allocator, .{ .metadata = metadata }));
    try std.testing.expectError(error.MissingUid, HTTPRouteRecord.fromHTTPRoute(std.testing.allocator, .{ .metadata = metadata }));
    try std.testing.expectError(error.MissingUid, GRPCRouteRecord.fromGRPCRoute(std.testing.allocator, .{ .metadata = metadata }));
    try std.testing.expectError(error.MissingUid, ReferenceGrantRecord.fromReferenceGrant(std.testing.allocator, .{ .metadata = metadata }));
    try std.testing.expectError(error.MissingUid, TCPRouteRecord.fromTCPRoute(std.testing.allocator, .{ .metadata = metadata }));
    try std.testing.expectError(error.MissingUid, TLSRouteRecord.fromTLSRoute(std.testing.allocator, .{ .metadata = metadata }));
    try std.testing.expectError(error.MissingUid, UDPRouteRecord.fromUDPRoute(std.testing.allocator, .{ .metadata = metadata }));
    try std.testing.expectError(error.MissingUid, BackendTLSPolicyRecord.fromBackendTLSPolicy(std.testing.allocator, .{ .metadata = metadata }));
    try std.testing.expectError(error.MissingUid, ListenerSetRecord.fromListenerSet(std.testing.allocator, .{ .metadata = metadata }));
}

fn ignoreDecoded(comptime T: type) fn (*const T) anyerror!void {
    return struct {
        fn run(_: *const T) anyerror!void {}
    }.run;
}

fn expectGatewayListeners(object: *const klient.Gateway) anyerror!void {
    const spec = object.spec orelse return error.MissingSpec;
    try std.testing.expect(spec.listeners.len > 0);
}

fn expectRouteRules(comptime T: type) fn (*const T) anyerror!void {
    return struct {
        fn run(object: *const T) anyerror!void {
            const spec = object.spec orelse return error.MissingSpec;
            const rules = spec.rules orelse return error.MissingRules;
            try std.testing.expect(rules.len > 0);
        }
    }.run;
}

fn expectBackendTlsValidation(object: *const klient.BackendTLSPolicy) anyerror!void {
    const spec = object.spec orelse return error.MissingSpec;
    const validation = spec.validation orelse return error.MissingValidation;
    try std.testing.expect(validation == .object);
}

/// A projected record must carry the flattened `metadata.labels` its object
/// declared, bounded, so `-l` filters work on rows that never left the wire.
fn expectProjectedLabels(labels: []const u8, expected_labels: []const u8) !void {
    try std.testing.expectEqualStrings(expected_labels, labels);
    try std.testing.expect(labels.len <= keys.max_projected_label_bytes);
    if (expected_labels.len > 0) {
        try std.testing.expect(k9s_query.labelsMatch(labels, expected_labels));
    }
}

fn exerciseRealShapedDecode(
    comptime T: type,
    comptime Record: type,
    comptime fromObject: fn (std.mem.Allocator, T) anyerror!Record,
    comptime object_json: []const u8,
    comptime path: []const u8,
    comptime expected: []const []const u8,
    comptime expected_labels: []const u8,
    comptime verify: fn (*const T) anyerror!void,
) !void {
    const stream_list = @import("StreamList.zig");
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const ResponseScript = @import("FakeTransport.zig").ResponseScript;
    const read_transport = @import("ReadTransport.zig");
    const Capture = struct {
        expected: []const []const u8,

        fn receive(self: *@This(), items: []const T) !void {
            try std.testing.expectEqual(@as(usize, 1), items.len);
            try verify(&items[0]);
            var record = try fromObject(std.testing.allocator, items[0]);
            defer record.deinit(std.testing.allocator);
            try expectProjectedLabels(record.key.labels, expected_labels);
            const columns = try record.columns(std.testing.allocator);
            defer support.freeColumns(std.testing.allocator, &columns);
            for (columns, self.expected) |actual, wanted|
                try std.testing.expectEqualStrings(wanted, actual);
        }
    };
    const Clock = struct {
        fn now(_: *anyopaque) u64 {
            return 0;
        }
    };
    const list_json = "{\"metadata\":{\"resourceVersion\":\"17\"},\"items\":[" ++ object_json ++ "]}";
    const scripts = [_]ResponseScript{.{ .body = list_json }};
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    var capture = Capture{ .expected = expected };
    var clock_context: u8 = 0;
    var result = try stream_list.stream(
        T,
        std.testing.allocator,
        fake.transport(),
        try read_transport.ReadRequest.init(path),
        .{ .clock = .{ .ptr = &clock_context, .now_ns_fn = Clock.now } },
        &capture,
        Capture.receive,
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("17", result.resource_version);

    const watch_json = "{\"type\":\"MODIFIED\",\"object\":" ++ object_json ++ "}";
    var parsed_watch = try std.json.parseFromSlice(
        klient.Watcher(T).WatchEnvelope,
        std.testing.allocator,
        watch_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed_watch.deinit();
    try verify(&parsed_watch.value.object.?);
    var watch_record = try fromObject(std.testing.allocator, parsed_watch.value.object.?);
    defer watch_record.deinit(std.testing.allocator);
    try expectProjectedLabels(watch_record.key.labels, expected_labels);
    const watch_columns = try watch_record.columns(std.testing.allocator);
    defer support.freeColumns(std.testing.allocator, &watch_columns);
    for (watch_columns, expected) |actual, wanted|
        try std.testing.expectEqualStrings(wanted, actual);
}

test "real-shaped GatewayClass LIST and WATCH decode projected columns" {
    try exerciseRealShapedDecode(klient.GatewayClass, GatewayClassRecord.GatewayClassRecord, GatewayClassRecord.fromGatewayClass, gateway_class_object_json, "/apis/gateway.networking.k8s.io/v1/gatewayclasses", &.{ "envoy", "gateway.envoyproxy.io/gatewayclass-controller", "n/a" }, "app=envoy,scope=cluster", ignoreDecoded(klient.GatewayClass));
}

test "real-shaped Gateway LIST and WATCH decode projected columns" {
    try exerciseRealShapedDecode(klient.Gateway, GatewayRecord.GatewayRecord, GatewayRecord.fromGateway, gateway_object_json, "/apis/gateway.networking.k8s.io/v1/gateways", &.{ "edge", "public", "envoy", "10.0.0.1,gw.example.com", "n/a" }, "app=public,tier=edge", expectGatewayListeners);
}

test "real-shaped HTTPRoute LIST and WATCH decode projected columns" {
    try exerciseRealShapedDecode(klient.HTTPRoute, HTTPRouteRecord.HTTPRouteRecord, HTTPRouteRecord.fromHTTPRoute, http_route_object_json, "/apis/gateway.networking.k8s.io/v1/httproutes", &.{ "edge", "web", "public", "www.example.com,api.example.com", "n/a" }, "", ignoreDecoded(klient.HTTPRoute));
}

test "real-shaped GRPCRoute LIST and WATCH decode projected columns" {
    try exerciseRealShapedDecode(klient.GRPCRoute, GRPCRouteRecord.GRPCRouteRecord, GRPCRouteRecord.fromGRPCRoute, grpc_route_object_json, "/apis/gateway.networking.k8s.io/v1/grpcroutes", &.{ "edge", "rpc", "public", "grpc.example.com", "n/a" }, "", ignoreDecoded(klient.GRPCRoute));
}

test "real-shaped ReferenceGrant LIST and WATCH decode projected columns" {
    try exerciseRealShapedDecode(klient.ReferenceGrant, ReferenceGrantRecord.ReferenceGrantRecord, ReferenceGrantRecord.fromReferenceGrant, reference_grant_object_json, "/apis/gateway.networking.k8s.io/v1beta1/referencegrants", &.{ "backend", "allow-edge", "HTTPRoute", "Service", "n/a" }, "", ignoreDecoded(klient.ReferenceGrant));
}

test "real-shaped TCPRoute LIST and WATCH decode projected columns" {
    try exerciseRealShapedDecode(klient.TCPRoute, TCPRouteRecord.TCPRouteRecord, TCPRouteRecord.fromTCPRoute, tcp_route_object_json, "/apis/gateway.networking.k8s.io/v1/tcproutes", &.{ "edge", "tcp", "public", "n/a" }, "", expectRouteRules(klient.TCPRoute));
}

test "real-shaped TLSRoute LIST and WATCH decode projected columns" {
    try exerciseRealShapedDecode(klient.TLSRoute, TLSRouteRecord.TLSRouteRecord, TLSRouteRecord.fromTLSRoute, tls_route_object_json, "/apis/gateway.networking.k8s.io/v1/tlsroutes", &.{ "edge", "tls", "public", "secure.example.com", "n/a" }, "", expectRouteRules(klient.TLSRoute));
}

test "real-shaped UDPRoute LIST and WATCH decode projected columns" {
    try exerciseRealShapedDecode(klient.UDPRoute, UDPRouteRecord.UDPRouteRecord, UDPRouteRecord.fromUDPRoute, udp_route_object_json, "/apis/gateway.networking.k8s.io/v1/udproutes", &.{ "edge", "udp", "public", "n/a" }, "", expectRouteRules(klient.UDPRoute));
}

test "real-shaped BackendTLSPolicy LIST and WATCH decode projected columns" {
    try exerciseRealShapedDecode(klient.BackendTLSPolicy, BackendTLSPolicyRecord.BackendTLSPolicyRecord, BackendTLSPolicyRecord.fromBackendTLSPolicy, backend_tls_policy_object_json, "/apis/gateway.networking.k8s.io/v1/backendtlspolicies", &.{ "edge", "backend-tls", "api", "n/a" }, "", expectBackendTlsValidation);
}

test "real-shaped ListenerSet LIST and WATCH decode projected columns" {
    try exerciseRealShapedDecode(klient.ListenerSet, ListenerSetRecord.ListenerSetRecord, ListenerSetRecord.fromListenerSet, listener_set_object_json, "/apis/gateway.networking.k8s.io/v1/listenersets", &.{ "edge", "extra", "public", "2", "n/a" }, "", ignoreDecoded(klient.ListenerSet));
}
