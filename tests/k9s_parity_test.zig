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
// Popeye, Helm, plugins, benchmarks, screendumps. Table keys match k9s
// (Ctrl-r refresh, `r` drain/restart, `u` cordon toggle, `f` port-forwards,
// Ctrl-c quit).

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

fn initApp(allocator: std.mem.Allocator) !App {
    return App.init(allocator, .{});
}

test "k9s alias table is not vacuous" {
    try testing.expect(k9s_view_aliases.len >= 40);
    try testing.expect(k9s_commands_absent.len >= 15);
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

test "k9s r on nodes starts a drain prompt; ctrl-r does not" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try app.switchToView("nodes");
    const t = &app.nodes_view.table;
    try t.appendItem(.{ .columns = .{
        try allocator.dupe(u8, "node-1"),   try allocator.dupe(u8, "Ready"),
        try allocator.dupe(u8, "worker"),   try allocator.dupe(u8, "v1.33.0"),
        try allocator.dupe(u8, "10.0.0.1"), try allocator.dupe(u8, "1d"),
    }, .allocator = allocator });
    try t.filtered_indices.append(allocator, 0);
    t.selected_row = 0;

    try app.handleKey(.ctrl_r);
    try testing.expect(app.pending_input == .none);

    try app.handleKey(.{ .char = 'r' });
    try testing.expect(app.pending_input == .drain);
    try testing.expect(app.command_input.visible);
}

test "ctrl-c quits, including while a prompt is open" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try testing.expect(app.running);
    try app.handleKey(.ctrl_c);
    try testing.expect(!app.running);

    var app2 = try initApp(allocator);
    defer app2.deinit();
    try app2.handleKey(.colon);
    try testing.expect(app2.command_input.visible);
    try app2.handleKey(.ctrl_c);
    try testing.expect(!app2.running);
}

test "f on pods opens the port-forwards view" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try app.switchToView("pods");
    try app.handleKey(.{ .char = 'f' });
    try testing.expectEqualStrings("portforwards", app.current_view_name);
}

test "ctrl-w hides VERY_LOW columns through App.handleKey" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try testing.expect(app.pods_view.show_wide);
    const cpu_i = blk: {
        inline for (src.PodsView.view_config.columns, 0..) |cd, i| {
            if (std.mem.eql(u8, cd.name, "CPU")) break :blk i;
        }
        return error.MissingCpuColumn;
    };
    try testing.expect(!app.pods_view.hiddenMask()[cpu_i]);
    try app.handleKey(.ctrl_w);
    try testing.expect(!app.pods_view.show_wide);
    try testing.expect(app.pods_view.hiddenMask()[cpu_i]);
}

test "empty command history - is a no-op" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();
    try testing.expectEqualStrings("pods", app.current_view_name);
    try app.handleKey(.{ .char = '-' });
    try testing.expectEqualStrings("pods", app.current_view_name);
    try testing.expect(!app.command_input.visible);
}

test "daily-driver palette commands are registered; OUT aliases stay absent" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try testing.expect(app.command_registry.contains("restart"));
    try testing.expect(app.command_registry.contains("scale"));
    try testing.expect(app.command_registry.contains("suspend"));
    try testing.expect(app.command_registry.contains("trigger"));
    try testing.expect(app.command_registry.contains("rollback"));
    try testing.expect(!app.command_registry.contains("sd"));
    try testing.expect(!app.command_registry.contains("screendump"));
    try testing.expect(!app.command_registry.contains("popeye"));
}

test "command extras :po kube-system pins the namespace" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try app.handleKey(.colon);
    for ("po kube-system") |c| {
        try app.handleKey(.{ .char = c });
    }
    try app.handleKey(.enter);
    try testing.expectEqualStrings("pods", app.current_view_name);
    try testing.expectEqualStrings("kube-system", app.k8s_service.current_namespace);
}

test "command extras :dp /fred applies the filter" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try app.handleKey(.colon);
    for ("dp /fred") |c| {
        try app.handleKey(.{ .char = c });
    }
    try app.handleKey(.enter);
    try testing.expectEqualStrings("deployments", app.current_view_name);
    try testing.expectEqualStrings("fred", app.deployments_view.table.filter_text);
}

test "last command - replays the previous palette command" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try app.handleKey(.colon);
    for ("nodes") |c| {
        try app.handleKey(.{ .char = c });
    }
    try app.handleKey(.enter);
    try testing.expectEqualStrings("nodes", app.current_view_name);

    try app.switchToView("po");
    try testing.expectEqualStrings("pods", app.current_view_name);

    try app.handleKey(.{ .char = '-' });
    try testing.expectEqualStrings("nodes", app.current_view_name);
}

test "filter /! is stored as inverse prefix" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();

    try app.handleKey(.{ .char = '/' });
    try app.handleKey(.{ .char = '!' });
    try app.handleKey(.{ .char = 'x' });
    try app.handleKey(.enter);
    try testing.expectEqualStrings("!x", app.pods_view.table.filter_text);
}

test "ctrl-g toggles breadcrumbs; crumbsless starts hidden" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();
    try testing.expect(app.crumbs_visible);
    try app.handleKey(.ctrl_g);
    try testing.expect(!app.crumbs_visible);
    try app.handleKey(.ctrl_g);
    try testing.expect(app.crumbs_visible);

    var app2 = try App.init(allocator, .{ .crumbsless = true });
    defer app2.deinit();
    try testing.expect(!app2.crumbs_visible);
}

test "R on pods does not start a restart; r on deployments is refused when readonly" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try initApp(allocator);
    defer app.deinit();
    try app.handleKey(.{ .char = 'R' });
    try testing.expect(app.pending_input == .none);

    var ro = try App.init(allocator, .{ .readonly = true });
    defer ro.deinit();
    try ro.switchToView("deployments");
    try ro.handleKey(.{ .char = 'r' });
    try testing.expect(ro.pending_input == .none);
    try ro.handleKey(.{ .char = 'R' });
    try testing.expect(ro.pending_input == .none);
}
