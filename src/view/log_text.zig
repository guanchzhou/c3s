// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Pure text helpers for the logs view: timestamp stripping and line wrapping.
//
// Both live here rather than in LogsView so they can be tested without a terminal or a
// cluster. The interesting cases -- a line exactly the width of the pane, a log line
// that happens to start with something timestamp-shaped, a UTF-8 sequence straddling
// the wrap point -- are all awkward to produce against a live pod and trivial here.
const std = @import("std");

/// Length of the RFC3339 timestamp Kubernetes prepends when `timestamps=true`, plus the
/// single space after it. The API emits nanosecond precision and a `Z`, e.g.
/// `2026-08-22T12:34:56.789012345Z `.
///
/// c3s always fetches WITH timestamps and strips them for display, rather than
/// refetching when the toggle flips: one request, an instant toggle, and no window
/// where the toggle is on but the buffer predates it. The cost is a few bytes per line.
pub fn stripTimestamp(line: []const u8) []const u8 {
    if (!looksLikeTimestamp(line)) return line;
    const sp = std.mem.indexOfScalar(u8, line, ' ') orelse return line;
    return line[sp + 1 ..];
}

/// Conservative shape check: `NNNN-NN-NNTNN:NN:NN`, then anything up to a space.
///
/// This is deliberately not a full RFC3339 parse. It only has to distinguish "the API
/// prepended a timestamp" from "it did not", and it must never strip a real log line's
/// first word -- so it requires the digit/separator layout to match exactly.
pub fn looksLikeTimestamp(line: []const u8) bool {
    if (line.len < 20) return false;
    const digits = [_]usize{ 0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18 };
    for (digits) |i| if (!std.ascii.isDigit(line[i])) return false;
    if (line[4] != '-' or line[7] != '-') return false;
    if (line[10] != 'T') return false;
    if (line[13] != ':' or line[16] != ':') return false;
    // Must be followed by a space somewhere -- a bare timestamp with no message is not
    // a line the API produces, and stripping it would leave nothing.
    return std.mem.indexOfScalar(u8, line, ' ') != null;
}

/// One on-screen row of a possibly-wrapped log line.
pub const Segment = struct {
    /// Index into the caller's line list.
    line_index: usize,
    /// Byte range within that line.
    start: usize,
    end: usize,
    /// True for the first row of a line, so the renderer can dim continuations.
    first: bool,
};

/// Split `line` into rows of at most `width` columns, appending Segments.
///
/// Splits on a UTF-8 boundary, never mid-codepoint: cutting a multi-byte sequence in
/// half writes an invalid byte to the terminal, which shows as a replacement character
/// and can desynchronise a line's column count. Width is counted in bytes rather than
/// grapheme clusters -- c3s does not carry a width table, and this at least never
/// produces invalid UTF-8.
pub fn wrapLine(
    allocator: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(Segment),
    line_index: usize,
    line: []const u8,
    width: usize,
) !void {
    if (width == 0) return;
    if (line.len == 0) {
        // An empty line still occupies a row; dropping it would silently renumber the
        // log.
        try out.append(allocator, .{ .line_index = line_index, .start = 0, .end = 0, .first = true });
        return;
    }

    var start: usize = 0;
    var first = true;
    while (start < line.len) {
        var end = @min(start + width, line.len);
        // Back up off a continuation byte so the row ends on a codepoint boundary.
        if (end < line.len) {
            while (end > start and isContinuation(line[end])) end -= 1;
            // A single codepoint wider than the pane would otherwise make no progress
            // and loop forever; emit the raw slice instead of hanging.
            if (end == start) end = @min(start + width, line.len);
        }
        try out.append(allocator, .{
            .line_index = line_index,
            .start = start,
            .end = end,
            .first = first,
        });
        first = false;
        start = end;
    }
}

fn isContinuation(byte: u8) bool {
    return byte & 0xc0 == 0x80;
}

// ===========================================================================
// Tests
// ===========================================================================

const testing = std.testing;

test "strips the timestamp the API prepends" {
    const line = "2026-08-22T12:34:56.789012345Z hello world";
    try testing.expectEqualStrings("hello world", stripTimestamp(line));
}

test "strips a second-precision timestamp too" {
    const line = "2026-08-22T12:34:56Z started";
    try testing.expectEqualStrings("started", stripTimestamp(line));
}

test "leaves an ordinary log line alone" {
    // The whole risk of strip-on-display: eating the first word of a real message.
    for ([_][]const u8{
        "hello world",
        "INFO starting up",
        "2026 was a year",
        "12:34:56 not a date",
        "",
        "short",
    }) |line| {
        try testing.expectEqualStrings(line, stripTimestamp(line));
    }
}

