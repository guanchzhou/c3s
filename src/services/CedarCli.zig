// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Runs the official `cedar` binary (cedar-policy-cli) on policy text c3s has read
// out of `cedar.k8s.aws` Policy objects.
//
// Why shell out at all, in a program that otherwise speaks to the API server
// directly: Cedar's evaluator is Rust with no stable C ABI and no Zig port. A
// reimplementation would be a second, divergent evaluator -- and a policy engine that
// disagrees with the real one about a `forbid` is worse than no engine. The official
// binary is the only thing that can answer authoritatively, so it is what runs.
//
// Everything here is read-only with respect to the cluster: policy text goes out to a
// private temporary file, `cedar` reads it, and the answer comes back. Nothing is
// written to Kubernetes.

const std = @import("std");
const builtin = @import("builtin");
const runtime = @import("../core/runtime.zig");
const Logger = @import("../core/logger.zig");
const env = @import("../core/env.zig");

/// Per-policy source limit. A Policy CR far past this is not something a reviewer is
/// reading in a terminal pane, and feeding it to `cedar` only delays the answer.
pub const max_policy_bytes: usize = 256 * 1024;

/// Upper bound on how many Policy objects one scan or authorization will consider.
pub const max_policies: usize = 1000;

/// Output cap for one `cedar` invocation.
const output_limit: usize = 1024 * 1024;

/// `cedar` exits 2 to mean "evaluated fine, the answer is DENY". Any other nonzero
/// exit means the run itself failed.
const deny_exit_code: u8 = 2;

pub const Error = error{
    CedarNotFound,
    CedarFailed,
    PolicyTooLarge,
    Canceled,
};

/// The outcome of a check that either passes or does not, with whatever `cedar`
/// printed. Diagnostics are the point of the feature -- a bare "invalid" tells a
/// reviewer nothing -- so they are always captured, on success as well as failure.
pub const Outcome = struct {
    ok: bool,
    diagnostics: []u8,

    pub fn deinit(self: *Outcome, allocator: std.mem.Allocator) void {
        allocator.free(self.diagnostics);
    }
};

/// Fail-closed by construction: there is no way to spell "probably allowed".
pub const Decision = enum {
    allow,
    deny,
    /// The evidence was incomplete or the evaluation failed. Never rendered as a
    /// permission, and never derived from a partial policy set.
    indeterminate,

    pub fn label(self: Decision) []const u8 {
        return switch (self) {
            .allow => "ALLOW",
            .deny => "DENY",
            .indeterminate => "INDETERMINATE",
        };
    }
};

pub const AuthorizeResult = struct {
    decision: Decision,
    diagnostics: []u8,
    /// The policies Cedar named as determining the answer, comma-separated. Empty
    /// when Cedar did not name any.
    determining: []u8,

    pub fn deinit(self: *AuthorizeResult, allocator: std.mem.Allocator) void {
        allocator.free(self.diagnostics);
        allocator.free(self.determining);
    }
};

pub const AuthorizeInput = struct {
    policies: []const u8,
    entities_json: []const u8,
    context_json: []const u8 = "{}",
    principal: []const u8,
    action: []const u8,
    resource: []const u8,
    schema_path: ?[]const u8 = null,
};

/// Files in the workspace are owner-only: policy text is security-relevant, and a
/// shared /tmp is not a private place to leave it.
const private_file: std.Io.Dir.Permissions = if (builtin.os.tag == .windows)
    .default_file
else
    @enumFromInt(0o600);

const private_dir: std.Io.Dir.Permissions = if (builtin.os.tag == .windows)
    .default_dir
else
    @enumFromInt(0o700);

