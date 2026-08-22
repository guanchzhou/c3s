const std = @import("std");
const KeyBinding = @import("../model/keybindings.zig").KeyBinding;
const KeyBindingsConfig = @import("../model/keybindings.zig").KeyBindingsConfig;
const bindings_data = @import("keybindings_data.zig");

/// ViewType enum for different resource types
pub const ViewType = enum {
    // Core resources
    pods,
    nodes,
    services,
    namespaces,
    events,
    secrets,
    configmaps,
    serviceaccounts,
    persistentvolumeclaims,

    // Apps resources
    deployments,
    replicasets,
    statefulsets,
    daemonsets,

    // Batch resources
    cronjobs,
    jobs,

    // RBAC resources
    clusterroles,
    clusterrolebindings,
    roles,
    rolebindings,

    /// Fallback for any resource view with no ViewType of its own. Before this,
    /// currentViewType() fell back to `.pods`, so `?` on an Ingress showed PODS' help.
    generic,

    // Misc views
    contexts,
    portforwards,
    aliases,
};

/// KeyBindingsViewModel - provides key bindings for any view type
pub const KeyBindingsViewModel = struct {
    allocator: std.mem.Allocator,
    view_type: ViewType,
    config: KeyBindingsConfig,

    pub fn init(allocator: std.mem.Allocator, view_type: ViewType) !KeyBindingsViewModel {
        // Load bindings for the specific view type
        // In the future, this could load from:
        // 1. c3s hotkeys.yaml
        // 2. c3s config file
        // 3. Built-in defaults (current)
        const bindings = try loadBindingsForView(allocator, view_type);

        return KeyBindingsViewModel{
            .allocator = allocator,
            .view_type = view_type,
            .config = KeyBindingsConfig{
                .bindings = bindings,
                .allocator = allocator,
            },
        };
    }

    pub fn deinit(self: *KeyBindingsViewModel) void {
        self.allocator.free(self.config.bindings);
    }

    pub fn getBindings(self: *const KeyBindingsViewModel) []const KeyBinding {
        return self.config.bindings;
    }
};

/// Load key bindings for a specific view type
fn loadBindingsForView(allocator: std.mem.Allocator, view_type: ViewType) ![]const KeyBinding {
    return switch (view_type) {
        // Core resources
        .pods => try loadPodsBindings(allocator),
        .nodes => try loadNodesBindings(allocator),
        .services => try loadServicesBindings(allocator),
        .namespaces => try bindings_data.loadNamespacesBindings(allocator),
        .events => try bindings_data.loadEventsBindings(allocator),
        .secrets => try bindings_data.loadSecretsBindings(allocator),
        .configmaps => try loadConfigMapsBindings(allocator),
        .serviceaccounts => try bindings_data.loadServiceAccountsBindings(allocator),
        .persistentvolumeclaims => try bindings_data.loadPVCsBindings(allocator),

        // Apps resources
        .deployments => try loadDeploymentsBindings(allocator),
        .replicasets => try bindings_data.loadReplicaSetsBindings(allocator),
        .statefulsets => try bindings_data.loadStatefulSetsBindings(allocator),
        .daemonsets => try bindings_data.loadDaemonSetsBindings(allocator),

        // Batch resources
        .cronjobs => try bindings_data.loadCronJobsBindings(allocator),
        .jobs => try bindings_data.loadJobsBindings(allocator),

        // RBAC resources (most use generic bindings)
        .clusterroles, .roles => try bindings_data.loadRolesBindings(allocator),
        .clusterrolebindings, .rolebindings => try bindings_data.loadRoleBindingsBindings(allocator),

        // Misc views (use generic or specific bindings)
        .contexts => try bindings_data.loadContextsBindings(allocator),
        .generic => try bindings_data.loadGenericResourceBindings(allocator),
        .portforwards => try bindings_data.loadPortForwardsBindings(allocator),
        .aliases => try bindings_data.loadAliasesBindings(allocator),
    };
}

