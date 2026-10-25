const std = @import("std");
const xdg = @import("core/xdg.zig");
const build = @import("c3s_build");
const version = @import("model/version.zig");
const task15 = @import("task15_diagnostics.zig");
const kubectl_flags = @import("k8s/kubectl_flags.zig");

var version_storage: [128]u8 = undefined;
var version_len: usize = 0;
var as_group_storage: [kubectl_flags.max_as_groups][]const u8 = undefined;

pub const Config = struct {
    all_namespaces: bool = false,
    context: ?[]const u8 = null,
    namespace: ?[]const u8 = null,
    command: ?[]const u8 = null,
    refresh_rate: f32 = 2.0,
    log_level: []const u8 = "info",
    log_file: ?[]const u8 = null,
    debug: bool = false,
    readonly: bool = false,
    crumbsless: bool = false,
    kubeconfig: ?[]const u8 = null,
    cluster: ?[]const u8 = null,
    user: ?[]const u8 = null,
    as: ?[]const u8 = null,
    as_groups: []const []const u8 = &.{},
    certificate_authority: ?[]const u8 = null,
    client_certificate: ?[]const u8 = null,
    client_key: ?[]const u8 = null,
    request_timeout: ?[]const u8 = null,
    screen_dump_dir: ?[]const u8 = null,
    diagnostic_control: ?task15.DiagnosticControl = null,
    task15_preflight: bool = false,
    task15_live: bool = false,
    task15_manifest_path: ?[]const u8 = null,
    task15_generate_manifest: bool = false,
    unknown_argument_seen: bool = false,

    pub fn kubectlOverrides(self: *const Config) kubectl_flags.Overrides {
        return .{
            .cluster = self.cluster,
            .user = self.user,
            .as = self.as,
            .as_groups = self.as_groups,
            .certificate_authority = self.certificate_authority,
            .client_certificate = self.client_certificate,
            .client_key = self.client_key,
            .request_timeout = self.request_timeout,
        };
    }
};

/// Flags c3s recognizes but does not implement. Accepting them silently would
/// let a user believe the behavior took effect.
fn unsupportedFlagReason(arg: []const u8) ?[]const u8 {
    const name = arg[0 .. std.mem.indexOfScalar(u8, arg, '=') orelse arg.len];
    const unsupported = [_]struct { []const u8, []const u8 }{
        .{ "--headless", "hiding the header is not implemented" },
        .{ "--logoless", "hiding the logo is not implemented" },
        .{ "--splashless", "c3s has no splash screen" },
        .{ "--write", "c3s is writable unless --readonly is given; there is no read-only setting to override" },
        .{ "--token", "a token on kubectl's command line is visible in the process list; set it in the kubeconfig" },
        .{ "--insecure-skip-tls-verify", "TLS verification cannot be disabled" },
    };
    for (unsupported) |entry| {
        if (std.mem.eql(u8, name, entry[0])) return entry[1];
    }
    return null;
}

