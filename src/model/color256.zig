/// 256-Color Palette Generator
///
/// Generates a 256-color palette from the terminal's base16 theme using
/// CIELAB colorspace interpolation. Based on the algorithm described at:
/// https://gist.github.com/jake-stewart/0a8ea46159a7da2c808e5be2177e1783
///
/// The 216-color cube (indices 16-231) is constructed via trilinear
/// interpolation of the 8 base colors mapped to cube corners. The 24-step
/// grayscale ramp (indices 232-255) interpolates between background and
/// foreground. All interpolation is done in CIELAB for perceptually
/// uniform brightness across hues.
const std = @import("std");
const math = std.math;
const posix = std.posix;
const clock = @import("../core/clock.zig");
const sys = @import("../core/sys.zig");

/// Write all bytes to a file descriptor. Zig 0.16 routes std.Io.File writes
/// through a buffered io Writer; these are short OSC sequences to the terminal,
/// so we write to the fd directly via libc (sys.zig).
fn writeAllFd(fd: posix.fd_t, bytes: []const u8) !void {
    try sys.writeAll(fd, bytes);
}

pub const Rgb = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn eql(a: Rgb, b: Rgb) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b;
    }
};

pub const Lab = struct {
    l: f64,
    a: f64,
    b: f64,
};

// CIE D65 reference white point
const ref_x: f64 = 0.95047;
const ref_y: f64 = 1.00000;
const ref_z: f64 = 1.08883;

// --- Color space conversions ---

fn srgbToLinear(v: f64) f64 {
    if (v <= 0.04045) return v / 12.92;
    return math.pow(f64, (v + 0.055) / 1.055, 2.4);
}

fn linearToSrgb(v: f64) f64 {
    if (v <= 0.0031308) return 12.92 * v;
    return 1.055 * math.pow(f64, v, 1.0 / 2.4) - 0.055;
}

fn labF(t: f64) f64 {
    const delta: f64 = 6.0 / 29.0;
    if (t > delta * delta * delta) {
        return math.pow(f64, t, 1.0 / 3.0);
    }
    return t / (3.0 * delta * delta) + 4.0 / 29.0;
}

fn labFInv(t: f64) f64 {
    const delta: f64 = 6.0 / 29.0;
    if (t > delta) return t * t * t;
    return 3.0 * delta * delta * (t - 4.0 / 29.0);
}

fn clampToU8(v: f64) u8 {
    const rounded = @round(v);
    if (rounded <= 0) return 0;
    if (rounded >= 255) return 255;
    return @intFromFloat(rounded);
}

pub fn rgbToLab(rgb: Rgb) Lab {
    const rf: f64 = @as(f64, @floatFromInt(rgb.r)) / 255.0;
    const gf: f64 = @as(f64, @floatFromInt(rgb.g)) / 255.0;
    const bf: f64 = @as(f64, @floatFromInt(rgb.b)) / 255.0;

    const rl = srgbToLinear(rf);
    const gl = srgbToLinear(gf);
    const bl = srgbToLinear(bf);

    // Linear RGB → CIE XYZ (D65)
    const x = 0.4124564 * rl + 0.3575761 * gl + 0.1804375 * bl;
    const y = 0.2126729 * rl + 0.7151522 * gl + 0.0721750 * bl;
    const z = 0.0193339 * rl + 0.1191920 * gl + 0.9503041 * bl;

    const fx = labF(x / ref_x);
    const fy = labF(y / ref_y);
    const fz = labF(z / ref_z);

    return .{
        .l = 116.0 * fy - 16.0,
        .a = 500.0 * (fx - fy),
        .b = 200.0 * (fy - fz),
    };
}

pub fn labToRgb(lab: Lab) Rgb {
    const fy = (lab.l + 16.0) / 116.0;
    const fx = lab.a / 500.0 + fy;
    const fz = fy - lab.b / 200.0;

    // CIE XYZ → Linear RGB
    const x = ref_x * labFInv(fx);
    const y = ref_y * labFInv(fy);
    const z = ref_z * labFInv(fz);

    const rl = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z;
    const gl = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z;
    const bl = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z;

    return .{
        .r = clampToU8(linearToSrgb(rl) * 255.0),
        .g = clampToU8(linearToSrgb(gl) * 255.0),
        .b = clampToU8(linearToSrgb(bl) * 255.0),
    };
}

