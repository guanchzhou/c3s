const std = @import("std");
const h = @import("data_plane_gate_harness.zig");

test "Gate 6 shutdown cancels every child before one root await" {
    try std.testing.expectEqual(@as(usize, 54), h.family_names.len);
    try std.testing.expectEqual(@as(usize, 6), h.ancillary_classes.len);
    try h.expectUnique(&h.ancillary_classes);
    try h.c3s.runTask14ShutdownGate();
    try h.c3s.runTask14PersistentApplyShutdownGate();
}