pub const CedarCli = struct {
    allocator: std.mem.Allocator,
    /// Absolute path to the `cedar` binary, or null when it is not installed. Null is
    /// a supported state: the policy list still works, the analysis keys report why
    /// they cannot.
    binary: ?[]u8,
    /// Private scratch directory, created on first use and removed on deinit.
    workspace: ?[]u8 = null,
    /// Distinguishes temp file names within one workspace.
    sequence: u32 = 0,

    pub fn init(allocator: std.mem.Allocator) CedarCli {
        return .{ .allocator = allocator, .binary = locate(allocator) };
    }

    pub fn deinit(self: *CedarCli) void {
        if (self.binary) |path| self.allocator.free(path);
        if (self.workspace) |path| {
            std.Io.Dir.cwd().deleteTree(runtime.io(), path) catch |err| {
                Logger.warn("Failed to remove Cedar workspace {s}: {any}", .{ path, err });
            };
            self.allocator.free(path);
        }
    }

    pub fn available(self: *const CedarCli) bool {
        return self.binary != null;
    }

    /// One-line explanation for the UI when `cedar` is missing. Naming the install
    /// command is the difference between a dead key and a two-minute fix.
    pub const missing_hint =
        "cedar not found on PATH. Install cedar-policy-cli (cargo install cedar-policy-cli) " ++
        "or download a cedar-policy-cli release, then reopen this view.";

    /// `cedar check-parse` on one policy's source.
    pub fn checkParse(self: *CedarCli, content: []const u8) !Outcome {
        const policy_file = try self.writeTemp("policy", ".cedar", content);
        defer self.removeTemp(policy_file);
        return self.runOutcome(&.{ "check-parse", "--policies", policy_file });
    }

    /// `cedar format`. On success the diagnostics field holds the formatted source,
    /// which is what the caller displays.
    pub fn format(self: *CedarCli, content: []const u8) !Outcome {
        const policy_file = try self.writeTemp("policy", ".cedar", content);
        defer self.removeTemp(policy_file);
        return self.runOutcome(&.{ "format", "--policies", policy_file });
    }

    /// `cedar validate` against a schema the user supplied. Validation is optional in
    /// Cedar and there is no schema in the CRD, so the path comes from the caller.
    pub fn validate(self: *CedarCli, content: []const u8, schema_path: []const u8) !Outcome {
        const policy_file = try self.writeTemp("policy", ".cedar", content);
        defer self.removeTemp(policy_file);
        return self.runOutcome(&.{
            "validate", "--schema", schema_path, "--policies", policy_file,
        });
    }

    /// `cedar authorize` against an already-assembled policy set.
    ///
    /// The caller is responsible for the set being complete: this function answers
    /// about exactly the policies it is handed, and cannot know that one was dropped.
    pub fn authorize(self: *CedarCli, input: AuthorizeInput) !AuthorizeResult {
        const policy_file = try self.writeTemp("policies", ".cedar", input.policies);
        defer self.removeTemp(policy_file);
        const entities_file = try self.writeTemp("entities", ".json", input.entities_json);
        defer self.removeTemp(entities_file);
        const context_file = try self.writeTemp("context", ".json", input.context_json);
        defer self.removeTemp(context_file);

        var argv = std.ArrayListUnmanaged([]const u8).empty;
        defer argv.deinit(self.allocator);
        try argv.appendSlice(self.allocator, &.{
            "authorize",   "-v",
            "--policies",  policy_file,
            "--entities",  entities_file,
            "--context",   context_file,
            "--principal", input.principal,
            "--action",    input.action,
            "--resource",  input.resource,
        });
        if (input.schema_path) |schema| {
            try argv.appendSlice(self.allocator, &.{ "--schema", schema });
        }

        const result = try self.run(argv.items);
        errdefer self.allocator.free(result.output);

        const decision = classify(result.exit_code, result.output);
        const determining = try parseDetermining(self.allocator, result.output);
        return .{
            .decision = decision,
            .diagnostics = result.output,
            .determining = determining,
        };
    }

    /// The decision only for one verb -- used to fill the matrix, where the
    /// per-verb diagnostics would be noise.
    pub fn authorizeDecision(self: *CedarCli, input: AuthorizeInput) !Decision {
        var result = try self.authorize(input);
        defer result.deinit(self.allocator);
        return result.decision;
    }

    // --- process plumbing ---

    const RunOutput = struct {
        exit_code: u8,
        /// stdout and stderr concatenated, in that order. `cedar` splits the decision
        /// and its explanation across both depending on subcommand, and a reviewer
        /// wants to read them together.
        output: []u8,
    };

    fn runOutcome(self: *CedarCli, args: []const []const u8) !Outcome {
        const result = try self.run(args);
        return .{ .ok = result.exit_code == 0, .diagnostics = result.output };
    }

    fn run(self: *CedarCli, args: []const []const u8) !RunOutput {
        const binary = self.binary orelse return Error.CedarNotFound;

        var argv = std.ArrayListUnmanaged([]const u8).empty;
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, binary);
        try argv.appendSlice(self.allocator, args);

        const result = std.process.run(self.allocator, runtime.io(), .{
            .argv = argv.items,
            .stdout_limit = .limited(output_limit),
            .stderr_limit = .limited(output_limit),
        }) catch |err| {
            Logger.warn("cedar invocation failed: {any}", .{err});
            return Error.CedarFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        const combined = try std.mem.concat(self.allocator, u8, &.{ result.stdout, result.stderr });
        errdefer self.allocator.free(combined);

        // A signalled child has no exit status. Reporting that as a failed run rather
        // than inventing a code keeps it out of the ALLOW/DENY classification.
        const exit_code: u8 = switch (result.term) {
            .exited => |code| code,
            else => {
                self.allocator.free(combined);
                return Error.CedarFailed;
            },
        };
        return .{ .exit_code = exit_code, .output = combined };
    }

    // --- workspace ---

    fn writeTemp(self: *CedarCli, prefix: []const u8, suffix: []const u8, content: []const u8) ![]u8 {
        if (content.len > max_policy_bytes) return Error.PolicyTooLarge;
        const dir = try self.ensureWorkspace();

        self.sequence += 1;
        const name = try std.fmt.allocPrint(
            self.allocator,
            "{s}/{s}-{d}{s}",
            .{ dir, prefix, self.sequence, suffix },
        );
        errdefer self.allocator.free(name);

        try std.Io.Dir.cwd().writeFile(runtime.io(), .{
            .sub_path = name,
            .data = content,
            .flags = .{ .permissions = private_file, .exclusive = true },
        });
        return name;
    }

    fn removeTemp(self: *CedarCli, path: []u8) void {
        std.Io.Dir.cwd().deleteFile(runtime.io(), path) catch |err| {
            Logger.warn("Failed to remove Cedar temp file {s}: {any}", .{ path, err });
        };
        self.allocator.free(path);
    }

    fn ensureWorkspace(self: *CedarCli) ![]const u8 {
        if (self.workspace) |dir| return dir;

        const base_owned = env.getOwned(self.allocator, "TMPDIR") catch null;
        defer if (base_owned) |value| self.allocator.free(value);
        const base = if (base_owned) |value| value else "/tmp";

        var attempt: u8 = 0;
        while (attempt < 8) : (attempt += 1) {
            var seed: [8]u8 = undefined;
            try runtime.io().randomSecure(&seed);
            const candidate = try std.fmt.allocPrint(
                self.allocator,
                "{s}{s}c3s-cedar-{s}",
                .{
                    base,
                    if (std.mem.endsWith(u8, base, "/")) "" else "/",
                    std.fmt.bytesToHex(seed, .lower),
                },
            );
            errdefer self.allocator.free(candidate);

            std.Io.Dir.cwd().createDir(runtime.io(), candidate, private_dir) catch |err| switch (err) {
                error.PathAlreadyExists => {
                    self.allocator.free(candidate);
                    continue;
                },
                else => return err,
            };
            self.workspace = candidate;
            return candidate;
        }
        return Error.CedarFailed;
    }
};

