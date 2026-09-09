const h = @import("data_plane_gate_harness.zig");

test "Gate 3 LIST complete precedes watch connected and WATCH data" {
    try h.c3s.runTask14ComposedOrderingGate();
    try h.c3s.k8s_list_watch.runTask14OrderingGate();
}