/// Load pods-specific key bindings
fn loadPodsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    // This data could be loaded from:
    // 1. c3s hotkeys.yaml file
    // 2. c3s config file
    // 3. Built-in defaults (as fallback)

    const bindings = [_]KeyBinding{
        // RESOURCE COMMANDS (sorted alphabetically)
        .{ .key = "a", .description = "Attach", .category = .resource, .action = "attach" },
        // `c` = "Copy" was advertised here with no implementation anywhere in the
        // codebase -- pressing it on the pods view did nothing. Same defect class as
        // the cordon/drain hints. Re-add it in the commit that implements a real copy
        // action, not before.
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "Ctrl-f", .description = "Kill Finalizers", .category = .resource, .action = "kill_finalizers" },
        .{ .key = "Ctrl-k", .description = "Kill", .category = .resource, .action = "kill" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "i", .description = "Set Image", .category = .resource, .action = "set_image" },
        .{ .key = "l", .description = "Logs", .category = .resource, .action = "logs" },
        .{ .key = "o", .description = "Show Node", .category = .resource, .action = "show_node" },
        .{ .key = "p", .description = "Logs Previous", .category = .resource, .action = "logs_previous" },
        .{ .key = "Shift-f", .description = "Port-Forward", .category = .resource, .action = "port_forward" },
        // `Shift-r` = Refresh was a contradiction: the same list advertises Shift-r as
        // the READY sort, and the sort wins in resource_view.handleKey. The real
        // refresh is lowercase `r`, which was advertised nowhere at all.
        .{ .key = "r", .description = "Refresh", .category = .resource, .action = "refresh" },
        .{ .key = "s", .description = "Shell", .category = .resource, .action = "shell" },
        .{ .key = "t", .description = "Transfer", .category = .resource, .action = "transfer" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "z", .description = "Sanitize", .category = .resource, .action = "sanitize" },

        // GENERAL COMMANDS
        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = "Ctrl-a", .description = "Aliases", .category = .general, .action = "aliases" },
        .{ .key = ":cmd", .description = "Command mode", .category = .general, .action = "command_mode" },
        .{ .key = "/term", .description = "Filter mode", .category = .general, .action = "filter_mode" },
        .{ .key = "esc", .description = "Back/Clear", .category = .general, .action = "back_clear" },
        .{ .key = "Ctrl-e", .description = "Toggle Header", .category = .general, .action = "toggle_header" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
        .{ .key = "space", .description = "Mark", .category = .general, .action = "mark" },
        .{ .key = "*", .description = "Mark All", .category = .general, .action = "mark_all" },
        .{ .key = "^", .description = "Invert Marks", .category = .general, .action = "mark_invert" },
        .{ .key = "\\", .description = "Mark Clear", .category = .general, .action = "mark_clear" },

        // NAVIGATION COMMANDS
        // `0` is the all-namespaces toggle (resource_view.zig), not "Down" -- this
        // entry contradicted the j/Down entries in the same list.
        .{ .key = "0", .description = "All Namespaces", .category = .navigation, .action = "toggle_all_namespaces" },
        .{ .key = "Ctrl-b", .description = "Page Up", .category = .navigation, .action = "page_up" },
        // `Ctrl-f` = Page Down removed: this same list advertises Ctrl-f as Kill
        // Finalizers, and is_pods claims it first. PageDown itself works.
        .{ .key = "pgdn", .description = "Page Down", .category = .navigation, .action = "page_down" },
        .{ .key = "g", .description = "Goto Top", .category = .navigation, .action = "goto_top" },
        .{ .key = "Shift-g", .description = "Goto Bottom", .category = .navigation, .action = "goto_bottom" },
        .{ .key = "j", .description = "Down", .category = .navigation, .action = "down" },
        .{ .key = "k", .description = "Up", .category = .navigation, .action = "up" },

        // SORTING COMMANDS
        .{ .key = "Shift-a", .description = "Age", .category = .sorting, .action = "sort_age" },
        .{ .key = "Shift-c", .description = "CPU", .category = .sorting, .action = "sort_cpu" },
        .{ .key = "Shift-m", .description = "MEM", .category = .sorting, .action = "sort_mem" },
        .{ .key = "Shift-n", .description = "Name", .category = .sorting, .action = "sort_name" },
        .{ .key = "Shift-p", .description = "Namespace", .category = .sorting, .action = "sort_namespace" },
        .{ .key = "Shift-i", .description = "IP", .category = .sorting, .action = "sort_ip" },
        .{ .key = "Shift-o", .description = "Node", .category = .sorting, .action = "sort_node" },
        .{ .key = "Shift-r", .description = "Ready", .category = .sorting, .action = "sort_ready" },
        .{ .key = "Shift-s", .description = "Status", .category = .sorting, .action = "sort_status" },
        .{ .key = "Shift-t", .description = "Restart", .category = .sorting, .action = "sort_restart" },
    };

    return try allocator.dupe(KeyBinding, &bindings);
}

