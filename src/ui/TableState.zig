const std = @import("std");
const Key = @import("../core/Terminal.zig").Key;
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Terminal = @import("../core/Terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const universal_filter = @import("../viewmodel/filter.zig");
const sort_util = @import("../viewmodel/sort.zig");

/// Reusable table navigation, filtering, and sorting state.
/// Views compose this instead of reimplementing navigation/filter/sort.
pub fn TableState(comptime ItemType: type) type {
    return struct {
        const Self = @This();

        items: std.ArrayListUnmanaged(ItemType),
        filtered_indices: std.ArrayListUnmanaged(usize),
        selected_row: u32 = 0,
        scroll_offset: u32 = 0,
        visible_rows: u32 = 0,
        /// Active filter text. OWNED by the TableState (duped in applyFilter,
        /// freed in deinit). Callers pass a transient slice (e.g. a command
        /// input buffer that is cleared right after); duping here keeps it
        /// valid for later reads such as the title's filter indicator.
        filter_text: []const u8 = "",
        sort_column: ?u8 = null,
        sort_ascending: bool = true,
        show_all_namespaces: bool = false,
        loading: bool = false,
        error_message: ?[]u8 = null,
        /// k9s-style multi-select: set of marked row identity keys.
        /// Keys are owned (duped) by the TableState; values are unit (void).
        marked: std.StringHashMap(void),
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .items = .empty,
                .filtered_indices = .empty,
                .marked = std.StringHashMap(void).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (@hasDecl(ItemType, "deinit")) {
                for (self.items.items) |*item| {
                    item.deinit();
                }
            }
            self.items.deinit(self.allocator);
            self.filtered_indices.deinit(self.allocator);
            self.clearMarks();
            self.marked.deinit();
            if (self.error_message) |msg| {
                self.allocator.free(msg);
            }
            if (self.filter_text.len > 0) self.allocator.free(self.filter_text);
        }

        // ====================================================================
        // Marking (k9s-style multi-select)
        // ====================================================================

        /// Toggle the marked state of a row identified by `key`.
        /// The key is duped on insert and freed on removal, so the caller's
        /// slice (which may be freed on refresh) need not outlive the call.
        pub fn toggleMark(self: *Self, key: []const u8) !void {
            if (self.marked.getEntry(key)) |entry| {
                const owned = entry.key_ptr.*;
                _ = self.marked.remove(key);
                self.allocator.free(owned);
            } else {
                const owned = try self.allocator.dupe(u8, key);
                errdefer self.allocator.free(owned);
                try self.marked.put(owned, {});
            }
        }

        pub fn isMarked(self: *const Self, key: []const u8) bool {
            return self.marked.contains(key);
        }

        /// Remove all marks, freeing every owned key.
        pub fn clearMarks(self: *Self) void {
            var it = self.marked.keyIterator();
            while (it.next()) |k| {
                self.allocator.free(k.*);
            }
            self.marked.clearRetainingCapacity();
        }

        /// Clear all items (calling deinit on each) and reset error state
        /// Drop every item and reset the derived view state.
        ///
        /// `filtered_indices`, `selected_row` and `scroll_offset` MUST be reset here.
        /// They index into `items`, so leaving them behind means the next
        /// getSelectedItem() indexes a cleared list. That was reachable without OOM:
        /// AuthorizationView's refresh clears items and returns early before
        /// applyFilter when the cluster is unreachable, so a cursor parked on row 3
        /// then read freed memory on Enter -- a panic in Debug, a silent
        /// out-of-bounds read in ReleaseFast.
        pub fn clearItems(self: *Self) void {
            if (@hasDecl(ItemType, "deinit")) {
                for (self.items.items) |*item| {
                    item.deinit();
                }
            }
            self.items.clearRetainingCapacity();
            self.filtered_indices.clearRetainingCapacity();
            self.selected_row = 0;
            self.scroll_offset = 0;
            if (self.error_message) |msg| {
                self.allocator.free(msg);
                self.error_message = null;
            }
        }

        pub fn appendItem(self: *Self, item: ItemType) !void {
            try self.items.append(self.allocator, item);
        }

        /// Allocate the new message BEFORE releasing the old one.
        ///
        /// Freeing first left error_message pointing at freed memory whenever the
        /// allocation failed, so the next setError freed it again -- a double free,
        /// and a dangling read from render in between. Same idiom applies to every
        /// replace-an-owned-field site.
        pub fn setError(self: *Self, msg: []const u8) !void {
            const new_msg = try self.allocator.dupe(u8, msg);
            if (self.error_message) |old| self.allocator.free(old);
            self.error_message = new_msg;
        }

        pub fn setErrorFmt(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            const new_msg = try std.fmt.allocPrint(self.allocator, fmt, args);
            if (self.error_message) |old| self.allocator.free(old);
            self.error_message = new_msg;
        }

        /// Set a user-friendly error message for common connection/API errors.
        /// Maps raw Zig errors to actionable messages instead of showing internal error names.
        /// `resource` is a runtime string on purpose: as a comptime parameter this
        /// monomorphized once per view (22 instances) purely to concatenate a literal.
        pub fn setConnectionError(self: *Self, resource: []const u8, err: anyerror) !void {
            const friendly: ?[]const u8 = switch (err) {
                error.TlsInitializationFailed => "TLS connection failed. Try: C3S_FORCE_PROXY=1 c3s",
                error.ConnectionRefused => "Connection refused. Is the cluster reachable?",
                error.ConnectionResetByPeer => "Connection reset. Check cluster status.",
                error.UnexpectedReadFailure => "Connection lost. Check cluster connectivity.",
                else => null,
            };
            if (friendly) |msg| {
                try self.setError(msg);
            } else {
                try self.setErrorFmt("Failed to list {s}: {}", .{ resource, err });
            }
        }

        // ====================================================================
        // Navigation
        // ====================================================================

        pub fn navigateDown(self: *Self) void {
            if (self.selected_row + 1 < self.filtered_indices.items.len) {
                self.selected_row += 1;
                if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                    self.scroll_offset += 1;
                }
            }
        }

        pub fn navigateUp(self: *Self) void {
            if (self.selected_row > 0) {
                self.selected_row -= 1;
                if (self.selected_row < self.scroll_offset) {
                    self.scroll_offset = self.selected_row;
                }
            }
        }

        pub fn gotoTop(self: *Self) void {
            self.selected_row = 0;
            self.scroll_offset = 0;
        }

        pub fn gotoBottom(self: *Self) void {
            if (self.filtered_indices.items.len > 0) {
                self.selected_row = @intCast(self.filtered_indices.items.len - 1);
                if (self.selected_row >= self.visible_rows) {
                    self.scroll_offset = self.selected_row - self.visible_rows + 1;
                }
            }
        }

        pub fn pageDown(self: *Self) void {
            const items_len: u32 = @intCast(self.filtered_indices.items.len);
            const jump = @min(self.visible_rows, items_len -| self.selected_row -| 1);
            self.selected_row += jump;
            if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }

        pub fn pageUp(self: *Self) void {
            const jump = @min(self.visible_rows, self.selected_row);
            self.selected_row -= jump;
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        }

        // ====================================================================
        // Key handling — returns KeyResult if handled, null if not
        // ====================================================================

        pub fn handleNavigationKey(self: *Self, key: Key) ?KeyResult {
            switch (key) {
                .char => |c| switch (c) {
                    'j' => {
                        self.navigateDown();
                        return .handled;
                    },
                    'k' => {
                        self.navigateUp();
                        return .handled;
                    },
                    'g' => {
                        self.gotoTop();
                        return .handled;
                    },
                    'd' => return .request_describe,
                    'y' => return .request_yaml,
                    ':' => return .request_command_palette,
                    '/' => return .request_filter,
                    else => return null,
                },
                // Terminal.readKey maps a raw 'G' byte to Key.shift_g, never to
                // .char='G' -- so matching on the character meant "Goto Bottom" was
                // dead on every view backed by TableState, which is nearly all of
                // them. The old test passed `.char = 'G'`, a value the real terminal
                // cannot produce, so it enforced the wrong contract and the bug
                // survived with a green suite.
                .shift_g => {
                    self.gotoBottom();
                    return .handled;
                },
                .down => {
                    self.navigateDown();
                    return .handled;
                },
                .up => {
                    self.navigateUp();
                    return .handled;
                },
                .page_down => {
                    self.pageDown();
                    return .handled;
                },
                // Ctrl-b / Ctrl-f are the vi page keys, and Ctrl-b was advertised as
                // "Page Up" on every view while nothing handled it -- App forwards it
                // to the view, and neither TableState nor resource_view had a case.
                // Same shape as the .shift_g bug.
                //
                // Ctrl-f is deliberately NOT added here: handleNavigationKey runs
                // BEFORE the is_pods branch, so claiming it would shadow pods'
                // working Kill Finalizers. The false "Page Down" hint is removed
                // instead.
                .ctrl_b => {
                    self.pageUp();
                    return .handled;
                },
                .page_up => {
                    self.pageUp();
                    return .handled;
                },
                .home => {
                    self.gotoTop();
                    return .handled;
                },
                .end => {
                    self.gotoBottom();
                    return .handled;
                },
                else => return null,
            }
        }

        // ====================================================================
        // Filter & Sort
        // ====================================================================

        pub fn applyFilter(self: *Self, filter: []const u8, comptime matchFn: fn (*const ItemType, []const u8) bool) !void {
            // Own the filter text: the caller's slice (often a command-input
            // buffer) may be cleared/reused right after this returns, but the
            // title's filter indicator reads filter_text on every later render.
            // Dupe before freeing the old so a self-referential call (passing
            // self.filter_text back in) is safe.
            const new_filter: []const u8 = if (filter.len > 0) try self.allocator.dupe(u8, filter) else "";
            if (self.filter_text.len > 0) self.allocator.free(self.filter_text);
            self.filter_text = new_filter;
            try universal_filter.applyFilter(
                ItemType,
                self.allocator,
                self.items.items,
                &self.filtered_indices,
                self.filter_text,
                &self.selected_row,
                &self.scroll_offset,
                self.visible_rows,
                matchFn,
            );
        }

        pub fn toggleSort(self: *Self, col: u8) void {
            sort_util.toggleSort(&self.sort_column, &self.sort_ascending, col);
        }

        pub fn sortBy(self: *Self, comptime getter: fn (*const ItemType) []const u8) void {
            sort_util.sortFilteredIndices(ItemType, self.items.items, &self.filtered_indices, getter, self.sort_ascending);
        }

        /// Sort by a column chosen at runtime.
        ///
        /// Preferred over sortBy where the item type exposes an indexed accessor: the
        /// comptime-getter form emits one std.sort.pdq per (view, column) pair.
        pub fn sortByColumn(
            self: *Self,
            getter: *const fn (*const ItemType, usize) []const u8,
            column: usize,
        ) void {
            sort_util.sortFilteredIndicesAtColumn(
                ItemType,
                self.items.items,
                &self.filtered_indices,
                getter,
                column,
                self.sort_ascending,
            );
        }

        // ====================================================================
        // Selection helpers
        // ====================================================================

        pub fn getSelectedItem(self: *const Self) ?*const ItemType {
            if (self.filtered_indices.items.len == 0) return null;
            if (self.selected_row >= self.filtered_indices.items.len) return null;
            const idx = self.filtered_indices.items[self.selected_row];
            // Belt as well as braces. clearItems now resets filtered_indices, but a
            // stale index is a silent OOB read rather than a loud failure, so the
            // bound is checked here too: any future path that mutates `items` without
            // refreshing the filter degrades to "no selection" instead of reading
            // out of bounds.
            if (idx >= self.items.items.len) return null;
            return &self.items.items[idx];
        }

        pub fn getVisibleRange(self: *const Self) struct { start: u32, end: u32 } {
            const end = @min(
                self.scroll_offset + self.visible_rows,
                @as(u32, @intCast(self.filtered_indices.items.len)),
            );
            return .{ .start = self.scroll_offset, .end = end };
        }

        pub fn isSelected(self: *const Self, display_offset: usize) bool {
            return (self.scroll_offset + display_offset) == self.selected_row;
        }

        // ====================================================================
        // Rendering helpers
        // ====================================================================

        /// Render loading/error states. Returns true if a state was rendered (caller should return).
        pub fn renderStatus(self: *const Self, terminal_inst: *Terminal, x: u16, y: u16, colors: *const theme_loader.ThemeColors) !bool {
            if (self.loading) {
                try Theme.writeStringWithTheme(terminal_inst, x, y, "Loading...", colors.main_fg, colors.main_bg);
                return true;
            }
            if (self.error_message) |msg| {
                try Theme.writeStringWithTheme(terminal_inst, x, y, msg, colors.status_failed, colors.main_bg);
                return true;
            }
            return false;
        }

        /// Get fg/bg colors for a row based on selection state
        pub fn rowColors(self: *const Self, display_offset: usize, colors: *const theme_loader.ThemeColors) struct { fg: []const u8, bg: []const u8 } {
            if (self.isSelected(display_offset)) {
                return .{ .fg = colors.selected_fg, .bg = colors.selected_bg };
            }
            return .{ .fg = colors.main_fg, .bg = colors.main_bg };
        }
    };
}

