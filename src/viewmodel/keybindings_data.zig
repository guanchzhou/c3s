// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Key bindings data for all resource views

const std = @import("std");
const KeyBinding = @import("../model/keybindings.zig").KeyBinding;

/// Global k9s daily-driver keys that resource tables actually handle.
pub const daily_driver_bindings = [_]KeyBinding{
    .{ .key = "c", .description = "Copy Name", .category = .resource, .action = "copy" },
    .{ .key = "n", .description = "Copy Namespace", .category = .resource, .action = "copy_namespace" },
    .{ .key = "Shift-y", .description = "Copy Column", .category = .resource, .action = "copy_column" },
    .{ .key = "Shift-t", .description = "Session Timeline", .category = .resource, .action = "timeline" },
    .{ .key = "Tab", .description = "Next Kind", .category = .navigation, .action = "next_kind" },
    .{ .key = "Shift-Tab", .description = "Previous Kind", .category = .navigation, .action = "previous_kind" },
    .{ .key = "Shift-j", .description = "Jump to Owner", .category = .resource, .action = "jump_owner" },
    .{ .key = "-", .description = "Last Command", .category = .general, .action = "last_command" },
    .{ .key = "[", .description = "History Back", .category = .general, .action = "history_back" },
    .{ .key = "]", .description = "History Forward", .category = .general, .action = "history_forward" },
    .{ .key = "Ctrl-s", .description = "Save JSON", .category = .general, .action = "save" },
    .{ .key = "Ctrl-g", .description = "Toggle Crumbs", .category = .general, .action = "toggle_crumbs" },
    .{ .key = "Ctrl-w", .description = "Wide Columns", .category = .general, .action = "toggle_wide" },
    .{ .key = "Ctrl-z", .description = "Toggle Faults", .category = .general, .action = "toggle_faults" },
    .{ .key = "Ctrl-r", .description = "Refresh", .category = .resource, .action = "refresh" },
    .{ .key = "Ctrl-c", .description = "Quit", .category = .general, .action = "quit" },
    .{ .key = "Ctrl-Space", .description = "Mark Range", .category = .general, .action = "mark_range" },
    .{ .key = "Ctrl-\\", .description = "Mark Clear", .category = .general, .action = "mark_clear" },
    .{ .key = "Shift-Left", .description = "Move Column Left", .category = .navigation, .action = "move_column_left" },
    .{ .key = "Shift-Right", .description = "Move Column Right", .category = .navigation, .action = "move_column_right" },
    .{ .key = "1-9", .description = "Recent Namespace", .category = .navigation, .action = "recent_namespace" },
};

pub fn concatBindings(allocator: std.mem.Allocator, head: []const KeyBinding, tail: []const KeyBinding) ![]const KeyBinding {
    const out = try allocator.alloc(KeyBinding, head.len + tail.len);
    @memcpy(out[0..head.len], head);
    @memcpy(out[head.len..], tail);
    return out;
}

pub fn withDailyDriver(allocator: std.mem.Allocator, extra: []const KeyBinding) ![]const KeyBinding {
    return concatBindings(allocator, &daily_driver_bindings, extra);
}

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
        .{ .key = "Ctrl-r", .description = "Refresh", .category = .resource, .action = "refresh" },
        .{ .key = "1-9", .description = "Recent Namespace", .category = .navigation, .action = "recent_namespace" },
    };
    return try allocator.dupe(KeyBinding, &bindings);
}

/// Events bindings
pub fn loadEventsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Shift-r", .description = "Sort Reason", .category = .sorting, .action = "sort_reason" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
    };
    return withDailyDriver(allocator, &bindings);
}

/// Secrets bindings
pub fn loadSecretsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "x", .description = "Decode", .category = .resource, .action = "decode" },
        .{ .key = "u", .description = "Used By", .category = .resource, .action = "used_by" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
    };
    return withDailyDriver(allocator, &bindings);
}

/// ServiceAccounts bindings
pub fn loadServiceAccountsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "u", .description = "Used By", .category = .resource, .action = "used_by" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
    };
    return withDailyDriver(allocator, &bindings);
}

/// PersistentVolumeClaims bindings
pub fn loadPVCsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "u", .description = "Used By", .category = .resource, .action = "used_by" },
        .{ .key = "Shift-s", .description = "Sort Status", .category = .sorting, .action = "sort_status" },
        .{ .key = "Shift-c", .description = "Sort Capacity", .category = .sorting, .action = "sort_capacity" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
    };
    return withDailyDriver(allocator, &bindings);
}

