//! Make cluster-supplied text safe to write to the terminal.
//!
//! Log lines, describe output and table cells come from the API server and are
//! ultimately controlled by whoever can write a pod's stdout or an object's
//! fields. Written raw, an ESC or a C1 control lets that text drive the
//! terminal: OSC 52 rewrites the clipboard, CSI moves the cursor over the UI,
//! and some terminals answer queries back on stdin. Everything is cleaned once,
//! where it enters c3s, so no render path has to remember to.
const std = @import("std");

pub const replacement: u8 = '?';
pub const tab_width: usize = 8;

/// True when `text` contains anything `sanitizeAlloc` would change.
pub fn needsSanitizing(text: []const u8) bool {
    var i: usize = 0;
    while (i < text.len) {
        const step = classify(text, i);
        if (step.kind != .keep) return true;
        i += step.len;
    }
    return false;
}

/// Copy `text`, replacing C0 controls, DEL, C1 controls and invalid UTF-8 bytes
/// with '?'. Tabs expand to spaces up to the next tab stop. Caller owns the result.
pub fn sanitizeAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.ensureTotalCapacity(allocator, text.len);

    var column: usize = 0;
    var i: usize = 0;
    while (i < text.len) {
        const step = classify(text, i);
        switch (step.kind) {
            .keep => try out.appendSlice(allocator, text[i .. i + step.len]),
            .tab => {
                const spaces = tab_width - (column % tab_width);
                try out.appendNTimes(allocator, ' ', spaces);
                column += spaces;
                i += step.len;
                continue;
            },
            .replace => try out.append(allocator, replacement),
        }
        column += 1;
        i += step.len;
    }
    return out.toOwnedSlice(allocator);
}

/// Sanitize an allocation in place of the original: returns `owned` untouched when
/// it is already clean, otherwise frees it and returns a cleaned copy.
pub fn sanitizeOwned(allocator: std.mem.Allocator, owned: []u8) ![]u8 {
    if (!needsSanitizing(owned)) return owned;
    const clean = try sanitizeAlloc(allocator, owned);
    allocator.free(owned);
    return clean;
}

/// Longest prefix of `text` that is at most `max_bytes` long and does not end
/// inside a multi-byte UTF-8 sequence.
pub fn utf8Prefix(text: []const u8, max_bytes: usize) []const u8 {
    if (text.len <= max_bytes) return text;
    var end = max_bytes;
    while (end > 0 and text[end] & 0xc0 == 0x80) end -= 1;
    return text[0..end];
}

const Kind = enum { keep, tab, replace };
const Step = struct { kind: Kind, len: usize };

fn classify(text: []const u8, i: usize) Step {
    const byte = text[i];
    if (byte == '\t') return .{ .kind = .tab, .len = 1 };
    if (byte < 0x20 or byte == 0x7f) return .{ .kind = .replace, .len = 1 };
    if (byte < 0x80) return .{ .kind = .keep, .len = 1 };

    const seq_len = std.unicode.utf8ByteSequenceLength(byte) catch
        return .{ .kind = .replace, .len = 1 };
    if (i + seq_len > text.len) return .{ .kind = .replace, .len = 1 };
    const codepoint = std.unicode.utf8Decode(text[i .. i + seq_len]) catch
        return .{ .kind = .replace, .len = 1 };
    if (codepoint >= 0x80 and codepoint <= 0x9f) return .{ .kind = .replace, .len = seq_len };
    return .{ .kind = .keep, .len = seq_len };
}

const testing = std.testing;

fn expectSanitized(expected: []const u8, input: []const u8) !void {
    const out = try sanitizeAlloc(testing.allocator, input);
    defer testing.allocator.free(out);
    try testing.expectEqualStrings(expected, out);
    try testing.expect(!needsSanitizing(out));
}

test "an OSC 52 clipboard write is defused" {
    try expectSanitized("?]52;c;aGVsbG8=?", "\x1b]52;c;aGVsbG8=\x07");
    try testing.expect(needsSanitizing("\x1b]52;c;aGVsbG8=\x07"));
}

test "a carriage return cannot overwrite the start of the line" {
    try expectSanitized("a?b", "a\rb");
}

test "C1 controls encoded as UTF-8 are replaced as one character" {
    // U+009B is CSI: on terminals that honour C1, it starts an escape sequence
    // without any ESC byte.
    try expectSanitized("?2J", "\xc2\x9b2J");
    try expectSanitized("x?y", "x\xc2\x85y");
}

test "DEL and NUL are replaced" {
    try expectSanitized("a?b?c", "a\x7fb\x00c");
}

test "valid UTF-8 survives untouched" {
    const text = "日本語 ✓ café — naïve 🙂";
    try testing.expect(!needsSanitizing(text));
    try expectSanitized(text, text);
}

test "invalid UTF-8 bytes are replaced one byte at a time" {
    try expectSanitized("a?b", "a\x9bb");
    try expectSanitized("a??", "a\xe6\x97");
    try expectSanitized("?(", "\xc3\x28");
}

test "tabs expand to the next tab stop" {
    try expectSanitized("a       b", "a\tb");
    try expectSanitized("        x", "\tx");
    try expectSanitized("日       x", "日\tx");
}

test "sanitizeOwned returns the same allocation when nothing changes" {
    const owned = try testing.allocator.dupe(u8, "plain");
    const result = try sanitizeOwned(testing.allocator, owned);
    defer testing.allocator.free(result);
    try testing.expectEqual(owned.ptr, result.ptr);

    const dirty = try testing.allocator.dupe(u8, "bad\x1b[2J");
    const cleaned = try sanitizeOwned(testing.allocator, dirty);
    defer testing.allocator.free(cleaned);
    try testing.expectEqualStrings("bad?[2J", cleaned);
}

test "utf8Prefix never ends inside a multi-byte sequence" {
    const text = "aé日";
    try testing.expectEqualStrings("a", utf8Prefix(text, 1));
    try testing.expectEqualStrings("a", utf8Prefix(text, 2));
    try testing.expectEqualStrings("aé", utf8Prefix(text, 3));
    try testing.expectEqualStrings("aé", utf8Prefix(text, 5));
    try testing.expectEqualStrings(text, utf8Prefix(text, 6));
    try testing.expectEqualStrings(text, utf8Prefix(text, 100));
    var width: usize = 0;
    while (width <= text.len) : (width += 1) {
        try testing.expect(std.unicode.utf8ValidateSlice(utf8Prefix(text, width)));
    }
}