/// Turn an exit code plus output into a decision, fail-closed.
///
/// The evaluation-error check comes first deliberately: `cedar` can print an error for
/// one policy and still exit 2, and treating that as a clean DENY would report a
/// confident answer derived from a policy set that did not fully evaluate.
fn classify(exit_code: u8, output: []const u8) Decision {
    if (std.mem.indexOf(u8, output, "error while evaluating policy") != null) return .indeterminate;
    if (exit_code == 0 and containsLine(output, "ALLOW")) return .allow;
    if (exit_code == deny_exit_code and containsLine(output, "DENY")) return .deny;
    return .indeterminate;
}

/// Cedar prints the verdict on a line of its own. Substring matching would find the
/// word inside a policy annotation echoed back in the diagnostics.
fn containsLine(haystack: []const u8, needle: []const u8) bool {
    var lines = std.mem.splitScalar(u8, haystack, '\n');
    while (lines.next()) |line| {
        if (std.mem.eql(u8, std.mem.trim(u8, line, " \t\r"), needle)) return true;
    }
    return false;
}

/// Pull the policy ids out of Cedar's "due to the following policies:" block. The
/// block is a run of indented lines terminated by the first blank or unindented one.
fn parseDetermining(allocator: std.mem.Allocator, output: []const u8) ![]u8 {
    const marker = "due to the following policies:";
    const start = std.mem.indexOf(u8, output, marker) orelse return allocator.dupe(u8, "");
    var rest = output[start + marker.len ..];
    if (std.mem.indexOfScalar(u8, rest, '\n')) |nl| rest = rest[nl + 1 ..] else return allocator.dupe(u8, "");

    var names = std.ArrayListUnmanaged(u8).empty;
    errdefer names.deinit(allocator);

    var lines = std.mem.splitScalar(u8, rest, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, " \t\r");
        if (line.len == 0) break;
        if (line[0] != ' ' and line[0] != '\t') break;
        const name = std.mem.trim(u8, line, " \t\r");
        if (name.len == 0) break;
        if (names.items.len > 0) try names.appendSlice(allocator, ", ");
        try names.appendSlice(allocator, name);
    }
    return names.toOwnedSlice(allocator);
}