pub fn parseArgs(args_src: std.process.Args, allocator: std.mem.Allocator) !Config {
    var config = Config{};
    // Zig 0.16: command-line args arrive via std.process.Init (no argv global).
    var args = try args_src.iterateAllocator(allocator);
    defer args.deinit();

    // Skip the program name
    _ = args.skip();

    var as_group_count: usize = 0;
    while (args.next()) |arg| {
        if (unsupportedFlagReason(arg)) |reason| {
            std.debug.print("c3s: unsupported flag {s}: {s}\n", .{ arg, reason });
            return error.UnsupportedFlag;
        }
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "version")) {
            printVersion();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "info")) {
            printInfo();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "task15-preflight")) {
            config.task15_preflight = true;
        } else if (std.mem.eql(u8, arg, "task15-manifest")) {
            config.task15_generate_manifest = true;
        } else if (std.mem.eql(u8, arg, "--all-namespaces") or std.mem.eql(u8, arg, "-A")) {
            config.all_namespaces = true;
        } else if (std.mem.eql(u8, arg, "--context")) {
            config.context = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--namespace") or std.mem.eql(u8, arg, "-n")) {
            config.namespace = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--command") or std.mem.eql(u8, arg, "-c")) {
            config.command = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--refresh") or std.mem.eql(u8, arg, "-r")) {
            const refresh_str = args.next() orelse return error.MissingValue;
            config.refresh_rate = std.fmt.parseFloat(f32, refresh_str) catch return error.InvalidValue;
        } else if (std.mem.eql(u8, arg, "--logLevel") or std.mem.eql(u8, arg, "-l")) {
            config.log_level = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--logFile")) {
            config.log_file = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            config.debug = true;
            config.log_level = "debug";
        } else if (std.mem.eql(u8, arg, "--readonly")) {
            config.readonly = true;
        } else if (std.mem.eql(u8, arg, "--crumbsless")) {
            config.crumbsless = true;
        } else if (std.mem.eql(u8, arg, "--kubeconfig")) {
            config.kubeconfig = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--cluster")) {
            config.cluster = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--user")) {
            config.user = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--as")) {
            config.as = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--as-group")) {
            if (as_group_count == as_group_storage.len) return error.TooManyAsGroups;
            as_group_storage[as_group_count] = args.next() orelse return error.MissingValue;
            as_group_count += 1;
            config.as_groups = as_group_storage[0..as_group_count];
        } else if (std.mem.eql(u8, arg, "--certificate-authority")) {
            config.certificate_authority = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--client-certificate")) {
            config.client_certificate = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--client-key")) {
            config.client_key = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--request-timeout")) {
            config.request_timeout = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--screen-dump-dir")) {
            config.screen_dump_dir = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--task15-live")) {
            config.task15_live = true;
        } else if (std.mem.eql(u8, arg, "--task15-manifest")) {
            config.task15_manifest_path = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--diagnostic-reconnect")) {
            if (config.diagnostic_control != null) return error.DuplicateDiagnosticControl;
            config.diagnostic_control = .{ .reconnect = try task15.parseFamily(
                args.next() orelse return error.MissingValue,
            ) };
        } else if (std.mem.eql(u8, arg, "--diagnostic-stale-rv")) {
            if (config.diagnostic_control != null) return error.DuplicateDiagnosticControl;
            config.diagnostic_control = .{ .stale_rv = try task15.parseFamily(
                args.next() orelse return error.MissingValue,
            ) };
        } else {
            std.log.warn("Unknown argument: {s}", .{arg});
            config.unknown_argument_seen = true;
        }
    }

    if (config.diagnostic_control != null and !config.task15_live) {
        return error.Task15ControlRequiresLiveMode;
    }
    if (config.task15_live) {
        if (config.unknown_argument_seen) return error.UnknownDiagnosticArgument;
        try task15.validateDiagnosticLaunch(.{
            .readonly = config.readonly,
            .context = config.context,
            .manifest_path = config.task15_manifest_path,
            .cluster = config.cluster,
            .user = config.user,
            .impersonate = config.as,
            .impersonate_group = if (config.as_groups.len > 0) config.as_groups[0] else null,
            .certificate_authority = config.certificate_authority,
            .client_certificate = config.client_certificate,
            .client_key = config.client_key,
        });
    }
    if (config.task15_generate_manifest) {
        if (config.unknown_argument_seen) return error.UnknownDiagnosticArgument;
        const context = config.context orelse return error.DiagnosticRequiresExplicitContext;
        if (!task15.contextAllowed(context)) return error.ContextNotAllowlisted;
        if (config.task15_live or config.task15_manifest_path != null or
            config.diagnostic_control != null or config.kubectlOverrides().changesIdentity())
        {
            return error.InvalidManifestGenerationArguments;
        }
    }
    return config;
}

