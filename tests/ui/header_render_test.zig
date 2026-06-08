// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Comprehensive tests for header rendering edge cases

const std = @import("std");
const testing = std.testing;
const Header = @import("../../src/ui/header.zig").Header;
const Terminal = @import("../../src/core/terminal.zig").Terminal;
const theme_loader = @import("../../src/model/theme_loader.zig");
const hints_model = @import("../../src/model/hints.zig");

test "header: render with empty hints should not crash" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = theme_loader.defaultTheme();
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    // Create terminal (won't actually write to screen in tests)
    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Empty hints config
    const empty_hints = hints_model.HintConfig{
        .quick_commands = &.{},
        .hints = &.{},
    };

    // Should not crash
    try header.render(&terminal, 0, 0, 120, 5, empty_hints);
}

test "header: render with hints that have empty text fields" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = theme_loader.defaultTheme();
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Hints with empty strings (edge case)
    const hints_with_empty = [_]hints_model.Hint{
        hints_model.Hint.plain("", 1),
        hints_model.Hint.highlighted("", "", "", 2),
    };

    const hints = hints_model.HintConfig{
        .quick_commands = &.{},
        .hints = &hints_with_empty,
    };

    // Should not crash
    try header.render(&terminal, 0, 0, 120, 5, hints);
}

test "header: render with very long hint text" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = theme_loader.defaultTheme();
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Very long hint that should be truncated
    const long_text = "This is a very long hint text that should be truncated to fit within the available space without causing a buffer overflow or segmentation fault";
    const long_hints = [_]hints_model.Hint{
        hints_model.Hint.plain(long_text, 1),
    };

    const hints = hints_model.HintConfig{
        .quick_commands = &.{},
        .hints = &long_hints,
    };

    // Should not crash
    try header.render(&terminal, 0, 0, 80, 5, hints);
}

test "header: render in very narrow terminal" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = theme_loader.defaultTheme();
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    const hints = hints_model.podsHints();

    // Very narrow terminal (should handle gracefully)
    try header.render(&terminal, 0, 0, 20, 5, hints);
    try header.render(&terminal, 0, 0, 10, 5, hints);
    try header.render(&terminal, 0, 0, 5, 5, hints);
}

test "header: render with many hints in narrow terminal" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = theme_loader.defaultTheme();
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Many hints
    const many_hints = [_]hints_model.Hint{
        hints_model.Hint.plain("hint1", 1),
        hints_model.Hint.plain("hint2", 2),
        hints_model.Hint.plain("hint3", 3),
        hints_model.Hint.plain("hint4", 4),
        hints_model.Hint.plain("hint5", 5),
        hints_model.Hint.plain("hint6", 6),
        hints_model.Hint.plain("hint7", 7),
        hints_model.Hint.plain("hint8", 8),
        hints_model.Hint.highlighted("a", "b", "c", 9),
        hints_model.Hint.highlighted("d", "e", "f", 10),
    };

    const hints = hints_model.HintConfig{
        .quick_commands = &.{},
        .hints = &many_hints,
    };

    // Render in narrow terminal - should handle gracefully
    try header.render(&terminal, 0, 0, 60, 5, hints);
}

test "header: compact mode at various widths" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = theme_loader.defaultTheme();
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    const hints = hints_model.podsHints();

    // Toggle compact mode
    header.toggleCompact();

    // Test all compression levels (0-11)
    const widths = [_]u16{ 200, 180, 160, 140, 120, 100, 80, 70, 60, 50, 40, 30 };
    for (widths) |width| {
        try header.render(&terminal, 0, 0, width, 1, hints);
    }
}

test "header: non-compact mode progressive hiding" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = theme_loader.defaultTheme();
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    const hints = hints_model.podsHints();

    // Test progressive hiding at various widths
    const widths = [_]u16{ 200, 150, 120, 100, 80, 60, 40 };
    for (widths) |width| {
        try header.render(&terminal, 0, 0, width, 5, hints);
    }
}

test "header: render with special characters in hints" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = theme_loader.defaultTheme();
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Hints with special characters
    const special_hints = [_]hints_model.Hint{
        hints_model.Hint.plain("<ctrl-d> delete", 1),
        hints_model.Hint.plain("<shift-f> forward", 2),
        hints_model.Hint.highlighted("?", "", " help", 3),
    };

    const hints = hints_model.HintConfig{
        .quick_commands = &.{},
        .hints = &special_hints,
    };

    // Should not crash
    try header.render(&terminal, 0, 0, 120, 5, hints);
}

test "header: all hint rendering modes" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = theme_loader.defaultTheme();
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Mix of plain and highlighted hints
    const mixed_hints = [_]hints_model.Hint{
        hints_model.Hint.plain("plain text", 1),
        hints_model.Hint.highlighted("k", "", "ey", 2),
        hints_model.Hint.highlighted("b", "be", "fore", 3),
        hints_model.Hint.plain("<ctrl-d> delete", 4),
    };

    const hints = hints_model.HintConfig{
        .quick_commands = &.{},
        .hints = &mixed_hints,
    };

    // Should handle both render modes
    try header.render(&terminal, 0, 0, 120, 5, hints);
}

test "header: stress test with maximum hints" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = theme_loader.defaultTheme();
    var header = try Header.init(allocator, &theme, true);
    defer header.cleanup();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Maximum number of hints (stress test)
    const max_hints = [_]hints_model.Hint{
        hints_model.Hint.plain("hint1", 1),
        hints_model.Hint.plain("hint2", 2),
        hints_model.Hint.plain("hint3", 3),
        hints_model.Hint.plain("hint4", 4),
        hints_model.Hint.plain("hint5", 5),
        hints_model.Hint.plain("hint6", 6),
        hints_model.Hint.plain("hint7", 7),
        hints_model.Hint.plain("hint8", 8),
        hints_model.Hint.plain("hint9", 9),
        hints_model.Hint.plain("hint10", 10),
        hints_model.Hint.plain("hint11", 11),
        hints_model.Hint.plain("hint12", 12),
        hints_model.Hint.plain("hint13", 13),
        hints_model.Hint.plain("hint14", 14),
        hints_model.Hint.plain("hint15", 15),
        hints_model.Hint.plain("hint16", 16),
        hints_model.Hint.plain("hint17", 17),
        hints_model.Hint.plain("hint18", 18),
        hints_model.Hint.plain("hint19", 19),
        hints_model.Hint.plain("hint20", 20),
    };

    const max_quick = [_]hints_model.QuickCommand{
        .{ .key = "0", .cmd = "all" },
        .{ .key = "1", .cmd = "default" },
        .{ .key = "2", .cmd = "kube-system" },
        .{ .key = "3", .cmd = "kube-public" },
        .{ .key = "4", .cmd = "custom" },
    };

    const hints = hints_model.HintConfig{
        .quick_commands = &max_quick,
        .hints = &max_hints,
    };

    // Should handle maximum load
    try header.render(&terminal, 0, 0, 200, 5, hints);
}