const testing = std.testing;

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const TestItem = struct {
    name: []const u8,
    value: u32,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *TestItem) void {
        self.allocator.free(self.name);
    }

    fn getName(self: *const TestItem) []const u8 {
        return self.name;
    }
};

fn createTestItem(allocator: std.mem.Allocator, name: []const u8, value: u32) !TestItem {
    return TestItem{
        .name = try allocator.dupe(u8, name),
        .value = value,
        .allocator = allocator,
    };
}

fn testMatchFn(item: *const TestItem, filter: []const u8) bool {
    return std.mem.indexOf(u8, item.name, filter) != null;
}

/// Populate a TableState with N items named "item-0" .. "item-(N-1)" and
/// apply an empty filter so that filtered_indices is fully populated.
fn populateTable(ts: *TableState(TestItem), allocator: std.mem.Allocator, count: u32) !void {
    for (0..count) |i| {
        var buf: [32]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "item-{d}", .{i});
        try ts.appendItem(try createTestItem(allocator, name, @intCast(i)));
    }
    try ts.applyFilter("", testMatchFn);
}

// =========================================================================
// Navigation tests
// =========================================================================

test "navigation: navigateDown from first item moves to second" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    ts.navigateDown();
    try testing.expectEqual(@as(u32, 1), ts.selected_row);
}

