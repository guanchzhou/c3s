// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Port-forwards view (`:pf`) -- lists the `kubectl port-forward` children c3s has
// spawned and lets you stop one with Ctrl-D.
//
// Why this exists: `portforwards` was already in the ViewType enum, already had
// "start"/"stop" bindings in keybindings_data, and already had a test asserting those
// bindings exist -- but there was no view and nothing could navigate to one. Starting a
// forward worked (`F` on a resource view); seeing or stopping one did not. So the help
// screen described a feature the binary did not have, and the test enforced it.
const std = @import("std");
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const view_mod = @import("../viewmodel/view.zig");
const View = view_mod.View;
const KeyResult = View.KeyResult;
const Logger = @import("../core/logger.zig");
const hints_model = @import("../model/hints.zig");
const sort_util = @import("../viewmodel/sort.zig");
const TableState = @import("../ui/TableState.zig").TableState;
const PortForwardRegistry = @import("../services/PortForwardRegistry.zig").PortForwardRegistry;

pub const PortForwardsView = struct {
    theme: *const theme_loader.ThemeColors,
    registry: *PortForwardRegistry,
    table: TableState(Row),

    const COL_TARGET: u8 = 0;
    const COL_PORTS: u8 = 1;
    const COL_STATUS: u8 = 2;

    /// A snapshot of one registry entry. Rows are rebuilt from the registry on every
    /// refresh rather than pointing into it: the registry shifts on stop(), and a row
    /// holding a pointer would dangle exactly when the user is pressing keys.
    const Row = struct {
        target: []const u8,
        ports: []const u8,
        namespace: []const u8,
        status: []const u8,
        pid: []const u8,
        /// Index into the registry at the time of the snapshot. Only ever used
        /// immediately, and always followed by a refresh.
        registry_index: usize,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *Row) void {
            self.allocator.free(self.target);
            self.allocator.free(self.ports);
            self.allocator.free(self.namespace);
            self.allocator.free(self.pid);
            // `status` is a static string from Entry.status(); not owned.
        }

        fn getTarget(self: *const Row) []const u8 {
            return self.target;
        }
        fn getPorts(self: *const Row) []const u8 {
            return self.ports;
        }
        fn getStatus(self: *const Row) []const u8 {
            return self.status;
        }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        registry: *PortForwardRegistry,
    ) !PortForwardsView {
        return .{
            .theme = theme,
            .registry = registry,
            .table = TableState(Row).init(allocator),
        };
    }

    pub fn deinit(self: *PortForwardsView) void {
        self.table.deinit();
    }

    /// Rebuild the rows from the registry. Cheap and local -- no network, so unlike the
    /// resource views this can refresh on every show without a latency cost.
    pub fn refresh(self: *PortForwardsView) !void {
        // Reap first, so a forward whose pod went away shows as Failed rather than
        // sitting there claiming to be Running.
        self.registry.poll();

        self.table.clearItems();
        const a = self.table.allocator;

        for (self.registry.entries.items, 0..) |*entry, i| {
            const pid_str = try std.fmt.allocPrint(a, "{d}", .{entry.pid()});
            errdefer a.free(pid_str);
            const target = try a.dupe(u8, entry.target);
            errdefer a.free(target);
            const ports = try a.dupe(u8, entry.ports);
            errdefer a.free(ports);
            const namespace = try a.dupe(u8, entry.namespace);
            errdefer a.free(namespace);

            try self.table.appendItem(.{
                .target = target,
                .ports = ports,
                .namespace = namespace,
                .status = entry.status(),
                .pid = pid_str,
                .registry_index = i,
                .allocator = a,
            });
        }
        // Rebuild filtered_indices, which is what render and getSelectedItem actually
        // walk -- appendItem only touches `items`. An earlier version ended with
        // applySorting(), which returns early when nothing is sorted, so the view drew
        // an empty list no matter how many forwards were running. Passing the existing
        // filter_text also keeps an active filter across a refresh.
        try self.applyFilter(self.table.filter_text);
    }

    fn matchFn(row: *const Row, filter: []const u8) bool {
        return std.ascii.indexOfIgnoreCase(row.target, filter) != null or
            std.ascii.indexOfIgnoreCase(row.ports, filter) != null or
            std.ascii.indexOfIgnoreCase(row.namespace, filter) != null;
    }

    pub fn applyFilter(self: *PortForwardsView, filter: []const u8) !void {
        try self.table.applyFilter(filter, matchFn);
        self.applySorting();
    }

    fn applySorting(self: *PortForwardsView) void {
        // sort_column is optional: null means "unsorted", which for this view means
        // registry order -- i.e. the order the user started the forwards in, which is
        // a more useful default than alphabetical.
        const col = self.table.sort_column orelse return;
        switch (col) {
            COL_PORTS => self.table.sortBy(Row.getPorts),
            COL_STATUS => self.table.sortBy(Row.getStatus),
            else => self.table.sortBy(Row.getTarget),
        }
    }

    /// Stop the selected forward. Returns false when there is nothing selected, so the
    /// caller can tell "no row" from "stopped".
    pub fn stopSelected(self: *PortForwardsView) !bool {
        const row = self.table.getSelectedItem() orelse return false;
        const idx = row.registry_index;
        // Guard against a registry that shifted under us (a poll that dropped an
        // entry, a second stop before the refresh landed).
        if (idx >= self.registry.count()) {
            try self.refresh();
            return false;
        }
        try self.registry.stop(idx);
        try self.refresh();
        return true;
    }

    pub fn createView(self: *PortForwardsView) View {
        return View.create(PortForwardsView, self, &vtable);
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
        // getSelectedResource is deliberately left at the default (null): a
        // port-forward is not a cluster resource, so describe/yaml/delete must be
        // no-ops here rather than acting on whatever the previous view had selected.
    };

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *PortForwardsView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *PortForwardsView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *PortForwardsView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *PortForwardsView = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(terminal, x, y, self.theme)) return;

        // An empty list is the common case, and "nothing here" is a much better
        // message than a bare header row over blank space.
        if (self.table.items.items.len == 0) {
            try Theme.writeStringWithTheme(
                terminal,
                x,
                y,
                "No active port-forwards. Press F on a pod or service to start one.",
                self.theme.main_fg,
                self.theme.main_bg,
            );
            return;
        }

        const target_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_TARGET);
        const ports_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_PORTS);
        const status_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_STATUS);
        var b1: [32]u8 = undefined;
        var b2: [32]u8 = undefined;
        var b3: [32]u8 = undefined;
        const target_hdr = std.fmt.bufPrint(&b1, "TARGET{s}", .{target_ind}) catch "TARGET";
        const ports_hdr = std.fmt.bufPrint(&b2, "PORTS{s}", .{ports_ind}) catch "PORTS";
        const status_hdr = std.fmt.bufPrint(&b3, "STATUS{s}", .{status_ind}) catch "STATUS";

        try Theme.writeStringWithTheme(terminal, x, y, "NAMESPACE", self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 20, y, target_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 50, y, ports_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 66, y, status_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 78, y, "PID", self.theme.title, self.theme.main_bg);

        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |row_idx, i| {
            const row = self.table.items.items[row_idx];
            const colors = self.table.rowColors(i, self.theme);
            const row_y = y + 1 + @as(u16, @intCast(i));

            if (width > 0) try terminal.fillRow(x, row_y, width, colors.fg, colors.bg);

            try Theme.writeStringWithTheme(terminal, x, row_y, row.namespace[0..@min(18, row.namespace.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 20, row_y, row.target[0..@min(28, row.target.len)], colors.fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 50, row_y, row.ports[0..@min(14, row.ports.len)], colors.fg, colors.bg);
            // A dead forward is called out in the error colour: the whole point of this
            // view is noticing that one stopped working.
            const status_fg = if (std.mem.eql(u8, row.status, "Running")) colors.fg else self.theme.status_failed;
            try Theme.writeStringWithTheme(terminal, x + 66, row_y, row.status, status_fg, colors.bg);
            try Theme.writeStringWithTheme(terminal, x + 78, row_y, row.pid, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *PortForwardsView = @ptrCast(@alignCast(ptr));

        if (self.table.handleNavigationKey(key)) |result| return result;

        switch (key) {
            // Ctrl-D to stop, matching both k9s and the binding this view's own help
            // entry has always advertised. No confirmation: stopping a forward is
            // local, instant and re-doable with F.
            .ctrl_d => {
                _ = self.stopSelected() catch |err| {
                    Logger.err("Failed to stop port-forward: {any}", .{err});
                };
                return .handled;
            },
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| Logger.err("Failed to refresh port-forwards: {any}", .{err});
                    return .handled;
                },
                'N' => {
                    self.table.toggleSort(COL_TARGET);
                    self.applySorting();
                    return .handled;
                },
                'P' => {
                    self.table.toggleSort(COL_PORTS);
                    self.applySorting();
                    return .handled;
                },
                'S' => {
                    self.table.toggleSort(COL_STATUS);
                    self.applySorting();
                    return .handled;
                },
                else => return .not_handled,
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *PortForwardsView = @ptrCast(@alignCast(ptr));
        // Always refresh, unlike the resource views: this reads a local list, not the
        // API server, and a stale port-forward list is the exact thing this view is for.
        self.refresh() catch |err| {
            Logger.err("Failed to refresh port-forwards: {any}", .{err});
            if (self.table.error_message == null) {
                self.table.setError("Failed to list port-forwards") catch {};
            }
        };
    }

    fn onHide(_: *anyopaque) void {}

    fn getName(_: *anyopaque) []const u8 {
        return "portforwards";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *PortForwardsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

// ===========================================================================
// Tests
//
// These spawn real `sleep` processes rather than kubectl, so the stop path is
// exercised end to end without a cluster.
// ===========================================================================

const builtin = @import("builtin");

fn spawnSleeper() !std.process.Child {
    return std.process.spawn(@import("../core/runtime.zig").io(), .{
        .argv = &.{ "/bin/sh", "-c", "sleep 300" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
}

test "refresh builds one row per registry entry" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = std.testing.allocator;

    var reg = PortForwardRegistry.init(a);
    defer reg.deinit();
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);

    var view = try PortForwardsView.init(a, &theme, &reg);
    defer view.deinit();

    try reg.add("pods/nginx", "8080:80", "default", try spawnSleeper());
    try reg.add("svc/api", "9090:9090", "prod", try spawnSleeper());

    try view.refresh();

    try std.testing.expectEqual(@as(usize, 2), view.table.items.items.len);
    try std.testing.expectEqualStrings("Running", view.table.items.items[0].status);
    // Unsorted by default, so rows are in the order the user started them.
    try std.testing.expectEqualStrings("pods/nginx", view.table.items.items[0].target);
    try std.testing.expectEqualStrings("8080:80", view.table.items.items[0].ports);
    try std.testing.expectEqualStrings("prod", view.table.items.items[1].namespace);
}

test "Ctrl-D stops the selected forward and drops its row" {
    // Behavioural: drives the real key handler rather than asserting a KeyResult
    // variant exists. Before this view, `Ctrl-d`/"Stop" was advertised in
    // keybindings_data with a test asserting it -- and nothing implemented it.
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = std.testing.allocator;

    var reg = PortForwardRegistry.init(a);
    defer reg.deinit();
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);

    var view = try PortForwardsView.init(a, &theme, &reg);
    defer view.deinit();

    try reg.add("pods/keep", "1:1", "default", try spawnSleeper());
    try reg.add("pods/kill", "2:2", "default", try spawnSleeper());
    try view.refresh();

    // Select the second row and stop it.
    view.table.selected_row = 1;
    const doomed_pid = reg.entries.items[1].pid();
    try std.testing.expect(doomed_pid > 0);

    const result = try PortForwardsView.handleKey(&view, Key{ .ctrl_d = {} });
    try std.testing.expectEqual(KeyResult.handled, result);

    // The registry really shrank -- the key is not cosmetic.
    try std.testing.expectEqual(@as(usize, 1), reg.count());
    try std.testing.expectEqualStrings("pods/keep", reg.entries.items[0].target);
    // And the view refreshed itself, so no row points at a gone entry.
    try std.testing.expectEqual(@as(usize, 1), view.table.items.items.len);
    try std.testing.expectEqualStrings("pods/keep", view.table.items.items[0].target);

    // The process is gone, not merely forgotten.
    std.posix.kill(@intCast(doomed_pid), .CHLD) catch |err| {
        try std.testing.expectEqual(error.ProcessNotFound, err);
        return;
    };
    return error.ForwardStillRunningAfterStop;
}

test "Ctrl-D on an empty list is a no-op, not a crash" {
    // getSelectedItem() on an empty table returns null; an earlier TableState bug
    // returned a row for an out-of-range index, which would have indexed the registry
    // out of bounds here.
    const a = std.testing.allocator;

    var reg = PortForwardRegistry.init(a);
    defer reg.deinit();
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);

    var view = try PortForwardsView.init(a, &theme, &reg);
    defer view.deinit();

    try view.refresh();
    try std.testing.expectEqual(@as(usize, 0), view.table.items.items.len);

    const result = try PortForwardsView.handleKey(&view, Key{ .ctrl_d = {} });
    try std.testing.expectEqual(KeyResult.handled, result);
    try std.testing.expectEqual(@as(usize, 0), reg.count());
    try std.testing.expectEqual(false, try view.stopSelected());
}

test "a stale registry_index refreshes instead of stopping the wrong forward" {
    // The hazard this guards: rows carry a registry index, and the registry shifts on
    // stop(). If the view acted on a stale index it would kill somebody else's
    // forward -- silently, since both rows look alike.
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = std.testing.allocator;

    var reg = PortForwardRegistry.init(a);
    defer reg.deinit();
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);

    var view = try PortForwardsView.init(a, &theme, &reg);
    defer view.deinit();

    try reg.add("pods/a", "1:1", "default", try spawnSleeper());
    try reg.add("pods/b", "2:2", "default", try spawnSleeper());
    try view.refresh();

    // Simulate the registry shrinking behind the view's back (a poll that dropped an
    // entry, a stop that already landed).
    try reg.stop(1);
    try std.testing.expectEqual(@as(usize, 1), reg.count());

    // The view still shows two rows; act on the one whose index is now out of range.
    view.table.selected_row = 1;
    try std.testing.expectEqual(false, try view.stopSelected());

    // The surviving forward was NOT stopped, and the view resynced.
    try std.testing.expectEqual(@as(usize, 1), reg.count());
    try std.testing.expectEqualStrings("pods/a", reg.entries.items[0].target);
    try std.testing.expectEqual(@as(usize, 1), view.table.items.items.len);
}

test "filter matches target, ports and namespace" {
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const a = std.testing.allocator;

    var reg = PortForwardRegistry.init(a);
    defer reg.deinit();
    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);

    var view = try PortForwardsView.init(a, &theme, &reg);
    defer view.deinit();

    try reg.add("pods/nginx", "8080:80", "default", try spawnSleeper());
    try reg.add("svc/postgres", "5432:5432", "prod", try spawnSleeper());
    try view.refresh();

    try view.applyFilter("nginx");
    try std.testing.expectEqual(@as(usize, 1), view.table.filtered_indices.items.len);

    try view.applyFilter("5432");
    try std.testing.expectEqual(@as(usize, 1), view.table.filtered_indices.items.len);

    try view.applyFilter("prod");
    try std.testing.expectEqual(@as(usize, 1), view.table.filtered_indices.items.len);

    try view.applyFilter("");
    try std.testing.expectEqual(@as(usize, 2), view.table.filtered_indices.items.len);
}

test "the view name resolves to the portforwards ViewType, so `?` shows its bindings" {
    // This is the join that was missing. keybindings_data has always had
    // loadPortForwardsBindings (Ctrl-d Stop, Shift-f Start) and ViewType has always had
    // a `portforwards` member -- but no view returned that name, so nothing could ever
    // select those bindings. App.currentViewType() does
    // stringToEnum(ViewType, current_view_name), which is set from getName().
    const ViewType = @import("../viewmodel/keybindings_vm.zig").ViewType;
    var dummy: u8 = 0;
    const name = PortForwardsView.getName(&dummy);
    try std.testing.expectEqualStrings("portforwards", name);
    try std.testing.expectEqual(ViewType.portforwards, std.meta.stringToEnum(ViewType, name).?);
}
