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

    // Build options for embedding version/build number.
    // `-Dversion=vX.Y.Z` is what the tag-triggered release workflow passes so
    // the binary reports the git tag instead of a date stamp.
    const version_override = b.option([]const u8, "version", "Release version (e.g. v0.2.0)");
    // Zig 0.16: std.process.Child.init was removed; use b.runAllowFail for the
    // build-time `date` command (preserves the graceful "v0.unknown" fallback).
    const base_version = version_override orelse blk: {
        var code: u8 = undefined;
        const raw = b.runAllowFail(&[_][]const u8{ "date", "+v0.%Y.%m.%d.%H.%M" }, &code, .inherit) catch break :blk "v0.unknown";
        break :blk std.mem.trimEnd(u8, raw, "\n");
    };
    var build_number = b.option([]const u8, "build", "Build number to append to version (e.g. 123)");
    if (build_number == null) {
        // Zig 0.16: std.fs.cwd() removed; read via std.Io.Dir with the build graph io.
        const file_data = std.Io.Dir.cwd().readFileAlloc(b.graph.io, ".build_number", b.allocator, .limited(64)) catch null;
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

    // Add zig-klient dependency (local)
    const klient = b.dependency("klient", .{
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("klient", klient.module("klient"));

    // Add kubectl-traffic library dependency (local path)
    const kt = b.dependency("kubectl_traffic", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("kubectl_traffic", kt.module("kubectl_traffic"));

    // Shared module exposing the c3s source tree (src/index.zig) to tests with
    // klient + build options wired. Reused as both "src" and "c3s" imports so
    // test targets get a consumable module (index.zig imports klient).
    const c3s_module = b.createModule(.{
        .root_source_file = b.path("src/index.zig"),
        .target = target,
        .optimize = optimize,
    });
    c3s_module.addImport("klient", klient.module("klient"));
    c3s_module.addImport("kubectl_traffic", kt.module("kubectl_traffic"));
    c3s_module.addOptions("c3s_build", build_opts);

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

    // Create unit tests. Root at index.zig (c3s_module), NOT main.zig: index.zig
    // pub-imports every source module, so Zig analyzes them all and discovers
    // every co-located `test{}` block. Rooting at main.zig would silently skip
    // tests in files main's graph doesn't force-analyze.
    const unit_tests = b.addTest(.{
        .root_module = c3s_module,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    // Test targets — every file under tests/ gets a `test-<name>` step and
    // feeds the aggregate `test-all`. Each test module sees the c3s source tree
    // (as both "src" and "c3s"), klient, and build options so any import style
    // resolves; Zig ignores module imports a given test doesn't use.
    const all_tests_step = b.step("test-all", "Run all tests");
    all_tests_step.dependOn(&run_unit_tests.step);

    const TestSpec = struct { step: []const u8, path: []const u8 };
    const test_specs = [_]TestSpec{
        .{ .step = "test-advanced", .path = "tests/advanced_features_test.zig" },
        .{ .step = "test-app", .path = "tests/app_test.zig" },
        .{ .step = "test-basic-workflow", .path = "tests/e2e/basic_workflow_test.zig" },
        .{ .step = "test-integration", .path = "tests/integration/k8s_service_integration_test.zig" },
        .{ .step = "test-k8s-client", .path = "tests/k8s_client_test.zig" },
        .{ .step = "test-k8s-resources", .path = "tests/k8s_resources_test.zig" },
        .{ .step = "test-memory-leak", .path = "tests/memory_leak_test.zig" },
        .{ .step = "test-new-resources", .path = "tests/new_resources_test.zig" },
        .{ .step = "test-retry", .path = "tests/retry_test.zig" },
        .{ .step = "test-k8s-service", .path = "tests/services/k8s_service_test.zig" },
        // ui tests are co-located in their src files (run via the `test`
        // unit-test step, which test-all depends on).
        .{ .step = "test-body-render", .path = "tests/view/body_render_test.zig" },
        .{ .step = "test-resource-view", .path = "tests/view/resource_view_test.zig" },
        .{ .step = "test-resource-views", .path = "tests/view/resource_views_test.zig" },
        // viewmodel tests are co-located in their src files (run via the `test`
        // unit-test step, which test-all depends on).
    };
    for (test_specs) |spec| {
        const t = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(spec.path),
            .target = target,
            .optimize = optimize,
        }) });
        t.root_module.addImport("src", c3s_module);
        t.root_module.addImport("c3s", c3s_module);
        t.root_module.addImport("klient", klient.module("klient"));
        t.root_module.addOptions("c3s_build", build_opts);
        const run = b.addRunArtifact(t);
        const step = b.step(spec.step, b.fmt("Run {s}", .{spec.path}));
        step.dependOn(&run.step);
        all_tests_step.dependOn(&run.step);
    }

    // Clean step — removes .zig-cache to force fresh build
    // Use after patching Zig stdlib or updating dependencies.
    // Zig 0.16: Build.addRemoveDirTree was removed; shell out to rm -rf instead.
    const clean_step = b.step("clean", "Remove .zig-cache for fresh build");
    const clean_cmd = b.addSystemCommand(&[_][]const u8{ "rm", "-rf", ".zig-cache" });
    clean_step.dependOn(&clean_cmd.step);

    // Formatting gate (ghostty/Zig convention: zig fmt is enforced).
    const fmt_step = b.step("fmt", "Check formatting with zig fmt --check");
    const fmt_check = b.addFmt(.{
        .paths = &.{ "src", "tests", "tools", "build.zig" },
        .check = true,
    });
    fmt_step.dependOn(&fmt_check.step);
}