test "navigation: navigateDown at last item stays at last" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    ts.gotoBottom();
    try testing.expectEqual(@as(u32, 4), ts.selected_row);
    ts.navigateDown();
    try testing.expectEqual(@as(u32, 4), ts.selected_row);
}

test "navigation: navigateUp from second item moves to first" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    ts.navigateDown();
    try testing.expectEqual(@as(u32, 1), ts.selected_row);
    ts.navigateUp();
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "navigation: navigateUp at first item stays at first" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    ts.navigateUp();
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "navigation: gotoTop resets to 0" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 20);

    ts.gotoBottom();
    try testing.expect(ts.selected_row > 0);
    try testing.expect(ts.scroll_offset > 0);

    ts.gotoTop();
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    try testing.expectEqual(@as(u32, 0), ts.scroll_offset);
}

test "navigation: gotoBottom goes to last item" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    ts.gotoBottom();
    try testing.expectEqual(@as(u32, 19), ts.selected_row);
    try testing.expectEqual(@as(u32, 15), ts.scroll_offset);
}

test "navigation: gotoBottom with empty list does nothing" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    // No items added
    ts.gotoBottom();
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    try testing.expectEqual(@as(u32, 0), ts.scroll_offset);
}

test "navigation: pageDown jumps by visible_rows count" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    ts.pageDown();
    try testing.expectEqual(@as(u32, 5), ts.selected_row);
}

