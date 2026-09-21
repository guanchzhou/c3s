// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Cedar policy workbench (`:cedar`) -- lists cluster-scoped `cedar.k8s.aws` Policy
// objects and runs the official `cedar` binary against them.
//
// Why this is a view of its own rather than rows in the authorization table: the
// Policy Browser tab aggregates RBAC and Cedar into one summary and deliberately
// carries no policy source. Parsing, formatting, validating and authorizing all need
// the source, and they need per-policy keys that would collide with the RBAC rows.
//
// Why not `:policies`: the Kyverno CRD has the same plural. In k9s that collision
// made a Cedar plugin fire on the Kyverno table; here the alias resolves to a view
// that only ever reads `cedar.k8s.aws`, so the two cannot be confused.

const std = @import("std");
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const view_mod = @import("../viewmodel/view.zig");
const View = view_mod.View;
const KeyResult = View.KeyResult;
const ResourceInfo = view_mod.ResourceInfo;
const hints_model = @import("../model/hints.zig");
const sort_util = @import("../viewmodel/sort.zig");
const TableState = @import("../ui/TableState.zig").TableState;
const keys = @import("../k8s/ResourceKey.zig");

pub const CedarView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    table: TableState(Row),

    /// Null until the first list attempt completes: "not asked yet" and "the CRD is
    /// not installed" are different states and the empty pane says so differently.
    crd_present: ?bool = null,
    /// Whether the `cedar` binary was found. Listing works without it; analysis does
    /// not, and the view says which is the case rather than letting keys do nothing.
    cedar_installed: bool = false,
    loading: bool = false,
    error_message: ?[]u8 = null,

    /// Identity of the in-flight list request, for the async router.
    active_key: ?keys.RequestKey = null,
    active_serial: u64 = 0,

    const COL_NAME: u8 = 0;
    const COL_EFFECT: u8 = 1;
    const COL_VALIDATION: u8 = 2;
    const COL_AGE: u8 = 3;

    pub const Row = struct {
        name: []const u8,
        /// The leading keyword: permit, forbid, or "—" when the source is neither.
        effect: []const u8,
        /// `spec.validation` summarised.
        validation: []const u8,
        age: []const u8,
        /// First line of the source, for the summary column.
        summary: []const u8,
        /// Full `spec.content`. Held so the analysis keys do not re-fetch an object
        /// that is already in hand, and so a scan does not issue N more GETs.
        content: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Row) void {
            self.allocator.free(self.name);
            self.allocator.free(self.validation);
            self.allocator.free(self.age);
            self.allocator.free(self.summary);
            self.allocator.free(self.content);
            // `effect` is one of three static strings.
        }

        fn getName(self: *const Row) []const u8 {
            return self.name;
        }
        fn getEffect(self: *const Row) []const u8 {
            return self.effect;
        }
        fn getValidation(self: *const Row) []const u8 {
            return self.validation;
        }
        fn getAge(self: *const Row) []const u8 {
            return self.age;
        }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !CedarView {
        return .{
            .allocator = allocator,
            .theme = theme,
            .table = TableState(Row).init(allocator),
        };
    }

    pub fn deinit(self: *CedarView) void {
        if (self.error_message) |message| self.allocator.free(message);
        self.error_message = null;
        self.table.deinit();
    }

    /// The leading keyword of a Cedar policy, which is the one thing about its
    /// meaning that can be read without a parser.
    pub fn effectOf(content: []const u8) []const u8 {
        const trimmed = std.mem.trim(u8, content, " \t\r\n");
        var rest = trimmed;
        // Skip annotations and comments, which precede the statement.
        while (rest.len > 0) {
            const line_end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const line = std.mem.trim(u8, rest[0..line_end], " \t\r");
            if (line.len > 0 and !std.mem.startsWith(u8, line, "@") and !std.mem.startsWith(u8, line, "//")) {
                if (std.mem.startsWith(u8, line, "permit")) return "permit";
                if (std.mem.startsWith(u8, line, "forbid")) return "forbid";
                return "—";
            }
            if (line_end == rest.len) break;
            rest = rest[line_end + 1 ..];
        }
        return "—";
    }

    /// First non-annotation, non-comment line, for the summary column.
    pub fn summaryOf(content: []const u8) []const u8 {
        var rest = std.mem.trim(u8, content, " \t\r\n");
        while (rest.len > 0) {
            const line_end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            const line = std.mem.trim(u8, rest[0..line_end], " \t\r");
            if (line.len > 0 and !std.mem.startsWith(u8, line, "@") and !std.mem.startsWith(u8, line, "//")) {
                return line;
            }
            if (line_end == rest.len) break;
            rest = rest[line_end + 1 ..];
        }
        return "(empty policy)";
    }

    pub fn setError(self: *CedarView, message: []const u8) !void {
        const owned = try self.allocator.dupe(u8, message);
        if (self.error_message) |old| self.allocator.free(old);
        self.error_message = owned;
    }

    pub fn clearError(self: *CedarView) void {
        if (self.error_message) |old| self.allocator.free(old);
        self.error_message = null;
    }

    /// Source of the selected policy, borrowed from the row.
    pub fn selectedContent(self: *const CedarView) ?[]const u8 {
        const row = self.table.getSelectedItem() orelse return null;
        return row.content;
    }

    pub fn selectedName(self: *const CedarView) ?[]const u8 {
        const row = self.table.getSelectedItem() orelse return null;
        return row.name;
    }

    pub fn applyFilter(self: *CedarView, filter: []const u8) !void {
        try self.table.applyFilter(filter, matchFn);
        self.applySorting();
    }

    pub fn matchFn(row: *const Row, filter: []const u8) bool {
        return containsIgnoreCase(row.name, filter) or
            containsIgnoreCase(row.effect, filter) or
            containsIgnoreCase(row.summary, filter);
    }

    fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0) return true;
        if (needle.len > haystack.len) return false;
        for (0..haystack.len - needle.len + 1) |index| {
            if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
        }
        return false;
    }

    pub fn applySorting(self: *CedarView) void {
        const col = self.table.sort_column orelse return;
        switch (col) {
            COL_EFFECT => self.table.sortBy(Row.getEffect),
            COL_VALIDATION => self.table.sortBy(Row.getValidation),
            COL_AGE => self.table.sortBy(Row.getAge),
            else => self.table.sortBy(Row.getName),
        }
    }

    pub fn createView(self: *CedarView) View {
        return View.create(CedarView, self, &vtable);
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getTitle = getTitle,
        .getHints = getHints,
        .deinit = deinitView,
        .applyFilter = vtableApplyFilter,
        .clearFilter = vtableClearFilter,
        .getSelectedResource = vtableGetSelectedResource,
    };

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *CedarView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *CedarView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    /// Policy is cluster-scoped, so the namespace is empty by definition rather than
    /// inherited from whatever the previous view had selected.
    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *CedarView = @ptrCast(@alignCast(ptr));
        const row = self.table.getSelectedItem() orelse return null;
        return .{ .name = row.name, .namespace = "" };
    }

    var title_buffer: [96]u8 = undefined;

    fn getTitle(ptr: *anyopaque) []const u8 {
        const self: *CedarView = @ptrCast(@alignCast(ptr));
        const count = self.table.filtered_indices.items.len;
        return std.fmt.bufPrint(&title_buffer, "cedar policies[{d}]", .{count}) catch "cedar policies";
    }

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *CedarView = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 2) height - 2 else 0;

        if (self.error_message) |message| {
            try Theme.writeStringWithTheme(terminal, x, y, message, self.theme.status_failed, self.theme.main_bg);
            return;
        }
        if (self.loading and self.table.items.items.len == 0) {
            try Theme.writeStringWithTheme(terminal, x, y, "Loading Cedar policies...", self.theme.main_fg, self.theme.main_bg);
            return;
        }
        if (try self.table.renderStatus(terminal, x, y, self.theme)) return;

        if (self.table.items.items.len == 0) {
            const message = if (self.crd_present) |present|
                if (present)
                    "No Cedar Policy objects in this cluster."
                else
                    "Cedar is not installed here: no cedar.k8s.aws Policy CRD on this cluster."
            else
                "Cedar policies have not been listed yet. Press r to refresh.";
            try Theme.writeStringWithTheme(terminal, x, y, message, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        // The analysis keys are the reason to be on this view, so a missing binary is
        // stated up front rather than discovered by pressing one and getting nothing.
        var header_y = y;
        if (!self.cedar_installed) {
            try Theme.writeStringWithTheme(
                terminal,
                x,
                header_y,
                "cedar binary not found -- listing only. Install cedar-policy-cli to analyze.",
                self.theme.status_pending,
                self.theme.main_bg,
            );
            header_y += 1;
        }

        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const effect_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_EFFECT);
        const valid_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_VALIDATION);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        var b1: [32]u8 = undefined;
        var b2: [32]u8 = undefined;
        var b3: [32]u8 = undefined;
        var b4: [32]u8 = undefined;

        try Theme.writeStringWithTheme(terminal, x, header_y, std.fmt.bufPrint(&b1, "NAME{s}", .{name_ind}) catch "NAME", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 34, header_y, std.fmt.bufPrint(&b2, "EFFECT{s}", .{effect_ind}) catch "EFFECT", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 44, header_y, std.fmt.bufPrint(&b3, "VALIDATION{s}", .{valid_ind}) catch "VALIDATION", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 58, header_y, std.fmt.bufPrint(&b4, "AGE{s}", .{age_ind}) catch "AGE", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 66, header_y, "POLICY", self.theme.title, self.theme.main_bg);

        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |row_idx, i| {
            const row = self.table.items.items[row_idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = header_y + 1 + @as(u16, @intCast(i));

            if (width > 0) try terminal.fillRow(x, row_y, width, colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x, row_y, row.name[0..@min(32, row.name.len)], colors.fg, colors.bg);
            // forbid is the one a reviewer must not miss, so it is coloured.
            const effect_fg = if (std.mem.eql(u8, row.effect, "forbid")) self.theme.status_failed else colors.fg;
            try Theme.writeStringWithTheme(terminal, x + 34, row_y, row.effect, effect_fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 44, row_y, row.validation[0..@min(12, row.validation.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 58, row_y, row.age[0..@min(7, row.age.len)], colors.fg, colors.bg);

            const remaining = if (width > 66) width - 66 else 0;
            const summary_len = @min(@as(usize, remaining), row.summary.len);
            if (summary_len > 0) {
                try Theme.writeStringWithTheme(terminal, x + 66, row_y, row.summary[0..summary_len], colors.fg, colors.bg);
            }
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *CedarView = @ptrCast(@alignCast(ptr));
        if (self.table.handleNavigationKey(key)) |result| return result;

        switch (key) {
            .enter => return .request_cedar_source,
            .ctrl_r => return .request_cedar_refresh,
            .char => |c| switch (c) {
                'r' => return .request_cedar_refresh,
                'P' => return .request_cedar_check_parse,
                'C' => return .request_cedar_format,
                'V' => return .request_cedar_validate,
                'A' => return .request_cedar_scan,
                'I' => return .request_cedar_can_i,
                'N' => {
                    self.table.toggleSort(COL_NAME);
                    self.applySorting();
                    return .handled;
                },
                'E' => {
                    self.table.toggleSort(COL_EFFECT);
                    self.applySorting();
                    return .handled;
                },
                'B' => {
                    self.table.toggleSort(COL_AGE);
                    self.applySorting();
                    return .handled;
                },
                else => return .not_handled,
            },
            else => return .not_handled,
        }
    }

    fn onShow(_: *anyopaque) void {}
    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "cedar";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *CedarView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

// --- Tests ---

const testing = std.testing;

fn testView(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !CedarView {
    return CedarView.init(allocator, theme);
}

fn appendRow(view: *CedarView, name: []const u8, content: []const u8, validation: []const u8) !void {
    const a = view.allocator;
    try view.table.appendItem(.{
        .name = try a.dupe(u8, name),
        .effect = CedarView.effectOf(content),
        .validation = try a.dupe(u8, validation),
        .age = try a.dupe(u8, "5m"),
        .summary = try a.dupe(u8, CedarView.summaryOf(content)),
        .content = try a.dupe(u8, content),
        .allocator = a,
    });
    try view.applyFilter(view.table.filter_text);
}

test "the effect is read past annotations and comments" {
    try testing.expectEqualStrings("permit", CedarView.effectOf("permit(principal, action, resource);"));
    try testing.expectEqualStrings("forbid", CedarView.effectOf("forbid(principal, action, resource);"));
    try testing.expectEqualStrings(
        "permit",
        CedarView.effectOf("@id(\"x\")\n// a note\npermit(principal, action, resource);"),
    );
    // Not a wildcard and not a guess: a policy that starts with neither keyword is
    // reported as neither.
    try testing.expectEqualStrings("—", CedarView.effectOf("nonsense"));
    try testing.expectEqualStrings("—", CedarView.effectOf(""));
}

test "the summary skips annotations rather than showing the id twice" {
    try testing.expectEqualStrings(
        "permit(principal, action, resource);",
        CedarView.summaryOf("@id(\"x\")\npermit(principal, action, resource);"),
    );
    try testing.expectEqualStrings("(empty policy)", CedarView.summaryOf("   \n\n"));
}

test "the analysis keys report themselves so App can dispatch them" {
    const a = testing.allocator;
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);
    var view = try testView(a, &theme);
    defer view.deinit();

    try appendRow(&view, "permit-all", "permit(principal, action, resource);", "off");

    try testing.expectEqual(KeyResult.request_cedar_check_parse, try CedarView.handleKey(&view, Key{ .char = 'P' }));
    try testing.expectEqual(KeyResult.request_cedar_format, try CedarView.handleKey(&view, Key{ .char = 'C' }));
    try testing.expectEqual(KeyResult.request_cedar_validate, try CedarView.handleKey(&view, Key{ .char = 'V' }));
    try testing.expectEqual(KeyResult.request_cedar_scan, try CedarView.handleKey(&view, Key{ .char = 'A' }));
    try testing.expectEqual(KeyResult.request_cedar_can_i, try CedarView.handleKey(&view, Key{ .char = 'I' }));
    try testing.expectEqual(KeyResult.request_cedar_source, try CedarView.handleKey(&view, Key{ .enter = {} }));
    try testing.expectEqual(KeyResult.request_cedar_refresh, try CedarView.handleKey(&view, Key{ .char = 'r' }));
}

test "the selected policy's source is available without another fetch" {
    const a = testing.allocator;
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);
    var view = try testView(a, &theme);
    defer view.deinit();

    try appendRow(&view, "first", "permit(principal, action, resource);", "off");
    try appendRow(&view, "second", "forbid(principal, action, resource);", "strict");

    try testing.expectEqualStrings("first", view.selectedName().?);
    view.table.selected_row = 1;
    try testing.expectEqualStrings("second", view.selectedName().?);
    try testing.expectEqualStrings("forbid(principal, action, resource);", view.selectedContent().?);
}

test "an empty table distinguishes a missing CRD from an empty cluster" {
    // Rendering the same "nothing here" for both would tell a user their policies
    // vanished when in fact Cedar was never installed.
    const a = testing.allocator;
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);
    var view = try testView(a, &theme);
    defer view.deinit();

    try testing.expect(view.crd_present == null);
    view.crd_present = false;
    try testing.expect(!view.crd_present.?);
}

test "filtering matches the name, the effect and the summary" {
    const a = testing.allocator;
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);
    var view = try testView(a, &theme);
    defer view.deinit();

    try appendRow(&view, "allow-viewers", "permit(principal, action, resource);", "off");
    try appendRow(&view, "block-admins", "forbid(principal in Group::\"admins\", action, resource);", "off");

    try view.applyFilter("forbid");
    try testing.expectEqual(@as(usize, 1), view.table.filtered_indices.items.len);

    try view.applyFilter("viewers");
    try testing.expectEqual(@as(usize, 1), view.table.filtered_indices.items.len);

    try view.applyFilter("admins");
    try testing.expectEqual(@as(usize, 1), view.table.filtered_indices.items.len);

    try view.applyFilter("");
    try testing.expectEqual(@as(usize, 2), view.table.filtered_indices.items.len);
}

test "the view name resolves to the cedar ViewType, so `?` shows its bindings" {
    const ViewType = @import("../viewmodel/keybindings_vm.zig").ViewType;
    var dummy: u8 = 0;
    const name = CedarView.getName(&dummy);
    try testing.expectEqualStrings("cedar", name);
    try testing.expectEqual(ViewType.cedar, std.meta.stringToEnum(ViewType, name).?);
}
