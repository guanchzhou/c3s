const h = @import("data_plane_gate_harness.zig");

test "Gate 4 exact identities isolate concurrent pod metrics and families" {
    try h.c3s.runTask14IdentityGate();
}
