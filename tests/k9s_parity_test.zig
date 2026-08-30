// SPDX-License-Identifier: Apache-2.0
//
// Comparison tests: k9s command/key contract vs c3s, driven through App —
// the join, not the isolated view. A passing test that constructs an input
// the terminal never emits is how Goto-Bottom stayed dead; these tests use
// the Key variants Terminal.readKey actually produces.
//
// Sources (pinned, not scraped at runtime):
//   - k9s README keyboard table (derailed/k9s)
//   - k9s internal/config/alias.go loadDefaultAliases (help/quit/alias/pf
//     plus the subsystems we do not ship)
//   - kubectl API shortNames for core/apps/rbac/policy resources
//
// Non-goals from the c3s roadmap stay inverted tripwires: XRay, Pulses,
// Popeye, Helm, plugins, benchmarks, screendumps. Drain is on `D`, not
// k9s's `r`, because `r` is refresh here.

const std = @import("std");
const testing = std.testing;
const src = @import("src");
const App = src.App;
const Key = src.Terminal.Key;

const Alias = struct { k9s: []const u8, c3s_view: []const u8 };

/// k9s command-palette aliases that must land on the matching c3s view.
/// Keys and commands are different namespaces (`a` on a pod is Attach; `:a`
/// is the aliases view).
const k9s_view_aliases = [_]Alias{
    .{ .k9s = "po", .c3s_view = "pods" },
    .{ .k9s = "pods", .c3s_view = "pods" },
    .{ .k9s = "dp", .c3s_view = "deployments" },
    .{ .k9s = "deploy", .c3s_view = "deployments" },
    .{ .k9s = "deployments", .c3s_view = "deployments" },
    .{ .k9s = "svc", .c3s_view = "services" },
    .{ .k9s = "services", .c3s_view = "services" },
    .{ .k9s = "ns", .c3s_view = "namespaces" },
    .{ .k9s = "namespace", .c3s_view = "namespaces" },
    .{ .k9s = "namespaces", .c3s_view = "namespaces" },
    .{ .k9s = "no", .c3s_view = "nodes" },
    .{ .k9s = "nodes", .c3s_view = "nodes" },
    .{ .k9s = "sts", .c3s_view = "statefulsets" },
    .{ .k9s = "statefulsets", .c3s_view = "statefulsets" },
    .{ .k9s = "ds", .c3s_view = "daemonsets" },
    .{ .k9s = "daemonsets", .c3s_view = "daemonsets" },
    .{ .k9s = "rs", .c3s_view = "replicasets" },
    .{ .k9s = "replicasets", .c3s_view = "replicasets" },
    .{ .k9s = "job", .c3s_view = "jobs" },
    .{ .k9s = "jobs", .c3s_view = "jobs" },
    .{ .k9s = "cj", .c3s_view = "cronjobs" },
    .{ .k9s = "cronjobs", .c3s_view = "cronjobs" },
    .{ .k9s = "cm", .c3s_view = "configmaps" },
    .{ .k9s = "configmaps", .c3s_view = "configmaps" },
    .{ .k9s = "secret", .c3s_view = "secrets" },
    .{ .k9s = "secrets", .c3s_view = "secrets" },
    .{ .k9s = "pv", .c3s_view = "persistentvolumes" },
    .{ .k9s = "pvc", .c3s_view = "persistentvolumeclaims" },
    .{ .k9s = "ing", .c3s_view = "ingresses" },
    .{ .k9s = "ingresses", .c3s_view = "ingresses" },
    .{ .k9s = "netpol", .c3s_view = "networkpolicies" },
    .{ .k9s = "sa", .c3s_view = "serviceaccounts" },
    .{ .k9s = "role", .c3s_view = "roles" },
    .{ .k9s = "rb", .c3s_view = "rolebindings" },
    .{ .k9s = "cr", .c3s_view = "clusterroles" },
    .{ .k9s = "crb", .c3s_view = "clusterrolebindings" },
    .{ .k9s = "ev", .c3s_view = "events" },
    .{ .k9s = "quota", .c3s_view = "resourcequotas" },
    .{ .k9s = "limits", .c3s_view = "limitranges" },
    .{ .k9s = "pdb", .c3s_view = "poddisruptionbudgets" },
    .{ .k9s = "hpa", .c3s_view = "hpa" },
    .{ .k9s = "ep", .c3s_view = "endpoints" },
    .{ .k9s = "sc", .c3s_view = "storageclasses" },
    .{ .k9s = "ctx", .c3s_view = "contexts" },
    .{ .k9s = "context", .c3s_view = "contexts" },
    .{ .k9s = "pf", .c3s_view = "portforwards" },
    .{ .k9s = "portforward", .c3s_view = "portforwards" },
    .{ .k9s = "csr", .c3s_view = "certificatesigningrequests" },
    .{ .k9s = "pc", .c3s_view = "priorityclasses" },
    .{ .k9s = "gw", .c3s_view = "gateways" },
    .{ .k9s = "gtw", .c3s_view = "gateways" },
    .{ .k9s = "htr", .c3s_view = "httproutes" },
};

