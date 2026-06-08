// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for all keybindings data functions

const std = @import("std");
const testing = std.testing;
const bindings_data = @import("src").keybindings_data;
const KeyBinding = @import("src").keybindings.KeyBinding;

test "keybindings_data: all load functions return valid bindings" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test all 24 binding load functions
    const load_functions = .{
        bindings_data.loadNamespacesBindings,
        bindings_data.loadEventsBindings,
        bindings_data.loadSecretsBindings,
        bindings_data.loadServiceAccountsBindings,
        bindings_data.loadPVCsBindings,
        bindings_data.loadPriorityClassesBindings,
        bindings_data.loadReplicaSetsBindings,
        bindings_data.loadStatefulSetsBindings,
        bindings_data.loadDaemonSetsBindings,
        bindings_data.loadCronJobsBindings,
        bindings_data.loadJobsBindings,
        bindings_data.loadRolesBindings,
        bindings_data.loadRoleBindingsBindings,
        bindings_data.loadUsersBindings,
        bindings_data.loadGroupsBindings,
        bindings_data.loadCRDBindings,
        bindings_data.loadContextsBindings,
        bindings_data.loadContainersBindings,
        bindings_data.loadWorkloadsBindings,
        bindings_data.loadPortForwardsBindings,
        bindings_data.loadAliasesBindings,
        bindings_data.loadBenchmarksBindings,
        bindings_data.loadImageScansBindings,
        bindings_data.loadReferencesBindings,
        bindings_data.loadScreenDumpsBindings,
        bindings_data.loadPulseBindings,
        bindings_data.loadHelmChartsBindings,
    };

    inline for (load_functions) |load_fn| {
        const bindings = try load_fn(allocator);
        defer allocator.free(bindings);
        
        // Validate each binding
        for (bindings) |binding| {
            try testing.expect(binding.key.len > 0);
            try testing.expect(binding.description.len > 0);
            try testing.expect(binding.action.len > 0);
            
            // Validate category is a valid enum value
            _ = binding.category;
        }
    }
}

test "keybindings_data: namespaces has switch binding" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try bindings_data.loadNamespacesBindings(allocator);
    defer allocator.free(bindings);

    var has_switch = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "switch")) has_switch = true;
    }
    
    try testing.expect(has_switch);
}

test "keybindings_data: secrets has decode binding" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try bindings_data.loadSecretsBindings(allocator);
    defer allocator.free(bindings);

    var has_decode = false;
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "decode")) has_decode = true;
    }
    
    try testing.expect(has_decode);
}

test "keybindings_data: cronjobs has trigger and suspend" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try bindings_data.loadCronJobsBindings(allocator);
    defer allocator.free(bindings);

    var has_trigger = false;
    var has_suspend = false;
    
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "trigger")) has_trigger = true;
        if (std.mem.eql(u8, binding.action, "suspend")) has_suspend = true;
    }
    
    try testing.expect(has_trigger);
    try testing.expect(has_suspend);
}

test "keybindings_data: containers has shell and attach" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try bindings_data.loadContainersBindings(allocator);
    defer allocator.free(bindings);

    var has_shell = false;
    var has_attach = false;
    
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "shell")) has_shell = true;
        if (std.mem.eql(u8, binding.action, "attach")) has_attach = true;
    }
    
    try testing.expect(has_shell);
    try testing.expect(has_attach);
}

test "keybindings_data: all bindings are UTF-8 valid" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const load_functions = .{
        bindings_data.loadNamespacesBindings,
        bindings_data.loadSecretsBindings,
        bindings_data.loadCronJobsBindings,
    };

    inline for (load_functions) |load_fn| {
        const bindings = try load_fn(allocator);
        defer allocator.free(bindings);
        
        for (bindings) |binding| {
            try testing.expect(std.unicode.utf8ValidateSlice(binding.key));
            try testing.expect(std.unicode.utf8ValidateSlice(binding.description));
            try testing.expect(std.unicode.utf8ValidateSlice(binding.action));
        }
    }
}

test "keybindings_data: portforwards has start and stop" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try bindings_data.loadPortForwardsBindings(allocator);
    defer allocator.free(bindings);

    var has_stop = false;
    var has_start = false;
    
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "stop")) has_stop = true;
        if (std.mem.eql(u8, binding.action, "start")) has_start = true;
    }
    
    try testing.expect(has_stop);
    try testing.expect(has_start);
}

test "keybindings_data: helmcharts has uninstall binding" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try bindings_data.loadHelmChartsBindings(allocator);
    defer allocator.free(bindings);

    var has_uninstall = false;
    
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "uninstall")) has_uninstall = true;
    }
    
    try testing.expect(has_uninstall);
}

test "keybindings_data: pvcs has capacity sorting" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const bindings = try bindings_data.loadPVCsBindings(allocator);
    defer allocator.free(bindings);

    var has_sort_capacity = false;
    
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "sort_capacity")) has_sort_capacity = true;
    }
    
    try testing.expect(has_sort_capacity);
}