test "navigation: pageUp jumps back by visible_rows count" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    ts.selected_row = 10;
    ts.scroll_offset = 6;
    ts.pageUp();
    try testing.expectEqual(@as(u32, 5), ts.selected_row);
}

test "navigation: pageUp from near top clamps to zero" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 20);

    ts.selected_row = 3;
    ts.scroll_offset = 0;
    ts.pageUp();
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "navigation: navigateDown adjusts scroll_offset when past visible area" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 3;

    try populateTable(&ts, allocator, 10);

    ts.selected_row = 2;
    ts.scroll_offset = 0;
    ts.navigateDown();
    try testing.expectEqual(@as(u32, 3), ts.selected_row);
    try testing.expectEqual(@as(u32, 1), ts.scroll_offset);
}

test "navigation: navigateUp adjusts scroll_offset when above visible area" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 3;

    try populateTable(&ts, allocator, 10);

    ts.selected_row = 5;
    ts.scroll_offset = 5;
    ts.navigateUp();
    try testing.expectEqual(@as(u32, 4), ts.selected_row);
    try testing.expectEqual(@as(u32, 4), ts.scroll_offset);
}

// =========================================================================
// Filtering tests
// =========================================================================

test "filter: applyFilter with empty string shows all items" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "alpha", 1));
    try ts.appendItem(try createTestItem(allocator, "beta", 2));
    try ts.appendItem(try createTestItem(allocator, "gamma", 3));
    try ts.appendItem(try createTestItem(allocator, "delta", 4));
    try ts.appendItem(try createTestItem(allocator, "epsilon", 5));

    try ts.applyFilter("", testMatchFn);
    try testing.expectEqual(@as(usize, 5), ts.filtered_indices.items.len);
}

test "filter: applyFilter matches subset of items" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "apple", 1));
    try ts.appendItem(try createTestItem(allocator, "banana", 2));
    try ts.appendItem(try createTestItem(allocator, "apricot", 3));
    try ts.appendItem(try createTestItem(allocator, "cherry", 4));

    try ts.applyFilter("ap", testMatchFn);
    try testing.expectEqual(@as(usize, 2), ts.filtered_indices.items.len);
    try testing.expectEqual(@as(usize, 0), ts.filtered_indices.items[0]); // apple
    try testing.expectEqual(@as(usize, 2), ts.filtered_indices.items[1]); // apricot
}