/// Load nodes-specific key bindings
fn loadNodesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    // Node-specific key bindings
    const bindings = [_]KeyBinding{
        // Node-specific commands.
        //
        // Cordon and Uncordon are re-added here in the same commit that implements
        // them, per the rule in tasks/lessons.md: "wire every key or remove the hint".
        //
        // Drain is implemented now, and re-added here in the same commit -- the
        // protocol this file's tripwires exist to enforce. It is on `D`, NOT k9s's
        // `r`: `r` is refresh in c3s, and binding an eviction to the refresh key would
        // be an accident generator. It confirms first, like delete.
        .{ .key = "c", .description = "Cordon", .category = .resource, .action = "cordon" },
        .{ .key = "D", .description = "Drain", .category = .resource, .action = "drain" },
        .{ .key = "u", .description = "Uncordon", .category = .resource, .action = "uncordon" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },

        // Sorting
        .{ .key = "Shift-r", .description = "Sort ROLE", .category = .sorting, .action = "sort_role" },

        // General and navigation commands are shared (could extract to common)
        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
        .{ .key = "g", .description = "Goto Top", .category = .navigation, .action = "goto_top" },
        .{ .key = "Shift-g", .description = "Goto Bottom", .category = .navigation, .action = "goto_bottom" },
    };

    return try allocator.dupe(KeyBinding, &bindings);
}

/// Load deployments-specific key bindings
fn loadDeploymentsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    // Similar to pods but with deployment-specific commands
    const bindings = [_]KeyBinding{
        // `r` was advertised as "Restart" while resource_view's generic switch binds
        // lowercase `r` to refresh -- so pressing it refreshed instead. Worse than a
        // missing feature: the user gets a different action from the one promised.
        // A rollout restart is unimplemented; see the roadmap.
        .{ .key = "r", .description = "Refresh", .category = .resource, .action = "refresh" },
        // Traffic is the reverse of every other defect here: implemented and reachable
        // (resource_view -> request_traffic -> App.showTrafficView) but advertised
        // nowhere, so nobody could discover it.
        .{ .key = "t", .description = "Traffic", .category = .resource, .action = "traffic" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },

        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
    };

    return try allocator.dupe(KeyBinding, &bindings);
}

/// Load services-specific key bindings
fn loadServicesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },

        .{ .key = "Shift-t", .description = "Sort Type", .category = .sorting, .action = "sort_type" },

        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
    };

    return try allocator.dupe(KeyBinding, &bindings);
}

/// Load configmaps-specific key bindings
fn loadConfigMapsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },

        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
    };

    return try allocator.dupe(KeyBinding, &bindings);
}

// --- Tests ---

test "keybindings_vm: init and deinit for all view types" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test all 22 view types can be initialized
    const view_types = [_]ViewType{
        // Core resources
        .pods,            .nodes,                  .services,            .namespaces,  .events,       .secrets,    .configmaps,
        .serviceaccounts, .persistentvolumeclaims,
        // Apps resources
        .deployments,         .replicasets, .statefulsets, .daemonsets,
        // Batch resources
        .cronjobs,
        .jobs,
        // RBAC resources
                   .clusterroles,           .clusterrolebindings, .roles,       .rolebindings,
        // Misc views
        .contexts,   .portforwards,
        .aliases,
    };

    for (view_types) |view_type| {
        var vm = try KeyBindingsViewModel.init(allocator, view_type);
        defer vm.deinit();

        // Verify bindings are returned
        const bindings = vm.getBindings();
        try std.testing.expect(bindings.len >= 0); // At least valid (could be empty)
    }
}

test "keybindings_vm: pods view has expected bindings" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .pods);
    defer vm.deinit();

    const bindings = vm.getBindings();

    // Pods should have many bindings
    try std.testing.expect(bindings.len > 10);

    // Check for some key pod bindings
    var has_attach = false;
    var has_logs = false;
    var has_describe = false;

    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "attach")) has_attach = true;
        if (std.mem.eql(u8, binding.action, "logs")) has_logs = true;
        if (std.mem.eql(u8, binding.action, "describe")) has_describe = true;
        // Same tripwire as the nodes one: `c` = "Copy" was advertised here with no
        // implementation anywhere. Re-add the hint only alongside a real action.
        try std.testing.expect(!std.mem.eql(u8, binding.action, "copy"));
    }

    try std.testing.expect(has_attach);
    try std.testing.expect(has_logs);
    try std.testing.expect(has_describe);
}

