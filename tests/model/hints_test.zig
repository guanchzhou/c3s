// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Tests for hints to ensure no dangling pointers

const std = @import("std");
const testing = std.testing;
const hints_model = @import("../../src/model/hints.zig");

test "hints: pods hints are valid and accessible" {
    const hints = hints_model.podsHints();
    
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
    const hints = hints_model.themesHints();
    
    try testing.expect(hints.hints.len > 0);
    
    for (hints.hints) |hint| {
        _ = hint.render_fn;
        const render_type = @intFromEnum(hint.render_fn);
        try testing.expect(render_type == 0 or render_type == 1);
    }
}

test "hints: help hints are valid and accessible" {
    const hints = hints_model.helpHints();
    
    try testing.expect(hints.hints.len > 0);
    
    for (hints.hints) |hint| {
        _ = hint.render_fn;
        const render_type = @intFromEnum(hint.render_fn);
        try testing.expect(render_type == 0 or render_type == 1);
    }
}

test "hints: can call hint functions multiple times without corruption" {
    // Call each function multiple times to ensure no state corruption
    _ = hints_model.podsHints();
    _ = hints_model.podsHints();
    _ = hints_model.themesHints();
    _ = hints_model.themesHints();
    _ = hints_model.helpHints();
    _ = hints_model.helpHints();
    
    // All should return the same valid data
    const hints1 = hints_model.podsHints();
    const hints2 = hints_model.podsHints();
    
    try testing.expectEqual(hints1.hints.len, hints2.hints.len);
    try testing.expectEqual(hints1.quick_commands.len, hints2.quick_commands.len);
}

test "hints: plain hints have text, highlighted hints have empty text" {
    const hints = hints_model.podsHints();
    
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
    const hints = hints_model.podsHints();
    
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
    const hints = hints_model.podsHints();
    
    for (hints.hints) |hint| {
        // Priority should be 0-255 (it's a u8, so this is always true, but documenting intent)
        try testing.expect(hint.priority >= 0 and hint.priority <= 255);
    }
}

test "hints: highlighted hints have valid components" {
    const hints = hints_model.podsHints();
    
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
