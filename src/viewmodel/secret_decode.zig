// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Base64-decode a Secret's `data` map for display (`x` on the secrets view).
//
// This is the reason the feature is not just "print the JSON": `kubectl get secret -o
// json` shows base64, and `kubectl describe secret` shows only byte counts, so neither
// answers "what is the password". k9s binds this to `x`, and c3s already advertised
// `x` = "Decode" in loadSecretsBindings with nothing implementing it.
//
// Kept as a pure function over a JSON string so it is testable without a cluster --
// which matters more than usual here, because the interesting inputs (binary values,
// invalid base64, a proxy's HTML error page) are exactly the ones a live cluster will
// not hand you on demand.
const std = @import("std");

pub const Error = error{
    /// The body was not a JSON object: an HTML error page from a TLS-intercepting
    /// proxy, or a metav1.Status. Callers must not treat this as an empty secret.
    NotAnObject,
    OutOfMemory,
};

/// Minimal sink over an ArrayListUnmanaged. `ArrayListUnmanaged` has no `writer()` in
/// Zig 0.16, and the alternative -- threading `allocator` through every append -- made
/// the formatting code harder to read than the thing it formats.
const Out = struct {
    list: *std.ArrayListUnmanaged(u8),
    alloc: std.mem.Allocator,

    fn writeAll(self: Out, bytes: []const u8) Error!void {
        try self.list.appendSlice(self.alloc, bytes);
    }

    fn writeByte(self: Out, b: u8) Error!void {
        try self.list.append(self.alloc, b);
    }

    fn print(self: Out, comptime fmt: []const u8, args: anytype) Error!void {
        const rendered = try std.fmt.allocPrint(self.alloc, fmt, args);
        defer self.alloc.free(rendered);
        try self.list.appendSlice(self.alloc, rendered);
    }
};

/// Render every key in `.data` (and `.stringData`, which is already plaintext) as
///
///     KEY  (n bytes)
///     value
///
/// Values that are not valid base64, or that contain bytes unsafe to write to a
/// terminal, are described rather than dumped -- a secret holding a TLS key would
/// otherwise spray control sequences through the TUI.
pub fn decodeSecretData(allocator: std.mem.Allocator, json_str: []const u8) Error![]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch {
        return Error.NotAnObject;
    };
    defer parsed.deinit();

    if (parsed.value != .object) return Error.NotAnObject;
    const root = parsed.value.object;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    const w = Out{ .list = &out, .alloc = allocator };

    var wrote_any = false;

    if (root.get("data")) |data| {
        if (data == .object) {
            // Sorted, so the same secret always renders the same way -- JSON object
            // order is not guaranteed and an unstable dump is hard to read twice.
            var keys = try sortedKeys(allocator, data.object);
            defer keys.deinit(allocator);
            for (keys.items) |key| {
                const val = data.object.get(key).?;
                if (val != .string) continue;
                try appendDecoded(allocator, w, key, val.string);
                wrote_any = true;
            }
        }
    }

    // stringData is write-only in the API and normally absent from a GET, but if a
    // caller ever sees it, it is already plaintext -- decoding it would corrupt it.
    if (root.get("stringData")) |sd| {
        if (sd == .object) {
            var keys = try sortedKeys(allocator, sd.object);
            defer keys.deinit(allocator);
            for (keys.items) |key| {
                const val = sd.object.get(key).?;
                if (val != .string) continue;
                try w.print("{s}  ({d} bytes, stringData)\n", .{ key, val.string.len });
                try writeSanitized(w, val.string);
                try w.writeAll("\n\n");
                wrote_any = true;
            }
        }
    }

    if (!wrote_any) {
        // An empty secret is a real thing; say so rather than showing a blank pane
        // that looks like a failed fetch.
        try w.writeAll("This secret has no data.\n");
    }

    return out.toOwnedSlice(allocator);
}

