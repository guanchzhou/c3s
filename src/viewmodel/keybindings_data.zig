// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// K9s-compatible key bindings data for all resource views
// Based on k9s internal/view/*.go files

const std = @import("std");
const KeyBinding = @import("../model/keybindings.zig").KeyBinding;

// ============================================================================
// CORE RESOURCES
// ============================================================================

/// Namespaces bindings (from k9s namespace.go)
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

/// PriorityClasses bindings
pub fn loadPriorityClassesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
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

/// Users bindings (RBAC subjects)
pub fn loadUsersBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "View Policies", .category = .resource, .action = "view_policies" },
        .{ .key = "p", .description = "Policies", .category = .resource, .action = "policies" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// Groups bindings (RBAC subjects)
pub fn loadGroupsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "View Policies", .category = .resource, .action = "view_policies" },
        .{ .key = "p", .description = "Policies", .category = .resource, .action = "policies" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

// ============================================================================
// CRD RESOURCES
// ============================================================================

/// CustomResourceDefinitions bindings
pub fn loadCRDBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "View Instances", .category = .resource, .action = "view_instances" },
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

/// Containers bindings (inside pod)
pub fn loadContainersBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "Logs", .category = .resource, .action = "logs" },
        .{ .key = "s", .description = "Shell", .category = .resource, .action = "shell" },
        .{ .key = "a", .description = "Attach", .category = .resource, .action = "attach" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// Workloads bindings (aggregated view)
pub fn loadWorkloadsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "View Details", .category = .resource, .action = "view" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
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

/// Benchmarks bindings
pub fn loadBenchmarksBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "Ctrl-d", .description = "Stop", .category = .resource, .action = "stop" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// ImageScans bindings (vulnerability scanning)
pub fn loadImageScansBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "View Details", .category = .resource, .action = "view" },
        .{ .key = "Shift-s", .description = "Sort Severity", .category = .sorting, .action = "sort_severity" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// References bindings (shows what references a resource)
pub fn loadReferencesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "Goto Reference", .category = .resource, .action = "goto" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// ScreenDumps bindings
pub fn loadScreenDumpsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "View Dump", .category = .resource, .action = "view" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// Pulse bindings (live metrics)
pub fn loadPulseBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "p", .description = "Pause/Resume", .category = .resource, .action = "pause" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

// ============================================================================
// HELM
// ============================================================================

/// HelmCharts bindings
pub fn loadHelmChartsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "enter", .description = "View Chart", .category = .resource, .action = "view" },
        .{ .key = "u", .description = "Uninstall", .category = .resource, .action = "uninstall" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}