fn printHelp() void {
    const help_head =
        \\C3S is a CLI to view and manage your Kubernetes clusters.
        \\
        \\Usage:
        \\  c3s [flags]
        \\  c3s [command]
        \\
        \\Available Commands:
        \\  info        List C3S configurations info
        \\  version     Print version/build info
        \\
        \\Flags:
        \\  -A, --all-namespaces                 Launch C3S in all namespaces
        \\      --as string                      Username to impersonate for the operation
        \\      --as-group string                Group to impersonate for the operation (repeatable)
        \\      --certificate-authority string   Path to a cert file for the certificate authority
        \\      --client-certificate string      Path to a client certificate file for TLS
        \\      --client-key string              Path to a client key file for TLS
        \\      --cluster string                 The name of the kubeconfig cluster to use
        \\  -c, --command string                 Overrides the default resource to load when the application launches
        \\      --context string                 The name of the kubeconfig context to use
        \\      --crumbsless                     Turn C3S crumbs off
        \\  -h, --help                           help for c3s
        \\      --kubeconfig string              Path to the kubeconfig file to use for CLI requests
        \\
    ;
    const help_tail =
        \\  -l, --logLevel string                Specify a log level (error, warn, info, debug) (default "info")
        \\      --debug                          Enable debug mode (sets log level to debug)
        \\  -n, --namespace string               If present, the namespace scope for this CLI request
        \\      --readonly                       Refuse every action that changes the cluster
        \\  -r, --refresh float32                Specify the default refresh rate as a float (sec) (default 2)
        \\      --request-timeout string         Time to wait for a single kubectl request (not watches or interactive sessions)
        \\      --screen-dump-dir string         Sets a path to a dir for a screen dumps
        \\      --user string                    The name of the kubeconfig user to use
        \\      --version                        Print version/build info
        \\      --task15-live                    Enable manifest-pinned Task 15 live diagnostics
        \\      --task15-manifest string         Frozen local Task 15 run manifest
        \\      --diagnostic-reconnect family    Restart one local read-only subscription family
        \\      --diagnostic-stale-rv family     Exercise one local stale-RV relist path
        \\
    ;
    var log_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const log_path = defaultLogFile(&log_path_buf, getenv("XDG_STATE_HOME"), getenv("HOME"));
    std.debug.print("{s}      --logFile string                 Specify the log file (default \"{s}\")\n{s}", .{
        help_head,
        log_path,
        help_tail,
    });
}

fn getenv(name: [*:0]const u8) ?[]const u8 {
    return if (std.c.getenv(name)) |value| std.mem.sliceTo(value, 0) else null;
}

/// The log path xdg.zig would resolve, computed without creating directories so
/// `--help` has no side effects.
fn defaultLogFile(buf: []u8, xdg_state_home: ?[]const u8, home: ?[]const u8) []const u8 {
    if (xdg_state_home) |state| {
        if (state.len > 0 and std.fs.path.isAbsolute(state)) {
            return std.fmt.bufPrint(buf, "{s}/c3s/c3s.log", .{state}) catch "$XDG_STATE_HOME/c3s/c3s.log";
        }
    }
    if (home) |dir| {
        if (dir.len > 0) {
            return std.fmt.bufPrint(buf, "{s}/.local/state/c3s/c3s.log", .{dir}) catch "~/.local/state/c3s/c3s.log";
        }
    }
    return "~/.local/state/c3s/c3s.log";
}

fn formatVersion() []const u8 {
    return version.string();
}

fn printVersion() void {
    const ver = formatVersion();
    std.debug.print("Version:    {s}\nCommit:     n/a\n", .{ver});
}

// C3S ASCII logo (small version)
const logo_small = [_][]const u8{
    "        _____     ",
    "   ____|__  /_____",
    "  / ___//_ </ ___/",
    " / /_____/ (__  ) ",
    " \\___/____/____/  ",
    "                  ",
};

fn printLogo(color: []const u8) void {
    for (logo_small) |line| {
        std.debug.print("{s}{s}\x1b[0m\n", .{ color, line });
    }
}

fn printInfoLine(label: []const u8, value: []const u8, color: []const u8) void {
    const padded_label = std.fmt.allocPrint(std.heap.page_allocator, "{s}:", .{label}) catch label;
    defer if (padded_label.ptr != label.ptr) std.heap.page_allocator.free(padded_label);
    std.debug.print("{s}{s:<27}\x1b[0m {s}\n", .{ color, padded_label, value });
}