/// Linear interpolation in CIELAB colorspace.
pub fn lerpLab(t: f64, a: Lab, b_: Lab) Lab {
    return .{
        .l = a.l + t * (b_.l - a.l),
        .a = a.a + t * (b_.a - a.a),
        .b = a.b + t * (b_.b - a.b),
    };
}

// --- Palette generation ---

/// Generate a 256-color palette from base16 colors.
///
/// The 8 normal base colors (indices 0-7) map to the corners of the
/// 6×6×6 color cube via trilinear interpolation in CIELAB:
///   (0,0,0)=bg  (5,0,0)=red    (0,5,0)=green  (5,5,0)=yellow
///   (0,0,5)=blue (5,0,5)=magenta (0,5,5)=cyan  (5,5,5)=fg
///
/// Optional bg/fg override colors 0 (black) and 7 (white) as the
/// background and foreground corners. The grayscale ramp (232-255)
/// interpolates linearly from bg to fg.
pub fn generate256Palette(base16: [16]Rgb, bg: ?Rgb, fg: ?Rgb) [256]Rgb {
    var base8_lab: [8]Lab = undefined;
    for (0..8) |i| {
        base8_lab[i] = rgbToLab(base16[i]);
    }

    const bg_lab = if (bg) |b_| rgbToLab(b_) else base8_lab[0];
    const fg_lab = if (fg) |f_| rgbToLab(f_) else base8_lab[7];

    var palette: [256]Rgb = undefined;

    // Indices 0-15: copy base16 as-is
    for (0..16) |i| {
        palette[i] = base16[i];
    }

    // Indices 16-231: 6×6×6 color cube via trilinear interpolation
    var idx: usize = 16;
    for (0..6) |r| {
        const rt: f64 = @as(f64, @floatFromInt(r)) / 5.0;
        // Interpolate along R axis for the 4 edge pairs
        const c0 = lerpLab(rt, bg_lab, base8_lab[1]); // bg → red
        const c1 = lerpLab(rt, base8_lab[2], base8_lab[3]); // green → yellow
        const c2 = lerpLab(rt, base8_lab[4], base8_lab[5]); // blue → magenta
        const c3 = lerpLab(rt, base8_lab[6], fg_lab); // cyan → fg

        for (0..6) |g| {
            const gt: f64 = @as(f64, @floatFromInt(g)) / 5.0;
            // Interpolate along G axis
            const c4 = lerpLab(gt, c0, c1);
            const c5 = lerpLab(gt, c2, c3);

            for (0..6) |b_val| {
                const bt: f64 = @as(f64, @floatFromInt(b_val)) / 5.0;
                // Interpolate along B axis
                palette[idx] = labToRgb(lerpLab(bt, c4, c5));
                idx += 1;
            }
        }
    }

    // Indices 232-255: 24-step grayscale ramp from bg to fg
    for (0..24) |i| {
        const t: f64 = @as(f64, @floatFromInt(i + 1)) / 25.0;
        palette[idx] = labToRgb(lerpLab(t, bg_lab, fg_lab));
        idx += 1;
    }

    return palette;
}

// --- Terminal integration via OSC escape sequences ---

/// Apply palette colors to the terminal using OSC 4.
/// Only modifies colors in the range [start, end).
pub fn applyPalette(stdout_fd: posix.fd_t, palette: [256]Rgb, start: u16, end: u16) !void {
    if (start >= end) return;

    var buf: [8192]u8 = undefined;
    var pos: usize = 0;

    var i: usize = start;
    while (i < end) : (i += 1) {
        // Flush if buffer might be too small for next entry (~30 bytes max)
        if (pos + 32 > buf.len) {
            try writeAllFd(stdout_fd,buf[0..pos]);
            pos = 0;
        }
        const c = palette[i];
        const seq = try std.fmt.bufPrint(buf[pos..], "\x1b]4;{d};rgb:{x:0>2}/{x:0>2}/{x:0>2}\x1b\\", .{
            i, c.r, c.g, c.b,
        });
        pos += seq.len;
    }

    if (pos > 0) {
        try writeAllFd(stdout_fd,buf[0..pos]);
    }
}

