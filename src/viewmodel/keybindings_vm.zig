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
    priorityclasses,

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
    users,
    groups,

    // CRD resources
    customresourcedefinitions,

    // Misc views
    contexts,
    containers,
    workloads,
    portforwards,
    aliases,
    benchmarks,
    imagescans,
    references,
    screendumps,
    pulse,

    // Helm
    helmcharts,
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
        .priorityclasses => try bindings_data.loadPriorityClassesBindings(allocator),

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
        .users => try bindings_data.loadUsersBindings(allocator),
        .groups => try bindings_data.loadGroupsBindings(allocator),

        // CRD resources
        .customresourcedefinitions => try bindings_data.loadCRDBindings(allocator),

        // Misc views (use generic or specific bindings)
        .contexts => try bindings_data.loadContextsBindings(allocator),
        .containers => try bindings_data.loadContainersBindings(allocator),
        .workloads => try bindings_data.loadWorkloadsBindings(allocator),
        .portforwards => try bindings_data.loadPortForwardsBindings(allocator),
        .aliases => try bindings_data.loadAliasesBindings(allocator),
        .benchmarks => try bindings_data.loadBenchmarksBindings(allocator),
        .imagescans => try bindings_data.loadImageScansBindings(allocator),
        .references => try bindings_data.loadReferencesBindings(allocator),
        .screendumps => try bindings_data.loadScreenDumpsBindings(allocator),
        .pulse => try bindings_data.loadPulseBindings(allocator),

        // Helm
        .helmcharts => try bindings_data.loadHelmChartsBindings(allocator),
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
        .{ .key = "0", .description = "all", .category = .resource, .action = "namespace_all" },
        .{ .key = "1", .description = "default", .category = .resource, .action = "namespace_default" },
        .{ .key = "a", .description = "Attach", .category = .resource, .action = "attach" },
        .{ .key = "c", .description = "Copy", .category = .resource, .action = "copy" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "Ctrl-f", .description = "Kill Finalizers", .category = .resource, .action = "kill_finalizers" },
        .{ .key = "Ctrl-k", .description = "Kill", .category = .resource, .action = "kill" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "f", .description = "Show PortForward", .category = .resource, .action = "show_portforward" },
        .{ .key = "i", .description = "Set Image", .category = .resource, .action = "set_image" },
        .{ .key = "l", .description = "Logs", .category = .resource, .action = "logs" },
        .{ .key = "n", .description = "Copy Namespace", .category = .resource, .action = "copy_namespace" },
        .{ .key = "o", .description = "Show Node", .category = .resource, .action = "show_node" },
        .{ .key = "p", .description = "Logs Previous", .category = .resource, .action = "logs_previous" },
        .{ .key = "Shift-f", .description = "Port-Forward", .category = .resource, .action = "port_forward" },
        .{ .key = "Shift-j", .description = "Jump Owner", .category = .resource, .action = "jump_owner" },
        .{ .key = "Shift-r", .description = "Refresh", .category = .resource, .action = "refresh" },
        .{ .key = "s", .description = "Shell", .category = .resource, .action = "shell" },
        .{ .key = "t", .description = "Transfer", .category = .resource, .action = "transfer" },
        .{ .key = "v", .description = "View", .category = .resource, .action = "view" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "z", .description = "Sanitize", .category = .resource, .action = "sanitize" },

        // GENERAL COMMANDS
        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = "Ctrl-a", .description = "Aliases", .category = .general, .action = "aliases" },
        .{ .key = ":cmd", .description = "Command mode", .category = .general, .action = "command_mode" },
        .{ .key = "/term", .description = "Filter mode", .category = .general, .action = "filter_mode" },
        .{ .key = "esc", .description = "Back/Clear", .category = .general, .action = "back_clear" },
        .{ .key = "tab", .description = "Field Next", .category = .general, .action = "field_next" },
        .{ .key = "backtab", .description = "Field Previous", .category = .general, .action = "field_previous" },
        .{ .key = "Ctrl-r", .description = "Reload", .category = .general, .action = "reload" },
        .{ .key = "Ctrl-u", .description = "Command Clear", .category = .general, .action = "command_clear" },
        .{ .key = "Ctrl-e", .description = "Toggle Header", .category = .general, .action = "toggle_header" },
        .{ .key = "Ctrl-g", .description = "Toggle Crumbs", .category = .general, .action = "toggle_crumbs" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
        .{ .key = "space", .description = "Mark", .category = .general, .action = "mark" },
        .{ .key = "*", .description = "Mark All", .category = .general, .action = "mark_all" },
        .{ .key = "^", .description = "Invert Marks", .category = .general, .action = "mark_invert" },
        .{ .key = "\\", .description = "Mark Clear", .category = .general, .action = "mark_clear" },
        .{ .key = "Ctrl-s", .description = "Save", .category = .general, .action = "save" },

        // NAVIGATION COMMANDS
        .{ .key = "-", .description = "Last Command", .category = .navigation, .action = "last_command" },
        .{ .key = "0", .description = "Down", .category = .navigation, .action = "down" },
        .{ .key = "[", .description = "History Back", .category = .navigation, .action = "history_back" },
        .{ .key = "]", .description = "History Forward", .category = .navigation, .action = "history_forward" },
        .{ .key = "Ctrl-b", .description = "Page Up", .category = .navigation, .action = "page_up" },
        .{ .key = "Ctrl-f", .description = "Page Down", .category = .navigation, .action = "page_down" },
        .{ .key = "g", .description = "Goto Top", .category = .navigation, .action = "goto_top" },
        .{ .key = "Shift-g", .description = "Goto Bottom", .category = .navigation, .action = "goto_bottom" },
        .{ .key = "h", .description = "Left", .category = .navigation, .action = "left" },
        .{ .key = "j", .description = "Down", .category = .navigation, .action = "down" },
        .{ .key = "k", .description = "Up", .category = .navigation, .action = "up" },
        .{ .key = "l", .description = "Right", .category = .navigation, .action = "right" },

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
        // Cordon / Uncordon / Drain were advertised here with NO implementation
        // anywhere in the codebase -- the help screen promised actions that did
        // nothing. tasks/lessons.md already records the rule: "Hints/help must not
        // advertise unimplemented actions -- wire every key or remove the hint."
        // They are on the Phase 4 list in docs/design/2026-08-22-c3s-roadmap.md;
        // re-add each one in the same commit that implements it.
        .{ .key = "s", .description = "Shell", .category = .resource, .action = "shell" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "enter", .description = "View Pods", .category = .resource, .action = "view_pods" },

        // Sorting
        .{ .key = "Shift-r", .description = "Sort ROLE", .category = .sorting, .action = "sort_role" },
        .{ .key = "Shift-c", .description = "Sort CPU", .category = .sorting, .action = "sort_cpu" },
        .{ .key = "Shift-m", .description = "Sort MEM", .category = .sorting, .action = "sort_mem" },
        .{ .key = "Shift-o", .description = "Sort Pods", .category = .sorting, .action = "sort_pods" },

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
        .{ .key = "s", .description = "Scale", .category = .resource, .action = "scale" },
        .{ .key = "r", .description = "Restart", .category = .resource, .action = "restart" },
        .{ .key = "l", .description = "Logs", .category = .resource, .action = "logs" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "enter", .description = "View Pods", .category = .resource, .action = "view_pods" },

        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
    };

    return try allocator.dupe(KeyBinding, &bindings);
}

