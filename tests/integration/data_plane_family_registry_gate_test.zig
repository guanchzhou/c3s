const std = @import("std");
const h = @import("data_plane_gate_harness.zig");

test "Gate 1 all resource families are registered and discoverable" {
    try std.testing.expectEqual(@as(usize, 54), h.family_names.len);
    try h.expectUnique(&h.family_names);

    var app = try h.c3s.App.init(std.testing.allocator, .{});
    defer app.deinit();
    const entries = app.resource_families.registry.items();
    try std.testing.expectEqual(h.family_names.len, entries.len);
    for (entries, h.family_names, 0..) |*entry, expected_name, i| {
        try std.testing.expectEqualStrings(expected_name, entry.name);
        for (entries[i + 1 ..]) |peer| {
            try std.testing.expect(entry.projection != peer.projection);
            try std.testing.expect(entry.view != peer.view);
        }
        var spec = try entry.taskSpecFn(
            std.testing.allocator,
            "deterministic-context",
            entry.namespace("team-a"),
            entry.projection,
        );
        spec.deinit(std.testing.allocator);
    }

    // Source gate rollback has been deleted; every family is permanently data-plane.
    // Invariant: every entry carries a real projection pointer and a production
    // task-spec builder — there is no enable flag that can disable them.
    for (entries) |entry| {
        try std.testing.expect(@intFromPtr(entry.projection) != 0);
        try std.testing.expect(@intFromPtr(entry.taskSpecFn) != 0);
    }
    try h.c3s.k8s_resource_family_registry.runTask14ProductionScopeGate();
}
