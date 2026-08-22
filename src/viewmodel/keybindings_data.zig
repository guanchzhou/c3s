// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Key bindings data for all resource views

const std = @import("std");
const KeyBinding = @import("../model/keybindings.zig").KeyBinding;

// ============================================================================
// CORE RESOURCES
// ============================================================================

/// Namespaces bindings
pub fn loadNamespacesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "Switch Context", .category = .resource, .action = "switch" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// Events bindings
pub fn loadEventsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Shift-t", .description = "Sort Type", .category = .sorting, .action = "sort_type" },
        .{ .key = "Shift-r", .description = "Sort Reason", .category = .sorting, .action = "sort_reason" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// Secrets bindings
pub fn loadSecretsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "x", .description = "Decode", .category = .resource, .action = "decode" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// ServiceAccounts bindings
pub fn loadServiceAccountsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// PersistentVolumeClaims bindings
pub fn loadPVCsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "Shift-s", .description = "Sort Status", .category = .sorting, .action = "sort_status" },
        .{ .key = "Shift-c", .description = "Sort Capacity", .category = .sorting, .action = "sort_capacity" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

// ============================================================================
// APPS RESOURCES
// ============================================================================

/// ReplicaSets bindings
pub fn loadReplicaSetsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "s", .description = "Scale", .category = .resource, .action = "scale" },
        .{ .key = "l", .description = "Logs", .category = .resource, .action = "logs" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// StatefulSets bindings
pub fn loadStatefulSetsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "s", .description = "Scale", .category = .resource, .action = "scale" },
        .{ .key = "r", .description = "Restart", .category = .resource, .action = "restart" },
        .{ .key = "l", .description = "Logs", .category = .resource, .action = "logs" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// DaemonSets bindings
pub fn loadDaemonSetsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "r", .description = "Restart", .category = .resource, .action = "restart" },
        .{ .key = "l", .description = "Logs", .category = .resource, .action = "logs" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

// ============================================================================
// BATCH RESOURCES
// ============================================================================

/// CronJobs bindings
pub fn loadCronJobsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "t", .description = "Trigger", .category = .resource, .action = "trigger" },
        .{ .key = "s", .description = "Suspend/Resume", .category = .resource, .action = "suspend" },
        .{ .key = "l", .description = "Logs", .category = .resource, .action = "logs" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// Jobs bindings
pub fn loadJobsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "l", .description = "Logs", .category = .resource, .action = "logs" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "Shift-c", .description = "Sort Completions", .category = .sorting, .action = "sort_completions" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

// ============================================================================
// RBAC RESOURCES
// ============================================================================

/// Roles/ClusterRoles bindings
pub fn loadRolesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "View Rules", .category = .resource, .action = "view_rules" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// RoleBindings/ClusterRoleBindings bindings
pub fn loadRoleBindingsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "View Rules", .category = .resource, .action = "view_rules" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

// ============================================================================
// MISC VIEWS
// ============================================================================

/// Contexts bindings
pub fn loadContextsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "Switch", .category = .resource, .action = "switch" },
        .{ .key = "d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// PortForwards bindings
pub fn loadPortForwardsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "Ctrl-d", .description = "Stop", .category = .resource, .action = "stop" },
        .{ .key = "Shift-f", .description = "Start", .category = .resource, .action = "start" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// Aliases bindings
pub fn loadAliasesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "Goto Resource", .category = .resource, .action = "goto" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

// --- Tests ---

test "keybindings_data: all load functions return valid bindings" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test all 15 binding load functions
    const load_functions = .{
        loadNamespacesBindings,
        loadEventsBindings,
        loadSecretsBindings,
        loadServiceAccountsBindings,
        loadPVCsBindings,
        loadReplicaSetsBindings,
        loadStatefulSetsBindings,
        loadDaemonSetsBindings,
        loadCronJobsBindings,
        loadJobsBindings,
        loadRolesBindings,
        loadRoleBindingsBindings,
        loadContextsBindings,
        loadPortForwardsBindings,
        loadAliasesBindings,
    };

    inline for (load_functions) |load_fn| {
        const bindings = try load_fn(allocator);
        defer allocator.free(bindings);

        // Validate each binding
        for (bindings) |binding| {
            try std.testing.expect(binding.key.len > 0);
            try std.testing.expect(binding.description.len > 0);
            try std.testing.expect(binding.action.len > 0);

            // Validate category is a valid enum value
            _ = binding.category;
        }
    }
}

test "keybindings_data: namespaces has switch binding" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try loadNamespacesBindings(allocator);
    defer allocator.free(bindings);

    var has_switch = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "switch")) has_switch = true;
    }

    try std.testing.expect(has_switch);
}

test "keybindings_data: secrets has decode binding" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try loadSecretsBindings(allocator);
    defer allocator.free(bindings);

    var has_decode = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "decode")) has_decode = true;
    }

    try std.testing.expect(has_decode);
}