/// Load services-specific key bindings
fn loadServicesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "b", .description = "Bench Run/Stop", .category = .resource, .action = "bench" },
        .{ .key = "l", .description = "Logs", .category = .resource, .action = "logs" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "enter", .description = "View Pods", .category = .resource, .action = "view_pods" },
        .{ .key = "Shift-f", .description = "Port-Forward", .category = .resource, .action = "port_forward" },

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
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },

        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
    };

    return try allocator.dupe(KeyBinding, &bindings);
}

/// Common general bindings shared by all views
const common_general_bindings = [_]KeyBinding{
    .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
    .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
    .{ .key = "/term", .description = "Filter mode", .category = .general, .action = "filter_mode" },
    .{ .key = "esc", .description = "Back/Clear", .category = .general, .action = "back_clear" },
    .{ .key = "Ctrl-e", .description = "Toggle Header", .category = .general, .action = "toggle_header" },
};

/// Common navigation bindings shared by all views
const common_navigation_bindings = [_]KeyBinding{
    .{ .key = "j", .description = "Down", .category = .navigation, .action = "down" },
    .{ .key = "k", .description = "Up", .category = .navigation, .action = "up" },
    .{ .key = "g", .description = "Goto Top", .category = .navigation, .action = "goto_top" },
    .{ .key = "Shift-g", .description = "Goto Bottom", .category = .navigation, .action = "goto_bottom" },
    .{ .key = "Ctrl-b", .description = "Page Up", .category = .navigation, .action = "page_up" },
    .{ .key = "Ctrl-f", .description = "Page Down", .category = .navigation, .action = "page_down" },
};