// ============================================================================
// APPS RESOURCES
// ============================================================================

/// ReplicaSets bindings
pub fn loadReplicaSetsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "Shift-x", .description = "Explain Unhealthy", .category = .resource, .action = "explain_health" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "s", .description = "Scale", .category = .resource, .action = "scale" },
        .{ .key = "Ctrl-l", .description = "Rollback", .category = .resource, .action = "rollback" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
    };
    return withDailyDriver(allocator, &bindings);
}

/// StatefulSets bindings
pub fn loadStatefulSetsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "Shift-x", .description = "Explain Unhealthy", .category = .resource, .action = "explain_health" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "s", .description = "Scale", .category = .resource, .action = "scale" },
        .{ .key = "r", .description = "Restart", .category = .resource, .action = "restart" },
        .{ .key = "Ctrl-l", .description = "Rollback", .category = .resource, .action = "rollback" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
    };
    return withDailyDriver(allocator, &bindings);
}

/// DaemonSets bindings
pub fn loadDaemonSetsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "Shift-x", .description = "Explain Unhealthy", .category = .resource, .action = "explain_health" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "r", .description = "Restart", .category = .resource, .action = "restart" },
        .{ .key = "Ctrl-l", .description = "Rollback", .category = .resource, .action = "rollback" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
    };
    return withDailyDriver(allocator, &bindings);
}

// ============================================================================
// BATCH RESOURCES
// ============================================================================

/// CronJobs bindings
pub fn loadCronJobsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "p", .description = "Suspend", .category = .resource, .action = "suspend" },
        .{ .key = "t", .description = "Trigger", .category = .resource, .action = "trigger" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
    };
    return withDailyDriver(allocator, &bindings);
}

/// Jobs bindings
pub fn loadJobsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "Shift-x", .description = "Explain Unhealthy", .category = .resource, .action = "explain_health" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
        .{ .key = "Shift-c", .description = "Sort Completions", .category = .sorting, .action = "sort_completions" },
        .{ .key = "w", .description = "Warp Namespace", .category = .resource, .action = "warp" },
    };
    return withDailyDriver(allocator, &bindings);
}

// ============================================================================
// RBAC RESOURCES
// ============================================================================

/// Roles/ClusterRoles bindings
pub fn loadRolesBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return withDailyDriver(allocator, &bindings);
}

/// RoleBindings/ClusterRoleBindings bindings
pub fn loadRoleBindingsBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "y", .description = "YAML", .category = .resource, .action = "yaml" },
        .{ .key = "Ctrl-d", .description = "Delete", .category = .resource, .action = "delete" },
    };
    return withDailyDriver(allocator, &bindings);
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
    const bindings = [_]KeyBinding{};
    return try allocator.dupe(KeyBinding, &bindings);
}

/// Cedar workbench bindings. Every one of these runs the official `cedar` binary
/// against the selected Policy object; none of them mutate the cluster.
pub fn loadCedarBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const bindings = [_]KeyBinding{
        .{ .key = "Enter", .description = "Policy source", .category = .resource, .action = "cedar_source" },
        .{ .key = "Shift-p", .description = "Check parse", .category = .resource, .action = "cedar_check_parse" },
        .{ .key = "Shift-c", .description = "Format", .category = .resource, .action = "cedar_format" },
        .{ .key = "Shift-v", .description = "Validate (schema)", .category = .resource, .action = "cedar_validate" },
        .{ .key = "Shift-a", .description = "Scan all policies", .category = .resource, .action = "cedar_scan" },
        .{ .key = "Shift-i", .description = "Can-i (P do A on R)", .category = .resource, .action = "cedar_can_i" },
        .{ .key = "r", .description = "Refresh", .category = .resource, .action = "refresh" },
        .{ .key = "/", .description = "Filter", .category = .navigation, .action = "filter" },
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
        loadCedarBindings,
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

test "keybindings_data: cronjobs advertises trigger, suspend, describe" {
    // Flipped in the same commit that implements `p`/`t` via kubectl.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try loadCronJobsBindings(allocator);
    defer allocator.free(bindings);

    var has_describe = false;
    var has_trigger = false;
    var has_suspend = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "describe")) has_describe = true;
        if (std.mem.eql(u8, binding.action, "trigger")) has_trigger = true;
        if (std.mem.eql(u8, binding.action, "suspend")) has_suspend = true;
    }
    try std.testing.expect(has_describe);
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

