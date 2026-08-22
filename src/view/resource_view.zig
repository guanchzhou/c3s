/// Generic Resource View - generates a complete View type from declarative config.
/// Replaces 25+ individual view files with one comptime template.
const std = @import("std");
const klient = @import("klient");
const view_mod = @import("../viewmodel/view.zig");
const View = view_mod.View;
const KeyResult = View.KeyResult;
const Key = @import("../core/Terminal.zig").Key;
const Terminal = @import("../core/Terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const hints_model = @import("../model/hints.zig");
const k8s_service_mod = @import("../services/K8sService.zig");
const K8sService = k8s_service_mod.K8sService;
const Logger = @import("../core/logger.zig");
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");
const TableState = @import("../ui/TableState.zig").TableState;
const table_layout = @import("../ui/table_layout.zig");
const PodMetric = @import("../services/k8s_types.zig").PodMetric;

/// Column definition for a resource view
pub const ColumnDef = struct {
    name: []const u8,
    min_width: u16 = 10,
    max_width: ?u16 = null, // null = unbounded (grows to fill)
    priority: u8 = table_layout.ColumnPriority.MEDIUM,
    sort_key: ?u8 = null, // keyboard char to trigger sort on this column (e.g., 'N', 'A')
    searchable: bool = false, // included in filter matching
};

/// Configuration for a resource view
pub const Config = struct {
    name: []const u8, // view name returned by getName() e.g., "deployments"
    columns: []const ColumnDef,
    is_namespaced: bool,
    default_all_namespaces: bool = false,
    name_column: u8, // index of resource name column
    namespace_column: ?u8 = null, // index of namespace column (null for cluster-scoped)
    /// When set, after the transform loop the cpu/mem columns at these indices
    /// are overwritten with live pod metrics from the metrics server (keyed
    /// "<namespace>/<name>"). Inert for every view that leaves this null.
    ///
    /// `cpu_pct`/`mem_pct`, when set, are %-of-request columns (k9s %CPU/R,
    /// %MEM/R). The transform writes the summed container request into these
    /// cells as a plain integer (millicores / bytes); the metrics hook then
    /// rewrites each cell to "<pct>" (usage*100/request) when metrics exist, or
    /// "n/a" otherwise — so the raw request integer never reaches the display.
    metrics_columns: ?struct {
        cpu: u8,
        mem: u8,
        cpu_pct: ?u8 = null,
        mem_pct: ?u8 = null,
    } = null,
};

/// Generate a complete View type for a Kubernetes resource.
///
/// Parameters:
/// - KlientType: the klient API type (e.g., klient.types.Deployment)
/// - KlientResourceType: the klient resource client (e.g., klient.resources.Deployments)
/// - config: declarative view configuration
/// - transformFn: converts a klient item to an array of display strings
pub fn ResourceView(
    comptime KlientType: type,
    comptime KlientResourceType: type,
    comptime config: Config,
    comptime transformFn: fn (KlientType, std.mem.Allocator) anyerror![config.columns.len][]const u8,
) type {
    const col_count = config.columns.len;

    return struct {
        const Self = @This();

        /// The view's Config, exposed so tests can check that what a view advertises
        /// (sort keys, columns) matches what it can actually do. ~14 advertised sort
        /// keys pointed at columns with no sort_key and nothing noticed.
        pub const view_config = config;

        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
        table: TableState(RowData),
        cached_col_widths: ?table_layout.ColumnWidths = null,
        cached_terminal_width: u16 = 0,
        /// Cached widths bake in whether NAMESPACE is hidden, so the cache is
        /// only valid while the namespace scope is unchanged.
        cached_show_all: bool = false,
        /// Scratch buffer for the decorated box title ("pods(default)[8]").
        title_buf: [192]u8 = undefined,

        /// Row data: uniform array of display strings
        pub const RowData = struct {
            columns: [col_count][]const u8,
            allocator: std.mem.Allocator,

            pub fn deinit(self: *RowData) void {
                for (&self.columns) |*col| {
                    self.allocator.free(col.*);
                }
            }

            /// Get column value by index (used for sorting)
            fn getColumn(comptime idx: comptime_int) fn (*const RowData) []const u8 {
                return struct {
                    fn get(row: *const RowData) []const u8 {
                        return row.columns[idx];
                    }
                }.get;
            }

            /// Runtime-indexed accessor, so sorting needs one std.sort.pdq
            /// instantiation per view rather than one per (view, column).
            fn getColumnAt(row: *const RowData, idx: usize) []const u8 {
                return row.columns[idx];
            }
        };

        pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !Self {
            var tbl = TableState(RowData).init(allocator);
            if (config.default_all_namespaces) tbl.show_all_namespaces = true;
            return Self{
                .theme = theme,
                .k8s_service = k8s_service,
                .table = tbl,
            };
        }

        pub fn deinit(self: *Self) void {
            if (self.cached_col_widths) |*w| w.deinit();
            self.table.deinit();
        }

        pub fn refresh(self: *Self) !void {
            // If connection not yet attempted, stay in loading state
            if (!self.k8s_service.isConnected() and !self.k8s_service.hasAttemptedConnect()) {
                self.table.loading = true;
                return;
            }

            self.table.loading = true;
            defer self.table.loading = false;
            self.table.clearItems();

            // Invalidate column width cache on refresh
            if (self.cached_col_widths) |*w| {
                w.deinit();
                self.cached_col_widths = null;
            }

            if (!self.k8s_service.isConnected()) {
                try self.table.setError("Not connected to Kubernetes cluster");
                return;
            }

            // Fetch items via k8s_service — ParsedList keeps JSON alive during transform
            var parsed_list = if (config.is_namespaced and !self.table.show_all_namespaces)
                self.k8s_service.listInNsGenericPub(KlientType, KlientResourceType, null) catch |err| {
                    try self.table.setConnectionError(config.name, err);
                    return;
                }
            else
                self.k8s_service.listAllGenericPub(KlientType, KlientResourceType) catch |err| {
                    try self.table.setConnectionError(config.name, err);
                    return;
                };
            defer parsed_list.deinit();

            // Transform each item to display strings (items valid until parsed_list.deinit)
            for (parsed_list.items()) |item| {
                const cols = transformFn(item, self.table.allocator) catch |err| {
                    Logger.err("Failed to transform {s} item: {}", .{ config.name, err });
                    continue;
                };
                try self.table.appendItem(.{
                    .columns = cols,
                    .allocator = self.table.allocator,
                });
            }

            // Overwrite the cpu/mem placeholder columns with live metrics, when
            // the config opts in. The metrics server is optional: on any error
            // the map is treated as absent. cpu/mem placeholders are left as-is
            // when a pod has no metrics; %-of-request cells are always rewritten
            // (to "<pct>" or "n/a") so the raw request integer the transform
            // stored there never reaches the display.
            if (config.metrics_columns) |mc| {
                var maybe_map: ?std.StringHashMap(PodMetric) =
                    self.k8s_service.getPodMetrics(self.table.show_all_namespaces) catch null;
                defer if (maybe_map) |*m| self.k8s_service.freePodMetrics(m);

                const alloc = self.table.allocator;
                for (self.table.items.items) |*row| {
                    const ns = row.columns[config.namespace_column.?];
                    const nm = row.columns[config.name_column];
                    var keybuf: [512]u8 = undefined;
                    const key = std.fmt.bufPrint(&keybuf, "{s}/{s}", .{ ns, nm }) catch continue;
                    const pm: ?PodMetric =
                        if (maybe_map) |*m| m.get(key) else null;

                    if (pm) |metric| {
                        // Both cells are duped before either old value is freed: the
                        // previous order freed cpu AND mem up front, so a failure on
                        // the first dupe left two dangling column pointers that the
                        // row's own cleanup would free again. The %-columns just below
                        // already got this ordering right.
                        const new_cpu = try alloc.dupe(u8, metric.cpu);
                        errdefer alloc.free(new_cpu);
                        const new_mem = try alloc.dupe(u8, metric.mem);

                        alloc.free(row.columns[mc.cpu]);
                        alloc.free(row.columns[mc.mem]);
                        row.columns[mc.cpu] = new_cpu;
                        row.columns[mc.mem] = new_mem;
                    }

                    if (mc.cpu_pct) |ci| {
                        const req = std.fmt.parseInt(u64, row.columns[ci], 10) catch 0;
                        const cell = if (pm != null and req > 0)
                            try std.fmt.allocPrint(alloc, "{d}", .{pm.?.cpu_milli * 100 / req})
                        else
                            try alloc.dupe(u8, "n/a");
                        alloc.free(row.columns[ci]);
                        row.columns[ci] = cell;
                    }
                    if (mc.mem_pct) |mi| {
                        const req = std.fmt.parseInt(u64, row.columns[mi], 10) catch 0;
                        const cell = if (pm != null and req > 0)
                            try std.fmt.allocPrint(alloc, "{d}", .{pm.?.mem_bytes * 100 / req})
                        else
                            try alloc.dupe(u8, "n/a");
                        alloc.free(row.columns[mi]);
                        row.columns[mi] = cell;
                    }
                }
            }

            try self.applyFilter(self.table.filter_text);
        }

        pub fn getSelectedResourceInfo(self: *Self) ?view_mod.ResourceInfo {
            const item = self.table.getSelectedItem() orelse return null;
            return view_mod.ResourceInfo{
                .name = item.columns[config.name_column],
                .namespace = if (config.namespace_column) |ns_col|
                    item.columns[ns_col]
                else
                    "cluster",
            };
        }

        pub fn applyFilter(self: *Self, filter: []const u8) !void {
            // Invalidate column width cache when filter changes
            if (self.cached_col_widths) |*w| {
                w.deinit();
                self.cached_col_widths = null;
            }
            try self.table.applyFilter(filter, matchFn);
            self.applySorting();
        }

        /// Bulk mark operations over the currently-filtered rows.
        /// `.all` marks every filtered row (idempotent); `.invert` toggles each.
        /// Clearing is `table.clearMarks()` directly. toggleMark dupes the key,
        /// so reusing one stack buffer across rows is safe.
        const MarkOp = enum { all, invert };
        fn applyMarkOp(self: *Self, op: MarkOp) void {
            var key_buf: [512]u8 = undefined;
            for (self.table.filtered_indices.items) |idx| {
                const item: *const RowData = &self.table.items.items[idx];
                const key = rowKey(item, &key_buf);
                switch (op) {
                    .all => if (!self.table.isMarked(key)) {
                        self.table.toggleMark(key) catch |err|
                            Logger.err("Failed to mark row in {s}: {}", .{ config.name, err });
                    },
                    .invert => self.table.toggleMark(key) catch |err|
                        Logger.err("Failed to invert mark in {s}: {}", .{ config.name, err }),
                }
            }
        }

        fn applySorting(self: *Self) void {
            if (self.table.sort_column) |col| {
                if (col < col_count) {
                    self.table.sortByColumn(&RowData.getColumnAt, col);
                }
            }
        }

        fn matchFn(item: *const RowData, filter: []const u8) bool {
            // Search only columns marked as searchable
            inline for (config.columns, 0..) |col_def, idx| {
                if (col_def.searchable) {
                    if (std.mem.indexOf(u8, item.columns[idx], filter) != null) return true;
                }
            }
            return false;
        }

        pub fn createView(self: *Self) View {
            return View.create(Self, self, &vtable);
        }

        // ====================================================================
        // Render
        // ====================================================================

        fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const allocator = self.table.allocator;

            self.table.visible_rows = if (height > 1) height - 1 else 0;

            if (try self.table.renderStatus(terminal, x, y, self.theme)) return;

            if (self.table.filtered_indices.items.len == 0) {
                const msg = if (self.table.items.items.len == 0)
                    "No " ++ config.name ++ " found"
                else
                    "No matching " ++ config.name;
                try Theme.writeStringWithTheme(terminal, x, y, msg, self.theme.main_fg, self.theme.main_bg);
                return;
            }

            // Build column layout info from config
            var layout_columns: [col_count]table_layout.ColumnInfo = undefined;
            inline for (config.columns, 0..) |col_def, idx| {
                layout_columns[idx] = .{
                    .name = col_def.name,
                    .min_width = col_def.min_width,
                    .max_width = col_def.max_width,
                    .priority = col_def.priority,
                };
            }

            // Column header names
            var col_names: [col_count][]const u8 = undefined;
            inline for (config.columns, 0..) |col_def, idx| {
                col_names[idx] = col_def.name;
            }

            const available_width = width;

            // When scoped to a single namespace the NAMESPACE column is redundant
            // (every row shares it), so mark it force-hidden: the width calc gives
            // it 0 and excludes it from the budget — its space is absorbed by the
            // highest-priority column (NAME). Excluding it from the budget (rather
            // than zeroing it after the fact) is what keeps a low-priority column
            // like CPU from being needlessly dropped to make room for a NAMESPACE
            // column that is not even shown. Mirrors k9s.
            var force_hidden: [col_count]bool = undefined;
            @memset(&force_hidden, false);
            const hide_ns = config.is_namespaced and !self.table.show_all_namespaces;
            if (hide_ns) {
                if (config.namespace_column) |ns_col| force_hidden[ns_col] = true;
            }

            const use_cache = self.cached_col_widths != null and
                self.cached_terminal_width == available_width and
                self.cached_show_all == self.table.show_all_namespaces;

            const col_widths = if (use_cache) blk: {
                break :blk &self.cached_col_widths.?;
            } else blk: {
                // Build rows data for width calculation
                var rows_data = try std.ArrayList([]const []const u8).initCapacity(allocator, self.table.filtered_indices.items.len);
                defer rows_data.deinit(allocator);

                for (self.table.filtered_indices.items) |item_idx| {
                    // Point into the stable items backing array, NOT a loop-local
                    // copy: `&item.columns` on a by-value copy aliases one stack
                    // slot, so every row would carry the last item's values and
                    // collapse column widths to the header width.
                    const item: *const RowData = &self.table.items.items[item_idx];
                    try rows_data.append(allocator, &item.columns);
                }

                // Compute the new widths first. Deinit-ing the cache and then hitting
                // a failure left cached_col_widths pointing at freed memory, and the
                // use_cache check above would hand that back on the next redraw.
                const new_widths = try table_layout.calculateColumnWidthsHidden(
                    allocator,
                    &col_names,
                    rows_data.items,
                    &layout_columns,
                    available_width,
                    &force_hidden,
                );

                // Swap only after the new value exists.
                if (self.cached_col_widths) |*old_widths| {
                    old_widths.deinit();
                }
                self.cached_col_widths = new_widths;
                self.cached_terminal_width = available_width;
                self.cached_show_all = self.table.show_all_namespaces;
                break :blk &self.cached_col_widths.?;
            };

            // The masked width calc already gave NAMESPACE width 0 (in single-ns
            // scope) and handed its space to NAME, so the rendered widths are the
            // computed widths verbatim.
            const eff_widths = col_widths.widths;

            // Render header using runtime loop (widths are runtime values)
            {
                const col_defs = comptime blk: {
                    var defs: [col_count]struct { name: []const u8, has_sort: bool, sort_col: u8 } = undefined;
                    for (config.columns, 0..) |cd, ci| {
                        defs[ci] = .{
                            .name = cd.name,
                            .has_sort = cd.sort_key != null,
                            .sort_col = @intCast(ci),
                        };
                    }
                    break :blk defs;
                };

                var col_x = x;
                const hdr_max_x = x + width;
                for (col_defs, eff_widths[0..]) |cd, w| {
                    if (w == 0) continue;
                    if (col_x >= hdr_max_x) break;
                    const hdr_avail = hdr_max_x - col_x;
                    const hdr_w = @min(w, hdr_avail);
                    _ = hdr_w;
                    if (cd.has_sort) {
                        const indicator = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, cd.sort_col);
                        var hdr_buf: [64]u8 = undefined;
                        const hdr = std.fmt.bufPrint(&hdr_buf, "{s}{s}", .{ cd.name, indicator }) catch cd.name;
                        try Theme.writeStringWithTheme(terminal, col_x, y, table_layout.utf8TruncateCols(hdr, w), self.theme.title, self.theme.main_bg);
                    } else {
                        try Theme.writeStringWithTheme(terminal, col_x, y, table_layout.utf8TruncateCols(cd.name, w), self.theme.title, self.theme.main_bg);
                    }
                    col_x += w;
                }
            }

            // Render data rows
            const range = self.table.getVisibleRange();
            for (self.table.filtered_indices.items[range.start..range.end], 0..) |item_idx, i| {
                const item = self.table.items.items[item_idx];
                const is_selected = self.table.isSelected(i);
                const row_y = y + 1 + @as(u16, @intCast(i));

                // Determine the marked state from a stable row identity key.
                var key_buf: [512]u8 = undefined;
                const key = rowKey(&item, &key_buf);
                const is_marked = self.table.isMarked(key);

                // Row colors: selection wins for fg/bg; a marked-but-unselected
                // row gets a distinct bg so the mark persists as the cursor moves.
                const fg: []const u8 = if (is_selected)
                    self.theme.selected_fg
                else if (is_marked)
                    self.theme.title_highlight
                else
                    self.theme.main_fg;
                const bg: []const u8 = if (is_selected)
                    self.theme.selected_bg
                else if (is_marked)
                    self.theme.selected_bg
                else
                    self.theme.main_bg;

                // Paint the ENTIRE row background first so the highlight is a
                // clean full-width bar (no seams in inter-column gaps or past
                // the last column), then draw cell text on top with the same bg.
                try terminal.fillRow(x, row_y, width, fg, bg);

                var rx = x;
                const max_x = x + width;
                for (&item.columns, eff_widths[0..]) |cell, w| {
                    if (w == 0) continue;
                    if (rx >= max_x) break;
                    const avail = max_x - rx;
                    const col_w = @min(w, avail);
                    try Theme.writeStringWithTheme(terminal, rx, row_y, table_layout.utf8TruncateCols(cell, col_w -| 1), fg, bg);
                    rx += w;
                }

                // Draw the marked-row marker LAST so it overwrites the first
                // glyph cell and stays visible even when the row is also the
                // selected (cursor) row — selection bar + marker together.
                if (is_marked and x < max_x) {
                    try Theme.writeStringWithTheme(terminal, x, row_y, "\xe2\x96\x8c", self.theme.title_highlight, bg);
                }
            }
        }

        /// Build a stable row identity key ("<namespace>/<name>" or just
        /// "<name>" for cluster-scoped resources) into `buf`. Used both for
        /// rendering the marked state and for toggling marks on space.
        fn rowKey(item: *const RowData, buf: []u8) []const u8 {
            const name = item.columns[config.name_column];
            if (config.namespace_column) |ns_col| {
                const ns = item.columns[ns_col];
                return std.fmt.bufPrint(buf, "{s}/{s}", .{ ns, name }) catch name;
            }
            return name;
        }

        // ====================================================================
        // Key handling
        // ====================================================================

        const is_pods = std.mem.eql(u8, config.name, "pods");
        // Node-specific keys, mirroring the is_pods branch below.
        const is_nodes = std.mem.eql(u8, config.name, "nodes");
        const is_secrets = std.mem.eql(u8, config.name, "secrets");

        /// pub so tests can drive the real key handler. It is already reachable
        /// through the vtable; a mutation that deleted the secrets `x` mapping survived
        /// the whole suite because every test here inspected configs instead.
        pub fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
            const self: *Self = @ptrCast(@alignCast(ptr));

            if (self.table.handleNavigationKey(key)) |result| return result;

            // Pod-specific action keys (comptime-gated; inert for every other
            // view). Mirrors the action map of the former bespoke PodsView so
            // logs/shell/exec/etc. keep working through the generic engine.
            if (is_secrets) {
                switch (key) {
                    // `x` = Decode, which loadSecretsBindings has always advertised.
                    .char => |c| if (c == 'x') return .request_decode,
                    else => {},
                }
            }

            if (is_nodes) {
                switch (key) {
                    .char => |c| switch (c) {
                        // Cordon / uncordon only. Drain is deliberately NOT bound
                        // here: k9s uses `r`, which in c3s is refresh -- binding a
                        // workload-evicting operation to the key users press to
                        // refresh is an accident generator. It also needs a
                        // confirmation flow, like delete has.
                        'c' => return .request_cordon,
                        'u' => return .request_uncordon,
                        // Uppercase D, NOT k9s's `r`: `r` is refresh in c3s, and
                        // binding an eviction to the key users press to refresh would
                        // be an accident generator. Only 'G' is remapped by
                        // Terminal.readKey, so 'D' arrives as a plain char, and nodes
                        // has no 'D' sort key.
                        'D' => return .request_drain,
                        else => {},
                    },
                    else => {},
                }
            }

            if (is_pods) {
                switch (key) {
                    .ctrl_k => return .request_kill,
                    .ctrl_f => return .request_kill_finalizers,
                    .char => |c| switch (c) {
                        'l' => return .request_logs,
                        'e' => return .request_edit,
                        's' => return .request_shell,
                        'a' => return .request_attach,
                        'o' => return .request_show_node,
                        'p' => return .request_logs_previous,
                        'i' => return .request_set_image,
                        'z' => return .request_sanitize,
                        't' => return .request_transfer,
                        'F' => return .request_port_forward,
                        else => {},
                    },
                    else => {},
                }
            }

            switch (key) {
                .char => |c| {
                    // Space toggles a k9s-style mark on the current row. Marks
                    // persist by row identity as the cursor moves/refreshes.
                    if (c == ' ') {
                        if (self.table.getSelectedItem()) |item| {
                            var key_buf: [512]u8 = undefined;
                            const mark_key = rowKey(item, &key_buf);
                            self.table.toggleMark(mark_key) catch |err|
                                Logger.err("Failed to toggle mark in {s}: {}", .{ config.name, err });
                        }
                        return .handled;
                    }

                    // Bulk mark manipulation over the currently-filtered rows
                    // (k9s-style multi-select): '*' mark all, '\' clear, '^'
                    // invert. Acts on the visible/filtered set, like the filter.
                    if (c == '*') {
                        self.applyMarkOp(.all);
                        return .handled;
                    }
                    if (c == '\\') {
                        self.table.clearMarks();
                        return .handled;
                    }
                    if (c == '^') {
                        self.applyMarkOp(.invert);
                        return .handled;
                    }

                    // Refresh
                    if (c == 'r') {
                        self.refresh() catch |err| Logger.err("Failed to refresh {s}: {}", .{ config.name, err });
                        return .handled;
                    }

                    // Traffic view (deployments only)
                    if (c == 't' and std.mem.eql(u8, config.name, "deployments")) {
                        return .request_traffic;
                    }

                    // Namespace toggle (only for namespaced resources)
                    if (config.is_namespaced and c == '0') {
                        self.table.show_all_namespaces = !self.table.show_all_namespaces;
                        self.table.gotoTop();
                        self.refresh() catch |err| Logger.err("Failed to refresh {s}: {}", .{ config.name, err });
                        return .handled;
                    }

                    // Comptime-generated sort key dispatch
                    inline for (config.columns, 0..) |col_def, idx| {
                        if (col_def.sort_key) |sk| {
                            if (c == sk) {
                                self.table.toggleSort(@intCast(idx));
                                self.applySorting();
                                return .handled;
                            }
                        }
                    }

                    return .not_handled;
                },
                else => return .not_handled,
            }
        }

        // ====================================================================
        // VTable
        // ====================================================================

        fn onShow(ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            // Re-showing must be instant (Esc back from a sub-view / switching
            // back): show already-loaded rows, never block on kubectl. Only
            // auto-load when empty; `r` forces a refresh. See PodsView.
            if (self.table.items.items.len > 0) return;
            self.refresh() catch |err| {
                Logger.err("Failed to refresh {s}: {}", .{ config.name, err });
                if (self.table.error_message == null) {
                    self.table.setError("Unexpected error during refresh") catch {
                        Logger.err("Failed to allocate error message", .{});
                    };
                }
            };
        }

        fn onHide(_: *anyopaque) void {}

        fn getName(_: *anyopaque) []const u8 {
            return config.name;
        }

        /// k9s-style decorated title: "<name>(<scope>)[<count>]" for namespaced
        /// resources (scope = "all" or the active namespace), "<name>[<count>]"
        /// for cluster-scoped ones. Falls back to the plain name on overflow.
        fn getTitle(ptr: *anyopaque) []const u8 {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const count = self.table.filtered_indices.items.len;
            const filt = self.table.filter_text;
            if (!config.is_namespaced) {
                return if (filt.len > 0)
                    std.fmt.bufPrint(&self.title_buf, "{s}[{d}] </{s}>", .{ config.name, count, filt }) catch config.name
                else
                    std.fmt.bufPrint(&self.title_buf, "{s}[{d}]", .{ config.name, count }) catch config.name;
            }
            const scope: []const u8 = if (self.table.show_all_namespaces)
                "all"
            else
                self.k8s_service.current_namespace;
            return if (filt.len > 0)
                std.fmt.bufPrint(&self.title_buf, "{s}({s})[{d}] </{s}>", .{ config.name, scope, count, filt }) catch config.name
            else
                std.fmt.bufPrint(&self.title_buf, "{s}({s})[{d}]", .{ config.name, scope, count }) catch config.name;
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
            return self.getSelectedResourceInfo();
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
}