test "filter: applyFilter with no matches produces empty filtered list" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "apple", 1));
    try ts.appendItem(try createTestItem(allocator, "banana", 2));
    try ts.appendItem(try createTestItem(allocator, "cherry", 3));

    try ts.applyFilter("xyz", testMatchFn);
    try testing.expectEqual(@as(usize, 0), ts.filtered_indices.items.len);
}

test "filter: applyFilter resets selected_row and scroll_offset" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 20);
    ts.selected_row = 15;
    ts.scroll_offset = 10;

    try ts.applyFilter("item-0", testMatchFn);
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
    try testing.expectEqual(@as(u32, 0), ts.scroll_offset);
}

test "filter: filter_text is tracked" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "alpha", 1));

    try testing.expectEqualStrings("", ts.filter_text);

    try ts.applyFilter("alph", testMatchFn);
    try testing.expectEqualStrings("alph", ts.filter_text);

    try ts.applyFilter("", testMatchFn);
    try testing.expectEqualStrings("", ts.filter_text);
}

// =========================================================================
// appendItem / clearItems
// =========================================================================

test "appendItem adds items correctly" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.appendItem(try createTestItem(allocator, "first", 1));
    try ts.appendItem(try createTestItem(allocator, "second", 2));
    try ts.appendItem(try createTestItem(allocator, "third", 3));

    try testing.expectEqual(@as(usize, 3), ts.items.items.len);
    try testing.expectEqualStrings("first", ts.items.items[0].name);
    try testing.expectEqualStrings("second", ts.items.items[1].name);
    try testing.expectEqualStrings("third", ts.items.items[2].name);
}

test "clearItems removes all items and resets error" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "alpha", 1));
    try ts.appendItem(try createTestItem(allocator, "beta", 2));
    try ts.setError("something went wrong");

    try testing.expectEqual(@as(usize, 2), ts.items.items.len);
    try testing.expect(ts.error_message != null);

    ts.clearItems();

    try testing.expectEqual(@as(usize, 0), ts.items.items.len);
    try testing.expect(ts.error_message == null);
}

// =========================================================================
// Error messages
// =========================================================================

test "setError stores error message" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setError("connection refused");

    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("connection refused", ts.error_message.?);
}

test "setError replaces previous error" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setError("first error");
    try testing.expectEqualStrings("first error", ts.error_message.?);

    try ts.setError("second error");
    try testing.expectEqualStrings("second error", ts.error_message.?);
}

test "setErrorFmt formats error message" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setErrorFmt("error {d}: {s}", .{ 404, "not found" });

    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("error 404: not found", ts.error_message.?);
}

test "setConnectionError maps TlsInitializationFailed" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setConnectionError("pods", error.TlsInitializationFailed);
    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("TLS connection failed. Try: C3S_FORCE_PROXY=1 c3s", ts.error_message.?);
}

test "setConnectionError maps ConnectionRefused" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setConnectionError("pods", error.ConnectionRefused);
    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("Connection refused. Is the cluster reachable?", ts.error_message.?);
}

test "setConnectionError maps ConnectionResetByPeer" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setConnectionError("pods", error.ConnectionResetByPeer);
    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("Connection reset. Check cluster status.", ts.error_message.?);
}

test "setConnectionError formats unknown error with resource name" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try ts.setConnectionError("deployments", error.OutOfMemory);
    try testing.expect(ts.error_message != null);
    try testing.expectEqualStrings("Failed to list deployments: error.OutOfMemory", ts.error_message.?);
}

// =========================================================================
// Sorting tests
// =========================================================================

test "toggleSort sets sort column and ascending true" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try testing.expect(ts.sort_column == null);
    ts.toggleSort(3);
    try testing.expectEqual(@as(?u8, 3), ts.sort_column);
    try testing.expect(ts.sort_ascending);
}

test "toggleSort on same column flips ascending" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    ts.toggleSort(2);
    try testing.expect(ts.sort_ascending);
    ts.toggleSort(2);
    try testing.expectEqual(@as(?u8, 2), ts.sort_column);
    try testing.expect(!ts.sort_ascending);
}

test "toggleSort on different column resets to ascending" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    ts.toggleSort(1);
    ts.toggleSort(1);
    try testing.expect(!ts.sort_ascending);

    ts.toggleSort(5);
    try testing.expectEqual(@as(?u8, 5), ts.sort_column);
    try testing.expect(ts.sort_ascending);
}

