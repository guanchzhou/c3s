// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Parses `views.yaml`: which columns each resource view shows, and in what order.
//
// SCOPE, deliberately narrower than k9s. c3s columns are decided at COMPILE time --
// `RowData.columns` is `[col_count][]const u8` and every transform function returns a
// fixed-size array of pre-extracted strings, with the raw resource object not retained.
// So this file can select and reorder the columns a view already defines; it cannot add
// arbitrary JSONPath columns the way k9s does. Doing that would mean reworking the whole
// comptime column path and every resource config.
//
// Hand-rolled line parser rather than a YAML dependency, matching theme_loader.zig --
// c3s has no yaml dep of its own and this grammar is two levels deep.
//
// Recognised shape (both list forms accepted):
//
//     views:
//       pods:
//         columns:
//           - NAME
//           - STATUS
//       nodes:
//         columns: [NAME, STATUS, AGE]
//
// Anything unrecognised is ignored rather than rejected: a typo in a cosmetic config
// must not stop c3s from starting.
const std = @import("std");
const Logger = @import("../core/logger.zig");

pub const ViewColumns = struct {
    /// Column names in the order the user wants them, uppercased for matching.
    names: [][]const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ViewColumns) void {
        for (self.names) |n| self.allocator.free(n);
        self.allocator.free(self.names);
    }
};

pub const ViewsConfig = struct {
    /// view name (e.g. "pods") -> requested columns
    map: std.StringHashMapUnmanaged(ViewColumns),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ViewsConfig) void {
        var it = self.map.iterator();
        while (it.next()) |e| {
            self.allocator.free(e.key_ptr.*);
            e.value_ptr.deinit();
        }
        self.map.deinit(self.allocator);
    }

    /// Requested columns for a view, or null if the file said nothing about it.
    /// Null means "use the compiled-in columns", which is why an absent or empty
    /// views.yaml changes nothing.
    pub fn forView(self: *const ViewsConfig, view_name: []const u8) ?[]const []const u8 {
        if (self.map.get(view_name)) |vc| return vc.names;
        return null;
    }
};

/// Parse views.yaml content. Never fails on malformed input -- unrecognised lines are
/// skipped, because a cosmetic config must not be able to stop the app starting.
pub fn parse(allocator: std.mem.Allocator, content: []const u8) !ViewsConfig {
    var cfg = ViewsConfig{ .map = .empty, .allocator = allocator };
    errdefer cfg.deinit();

    var in_views = false;
    var current_view: ?[]const u8 = null; // borrowed from content
    var collecting = false; // inside a `columns:` block list
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (names.items) |n| allocator.free(n);
        names.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        const trimmed = std.mem.trim(u8, line, " \t");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        const indent = line.len - std.mem.trimStart(u8, line, " \t").len;

        // A list item under `columns:`.
        if (collecting and trimmed[0] == '-') {
            const item = std.mem.trim(u8, trimmed[1..], " \t\"'");
            if (item.len > 0) try names.append(allocator, try upper(allocator, item));
            continue;
        }

        // Any non-list line ends a block list.
        if (collecting) {
            try commit(&cfg, &current_view, &names);
            collecting = false;
        }

        if (indent == 0) {
            in_views = std.mem.startsWith(u8, trimmed, "views:");
            current_view = null;
            continue;
        }
        if (!in_views) continue;

        // `columns:` — either inline `[A, B]` or the start of a block list.
        if (std.mem.startsWith(u8, trimmed, "columns:")) {
            if (current_view == null) continue;
            const rest = std.mem.trim(u8, trimmed["columns:".len..], " \t");
            if (rest.len == 0) {
                collecting = true;
                continue;
            }
            if (rest[0] == '[') {
                const close = std.mem.indexOfScalar(u8, rest, ']') orelse rest.len;
                var items = std.mem.splitScalar(u8, rest[1..close], ',');
                while (items.next()) |it| {
                    const item = std.mem.trim(u8, it, " \t\"'");
                    if (item.len > 0) try names.append(allocator, try upper(allocator, item));
                }
                try commit(&cfg, &current_view, &names);
            }
            continue;
        }

        // A view name: `pods:` at deeper indent than `views:`.
        if (std.mem.endsWith(u8, trimmed, ":")) {
            current_view = std.mem.trim(u8, trimmed[0 .. trimmed.len - 1], " \t\"'");
        }
    }

    // A block list running to EOF still counts.
    if (collecting) try commit(&cfg, &current_view, &names);
    return cfg;
}