/// Merge view-specific bindings with common general + navigation bindings
fn mergeWithCommon(allocator: std.mem.Allocator, specific: []const KeyBinding) ![]const KeyBinding {
    const total = specific.len + common_general_bindings.len + common_navigation_bindings.len;
    const result = try allocator.alloc(KeyBinding, total);
    var i: usize = 0;
    for (specific) |b| {
        result[i] = b;
        i += 1;
    }
    for (&common_general_bindings) |b| {
        result[i] = b;
        i += 1;
    }
    for (&common_navigation_bindings) |b| {
        result[i] = b;
        i += 1;
    }
    return result;
}

// --- Tests ---

test "keybindings_vm: init and deinit for all view types" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test all 44 view types can be initialized
    const view_types = [_]ViewType{
        // Core resources
        .pods,            .nodes,                     .services,        .namespaces,          .events,      .secrets,      .configmaps,
        .serviceaccounts, .persistentvolumeclaims,    .priorityclasses,
        // Apps resources
        .deployments,         .replicasets, .statefulsets, .daemonsets,
        // Batch resources
        .cronjobs,        .jobs,
        // RBAC resources
                             .clusterroles,    .clusterrolebindings, .roles,       .rolebindings, .users,
        .groups,
        // CRD resources
                 .customresourcedefinitions,
        // Misc views
        .contexts,        .containers,          .workloads,   .portforwards, .aliases,
        .benchmarks,      .imagescans,                .references,      .screendumps,         .pulse,
        // Helm
              .helmcharts,
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

    // Tripwire, deliberately inverted.
    //
    // This test used to assert that cordon and drain WERE advertised -- enforcing a
    // lie, since neither has any implementation. It now asserts the opposite, so the
    // suite fails if an unimplemented action is advertised again. When Phase 4
    // implements them, flip these back in the same commit as the implementation.
    for (bindings) |binding| {
        try std.testing.expect(!std.mem.eql(u8, binding.action, "cordon"));
        try std.testing.expect(!std.mem.eql(u8, binding.action, "uncordon"));
        try std.testing.expect(!std.mem.eql(u8, binding.action, "drain"));
    }

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

test "keybindings_vm: deployments view has scale and restart" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .deployments);
    defer vm.deinit();

    const bindings = vm.getBindings();

    var has_scale = false;
    var has_restart = false;

    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "scale")) has_scale = true;
        if (std.mem.eql(u8, binding.action, "restart")) has_restart = true;
    }

    try std.testing.expect(has_scale);
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

test "keybindings_vm: services view has port-forward binding" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .services);
    defer vm.deinit();

    const bindings = vm.getBindings();

    var has_port_forward = false;

    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "port_forward")) has_port_forward = true;
    }

    try std.testing.expect(has_port_forward);
}

test "keybindings_vm: cronjobs has trigger binding" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .cronjobs);
    defer vm.deinit();

    const bindings = vm.getBindings();

    var has_trigger = false;

    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "trigger")) has_trigger = true;
    }

    try std.testing.expect(has_trigger);
}
