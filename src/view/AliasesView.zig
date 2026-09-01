/// Aliases view (k9s Ctrl-A): a REAL table view over `kubectl api-resources`.
///
/// Renders identically to the resource tables (no leading chevron/indent
/// column, full-width selection bar, codepoint-safe truncation, working
/// `/filter`, k9s-style title) by reusing the shared rendering helpers:
/// `TableState`, `table_layout.calculateColumnWidths`/`utf8TruncateCols`, and
/// `Terminal.fillRow`. It is NOT a klient resource, so it is built bespoke,
/// but the render path mirrors `resource_view.zig` cell-for-cell.
const std = @import("std");
const view_mod = @import("../viewmodel/view.zig");
const View = view_mod.View;
const KeyResult = View.KeyResult;
const Key = @import("../core/Terminal.zig").Key;
const Terminal = @import("../core/Terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const hints_model = @import("../model/hints.zig");
const K8sService = @import("../services/K8sService.zig").K8sService;
const Logger = @import("../core/logger.zig");
const TableState = @import("../ui/TableState.zig").TableState;
const table_layout = @import("../ui/table_layout.zig");

const col_count = 5;
const COL_NAME = 0;
const COL_SHORTNAMES = 1;
const COL_APIVERSION = 2;
const COL_NAMESPACED = 3;
const COL_KIND = 4;

pub const AliasesView = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(Row),
    cached_col_widths: ?table_layout.ColumnWidths = null,
    cached_terminal_width: u16 = 0,
    /// Scratch buffer for the decorated box title ("aliases[123]").
    title_buf: [192]u8 = undefined,

    /// One api-resource row: NAME, SHORTNAMES, APIVERSION, NAMESPACED, KIND.
    /// Each cell is owned (duped) by the TableState allocator.
    pub const Row = struct {
        cols: [col_count][]const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Row) void {
            for (&self.cols) |*c| self.allocator.free(c.*);
        }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !Self {
        return Self{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(Row).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.cached_col_widths) |*w| w.deinit();
        self.table.deinit();
    }

    /// Parse `kubectl api-resources` text into rows. The output is
    /// whitespace-aligned with a header line (NAME SHORTNAMES APIVERSION
    /// NAMESPACED KIND). SHORTNAMES may be empty for a given resource; we map
    /// columns positionally by the header's column start offsets so an empty
    /// SHORTNAMES doesn't shift APIVERSION/etc. left.
    pub fn refresh(self: *Self) !void {
        self.table.loading = true;
        defer self.table.loading = false;
        self.table.clearItems();

        if (self.cached_col_widths) |*w| {
            w.deinit();
            self.cached_col_widths = null;
        }

        const raw = self.k8s_service.listApiResources() catch |err| {
            try self.table.setConnectionError("api-resources", err);
            return;
        };
        defer self.allocator.free(raw);

        var lines = std.mem.splitScalar(u8, raw, '\n');
        const header = lines.next() orelse return;
        // Column start offsets are derived from the header so positional
        // parsing tolerates an empty SHORTNAMES column.
        const offsets = headerOffsets(header);

        while (lines.next()) |line| {
            if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
            const cells = sliceColumns(line, offsets);
            var row = Row{ .cols = undefined, .allocator = self.table.allocator };
            var dup_idx: usize = 0;
            errdefer {
                for (row.cols[0..dup_idx]) |c| self.table.allocator.free(c);
            }
            while (dup_idx < col_count) : (dup_idx += 1) {
                row.cols[dup_idx] = try self.table.allocator.dupe(u8, cells[dup_idx]);
            }
            try self.table.appendItem(row);
        }

        try self.applyFilter(self.table.filter_text);
    }

    /// Derive the start column (byte offset) of each of the 5 fields from the
    /// header line by locating each header label. Falls back to whitespace
    /// splitting on any miss.
    const Offsets = struct {
        starts: [col_count]usize,
        ok: bool,
    };

    fn headerOffsets(header: []const u8) Offsets {
        const labels = [_][]const u8{ "NAME", "SHORTNAMES", "APIVERSION", "NAMESPACED", "KIND" };
        var starts: [col_count]usize = undefined;
        var search_from: usize = 0;
        for (labels, 0..) |label, i| {
            const idx = std.mem.indexOfPos(u8, header, search_from, label) orelse {
                return .{ .starts = starts, .ok = false };
            };
            starts[i] = idx;
            search_from = idx + label.len;
        }
        return .{ .starts = starts, .ok = true };
    }

    /// Slice a data line into 5 trimmed fields using the header offsets. Each
    /// field spans [start[i], start[i+1]) (last field runs to EOL). If the
    /// header offsets could not be derived, fall back to whitespace splitting.
    fn sliceColumns(line: []const u8, offsets: Offsets) [col_count][]const u8 {
        var out: [col_count][]const u8 = .{ "", "", "", "", "" };
        if (offsets.ok) {
            inline for (0..col_count) |i| {
                const start = @min(offsets.starts[i], line.len);
                const end = if (i + 1 < col_count)
                    @min(offsets.starts[i + 1], line.len)
                else
                    line.len;
                out[i] = std.mem.trim(u8, line[start..end], " \t\r");
            }
            return out;
        }
        // Fallback: split on runs of whitespace (loses an empty SHORTNAMES,
        // but only triggers if the header was unrecognizable).
        var it = std.mem.tokenizeAny(u8, line, " \t\r");
        var n: usize = 0;
        while (n < col_count) : (n += 1) {
            out[n] = it.next() orelse "";
        }
        return out;
    }

    pub fn applyFilter(self: *Self, filter: []const u8) !void {
        if (self.cached_col_widths) |*w| {
            w.deinit();
            self.cached_col_widths = null;
        }
        try self.table.applyFilter(filter, matchFn);
    }

    /// Case-insensitive substring match on NAME, SHORTNAMES, APIVERSION, or
    /// KIND (APIVERSION included so a filter like "beta" matches v1beta1 APIs).
    fn matchFn(item: *const Row, filter: []const u8) bool {
        return containsIgnoreCase(item.cols[COL_NAME], filter) or
            containsIgnoreCase(item.cols[COL_SHORTNAMES], filter) or
            containsIgnoreCase(item.cols[COL_APIVERSION], filter) or
            containsIgnoreCase(item.cols[COL_KIND], filter);
    }

    fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len == 0) return true;
        if (needle.len > haystack.len) return false;
        var i: usize = 0;
        outer: while (i + needle.len <= haystack.len) : (i += 1) {
            for (needle, 0..) |nc, j| {
                if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(nc)) continue :outer;
            }
            return true;
        }
        return false;
    }

    pub fn createView(self: *Self) View {
        return View.create(Self, self, &vtable);
    }

    // ========================================================================
    // Render — mirrors resource_view.zig render exactly.
    // ========================================================================

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const allocator = self.table.allocator;

        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(terminal, x, y, self.theme)) return;

        if (self.table.filtered_indices.items.len == 0) {
            const msg = if (self.table.items.items.len == 0)
                "No aliases"
            else
                "No matching aliases";
            try Theme.writeStringWithTheme(terminal, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        const layout_columns = [col_count]table_layout.ColumnInfo{
            .{ .name = "NAME", .min_width = 16, .max_width = null, .priority = table_layout.ColumnPriority.CRITICAL },
            .{ .name = "SHORTNAMES", .min_width = 8, .max_width = 16, .priority = table_layout.ColumnPriority.MEDIUM },
            .{ .name = "APIVERSION", .min_width = 14, .max_width = null, .priority = table_layout.ColumnPriority.HIGH },
            .{ .name = "NAMESPACED", .min_width = 8, .max_width = 12, .priority = table_layout.ColumnPriority.MEDIUM },
            .{ .name = "KIND", .min_width = 10, .max_width = 24, .priority = table_layout.ColumnPriority.MEDIUM },
        };
        const col_names = [col_count][]const u8{ "NAME", "SHORTNAMES", "APIVERSION", "NAMESPACED", "KIND" };

        const available_width = width;
        const use_cache = self.cached_col_widths != null and self.cached_terminal_width == available_width;

        const col_widths = if (use_cache) blk: {
            break :blk &self.cached_col_widths.?;
        } else blk: {
            var rows_data = try std.ArrayList([]const []const u8).initCapacity(allocator, self.table.filtered_indices.items.len);
            defer rows_data.deinit(allocator);

            for (self.table.filtered_indices.items) |item_idx| {
                // Point into the stable items backing array (not a loop-local
                // copy) — see resource_view.zig for why this matters.
                const item: *const Row = &self.table.items.items[item_idx];
                try rows_data.append(allocator, &item.cols);
            }

            if (self.cached_col_widths) |*old_widths| {
                old_widths.deinit();
            }

            self.cached_col_widths = try table_layout.calculateColumnWidths(
                allocator,
                &col_names,
                rows_data.items,
                &layout_columns,
                available_width,
            );
            self.cached_terminal_width = available_width;
            break :blk &self.cached_col_widths.?;
        };

        const eff_widths = col_widths.widths;

        // Header.
        {
            var col_x = x;
            const hdr_max_x = x + width;
            for (col_names, eff_widths[0..col_count]) |name, w| {
                if (w == 0) continue;
                if (col_x >= hdr_max_x) break;
                try Theme.writeStringWithTheme(terminal, col_x, y, table_layout.utf8TruncateCols(name, w), self.theme.title, self.theme.main_bg);
                col_x += w;
            }
        }

        // Data rows.
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |item_idx, i| {
            const item = self.table.items.items[item_idx];
            const row_y = y + 1 + @as(u16, @intCast(i));

            // Selection = full-width bar via the shared rowColors helper.
            const colors = self.table.rowColors(i, self.theme);
            const fg = colors.fg;
            const bg = colors.bg;

            // Full-width row bg first (clean selection bar with no seams), then
            // cell text on top with the same bg.
            try terminal.fillRow(x, row_y, width, fg, bg);

            var rx = x;
            const max_x = x + width;
            for (&item.cols, eff_widths[0..col_count]) |cell, w| {
                if (w == 0) continue;
                if (rx >= max_x) break;
                const avail = max_x - rx;
                const col_w = @min(w, avail);
                try Theme.writeStringWithTheme(terminal, rx, row_y, table_layout.utf8TruncateCols(cell, col_w -| 1), fg, bg);
                rx += w;
            }
        }
    }

    // ========================================================================
    // Key handling
    // ========================================================================

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));

        if (self.table.handleNavigationKey(key)) |result| return result;

        switch (key) {
            .ctrl_r => {
                self.refresh() catch |err| Logger.err("Failed to refresh aliases: {}", .{err});
                return .handled;
            },
            .char => |c| {
                if (c == 'r') {
                    self.refresh() catch |err| Logger.err("Failed to refresh aliases: {}", .{err});
                    return .handled;
                }
                return .not_handled;
            },
            else => return .not_handled,
        }
    }

    // ========================================================================
    // VTable
    // ========================================================================

    fn onShow(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.table.items.items.len > 0) return;
        self.refresh() catch |err| {
            Logger.err("Failed to refresh aliases: {}", .{err});
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "aliases";
    }

    /// k9s-style decorated title: "aliases[<count>]", with a trailing filter
    /// indicator " </{filter}>" when a filter is active (consistent with the
    /// resource tables and PodsView).
    fn getTitle(ptr: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const count = self.table.filtered_indices.items.len;
        if (self.table.filter_text.len > 0) {
            return std.fmt.bufPrint(&self.title_buf, "aliases[{d}] </{s}>", .{ count, self.table.filter_text }) catch "aliases";
        }
        return std.fmt.bufPrint(&self.title_buf, "aliases[{d}]", .{count}) catch "aliases";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?view_mod.ResourceInfo {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const item = self.table.getSelectedItem() orelse return null;
        return view_mod.ResourceInfo{ .name = item.cols[COL_NAME], .namespace = "cluster" };
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
        .refresh = vtableRefresh,
        .getSelectedResource = vtableGetSelectedResource,
    };
};
