const std = @import("std");

/// KeyBinding represents a single key binding with its description
pub const KeyBinding = struct {
    key: []const u8,           // Display name (e.g., "a", "Ctrl-d", "Shift-f")
    description: []const u8,   // What it does
    category: Category,        // Which section it belongs to
    
    pub const Category = enum {
        resource,
        general,
        navigation,
        sorting,
    };
};

/// All k9s-compatible key bindings for pod view
pub const pod_bindings = [_]KeyBinding{
    // RESOURCE COMMANDS (sorted alphabetically like k9s)
    .{ .key = "0", .description = "all", .category = .resource },
    .{ .key = "1", .description = "default", .category = .resource },
    .{ .key = "a", .description = "Attach", .category = .resource },
    .{ .key = "c", .description = "Copy", .category = .resource },
    .{ .key = "Ctrl-d", .description = "Delete", .category = .resource },
    .{ .key = "Ctrl-f", .description = "Kill Finalizers", .category = .resource },
    .{ .key = "Ctrl-k", .description = "Kill", .category = .resource },
    .{ .key = "d", .description = "Describe", .category = .resource },
    .{ .key = "e", .description = "Edit", .category = .resource },
    .{ .key = "f", .description = "Show PortForward", .category = .resource },
    .{ .key = "i", .description = "Set Image", .category = .resource },
    .{ .key = "l", .description = "Logs", .category = .resource },
    .{ .key = "n", .description = "Copy Namespace", .category = .resource },
    .{ .key = "o", .description = "Show Node", .category = .resource },
    .{ .key = "p", .description = "Logs Previous", .category = .resource },
    .{ .key = "Shift-f", .description = "Port-Forward", .category = .resource },
    .{ .key = "Shift-j", .description = "Jump Owner", .category = .resource },
    .{ .key = "Shift-r", .description = "Refresh", .category = .resource },
    .{ .key = "s", .description = "Shell", .category = .resource },
    .{ .key = "t", .description = "Transfer", .category = .resource },
    .{ .key = "v", .description = "View", .category = .resource },
    .{ .key = "y", .description = "YAML", .category = .resource },
    .{ .key = "z", .description = "Sanitize", .category = .resource },
    
    // GENERAL COMMANDS
    .{ .key = "?", .description = "Help", .category = .general },
    .{ .key = "Ctrl-a", .description = "Aliases", .category = .general },
    .{ .key = ":cmd", .description = "Command mode", .category = .general },
    .{ .key = "/term", .description = "Filter mode", .category = .general },
    .{ .key = "esc", .description = "Back/Clear", .category = .general },
    .{ .key = "tab", .description = "Field Next", .category = .general },
    .{ .key = "backtab", .description = "Field Previous", .category = .general },
    .{ .key = "Ctrl-r", .description = "Reload", .category = .general },
    .{ .key = "Ctrl-u", .description = "Command Clear", .category = .general },
    .{ .key = "Ctrl-e", .description = "Toggle Header", .category = .general },
    .{ .key = "Ctrl-g", .description = "Toggle Crumbs", .category = .general },
    .{ .key = ":q", .description = "Quit", .category = .general },
    .{ .key = "space", .description = "Mark", .category = .general },
    .{ .key = "Ctrl-space", .description = "Mark Range", .category = .general },
    .{ .key = "Ctrl-\\", .description = "Mark Clear", .category = .general },
    .{ .key = "Ctrl-s", .description = "Save", .category = .general },
    
    // NAVIGATION COMMANDS  
    .{ .key = "-", .description = "Last Command", .category = .navigation },
    .{ .key = "0", .description = "Down", .category = .navigation },
    .{ .key = "[", .description = "History Back", .category = .navigation },
    .{ .key = "]", .description = "History Forward", .category = .navigation },
    .{ .key = "Ctrl-b", .description = "Page Up", .category = .navigation },
    .{ .key = "Ctrl-f", .description = "Page Down", .category = .navigation },
    .{ .key = "g", .description = "Goto Top", .category = .navigation },
    .{ .key = "Shift-g", .description = "Goto Bottom", .category = .navigation },
    .{ .key = "h", .description = "Left", .category = .navigation },
    .{ .key = "j", .description = "Down", .category = .navigation },
    .{ .key = "k", .description = "Up", .category = .navigation },
    .{ .key = "l", .description = "Right", .category = .navigation },
    
    // SORTING COMMANDS
    .{ .key = "Shift-a", .description = "Age", .category = .sorting },
    .{ .key = "Shift-c", .description = "CPU", .category = .sorting },
    .{ .key = "Shift-m", .description = "MEM", .category = .sorting },
    .{ .key = "Shift-n", .description = "Name", .category = .sorting },
    .{ .key = "Shift-p", .description = "Namespace", .category = .sorting },
    .{ .key = "Shift-i", .description = "IP", .category = .sorting },
    .{ .key = "Shift-o", .description = "Node", .category = .sorting },
    .{ .key = "Shift-r", .description = "Ready", .category = .sorting },
    .{ .key = "Shift-s", .description = "Status", .category = .sorting },
    .{ .key = "Shift-t", .description = "Restart", .category = .sorting },
};

