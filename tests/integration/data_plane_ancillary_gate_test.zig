const std = @import("std");
const h = @import("data_plane_gate_harness.zig");

test "Gate 10 ancillary consumers obey the same lifecycle and queue rules" {
    try std.testing.expectEqual(@as(usize, 6), h.ancillary_classes.len);
    try h.expectUnique(&h.ancillary_classes);
    try h.expectGetOnlyTransport();
    try h.c3s.k8s_header_metrics_request.runTask14HeaderMetricsGate();
    try h.c3s.k8s_header_metrics_request.runTask14HeaderIdentityGate();
    try h.c3s.k8s_traffic_request.runTask14TrafficGate();
    try h.c3s.k8s_traffic_request.runTask14TrafficIdentityGate();
    try h.c3s.k8s_logs_request.runTask14DetailLogsGate();
    try h.c3s.k8s_detail_request.runTask14DetailIdentityGate();
    try h.c3s.k8s_logs_request.runTask14LogsIdentityGate();
    try h.c3s.k8s_authorization_request.runTask14AuthorizationGate();
    try h.c3s.k8s_authorization_request.runTask14AuthorizationIdentityGate();
    try h.c3s.k8s_authorization_request.runTask14AuthorizationUnknownGate();
    try h.c3s.k8s_ancillary_requests.runTask14AncillaryIdentityGate();
    try h.c3s.k8s_ancillary_requests.runTask14ProductionShutdownGate();
    try h.c3s.k8s_ancillary_requests.runTask14SourceAuditGate();
    try h.c3s.runTask14HeaderPeriodicGate();

    const redacted = try h.c3s.secret_decode.redactSecretJson(
        std.testing.allocator,
        "{\"kind\":\"Secret\",\"data\":{\"token\":\"c2VjcmV0\"}}",
    );
    defer std.testing.allocator.free(redacted);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "c2VjcmV0") == null);
    try std.testing.expect(std.mem.indexOf(u8, redacted, "<redacted 8 bytes>") != null);
}