test "sortBy sorts filtered indices by name ascending" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "cherry", 1));
    try ts.appendItem(try createTestItem(allocator, "apple", 2));
    try ts.appendItem(try createTestItem(allocator, "banana", 3));

    try ts.applyFilter("", testMatchFn);

    ts.sort_ascending = true;
    ts.sortBy(TestItem.getName);

    // After ascending sort: apple(1), banana(2), cherry(0)
    try testing.expectEqual(@as(usize, 1), ts.filtered_indices.items[0]);
    try testing.expectEqual(@as(usize, 2), ts.filtered_indices.items[1]);
    try testing.expectEqual(@as(usize, 0), ts.filtered_indices.items[2]);
}

test "sortBy sorts filtered indices by name descending" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "cherry", 1));
    try ts.appendItem(try createTestItem(allocator, "apple", 2));
    try ts.appendItem(try createTestItem(allocator, "banana", 3));

    try ts.applyFilter("", testMatchFn);

    ts.sort_ascending = false;
    ts.sortBy(TestItem.getName);

    // After descending sort: cherry(0), banana(2), apple(1)
    try testing.expectEqual(@as(usize, 0), ts.filtered_indices.items[0]);
    try testing.expectEqual(@as(usize, 2), ts.filtered_indices.items[1]);
    try testing.expectEqual(@as(usize, 1), ts.filtered_indices.items[2]);
}

// =========================================================================
// Selection tests
// =========================================================================

test "getSelectedItem returns correct item" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    ts.navigateDown();
    ts.navigateDown();
    try testing.expectEqual(@as(u32, 2), ts.selected_row);

    const selected = ts.getSelectedItem();
    try testing.expect(selected != null);
    try testing.expectEqualStrings("item-2", selected.?.name);
}

test "getSelectedItem returns null when empty" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    const selected = ts.getSelectedItem();
    try testing.expect(selected == null);
}

test "getSelectedItem returns null when selected_row out of range" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "only", 1));
    try ts.applyFilter("", testMatchFn);

    ts.selected_row = 99; // out of bounds
    const selected = ts.getSelectedItem();
    try testing.expect(selected == null);
}

test "getVisibleRange returns correct start and end" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    ts.scroll_offset = 3;
    const range = ts.getVisibleRange();
    try testing.expectEqual(@as(u32, 3), range.start);
    try testing.expectEqual(@as(u32, 8), range.end);
}

test "getVisibleRange clamps end to item count" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 100;

    try populateTable(&ts, allocator, 5);

    ts.scroll_offset = 0;
    const range = ts.getVisibleRange();
    try testing.expectEqual(@as(u32, 0), range.start);
    try testing.expectEqual(@as(u32, 5), range.end);
}

test "isSelected returns true for selected row offset" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 10);

    ts.selected_row = 3;
    ts.scroll_offset = 1;

    try testing.expect(ts.isSelected(2)); // 1 + 2 = 3
    try testing.expect(!ts.isSelected(0)); // 1 + 0 = 1 != 3
    try testing.expect(!ts.isSelected(3)); // 1 + 3 = 4 != 3
}

// =========================================================================
// show_all_namespaces toggle
// =========================================================================

test "show_all_namespaces defaults to false" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try testing.expect(!ts.show_all_namespaces);
}

test "show_all_namespaces can be toggled" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    ts.show_all_namespaces = true;
    try testing.expect(ts.show_all_namespaces);
    ts.show_all_namespaces = false;
    try testing.expect(!ts.show_all_namespaces);
}

// =========================================================================
// Row colors tests
// =========================================================================

test "rowColors returns selected colors for selected row" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    const colors = theme_loader.ThemeColors{
        .main_bg = "bg",
        .main_fg = "fg",
        .title = "",
        .hi_fg = "",
        .selected_bg = "sel_bg",
        .selected_fg = "sel_fg",
        .inactive_fg = "",
        .proc_box = "",
        .div_line = "",
        .status_running = "",
        .status_pending = "",
        .status_failed = "",
        .status_succeeded = "",
        .key_highlight = "",
        .title_highlight = "",
        .app_name = "",
        .prompt_fg = "",
        .prompt_bg = "",
        .allocator = allocator,
    };

    const rc = ts.rowColors(0, &colors);
    try testing.expectEqualStrings("sel_fg", rc.fg);
    try testing.expectEqualStrings("sel_bg", rc.bg);
}

test "rowColors returns normal colors for non-selected row" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    const colors = theme_loader.ThemeColors{
        .main_bg = "bg",
        .main_fg = "fg",
        .title = "",
        .hi_fg = "",
        .selected_bg = "sel_bg",
        .selected_fg = "sel_fg",
        .inactive_fg = "",
        .proc_box = "",
        .div_line = "",
        .status_running = "",
        .status_pending = "",
        .status_failed = "",
        .status_succeeded = "",
        .key_highlight = "",
        .title_highlight = "",
        .app_name = "",
        .prompt_fg = "",
        .prompt_bg = "",
        .allocator = allocator,
    };

    const rc = ts.rowColors(1, &colors);
    try testing.expectEqualStrings("fg", rc.fg);
    try testing.expectEqualStrings("bg", rc.bg);
}

