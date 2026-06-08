// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for theme rendering functions

const std = @import("std");
const testing = std.testing;
const Theme = @import("../src/model/theme_loader.zig");
const Terminal = @import("../src/core/terminal.zig").Terminal;

// Test color constants
const test_fg = "\x1b[38;2;207;201;194m";
const test_bg = "\x1b[49m";
const test_hi = "\x1b[38;2;247;118;142m";

test "theme: writeStringWithTheme with empty text" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Should not crash with empty text
    try Theme.writeStringWithTheme(&terminal, 0, 0, "", test_fg, test_bg);
}

test "theme: writeStringWithTheme with very long text" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Create very long text that would exceed buffer
    var long_text: [2048]u8 = undefined;
    @memset(&long_text, 'A');

    // Should truncate and not crash
    try Theme.writeStringWithTheme(&terminal, 0, 0, &long_text, test_fg, test_bg);
}

test "theme: writeStringWithTheme with normal text" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Should work fine with normal text
    try Theme.writeStringWithTheme(&terminal, 0, 0, "Hello, World!", test_fg, test_bg);
}

test "theme: writeStringWithTheme with special characters" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Should handle special characters
    try Theme.writeStringWithTheme(&terminal, 0, 0, "<ctrl-d>", test_fg, test_bg);
    try Theme.writeStringWithTheme(&terminal, 0, 0, "│─┤", test_fg, test_bg);
}

test "theme: writeShortcutWithHighlight with empty strings" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Should not crash with empty strings
    try Theme.writeShortcutWithHighlight(&terminal, 0, 0, "", "", "", test_hi);
}

test "theme: writeShortcutWithHighlight with normal text" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Should work fine with normal text
    try Theme.writeShortcutWithHighlight(&terminal, 0, 0, "", "a", "ttach", test_hi);
    try Theme.writeShortcutWithHighlight(&terminal, 0, 0, "sh", "o", "w node", test_hi);
}

test "theme: buffer size limits" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test with text that approaches buffer limit
    var medium_text: [500]u8 = undefined;
    @memset(&medium_text, 'B');

    try Theme.writeStringWithTheme(&terminal, 0, 0, &medium_text, test_fg, test_bg);

    // Test with text that exceeds buffer limit
    var huge_text: [5000]u8 = undefined;
    @memset(&huge_text, 'C');

    try Theme.writeStringWithTheme(&terminal, 0, 0, &huge_text, test_fg, test_bg);
}
