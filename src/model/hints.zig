// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Andrey Maltsev

const std = @import("std");

/// Hint render type
pub const HintRenderType = enum(u8) {
    plain = 0, // Plain text: "<ctrl-k> kill"
    highlighted = 1, // Highlighted: a + "ttach" -> "attach" with 'a' highlighted
};

/// Individual hint item
pub const Hint = struct {
    render_fn: HintRenderType,
    text: []const u8, // For plain text hints
    key: []const u8, // For highlighted hints
    before: []const u8, // For highlighted hints
    after: []const u8, // For highlighted hints
    priority: u8 = 100, // Lower = higher priority (0-255)

    pub fn plain(text: []const u8, priority: u8) Hint {
        return .{
            .render_fn = .plain,
            .text = text,
            .key = "",
            .before = "",
            .after = "",
            .priority = priority,
        };
    }

    pub fn highlighted(key: []const u8, before: []const u8, after: []const u8, priority: u8) Hint {
        return .{
            .render_fn = .highlighted,
            .text = "",
            .key = key,
            .before = before,
            .after = after,
            .priority = priority,
        };
    }
};

/// Quick command (namespace shortcut)
pub const QuickCommand = struct {
    key: []const u8,
    cmd: []const u8,
};

/// Hints configuration for a view
pub const HintConfig = struct {
    quick_commands: []const QuickCommand = &.{},
    hints: []const Hint = &.{},
};

/// Pods view hints (default)
pub fn podsHints() HintConfig {
    const quick_cmds = comptime [_]QuickCommand{
        .{ .key = "0", .cmd = "all" },
        .{ .key = "1", .cmd = "default" },
    };

    const hint_items = comptime [_]Hint{
        Hint.highlighted("a", "", "ttach", 1), // Priority 1: Most important
        Hint.plain("<ctrl-k> kill", 7), // Priority 7: Dangerous
        Hint.plain("<ctrl-d> delete", 8), // Priority 8: Dangerous
        Hint.highlighted("s", "", "hell", 2), // Priority 2: Very important
        Hint.highlighted("d", "", "escribe", 4), // Priority 4: Important
        Hint.highlighted("e", "", "dit", 5), // Priority 5: Important
        Hint.highlighted("o", "sh", "w node", 12), // Priority 12: Less important
        Hint.highlighted("?", "", " help", 20), // Priority 20: Always accessible via ?
        Hint.highlighted("l", "", "ogs", 3), // Priority 3: Very important
        Hint.plain("<shift-f> port-forward", 10), // Priority 10: Specialized
        Hint.plain("<ctrl-f> kill finalizers", 11), // Priority 11: Specialized
        Hint.highlighted("p", "logs ", "revious", 9), // Priority 9: Secondary
        Hint.highlighted("t", "", "ransfer", 13), // Priority 13: Less common
        Hint.highlighted("z", "saniti", "e", 14), // Priority 14: Less common
        Hint.highlighted("i", "set ", "mage", 15), // Priority 15: Less common
        Hint.highlighted("y", "", " yaml", 6), // Priority 6: Important
    };

    return .{
        .quick_commands = &quick_cmds,
        .hints = &hint_items,
    };
}

/// Themes view hints
pub fn themesHints() HintConfig {
    const hint_items = comptime [_]Hint{
        Hint.highlighted("/", "", " filter", 1), // Priority 1: Most important
        Hint.highlighted("Enter", "", " select", 2), // Priority 2: Very important
        Hint.highlighted("Esc", "", " back", 3), // Priority 3: Important
        Hint.highlighted("g", "", " top", 4), // Priority 4: Navigation
        Hint.highlighted("G", "shift-", " bottom", 5), // Priority 5: Navigation
        Hint.highlighted("?", "", " help", 20), // Priority 20: Always accessible
    };

    return .{
        .quick_commands = &.{},
        .hints = &hint_items,
    };
}

/// Help view hints (minimal - just navigation)
pub fn helpHints() HintConfig {
    const hint_items = comptime [_]Hint{
        Hint.highlighted("Esc", "", " back", 1), // Priority 1: Most important
        Hint.highlighted("g", "", " top", 2), // Priority 2: Navigation
        Hint.highlighted("G", "shift-", " bottom", 3), // Priority 3: Navigation
        Hint.highlighted("j/k", "", " down/up", 4), // Priority 4: Navigation
        Hint.highlighted("h/l", "", " left/right", 5), // Priority 5: Navigation
    };

    return .{
        .quick_commands = &.{},
        .hints = &hint_items,
    };
}

/// Detail view hints (describe/yaml)
pub fn detailHints() HintConfig {
    const hint_items = comptime [_]Hint{
        Hint.highlighted("Esc", "", " back", 1),
        Hint.highlighted("j/k", "", " down/up", 2),
        Hint.highlighted("h/l", "", " left/right", 3),
        Hint.highlighted("g", "", " top", 4),
        Hint.highlighted("G", "shift-", " bottom", 5),
        Hint.highlighted("Spc", "", " fold", 6),
        Hint.highlighted("c", "", " fold all", 7),
        Hint.highlighted("o", "", " unfold all", 8),
    };

    return .{
        .quick_commands = &.{},
        .hints = &hint_items,
    };
}