test "keybindings_data: portforwards advertises implemented start and stop" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try loadPortForwardsBindings(allocator);
    defer allocator.free(bindings);

    var has_start = false;
    var has_stop = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "start")) has_start = true;
        if (std.mem.eql(u8, binding.action, "stop")) has_stop = true;
    }
    try std.testing.expect(has_start);
    try std.testing.expect(has_stop);
}

test "keybindings_data: Argo applications advertise refresh and sync details" {
    const bindings = try loadArgoApplicationBindings(std.testing.allocator);
    defer std.testing.allocator.free(bindings);

    var refresh = false;
    var hard_refresh = false;
    var sync_details = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "argo_refresh")) refresh = true;
        if (std.mem.eql(u8, binding.action, "argo_hard_refresh")) hard_refresh = true;
        if (std.mem.eql(u8, binding.action, "argo_sync_details")) sync_details = true;
    }
    try std.testing.expect(refresh and hard_refresh and sync_details);
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
        .{ .key = "e", .description = "Edit", .category = .resource, .action = "edit" },
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
    return withDailyDriver(allocator, &bindings);
}

pub fn loadArgoApplicationBindings(allocator: std.mem.Allocator) ![]const KeyBinding {
    const argo = [_]KeyBinding{
        .{ .key = "Shift-r", .description = "Argo Refresh", .category = .resource, .action = "argo_refresh" },
        .{ .key = "Shift-h", .description = "Argo Hard Refresh", .category = .resource, .action = "argo_hard_refresh" },
        .{ .key = "Shift-s", .description = "Argo Sync Details", .category = .resource, .action = "argo_sync_details" },
    };
    const generic = try loadGenericResourceBindings(allocator);
    defer allocator.free(generic);
    return concatBindings(allocator, generic, &argo);
}

/// Actions with no implementation anywhere in c3s.
///
/// This is the canonical list, and the test below enforces it across EVERY ViewType.
/// Before it existed, the same defect was found five separate times by hand and the
/// countermeasure was a per-view tripwire test each time -- which does not scale and
/// cannot catch the next view.
///
/// The rule: a help entry may only exist for an action a key actually performs. To
/// implement one of these, delete it from this list in the SAME commit that wires it
/// up, and add the binding then.
///
/// Grouped by why they are absent:
///
///   - Workload mutations (`scale`, `restart`, `suspend`, `trigger`, `rollback`)
///     are implemented via `K8sService.runKubectl` and are NOT in this list.
///   - `view_rules`, `view_policies`, `view_instances`: Enter-to-drill-down.
///     There is not even a KeyResult variant for these. `view_pods` is wired on nodes.
///   - `view`, `bench`: never existed as table keys. `bench` is an OUT subsystem.
///     `f` = show port-forwards is wired on pods/services.
///   - `field_next`, `field_previous`, `reload`, `command_clear`, `left`, `right`:
///     column-cursor / leftover names. Shift-arrows move columns without a cursor.
///   - `namespace_all`, `namespace_default`: superseded by `toggle_all_namespaces`
///     on `0`, which is real.
///   - `xray`, `pulses`, `popeye`, `charts`, `plugins`, `screendump`, `jsonpath`:
///     owner OUT list (not deferred). Do not advertise.
pub const unimplemented_actions = [_][]const u8{
    "view_rules",        "view_policies", "view_instances",
    "view",              "bench",         "field_next",
    "field_previous",    "reload",        "command_clear",
    "left",              "right",         "namespace_all",
    "namespace_default", "goto",          "xray",
    "pulses",            "popeye",        "charts",
    "plugins",           "screendump",    "jsonpath",
};

test "no view advertises an action that nothing implements" {
    // The enforcement that replaces five hand-found instances and their five
    // per-view tripwires. Scans every ViewType, so it also covers views added later.
    const keybindings_vm = @import("keybindings_vm.zig");
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    for (std.enums.values(keybindings_vm.ViewType)) |vt| {
        var vm = try keybindings_vm.KeyBindingsViewModel.init(allocator, vt);
        defer vm.deinit();

        for (vm.getBindings()) |binding| {
            for (unimplemented_actions) |dead| {
                if (std.mem.eql(u8, binding.action, dead)) {
                    std.debug.print(
                        "{s} advertises '{s}' on key '{s}', which nothing implements\n",
                        .{ @tagName(vt), binding.action, binding.key },
                    );
                    return error.ViewAdvertisesUnimplementedAction;
                }
            }
        }
    }
}

