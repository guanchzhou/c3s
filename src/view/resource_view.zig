/// Generic Resource View - generates a complete View type from declarative config.
/// Replaces 25+ individual view files with one comptime template.
const std = @import("std");
const klient = @import("klient");
const view_mod = @import("../viewmodel/view.zig");
const View = view_mod.View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const hints_model = @import("../model/hints.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const Logger = @import("../core/logger.zig");
const sort_util = @import("../viewmodel/sort.zig");
const age_util = @import("../viewmodel/age.zig");
const TableState = @import("../ui/table_state.zig").TableState;
const table_layout = @import("../ui/table_layout.zig");

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

        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
        table: TableState(RowData),
        cached_col_widths: ?table_layout.ColumnWidths = null,
        cached_terminal_width: u16 = 0,

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

        fn applySorting(self: *Self) void {
            if (self.table.sort_column) |col| {
                // Comptime-generated sort dispatch
                inline for (0..col_count) |idx| {
                    if (col == idx) {
                        self.table.sortBy(RowData.getColumn(idx));
                        return;
                    }
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
            const use_cache = self.cached_col_widths != null and self.cached_terminal_width == available_width;

            const col_widths = if (use_cache) blk: {
                break :blk &self.cached_col_widths.?;
            } else blk: {
                // Build rows data for width calculation
                var rows_data = try std.ArrayList([]const []const u8).initCapacity(allocator, self.table.filtered_indices.items.len);
                defer rows_data.deinit(allocator);

                for (self.table.filtered_indices.items) |item_idx| {
                    const item = self.table.items.items[item_idx];
                    const row: *const [col_count][]const u8 = &item.columns;
                    try rows_data.append(allocator, row);
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
                for (col_defs, col_widths.widths) |cd, w| {
                    if (w == 0) continue;
                    if (col_x >= hdr_max_x) break;
                    const hdr_avail = hdr_max_x - col_x;
                    const hdr_w = @min(w, hdr_avail);
                    _ = hdr_w;
                    if (cd.has_sort) {
                        const indicator = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, cd.sort_col);
                        var hdr_buf: [64]u8 = undefined;
                        const hdr = std.fmt.bufPrint(&hdr_buf, "{s}{s}", .{ cd.name, indicator }) catch cd.name;
                        try Theme.writeStringWithTheme(terminal, col_x, y, hdr[0..@min(hdr.len, w)], self.theme.title, self.theme.main_bg);
                    } else {
                        try Theme.writeStringWithTheme(terminal, col_x, y, cd.name[0..@min(cd.name.len, w)], self.theme.title, self.theme.main_bg);
                    }
                    col_x += w;
                }
            }

            // Render data rows
            const range = self.table.getVisibleRange();
            for (self.table.filtered_indices.items[range.start..range.end], 0..) |item_idx, i| {
                const item = self.table.items.items[item_idx];
                const colors = self.table.rowColors(i, self.theme);
                const row_y = y + 1 + @as(u16, @intCast(i));

                var rx = x;
                const max_x = x + width;
                for (&item.columns, col_widths.widths) |cell, w| {
                    if (w == 0) continue;
                    if (rx >= max_x) break;
                    const avail = max_x - rx;
                    const col_w = @min(w, avail);
                    const display_len = @min(cell.len, col_w -| 1);
                    try Theme.writeStringWithTheme(terminal, rx, row_y, cell[0..display_len], colors.fg, colors.bg);
                    rx += w;
                }
            }
        }

        // ====================================================================
        // Key handling
        // ====================================================================

        fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
            const self: *Self = @ptrCast(@alignCast(ptr));

            if (self.table.handleNavigationKey(key)) |result| return result;

            switch (key) {
                .char => |c| {
                    // Refresh
                    if (c == 'r') {
                        self.refresh() catch |err| Logger.err("Failed to refresh {s}: {}", .{ config.name, err });
                        return .handled;
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
            .getHints = getHints,
            .deinit = deinitView,
            .applyFilter = vtableApplyFilter,
            .clearFilter = vtableClearFilter,
            .refresh = vtableRefresh,
            .getSelectedResource = vtableGetSelectedResource,
        };
    };
}
