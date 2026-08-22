/// LogsView - Scrollable pod log viewer with filtering and search highlighting
const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");

const log_text_util = @import("log_text.zig");

pub const LogsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    lines: std.ArrayListUnmanaged([]const u8),
    filtered_indices: std.ArrayListUnmanaged(usize),
    title: []const u8,
    filter_text: []const u8 = "",
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    visible_rows: u32 = 0,
    auto_scroll: bool = true,
    /// Show the RFC3339 timestamp the API prepends (`t`). Off by default, so output
    /// matches what c3s showed before timestamps were fetched at all.
    show_timestamps: bool = false,
    /// Wrap long lines across rows instead of truncating them (`w`).
    wrap: bool = false,
    /// Cached wrap layout, plus the width and generation it was built for. Rebuilt
    /// lazily in render, because the pane width is not known until then.
    wrap_segments: std.ArrayListUnmanaged(log_text_util.Segment) = .empty,
    wrap_built_width: usize = 0,
    /// Bumped whenever the lines or the filter change, so a stale layout is never
    /// reused for a different log.
    content_generation: u64 = 0,
    wrap_built_generation: u64 = 0,
    /// Content width of the last render, so a toggle can rebuild the layout
    /// immediately instead of reporting a stale row count until the next frame.
    last_content_width: u16 = 0,

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !LogsView {
        return LogsView{
            .allocator = allocator,
            .theme = theme,
            .lines = .empty,
            .filtered_indices = .empty,
            .title = "Logs",
        };
    }

    pub fn deinit(self: *LogsView) void {
        self.wrap_segments.deinit(self.allocator);
        // clearContent frees the line strings, the title and filter_text -- but it
        // uses clearRetainingCapacity, so the lines ArrayList's own backing buffer
        // survives. It was never freed: a real leak, sized by the largest log ever
        // viewed. Surfaced by the first test to populate a LogsView and destroy it
        // under testing.allocator.
        self.clearContent();
        self.lines.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
    }

    fn clearContent(self: *LogsView) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();
        self.filtered_indices.clearRetainingCapacity();
        if (!std.mem.eql(u8, self.title, "Logs")) {
            self.allocator.free(self.title);
            self.title = "Logs";
        }
        if (self.filter_text.len > 0) self.allocator.free(self.filter_text);
        self.filter_text = "";
    }

    /// Whether new content jumps to the tail. Toggled with `s`.
    ///
    /// Exposed so the header can show it: a toggle the user cannot see the state of is
    /// nearly as unhelpful as no toggle at all.
    pub fn isFollowing(self: *const LogsView) bool {
        return self.auto_scroll;
    }

    /// The text of a line as it should appear on screen: the raw line, minus the
    /// timestamp when the toggle is off.
    ///
    /// Everything user-facing goes through here -- rendering AND filtering. Filtering
    /// the raw line would mean a search for "12:34" silently matched hidden
    /// timestamps, which is the sort of thing that looks like a broken filter.
    pub fn displayText(self: *const LogsView, line: []const u8) []const u8 {
        return if (self.show_timestamps) line else log_text_util.stripTimestamp(line);
    }

    /// Toggle timestamps. Instant: the buffer already contains them.
    pub fn toggleTimestamps(self: *LogsView) !void {
        self.show_timestamps = !self.show_timestamps;
        // The filter matches display text, so its result can change, and the wrap
        // layout depends on line widths.
        self.content_generation += 1;
        try self.rebuildFilteredIndices();
        try self.ensureWrapLayoutIfPossible();
        self.clampSelection();
    }

    pub fn toggleWrap(self: *LogsView) !void {
        self.wrap = !self.wrap;
        // Force a rebuild rather than trusting the width check alone: toggling wrap
        // off then on at the same width must not reuse a layout built in between.
        self.content_generation += 1;
        // Rebuild now. Without this, displayRowCount() reports 0 until the next
        // render, so the clamp right after this call would jump the user to the top
        // of the log the first time they press `w`.
        try self.ensureWrapLayoutIfPossible();
    }

    /// Rebuild the wrap layout when wrap is on and a width is known from a previous
    /// render. A no-op before the first render, which is correct: there is nothing on
    /// screen to keep consistent yet.
    fn ensureWrapLayoutIfPossible(self: *LogsView) !void {
        if (!self.wrap or self.last_content_width == 0) return;
        try self.ensureWrapLayout(self.last_content_width);
    }

    /// Set log content from raw text
    pub fn setContent(self: *LogsView, log_text: []const u8, pod_name: []const u8) !void {
        self.clearContent();
        self.title = try std.fmt.allocPrint(self.allocator, "Logs({s})", .{pod_name});
        self.selected_row = 0;
        self.scroll_offset = 0;

        // Split text into lines
        var line_iter = std.mem.splitScalar(u8, log_text, '\n');
        while (line_iter.next()) |line| {
            try self.lines.append(self.allocator, try self.allocator.dupe(u8, line));
        }

        // Build initial unfiltered indices
        self.content_generation += 1;
        try self.rebuildFilteredIndices();

        // Auto-scroll to bottom. Counts DISPLAY rows: with wrap on there are more
        // rows than lines, so using the line count would stop short of the tail --
        // which is the one thing "follow" exists to reach.
        try self.ensureWrapLayoutIfPossible();
        if (self.auto_scroll and self.displayRowCount() > 0) {
            self.selected_row = @intCast(self.displayRowCount() - 1);
            if (self.selected_row >= self.visible_rows and self.visible_rows > 0) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }
    }

    /// Apply a filter to log lines
    pub fn applyFilter(self: *LogsView, filter: []const u8) !void {
        // Own the filter text. The caller's slice is usually command_input's buffer,
        // which is cleared with clearRetainingCapacity() immediately after this
        // returns -- so keeping the borrow meant filter_text aliased whatever the
        // user typed next while retaining its old length, and became a true
        // use-after-free once the buffer grew past its capacity. Reads happen on
        // every later render, not just here.
        //
        // Dupe BEFORE freeing the old: applyFilter is called with self.filter_text
        // itself (refresh paths pass the current filter back in), so freeing first
        // would read freed memory. TableState.applyFilter documents the same hazard.
        const new_filter: []const u8 = if (filter.len > 0) try self.allocator.dupe(u8, filter) else "";
        if (self.filter_text.len > 0) self.allocator.free(self.filter_text);
        self.filter_text = new_filter;
        self.content_generation += 1;
        try self.rebuildFilteredIndices();
        self.selected_row = 0;
        self.scroll_offset = 0;
    }

    fn rebuildFilteredIndices(self: *LogsView) !void {
        self.filtered_indices.clearRetainingCapacity();
        for (self.lines.items, 0..) |line, i| {
            if (self.filter_text.len == 0 or containsCaseInsensitive(self.displayText(line), self.filter_text)) {
                try self.filtered_indices.append(self.allocator, i);
            }
        }
    }

    fn containsCaseInsensitive(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0) return true;
        if (needle.len > haystack.len) return false;
        const end = haystack.len - needle.len + 1;
        for (0..end) |i| {
            var match = true;
            for (0..needle.len) |j| {
                if (toLower(haystack[i + j]) != toLower(needle[j])) {
                    match = false;
                    break;
                }
            }
            if (match) return true;
        }
        return false;
    }

    fn toLower(c: u8) u8 {
        return if (c >= 'A' and c <= 'Z') c + 32 else c;
    }

    // View trait implementation
    pub fn createView(self: *LogsView) View {
        return View.create(LogsView, self, &vtable);
    }

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *LogsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }
    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *LogsView = @ptrCast(@alignCast(ptr));
        if (self.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinitView,
        .applyFilter = vtableApplyFilter,
        .clearFilter = vtableClearFilter,
    };

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *LogsView = @ptrCast(@alignCast(ptr));
        self.visible_rows = if (height > 1) height - 1 else 0;

        if (self.filtered_indices.items.len == 0) {
            const Theme = theme_loader;
            const msg = if (self.filter_text.len > 0) "No matching lines" else "No logs available";
            try Theme.writeStringWithTheme(terminal, x, y, msg, self.theme.inactive_fg, self.theme.main_bg);
            return;
        }

        const content_width: u16 = if (width > 2) width - 2 else 1;
        self.last_content_width = content_width;

        if (self.wrap) {
            try self.ensureWrapLayout(content_width);
            try self.renderWrapped(terminal, x, y);
            return;
        }

        // Draw log lines, truncated at the pane edge.
        const total_lines: u32 = @intCast(self.filtered_indices.items.len);
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + self.visible_rows, total_lines);

        for (start_row..end_row, 0..) |filtered_idx, display_idx| {
            const line_idx = self.filtered_indices.items[filtered_idx];
            const line = self.displayText(self.lines.items[line_idx]);
            const row_y = y + @as(u16, @intCast(display_idx));

            try terminal.setCursor(x, row_y);

            const display_line = line[0..@min(line.len, content_width)];

            if (self.filter_text.len > 0) {
                // Render with highlighted matches
                try self.renderHighlightedLine(terminal, display_line);
            } else {
                try terminal.writeAll(self.theme.main_fg);
                try terminal.writeAll(display_line);
            }
            try terminal.writeAll("\x1b[0m");
        }
    }

    /// Rebuild the wrap layout if the width or the content changed since last time.
    ///
    /// Done here rather than in toggleWrap because the pane width is not known until
    /// render, and it changes when the terminal is resized.
    fn ensureWrapLayout(self: *LogsView, width: u16) !void {
        if (self.wrap_built_width == width and
            self.wrap_built_generation == self.content_generation and
            self.wrap_segments.items.len > 0) return;

        self.wrap_segments.clearRetainingCapacity();
        for (self.filtered_indices.items) |line_idx| {
            try log_text_util.wrapLine(
                self.allocator,
                &self.wrap_segments,
                line_idx,
                self.displayText(self.lines.items[line_idx]),
                width,
            );
        }
        self.wrap_built_width = width;
        self.wrap_built_generation = self.content_generation;
    }

    /// Number of on-screen rows the log currently occupies. Equals the line count when
    /// wrap is off; scrolling must use this, not the line count, or the tail of a
    /// wrapped log becomes unreachable.
    pub fn displayRowCount(self: *const LogsView) usize {
        return if (self.wrap) self.wrap_segments.items.len else self.filtered_indices.items.len;
    }

    fn renderWrapped(self: *LogsView, terminal: *Terminal, x: u16, y: u16) !void {
        const total: u32 = @intCast(self.wrap_segments.items.len);
        const start_row = @min(self.scroll_offset, total);
        const end_row = @min(start_row + self.visible_rows, total);

        for (start_row..end_row, 0..) |seg_idx, display_idx| {
            const seg = self.wrap_segments.items[seg_idx];
            const line = self.displayText(self.lines.items[seg.line_index]);
            // Defensive: the layout is rebuilt whenever content changes, but a stale
            // segment must clamp rather than slice out of bounds.
            const from = @min(seg.start, line.len);
            const to = @min(seg.end, line.len);
            const piece = line[from..to];
            const row_y = y + @as(u16, @intCast(display_idx));

            try terminal.setCursor(x, row_y);
            if (self.filter_text.len > 0) {
                try self.renderHighlightedLine(terminal, piece);
            } else {
                // Continuation rows are dimmed, so a wrapped line reads as one entry
                // rather than several unrelated ones.
                try terminal.writeAll(if (seg.first) self.theme.main_fg else self.theme.inactive_fg);
                try terminal.writeAll(piece);
            }
            try terminal.writeAll("\x1b[0m");
        }
    }

    /// Render a line with filter matches highlighted
    fn renderHighlightedLine(self: *LogsView, terminal: *Terminal, line: []const u8) !void {
        var pos: usize = 0;
        const needle_len = self.filter_text.len;

        while (pos < line.len) {
            // Find next case-insensitive match
            const match_pos = self.findNextMatch(line, pos);
            if (match_pos) |mp| {
                // Write text before match in normal color
                if (mp > pos) {
                    try terminal.writeAll(self.theme.main_fg);
                    try terminal.writeAll(line[pos..mp]);
                }
                // Write matched text highlighted (black on yellow)
                try terminal.writeAll("\x1b[30;43m");
                try terminal.writeAll(line[mp .. mp + needle_len]);
                try terminal.writeAll("\x1b[0m");
                pos = mp + needle_len;
            } else {
                // No more matches, write remaining text
                try terminal.writeAll(self.theme.main_fg);
                try terminal.writeAll(line[pos..]);
                break;
            }
        }
    }

    fn findNextMatch(self: *LogsView, haystack: []const u8, start: usize) ?usize {
        const needle = self.filter_text;
        if (needle.len == 0) return null;
        if (start + needle.len > haystack.len) return null;
        for (start..haystack.len - needle.len + 1) |i| {
            var match = true;
            for (0..needle.len) |j| {
                if (toLower(haystack[i + j]) != toLower(needle[j])) {
                    match = false;
                    break;
                }
            }
            if (match) return i;
        }
        return null;
    }

    /// Keep selected_row and scroll_offset inside the current display, after
    /// anything that changes the row count (wrap toggle, timestamp toggle, filter).
    fn clampSelection(self: *LogsView) void {
        const rows = self.displayRowCount();
        if (rows == 0) {
            self.selected_row = 0;
            self.scroll_offset = 0;
            return;
        }
        if (self.selected_row >= rows) self.selected_row = @intCast(rows - 1);
        if (self.visible_rows > 0 and self.selected_row >= self.scroll_offset + self.visible_rows) {
            self.scroll_offset = self.selected_row - self.visible_rows + 1;
        }
        if (self.selected_row < self.scroll_offset) self.scroll_offset = self.selected_row;
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *LogsView = @ptrCast(@alignCast(ptr));

        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    if (self.selected_row + 1 < self.displayRowCount()) {
                        self.selected_row += 1;
                        if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                            self.scroll_offset = self.selected_row - self.visible_rows + 1;
                        }
                    }
                    return .handled;
                },
                'k' => {
                    if (self.selected_row > 0) {
                        self.selected_row -= 1;
                        if (self.selected_row < self.scroll_offset) {
                            self.scroll_offset = self.selected_row;
                        }
                    }
                    return .handled;
                },
                'g' => {
                    self.selected_row = 0;
                    self.scroll_offset = 0;
                    return .handled;
                },
                '/' => return .request_filter,
                't' => {
                    self.toggleTimestamps() catch |err| {
                        Logger.err("Failed to toggle timestamps: {any}", .{err});
                    };
                    return .handled;
                },
                'w' => {
                    self.toggleWrap() catch |err| {
                        Logger.err("Failed to toggle wrap: {any}", .{err});
                    };
                    // Row count changes under the cursor, so clamp rather than leave
                    // selected_row past the end of the new layout.
                    self.clampSelection();
                    return .handled;
                },
                's' => {
                    // Toggle follow. auto_scroll was read by setContent but no key
                    // could change it, so it was a knob permanently stuck on: every
                    // refresh yanked you back to the bottom, which makes reading
                    // anything above the tail impossible on a chatty pod.
                    self.auto_scroll = !self.auto_scroll;
                    return .handled;
                },
                else => return .not_handled,
            },
            .up => {
                if (self.selected_row > 0) {
                    self.selected_row -= 1;
                    if (self.selected_row < self.scroll_offset) {
                        self.scroll_offset = self.selected_row;
                    }
                }
                return .handled;
            },
            .down => {
                if (self.selected_row + 1 < self.displayRowCount()) {
                    self.selected_row += 1;
                    if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .shift_g => {
                if (self.displayRowCount() > 0) {
                    self.selected_row = @intCast(self.displayRowCount() - 1);
                    if (self.selected_row >= self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .page_up => {
                if (self.selected_row >= self.visible_rows) {
                    self.selected_row -= self.visible_rows;
                    if (self.selected_row < self.scroll_offset) {
                        self.scroll_offset = self.selected_row;
                    }
                } else {
                    self.selected_row = 0;
                    self.scroll_offset = 0;
                }
                return .handled;
            },
            .page_down => {
                if (self.selected_row + self.visible_rows < self.displayRowCount()) {
                    self.selected_row += self.visible_rows;
                    if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                } else if (self.displayRowCount() > 0) {
                    self.selected_row = @intCast(self.displayRowCount() - 1);
                    if (self.selected_row >= self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .home => {
                self.selected_row = 0;
                self.scroll_offset = 0;
                return .handled;
            },
            .end => {
                if (self.displayRowCount() > 0) {
                    self.selected_row = @intCast(self.displayRowCount() - 1);
                    if (self.selected_row >= self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .escape => return .not_handled,
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("LogsView: View activated", .{});
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("LogsView: View deactivated", .{});
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "logs";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.logsHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *LogsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

test "s toggles follow, and follow controls whether new content jumps to the tail" {
    // auto_scroll was read by setContent and reachable from no key -- a knob stuck
    // on. On a chatty pod that means every refresh yanks you back to the bottom, so
    // reading anything above the tail is impossible.
    const a = std.testing.allocator;

    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);

    var view = try LogsView.init(a, &theme);
    defer view.deinit();
    view.visible_rows = 2;

    // Default is follow-on, matching prior behaviour.
    try std.testing.expect(view.isFollowing());

    try view.setContent("one\ntwo\nthree\nfour", "pod-a");
    // Following: parked at the last line.
    try std.testing.expectEqual(@as(u32, 3), view.selected_row);

    // Toggle off via the key, then move up and confirm new content leaves us alone.
    const r = try LogsView.handleKey(&view, Key{ .char = 's' });
    try std.testing.expectEqual(View.KeyResult.handled, r);
    try std.testing.expect(!view.isFollowing());

    view.selected_row = 0;
    view.scroll_offset = 0;
    try view.setContent("one\ntwo\nthree\nfour\nfive", "pod-a");
    try std.testing.expectEqual(@as(u32, 0), view.selected_row);

    // Toggling back on resumes jumping to the tail.
    _ = try LogsView.handleKey(&view, Key{ .char = 's' });
    try std.testing.expect(view.isFollowing());
    try view.setContent("one\ntwo\nthree", "pod-a");
    try std.testing.expectEqual(@as(u32, 2), view.selected_row);
}

test "t toggles timestamps, and the display text changes without a refetch" {
    // c3s always fetches with timestamps=true and strips them for display, so the
    // toggle must be instant and must not need new content.
    const a = std.testing.allocator;
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);
    var view = try LogsView.init(a, &theme);
    defer view.deinit();

    try view.setContent(
        "2026-08-22T12:34:56.000000000Z first\n2026-08-22T12:34:57.000000000Z second",
        "pod-a",
    );

    // Default: stripped.
    try std.testing.expect(!view.show_timestamps);
    try std.testing.expectEqualStrings("first", view.displayText(view.lines.items[0]));

    const r = try LogsView.handleKey(&view, Key{ .char = 't' });
    try std.testing.expectEqual(View.KeyResult.handled, r);
    try std.testing.expect(view.show_timestamps);
    try std.testing.expectEqualStrings(
        "2026-08-22T12:34:56.000000000Z first",
        view.displayText(view.lines.items[0]),
    );

    // And back, with no new content fetched.
    _ = try LogsView.handleKey(&view, Key{ .char = 't' });
    try std.testing.expectEqualStrings("first", view.displayText(view.lines.items[0]));
}

test "the filter matches what is on screen, not the hidden timestamp" {
    // Filtering the raw line would mean searching for a time silently matched hidden
    // timestamps -- indistinguishable from a broken filter.
    const a = std.testing.allocator;
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);
    var view = try LogsView.init(a, &theme);
    defer view.deinit();

    try view.setContent(
        "2026-08-22T12:34:56.000000000Z alpha\n2026-08-22T09:09:09.000000000Z beta",
        "pod-a",
    );

    // Timestamps hidden: a timestamp substring must match nothing.
    try view.applyFilter("12:34");
    try std.testing.expectEqual(@as(usize, 0), view.filtered_indices.items.len);

    // A message substring still matches.
    try view.applyFilter("alpha");
    try std.testing.expectEqual(@as(usize, 1), view.filtered_indices.items.len);

    // With timestamps shown, the same search now legitimately matches.
    _ = try LogsView.handleKey(&view, Key{ .char = 't' });
    try view.applyFilter("12:34");
    try std.testing.expectEqual(@as(usize, 1), view.filtered_indices.items.len);
}

test "w wraps long lines across rows instead of truncating them" {
    const a = std.testing.allocator;
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);
    var view = try LogsView.init(a, &theme);
    defer view.deinit();

    try view.setContent("aaaaaaaaaaaaaaaaaaaa\nbbb", "pod-a"); // 20 chars, then 3
    view.last_content_width = 5;
    view.visible_rows = 10;

    // Unwrapped: one row per line.
    try std.testing.expectEqual(@as(usize, 2), view.displayRowCount());

    const r = try LogsView.handleKey(&view, Key{ .char = 'w' });
    try std.testing.expectEqual(View.KeyResult.handled, r);
    try std.testing.expect(view.wrap);

    // 20 chars at width 5 = 4 rows, plus 1 for "bbb".
    try std.testing.expectEqual(@as(usize, 5), view.displayRowCount());

    _ = try LogsView.handleKey(&view, Key{ .char = 'w' });
    try std.testing.expectEqual(@as(usize, 2), view.displayRowCount());
}

test "G reaches the tail of a wrapped log, not just the last line index" {
    // The bug this guards: every scroll bound counted filtered_indices, so with wrap
    // on the last rows of a long line were unreachable -- you could not scroll to the
    // end of your own logs.
    const a = std.testing.allocator;
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);
    var view = try LogsView.init(a, &theme);
    defer view.deinit();

    try view.setContent("aaaaaaaaaaaaaaaaaaaa", "pod-a"); // one line, 20 chars
    view.last_content_width = 5;
    view.visible_rows = 2;
    try view.toggleWrap();

    try std.testing.expectEqual(@as(usize, 4), view.displayRowCount());

    _ = try LogsView.handleKey(&view, Key{ .shift_g = {} });
    // Row 3 is the last wrapped row. Counting lines would have parked us on row 0.
    try std.testing.expectEqual(@as(u32, 3), view.selected_row);
}

test "toggling wrap clamps the cursor instead of leaving it past the end" {
    const a = std.testing.allocator;
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);
    var view = try LogsView.init(a, &theme);
    defer view.deinit();

    try view.setContent("aaaaaaaaaaaaaaaaaaaa", "pod-a");
    view.last_content_width = 5;
    view.visible_rows = 10;
    try view.toggleWrap();

    // Sit on the last wrapped row, then turn wrap off: only one row remains.
    _ = try LogsView.handleKey(&view, Key{ .shift_g = {} });
    try std.testing.expectEqual(@as(u32, 3), view.selected_row);

    _ = try LogsView.handleKey(&view, Key{ .char = 'w' });
    try std.testing.expectEqual(@as(usize, 1), view.displayRowCount());
    try std.testing.expectEqual(@as(u32, 0), view.selected_row);
    try std.testing.expectEqual(@as(u32, 0), view.scroll_offset);
}

test "following a wrapped log lands on the last row, not the last line" {
    const a = std.testing.allocator;
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);
    var view = try LogsView.init(a, &theme);
    defer view.deinit();

    view.last_content_width = 5;
    view.visible_rows = 10;
    try view.toggleWrap();
    try std.testing.expect(view.isFollowing());

    try view.setContent("short\naaaaaaaaaaaaaaaaaaaa", "pod-a");
    // 1 row + 4 rows = 5; following must park on row 4.
    try std.testing.expectEqual(@as(usize, 5), view.displayRowCount());
    try std.testing.expectEqual(@as(u32, 4), view.selected_row);
}
