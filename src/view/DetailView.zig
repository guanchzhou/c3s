/// DetailView - Scrollable text view for describe/JSON display.
/// Supports IDE-style folding of JSON objects/arrays: fold/unfold the block at
/// the cursor (Enter/Space), or fold/unfold everything (c / o).
const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");

pub const DetailView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    lines: std.ArrayListUnmanaged([]const u8),
    /// Per-line: index of the matching close line if this line opens a foldable
    /// block (ends with `{` or `[`), else null. Parallel to `lines`.
    fold_end: std.ArrayListUnmanaged(?u32),
    /// Per-line collapse state (only meaningful where fold_end != null). Parallel to `lines`.
    folded: std.ArrayListUnmanaged(bool),
    /// Indices into `lines` that are currently visible (rebuilt when folds change).
    visible: std.ArrayListUnmanaged(u32),
    title: []const u8,
    /// Cursor position as an index into `visible`.
    selected_row: u32 = 0,
    scroll_offset: u32 = 0,
    horizontal_scroll: u16 = 0,
    visible_rows: u32 = 0,
    /// Last render origin, captured each render() for mouse hit-testing.
    render_x: u16 = 0,
    render_y: u16 = 0,
    /// Detected column-start offsets (for column-wise h/l horizontal nav over
    /// space-aligned content like the aliases / api-resources table).
    col_stops: std.ArrayListUnmanaged(u16) = .empty,

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !DetailView {
        return DetailView{
            .allocator = allocator,
            .theme = theme,
            .lines = .empty,
            .fold_end = .empty,
            .folded = .empty,
            .visible = .empty,
            .title = "Detail",
        };
    }

    pub fn deinit(self: *DetailView) void {
        self.clearContent();
        self.lines.deinit(self.allocator);
        self.fold_end.deinit(self.allocator);
        self.folded.deinit(self.allocator);
        self.visible.deinit(self.allocator);
        self.col_stops.deinit(self.allocator);
    }

    fn clearContent(self: *DetailView) void {
        for (self.lines.items) |line| {
            self.allocator.free(line);
        }
        self.lines.clearRetainingCapacity();
        self.fold_end.clearRetainingCapacity();
        self.folded.clearRetainingCapacity();
        self.visible.clearRetainingCapacity();
        self.col_stops.clearRetainingCapacity();
        if (!std.mem.eql(u8, self.title, "Detail")) {
            self.allocator.free(self.title);
            self.title = "Detail";
        }
    }

    /// Set content from raw JSON string, pretty-printed.
    pub fn setContentJson(self: *DetailView, json_str: []const u8, title: []const u8) !void {
        self.clearContent();
        self.title = try self.allocator.dupe(u8, title);
        self.selected_row = 0;
        self.scroll_offset = 0;
        self.horizontal_scroll = 0;

        // Pretty-print JSON with indentation
        var indent: usize = 0;
        var in_string = false;
        var escape_next = false;
        var line_buf = std.ArrayListUnmanaged(u8).empty;
        defer line_buf.deinit(self.allocator);

        for (json_str) |c| {
            if (escape_next) {
                try line_buf.append(self.allocator, c);
                escape_next = false;
                continue;
            }
            if (c == '\\' and in_string) {
                try line_buf.append(self.allocator, c);
                escape_next = true;
                continue;
            }
            if (c == '"') {
                in_string = !in_string;
                try line_buf.append(self.allocator, c);
                continue;
            }
            if (in_string) {
                try line_buf.append(self.allocator, c);
                continue;
            }

            switch (c) {
                '{', '[' => {
                    try line_buf.append(self.allocator, c);
                    try self.flushLine(&line_buf);
                    indent += 2;
                    try self.writeIndent(&line_buf, indent);
                },
                '}', ']' => {
                    try self.flushLine(&line_buf);
                    indent -|= 2;
                    try self.writeIndent(&line_buf, indent);
                    try line_buf.append(self.allocator, c);
                },
                ',' => {
                    try line_buf.append(self.allocator, c);
                    try self.flushLine(&line_buf);
                    try self.writeIndent(&line_buf, indent);
                },
                ':' => {
                    try line_buf.appendSlice(self.allocator, ": ");
                },
                ' ', '\t', '\n', '\r' => {
                    // Skip whitespace in raw JSON
                },
                else => {
                    try line_buf.append(self.allocator, c);
                },
            }
        }
        if (line_buf.items.len > 0) {
            try self.flushLine(&line_buf);
        }

        try self.computeFolds();
        try self.rebuildVisible();
    }

    /// Set content from raw JSON, formatted as kubectl-describe style.
    /// Set plain-text content (one entry per newline), no JSON parsing — for
    /// simple list overlays like the aliases view.
    pub fn setContentText(self: *DetailView, text: []const u8, title: []const u8) !void {
        self.clearContent();
        self.title = try self.allocator.dupe(u8, title);
        self.selected_row = 0;
        self.scroll_offset = 0;
        self.horizontal_scroll = 0;
        var it = std.mem.splitScalar(u8, text, '\n');
        while (it.next()) |line| {
            try self.lines.append(self.allocator, try self.allocator.dupe(u8, line));
        }
        try self.computeFolds();
        try self.rebuildVisible();
    }

    pub fn setContentDescribe(self: *DetailView, json_str: []const u8, title: []const u8) !void {
        self.clearContent();
        self.title = try self.allocator.dupe(u8, title);
        self.selected_row = 0;
        self.scroll_offset = 0;
        self.horizontal_scroll = 0;

        // Parse JSON and format as describe output
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{
            .ignore_unknown_fields = true,
            .allocate = .alloc_always,
        }) catch {
            // If JSON parsing fails, just show raw text line by line
            var line_iter = std.mem.splitScalar(u8, json_str, '\n');
            while (line_iter.next()) |line| {
                try self.lines.append(self.allocator, try self.allocator.dupe(u8, line));
            }
            try self.computeFolds();
            try self.rebuildVisible();
            return;
        };
        defer parsed.deinit();

        try self.formatDescribeValue(parsed.value, 0);
        try self.computeFolds();
        try self.rebuildVisible();
    }

    fn formatDescribeValue(self: *DetailView, value: std.json.Value, indent: usize) !void {
        // Create indent string
        var indent_buf: [128]u8 = undefined;
        const indent_len = @min(indent, 128);
        @memset(indent_buf[0..indent_len], ' ');
        const indent_str = indent_buf[0..indent_len];

        switch (value) {
            .object => |obj| {
                var it = obj.iterator();
                while (it.next()) |entry| {
                    const key = entry.key_ptr.*;
                    const val = entry.value_ptr.*;

                    switch (val) {
                        .object => {
                            const line = try std.fmt.allocPrint(self.allocator, "{s}{s}:", .{ indent_str, key });
                            try self.lines.append(self.allocator, line);
                            try self.formatDescribeValue(val, indent + 2);
                        },
                        .array => |arr| {
                            const line = try std.fmt.allocPrint(self.allocator, "{s}{s}:", .{ indent_str, key });
                            try self.lines.append(self.allocator, line);
                            for (arr.items) |item| {
                                try self.formatDescribeValue(item, indent + 2);
                            }
                        },
                        else => {
                            const val_str = try self.jsonValueToString(val);
                            defer self.allocator.free(val_str);
                            const line = try std.fmt.allocPrint(self.allocator, "{s}{s}: {s}", .{ indent_str, key, val_str });
                            try self.lines.append(self.allocator, line);
                        },
                    }
                }
            },
            .array => |arr| {
                for (arr.items) |item| {
                    try self.formatDescribeValue(item, indent + 2);
                }
            },
            else => {
                const val_str = try self.jsonValueToString(value);
                defer self.allocator.free(val_str);
                const line = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ indent_str, val_str });
                try self.lines.append(self.allocator, line);
            },
        }
    }

    fn jsonValueToString(self: *DetailView, value: std.json.Value) ![]u8 {
        return switch (value) {
            .string => |s| try self.allocator.dupe(u8, s),
            .integer => |i| try std.fmt.allocPrint(self.allocator, "{d}", .{i}),
            .float => |f| try std.fmt.allocPrint(self.allocator, "{d}", .{f}),
            .bool => |b| try self.allocator.dupe(u8, if (b) "true" else "false"),
            .null => try self.allocator.dupe(u8, "null"),
            else => try self.allocator.dupe(u8, "<complex>"),
        };
    }

    fn flushLine(self: *DetailView, line_buf: *std.ArrayListUnmanaged(u8)) !void {
        if (line_buf.items.len > 0) {
            try self.lines.append(self.allocator, try self.allocator.dupe(u8, line_buf.items));
            line_buf.clearRetainingCapacity();
        }
    }

    fn writeIndent(self: *DetailView, line_buf: *std.ArrayListUnmanaged(u8), indent: usize) !void {
        for (0..indent) |_| {
            try line_buf.append(self.allocator, ' ');
        }
    }

    // ===== Folding =====

    fn indentOf(line: []const u8) usize {
        return std.mem.indexOfNone(u8, line, " ") orelse line.len;
    }

    /// True if the line opens a foldable block (last non-space char is `{` or `[`).
    fn opensBlock(line: []const u8) bool {
        const t = std.mem.trimEnd(u8, line, " \t");
        return t.len > 0 and (t[t.len - 1] == '{' or t[t.len - 1] == '[');
    }

    /// Noisy openers collapsed by default: the `managedFields` apply-tracking
    /// tree and its `f:`/`k:` fieldsV1 entries (same churn kubectl hides).
    /// Tolerates both JSON (`"f:..."`) and describe/YAML (`f:...`) key styles.
    fn isNoisyOpener(line: []const u8) bool {
        var t = std.mem.trimStart(u8, line, " \t");
        if (t.len > 0 and t[0] == '"') t = t[1..]; // tolerate JSON quoting
        return std.mem.startsWith(u8, t, "f:") or
            std.mem.startsWith(u8, t, "k:") or
            std.mem.startsWith(u8, t, "managedFields");
    }

    /// The closing bracket char of a close line (`}` / `]`), or 0 if not a closer.
    fn closeBracketOf(line: []const u8) u8 {
        const t = std.mem.trimStart(u8, line, " \t");
        if (t.len > 0 and (t[0] == '}' or t[0] == ']')) return t[0];
        return 0;
    }

    /// Fill fold_end/folded (parallel to lines). An opener's match is the first
    /// later line at the SAME indent that begins with a closing bracket — which,
    /// for consistent 2-space pretty-printing, is exactly its block close.
    fn computeFolds(self: *DetailView) !void {
        const n = self.lines.items.len;
        try self.fold_end.ensureTotalCapacity(self.allocator, n);
        try self.folded.ensureTotalCapacity(self.allocator, n);
        self.fold_end.clearRetainingCapacity();
        self.folded.clearRetainingCapacity();
        for (0..n) |_| {
            self.fold_end.appendAssumeCapacity(null);
            self.folded.appendAssumeCapacity(false);
        }
        for (self.lines.items, 0..) |line, i| {
            const ind = indentOf(line);
            if (opensBlock(line)) {
                // JSON/braces: the block close is the first later line at the
                // SAME indent that begins with `}`/`]` — fold through it.
                var j = i + 1;
                while (j < n) : (j += 1) {
                    const lj = self.lines.items[j];
                    if (indentOf(lj) == ind) {
                        if (closeBracketOf(lj) != 0) self.fold_end.items[i] = @intCast(j);
                        break; // first same-indent line decides
                    }
                }
            } else if (closeBracketOf(line) == 0 and i + 1 < n and indentOf(self.lines.items[i + 1]) > ind) {
                // Describe/YAML (no braces): a key whose following lines are more
                // indented is a foldable parent. Fold through the contiguous run
                // of deeper-indented lines (there is no closing-bracket line).
                var j = i + 1;
                var last: u32 = @intCast(i);
                while (j < n and indentOf(self.lines.items[j]) > ind) : (j += 1) last = @intCast(j);
                if (last > i) self.fold_end.items[i] = last;
            }
            // Collapse noisy managedFields/fieldsV1 blocks by default.
            if (self.fold_end.items[i] != null and isNoisyOpener(line)) {
                self.folded.items[i] = true;
            }
        }
        try self.computeColumnStops();
    }

    /// Detect column-start offsets in space-aligned content (e.g. the aliases /
    /// api-resources table): a column starts where a non-space char follows a
    /// 2+ space gap, counted across lines and kept when common enough. Lets h/l
    /// jump column-to-column instead of one char at a time.
    fn computeColumnStops(self: *DetailView) !void {
        self.col_stops.clearRetainingCapacity();
        var counts = [_]u16{0} ** 256;
        var nonempty: u32 = 0;
        for (self.lines.items) |line| {
            if (std.mem.indexOfNone(u8, line, " ") == null) continue; // blank
            nonempty += 1;
            var i: usize = 2;
            while (i < line.len and i < 256) : (i += 1) {
                if (line[i] != ' ' and line[i - 1] == ' ' and line[i - 2] == ' ') counts[i] +|= 1;
            }
        }
        if (nonempty == 0) return;
        try self.col_stops.append(self.allocator, 0); // first column
        const thresh: u16 = @max(@as(u16, 3), @as(u16, @intCast(nonempty / 8)));
        var c: usize = 1;
        while (c < 256) : (c += 1) {
            if (counts[c] < thresh) continue;
            const last = self.col_stops.items[self.col_stops.items.len - 1];
            if (c > @as(usize, last) + 2) try self.col_stops.append(self.allocator, @intCast(c));
        }
    }

    /// Next/previous column offset relative to the current horizontal scroll.
    /// Falls back to a coarse step when no columns were detected (e.g. JSON).
    fn nextColStop(self: *DetailView) u16 {
        for (self.col_stops.items) |s| {
            if (s > self.horizontal_scroll) return s;
        }
        return self.horizontal_scroll +| 16;
    }

    fn prevColStop(self: *DetailView) u16 {
        var best: u16 = 0;
        for (self.col_stops.items) |s| {
            if (s < self.horizontal_scroll) best = s else break;
        }
        if (best == 0 and self.horizontal_scroll > 16) return self.horizontal_scroll - 16;
        return best;
    }

    /// Rebuild the visible-line projection from fold state.
    fn rebuildVisible(self: *DetailView) !void {
        self.visible.clearRetainingCapacity();
        var i: usize = 0;
        const n = self.lines.items.len;
        while (i < n) {
            try self.visible.append(self.allocator, @intCast(i));
            if (self.folded.items[i]) {
                if (self.fold_end.items[i]) |e| {
                    i = e + 1; // hide i+1..e (the opener shows a collapsed marker)
                    continue;
                }
            }
            i += 1;
        }
        if (self.visible.items.len == 0) {
            self.selected_row = 0;
        } else if (self.selected_row >= self.visible.items.len) {
            self.selected_row = @intCast(self.visible.items.len - 1);
        }
        self.clampScroll();
    }

    fn clampScroll(self: *DetailView) void {
        if (self.visible_rows == 0) return;
        if (self.selected_row < self.scroll_offset) {
            self.scroll_offset = self.selected_row;
        } else if (self.selected_row >= self.scroll_offset + self.visible_rows) {
            self.scroll_offset = self.selected_row - self.visible_rows + 1;
        }
    }

    fn toggleFoldAtCursor(self: *DetailView) !void {
        if (self.selected_row >= self.visible.items.len) return;
        const raw = self.visible.items[self.selected_row];
        if (self.fold_end.items[raw] == null) return; // not a foldable line
        self.folded.items[raw] = !self.folded.items[raw];
        try self.rebuildVisible();
    }

    /// Set the fold state of the block at the cursor to `value`. Returns true
    /// if the cursor line is foldable (whether or not the state changed), so
    /// callers can fall back to other behavior (e.g. horizontal scroll).
    fn setFoldAtCursor(self: *DetailView, value: bool) !bool {
        if (self.selected_row >= self.visible.items.len) return false;
        const raw = self.visible.items[self.selected_row];
        if (self.fold_end.items[raw] == null) return false; // not foldable
        if (self.folded.items[raw] != value) {
            self.folded.items[raw] = value;
            try self.rebuildVisible();
        }
        return true;
    }

    fn setAllFolds(self: *DetailView, value: bool) !void {
        if (!value) {
            // Unfold everything.
            for (self.folded.items, 0..) |*f, i| {
                if (self.fold_end.items[i] != null) f.* = false;
            }
        } else {
            // "Fold all" collapses to the TOP LEVEL (like IDE "collapse all"):
            // keep the outermost block (minimum opener indent, i.e. the root)
            // open so its top-level keys stay visible, and fold everything
            // nested below. Collapsing the root too would show just "{ ... }".
            var min_indent: usize = std.math.maxInt(usize);
            for (self.lines.items, 0..) |line, i| {
                if (self.fold_end.items[i] != null) {
                    const ind = indentOf(line);
                    if (ind < min_indent) min_indent = ind;
                }
            }
            for (self.folded.items, 0..) |*f, i| {
                if (self.fold_end.items[i] != null) {
                    f.* = indentOf(self.lines.items[i]) > min_indent;
                }
            }
        }
        // Keep the cursor on the same raw line if still visible; else clamp.
        try self.rebuildVisible();
    }

    // View trait implementation
    pub fn createView(self: *DetailView) View {
        return View.create(DetailView, self, &vtable);
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinitView,
    };

    // Fold-gutter / indent-guide glyphs (1 display cell each; same family as the
    // box-drawing chars the app already renders).
    const chevron_expanded = "\u{25BE}"; // ▾ foldable + expanded
    const chevron_collapsed = "\u{25B8}"; // ▸ foldable + collapsed
    const indent_rail = "\u{2502}"; // │ indent guide

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *DetailView = @ptrCast(@alignCast(ptr));
        self.visible_rows = if (height > 1) height - 1 else 0;
        self.render_x = x;
        self.render_y = y;

        if (self.visible.items.len == 0) {
            const Theme = theme_loader;
            try Theme.writeStringWithTheme(terminal, x, y, "No content", self.theme.inactive_fg, self.theme.main_bg);
            return;
        }

        const interior: u16 = if (width > 2) width - 2 else 1;
        const start_row = self.scroll_offset;
        const end_row = @min(start_row + self.visible_rows, self.visible.items.len);

        for (start_row..end_row, 0..) |vis_idx, display_idx| {
            const raw = self.visible.items[vis_idx];
            const line = self.lines.items[raw];
            const row_y = y + @as(u16, @intCast(display_idx));
            const selected = vis_idx == self.selected_row;
            const foldable = self.fold_end.items[raw] != null;
            const is_folded = foldable and self.folded.items[raw];

            // Color roles (selection overrides all three with the selection fg).
            const fg = if (selected) self.theme.selected_fg else self.theme.main_fg;
            const dim = if (selected) self.theme.selected_fg else self.theme.inactive_fg;
            const chev = if (selected) self.theme.selected_fg else self.theme.title_highlight;

            try terminal.setCursor(x, row_y);
            if (selected) try terminal.writeAll(self.theme.selected_bg);

            var cols: u16 = 0; // display columns written

            // Fold gutter (2 cols): chevron for foldable lines, blank otherwise.
            try terminal.writeAll(chev);
            if (cols < interior) {
                try terminal.writeAll(if (foldable) (if (is_folded) chevron_collapsed else chevron_expanded) else " ");
                cols += 1;
            }
            if (cols < interior) {
                try terminal.writeAll(" ");
                cols += 1;
            }

            // Indent-guide rails: one "│ " per 2-space indent level. Rendered
            // faint (SGR 2) so they recede behind the content — inactive_fg
            // alone reads too bright and competes with the text.
            const indent = indentOf(line);
            const depth = indent / 2;
            if (!selected) try terminal.writeAll("\x1b[2m");
            try terminal.writeAll(dim);
            var d: usize = 0;
            while (d < depth and cols + 2 <= interior) : (d += 1) {
                try terminal.writeAll(indent_rail);
                try terminal.writeAll(" ");
                cols += 2;
            }
            if (!selected) try terminal.writeAll("\x1b[22m"); // end faint before content

            // Line content (after its leading indent), with horizontal scroll.
            try terminal.writeAll(fg);
            const after_indent = line[@min(indent, line.len)..];
            const content = if (self.horizontal_scroll < after_indent.len)
                after_indent[self.horizontal_scroll..]
            else
                "";
            const room: u16 = if (interior > cols) interior - cols else 0;
            const clen = @min(content.len, @as(usize, room));
            if (clen > 0) {
                try terminal.writeAll(content[0..clen]);
                cols += @intCast(clen);
            }

            // Collapsed marker, derived from the OPENER: "...}"/"...]" for JSON
            // braces, " ..." for describe/YAML keys (which have no bracket).
            if (is_folded and cols < interior) {
                const ot = std.mem.trimEnd(u8, line, " \t");
                const last_ch: u8 = if (ot.len > 0) ot[ot.len - 1] else 0;
                const marker: []const u8 = switch (last_ch) {
                    '{' => "...}",
                    '[' => "...]",
                    else => " ...",
                };
                const mlen = @min(marker.len, @as(usize, interior - cols));
                try terminal.writeAll(marker[0..mlen]);
                cols += @intCast(mlen);
            }

            // Pad the rest so the selection bar spans the full interior width.
            if (selected) {
                while (cols < interior) : (cols += 1) try terminal.writeAll(" ");
            }
            try terminal.writeAll("\x1b[0m");
        }
    }

    fn moveDown(self: *DetailView) void {
        if (self.selected_row + 1 < self.visible.items.len) {
            self.selected_row += 1;
            if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }
    }

    fn moveUp(self: *DetailView) void {
        if (self.selected_row > 0) {
            self.selected_row -= 1;
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *DetailView = @ptrCast(@alignCast(ptr));
        const count: u32 = @intCast(self.visible.items.len);

        switch (key) {
            .char => |c| switch (c) {
                'j' => {
                    self.moveDown();
                    return .handled;
                },
                'k' => {
                    self.moveUp();
                    return .handled;
                },
                'g' => {
                    self.selected_row = 0;
                    self.scroll_offset = 0;
                    return .handled;
                },
                'h' => {
                    self.horizontal_scroll = self.prevColStop();
                    return .handled;
                },
                'l' => {
                    self.horizontal_scroll = self.nextColStop();
                    return .handled;
                },
                // Folding: Space toggles the block at the cursor; c folds all, o unfolds all.
                ' ' => {
                    try self.toggleFoldAtCursor();
                    return .handled;
                },
                'c' => {
                    try self.setAllFolds(true);
                    return .handled;
                },
                'o' => {
                    try self.setAllFolds(false);
                    return .handled;
                },
                'f' => return .request_fullscreen,
                else => return .not_handled,
            },
            .enter => {
                try self.toggleFoldAtCursor();
                return .handled;
            },
            .mouse => |m| {
                // Map screen coords -> visible row. Clicking a foldable line
                // toggles its fold (the chevron); any click also moves selection.
                if (m.y < self.render_y) return .not_handled;
                const display_idx: u32 = m.y - self.render_y;
                if (display_idx >= self.visible_rows) return .not_handled;
                const vis_idx = self.scroll_offset + display_idx;
                if (vis_idx >= self.visible.items.len) return .not_handled;
                self.selected_row = vis_idx;
                const raw = self.visible.items[vis_idx];
                if (self.fold_end.items[raw] != null) {
                    try self.toggleFoldAtCursor();
                }
                return .handled;
            },
            .up => {
                self.moveUp();
                return .handled;
            },
            .down => {
                self.moveDown();
                return .handled;
            },
            .left => {
                // Collapse the block at the cursor (IDE-style); on non-foldable
                // lines, move one column left (snaps to detected column stops).
                if (!(try self.setFoldAtCursor(true))) self.horizontal_scroll = self.prevColStop();
                return .handled;
            },
            .right => {
                // Expand the block at the cursor; else move one column right.
                if (!(try self.setFoldAtCursor(false))) self.horizontal_scroll = self.nextColStop();
                return .handled;
            },
            .shift_g => {
                if (count > 0) {
                    self.selected_row = count - 1;
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
                if (self.selected_row + self.visible_rows < count) {
                    self.selected_row += self.visible_rows;
                    if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                } else if (count > 0) {
                    self.selected_row = count - 1;
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
                if (count > 0) {
                    self.selected_row = count - 1;
                    if (self.selected_row >= self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .escape => return .not_handled, // Let parent handle pop
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("DetailView: View activated", .{});
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
        Logger.info("DetailView: View deactivated", .{});
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "detail";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.detailHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *DetailView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

test "DetailView fold: collapse and expand a JSON block" {
    const testing = std.testing;
    var theme = try theme_loader.defaultTheme(testing.allocator);
    defer theme_loader.deinitTheme(&theme);

    var dv = try DetailView.init(testing.allocator, &theme);
    defer dv.deinit();

    try dv.setContentJson(
        \\{"metadata":{"name":"x","labels":{"a":"b"}},"spec":{"n":1}}
    , "pod");

    // All expanded initially: every produced line is visible.
    try testing.expectEqual(dv.lines.items.len, dv.visible.items.len);
    const full = dv.visible.items.len;

    // The root line (index 0) opens a block and must have a matching close.
    try testing.expect(dv.fold_end.items[0] != null);

    // Fold all collapses to the TOP LEVEL: far fewer visible lines, but the
    // root block (index 0) stays OPEN so its top-level keys remain visible
    // (each itself folded) — not collapsed to a lone "{ ... }".
    try dv.setAllFolds(true);
    try testing.expect(dv.visible.items.len < full);
    try testing.expect(!dv.folded.items[0]); // root stays open
    try testing.expect(dv.visible.items.len >= 3); // root + >=1 top-level key + close

    // Unfold everything: back to the full set.
    try dv.setAllFolds(false);
    try testing.expectEqual(full, dv.visible.items.len);

    // Toggle the block at the cursor (root) collapses to a single visible line.
    dv.selected_row = 0;
    try dv.toggleFoldAtCursor();
    try testing.expectEqual(@as(usize, 1), dv.visible.items.len);
}

test "DetailView fold: managedFields/f: noise is collapsed by default" {
    const testing = std.testing;
    var theme = try theme_loader.defaultTheme(testing.allocator);
    defer theme_loader.deinitTheme(&theme);

    var dv = try DetailView.init(testing.allocator, &theme);
    defer dv.deinit();

    try dv.setContentJson(
        \\{"metadata":{"managedFields":[{"fieldsV1":{"f:spec":{"f:x":{}}}}]},"spec":{"n":1}}
    , "pod");

    // At least one opener is folded by default (the managedFields/f: noise),
    // so fewer lines are visible than total.
    var any_default_fold = false;
    for (dv.folded.items) |f| {
        if (f) any_default_fold = true;
    }
    try testing.expect(any_default_fold);
    try testing.expect(dv.visible.items.len < dv.lines.items.len);
}

test "DetailView fold: describe (indent-based, no braces) is foldable" {
    const testing = std.testing;
    var theme = try theme_loader.defaultTheme(testing.allocator);
    defer theme_loader.deinitTheme(&theme);

    var dv = try DetailView.init(testing.allocator, &theme);
    defer dv.deinit();

    // Describe output is YAML-style (key: with indentation, no { } [ ]).
    try dv.setContentDescribe(
        \\{"metadata":{"name":"x","labels":{"a":"b"}},"spec":{"n":1}}
    , "pod");

    // Indent nesting alone must still produce foldable openers.
    var any_foldable = false;
    for (dv.fold_end.items) |fe| {
        if (fe != null) any_foldable = true;
    }
    try testing.expect(any_foldable);

    // Collapsing to the top level hides nested lines.
    const full = dv.visible.items.len;
    try dv.setAllFolds(true);
    try testing.expect(dv.visible.items.len < full);
}

test "DetailView: column-aligned content yields column stops for h/l nav" {
    const testing = std.testing;
    var theme = try theme_loader.defaultTheme(testing.allocator);
    defer theme_loader.deinitTheme(&theme);

    var dv = try DetailView.init(testing.allocator, &theme);
    defer dv.deinit();

    try dv.setContentText(
        \\NAME          SHORTNAMES    APIVERSION
        \\pods          po            v1
        \\configmaps    cm            v1
    , "Aliases");

    // Detected at least the first column + one more (the gapped columns).
    try testing.expect(dv.col_stops.items.len >= 2);
    // h/l jumps a whole column, not one character.
    dv.horizontal_scroll = 0;
    try testing.expect(dv.nextColStop() > 1);
}
