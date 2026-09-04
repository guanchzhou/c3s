const std = @import("std");
const klient = @import("klient");
const support = @import("GatewayRecordSupport.zig");

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