/// Reset terminal colors to defaults using OSC 104.
pub fn resetPalette(stdout_fd: posix.fd_t, start: u16, end: u16) !void {
    if (start >= end) return;

    var buf: [4096]u8 = undefined;
    var pos: usize = 0;

    var i: usize = start;
    while (i < end) : (i += 1) {
        if (pos + 16 > buf.len) {
            try writeAllFd(stdout_fd,buf[0..pos]);
            pos = 0;
        }
        const seq = try std.fmt.bufPrint(buf[pos..], "\x1b]104;{d}\x1b\\", .{i});
        pos += seq.len;
    }

    if (pos > 0) {
        try writeAllFd(stdout_fd,buf[0..pos]);
    }
}

/// Query the terminal for its current base16 colors (0-15) via OSC 4.
/// Returns null if the terminal doesn't respond within the timeout.
pub fn queryTerminalColors(stdin_fd: posix.fd_t, stdout_fd: posix.fd_t) ?[16]Rgb {
    // Send all 16 color queries at once
    var query_buf: [256]u8 = undefined;
    var qpos: usize = 0;
    for (0..16) |i| {
        const s = std.fmt.bufPrint(query_buf[qpos..], "\x1b]4;{d};?\x1b\\", .{i}) catch break;
        qpos += s.len;
    }
    writeAllFd(stdout_fd,query_buf[0..qpos]) catch return null;

    // Read responses with 200ms total timeout
    var response: [4096]u8 = undefined;
    var total: usize = 0;
    const deadline = clock.milliTimestamp() + 200;

    while (total < response.len) {
        const now = clock.milliTimestamp();
        if (now >= deadline) break;

        var pollfds = [_]posix.pollfd{
            .{ .fd = stdin_fd, .events = posix.POLL.IN, .revents = 0 },
        };

        const timeout_ms = deadline - now;
        const timeout: i32 = @intCast(@min(timeout_ms, 200));
        const ready = posix.poll(&pollfds, timeout) catch break;
        if (ready == 0) break;

        if ((pollfds[0].revents & posix.POLL.IN) != 0) {
            const n = posix.read(stdin_fd, response[total..]) catch break;
            if (n == 0) break;
            total += n;
            if (countOscResponses(response[0..total]) >= 16) break;
        }
    }

    if (total == 0) return null;
    return parseOscResponses(response[0..total]);
}

fn countOscResponses(data: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i + 3 < data.len) : (i += 1) {
        if (data[i] == 'r' and data[i + 1] == 'g' and data[i + 2] == 'b' and data[i + 3] == ':') {
            count += 1;
        }
    }
    return count;
}

fn parseOscResponses(data: []const u8) ?[16]Rgb {
    var colors: [16]Rgb = undefined;
    var found: [16]bool = undefined;
    @memset(&found, false);

    var i: usize = 0;
    while (i + 1 < data.len) {
        // Find ESC ]
        if (data[i] != 0x1b or data[i + 1] != ']') {
            i += 1;
            continue;
        }
        i += 2;

        // Expect "4;"
        if (i + 2 > data.len or data[i] != '4' or data[i + 1] != ';') continue;
        i += 2;

        // Parse color index
        var idx_end = i;
        while (idx_end < data.len and data[idx_end] >= '0' and data[idx_end] <= '9') : (idx_end += 1) {}
        if (idx_end == i or idx_end >= data.len or data[idx_end] != ';') continue;

        const index = std.fmt.parseInt(u8, data[i..idx_end], 10) catch continue;
        i = idx_end + 1;

        // Expect "rgb:"
        if (i + 4 > data.len) continue;
        if (!std.mem.eql(u8, data[i .. i + 4], "rgb:")) continue;
        i += 4;

        // Parse R/G/B hex components
        const r_hex = readHexUntil(data[i..], '/') orelse continue;
        i += r_hex.len + 1;

        const g_hex = readHexUntil(data[i..], '/') orelse continue;
        i += g_hex.len + 1;

        const b_hex = readHexUntilTerminator(data[i..]) orelse continue;
        i += b_hex.len;

        if (index < 16) {
            colors[index] = .{
                .r = parseHexComponent(r_hex),
                .g = parseHexComponent(g_hex),
                .b = parseHexComponent(b_hex),
            };
            found[index] = true;
        }
    }

    for (found) |f| {
        if (!f) return null;
    }
    return colors;
}

