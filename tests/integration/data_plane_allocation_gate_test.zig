const std = @import("std");
const h = @import("data_plane_gate_harness.zig");

test "Gate 8 allocation failures are atomic across queue view and lifecycle" {
    const representative = [_][]const u8{ "PodRecord", "ServiceRecord", "NodeRecord", "GatewayRecord" };
    try h.expectUnique(&representative);
    try h.c3s.k8s_resource_subscription.runTask14RecordContractGate();
    try h.c3s.k8s_resource_projection.runTask14ProjectionAllocationOrdinalsGate();
    try h.c3s.runTask14AllocationOrdinalsGate();
    try h.c3s.runTask14ShutdownDrainAllocationOrdinalsGate();
    try h.c3s.k8s_traffic_request.runTask14SinkCreateFailureOwnershipGate();
    try std.testing.expectEqual(@as(usize, 4), representative.len);
}
