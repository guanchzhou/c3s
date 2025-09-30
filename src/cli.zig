const std = @import("std");
const xdg = @import("core/xdg.zig");
const build = @import("c3s_build");
const version = @import("model/version.zig");

var version_storage: [128]u8 = undefined;
var version_len: usize = 0;

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
    headless: bool = false,
    crumbsless: bool = false,
    logoless: bool = false,
    splashless: bool = false,
    kubeconfig: ?[]const u8 = null,
    cluster: ?[]const u8 = null,
    user: ?[]const u8 = null,
    token: ?[]const u8 = null,
    as: ?[]const u8 = null,
    as_group: ?[]const u8 = null,
    certificate_authority: ?[]const u8 = null,
    client_certificate: ?[]const u8 = null,
    client_key: ?[]const u8 = null,
    insecure_skip_tls_verify: bool = false,
    request_timeout: ?[]const u8 = null,
    screen_dump_dir: ?[]const u8 = null,
    write: bool = false,
};

pub fn parseArgs(allocator: std.mem.Allocator) !Config {
    var config = Config{};
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    // Skip the program name
    _ = args.next();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            printHelp();
            std.process.exit(0);
            } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "version")) {
                printVersion();
                std.process.exit(0);
            } else if (std.mem.eql(u8, arg, "info")) {
                printInfo();
                std.process.exit(0);
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
        } else if (std.mem.eql(u8, arg, "--headless")) {
            config.headless = true;
        } else if (std.mem.eql(u8, arg, "--crumbsless")) {
            config.crumbsless = true;
        } else if (std.mem.eql(u8, arg, "--logoless")) {
            config.logoless = true;
        } else if (std.mem.eql(u8, arg, "--splashless")) {
            config.splashless = true;
        } else if (std.mem.eql(u8, arg, "--kubeconfig")) {
            config.kubeconfig = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--cluster")) {
            config.cluster = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--user")) {
            config.user = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--token")) {
            config.token = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--as")) {
            config.as = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--as-group")) {
            config.as_group = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--certificate-authority")) {
            config.certificate_authority = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--client-certificate")) {
            config.client_certificate = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--client-key")) {
            config.client_key = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--insecure-skip-tls-verify")) {
            config.insecure_skip_tls_verify = true;
        } else if (std.mem.eql(u8, arg, "--request-timeout")) {
            config.request_timeout = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--screen-dump-dir")) {
            config.screen_dump_dir = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--logFile")) {
            config.log_file = args.next() orelse return error.MissingValue;
        } else if (std.mem.eql(u8, arg, "--write")) {
            config.write = true;
        } else {
            std.log.warn("Unknown argument: {s}", .{arg});
        }
    }

    return config;
}

fn printHelp() void {
    const help_text = 
        \\C3S is a CLI to view and manage your Kubernetes clusters.
        \\
        \\Usage:
        \\  c3s [flags]
        \\  c3s [command]
        \\
        \\Available Commands:
        \\  completion  Generate the autocompletion script for the specified shell
        \\  help        Help about any command
        \\  info        List C3S configurations info
        \\  version     Print version/build info
        \\
        \\Flags:
        \\  -A, --all-namespaces                 Launch C3S in all namespaces
        \\      --as string                      Username to impersonate for the operation
        \\      --as-group stringArray           Group to impersonate for the operation
        \\      --certificate-authority string   Path to a cert file for the certificate authority
        \\      --client-certificate string      Path to a client certificate file for TLS
        \\      --client-key string              Path to a client key file for TLS
        \\      --cluster string                 The name of the kubeconfig cluster to use
        \\  -c, --command string                 Overrides the default resource to load when the application launches
        \\      --context string                 The name of the kubeconfig context to use
        \\      --crumbsless                     Turn C3S crumbs off
        \\      --headless                       Turn C3S header off
        \\  -h, --help                           help for c3s
        \\      --insecure-skip-tls-verify       If true, the server's caCertFile will not be checked for validity
        \\      --kubeconfig string              Path to the kubeconfig file to use for CLI requests
        \\      --logFile string                 Specify the log file (default "/Users/andreymaltsev/Library/Application Support/c3s/c3s.log")
        \\  -l, --logLevel string                Specify a log level (error, warn, info, debug) (default "info")
        \\      --debug                          Enable debug mode (sets log level to debug)
            \\      --logoless                       Turn C3S logo off
        \\  -n, --namespace string               If present, the namespace scope for this CLI request
        \\      --readonly                       Sets readOnly mode by overriding readOnly configuration setting
        \\  -r, --refresh float32                Specify the default refresh rate as a float (sec) (default 2)
        \\      --request-timeout string         The length of time to wait before giving up on a single server request
        \\      --screen-dump-dir string         Sets a path to a dir for a screen dumps
        \\      --splashless                     Turn C3S splash screen off
        \\      --token string                   Bearer token for authentication to the API server
        \\      --user string                    The name of the kubeconfig user to use
        \\      --version                        Print version/build info
        \\      --write                          Sets write mode by overriding the readOnly configuration setting
        \\
        \\Use "c3s [command] --help" for more information about a command.
        \\
    ;
    std.debug.print("{s}", .{help_text});
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
    "       _____     ",
    "  ____|__  /_____",
    " / ___//_ </ ___/",
    "/ /_____/ (__  ) ",
    "\\___/____/____/  ",
    "                 ",
};

fn printLogo(color: []const u8) void {
    for (logo_small) |line| {
        std.debug.print("{s}{s}\x1b[0m\n", .{ color, line });
    }
    std.debug.print("\n", .{});
}

fn printInfoLine(label: []const u8, value: []const u8, color: []const u8) void {
    const padded_label = std.fmt.allocPrint(std.heap.page_allocator, "{s}:", .{label}) catch label;
    defer if (padded_label.ptr != label.ptr) std.heap.page_allocator.free(padded_label);
    std.debug.print("{s}{s:<27}\x1b[0m {s}\n", .{ color, padded_label, value });
}

fn printInfo() void {
    const paths = xdg.ensurePaths() catch {
        std.log.err("Failed to resolve XDG paths", .{});
        return;
    };

    const ver = formatVersion();
    
    // Cyan color (matching k9s style)
    const cyan = "\x1b[36m";

    // Print logo first
    printLogo(cyan);

    // Print info lines
    printInfoLine("Version", ver, cyan);
    printInfoLine("Config", paths.config_file, cyan);
    printInfoLine("Custom Views", paths.views_file, cyan);
    printInfoLine("Plugins", paths.plugins_file, cyan);
    printInfoLine("Hotkeys", paths.hotkeys_file, cyan);
    printInfoLine("Aliases", paths.aliases_file, cyan);
    printInfoLine("Skins", paths.skins_dir, cyan);
    printInfoLine("Context Configs", paths.contexts_dir, cyan);
    printInfoLine("Logs", paths.log_file, cyan);
    printInfoLine("Benchmarks", paths.benchmarks_dir, cyan);
    printInfoLine("ScreenDumps", paths.dumps_dir, cyan);
}
