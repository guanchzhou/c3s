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
    var date_child = std.process.Child.init(&[_][]const u8{"date", "+v0.%Y.%m.%d.%H.%M"}, b.allocator);
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

    // Create unit tests for terminal
    const terminal_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/terminal_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const src_module = b.createModule(.{
        .root_source_file = b.path("src/index.zig"),
    });
    terminal_tests.root_module.addImport("src", src_module);

    const run_terminal_tests = b.addRunArtifact(terminal_tests);
    const terminal_test_step = b.step("test-terminal", "Run terminal tests");
    terminal_test_step.dependOn(&run_terminal_tests.step);

    // Create unit tests for header
    const header_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/header_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    header_tests.root_module.addAnonymousImport("src", .{ .root_source_file = b.path("src/index.zig") });

    const run_header_tests = b.addRunArtifact(header_tests);
    const header_test_step = b.step("test-header", "Run header tests");
    header_test_step.dependOn(&run_header_tests.step);

    // Create unit tests for body
    const body_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/body_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    body_tests.root_module.addAnonymousImport("src", .{ .root_source_file = b.path("src/index.zig") });

    const run_body_tests = b.addRunArtifact(body_tests);
    const body_test_step = b.step("test-body", "Run body tests");
    body_test_step.dependOn(&run_body_tests.step);

    // Create unit tests for footer
    const footer_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/footer_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    footer_tests.root_module.addAnonymousImport("src", .{ .root_source_file = b.path("src/index.zig") });

    const run_footer_tests = b.addRunArtifact(footer_tests);
    const footer_test_step = b.step("test-footer", "Run footer tests");
    footer_test_step.dependOn(&run_footer_tests.step);

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

    // Create integration tests
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    integration_tests.root_module.addAnonymousImport("src", .{ .root_source_file = b.path("src/index.zig") });

    const run_integration_tests = b.addRunArtifact(integration_tests);
    const integration_test_step = b.step("test-integration", "Run integration tests");
    integration_test_step.dependOn(&run_integration_tests.step);

    // Create a step to run all tests
    const all_tests_step = b.step("test-all", "Run all tests");
    all_tests_step.dependOn(&run_unit_tests.step);
    all_tests_step.dependOn(&run_terminal_tests.step);
    all_tests_step.dependOn(&run_header_tests.step);
    all_tests_step.dependOn(&run_body_tests.step);
    all_tests_step.dependOn(&run_footer_tests.step);
    all_tests_step.dependOn(&run_app_tests.step);
    all_tests_step.dependOn(&run_integration_tests.step);

    // Create benchmark executable
    const benchmark = b.addExecutable(.{
        .name = "benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/benchmark.zig"),
            .target = target,
            .optimize = .ReleaseFast,
        }),
    });

    const run_benchmark = b.addRunArtifact(benchmark);
    const benchmark_step = b.step("benchmark", "Run benchmarks");
    benchmark_step.dependOn(&run_benchmark.step);
}