fn readHexUntil(data: []const u8, delimiter: u8) ?[]const u8 {
    for (data, 0..) |ch, j| {
        if (ch == delimiter) return if (j > 0) data[0..j] else null;
        if (!std.ascii.isHex(ch)) return null;
    }
    return null;
}

fn readHexUntilTerminator(data: []const u8) ?[]const u8 {
    for (data, 0..) |ch, j| {
        // OSC terminators: ESC \ or BEL
        if (ch == 0x1b or ch == 0x07 or ch == '\n') return if (j > 0) data[0..j] else null;
        if (!std.ascii.isHex(ch)) return null;
    }
    return null;
}

fn parseHexComponent(hex: []const u8) u8 {
    // 16-bit (4 digit): take high byte; 8-bit (2 digit): use directly
    if (hex.len >= 4) {
        return std.fmt.parseInt(u8, hex[0..2], 16) catch 0;
    }
    if (hex.len >= 2) {
        return std.fmt.parseInt(u8, hex[0..2], 16) catch 0;
    }
    if (hex.len == 1) {
        const v = std.fmt.parseInt(u8, hex, 16) catch 0;
        return v | (v << 4); // 0xf → 0xff
    }
    return 0;
}

/// Query terminal base16 colors, generate 256-color palette, and apply.
/// Returns true if the palette was successfully applied.
pub fn queryAndApplyPalette(stdin_fd: posix.fd_t, stdout_fd: posix.fd_t) bool {
    const base16 = queryTerminalColors(stdin_fd, stdout_fd) orelse return false;
    const palette = generate256Palette(base16, null, null);
    applyPalette(stdout_fd, palette, 16, 256) catch return false;
    return true;
}

// --- Tests ---

test "rgb to lab roundtrip" {
    const cases = [_]Rgb{
        .{ .r = 0, .g = 0, .b = 0 },
        .{ .r = 255, .g = 255, .b = 255 },
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 128, .g = 64, .b = 192 },
        .{ .r = 1, .g = 1, .b = 1 },
        .{ .r = 254, .g = 254, .b = 254 },
    };

    for (cases) |c| {
        const lab = rgbToLab(c);
        const back = labToRgb(lab);
        const dr = @as(i16, c.r) - @as(i16, back.r);
        const dg = @as(i16, c.g) - @as(i16, back.g);
        const db = @as(i16, c.b) - @as(i16, back.b);
        try std.testing.expect(@abs(dr) <= 1);
        try std.testing.expect(@abs(dg) <= 1);
        try std.testing.expect(@abs(db) <= 1);
    }
}

test "lerp endpoints" {
    const a = Lab{ .l = 0, .a = 10, .b = 20 };
    const b_ = Lab{ .l = 100, .a = -10, .b = -20 };

    const at0 = lerpLab(0, a, b_);
    try std.testing.expectApproxEqAbs(a.l, at0.l, 0.001);
    try std.testing.expectApproxEqAbs(a.a, at0.a, 0.001);
    try std.testing.expectApproxEqAbs(a.b, at0.b, 0.001);

    const at1 = lerpLab(1, a, b_);
    try std.testing.expectApproxEqAbs(b_.l, at1.l, 0.001);
    try std.testing.expectApproxEqAbs(b_.a, at1.a, 0.001);
    try std.testing.expectApproxEqAbs(b_.b, at1.b, 0.001);

    const mid = lerpLab(0.5, a, b_);
    try std.testing.expectApproxEqAbs(50, mid.l, 0.001);
    try std.testing.expectApproxEqAbs(0, mid.a, 0.001);
    try std.testing.expectApproxEqAbs(0, mid.b, 0.001);
}