/// Find `cedar` on PATH, then in the two places a Rust CLI usually lands.
///
/// Searching beyond PATH is not cosmetic: `cargo install` is the documented way to get
/// this binary and it drops it in `~/.cargo/bin`, which plenty of shells never add.
fn locate(allocator: std.mem.Allocator) ?[]u8 {
    if (builtin.os.tag == .windows) return null;

    if (env.getOwned(allocator, "PATH") catch null) |path_env| {
        defer allocator.free(path_env);
        var entries = std.mem.splitScalar(u8, path_env, ':');
        while (entries.next()) |entry| {
            if (entry.len == 0) continue;
            if (executableAt(allocator, entry, "cedar")) |found| return found;
        }
    }

    if (env.getOwned(allocator, "HOME") catch null) |home| {
        defer allocator.free(home);
        const fallbacks = [_][]const u8{ ".cargo/bin", ".local/bin" };
        for (fallbacks) |suffix| {
            const dir = std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, suffix }) catch return null;
            defer allocator.free(dir);
            if (executableAt(allocator, dir, "cedar")) |found| return found;
        }
    }
    return null;
}

fn executableAt(allocator: std.mem.Allocator, dir: []const u8, name: []const u8) ?[]u8 {
    const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, name }) catch return null;
    errdefer allocator.free(path);
    std.Io.Dir.cwd().access(runtime.io(), path, .{ .execute = true }) catch {
        allocator.free(path);
        return null;
    };
    return path;
}

// --- Tests ---

const testing = std.testing;

test "a verdict is only read off a line of its own" {
    // A policy annotation echoed into the diagnostics contains the word ALLOW. Reading
    // it as the verdict would invert a DENY.
    try testing.expect(containsLine("ALLOW\n", "ALLOW"));
    try testing.expect(containsLine("noise\n  DENY  \nmore", "DENY"));
    try testing.expect(!containsLine("@id(\"ALLOW-everything\")\nDENY\n", "ALLOW"));
}

test "an evaluation error is indeterminate even when cedar exits with a clean code" {
    // The hazard: cedar can report an error for one policy and still exit 2. Taking
    // that as DENY states a confident answer about a set that did not fully evaluate.
    try testing.expectEqual(
        Decision.indeterminate,
        classify(deny_exit_code, "error while evaluating policy `p1`: type error\nDENY\n"),
    );
    try testing.expectEqual(Decision.deny, classify(deny_exit_code, "DENY\n"));
}

