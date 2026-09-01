// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// OSC 52 clipboard copy. The sequence is written to a buffer the caller
// flushes to the tty — same channel k9s uses, so it works over ssh.

const std = @import("std");

/// Append `ESC ] 52 ; c ; <base64> BEL` for `text`.
pub fn appendOsc52(allocator: std.mem.Allocator, dest: *std.ArrayList(u8), text: []const u8) !void {
    const enc = std.base64.standard.Encoder;
    const size = enc.calcSize(text.len);
    const b64 = try allocator.alloc(u8, size);
    defer allocator.free(b64);
    _ = enc.encode(b64, text);
    try dest.appendSlice(allocator, "\x1b]52;c;");
    try dest.appendSlice(allocator, b64);
    try dest.append(allocator, 0x07);
}

test "appendOsc52 wraps base64 in OSC 52" {
    const allocator = std.testing.allocator;
    var dest: std.ArrayList(u8) = .empty;
    defer dest.deinit(allocator);

    try appendOsc52(allocator, &dest, "nginx");
    try std.testing.expect(std.mem.startsWith(u8, dest.items, "\x1b]52;c;"));
    try std.testing.expectEqual(@as(u8, 0x07), dest.items[dest.items.len - 1]);

    const payload = dest.items[7 .. dest.items.len - 1];
    var out: [16]u8 = undefined;
    const n = try std.base64.standard.Decoder.calcSizeForSlice(payload);
    try std.base64.standard.Decoder.decode(out[0..n], payload);
    try std.testing.expectEqualStrings("nginx", out[0..n]);
}
