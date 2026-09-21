const std = @import("std");
const view_mod = @import("../viewmodel/view.zig");
const View = view_mod.View;
const Key = @import("../core/Terminal.zig").Key;
const Terminal = @import("../core/Terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const hints_model = @import("../model/hints.zig");
const K8sService = @import("../services/K8sService.zig").K8sService;
const dynamic_resource = @import("../k8s/DynamicResource.zig");
const Logger = @import("../core/logger.zig");
const TableState = @import("../ui/TableState.zig").TableState;
const table_layout = @import("../ui/table_layout.zig");
const clock = @import("../core/clock.zig");

pub const DynamicResourceView = struct {
    const Self = @This();
    const refresh_interval_ns = 10 * std.time.ns_per_s;

    const Row = struct {
        cells: [][]u8,
        name: []u8,
        namespace: []u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Row) void {
            for (self.cells) |cell| self.allocator.free(cell);
            self.allocator.free(self.cells);
            self.allocator.free(self.name);
            self.allocator.free(self.namespace);
        }
    };

    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    descriptor: ?dynamic_resource.Descriptor = null,
    table: TableState(Row),
    columns: [][]u8 = &.{},
    cached_col_widths: ?table_layout.ColumnWidths = null,
    cached_terminal_width: u16 = 0,
    show_all_namespaces: bool = false,
    next_refresh_ns: i128 = 0,
    title_buf: [256]u8 = undefined,
    name_bufs: [2][256]u8 = undefined,
    name_lens: [2]usize = .{ 0, 0 },
    active_name: u1 = 0,
    selected_cell_names: std.ArrayListUnmanaged([]const u8) = .empty,
    selected_cell_values: std.ArrayListUnmanaged([]const u8) = .empty,

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) Self {
        return .{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(Row).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.clearColumnCache();
        self.freeColumns();
        self.table.deinit();
        self.selected_cell_names.deinit(self.allocator);
        self.selected_cell_values.deinit(self.allocator);
        if (self.descriptor) |*descriptor| descriptor.deinit(self.allocator);
    }

    pub fn open(
        self: *Self,
        descriptor: dynamic_resource.Descriptor,
        show_all_namespaces: bool,
    ) !void {
        if (self.descriptor) |*old| old.deinit(self.allocator);
        self.descriptor = descriptor;
        self.show_all_namespaces = descriptor.namespaced and show_all_namespaces;
        try self.refresh();
        const next_name: u1 = self.active_name ^ 1;
        if (descriptor.plural.len > self.name_bufs[next_name].len)
            return error.ResourceNameTooLong;
        @memcpy(self.name_bufs[next_name][0..descriptor.plural.len], descriptor.plural);
        self.name_lens[next_name] = descriptor.plural.len;
        self.active_name = next_name;
    }

    pub fn isRefreshDue(self: *const Self, now_ns: i128) bool {
        return self.descriptor != null and now_ns >= self.next_refresh_ns;
    }

    pub fn createView(self: *Self) View {
        return View.create(Self, self, &vtable);
    }

    fn clearColumnCache(self: *Self) void {
        if (self.cached_col_widths) |*widths| widths.deinit();
        self.cached_col_widths = null;
        self.cached_terminal_width = 0;
    }

    fn freeColumns(self: *Self) void {
        for (self.columns) |column| self.allocator.free(column);
        if (self.columns.len > 0) self.allocator.free(self.columns);
        self.columns = &.{};
    }

    fn refresh(self: *Self) !void {
        const descriptor = self.descriptor orelse return;
        self.table.loading = true;
        defer self.table.loading = false;
        self.next_refresh_ns = clock.nanoTimestamp() + refresh_interval_ns;

        var data = self.k8s_service.listDynamicResourceTable(
            descriptor,
            self.show_all_namespaces,
        ) catch |err| {
            try self.table.setConnectionError(descriptor.plural, err);
            return;
        };
        var data_owned = true;
        defer if (data_owned) data.deinit();

        var new_table = TableState(Row).init(self.allocator);
        var new_table_owned = true;
        defer if (new_table_owned) new_table.deinit();
        try new_table.items.ensureTotalCapacity(self.allocator, data.rows.len);
        for (data.rows) |row| {
            new_table.items.appendAssumeCapacity(.{
                .cells = row.cells,
                .name = row.name,
                .namespace = row.namespace,
                .allocator = self.allocator,
            });
        }
        self.allocator.free(data.rows);
        data.rows = &.{};

        self.table.deinit();
        self.table = new_table;
        new_table_owned = false;
        self.freeColumns();
        self.columns = data.columns;
        data.columns = &.{};
        data_owned = false;
        self.clearColumnCache();
        try self.applyFilter("");
    }

    fn applyFilter(self: *Self, filter: []const u8) !void {
        self.clearColumnCache();
        try self.table.applyFilter(filter, matchFn);
    }

    fn matchFn(row: *const Row, filter: []const u8) bool {
        if (filter.len == 0) return true;
        for (row.cells) |cell| {
            if (containsIgnoreCase(cell, filter)) return true;
        }
        return false;
    }

    fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
        if (needle.len > haystack.len) return false;
        var index: usize = 0;
        outer: while (index + needle.len <= haystack.len) : (index += 1) {
            for (needle, 0..) |byte, needle_index| {
                if (std.ascii.toLower(haystack[index + needle_index]) !=
                    std.ascii.toLower(byte)) continue :outer;
            }
            return true;
        }
        return needle.len == 0;
    }

    fn render(
        ptr: *anyopaque,
        terminal: *Terminal,
        x: u16,
        y: u16,
        width: u16,
        height: u16,
    ) !void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 1) height - 1 else 0;
        if (try self.table.renderStatus(terminal, x, y, self.theme)) return;
        if (self.columns.len == 0) {
            try Theme.writeStringWithTheme(
                terminal,
                x,
                y,
                "No printable columns",
                self.theme.main_fg,
                self.theme.main_bg,
            );
            return;
        }
        if (self.table.filtered_indices.items.len == 0) {
            try Theme.writeStringWithTheme(
                terminal,
                x,
                y,
                if (self.table.items.items.len == 0) "No resources" else "No matching resources",
                self.theme.main_fg,
                self.theme.main_bg,
            );
            return;
        }

        const widths = try self.columnWidths(width);
        var column_x = x;
        for (self.columns, widths.widths) |name, column_width| {
            if (column_width == 0) continue;
            if (column_x >= x + width) break;
            try Theme.writeStringWithTheme(
                terminal,
                column_x,
                y,
                table_layout.utf8TruncateCols(name, column_width),
                self.theme.title,
                self.theme.main_bg,
            );
            column_x += column_width;
        }

        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |item_index, row_index| {
            const row = self.table.items.items[item_index];
            const row_y = y + 1 + @as(u16, @intCast(row_index));
            const colors = self.table.rowColors(row_index, self.theme);
            try terminal.fillRow(x, row_y, width, colors.fg, colors.bg);

            var row_x = x;
            for (row.cells, widths.widths) |cell, column_width| {
                if (column_width == 0) continue;
                if (row_x >= x + width) break;
                const available = @min(column_width, x + width - row_x);
                try Theme.writeStringWithTheme(
                    terminal,
                    row_x,
                    row_y,
                    table_layout.utf8TruncateCols(cell, available -| 1),
                    colors.fg,
                    colors.bg,
                );
                row_x += column_width;
            }
        }
    }

    fn columnWidths(self: *Self, width: u16) !*const table_layout.ColumnWidths {
        if (self.cached_col_widths != null and self.cached_terminal_width == width)
            return &self.cached_col_widths.?;

        var rows = try std.ArrayList([]const []const u8).initCapacity(
            self.allocator,
            self.table.filtered_indices.items.len,
        );
        defer rows.deinit(self.allocator);
        for (self.table.filtered_indices.items) |item_index|
            try rows.append(self.allocator, self.table.items.items[item_index].cells);

        var info = try self.allocator.alloc(table_layout.ColumnInfo, self.columns.len);
        defer self.allocator.free(info);
        for (self.columns, 0..) |name, index| {
            info[index] = .{
                .name = name,
                .min_width = if (index == 0) 16 else 8,
                .max_width = if (index == 0) null else 32,
                .priority = if (index == 0)
                    table_layout.ColumnPriority.CRITICAL
                else if (index < 4)
                    table_layout.ColumnPriority.MEDIUM
                else
                    table_layout.ColumnPriority.LOW,
            };
        }
        self.clearColumnCache();
        self.cached_col_widths = try table_layout.calculateColumnWidths(
            self.allocator,
            self.columns,
            rows.items,
            info,
            width,
        );
        self.cached_terminal_width = width;
        return &self.cached_col_widths.?;
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.table.handleNavigationKey(key)) |result| return result;
        switch (key) {
            .ctrl_r => {
                self.refresh() catch |err| Logger.err("Dynamic resource refresh failed: {}", .{err});
                return .handled;
            },
            .char => |character| {
                if (self.isArgoApplication()) {
                    if (character == 'R') return .request_argo_refresh;
                    if (character == 'H') return .request_argo_hard_refresh;
                    if (character == 'S') return .request_argo_sync_details;
                }
                if (character == 'r') {
                    self.refresh() catch |err| Logger.err("Dynamic resource refresh failed: {}", .{err});
                    return .handled;
                }
                if (character == '0') {
                    const descriptor = self.descriptor orelse return .handled;
                    if (!descriptor.namespaced) return .handled;
                    self.show_all_namespaces = !self.show_all_namespaces;
                    self.refresh() catch |err| Logger.err("Dynamic resource scope refresh failed: {}", .{err});
                    return .handled;
                }
                if (character == 'Y') return .request_copy_column;
                return .not_handled;
            },
            else => return .not_handled,
        }
    }

    fn onShow(_: *anyopaque) void {}
    fn onHide(_: *anyopaque) void {}

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const len = self.name_lens[self.active_name];
        return if (len > 0)
            self.name_bufs[self.active_name][0..len]
        else
            "customresources";
    }

    fn getTitle(ptr: *anyopaque) []const u8 {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const descriptor = self.descriptor orelse return "customresources";
        const scope = if (!descriptor.namespaced)
            "cluster"
        else if (self.show_all_namespaces)
            "all"
        else
            self.k8s_service.getCurrentNamespace();
        return std.fmt.bufPrint(
            &self.title_buf,
            "{s}({s})[{d}]",
            .{ descriptor.plural, scope, self.table.filtered_indices.items.len },
        ) catch descriptor.plural;
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.commonHints();
    }

    fn deinitView(_: *anyopaque) void {}

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len == 0) return false;
        try self.applyFilter("");
        return true;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn getSelectedResource(ptr: *anyopaque) ?view_mod.ResourceInfo {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const row = self.table.getSelectedItem() orelse return null;
        const namespace = if (row.namespace.len > 0) row.namespace else "cluster";
        const descriptor = self.descriptor orelse return null;
        return .{
            .name = row.name,
            .namespace = namespace,
            .group = descriptor.group,
            .version = descriptor.version,
            .resource = descriptor.plural,
        };
    }

    fn isArgoApplication(self: *const Self) bool {
        const descriptor = self.descriptor orelse return false;
        return std.mem.eql(u8, descriptor.group, "argoproj.io") and
            std.mem.eql(u8, descriptor.plural, "applications");
    }

    fn getSelectedCells(ptr: *anyopaque) ?view_mod.SelectedCells {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const row = self.table.getSelectedItem() orelse return null;
        self.selected_cell_names.clearRetainingCapacity();
        self.selected_cell_values.clearRetainingCapacity();
        self.selected_cell_names.ensureTotalCapacity(self.allocator, self.columns.len) catch return null;
        self.selected_cell_values.ensureTotalCapacity(self.allocator, row.cells.len) catch return null;
        for (self.columns) |name| self.selected_cell_names.appendAssumeCapacity(name);
        for (row.cells) |value| self.selected_cell_values.appendAssumeCapacity(value);
        return .{
            .names = self.selected_cell_names.items,
            .values = self.selected_cell_values.items,
        };
    }

    fn setShowAllNamespaces(ptr: *anyopaque, all: bool) void {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const descriptor = self.descriptor orelse return;
        self.show_all_namespaces = descriptor.namespaced and all;
    }

    fn showsAllNamespaces(ptr: *anyopaque) bool {
        const self: *Self = @ptrCast(@alignCast(ptr));
        return self.show_all_namespaces;
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
        .getSelectedResource = getSelectedResource,
        .getSelectedCells = getSelectedCells,
        .setShowAllNamespaces = setShowAllNamespaces,
        .showsAllNamespaces = showsAllNamespaces,
    };
};

test "dynamic view refresh deadline is inactive until a resource opens" {
    var view: DynamicResourceView = undefined;
    view.descriptor = null;
    view.next_refresh_ns = 0;
    try std.testing.expect(!view.isRefreshDue(std.math.maxInt(i128)));
}
