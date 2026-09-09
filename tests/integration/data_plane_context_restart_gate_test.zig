const std = @import("std");
const h = @import("data_plane_gate_harness.zig");

test "Gate 5 context switch cancels awaits and restarts the complete registry" {
    try std.testing.expectEqual(@as(usize, 54), h.family_names.len);
    try h.c3s.runTask14ContextSwitchGate();
}
