const std = @import("std");
const src = @import("src");
const types = src.k8s_types;

test "StatefulSet - Structure" {
    // selector/template are std.json.Value in klient v0.3.2; assert on typed scalars.
    const statefulset = types.StatefulSet{
        .apiVersion = "apps/v1",
        .kind = "StatefulSet",
        .metadata = .{
            .name = "web",
            .namespace = "default",
        },
        .spec = .{
            .replicas = 3,
            .serviceName = "nginx",
            .selector = null,
            .template = null,
        },
    };

    try std.testing.expectEqualStrings("StatefulSet", statefulset.kind.?);
    try std.testing.expectEqualStrings("web", statefulset.metadata.name);
    try std.testing.expectEqual(3, statefulset.spec.?.replicas.?);
    try std.testing.expectEqualStrings("nginx", statefulset.spec.?.serviceName.?);

    std.debug.print("✅ StatefulSet structure test passed\n", .{});
}

test "DaemonSet - Structure" {
    const daemonset = types.DaemonSet{
        .apiVersion = "apps/v1",
        .kind = "DaemonSet",
        .metadata = .{
            .name = "fluentd",
            .namespace = "kube-system",
        },
        .spec = .{
            .selector = null,
            .template = null,
        },
    };

    try std.testing.expectEqualStrings("DaemonSet", daemonset.kind.?);
    try std.testing.expectEqualStrings("fluentd", daemonset.metadata.name);
    try std.testing.expectEqualStrings("kube-system", daemonset.metadata.namespace.?);

    std.debug.print("✅ DaemonSet structure test passed\n", .{});
}

test "Job - Structure" {
    const job = types.Job{
        .apiVersion = "batch/v1",
        .kind = "Job",
        .metadata = .{
            .name = "pi",
        },
        .spec = .{
            .template = null,
            .completions = 1,
            .parallelism = 1,
            .backoffLimit = 4,
        },
    };

    try std.testing.expectEqualStrings("Job", job.kind.?);
    try std.testing.expectEqualStrings("pi", job.metadata.name);
    try std.testing.expectEqual(1, job.spec.?.completions.?);
    try std.testing.expectEqual(4, job.spec.?.backoffLimit.?);

    std.debug.print("✅ Job structure test passed\n", .{});
}

test "CronJob - Structure" {
    const cronjob = types.CronJob{
        .apiVersion = "batch/v1",
        .kind = "CronJob",
        .metadata = .{
            .name = "hello",
        },
        .spec = .{
            .schedule = "*/1 * * * *",
            .jobTemplate = null,
            .successfulJobsHistoryLimit = 3,
            .failedJobsHistoryLimit = 1,
        },
    };

    try std.testing.expectEqualStrings("CronJob", cronjob.kind.?);
    try std.testing.expectEqualStrings("hello", cronjob.metadata.name);
    try std.testing.expectEqualStrings("*/1 * * * *", cronjob.spec.?.schedule.?);
    try std.testing.expectEqual(3, cronjob.spec.?.successfulJobsHistoryLimit.?);

    std.debug.print("✅ CronJob structure test passed\n", .{});
}

test "ReplicaSet - Structure" {
    const replicaset = types.ReplicaSet{
        .apiVersion = "apps/v1",
        .kind = "ReplicaSet",
        .metadata = .{
            .name = "frontend",
        },
        .spec = .{
            .replicas = 3,
            .selector = null,
            .template = null,
        },
    };

    try std.testing.expectEqualStrings("ReplicaSet", replicaset.kind.?);
    try std.testing.expectEqualStrings("frontend", replicaset.metadata.name);
    try std.testing.expectEqual(3, replicaset.spec.?.replicas.?);

    std.debug.print("✅ ReplicaSet structure test passed\n", .{});
}

test "PersistentVolumeClaim - Structure" {
    var access_modes = [_][]const u8{"ReadWriteOnce"};
    const pvc = types.PersistentVolumeClaim{
        .apiVersion = "v1",
        .kind = "PersistentVolumeClaim",
        .metadata = .{
            .name = "myclaim",
        },
        .spec = .{
            .accessModes = @as(?[][]const u8, &access_modes),
            .storageClassName = "standard",
        },
    };

    try std.testing.expectEqualStrings("PersistentVolumeClaim", pvc.kind.?);
    try std.testing.expectEqualStrings("myclaim", pvc.metadata.name);
    try std.testing.expectEqualStrings("standard", pvc.spec.?.storageClassName.?);

    std.debug.print("✅ PersistentVolumeClaim structure test passed\n", .{});
}