/// Get bindings for a specific category
pub fn getBindingsForCategory(category: KeyBinding.Category) []const KeyBinding {
    var result: [pod_bindings.len]KeyBinding = undefined;
    var count: usize = 0;
    
    for (pod_bindings) |binding| {
        if (binding.category == category) {
            result[count] = binding;
            count += 1;
        }
    }
    
    return result[0..count];
}

/// Format help text for display in columns
pub fn formatHelpLine(allocator: std.mem.Allocator, key: []const u8, description: []const u8) ![]const u8 {
    // Format: "  key       description" with proper padding
    const key_width = 10;
    const padding = if (key.len < key_width) key_width - key.len else 0;
    
    return try std.fmt.allocPrint(allocator, "  {s}{s}{s}", .{
        key,
        " " ** padding,
        description,
    });
}

/// Calculate max width for key and description in a category
fn calculateMaxWidths(bindings: []const KeyBinding) struct { key: usize, desc: usize } {
    var max_key: usize = 0;
    var max_desc: usize = 0;
    for (bindings) |binding| {
        if (binding.key.len > max_key) max_key = binding.key.len;
        if (binding.description.len > max_desc) max_desc = binding.description.len;
    }
    return .{ .key = max_key + 2, .desc = max_desc };  // +2 padding for key like k9s
}