test "keybindings_vm: nodes view has specific bindings" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .nodes);
    defer vm.deinit();

    const bindings = vm.getBindings();

    // Cordon and uncordon are implemented now, so they must BE advertised -- the help
    // screen is as wrong when it omits a working key as when it invents one.
    var has_cordon = false;
    var has_uncordon = false;
    var has_drain = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "cordon")) has_cordon = true;
        if (std.mem.eql(u8, binding.action, "uncordon")) has_uncordon = true;
        if (std.mem.eql(u8, binding.action, "drain")) {
            has_drain = true;
            // On `D`, deliberately not k9s's `r`, which is refresh here.
            try std.testing.expectEqualStrings("D", binding.key);
        }
    }
    try std.testing.expect(has_cordon);
    try std.testing.expect(has_uncordon);
    try std.testing.expect(has_drain);

    // The node bindings that ARE implemented must still be present.
    var has_yaml = false;
    var has_describe = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "yaml")) has_yaml = true;
        if (std.mem.eql(u8, binding.action, "describe")) has_describe = true;
    }
    try std.testing.expect(has_yaml);
    try std.testing.expect(has_describe);
}

test "keybindings_vm: deployments advertise traffic, and no longer advertise restart" {
    // This test used to assert deployments advertised "restart". That was enforcing a
    // lie with a sting in it: nothing implements a rollout restart, and the key it was
    // advertised on -- lowercase `r` -- is bound to refresh in resource_view's generic
    // switch. So the help promised Restart and the key delivered Refresh.
    //
    // Now inverted for restart, and positive for traffic, which is implemented and
    // reachable but had been advertised nowhere. Flip the restart half back in the
    // same commit that implements a rollout restart on a key that is actually free.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .deployments);
    defer vm.deinit();

    const bindings = vm.getBindings();

    var has_traffic = false;
    var has_refresh = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "traffic")) {
            has_traffic = true;
            try std.testing.expectEqualStrings("t", binding.key);
        }
        if (std.mem.eql(u8, binding.action, "refresh")) {
            has_refresh = true;
            try std.testing.expectEqualStrings("r", binding.key);
        }
        try std.testing.expect(!std.mem.eql(u8, binding.action, "restart"));
    }

    try std.testing.expect(has_traffic);
    try std.testing.expect(has_refresh);
}

test "keybindings_vm: all bindings have valid enum values" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const view_types = [_]ViewType{ .pods, .nodes, .deployments, .services };

    for (view_types) |view_type| {
        var vm = try KeyBindingsViewModel.init(allocator, view_type);
        defer vm.deinit();

        const bindings = vm.getBindings();

        for (bindings) |binding| {
            // Validate category enum
            _ = binding.category;

            // Ensure strings are not empty
            try std.testing.expect(binding.key.len > 0);
            try std.testing.expect(binding.description.len > 0);
            try std.testing.expect(binding.action.len > 0);
        }
    }
}

test "keybindings_vm: multiple init calls return same data" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm1 = try KeyBindingsViewModel.init(allocator, .pods);
    defer vm1.deinit();

    var vm2 = try KeyBindingsViewModel.init(allocator, .pods);
    defer vm2.deinit();

    const bindings1 = vm1.getBindings();
    const bindings2 = vm2.getBindings();

    // Should return same number of bindings
    try std.testing.expectEqual(bindings1.len, bindings2.len);
}

test "keybindings_vm: services does NOT advertise port-forward" {
    // This test used to assert services advertised port-forward. It was enforcing a
    // lie: `F` -> request_port_forward exists only in resource_view's is_pods branch,
    // so pressing it on a service did nothing. Inverted, and now also covered globally
    // by keybindings_data's unimplemented-action scan.
    //
    // Port-forwarding a Service is a genuinely useful thing k9s supports; implement it
    // by adding an is_services branch (or widening is_pods) and re-add the hint in the
    // same commit.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .services);
    defer vm.deinit();

    for (vm.getBindings()) |binding| {
        try std.testing.expect(!std.mem.eql(u8, binding.action, "port_forward"));
        try std.testing.expect(!std.mem.eql(u8, binding.action, "logs"));
        try std.testing.expect(!std.mem.eql(u8, binding.action, "bench"));
    }
}

test "keybindings_vm: cronjobs does NOT advertise trigger or suspend" {
    // Was asserting cronjobs advertised trigger. Nothing triggers a cronjob run
    // anywhere in c3s, and setCronJobSuspend exists with zero callers (and would fail
    // under the kubectl-proxy transport, since it reaches straight for self.client.?).
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .cronjobs);
    defer vm.deinit();

    for (vm.getBindings()) |binding| {
        try std.testing.expect(!std.mem.eql(u8, binding.action, "trigger"));
        try std.testing.expect(!std.mem.eql(u8, binding.action, "suspend"));
    }
}