test "a line that is only a timestamp is left alone rather than emptied" {
    const line = "2026-08-22T12:34:56.000000000Z";
    try testing.expectEqualStrings(line, stripTimestamp(line));
}

test "a near-miss shape is not stripped" {
    // One character off in each position that matters.
    for ([_][]const u8{
        "2026-08-22X12:34:56Z msg", // wrong T
        "2026/08/22T12:34:56Z msg", // wrong separators
        "202X-08-22T12:34:56Z msg", // non-digit
        "2026-08-22T12-34-56Z msg", // wrong colons
    }) |line| {
        try testing.expectEqualStrings(line, stripTimestamp(line));
    }
}

test "wrapping a short line yields exactly one row" {
    const a = testing.allocator;
    var segs: std.ArrayListUnmanaged(Segment) = .empty;
    defer segs.deinit(a);

    try wrapLine(a, &segs, 7, "hello", 20);
    try testing.expectEqual(@as(usize, 1), segs.items.len);
    try testing.expectEqual(@as(usize, 7), segs.items[0].line_index);
    try testing.expect(segs.items[0].first);
    try testing.expectEqual(@as(usize, 5), segs.items[0].end);
}

test "a line exactly the pane width is one row, not two" {
    // Off-by-one here would put a phantom blank row after every full-width line.
    const a = testing.allocator;
    var segs: std.ArrayListUnmanaged(Segment) = .empty;
    defer segs.deinit(a);

    try wrapLine(a, &segs, 0, "abcde", 5);
    try testing.expectEqual(@as(usize, 1), segs.items.len);
}

test "a long line splits into covering, non-overlapping rows" {
    const a = testing.allocator;
    var segs: std.ArrayListUnmanaged(Segment) = .empty;
    defer segs.deinit(a);

    const line = "abcdefghij";
    try wrapLine(a, &segs, 0, line, 3);
    try testing.expectEqual(@as(usize, 4), segs.items.len);
    try testing.expect(segs.items[0].first);
    try testing.expect(!segs.items[1].first);

    // The rows must reconstruct the line exactly -- no gap, no duplication.
    var rebuilt: std.ArrayListUnmanaged(u8) = .empty;
    defer rebuilt.deinit(a);
    var expect_start: usize = 0;
    for (segs.items) |s| {
        try testing.expectEqual(expect_start, s.start);
        try rebuilt.appendSlice(a, line[s.start..s.end]);
        expect_start = s.end;
    }
    try testing.expectEqualStrings(line, rebuilt.items);
}

test "wrapping never splits a multi-byte codepoint" {
    // Cutting a UTF-8 sequence in half writes an invalid byte straight to the
    // terminal. Every row must validate on its own.
    const a = testing.allocator;
    var segs: std.ArrayListUnmanaged(Segment) = .empty;
    defer segs.deinit(a);

    // Three-byte codepoints, so most width values land mid-sequence.
    const line = "日本語のログ行です";
    var width: usize = 1;
    while (width <= 12) : (width += 1) {
        segs.clearRetainingCapacity();
        try wrapLine(a, &segs, 0, line, width);

        var rebuilt: std.ArrayListUnmanaged(u8) = .empty;
        defer rebuilt.deinit(a);
        for (segs.items) |s| {
            const piece = line[s.start..s.end];
            // width 1 and 2 cannot fit a 3-byte codepoint; those rows are allowed to
            // be raw, but must still make progress rather than loop.
            if (width >= 3) {
                try testing.expect(std.unicode.utf8ValidateSlice(piece));
            }
            try testing.expect(s.end > s.start);
            try rebuilt.appendSlice(a, piece);
        }
        try testing.expectEqualStrings(line, rebuilt.items);
    }
}

test "an empty line still occupies one row" {
    const a = testing.allocator;
    var segs: std.ArrayListUnmanaged(Segment) = .empty;
    defer segs.deinit(a);

    try wrapLine(a, &segs, 3, "", 10);
    try testing.expectEqual(@as(usize, 1), segs.items.len);
    try testing.expectEqual(@as(usize, 0), segs.items[0].end);
    try testing.expect(segs.items[0].first);
}

test "zero width produces no rows instead of looping forever" {
    const a = testing.allocator;
    var segs: std.ArrayListUnmanaged(Segment) = .empty;
    defer segs.deinit(a);

    try wrapLine(a, &segs, 0, "anything", 0);
    try testing.expectEqual(@as(usize, 0), segs.items.len);
}
