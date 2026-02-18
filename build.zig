const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Build options for embedding version/build number
    var date_child = std.process.Child.init(&[_][]const u8{ "date", "+v0.%Y.%m.%d.%H.%M" }, b.allocator);
    date_child.stdin_behavior = .Ignore;
    date_child.stdout_behavior = .Pipe;
    date_child.stderr_behavior = .Inherit;
    const base_version = blk: {
        if (date_child.spawn() catch null) |_| {
            const stdout_stream = date_child.stdout orelse {
                _ = date_child.wait() catch null;
                break :blk "v0.unknown";
            };
            const raw = stdout_stream.readToEndAlloc(b.allocator, 128) catch {
                _ = date_child.wait() catch null;
                break :blk "v0.unknown";
            };
            _ = date_child.wait() catch null;
            break :blk std.mem.trimRight(u8, raw, "\n");
        } else {
            break :blk "v0.unknown";
        }
    };
    var build_number = b.option([]const u8, "build", "Build number to append to version (e.g. 123)");
    if (build_number == null) {
        const cwd = std.fs.cwd();
        const file_data = cwd.readFileAlloc(b.allocator, ".build_number", 64) catch null;
        if (file_data) |bytes| {
            const trimmed = std.mem.trim(u8, bytes, " \n\r\t");
            build_number = trimmed;
        } else {
            build_number = "";
        }
    }
    const build_opts = b.addOptions();
    build_opts.addOption([]const u8, "base_version", base_version);
    build_opts.addOption([]const u8, "build_number", build_number.?);

    // Create the main executable
    const exe = b.addExecutable(.{
        .name = "c3s",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Import dependencies
    exe.root_module.addOptions("c3s_build", build_opts);

    // Add zig-yaml dependency (Zig 0.15.0 compatible branch)
    const yaml = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("yaml", yaml.module("yaml"));

    // Add zig-klient dependency (local)
    const klient = b.dependency("klient", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("klient", klient.module("klient"));

    // Bump step: increments .build_number using a small Zig tool
    const bump_exe = b.addExecutable(.{
        .name = "bump_build",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/bump_build.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const bump_run = b.addRunArtifact(bump_exe);
    const bump_step = b.step("bump", "Increment .build_number");
    bump_step.dependOn(&bump_run.step);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // Install bundled skins alongside the binary
    b.installDirectory(.{
        .source_dir = b.path("skins"),
        .install_dir = .{ .custom = "bin" },
        .install_subdir = "skins",
    });

    // Create a run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Create unit tests
    const unit_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Create unit tests for app
    const app_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/app_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    app_tests.root_module.addAnonymousImport("src", .{ .root_source_file = b.path("src/index.zig") });

    const run_app_tests = b.addRunArtifact(app_tests);
    const app_test_step = b.step("test-app", "Run app tests");
    app_test_step.dependOn(&run_app_tests.step);

    // Create integration tests (requires real Kubernetes cluster)
    const c3s_module = b.createModule(.{
        .root_source_file = b.path("src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    c3s_module.addImport("klient", klient.module("klient"));
    c3s_module.addImport("yaml", yaml.module("yaml"));
    c3s_module.addOptions("c3s_build", build_opts);

    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/k8s_service_integration_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    integration_tests.root_module.addImport("c3s", c3s_module);
    integration_tests.root_module.addImport("klient", klient.module("klient"));
    integration_tests.root_module.addImport("yaml", yaml.module("yaml"));
    integration_tests.root_module.addOptions("c3s_build", build_opts);

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "Run integration tests (requires K8s cluster)");
    integration_test_step.dependOn(&run_integration_tests.step);

    // Create K8s client unit tests
    const k8s_client_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/k8s_client_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    k8s_client_tests.root_module.addAnonymousImport("src", .{ .root_source_file = b.path("src/index.zig") });

    const run_k8s_client_tests = b.addRunArtifact(k8s_client_tests);
    const k8s_client_test_step = b.step("test-k8s-client", "Run K8s client tests");
    k8s_client_test_step.dependOn(&run_k8s_client_tests.step);

    // Create K8s resources integration tests
    const k8s_resources_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/k8s_resources_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    k8s_resources_tests.root_module.addAnonymousImport("src", .{ .root_source_file = b.path("src/index.zig") });

    const run_k8s_resources_tests = b.addRunArtifact(k8s_resources_tests);
    const k8s_resources_test_step = b.step("test-k8s-resources", "Run K8s resources integration tests");
    k8s_resources_test_step.dependOn(&run_k8s_resources_tests.step);

    // Create retry tests
    const retry_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/retry_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    retry_tests.root_module.addAnonymousImport("src", .{ .root_source_file = b.path("src/index.zig") });

    const run_retry_tests = b.addRunArtifact(retry_tests);
    const retry_test_step = b.step("test-retry", "Run retry logic tests");
    retry_test_step.dependOn(&run_retry_tests.step);

    // Create new resources tests
    const new_resources_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/new_resources_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    new_resources_tests.root_module.addAnonymousImport("src", .{ .root_source_file = b.path("src/index.zig") });

    const run_new_resources_tests = b.addRunArtifact(new_resources_tests);
    const new_resources_test_step = b.step("test-new-resources", "Run new resources structure tests");
    new_resources_test_step.dependOn(&run_new_resources_tests.step);

    // Create advanced features tests
    const advanced_features_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/advanced_features_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    advanced_features_tests.root_module.addAnonymousImport("src", .{ .root_source_file = b.path("src/index.zig") });

    const run_advanced_features_tests = b.addRunArtifact(advanced_features_tests);
    const advanced_features_test_step = b.step("test-advanced", "Run advanced features tests (TLS, Pool, CRD)");
    advanced_features_test_step.dependOn(&run_advanced_features_tests.step);

    // Create K8s service unit tests
    const k8s_service_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/services/k8s_service_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    k8s_service_tests.root_module.addImport("c3s", c3s_module);

    const run_k8s_service_tests = b.addRunArtifact(k8s_service_tests);
    const k8s_service_test_step = b.step("test-k8s-service", "Run K8s service unit tests");
    k8s_service_test_step.dependOn(&run_k8s_service_tests.step);

    // Create authorization view tests
    const auth_view_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/view/authorization_view_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    auth_view_tests.root_module.addImport("c3s", c3s_module);

    const run_auth_view_tests = b.addRunArtifact(auth_view_tests);
    const auth_view_test_step = b.step("test-auth-view", "Run authorization view tests");
    auth_view_test_step.dependOn(&run_auth_view_tests.step);

    // Create table state unit tests
    const table_state_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/ui/table_state_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    table_state_tests.root_module.addImport("c3s", c3s_module);

    const run_table_state_tests = b.addRunArtifact(table_state_tests);
    const table_state_test_step = b.step("test-table-state", "Run table state unit tests");
    table_state_test_step.dependOn(&run_table_state_tests.step);

    // Create sort utility tests
    const sort_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/viewmodel/sort_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sort_tests.root_module.addImport("c3s", c3s_module);

    const run_sort_tests = b.addRunArtifact(sort_tests);
    const sort_test_step = b.step("test-sort", "Run sort utility tests");
    sort_test_step.dependOn(&run_sort_tests.step);

    // Create view trait tests
    const view_trait_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/viewmodel/view_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    view_trait_tests.root_module.addImport("c3s", c3s_module);

    const run_view_trait_tests = b.addRunArtifact(view_trait_tests);
    const view_trait_test_step = b.step("test-view-trait", "Run view trait tests");
    view_trait_test_step.dependOn(&run_view_trait_tests.step);

    // Create a step to run all tests
    const all_tests_step = b.step("test-all", "Run all tests");
    all_tests_step.dependOn(&run_unit_tests.step);
    all_tests_step.dependOn(&run_app_tests.step);
    all_tests_step.dependOn(&run_integration_tests.step);
    all_tests_step.dependOn(&run_k8s_client_tests.step);
    all_tests_step.dependOn(&run_k8s_resources_tests.step);
    all_tests_step.dependOn(&run_retry_tests.step);
    all_tests_step.dependOn(&run_new_resources_tests.step);
    all_tests_step.dependOn(&run_advanced_features_tests.step);
    all_tests_step.dependOn(&run_k8s_service_tests.step);
    all_tests_step.dependOn(&run_auth_view_tests.step);
    all_tests_step.dependOn(&run_table_state_tests.step);
    all_tests_step.dependOn(&run_sort_tests.step);
    all_tests_step.dependOn(&run_view_trait_tests.step);
}
