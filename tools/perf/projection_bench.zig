const std = @import("std");
const c3s = @import("c3s");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();
    _ = args.skip();
    const object_count = if (args.next()) |value|
        try std.fmt.parseInt(usize, value, 10)
    else
        22_115;
    const batch_size = if (args.next()) |value|
        try std.fmt.parseInt(usize, value, 10)
    else
        128;

    const baseline = try c3s.k8s_resource_projection.benchmarkSynthetic(
        allocator,
        object_count,
        batch_size,
        false,
    );
    const optimized = try c3s.k8s_resource_projection.benchmarkSynthetic(
        allocator,
        object_count,
        batch_size,
        true,
    );
    var buffer: [384]u8 = undefined;
    const output = try std.fmt.bufPrint(
        &buffer,
        "objects={} batch={} baseline_initial_ms={d:.3} optimized_initial_ms={d:.3} speedup={d:.2}x single_update_ms={d:.3}\n",
        .{
            optimized.objects,
            optimized.batch_size,
            @as(f64, @floatFromInt(baseline.initial_sync_ns)) / std.time.ns_per_ms,
            @as(f64, @floatFromInt(optimized.initial_sync_ns)) / std.time.ns_per_ms,
            @as(f64, @floatFromInt(baseline.initial_sync_ns)) /
                @as(f64, @floatFromInt(@max(optimized.initial_sync_ns, 1))),
            @as(f64, @floatFromInt(optimized.single_update_ns)) / std.time.ns_per_ms,
        },
    );
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
}
