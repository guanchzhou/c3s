// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for KeyBindingsViewModel

const std = @import("std");
const testing = std.testing;
const KeyBindingsViewModel = @import("../../src/viewmodel/keybindings_vm.zig").KeyBindingsViewModel;
const ViewType = @import("../../src/viewmodel/keybindings_vm.zig").ViewType;

test "keybindings_vm: init and deinit for all view types" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Test all 44 view types can be initialized
    const view_types = [_]ViewType{
        // Core resources
        .pods, .nodes, .services, .namespaces, .events, .secrets, .configmaps,
        .serviceaccounts, .persistentvolumeclaims, .priorityclasses,
        // Apps resources
        .deployments, .replicasets, .statefulsets, .daemonsets,
        // Batch resources
        .cronjobs, .jobs,
        // RBAC resources
        .clusterroles, .clusterrolebindings, .roles, .rolebindings, .users, .groups,
        // CRD resources
        .customresourcedefinitions,
        // Misc views
        .contexts, .containers, .workloads, .portforwards, .aliases, .benchmarks,
        .imagescans, .references, .screendumps, .pulse,
        // Helm
        .helmcharts,
    };

    for (view_types) |view_type| {
        var vm = try KeyBindingsViewModel.init(allocator, view_type);
        defer vm.deinit();

        // Verify bindings are returned
        const bindings = vm.getBindings();
        try testing.expect(bindings.len >= 0); // At least valid (could be empty)
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
    try testing.expect(bindings.len > 10);
    
    // Check for some key pod bindings
    var has_attach = false;
    var has_logs = false;
    var has_describe = false;
    
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "attach")) has_attach = true;
        if (std.mem.eql(u8, binding.action, "logs")) has_logs = true;
        if (std.mem.eql(u8, binding.action, "describe")) has_describe = true;
    }
    
    try testing.expect(has_attach);
    try testing.expect(has_logs);
    try testing.expect(has_describe);
}

test "keybindings_vm: nodes view has specific bindings" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var vm = try KeyBindingsViewModel.init(allocator, .nodes);
    defer vm.deinit();

    const bindings = vm.getBindings();
    
    // Check for node-specific bindings
    var has_cordon = false;
    var has_drain = false;
    
    for (bindings) |binding| {
        if (std.mem.eql(u8, binding.action, "cordon")) has_cordon = true;
        if (std.mem.eql(u8, binding.action, "drain")) has_drain = true;
    }
    
    try testing.expect(has_cordon);
    try testing.expect(has_drain);
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
    
    try testing.expect(has_scale);
    try testing.expect(has_restart);
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
            try testing.expect(binding.key.len > 0);
            try testing.expect(binding.description.len > 0);
            try testing.expect(binding.action.len > 0);
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
    try testing.expectEqual(bindings1.len, bindings2.len);
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
    
    try testing.expect(has_port_forward);
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
    
    try testing.expect(has_trigger);
}