/// k9s builtins we refuse. Inverted tripwire: the suite fails if someone
/// registers them as if they were implemented. Do not shrink this list by
/// deleting entries — add a positive alias test in the same commit that
/// actually ships the feature.
const k9s_commands_absent = [_][]const u8{
    "popeye",
    "pop",
    "xray",
    "pulse",
    "pulses",
    "pu",
    "hz",
    "charts",
    "chart",
    "hm",
    "plugin",
    "plugins",
    "benchmark",
    "bench",
    "screendump",
    "sd",
    "dir",
    "user",
    "usr",
    "group",
    "grp",
    "workload",
    "wk",
    // kubectl shortName for ReplicationController. Do not steal it for
    // ResourceClaims (`rclaim`).
    "rc",
};

const KeyDivergence = struct {
    action: []const u8,
    k9s_key: []const u8,
    c3s_key: []const u8,
};

/// Load-bearing: a scan that can be emptied is vacuous. These are the
/// intentional k9s mismatches, not bugs.
const k9s_key_divergences = [_]KeyDivergence{
    .{ .action = "refresh", .k9s_key = "ctrl-r", .c3s_key = "r" },
    .{ .action = "drain", .k9s_key = "r", .c3s_key = "D" },
    .{ .action = "cordon", .k9s_key = "u (toggle)", .c3s_key = "c" },
    .{ .action = "show-port-forwards", .k9s_key = "f", .c3s_key = ":pf" },
    .{ .action = "quit", .k9s_key = "ctrl-c", .c3s_key = ":q" },
};

fn initApp(allocator: std.mem.Allocator) !App {
    return App.init(allocator, .{});
}

test "k9s alias table is not vacuous" {
    try testing.expect(k9s_view_aliases.len >= 40);
    try testing.expect(k9s_commands_absent.len >= 15);
    try testing.expect(k9s_key_divergences.len >= 3);
}

test "every pinned k9s view alias is registered and switches the view" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    for (k9s_view_aliases) |row| {
        try testing.expect(app.command_registry.contains(row.k9s));
        try app.switchToView(row.k9s);
        try testing.expectEqualStrings(row.c3s_view, app.current_view_name);
    }
}

test "k9s subsystems c3s does not ship stay unregistered" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    const before = app.current_view_name;
    for (k9s_commands_absent) |alias| {
        try testing.expect(!app.command_registry.contains(alias));
        try app.switchToView(alias);
        try testing.expectEqualStrings(before, app.current_view_name);
    }
}

test "k9s :q :h :a match quit, help, aliases" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try testing.expect(app.command_registry.contains("q"));
    try testing.expect(app.command_registry.contains("q!"));
    try testing.expect(app.command_registry.contains("qa"));
    try testing.expect(app.command_registry.contains("Q"));
    try testing.expect(app.command_registry.contains("help"));
    try testing.expect(app.command_registry.contains("h"));
    try testing.expect(app.command_registry.contains("?"));
    try testing.expect(app.command_registry.contains("alias"));
    try testing.expect(app.command_registry.contains("a"));

    try app.switchToView("a");
    try testing.expectEqualStrings("aliases", app.current_view_name);

    try app.switchToView("help");
    try testing.expect(app.view_manager.isViewActive("help"));

    try app.switchToView("q");
    try testing.expect(!app.running);
}

test "k9s keys that share a namespace fire through App.handleKey" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    // Terminal.readKey maps '?' to Key.question_mark, never .char='?'.
    try app.handleKey(.question_mark);
    try testing.expect(app.view_manager.isViewActive("help"));
    try app.handleKey(.question_mark);
    try testing.expect(!app.view_manager.isViewActive("help"));

    try app.handleKey(.colon);
    try testing.expect(app.command_input.visible);
    app.command_input.hide();

    try app.handleKey(.{ .char = '/' });
    try testing.expect(app.command_input.visible);
    app.command_input.hide();

    try app.handleKey(.ctrl_a);
    try testing.expectEqualStrings("aliases", app.current_view_name);
    try app.handleKey(.ctrl_a);
    try testing.expect(std.mem.eql(u8, app.current_view_name, "aliases") == false);
}

test "drain is on D, not k9s r: r on nodes does not start a drain prompt" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try app.switchToView("nodes");
    try testing.expectEqualStrings("nodes", app.current_view_name);

    try app.handleKey(.{ .char = 'r' });
    try testing.expect(app.pending_input == .none);
    try testing.expect(!app.command_input.visible);
}

test "ctrl-c does not quit (k9s does; c3s uses :q)" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try testing.expect(app.running);
    try app.handleKey(.ctrl_c);
    try testing.expect(app.running);
}

test "intentional k9s key divergences stay named" {
    var saw_drain = false;
    var saw_refresh = false;
    for (k9s_key_divergences) |row| {
        if (std.mem.eql(u8, row.action, "drain")) {
            saw_drain = true;
            try testing.expectEqualStrings("r", row.k9s_key);
            try testing.expectEqualStrings("D", row.c3s_key);
        }
        if (std.mem.eql(u8, row.action, "refresh")) {
            saw_refresh = true;
            try testing.expectEqualStrings("ctrl-r", row.k9s_key);
            try testing.expectEqualStrings("r", row.c3s_key);
        }
    }
    try testing.expect(saw_drain);
    try testing.expect(saw_refresh);
}
