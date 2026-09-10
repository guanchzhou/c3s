const std = @import("std");
const h = @import("data_plane_gate_harness.zig");

test "Gate 2 production LIST WATCH reaches every migrated view" {
    try std.testing.expectEqual(@as(usize, 54), h.family_names.len);
    try h.c3s.k8s_resource_subscription.runTask14FamilyStackGate();
}

test "Gate 11 ResourceQuota and LimitRange WATCH updates use visible columns" {
    try h.c3s.k8s_resource_subscription.runTask14DeferredDisplayGate();
    try h.c3s.k8s_resource_family_registry.runTask14ProductionScopeGate();
}