const InfoPath = struct { label: []const u8, value: []const u8 };

/// Paths c3s advertises on the splash screen -- and this list is exactly the set it
/// actually reads.
///
/// It used to list ten. Seven of them ("Custom Views", "Plugins", "Hotkeys",
/// "Aliases", "Context Configs", "Benchmarks", "ScreenDumps") had no reader anywhere
/// in the codebase: c3s printed a path, the user put a file there, and nothing ever
/// opened it. That is the same defect as a help screen advertising an unimplemented
/// key, except the user has to write a whole config file before discovering it.
///
/// Add a line here in the commit that implements the reader, not before.
/// `unread_path_labels` below is the tripwire that enforces it.
fn advertisedPaths(paths: *const xdg.Paths) [4]InfoPath {
    return .{
        .{ .label = "Config", .value = paths.config_file },
        // Re-added in the commit that implemented the reader, exactly as the comment
        // above required. views_config.get() reads this file to select and reorder each
        // view's columns.
        .{ .label = "Custom Views", .value = paths.views_file },
        .{ .label = "Skins", .value = paths.skins_dir },
        .{ .label = "Logs", .value = paths.log_file },
    };
}

/// Labels whose backing path has no reader. Advertising one is a lie; the test below
/// fails if any reappears in `advertisedPaths`.
const unread_path_labels = [_][]const u8{
    // "Custom Views" was removed from this list when views_config landed -- that is the
    // sanctioned way to advertise a path: implement the reader, then delete the label
    // from here, in the same commit.
    "Plugins",
    "Hotkeys",
    "Aliases",
    "Context Configs",
    "Benchmarks",
    "ScreenDumps",
};

fn printInfo() void {
    const paths = xdg.ensurePaths() catch {
        std.log.err("Failed to resolve XDG paths", .{});
        return;
    };

    const ver = formatVersion();

    // Cyan color
    const cyan = "\x1b[36m";

    // Print logo first
    printLogo(cyan);

    // Print info lines
    printInfoLine("Version", ver, cyan);
    for (advertisedPaths(paths)) |entry| printInfoLine(entry.label, entry.value, cyan);
}

const testing = std.testing;

// Since cli.zig functions use std.debug.print and interact with environment,
// we'll test the public interface and helper functions

test "logo array is correctly defined" {
    // Verify the logo is present and non-empty.
    try testing.expect(logo_small.len > 0);
}

test "CLI parseArgs with help flag" {
    // Test would require mocking process.args, which is complex
    // For now, verify the function reference is valid.
    _ = parseArgs;
}

test "CLI parseArgs with version flag" {
    _ = parseArgs;
    // Version handling is tested separately in src/model/version.zig
}

test "CLI Config default values" {
    const default_config = Config{};

    try testing.expect(default_config.all_namespaces == false);
    try testing.expect(default_config.context == null);
    try testing.expect(default_config.namespace == null);
    try testing.expect(default_config.command == null);
    try testing.expect(default_config.refresh_rate == 2.0);
    try testing.expect(std.mem.eql(u8, default_config.log_level, "info"));
    try testing.expect(default_config.log_file == null);
    try testing.expect(default_config.debug == false);
    try testing.expect(default_config.readonly == false);
    try testing.expect(default_config.crumbsless == false);
    try testing.expect(default_config.as_groups.len == 0);
    try testing.expect(default_config.diagnostic_control == null);
}

test "CLI Config flag toggles" {
    const config = Config{
        .all_namespaces = true,
        .debug = true,
        .readonly = true,
    };

    try testing.expect(config.all_namespaces == true);
    try testing.expect(config.debug == true);
    try testing.expect(config.readonly == true);
}

test "CLI Config with custom values" {
    const config = Config{
        .refresh_rate = 5.0,
        .log_level = "debug",
        .context = "test-context",
        .namespace = "test-namespace",
    };

    try testing.expect(config.refresh_rate == 5.0);
    try testing.expect(std.mem.eql(u8, config.log_level, "debug"));
    try testing.expect(std.mem.eql(u8, config.context.?, "test-context"));
    try testing.expect(std.mem.eql(u8, config.namespace.?, "test-namespace"));
}