// =========================================================================
// Memory tests
// =========================================================================

test "memory: init and deinit with items does not leak" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected in init/deinit test");
        }
    }
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    ts.visible_rows = 10;

    try ts.appendItem(try createTestItem(allocator, "one", 1));
    try ts.appendItem(try createTestItem(allocator, "two", 2));
    try ts.appendItem(try createTestItem(allocator, "three", 3));
    try ts.applyFilter("", testMatchFn);
    try ts.setError("test error");

    ts.deinit();
}

test "memory: multiple clearItems cycles do not leak" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            @panic("Memory leak detected in clearItems cycle test");
        }
    }
    const allocator = gpa.allocator();

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    // Cycle 1
    try ts.appendItem(try createTestItem(allocator, "a", 1));
    try ts.appendItem(try createTestItem(allocator, "b", 2));
    try ts.setError("error 1");
    ts.clearItems();

    try testing.expectEqual(@as(usize, 0), ts.items.items.len);
    try testing.expect(ts.error_message == null);

    // Cycle 2
    try ts.appendItem(try createTestItem(allocator, "c", 3));
    try ts.appendItem(try createTestItem(allocator, "d", 4));
    try ts.appendItem(try createTestItem(allocator, "e", 5));
    try ts.setError("error 2");
    ts.clearItems();

    try testing.expectEqual(@as(usize, 0), ts.items.items.len);
    try testing.expect(ts.error_message == null);

    // Cycle 3
    try ts.appendItem(try createTestItem(allocator, "f", 6));
}

// =========================================================================
// handleNavigationKey tests
// =========================================================================

test "handleNavigationKey: j navigates down" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    const result = ts.handleNavigationKey(.{ .char = 'j' });
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 1), ts.selected_row);
}

test "handleNavigationKey: k navigates up" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);
    ts.navigateDown();

    const result = ts.handleNavigationKey(.{ .char = 'k' });
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "handleNavigationKey: g goes to top" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 20);
    ts.gotoBottom();

    const result = ts.handleNavigationKey(.{ .char = 'g' });
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "handleNavigationKey: G goes to bottom" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 5;

    try populateTable(&ts, allocator, 20);

    // .shift_g, not .char='G': that is what Terminal.readKey actually emits for a
    // raw 'G'. This test used to pass the character and therefore proved nothing.
    const result = ts.handleNavigationKey(.{ .shift_g = {} });
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 19), ts.selected_row);

    // And the character form must NOT work, since nothing produces it -- if someone
    // re-adds a .char='G' case, this catches the duplicate contract.
    ts.selected_row = 0;
    _ = ts.handleNavigationKey(.{ .char = 'G' });
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

test "handleNavigationKey: unhandled key returns null" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    const result = ts.handleNavigationKey(.{ .char = 'z' });
    try testing.expect(result == null);
}

test "handleNavigationKey: d returns request_describe" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    const result = ts.handleNavigationKey(.{ .char = 'd' });
    try testing.expect(result != null);
    try testing.expectEqual(View.KeyResult.request_describe, result.?);
}

test "handleNavigationKey: y returns request_yaml" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    const result = ts.handleNavigationKey(.{ .char = 'y' });
    try testing.expect(result != null);
    try testing.expectEqual(View.KeyResult.request_yaml, result.?);
}

test "handleNavigationKey: colon returns request_command_palette" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    const result = ts.handleNavigationKey(.{ .char = ':' });
    try testing.expect(result != null);
    try testing.expectEqual(View.KeyResult.request_command_palette, result.?);
}

test "handleNavigationKey: slash returns request_filter" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    const result = ts.handleNavigationKey(.{ .char = '/' });
    try testing.expect(result != null);
    try testing.expectEqual(View.KeyResult.request_filter, result.?);
}

test "handleNavigationKey: arrow down navigates down" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);

    const result = ts.handleNavigationKey(.down);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 1), ts.selected_row);
}

test "handleNavigationKey: arrow up navigates up" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();
    ts.visible_rows = 10;

    try populateTable(&ts, allocator, 5);
    ts.navigateDown();

    const result = ts.handleNavigationKey(.up);
    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 0), ts.selected_row);
}

// =========================================================================
// Loading state
// =========================================================================

test "loading defaults to false" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    try testing.expect(!ts.loading);
}