test "an unexpected exit code never becomes a permission" {
    for ([_]u8{ 1, 3, 101, 255 }) |code| {
        try testing.expectEqual(Decision.indeterminate, classify(code, "ALLOW\n"));
    }
    // Nor does a zero exit without the word.
    try testing.expectEqual(Decision.indeterminate, classify(0, ""));
}

test "determining policies are read out of the explanation block" {
    const a = testing.allocator;

    const output =
        \\ALLOW
        \\
        \\This decision was reached due to the following policies:
        \\  policy0
        \\  permit-viewers
        \\
        \\nothing after the blank line counts
    ;
    const names = try parseDetermining(a, output);
    defer a.free(names);
    try testing.expectEqualStrings("policy0, permit-viewers", names);
}

test "no explanation block yields no determining policies" {
    const a = testing.allocator;
    const names = try parseDetermining(a, "DENY\n");
    defer a.free(names);
    try testing.expectEqualStrings("", names);
}

test "the workspace is private, and temp files are owner-only" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = testing.allocator;

    var cli = CedarCli{ .allocator = a, .binary = null };
    defer cli.deinit();

    const path = try cli.writeTemp("policy", ".cedar", "permit(principal, action, resource);");
    defer cli.removeTemp(path);

    try testing.expectEqual(@as(u32, 0o600), try fileMode(path));
    try testing.expectEqual(@as(u32, 0o700), try dirMode(cli.workspace.?));
}

fn fileMode(path: []const u8) !u32 {
    var file = try std.Io.Dir.cwd().openFile(runtime.io(), path, .{});
    defer file.close(runtime.io());
    const stat = try file.stat(runtime.io());
    return @as(u32, @intFromEnum(stat.permissions)) & 0o777;
}

fn dirMode(path: []const u8) !u32 {
    var dir = try std.Io.Dir.cwd().openDir(runtime.io(), path, .{});
    defer dir.close(runtime.io());
    const stat = try dir.stat(runtime.io());
    return @as(u32, @intFromEnum(stat.permissions)) & 0o777;
}

test "an oversized policy is refused before it reaches the filesystem" {
    const a = testing.allocator;
    var cli = CedarCli{ .allocator = a, .binary = null };
    defer cli.deinit();

    const huge = try a.alloc(u8, max_policy_bytes + 1);
    defer a.free(huge);
    @memset(huge, 'x');

    try testing.expectError(Error.PolicyTooLarge, cli.writeTemp("policy", ".cedar", huge));
    // Nothing was created, so no workspace was needed either.
    try testing.expect(cli.workspace == null);
}

test "every operation reports CedarNotFound rather than pretending" {
    const a = testing.allocator;
    var cli = CedarCli{ .allocator = a, .binary = null };
    defer cli.deinit();

    try testing.expect(!cli.available());
    try testing.expectError(Error.CedarNotFound, cli.checkParse("permit(principal, action, resource);"));
    try testing.expectError(Error.CedarNotFound, cli.format("permit(principal, action, resource);"));
}

test "a stub binary drives the real invocation path" {
    // Exercises argv assembly, temp-file writing and output capture end to end without
    // requiring cedar to be installed on the machine running the suite.
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = testing.allocator;

    var cli = CedarCli{ .allocator = a, .binary = null };
    defer cli.deinit();

    const dir = try cli.ensureWorkspace();
    const stub_path = try std.fmt.allocPrint(a, "{s}/cedar-stub", .{dir});
    defer a.free(stub_path);
    try std.Io.Dir.cwd().writeFile(runtime.io(), .{
        .sub_path = stub_path,
        .data =
        \\#!/bin/sh
        \\echo "subcommand=$1"
        \\echo "ALLOW"
        \\exit 0
        \\
        ,
        .flags = .{ .permissions = @enumFromInt(0o700) },
    });
    cli.binary = try a.dupe(u8, stub_path);

    var outcome = try cli.checkParse("permit(principal, action, resource);");
    defer outcome.deinit(a);
    try testing.expect(outcome.ok);
    try testing.expect(std.mem.indexOf(u8, outcome.diagnostics, "subcommand=check-parse") != null);
}

