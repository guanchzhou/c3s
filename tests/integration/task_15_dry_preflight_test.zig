const std = @import("std");
const c3s = @import("c3s");

test "Task 15 dry preflight validates schema controls and request enforcement" {
    const diagnostics = c3s.task15_diagnostics;
    try std.testing.expectEqual(@as(u8, 2), diagnostics.schema_version);
    try std.testing.expectEqual(@as(usize, 15), @typeInfo(diagnostics.Family).@"enum".fields.len);
    try std.testing.expectEqual(@as(usize, 2), diagnostics.allowed_contexts.len);

    inline for (@typeInfo(diagnostics.Family).@"enum".fields) |field| {
        const family = @field(diagnostics.Family, field.name);
        try std.testing.expectEqual(family, try diagnostics.parseFamily(field.name));
    }

    try std.testing.expectError(
        error.Task15ManifestRequired,
        diagnostics.validateDiagnosticLaunch(.{
            .readonly = true,
            .context = "dev4.as",
        }),
    );
    try std.testing.expectError(
        error.InvalidDiagnosticFamily,
        diagnostics.parseFamily("../../pods"),
    );
    try std.testing.expect(diagnostics.requestAllowed(.GET, "/api/v1/pods"));
    try std.testing.expect(diagnostics.requestAllowed(.WATCH, "/api/v1/pods?watch=true"));
    try std.testing.expect(diagnostics.requestAllowed(.POST, diagnostics.ssar_path));
    try std.testing.expect(!diagnostics.requestAllowed(.POST, "/apis/apps/v1/deployments"));
    diagnostics.setLiveMode(true);
    defer diagnostics.setLiveMode(false);
    _ = try diagnostics.enforceRequest(
        .GET,
        "/api/v1/namespaces/private/pods/private/log?container=private",
    );
    try std.testing.expectError(
        error.Task15RequestRejected,
        diagnostics.enforceRequest(
            .POST,
            "/apis/authorization.k8s.io/v1alpha1/subjectaccessreviews",
        ),
    );

    const zero = diagnostics.Snapshot{};
    try std.testing.expectEqual(@as(usize, 0), zero.queue.count);
    try std.testing.expectEqual(@as(usize, 0), zero.queue.bytes);
    try std.testing.expectEqual(@as(usize, 0), zero.supervisor.live);
    try std.testing.expectEqual(@as(usize, 0), zero.leases.active);
    try std.testing.expectEqual(@as(usize, 0), zero.leases.retiring);
}

test "Task 15 live launch requires manifest and both evidence descriptors" {
    if (std.c.getenv("C3S_DIAGNOSTIC_FD") != null or
        std.c.getenv("C3S_PERF_FD") != null)
    {
        return error.SkipZigTest;
    }
    const Env = struct {
        extern "c" fn setenv(
            name: [*:0]const u8,
            value: [*:0]const u8,
            overwrite: c_int,
        ) c_int;
        extern "c" fn unsetenv(name: [*:0]const u8) c_int;
    };
    try std.testing.expectEqual(
        @as(c_int, 0),
        Env.setenv("C3S_DIAGNOSTIC_FD", "2", 1),
    );
    defer _ = Env.unsetenv("C3S_DIAGNOSTIC_FD");
    try std.testing.expectEqual(
        @as(c_int, 0),
        Env.setenv("C3S_PERF_FD", "2", 1),
    );
    defer _ = Env.unsetenv("C3S_PERF_FD");

    try c3s.task15_diagnostics.validateDiagnosticLaunch(.{
        .readonly = true,
        .context = "dev4.as",
        .manifest_path = "frozen.json",
    });
    try std.testing.expectError(
        error.UnsafeClusterOverride,
        c3s.task15_diagnostics.validateDiagnosticLaunch(.{
            .readonly = true,
            .context = "dev4.as",
            .manifest_path = "frozen.json",
            .client_key = "unsafe",
        }),
    );
}

