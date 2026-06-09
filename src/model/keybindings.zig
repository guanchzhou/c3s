const std = @import("std");

/// KeyBinding represents a single key binding with its description
pub const KeyBinding = struct {
    key: []const u8, // Display name (e.g., "a", "Ctrl-d", "Shift-f")
    description: []const u8, // What it does
    category: Category, // Which section it belongs to
    action: []const u8, // Action identifier for handler lookup

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
    return .{ .key = max_key + 2, .desc = max_desc }; // +2 padding for key column
}

/// Generate help content dynamically from key bindings
pub fn generateHelpContent(allocator: std.mem.Allocator, bindings: []const KeyBinding) !std.ArrayListUnmanaged([]const u8) {
    var lines = std.ArrayListUnmanaged([]const u8).empty;
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
    try header_buf.appendNTimes(allocator, ' ', col1_width -| 8); // "RESOURCE" = 8 chars; saturating: col may be < 8 when the category is empty
    try header_buf.appendSlice(allocator, "GENERAL");
    try header_buf.appendNTimes(allocator, ' ', col2_width -| 7); // "GENERAL" = 7 chars; saturating
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

const testing = std.testing;

test "keybindings: generateHelpContent with normal bindings" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const test_bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Attach", .category = .resource, .action = "attach" },
        .{ .key = "d", .description = "Describe", .category = .resource, .action = "describe" },
        .{ .key = "?", .description = "Help", .category = .general, .action = "help" },
        .{ .key = "j", .description = "Down", .category = .navigation, .action = "down" },
        .{ .key = "Shift-a", .description = "Age", .category = .sorting, .action = "sort_age" },
    };

    var lines = try generateHelpContent(allocator, &test_bindings);
    defer {
        for (lines.items) |line| {
            allocator.free(line);
        }
        lines.deinit(allocator);
    }

    // Should have title, empty line, headers, data rows, and footer
    try testing.expect(lines.items.len >= 5);

    // First line should be title
    try testing.expect(std.mem.indexOf(u8, lines.items[0], "C3S") != null);
}

test "keybindings: generateHelpContent with empty bindings" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const empty_bindings = [_]KeyBinding{};

    var lines = try generateHelpContent(allocator, &empty_bindings);
    defer {
        for (lines.items) |line| {
            allocator.free(line);
        }
        lines.deinit(allocator);
    }

    // Should still have title and footer
    try testing.expect(lines.items.len >= 3);
}

test "keybindings: generateHelpContent with very long keys" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const long_bindings = [_]KeyBinding{
        .{ .key = "Ctrl-Shift-Alt-Meta-Super-Hyper-X", .description = "Very complex command", .category = .resource, .action = "complex" },
    };

    var lines = try generateHelpContent(allocator, &long_bindings);
    defer {
        for (lines.items) |line| {
            allocator.free(line);
        }
        lines.deinit(allocator);
    }

    // Should handle long keys gracefully
    try testing.expect(lines.items.len > 0);
}

test "keybindings: calculateMaxWidths with various lengths" {
    const bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Short", .category = .resource, .action = "test" },
        .{ .key = "Ctrl-d", .description = "A very long description that should affect width", .category = .resource, .action = "test" },
    };

    // This is an internal function, but we can verify the help content accommodates it
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var lines = try generateHelpContent(allocator, &bindings);
    defer {
        for (lines.items) |line| {
            allocator.free(line);
        }
        lines.deinit(allocator);
    }

    try testing.expect(lines.items.len > 0);
}

test "keybindings: all categories are handled" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const all_category_bindings = [_]KeyBinding{
        .{ .key = "a", .description = "Resource", .category = .resource, .action = "test" },
        .{ .key = "b", .description = "General", .category = .general, .action = "test" },
        .{ .key = "c", .description = "Navigation", .category = .navigation, .action = "test" },
        .{ .key = "d", .description = "Sorting", .category = .sorting, .action = "test" },
    };

    var lines = try generateHelpContent(allocator, &all_category_bindings);
    defer {
        for (lines.items) |line| {
            allocator.free(line);
        }
        lines.deinit(allocator);
    }

    // Should have all sections
    var has_resource = false;
    var has_general = false;
    var has_navigation = false;
    var has_sorting = false;

    for (lines.items) |line| {
        if (std.mem.indexOf(u8, line, "RESOURCE") != null) has_resource = true;
        if (std.mem.indexOf(u8, line, "GENERAL") != null) has_general = true;
        if (std.mem.indexOf(u8, line, "NAVIGATION") != null) has_navigation = true;
        if (std.mem.indexOf(u8, line, "SORTING") != null) has_sorting = true;
    }

    try testing.expect(has_resource);
    try testing.expect(has_general);
    try testing.expect(has_navigation);
    try testing.expect(has_sorting);
}
