const std = @import("std");

/// KeyBinding represents a single key binding with its description
pub const KeyBinding = struct {
    key: []const u8,           // Display name (e.g., "a", "Ctrl-d", "Shift-f")
    description: []const u8,   // What it does
    category: Category,        // Which section it belongs to
    action: []const u8,        // Action identifier for handler lookup
    
    pub const Category = enum {
        resource,
        general,
        navigation,
        sorting,
    };
};

/// KeyBindingsConfig holds all key bindings for a view
pub const KeyBindingsConfig = struct {
    bindings: []const KeyBinding,
    allocator: std.mem.Allocator,
    
    pub fn deinit(self: *KeyBindingsConfig) void {
        // Free allocated bindings if needed
        _ = self;
    }
};


/// Calculate max width for key and description in a category
fn calculateMaxWidths(bindings: []const KeyBinding) struct { key: usize, desc: usize } {
    var max_key: usize = 0;
    var max_desc: usize = 0;
    for (bindings) |binding| {
        if (binding.key.len > max_key) max_key = binding.key.len;
        if (binding.description.len > max_desc) max_desc = binding.description.len;
    }
    return .{ .key = max_key + 2, .desc = max_desc };  // +2 padding for key column
}

/// Generate help content dynamically from key bindings
pub fn generateHelpContent(allocator: std.mem.Allocator, bindings: []const KeyBinding) !std.ArrayListUnmanaged([]const u8) {
    var lines = std.ArrayListUnmanaged([]const u8){};
    try lines.ensureTotalCapacity(allocator, 50);
    
    try lines.append(allocator, try allocator.dupe(u8, "C3S - Kubernetes TUI Client"));
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
    
    for (bindings) |binding| {
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
    
    // Calculate column widths dynamically
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
            const key_padding = res_widths.key - binding.key.len;
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
            const key_padding = gen_widths.key - binding.key.len;
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
            const key_padding = nav_widths.key - binding.key.len;
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
            const key_padding = sort_widths.key - binding.key.len;
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

/// Free help content lines
pub fn freeHelpContent(allocator: std.mem.Allocator, lines: *std.ArrayListUnmanaged([]const u8)) void {
    for (lines.items) |line| {
        allocator.free(line);
    }
    lines.deinit(allocator);
}