/// Logs view hints
pub fn logsHints() HintConfig {
    const hint_items = comptime [_]Hint{
        Hint.highlighted("Esc", "", " back", 1),
        Hint.highlighted("j/k", "", " down/up", 2),
        Hint.highlighted("g", "", " top", 3),
        Hint.highlighted("G", "shift-", " bottom", 4),
    };

    return .{
        .quick_commands = &.{},
        .hints = &hint_items,
    };
}

/// Resource view hints (common for all resource views with d/y/delete support)
pub fn resourceHints() HintConfig {
    const hint_items = comptime [_]Hint{
        Hint.highlighted("d", "", "escribe", 1),
        Hint.highlighted("y", "", " yaml", 2),
        Hint.highlighted("/", "", " filter", 3),
        Hint.highlighted("r", "", "efresh", 4),
        Hint.plain("<ctrl-d> delete", 5),
        Hint.highlighted("?", "", " help", 20),
    };

    return .{
        .quick_commands = &.{},
        .hints = &hint_items,
    };
}

/// Common hints (for future use - can be merged with view-specific hints)
pub fn commonHints() HintConfig {
    const hint_items = [_]Hint{
        Hint.highlighted("?", "", " help", 1),
        Hint.highlighted(":", "", " command", 2),
        Hint.highlighted("/", "", " filter", 3),
        Hint.highlighted("Esc", "", " back", 4),
        Hint.plain("<ctrl-r> refresh", 5),
    };

    return .{
        .quick_commands = &.{},
        .hints = &hint_items,
    };
}

const testing = std.testing;

test "hints: pods hints are valid and accessible" {
    const hints = podsHints();

    // Ensure we have hints
    try testing.expect(hints.hints.len > 0);
    try testing.expect(hints.quick_commands.len > 0);

    // Ensure we can access each hint without crash
    for (hints.hints) |hint| {
        // Access all fields to ensure no dangling pointers
        _ = hint.render_fn;
        _ = hint.text;
        _ = hint.key;
        _ = hint.before;
        _ = hint.after;
        _ = hint.priority;

        // Validate enum
        const render_type = @intFromEnum(hint.render_fn);
        try testing.expect(render_type == 0 or render_type == 1);
    }

    // Ensure we can access quick commands
    for (hints.quick_commands) |cmd| {
        try testing.expect(cmd.key.len > 0);
        try testing.expect(cmd.cmd.len > 0);
    }
}

test "hints: themes hints are valid and accessible" {
    const hints = themesHints();

    try testing.expect(hints.hints.len > 0);

    for (hints.hints) |hint| {
        _ = hint.render_fn;
        const render_type = @intFromEnum(hint.render_fn);
        try testing.expect(render_type == 0 or render_type == 1);
    }
}

test "hints: help hints are valid and accessible" {
    const hints = helpHints();

    try testing.expect(hints.hints.len > 0);

    for (hints.hints) |hint| {
        _ = hint.render_fn;
        const render_type = @intFromEnum(hint.render_fn);
        try testing.expect(render_type == 0 or render_type == 1);
    }
}

test "hints: can call hint functions multiple times without corruption" {
    // Call each function multiple times to ensure no state corruption
    _ = podsHints();
    _ = podsHints();
    _ = themesHints();
    _ = themesHints();
    _ = helpHints();
    _ = helpHints();

    // All should return the same valid data
    const hints1 = podsHints();
    const hints2 = podsHints();

    try testing.expectEqual(hints1.hints.len, hints2.hints.len);
    try testing.expectEqual(hints1.quick_commands.len, hints2.quick_commands.len);
}

test "hints: plain hints have text, highlighted hints have empty text" {
    const hints = podsHints();

    for (hints.hints) |hint| {
        switch (hint.render_fn) {
            .plain => {
                // Plain hints should have non-empty text
                try testing.expect(hint.text.len > 0);
            },
            .highlighted => {
                // Highlighted hints should have empty text
                try testing.expectEqual(@as(usize, 0), hint.text.len);
                // But should have key
                try testing.expect(hint.key.len > 0);
            },
        }
    }
}

test "hints: all hint strings are valid UTF-8" {
    const hints = podsHints();

    for (hints.hints) |hint| {
        // Validate UTF-8 for all string fields
        try testing.expect(std.unicode.utf8ValidateSlice(hint.text));
        try testing.expect(std.unicode.utf8ValidateSlice(hint.key));
        try testing.expect(std.unicode.utf8ValidateSlice(hint.before));
        try testing.expect(std.unicode.utf8ValidateSlice(hint.after));
    }

    for (hints.quick_commands) |cmd| {
        try testing.expect(std.unicode.utf8ValidateSlice(cmd.key));
        try testing.expect(std.unicode.utf8ValidateSlice(cmd.cmd));
    }
}

test "hints: priorities are within valid range" {
    const hints = podsHints();

    for (hints.hints) |hint| {
        // Priority should be 0-255 (it's a u8, so this is always true, but documenting intent)
        try testing.expect(hint.priority >= 0 and hint.priority <= 255);
    }
}

test "hints: highlighted hints have valid components" {
    const hints = podsHints();

    for (hints.hints) |hint| {
        if (hint.render_fn == .highlighted) {
            // At least key should be non-empty for highlighted
            try testing.expect(hint.key.len > 0);

            // Total length should be reasonable
            const total = hint.before.len + hint.key.len + hint.after.len;
            try testing.expect(total > 0);
            try testing.expect(total < 100); // Sanity check
        }
    }
}
