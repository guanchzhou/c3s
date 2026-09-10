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
        .{ .key = "f", .description = "Show Port-Forwards", .category = .resource, .action = "show_portforward" },
        // k9s refresh is Ctrl-r (daily_driver). Lowercase `r` still refreshes here
        // because it does not collide with drain/restart.
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
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
    };

    return bindings_data.withDailyDriver(allocator, &bindings);
}

/// Load nodes-specific key bindings
fn loadNodesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    // Node-specific key bindings
    const bindings = [_]KeyBinding{
        // Node-specific commands. k9s keys: `r` drain, `u` cordon toggle.
        // `c` is copy (daily_driver), matching every other table.
        .{ .key = "u", .description = "Cordon", .category = .resource, .action = "cordon" },
        .{ .key = "u", .description = "Uncordon", .category = .resource, .action = "uncordon" },
        .{ .key = "r", .description = "Drain", .category = .resource, .action = "drain" },
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

    return bindings_data.withDailyDriver(allocator, &bindings);
}

/// Load deployments-specific key bindings
fn loadDeploymentsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    // Similar to pods but with deployment-specific commands
    const bindings = [_]KeyBinding{
        // k9s: `r` restarts the rollout; Ctrl-r (daily_driver) refreshes.
        .{ .key = "r", .description = "Restart", .category = .resource, .action = "restart" },
        .{ .key = "s", .description = "Scale", .category = .resource, .action = "scale" },
        .{ .key = "Ctrl-l", .description = "Rollback", .category = .resource, .action = "rollback" },
        .{ .key = "z", .description = "View ReplicaSets", .category = .resource, .action = "view_replicasets" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
        .{ .key = "t", .description = "Traffic", .category = .resource, .action = "traffic" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },

        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
    };

    return bindings_data.withDailyDriver(allocator, &bindings);
}

/// Load services-specific key bindings
fn loadServicesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "Shift-f", .description = "Port-Forward", .category = .resource, .action = "port_forward" },
        .{ .key = "f", .description = "Show Port-Forwards", .category = .resource, .action = "show_portforward" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },

        .{ .key = "Shift-t", .description = "Sort Type", .category = .sorting, .action = "sort_type" },

        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
    };

    return bindings_data.withDailyDriver(allocator, &bindings);
}

/// Load configmaps-specific key bindings
fn loadConfigMapsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "u", .description = "Used By", .category = .resource, .action = "used_by" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },

        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
    };

    return bindings_data.withDailyDriver(allocator, &bindings);
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
    var has_copy = false;

    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "attach")) has_attach = true;
        if (std.mem.eql(u8, binding.action, "logs")) has_logs = true;
        if (std.mem.eql(u8, binding.action, "describe")) has_describe = true;
        if (std.mem.eql(u8, binding.action, "copy")) {
            has_copy = true;
            try std.testing.expectEqualStrings("c", binding.key);
        }
    }

    try std.testing.expect(has_attach);
    try std.testing.expect(has_logs);
    try std.testing.expect(has_describe);
    try std.testing.expect(has_copy);
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
            try std.testing.expectEqualStrings("r", binding.key);
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

test "keybindings_vm: deployments advertise traffic, refresh on Ctrl-r, restart on r" {
    // k9s: `r` restarts the rollout; Ctrl-r refreshes (daily_driver).
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .deployments);
    defer vm.deinit();

    const bindings = vm.getBindings();

    var has_traffic = false;
    var has_refresh = false;
    var has_restart = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "traffic")) {
            has_traffic = true;
            try std.testing.expectEqualStrings("t", binding.key);
        }
        if (std.mem.eql(u8, binding.action, "refresh")) {
            has_refresh = true;
            try std.testing.expectEqualStrings("Ctrl-r", binding.key);
        }
        if (std.mem.eql(u8, binding.action, "restart")) {
            has_restart = true;
            try std.testing.expectEqualStrings("r", binding.key);
        }
    }

    try std.testing.expect(has_traffic);
    try std.testing.expect(has_refresh);
    try std.testing.expect(has_restart);
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

test "keybindings_vm: services advertises port-forward" {
    // Inverted from the previous tripwire: `F` on a Service is now wired in
    // resource_view's is_services branch, so the hint is allowed to exist.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .services);
    defer vm.deinit();

    var has_pf = false;
    for (vm.getBindings()) |binding| {
        if (std.mem.eql(u8, binding.action, "port_forward")) has_pf = true;
        try std.testing.expect(!std.mem.eql(u8, binding.action, "logs"));
        try std.testing.expect(!std.mem.eql(u8, binding.action, "bench"));
    }
    try std.testing.expect(has_pf);
}

test "keybindings_vm: cronjobs advertises trigger and suspend" {
    // Flipped in the same commit that wires `p`/`t` through App.handleKey → kubectl.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .cronjobs);
    defer vm.deinit();

    var has_trigger = false;
    var has_suspend = false;
    for (vm.getBindings()) |binding| {
        if (std.mem.eql(u8, binding.action, "trigger")) {
            has_trigger = true;
            try std.testing.expectEqualStrings("t", binding.key);
        }
        if (std.mem.eql(u8, binding.action, "suspend")) {
            has_suspend = true;
            try std.testing.expectEqualStrings("p", binding.key);
        }
    }
    try std.testing.expect(has_trigger);
    try std.testing.expect(has_suspend);
}