/// Generate help content dynamically from key bindings
pub fn generateHelpContent(allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var lines = try std.ArrayList([]const u8).initCapacity(allocator, 50);
    
    try lines.append(allocator, try allocator.dupe(u8, "C3S - Kubernetes TUI Client (k9s-compatible)"));
    try lines.append(allocator, try allocator.dupe(u8, ""));
    
    // Filter bindings by category at runtime
    var resource_list = try std.ArrayList(KeyBinding).initCapacity(allocator, 25);
    defer resource_list.deinit(allocator);
    var general_list = try std.ArrayList(KeyBinding).initCapacity(allocator, 20);
    defer general_list.deinit(allocator);
    var navigation_list = try std.ArrayList(KeyBinding).initCapacity(allocator, 15);
    defer navigation_list.deinit(allocator);
    var sorting_list = try std.ArrayList(KeyBinding).initCapacity(allocator, 15);
    defer sorting_list.deinit(allocator);
    
    for (pod_bindings) |binding| {
        switch (binding.category) {
            .resource => try resource_list.append(allocator, binding),
            .general => try general_list.append(allocator, binding),
            .navigation => try navigation_list.append(allocator, binding),
            .sorting => try sorting_list.append(allocator, binding),
        }
    }
    
    const resource_bindings = resource_list.items;
    const general_bindings = general_list.items;
    const navigation_bindings = navigation_list.items;
    const sorting_bindings = sorting_list.items;
    
    // Calculate column widths dynamically (like k9s)
    const res_widths = calculateMaxWidths(resource_bindings);
    const gen_widths = calculateMaxWidths(general_bindings);
    const nav_widths = calculateMaxWidths(navigation_bindings);
    
    // Column widths (key + description + padding)
    const col1_width = res_widths.key + res_widths.desc + 2;
    const col2_width = gen_widths.key + gen_widths.desc + 2;
    
    // Build header with runtime padding
    var header_buf = try std.ArrayList(u8).initCapacity(allocator, 100);
    defer header_buf.deinit(allocator);
    try header_buf.appendSlice(allocator, "RESOURCE");
    try header_buf.appendNTimes(allocator, ' ', col1_width - 8);  // "RESOURCE" = 8 chars
    try header_buf.appendSlice(allocator, "GENERAL");
    try header_buf.appendNTimes(allocator, ' ', col2_width - 7);  // "GENERAL" = 7 chars
    try header_buf.appendSlice(allocator, "NAVIGATION");
    try lines.append(allocator, try allocator.dupe(u8, header_buf.items));
    
    // Find max rows needed
    const max_rows = @max(
        @max(resource_bindings.len, general_bindings.len),
        navigation_bindings.len,
    );
    
    // Build data rows
    for (0..max_rows) |i| {
        var line_parts = try std.ArrayList(u8).initCapacity(allocator, 150);
        defer line_parts.deinit(allocator);
        
        // Resource column
        if (i < resource_bindings.len) {
            const binding = resource_bindings[i];
            try line_parts.appendSlice(allocator, "  <");
            try line_parts.appendSlice(allocator, binding.key);
            try line_parts.appendSlice(allocator, ">");
            const key_padding = res_widths.key - binding.key.len - 2;
            if (key_padding > 0) {
                try line_parts.appendNTimes(allocator, ' ', key_padding);
            }
            try line_parts.appendSlice(allocator, binding.description);
            const desc_padding = res_widths.desc - binding.description.len + 2;
            if (desc_padding > 0) {
                try line_parts.appendNTimes(allocator, ' ', desc_padding);
            }
        } else {
            try line_parts.appendNTimes(allocator, ' ', col1_width);
        }
        
        // General column
        if (i < general_bindings.len) {
            const binding = general_bindings[i];
            try line_parts.appendSlice(allocator, "  <");
            try line_parts.appendSlice(allocator, binding.key);
            try line_parts.appendSlice(allocator, ">");
            const key_padding = gen_widths.key - binding.key.len - 2;
            if (key_padding > 0) {
                try line_parts.appendNTimes(allocator, ' ', key_padding);
            }
            try line_parts.appendSlice(allocator, binding.description);
            const desc_padding = gen_widths.desc - binding.description.len + 2;
            if (desc_padding > 0) {
                try line_parts.appendNTimes(allocator, ' ', desc_padding);
            }
        } else {
            try line_parts.appendNTimes(allocator, ' ', col2_width);
        }
        
        // Navigation column
        if (i < navigation_bindings.len) {
            const binding = navigation_bindings[i];
            try line_parts.appendSlice(allocator, "  <");
            try line_parts.appendSlice(allocator, binding.key);
            try line_parts.appendSlice(allocator, ">");
            const key_padding = nav_widths.key - binding.key.len - 2;
            if (key_padding > 0) {
                try line_parts.appendNTimes(allocator, ' ', key_padding);
            }
            try line_parts.appendSlice(allocator, binding.description);
        }
        
        try lines.append(allocator, try allocator.dupe(u8, line_parts.items));
    }
    
    // Add sorting section
    if (sorting_bindings.len > 0) {
        try lines.append(allocator, try allocator.dupe(u8, ""));
        try lines.append(allocator, try allocator.dupe(u8, "SORTING"));
        const sort_widths = calculateMaxWidths(sorting_bindings);
        for (sorting_bindings) |binding| {
            var sort_line = try std.ArrayList(u8).initCapacity(allocator, 50);
            defer sort_line.deinit(allocator);
            try sort_line.appendSlice(allocator, "  <");
            try sort_line.appendSlice(allocator, binding.key);
            try sort_line.appendSlice(allocator, ">");
            const key_padding = sort_widths.key - binding.key.len - 2;
            if (key_padding > 0) {
                try sort_line.appendNTimes(allocator, ' ', key_padding);
            }
            try sort_line.appendSlice(allocator, binding.description);
            try lines.append(allocator, try allocator.dupe(u8, sort_line.items));
        }
    }
    
    try lines.append(allocator, try allocator.dupe(u8, ""));
    try lines.append(allocator, try allocator.dupe(u8, "Press ? or Esc to close help"));
    
    return lines;
}