fn commit(
    cfg: *ViewsConfig,
    current_view: *?[]const u8,
    names: *std.ArrayListUnmanaged([]const u8),
) !void {
    defer names.clearRetainingCapacity();
    const view = current_view.* orelse return;
    if (names.items.len == 0) return;

    const a = cfg.allocator;
    // Last writer wins on a duplicated view key -- and the earlier entry must be freed
    // rather than leaked.
    const key = try a.dupe(u8, view);
    const owned = try a.dupe([]const u8, names.items);
    names.clearRetainingCapacity(); // ownership moved into `owned`

    const gop = try cfg.map.getOrPut(a, key);
    if (gop.found_existing) {
        a.free(key);
        gop.value_ptr.deinit();
    }
    gop.value_ptr.* = .{ .names = owned, .allocator = a };
}

fn upper(allocator: std.mem.Allocator, s: []const u8) ![]const u8 {
    const out = try allocator.alloc(u8, s.len);
    for (s, 0..) |c, i| out[i] = std.ascii.toUpper(c);
    return out;
}

// ===========================================================================
// Process-wide cache, mirroring xdg.ensurePaths().
//
// ResourceView.init is called from a comptime loop with a fixed
// (allocator, theme, k8s_service) signature, so threading the parsed config through
// would mean changing that loop and every bespoke view's signature. A lazily-loaded
// singleton keeps the change contained, and matches an idiom already in the codebase.
// ===========================================================================

var cached: ?ViewsConfig = null;
var load_attempted = false;

/// The parsed views.yaml, or null when there is no readable file. Loads at most once.
pub fn get() ?*const ViewsConfig {
    if (cached) |*c| return c;
    if (load_attempted) return null;
    load_attempted = true;

    const xdg = @import("../core/xdg.zig");
    const runtime = @import("../core/runtime.zig");
    const paths = xdg.ensurePaths() catch return null;

    // 256 KiB is far more than any plausible column config; a runaway file must not be
    // read into memory unbounded. A missing file is the normal case, not an error.
    const content = std.Io.Dir.cwd().readFileAlloc(
        runtime.io(),
        paths.views_file,
        std.heap.page_allocator,
        .limited(256 * 1024),
    ) catch return null;
    defer std.heap.page_allocator.free(content);

    cached = parse(std.heap.page_allocator, content) catch |err| {
        Logger.warn("could not parse {s}: {any}", .{ paths.views_file, err });
        return null;
    };
    return &cached.?;
}

/// Test-only: install a parsed config, so a test can drive the real consumer
/// (ResourceView.applyViewsConfig) instead of reimplementing its resolution logic.
/// Takes ownership.
pub fn setForTests(cfg: ViewsConfig) void {
    if (cached) |*c| c.deinit();
    cached = cfg;
    load_attempted = true;
}

/// Test-only: drop the cache so the next get() re-reads.
pub fn resetForTests() void {
    if (cached) |*c| c.deinit();
    cached = null;
    load_attempted = false;
}

// ===========================================================================
// Tests
// ===========================================================================

const testing = std.testing;

test "parses a block list" {
    const a = testing.allocator;
    var cfg = try parse(a,
        \\views:
        \\  pods:
        \\    columns:
        \\      - NAME
        \\      - STATUS
        \\      - AGE
    );
    defer cfg.deinit();

    const cols = cfg.forView("pods").?;
    try testing.expectEqual(@as(usize, 3), cols.len);
    try testing.expectEqualStrings("NAME", cols[0]);
    try testing.expectEqualStrings("STATUS", cols[1]);
    try testing.expectEqualStrings("AGE", cols[2]);
}

test "parses an inline list" {
    const a = testing.allocator;
    var cfg = try parse(a,
        \\views:
        \\  nodes:
        \\    columns: [NAME, STATUS, AGE]
    );
    defer cfg.deinit();

    const cols = cfg.forView("nodes").?;
    try testing.expectEqual(@as(usize, 3), cols.len);
    try testing.expectEqualStrings("STATUS", cols[1]);
}

test "order is preserved, since reordering is the point" {
    const a = testing.allocator;
    var cfg = try parse(a,
        \\views:
        \\  pods:
        \\    columns: [AGE, NAME, STATUS]
    );
    defer cfg.deinit();

    const cols = cfg.forView("pods").?;
    try testing.expectEqualStrings("AGE", cols[0]);
    try testing.expectEqualStrings("NAME", cols[1]);
    try testing.expectEqualStrings("STATUS", cols[2]);
}