test "cli: the splash advertises only config paths c3s actually reads" {
    // Regression guard. The splash used to promise ten config paths, seven of which
    // nothing in the codebase ever opened -- so a user could write a views.yaml or a
    // plugins file and watch it be silently ignored. If a label from
    // unread_path_labels shows up in advertisedPaths again, either the reader landed
    // in the same commit (delete it from unread_path_labels) or this is a
    // re-introduction of the bug.
    xdg.resetCachedPathsForTests();
    const paths = try xdg.ensurePaths();
    const advertised = advertisedPaths(paths);

    for (advertised) |entry| {
        for (unread_path_labels) |bad| {
            try std.testing.expect(!std.mem.eql(u8, entry.label, bad));
        }
        // A blank path would render as a dangling label.
        try std.testing.expect(entry.value.len > 0);
    }

    // The three that ARE read must all still be there -- omitting a real path is as
    // wrong as inventing a fake one.
    var has_config = false;
    var has_skins = false;
    var has_logs = false;
    var has_views = false;
    for (advertised) |entry| {
        if (std.mem.eql(u8, entry.label, "Config")) has_config = true;
        if (std.mem.eql(u8, entry.label, "Skins")) has_skins = true;
        if (std.mem.eql(u8, entry.label, "Logs")) has_logs = true;
        if (std.mem.eql(u8, entry.label, "Custom Views")) has_views = true;
    }
    try std.testing.expect(has_config);
    try std.testing.expect(has_skins);
    try std.testing.expect(has_logs);
    // Custom Views is real now: views_config reads it.
    try std.testing.expect(has_views);
}

test "flags c3s does not implement are refused, including --flag=value forms" {
    for ([_][]const u8{
        "--headless",
        "--logoless",
        "--splashless",
        "--write",
        "--token",
        "--token=abc",
        "--insecure-skip-tls-verify",
        "--insecure-skip-tls-verify=true",
    }) |flag| {
        try testing.expect(unsupportedFlagReason(flag) != null);
    }
    for ([_][]const u8{ "--as", "--as-group", "--cluster", "--user", "--request-timeout", "--logFile", "--readonly" }) |flag| {
        try testing.expect(unsupportedFlagReason(flag) == null);
    }
}

test "every identity flag reaches the kubectl overrides" {
    const groups = [_][]const u8{ "devs", "oncall" };
    const config = Config{
        .cluster = "c",
        .user = "u",
        .as = "jane",
        .as_groups = &groups,
        .certificate_authority = "/ca.pem",
        .client_certificate = "/crt.pem",
        .client_key = "/key.pem",
        .request_timeout = "7s",
    };
    const overrides = config.kubectlOverrides();
    try testing.expectEqualStrings("c", overrides.cluster.?);
    try testing.expectEqualStrings("u", overrides.user.?);
    try testing.expectEqualStrings("jane", overrides.as.?);
    try testing.expectEqual(@as(usize, 2), overrides.as_groups.len);
    try testing.expectEqualStrings("/ca.pem", overrides.certificate_authority.?);
    try testing.expectEqualStrings("/crt.pem", overrides.client_certificate.?);
    try testing.expectEqualStrings("/key.pem", overrides.client_key.?);
    try testing.expectEqualStrings("7s", overrides.request_timeout.?);
}

test "help shows the log path for this user, not a fixed one" {
    var buf: [256]u8 = undefined;
    try testing.expectEqualStrings(
        "/state/c3s/c3s.log",
        defaultLogFile(&buf, "/state", "/home/someone"),
    );
    try testing.expectEqualStrings(
        "/home/someone/.local/state/c3s/c3s.log",
        defaultLogFile(&buf, null, "/home/someone"),
    );
    try testing.expectEqualStrings(
        "/home/someone/.local/state/c3s/c3s.log",
        defaultLogFile(&buf, "relative", "/home/someone"),
    );
    try testing.expectEqualStrings("~/.local/state/c3s/c3s.log", defaultLogFile(&buf, null, null));
}