/// Actions that ARE implemented, but only for specific views.
///
/// The `unimplemented_actions` scan above cannot catch these: `logs` is real, so
/// it is absent from that list, yet advertising it on configmaps is just as
/// false as inventing an action -- resource_view only wires logs inside its
/// `is_pods` branch. `edit` used to be in that category; it is now on the
/// generic resource-view switch, so it is advertised on `.generic` (and pods /
/// services) and must not appear in this list.
///
/// To widen one of these, add the branch in resource_view.zig and add the view here in
/// the same commit.
const OwnedActions = struct { views: []const []const u8, actions: []const []const u8 };

const view_scoped_actions = [_]OwnedActions{
    // resource_view.zig `is_pods` branch. attach/logs/shell are pod-specific;
    // edit is generic (see loadGenericResourceBindings) and lives outside this list.
    .{
        .views = &.{"pods"},
        .actions = &.{
            "logs",            "shell",         "attach",
            "show_node",       "logs_previous", "set_image",
            "sanitize",        "transfer",      "kill",
            "kill_finalizers",
        },
    },
    // resource_view.zig `is_pods` + `is_services` branches.
    .{ .views = &.{ "pods", "services" }, .actions = &.{ "port_forward", "show_portforward" } },
    // resource_view.zig `is_nodes` branch.
    .{ .views = &.{"nodes"}, .actions = &.{ "cordon", "uncordon", "drain", "view_pods" } },
    // resource_view.zig `is_secrets` branch.
    .{ .views = &.{"secrets"}, .actions = &.{"decode"} },
    // resource_view.zig generic switch, gated on config.name == "deployments".
    .{ .views = &.{"deployments"}, .actions = &.{ "traffic", "view_replicasets" } },
    .{ .views = &.{ "deployments", "statefulsets", "replicasets" }, .actions = &.{"scale"} },
    .{ .views = &.{ "deployments", "statefulsets", "daemonsets" }, .actions = &.{"restart"} },
    .{ .views = &.{ "deployments", "statefulsets", "daemonsets", "replicasets" }, .actions = &.{"rollback"} },
    .{ .views = &.{"cronjobs"}, .actions = &.{ "suspend", "trigger" } },
    .{ .views = &.{ "pods", "services", "events", "secrets", "configmaps", "serviceaccounts", "persistentvolumeclaims", "deployments", "replicasets", "statefulsets", "daemonsets", "cronjobs", "jobs", "roles", "rolebindings" }, .actions = &.{"warp"} },
    .{ .views = &.{ "serviceaccounts", "secrets", "configmaps", "persistentvolumeclaims" }, .actions = &.{"used_by"} },
    // CedarView.zig. These need a Cedar Policy object's source, so they exist nowhere
    // else -- the aggregated policy table deliberately does not carry it.
    .{
        .views = &.{"cedar"},
        .actions = &.{
            "cedar_source",   "cedar_check_parse", "cedar_format",
            "cedar_validate", "cedar_scan",        "cedar_can_i",
        },
    },
    // PortForwardsView's own handleKey.
    .{ .views = &.{"portforwards"}, .actions = &.{"stop"} },
    // DynamicResourceView's applications.argoproj.io branch.
    .{ .views = &.{"applications"}, .actions = &.{ "argo_refresh", "argo_hard_refresh", "argo_sync_details" } },
};

test "no view advertises an action implemented only for a different view" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const keybindings_vm = @import("keybindings_vm.zig");

    for (std.enums.values(keybindings_vm.ViewType)) |vt| {
        var vm = try keybindings_vm.KeyBindingsViewModel.init(allocator, vt);
        defer vm.deinit();

        for (vm.getBindings()) |binding| {
            for (view_scoped_actions) |scope| {
                var owns = false;
                for (scope.views) |v| {
                    if (std.mem.eql(u8, v, @tagName(vt))) owns = true;
                }
                if (owns) continue;
                for (scope.actions) |action| {
                    if (std.mem.eql(u8, binding.action, action)) {
                        std.debug.print(
                            "{s} advertises '{s}' on key '{s}', which is only wired for {s}\n",
                            .{ @tagName(vt), binding.action, binding.key, scope.views[0] },
                        );
                        return error.ViewAdvertisesForeignAction;
                    }
                }
            }
        }
    }
}

test "the unimplemented-action list is not empty" {
    // A list-driven scan is vacuous if the list is emptied, and an empty list would let
    // every dead hint back in silently. Confirmed by mutation: emptying the list makes
    // the scan above pass.
    try std.testing.expect(unimplemented_actions.len > 20);
    try std.testing.expect(view_scoped_actions.len > 0);
}