test "column names are matched case-insensitively" {
    const a = testing.allocator;
    var cfg = try parse(a,
        \\views:
        \\  pods:
        \\    columns: [name, Status, aGe]
    );
    defer cfg.deinit();

    const cols = cfg.forView("pods").?;
    try testing.expectEqualStrings("NAME", cols[0]);
    try testing.expectEqualStrings("STATUS", cols[1]);
    try testing.expectEqualStrings("AGE", cols[2]);
}

test "several views in one file" {
    const a = testing.allocator;
    var cfg = try parse(a,
        \\views:
        \\  pods:
        \\    columns:
        \\      - NAME
        \\      - STATUS
        \\  services:
        \\    columns:
        \\      - NAME
        \\      - PORTS
        \\  nodes:
        \\    columns: [NAME]
    );
    defer cfg.deinit();

    try testing.expectEqual(@as(usize, 2), cfg.forView("pods").?.len);
    try testing.expectEqualStrings("PORTS", cfg.forView("services").?[1]);
    try testing.expectEqual(@as(usize, 1), cfg.forView("nodes").?.len);
}

test "a view not mentioned returns null, so compiled-in columns are used" {
    const a = testing.allocator;
    var cfg = try parse(a,
        \\views:
        \\  pods:
        \\    columns: [NAME]
    );
    defer cfg.deinit();

    try testing.expect(cfg.forView("pods") != null);
    try testing.expect(cfg.forView("secrets") == null);
    try testing.expect(cfg.forView("") == null);
}

test "malformed input is ignored rather than rejected" {
    // A cosmetic config must never stop c3s from starting, so every one of these has to
    // parse without error and simply contribute nothing.
    const a = testing.allocator;
    for ([_][]const u8{
        "",
        "\n\n\n",
        "not yaml at all",
        "views:",
        "views:\n  pods:",
        "views:\n  pods:\n    columns:",
        "views:\n  pods:\n    columns: [",
        "views:\n  pods:\n    columns: []",
        "views:\n  :\n    columns: [NAME]",
        "# just a comment\n",
    }) |input| {
        var cfg = try parse(a, input);
        defer cfg.deinit();
        // Nothing usable may be recorded from any of these.
        try testing.expect(cfg.forView("pods") == null);
    }
}

test "a columns block outside `views:` is ignored" {
    // Split out of the malformed-input loop above because that loop's assertion was
    // too weak to distinguish the cases: a mutation deleting the `views:` gate entirely
    // survived it. This one fails without the gate.
    const a = testing.allocator;
    var cfg = try parse(a,
        \\other_key:
        \\  pods:
        \\    columns: [NAME, AGE]
    );
    defer cfg.deinit();
    try testing.expect(cfg.forView("pods") == null);
}

test "comments and blank lines inside a list are skipped" {
    const a = testing.allocator;
    var cfg = try parse(a,
        \\views:
        \\  pods:
        \\    columns:
        \\      - NAME
        \\      # a comment
        \\
        \\      - AGE
    );
    defer cfg.deinit();

    const cols = cfg.forView("pods").?;
    try testing.expectEqual(@as(usize, 2), cols.len);
    try testing.expectEqualStrings("AGE", cols[1]);
}

test "quotes are stripped" {
    const a = testing.allocator;
    var cfg = try parse(a,
        \\views:
        \\  pods:
        \\    columns: ["NAME", 'STATUS']
    );
    defer cfg.deinit();

    const cols = cfg.forView("pods").?;
    try testing.expectEqualStrings("NAME", cols[0]);
    try testing.expectEqualStrings("STATUS", cols[1]);
}

test "a duplicated view key keeps the last and leaks nothing" {
    // testing.allocator fails the test on a leak, which is the real assertion here.
    const a = testing.allocator;
    var cfg = try parse(a,
        \\views:
        \\  pods:
        \\    columns: [NAME]
        \\  pods:
        \\    columns: [AGE, STATUS]
    );
    defer cfg.deinit();

    const cols = cfg.forView("pods").?;
    try testing.expectEqual(@as(usize, 2), cols.len);
    try testing.expectEqualStrings("AGE", cols[0]);
}

test "a block list running to end of file is committed" {
    // The commit only happens when a non-list line ends the block, so EOF needs its own
    // flush -- without it the last view in every file would be silently dropped.
    const a = testing.allocator;
    var cfg = try parse(a,
        \\views:
        \\  pods:
        \\    columns:
        \\      - NAME
        \\      - AGE
    );
    defer cfg.deinit();
    try testing.expectEqual(@as(usize, 2), cfg.forView("pods").?.len);
}