/// Replace Secret `data` / `stringData` string values with a length marker so
/// `y` / `d` cannot dump credentials. `x` (decodeSecretData) is the deliberate
/// reveal path. The original JSON is left untouched; this returns a new buffer.
///
/// Parse failure is an error, not a passthrough: returning the raw body on a
/// TLS-intercepting proxy's HTML page would still leak whatever was in it, and
/// reporting "empty" would lie about the cluster.
pub fn redactSecretJson(allocator: std.mem.Allocator, json_str: []const u8) Error![]u8 {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, json_str, .{}) catch {
        return Error.NotAnObject;
    };
    defer parsed.deinit();
    if (parsed.value != .object) return Error.NotAnObject;

    var replacements: std.ArrayListUnmanaged([]u8) = .empty;
    defer {
        for (replacements.items) |s| allocator.free(s);
        replacements.deinit(allocator);
    }

    try redactSecretMap(allocator, parsed.value.object.getPtr("data"), &replacements);
    try redactSecretMap(allocator, parsed.value.object.getPtr("stringData"), &replacements);

    return std.json.Stringify.valueAlloc(allocator, parsed.value, .{}) catch return Error.OutOfMemory;
}

fn redactSecretMap(
    allocator: std.mem.Allocator,
    maybe: ?*std.json.Value,
    replacements: *std.ArrayListUnmanaged([]u8),
) Error!void {
    const v = maybe orelse return;
    if (v.* != .object) return;
    var it = v.object.iterator();
    while (it.next()) |entry| {
        if (entry.value_ptr.* != .string) continue;
        const label = try std.fmt.allocPrint(allocator, "<redacted {d} bytes>", .{entry.value_ptr.string.len});
        try replacements.append(allocator, label);
        entry.value_ptr.* = .{ .string = label };
    }
}

fn sortedKeys(
    allocator: std.mem.Allocator,
    obj: std.json.ObjectMap,
) Error!std.ArrayListUnmanaged([]const u8) {
    var keys: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer keys.deinit(allocator);
    var it = obj.iterator();
    while (it.next()) |entry| try keys.append(allocator, entry.key_ptr.*);
    std.mem.sort([]const u8, keys.items, {}, lessThanStr);
    return keys;
}

fn lessThanStr(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn appendDecoded(
    allocator: std.mem.Allocator,
    w: Out,
    key: []const u8,
    b64: []const u8,
) Error!void {
    const dec = std.base64.standard.Decoder;
    const size = dec.calcSizeForSlice(b64) catch {
        try w.print("{s}  (invalid base64, {d} chars)\n\n", .{ key, b64.len });
        return;
    };
    const buf = try allocator.alloc(u8, size);
    defer allocator.free(buf);
    dec.decode(buf, b64) catch {
        try w.print("{s}  (invalid base64, {d} chars)\n\n", .{ key, b64.len });
        return;
    };

    try w.print("{s}  ({d} bytes)\n", .{ key, buf.len });
    if (isBinary(buf)) {
        // Refusing to print is the point: a TLS key or a gzipped blob would otherwise
        // write raw escape bytes straight into the terminal.
        try w.print("<binary data, not shown>\n\n", .{});
        return;
    }
    try writeSanitized(w, buf);
    try w.writeAll("\n\n");
}

/// True when the value should not be printed at all.
///
/// A NUL byte or invalid UTF-8 does nearly all the work here: DER certificates,
/// keystores and gzipped blobs all trip one or the other, while a PEM-encoded key is
/// plain text and is shown in full (which is what you want -- hiding it would make the
/// feature useless for the most common binary-looking secret).
///
/// ESC is deliberately NOT counted: writeSanitized already neutralises it, and an
/// earlier version's density check classified a 9-byte value containing one ESC as
/// binary, hiding a perfectly readable secret.
fn isBinary(bytes: []const u8) bool {
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return true;
    if (!std.unicode.utf8ValidateSlice(bytes)) return true;
    var weird: usize = 0;
    for (bytes) |b| {
        if (b < 0x20 and b != '\n' and b != '\t' and b != '\r' and b != 0x1b) weird += 1;
    }
    // A dense run of control bytes with no NUL and valid UTF-8 is rare but possible.
    // Require several, so one stray byte in a short value does not hide it.
    return weird >= 2 and weird * 8 > bytes.len;
}

/// Write text with escape-sequence introducers neutralised. Even a "text" secret can
/// contain an ESC, and the detail view writes straight through to the terminal.
fn writeSanitized(w: Out, bytes: []const u8) Error!void {
    for (bytes) |b| {
        if (b == 0x1b or (b < 0x20 and b != '\n' and b != '\t')) {
            try w.writeByte('.');
        } else {
            try w.writeByte(b);
        }
    }
}

// ===========================================================================
// Tests
// ===========================================================================

const testing = std.testing;

test "decodes each data key, sorted, with byte counts" {
    const a = testing.allocator;
    // "hunter2" and "admin". Listed username-first ON PURPOSE: std.json preserves
    // insertion order, so a fixture in already-sorted order lets the sort be deleted
    // without the test noticing -- which is exactly what a mutation caught.
    const json =
        \\{"kind":"Secret","data":{"username":"YWRtaW4=","password":"aHVudGVyMg=="}}
    ;
    const out = try decodeSecretData(a, json);
    defer a.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "hunter2") != null);
    try testing.expect(std.mem.indexOf(u8, out, "admin") != null);
    try testing.expect(std.mem.indexOf(u8, out, "password  (7 bytes)") != null);
    try testing.expect(std.mem.indexOf(u8, out, "username  (5 bytes)") != null);
    // Sorted: password before username, so repeated views read the same.
    try testing.expect(std.mem.indexOf(u8, out, "password").? < std.mem.indexOf(u8, out, "username").?);
}