test "a stub that denies produces DENY, and one that errors produces INDETERMINATE" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = testing.allocator;

    var cli = CedarCli{ .allocator = a, .binary = null };
    defer cli.deinit();
    const dir = try cli.ensureWorkspace();

    const input = AuthorizeInput{
        .policies = "permit(principal, action, resource);",
        .entities_json = "[]",
        .principal = "User::\"alice\"",
        .action = "Action::\"view\"",
        .resource = "Photo::\"x\"",
    };

    {
        const stub = try std.fmt.allocPrint(a, "{s}/deny-stub", .{dir});
        defer a.free(stub);
        try std.Io.Dir.cwd().writeFile(runtime.io(), .{
            .sub_path = stub,
            .data = "#!/bin/sh\necho DENY\nexit 2\n",
            .flags = .{ .permissions = @enumFromInt(0o700) },
        });
        cli.binary = try a.dupe(u8, stub);
        var result = try cli.authorize(input);
        defer result.deinit(a);
        try testing.expectEqual(Decision.deny, result.decision);
        a.free(cli.binary.?);
        cli.binary = null;
    }

    {
        const stub = try std.fmt.allocPrint(a, "{s}/error-stub", .{dir});
        defer a.free(stub);
        try std.Io.Dir.cwd().writeFile(runtime.io(), .{
            .sub_path = stub,
            .data = "#!/bin/sh\necho 'error while evaluating policy `p`: oops'\necho DENY\nexit 2\n",
            .flags = .{ .permissions = @enumFromInt(0o700) },
        });
        cli.binary = try a.dupe(u8, stub);
        var result = try cli.authorize(input);
        defer result.deinit(a);
        try testing.expectEqual(Decision.indeterminate, result.decision);
    }
}

test "the real cedar binary agrees with the exit codes and output shape assumed here" {
    // The stub tests above pin the plumbing; this one pins the contract. Skipped when
    // cedar is not installed, because the suite must run on machines without it -- but
    // when it is installed, a cedar release that changes its exit codes or drops the
    // explanation block should fail here rather than in front of a user.
    const a = testing.allocator;
    var cli = CedarCli.init(a);
    defer cli.deinit();
    if (!cli.available()) return error.SkipZigTest;

    const policy = "@id(\"allow-list\")\npermit(principal, action == k8s::Action::\"list\", resource);\n";
    const entities =
        \\[{"uid":{"type":"k8s::User","id":"alice"},"attrs":{"name":"alice"},"parents":[]}]
    ;
    const input = AuthorizeInput{
        .policies = policy,
        .entities_json = entities,
        .principal = "k8s::User::\"alice\"",
        .action = "k8s::Action::\"list\"",
        .resource = "k8s::Resource::\"/api/v1/pods\"",
    };

    var allowed = try cli.authorize(input);
    defer allowed.deinit(a);
    try testing.expectEqual(Decision.allow, allowed.decision);
    try testing.expectEqualStrings("allow-list", allowed.determining);

    var other_verb = input;
    other_verb.action = "k8s::Action::\"create\"";
    var denied = try cli.authorize(other_verb);
    defer denied.deinit(a);
    try testing.expectEqual(Decision.deny, denied.decision);

    var parsed = try cli.checkParse(policy);
    defer parsed.deinit(a);
    try testing.expect(parsed.ok);

    var broken = try cli.checkParse("permit(principal");
    defer broken.deinit(a);
    try testing.expect(!broken.ok);
    try testing.expect(broken.diagnostics.len > 0);

    var formatted = try cli.format(policy);
    defer formatted.deinit(a);
    try testing.expect(formatted.ok);
    try testing.expect(std.mem.indexOf(u8, formatted.diagnostics, "permit (") != null);

    var validated = try cli.validate(
        policy,
        "tests/fixtures/cedar/k8s-authorization.cedarschema",
    );
    defer validated.deinit(a);
    try testing.expect(validated.ok);
}
