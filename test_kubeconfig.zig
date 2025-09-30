const std = @import("std");
const KubeconfigParser = @import("src/k8s/kubeconfig.zig").KubeconfigParser;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var parser = KubeconfigParser.init(allocator);
    var kubeconfig = try parser.load();
    defer kubeconfig.deinit(allocator);

    std.debug.print("Current context: {s}\n", .{kubeconfig.current_context});
    std.debug.print("Found {d} clusters:\n", .{kubeconfig.clusters.len});
    for (kubeconfig.clusters) |cluster| {
        std.debug.print("  - {s}: {s}\n", .{cluster.name, cluster.server});
    }
    std.debug.print("Found {d} contexts:\n", .{kubeconfig.contexts.len});
    for (kubeconfig.contexts) |ctx| {
        std.debug.print("  - {s} (cluster={s}, user={s})\n", .{ctx.name, ctx.cluster, ctx.user});
    }
    std.debug.print("Found {d} users:\n", .{kubeconfig.users.len});
    for (kubeconfig.users) |user| {
        std.debug.print("  - {s}\n", .{user.name});
    }
}