test "a non-object body is an error, not an empty secret" {
    // The class of bug already fixed in cacheVersionFromResponse: a TLS-intercepting
    // proxy returns an HTML error page, and reporting "no data" for it would tell the
    // user their secret is empty when the request never reached the API server.
    const a = testing.allocator;
    try testing.expectError(Error.NotAnObject, decodeSecretData(a, "<html>nope</html>"));
    try testing.expectError(Error.NotAnObject, decodeSecretData(a, "\"a string\""));
    try testing.expectError(Error.NotAnObject, decodeSecretData(a, "[1,2,3]"));
}

test "binary values are described, never written to the terminal" {
    const a = testing.allocator;
    // base64 of bytes 0x00 0x01 0x02 0xff -- a NUL, so unambiguously binary.
    const json =
        \\{"data":{"tls.key":"AAEC/w=="}}
    ;
    const out = try decodeSecretData(a, json);
    defer a.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "<binary data, not shown>") != null);
    try testing.expect(std.mem.indexOfScalar(u8, out, 0) == null);
}

test "escape bytes in a text value are neutralised" {
    // A secret whose value contains ESC would otherwise write a real escape sequence
    // into a TUI that does write-through rendering, moving the cursor or recolouring
    // the screen from inside a data field.
    const a = testing.allocator;
    // base64 of "a\x1b[31mred"
    const json =
        \\{"data":{"k":"YRtbMzFtcmVk"}}
    ;
    const out = try decodeSecretData(a, json);
    defer a.free(out);

    try testing.expect(std.mem.indexOfScalar(u8, out, 0x1b) == null);
    try testing.expect(std.mem.indexOf(u8, out, "red") != null);
}

test "invalid base64 is reported per key without failing the whole secret" {
    const a = testing.allocator;
    const json =
        \\{"data":{"bad":"!!!not base64!!!","good":"YWRtaW4="}}
    ;
    const out = try decodeSecretData(a, json);
    defer a.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "invalid base64") != null);
    // The good key still decoded: one bad value must not hide the rest.
    try testing.expect(std.mem.indexOf(u8, out, "admin") != null);
}

test "an empty or dataless secret says so rather than rendering blank" {
    const a = testing.allocator;
    for ([_][]const u8{ "{}", "{\"data\":{}}", "{\"kind\":\"Secret\"}" }) |json| {
        const out = try decodeSecretData(a, json);
        defer a.free(out);
        try testing.expect(std.mem.indexOf(u8, out, "no data") != null);
    }
}