test "Task 15 manifest binds allowlisted context cluster and server identity offline" {
    const diagnostics = c3s.task15_diagnostics;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const kubeconfig =
        \\apiVersion: v1
        \\kind: Config
        \\current-context: dev4.as
        \\clusters:
        \\  - name: k8s-dev
        \\    cluster:
        \\      server: https://approved.example.test:6443/private/path
        \\contexts:
        \\  - name: dev4.as
        \\    context:
        \\      cluster: k8s-dev
        \\      user: frozen-user
        \\users:
        \\  - name: frozen-user
        \\    user: {}
        \\
    ;
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "config",
        .data = kubeconfig,
    });
    const fingerprint = diagnostics.manifestFingerprint(
        "dev4.as",
        "k8s-dev",
        "approved.example.test:6443",
    );
    const manifest = try std.fmt.allocPrint(
        std.testing.allocator,
        "{{\"schema_version\":2,\"context\":\"dev4.as\",\"cluster\":\"k8s-dev\",\"server_host\":\"approved.example.test:6443\",\"fingerprint\":{d}}}",
        .{fingerprint},
    );
    defer std.testing.allocator.free(manifest);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "manifest.json",
        .data = manifest,
    });
    const root = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}",
        .{tmp.sub_path},
    );
    defer std.testing.allocator.free(root);
    const config_path = try std.fs.path.join(std.testing.allocator, &.{ root, "config" });
    defer std.testing.allocator.free(config_path);
    const manifest_path = try std.fs.path.join(std.testing.allocator, &.{ root, "manifest.json" });
    defer std.testing.allocator.free(manifest_path);
    try diagnostics.validateManifest(
        std.testing.allocator,
        std.testing.io,
        manifest_path,
        "dev4.as",
        config_path,
    );

    const changed_config = try std.mem.replaceOwned(
        u8,
        std.testing.allocator,
        kubeconfig,
        "approved.example.test",
        "unapproved.example.test",
    );
    defer std.testing.allocator.free(changed_config);
    try tmp.dir.writeFile(std.testing.io, .{
        .sub_path = "config",
        .data = changed_config,
    });
    try std.testing.expectError(
        error.KubeconfigIdentityMismatch,
        diagnostics.validateManifest(
            std.testing.allocator,
            std.testing.io,
            manifest_path,
            "dev4.as",
            config_path,
        ),
    );
}

test "Task 15 App wiring renders banner and counts exact resource identities" {
    // Source gate overrides have been deleted; all families are permanently data-plane.
    // This test verifies banner rendering and identity counting without source manipulation.
    var app = try c3s.App.init(std.testing.allocator, .{
        .readonly = true,
        .context = "dev4.as",
        .namespace = "frozen-scope",
    });
    defer app.deinit();
    c3s.task15_diagnostics.setLiveMode(true);
    defer c3s.task15_diagnostics.setLiveMode(false);
    try std.testing.expect(!(try app.k8s_service.detectCedarAuth()));
    try std.testing.expectError(
        error.Task15RequestRejected,
        app.k8s_service.listCedarPolicies(),
    );

    try app.header.updateClusterInfo("dev4.as", "frozen", "redacted");
    try app.header.setReadonlyScope(true, "frozen-scope");
    var banner: [128]u8 = undefined;
    try std.testing.expectEqualStrings(
        "READONLY | context: dev4.as | namespace: frozen-scope",
        try app.header.safetyText(&banner),
    );

    try std.testing.expectEqual(@as(usize, 0), app.activeIdentityCount());
    app.active_pod_subscription = .{ .generation = 1, .subscription_id = 1 };
    const first = app.resource_families.registry.entryAt(0) orelse
        return error.MissingFamily;
    first.active = .{ .generation = 1, .subscription_id = 2 };
    try std.testing.expectEqual(@as(usize, 2), app.activeIdentityCount());
    var ancillary_spec = c3s.k8s_lifecycle_inbox.OwnedTaskSpec{
        .lease_purpose = .detail,
    };
    _ = try app.ancillary_requests.startRequest(.detail, 0, &ancillary_spec);
    try std.testing.expectEqual(@as(usize, 3), app.activeIdentityCount());
    first.active = null;
    var terminal: c3s.k8s_lifecycle_inbox.LifecycleCompletion = .{
        .subscription_stopped = .{
            .key = .{ .generation = 1, .subscription_id = 1 },
            .detail = .{ .code = .forbidden, .http_status = 403 },
        },
    };
    c3s.App.appObserveLifecycle(
        &app,
        @ptrCast(&terminal),
        .{ .generation = 1, .subscription_id = 1 },
    );
    try std.testing.expect(app.active_pod_subscription == null);
    const message = app.pods_view.table.error_message orelse
        return error.MissingTerminalUiState;
    try std.testing.expect(std.mem.indexOf(u8, message, "Forbidden") != null);
}

test "Task 15 bookmark and ERROR classification gate is network free" {
    try c3s.k8s_list_watch.runTask15DiagnosticGate();
}