test "palette size and corners" {
    const base16 = [16]Rgb{
        .{ .r = 0, .g = 0, .b = 0 }, // 0: black
        .{ .r = 204, .g = 0, .b = 0 }, // 1: red
        .{ .r = 0, .g = 204, .b = 0 }, // 2: green
        .{ .r = 204, .g = 204, .b = 0 }, // 3: yellow
        .{ .r = 0, .g = 0, .b = 204 }, // 4: blue
        .{ .r = 204, .g = 0, .b = 204 }, // 5: magenta
        .{ .r = 0, .g = 204, .b = 204 }, // 6: cyan
        .{ .r = 204, .g = 204, .b = 204 }, // 7: white
        .{ .r = 85, .g = 85, .b = 85 }, // 8+: bright variants
        .{ .r = 255, .g = 0, .b = 0 },
        .{ .r = 0, .g = 255, .b = 0 },
        .{ .r = 255, .g = 255, .b = 0 },
        .{ .r = 0, .g = 0, .b = 255 },
        .{ .r = 255, .g = 0, .b = 255 },
        .{ .r = 0, .g = 255, .b = 255 },
        .{ .r = 255, .g = 255, .b = 255 },
    };

    const palette = generate256Palette(base16, null, null);

    // Base16 should be copied verbatim
    for (0..16) |i| {
        try std.testing.expect(palette[i].eql(base16[i]));
    }

    // Corner (0,0,0) = index 16 should ≈ bg (black)
    try std.testing.expect(palette[16].r <= 2);
    try std.testing.expect(palette[16].g <= 2);
    try std.testing.expect(palette[16].b <= 2);

    // Corner (5,5,5) = index 16 + 215 = 231 should ≈ fg (white)
    try std.testing.expect(palette[231].r >= 200);
    try std.testing.expect(palette[231].g >= 200);
    try std.testing.expect(palette[231].b >= 200);

    // Corner (5,0,0) = 16 + 5*36 = 196 should ≈ red
    try std.testing.expect(palette[196].r >= 180);
    try std.testing.expect(palette[196].g <= 30);
    try std.testing.expect(palette[196].b <= 30);

    // Grayscale ramp: first entry (232) should be near bg, last (255) near fg
    try std.testing.expect(palette[232].r < 30);
    try std.testing.expect(palette[255].r > 180);
}

test "parse hex component" {
    try std.testing.expectEqual(@as(u8, 255), parseHexComponent("ffff"));
    try std.testing.expectEqual(@as(u8, 255), parseHexComponent("ff"));
    try std.testing.expectEqual(@as(u8, 0), parseHexComponent("0000"));
    try std.testing.expectEqual(@as(u8, 128), parseHexComponent("8080"));
    try std.testing.expectEqual(@as(u8, 0xff), parseHexComponent("f"));
}

test "parse osc responses" {
    // Simulate terminal OSC 4 response for color 0 (black)
    const resp = "\x1b]4;0;rgb:0000/0000/0000\x1b\\" ++
        "\x1b]4;1;rgb:cc00/0000/0000\x1b\\" ++
        "\x1b]4;2;rgb:0000/cc00/0000\x1b\\" ++
        "\x1b]4;3;rgb:cc00/cc00/0000\x1b\\" ++
        "\x1b]4;4;rgb:0000/0000/cc00\x1b\\" ++
        "\x1b]4;5;rgb:cc00/0000/cc00\x1b\\" ++
        "\x1b]4;6;rgb:0000/cc00/cc00\x1b\\" ++
        "\x1b]4;7;rgb:cc00/cc00/cc00\x1b\\" ++
        "\x1b]4;8;rgb:5555/5555/5555\x1b\\" ++
        "\x1b]4;9;rgb:ff00/0000/0000\x1b\\" ++
        "\x1b]4;10;rgb:0000/ff00/0000\x1b\\" ++
        "\x1b]4;11;rgb:ff00/ff00/0000\x1b\\" ++
        "\x1b]4;12;rgb:0000/0000/ff00\x1b\\" ++
        "\x1b]4;13;rgb:ff00/0000/ff00\x1b\\" ++
        "\x1b]4;14;rgb:0000/ff00/ff00\x1b\\" ++
        "\x1b]4;15;rgb:ff00/ff00/ff00\x1b\\";

    const colors = parseOscResponses(resp) orelse {
        try std.testing.expect(false);
        return;
    };

    // Color 0: black
    try std.testing.expectEqual(@as(u8, 0), colors[0].r);
    try std.testing.expectEqual(@as(u8, 0), colors[0].g);
    try std.testing.expectEqual(@as(u8, 0), colors[0].b);

    // Color 1: red
    try std.testing.expectEqual(@as(u8, 0xcc), colors[1].r);
    try std.testing.expectEqual(@as(u8, 0), colors[1].g);

    // Color 15: bright white
    try std.testing.expectEqual(@as(u8, 0xff), colors[15].r);
    try std.testing.expectEqual(@as(u8, 0xff), colors[15].g);
    try std.testing.expectEqual(@as(u8, 0xff), colors[15].b);
}