test "stringData is shown as-is, not double-decoded" {
    const a = testing.allocator;
    const json =
        \\{"stringData":{"plain":"already-text"}}
    ;
    const out = try decodeSecretData(a, json);
    defer a.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "already-text") != null);
    try testing.expect(std.mem.indexOf(u8, out, "stringData") != null);
}

test "non-string data values are skipped instead of crashing" {
    // A hand-edited or non-conforming body could carry a number or null here; the
    // parser must not be trusted to have rejected it.
    const a = testing.allocator;
    const json =
        \\{"data":{"n":123,"nil":null,"ok":"YWRtaW4="}}
    ;
    const out = try decodeSecretData(a, json);
    defer a.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "admin") != null);
}

test "a dense run of control bytes is treated as binary even without a NUL" {
    // Guards the density branch specifically, so it cannot rot into dead logic behind
    // the NUL and UTF-8 checks.
    const a = testing.allocator;
    // base64 of 0x01 0x02 0x03 0x04 -- valid UTF-8, no NUL, all control.
    const json =
        \\{"data":{"k":"AQIDBA=="}}
    ;
    const out = try decodeSecretData(a, json);
    defer a.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "<binary data, not shown>") != null);
}

test "a PEM key is shown in full rather than hidden as binary" {
    // The most common binary-LOOKING secret is a PEM block, which is plain text.
    // Hiding it would defeat the point of the feature.
    const a = testing.allocator;
    const pem = "-----BEGIN PRIVATE KEY-----\nMIIBVgIBADAN\n-----END PRIVATE KEY-----\n";
    var b64_buf: [256]u8 = undefined;
    const b64 = std.base64.standard.Encoder.encode(&b64_buf, pem);

    const json = try std.fmt.allocPrint(a, "{{\"data\":{{\"tls.key\":\"{s}\"}}}}", .{b64});
    defer a.free(json);

    const out = try decodeSecretData(a, json);
    defer a.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "BEGIN PRIVATE KEY") != null);
    try testing.expect(std.mem.indexOf(u8, out, "<binary data") == null);
}

test "redactSecretJson replaces data values and keeps keys" {
    const a = testing.allocator;
    const json =
        \\{"kind":"Secret","data":{"password":"aHVudGVyMg==","username":"YWRtaW4="},"type":"Opaque"}
    ;
    const out = try redactSecretJson(a, json);
    defer a.free(out);

    try testing.expect(std.mem.indexOf(u8, out, "password") != null);
    try testing.expect(std.mem.indexOf(u8, out, "username") != null);
    try testing.expect(std.mem.indexOf(u8, out, "Opaque") != null);
    try testing.expect(std.mem.indexOf(u8, out, "<redacted 12 bytes>") != null);
    try testing.expect(std.mem.indexOf(u8, out, "<redacted 8 bytes>") != null);
    // The original base64 must not survive -- that is the leak `y` used to have.
    try testing.expect(std.mem.indexOf(u8, out, "aHVudGVyMg==") == null);
    try testing.expect(std.mem.indexOf(u8, out, "YWRtaW4=") == null);
}

test "redactSecretJson refuses a non-object body instead of passing it through" {
    const a = testing.allocator;
    try testing.expectError(Error.NotAnObject, redactSecretJson(a, "<html>nope</html>"));
    try testing.expectError(Error.NotAnObject, redactSecretJson(a, "\"a string\""));
}

test "redactSecretJson redacts stringData too" {
    const a = testing.allocator;
    const json =
        \\{"stringData":{"plain":"already-text"}}
    ;
    const out = try redactSecretJson(a, json);
    defer a.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "already-text") == null);
    try testing.expect(std.mem.indexOf(u8, out, "<redacted 12 bytes>") != null);
    try testing.expect(std.mem.indexOf(u8, out, "plain") != null);
}