test "loading can be set" {
    const allocator = testing.allocator;

    var ts = TableState(TestItem).init(allocator);
    defer ts.deinit();

    ts.loading = true;
    try testing.expect(ts.loading);
    ts.loading = false;
    try testing.expect(!ts.loading);
}

test "clearItems resets the derived view state, so a parked cursor cannot read OOB" {
    // Reproduces the reachable out-of-bounds: populate, move the cursor down, then
    // clear WITHOUT re-filtering (what AuthorizationView does when a refresh fails
    // against an unreachable cluster). getSelectedItem previously bounds-checked
    // selected_row against filtered_indices but never the resulting index against
    // items, so it returned a pointer into a cleared list.
    const Row = struct { name: []const u8 };
    const match = struct {
        fn f(_: *const Row, _: []const u8) bool {
            return true;
        }
    }.f;
    const T = TableState(Row);

    var t = T.init(std.testing.allocator);
    defer t.deinit();

    try t.appendItem(.{ .name = "a" });
    try t.appendItem(.{ .name = "b" });
    try t.appendItem(.{ .name = "c" });
    try t.applyFilter("", match);

    t.selected_row = 2;
    try std.testing.expect(t.getSelectedItem() != null);

    t.clearItems();

    // The derived state must be gone, not merely the items.
    try std.testing.expectEqual(@as(usize, 0), t.filtered_indices.items.len);
    try std.testing.expectEqual(@as(u32, 0), t.selected_row);
    try std.testing.expectEqual(@as(u32, 0), t.scroll_offset);
    try std.testing.expect(t.getSelectedItem() == null);
}

test "getSelectedItem refuses a stale index even if filtered_indices survives" {
    // Directly exercises the defensive bound: hand-craft the exact state clearItems
    // used to leave behind, and assert we degrade to "no selection" rather than
    // reading past the end of items.
    const Row = struct { name: []const u8 };
    const match = struct {
        fn f(_: *const Row, _: []const u8) bool {
            return true;
        }
    }.f;
    const T = TableState(Row);

    var t = T.init(std.testing.allocator);
    defer t.deinit();

    try t.appendItem(.{ .name = "a" });
    try t.applyFilter("", match);
    try std.testing.expect(t.getSelectedItem() != null);

    // items emptied, filtered_indices deliberately left pointing at index 0
    t.items.clearRetainingCapacity();
    try std.testing.expectEqual(@as(usize, 1), t.filtered_indices.items.len);
    try std.testing.expect(t.getSelectedItem() == null);
}

test "setError allocates before freeing, so a replace cannot dangle" {
    // setError used to free the old message and THEN allocate. On failure that left
    // error_message pointing at freed memory, which the next setError freed again.
    // Replacing repeatedly under testing.allocator proves the ordering holds and
    // nothing leaks or double-frees.
    const Row = struct { name: []const u8 };
    var t = TableState(Row).init(std.testing.allocator);
    defer t.deinit();

    try t.setError("first");
    try std.testing.expectEqualStrings("first", t.error_message.?);
    try t.setError("second");
    try std.testing.expectEqualStrings("second", t.error_message.?);
    try t.setErrorFmt("count {d}", .{7});
    try std.testing.expectEqualStrings("count 7", t.error_message.?);

    // clearItems releases it; doing so twice must be safe.
    t.clearItems();
    try std.testing.expect(t.error_message == null);
    t.clearItems();
    try std.testing.expect(t.error_message == null);
}

test "setError: a failed allocation leaves the previous message intact, not dangling" {
    // This is the assertion the plain replace-twice test CANNOT make: the
    // free-then-allocate ordering bug only manifests when the allocation fails.
    // FailingAllocator makes that reachable, so the ordering is genuinely pinned
    // rather than merely described in a comment.
    //
    // Old order: free(old) then allocate. On failure error_message pointed at freed
    // memory, and the NEXT setError freed it again -- a double free. New order
    // allocates first, so a failure leaves the old message untouched and valid.
    const Row = struct { name: []const u8 };

    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 3 });
    const a = failing.allocator();

    var t = TableState(Row).init(a);
    defer t.deinit();

    try t.setError("keep me");
    try std.testing.expectEqualStrings("keep me", t.error_message.?);

    // Burn remaining budget until a replace fails.
    var saw_failure = false;
    for (0..8) |_| {
        t.setError("replacement") catch {
            saw_failure = true;
            break;
        };
    }
    try std.testing.expect(saw_failure);

    // The critical assertion: whatever is held is still readable and still owned by
    // us. Under the old ordering this slice was freed memory.
    try std.testing.expect(t.error_message != null);
    try std.testing.expect(t.error_message.?.len > 0);
}