test "keybindings_data: cronjobs has trigger and suspend" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try loadCronJobsBindings(allocator);
    defer allocator.free(bindings);

    var has_trigger = false;
    var has_suspend = false;

    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "trigger")) has_trigger = true;
        if (std.mem.eql(u8, binding.action, "suspend")) has_suspend = true;
    }

    try std.testing.expect(has_trigger);
    try std.testing.expect(has_suspend);
}

test "keybindings_data: all bindings are UTF-8 valid" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const load_functions = .{
        loadNamespacesBindings,
        loadSecretsBindings,
        loadCronJobsBindings,
    };

    inline for (load_functions) |load_fn| {
        const bindings = try load_fn(allocator);
        defer allocator.free(bindings);

        for (bindings) |binding| {
            try std.testing.expect(std.unicode.utf8ValidateSlice(binding.key));
            try std.testing.expect(std.unicode.utf8ValidateSlice(binding.description));
            try std.testing.expect(std.unicode.utf8ValidateSlice(binding.action));
        }
    }
}

test "keybindings_data: portforwards has start and stop" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try loadPortForwardsBindings(allocator);
    defer allocator.free(bindings);

    var has_stop = false;
    var has_start = false;

    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "stop")) has_stop = true;
        if (std.mem.eql(u8, binding.action, "start")) has_start = true;
    }

    try std.testing.expect(has_stop);
    try std.testing.expect(has_start);
}

test "keybindings_data: pvcs has capacity sorting" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try loadPVCsBindings(allocator);
    defer allocator.free(bindings);

    var has_sort_capacity = false;

    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "sort_capacity")) has_sort_capacity = true;
    }

    try std.testing.expect(has_sort_capacity);
}

test "keybindings_data: secrets advertise decode, which is now implemented" {
    // `x` = "Decode" was advertised here with no implementation anywhere -- the fifth
    // instance of that defect class in this codebase. It is real now (request_decode ->
    // App.showDecodedSecret), so this asserts the hint is present rather than absent.
    // If decode is ever removed, remove the hint in the same commit.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try loadSecretsBindings(allocator);
    defer allocator.free(bindings);

    var has_decode = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "decode")) {
            has_decode = true;
            try std.testing.expectEqualStrings("x", binding.key);
        }
    }
    try std.testing.expect(has_decode);
}

/// Bindings that are true on ANY table-backed resource view.
///
/// This exists because nine resource types (Ingresses, NetworkPolicies, ResourceQuotas,
/// LimitRanges, PodDisruptionBudgets, HPA, PersistentVolumes, Endpoints, StorageClasses)
/// have no ViewType of their own, so App.currentViewType() fell back to `.pods` and `?`
/// showed PODS' help under their own name -- advertising Shell, Logs, Attach and
/// Sanitize on an Ingress, none of which do anything there.
///
/// Every entry here is verified reachable for a generic ResourceView: describe/yaml via
/// TableState.handleNavigationKey, delete via App's global Ctrl-D (all nine ARE
/// ResourceType members, so it resolves), refresh via resource_view's generic switch,
/// and the mark family via the same switch.
///
/// Deliberately omitted: per-view sort keys (they differ per config, and this table
/// cannot see which), and `0` = All Namespaces (meaningless on the cluster-scoped
/// members like PersistentVolumes and StorageClasses).
pub fn loadGenericResourceBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "r", .description = "Refresh", .category = .resource, .action = "refresh" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },

        .{ .key = "j", .description = "Down", .category = .navigation, .action = "down" },
        .{ .key = "k", .description = "Up", .category = .navigation, .action = "up" },
        .{ .key = "g", .description = "Goto Top", .category = .navigation, .action = "goto_top" },
        .{ .key = "Shift-g", .description = "Goto Bottom", .category = .navigation, .action = "goto_bottom" },
        .{ .key = "Ctrl-b", .description = "Page Up", .category = .navigation, .action = "page_up" },

        .{ .key = "space", .description = "Mark", .category = .general, .action = "mark" },
        .{ .key = "*", .description = "Mark All", .category = .general, .action = "mark_all" },
        .{ .key = "^", .description = "Invert Marks", .category = .general, .action = "mark_invert" },
        .{ .key = "\\", .description = "Mark Clear", .category = .general, .action = "mark_clear" },

        .{ .key = "/term", .description = "Filter mode", .category = .general, .action = "filter_mode" },
        .{ .key = "x", .description = "Clear Filter", .category = .general, .action = "clear_filter" },
        .{ .key = ":cmd", .description = "Command mode", .category = .general, .action = "command_mode" },
        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = "Ctrl-a", .description = "Aliases", .category = .general, .action = "aliases" },
        .{ .key = "Ctrl-e", .description = "Toggle Header", .category = .general, .action = "toggle_header" },
        .{ .key = "esc", .description = "Back/Clear", .category = .general, .action = "back_clear" },
        .{ .key = ":q", .description = "Quit", .category = .general, .action = "quit" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}
