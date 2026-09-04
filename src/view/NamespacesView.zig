/// Namespaces View - Display and switch between Kubernetes namespaces
const std = @import("std");
const Terminal = @import("../core/Terminal.zig").Terminal;
const Theme = theme_loader;
const theme_loader = @import("../model/theme_loader.zig");
const View = @import("../viewmodel/view.zig").View;
const Key = @import("../core/Terminal.zig").Key;
const KeyResult = View.KeyResult;
const Logger = @import("../core/logger.zig");
const k8s_service_mod = @import("../services/K8sService.zig");
const K8sService = k8s_service_mod.K8sService;
const view_mod = @import("../viewmodel/view.zig");
const ResourceInfo = view_mod.ResourceInfo;
const klient = @import("klient");
const hints_model = @import("../model/hints.zig");
const sort_util = @import("../viewmodel/sort.zig");
const filter_util = @import("../viewmodel/filter.zig");
const age_util = @import("../viewmodel/age.zig");
const TableState = @import("../ui/TableState.zig").TableState;
const runtime = @import("../core/runtime.zig");
const ActiveContextSession = @import("../k8s/ActiveContextSession.zig").ActiveContextSession;
const ActiveSessionSlot = @import("../k8s/ActiveSessionSlot.zig").ActiveSessionSlot;
const NamespaceRecord = @import("../k8s/NamespaceRecord.zig");
const NamespaceProjection = @import("../k8s/ResourceProjection.zig").ResourceProjection(NamespaceRecord);

pub var active_namespace_source: @import("resource_view.zig").Source = .data_plane;
pub var legacy_loader_test_hook: ?*const fn () void = null;

pub const NamespacesView = struct {
    pub const SubscriptionRequest = enum { none, start, restart };

    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    table: TableState(NamespaceInfo),
    current_namespace: []const u8,
    projection: ?*NamespaceProjection = null,
    subscription_started: bool = false,
    subscription_request: SubscriptionRequest = .none,

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;
    const COL_STATUS: u8 = 2;

    const NamespaceInfo = struct {
        name: []const u8,
        status: []const u8,
        age: []const u8,
        uid: []const u8 = &.{},
        allocator: std.mem.Allocator,

        pub fn deinit(self: *NamespaceInfo) void {
            self.allocator.free(self.name);
            self.allocator.free(self.status);
            self.allocator.free(self.age);
            if (self.uid.len > 0) self.allocator.free(self.uid);
        }

        fn getName(self: *const NamespaceInfo) []const u8 {
            return self.name;
        }
        fn getAge(self: *const NamespaceInfo) []const u8 {
            return self.age;
        }
        fn getStatus(self: *const NamespaceInfo) []const u8 {
            return self.status;
        }
    };

    pub fn init(
        allocator: std.mem.Allocator,
        theme: *const theme_loader.ThemeColors,
        k8s_service: *K8sService,
    ) !NamespacesView {
        const current_ns = k8s_service.getCurrentNamespace();

        return NamespacesView{
            .theme = theme,
            .k8s_service = k8s_service,
            .table = TableState(NamespaceInfo).init(allocator),
            .current_namespace = try allocator.dupe(u8, current_ns),
        };
    }

    pub fn deinit(self: *NamespacesView) void {
        self.table.allocator.free(self.current_namespace);
        self.table.deinit();
    }

    pub fn bindProjection(self: *NamespacesView, projection: *NamespaceProjection) void {
        self.projection = projection;
    }

    pub fn markSubscriptionStarted(self: *NamespacesView) void {
        self.subscription_started = true;
        self.subscription_request = .none;
    }

    pub fn markSubscriptionStopped(self: *NamespacesView) void {
        self.subscription_started = false;
    }

    pub fn takeSubscriptionRequest(self: *NamespacesView) SubscriptionRequest {
        const request = self.subscription_request;
        self.subscription_request = .none;
        return request;
    }

    /// Refresh namespaces list from K8s API
    pub fn refresh(self: *NamespacesView) !void {
        if (active_namespace_source == .data_plane and self.projection != null) {
            self.table.loading = self.table.items.items.len == 0;
            self.subscription_request = if (self.subscription_started) .restart else .start;
            return;
        }
        if (legacy_loader_test_hook) |hook| {
            hook();
            return;
        }
        // Remember the selected namespace name before clearItems frees the rows.
        const preserve_name_owned: ?[]const u8 = if (self.table.getSelectedItem()) |item|
            try self.table.allocator.dupe(u8, item.name)
        else
            null;
        defer if (preserve_name_owned) |name| self.table.allocator.free(name);
        const preserve_scroll = self.table.scroll_offset;

        const had_items = self.table.items.items.len > 0;
        if (!had_items) self.table.loading = true;
        defer if (!had_items) {
            self.table.loading = false;
        };
        self.table.clearItems();

        // SAFETY: Check if connected to k8s before making requests
        if (!self.k8s_service.isConnected()) {
            try self.table.setError("Not connected to Kubernetes cluster");
            Logger.warn("NamespacesView: Cannot refresh - not connected to k8s", .{});
            return;
        }

        // Fetch namespaces. Keep the parsed list alive for the whole loop: the
        // items' status (json.Value) references its arena, so deinit must wait
        // until after we've copied out the fields we need.
        var ns_list = self.k8s_service.listNamespaces() catch |err| {
            try self.table.setConnectionError("namespaces", err);
            return;
        };
        defer ns_list.deinit();

        // Convert to NamespaceInfo
        for (ns_list.items()) |ns| {
            // Extract status from JSON value
            const status = if (ns.status) |status_json| blk: {
                if (status_json == .object) {
                    if (status_json.object.get("phase")) |phase| {
                        if (phase == .string) {
                            break :blk try self.table.allocator.dupe(u8, phase.string);
                        }
                    }
                }
                break :blk try self.table.allocator.dupe(u8, "Active");
            } else try self.table.allocator.dupe(u8, "Unknown");

            const info = NamespaceInfo{
                .name = try self.table.allocator.dupe(u8, ns.metadata.name),
                .status = status,
                .age = try age_util.calculateAge(self.table.allocator, ns.metadata.creationTimestamp),
                .uid = if (ns.metadata.uid) |uid|
                    try self.table.allocator.dupe(u8, uid)
                else
                    &.{},
                .allocator = self.table.allocator,
            };

            try self.table.appendItem(info);
        }

        Logger.info("Loaded {} namespaces", .{self.table.items.items.len});

        // Rebuild filtered indices
        try self.applyFilter(self.table.filter_text);
        self.restoreSelectionAfterRefresh(preserve_name_owned, preserve_scroll);
    }

    pub fn syncProjection(self: *NamespacesView) !void {
        const projection = self.projection orelse return;
        if (self.table.getSelectedItem()) |selected| {
            if (selected.uid.len > 0) _ = projection.selectUid(selected.uid);
        }

        var next_items: std.ArrayListUnmanaged(NamespaceInfo) = .empty;
        errdefer {
            for (next_items.items) |*item| item.deinit();
            next_items.deinit(self.table.allocator);
        }
        var next_indices: std.ArrayListUnmanaged(usize) = .empty;
        errdefer next_indices.deinit(self.table.allocator);
        try next_items.ensureTotalCapacity(self.table.allocator, projection.visibleCount());
        try next_indices.ensureTotalCapacity(self.table.allocator, projection.visibleCount());

        var row: usize = 0;
        while (row < projection.visibleCount()) : (row += 1) {
            const uid = projection.visibleUid(row) orelse continue;
            const record = projection.record(uid) orelse continue;
            const name = try self.table.allocator.dupe(u8, record.key.name);
            var name_owned = true;
            errdefer if (name_owned) self.table.allocator.free(name);
            const status = try self.table.allocator.dupe(u8, record.status);
            var status_owned = true;
            errdefer if (status_owned) self.table.allocator.free(status);
            const age = try record.age(self.table.allocator);
            var age_owned = true;
            errdefer if (age_owned) self.table.allocator.free(age);
            const owned_uid = try self.table.allocator.dupe(u8, uid);
            next_items.appendAssumeCapacity(.{
                .name = name,
                .status = status,
                .age = age,
                .uid = owned_uid,
                .allocator = self.table.allocator,
            });
            name_owned = false;
            status_owned = false;
            age_owned = false;
            next_indices.appendAssumeCapacity(next_items.items.len - 1);
        }

        self.table.clearItems();
        self.table.items.deinit(self.table.allocator);
        self.table.filtered_indices.deinit(self.table.allocator);
        self.table.items = next_items;
        self.table.filtered_indices = next_indices;
        next_items = .empty;
        next_indices = .empty;
        self.table.loading = false;

        if (projection.selectedUid()) |selected_uid| {
            for (self.table.filtered_indices.items, 0..) |item_index, visible_index| {
                if (std.mem.eql(u8, self.table.items.items[item_index].uid, selected_uid)) {
                    self.table.selected_row = @intCast(visible_index);
                    break;
                }
            }
        }
    }

    fn restoreSelectionAfterRefresh(
        self: *NamespacesView,
        previous_name: ?[]const u8,
        previous_scroll: u32,
    ) void {
        const target_name = previous_name orelse self.current_namespace;
        const restore_idx: ?usize = blk: {
            for (self.table.items.items, 0..) |ns, i| {
                if (std.mem.eql(u8, ns.name, target_name)) break :blk i;
            }
            break :blk null;
        };
        if (restore_idx != null and previous_name != null) {
            self.table.scroll_offset = previous_scroll;
        }
        _ = filter_util.restoreSelectionByItemIndex(
            self.table.filtered_indices.items,
            restore_idx,
            &self.table.selected_row,
            &self.table.scroll_offset,
            self.table.visible_rows,
        );
    }

    pub fn getSelectedResourceInfo(self: *NamespacesView) ?ResourceInfo {
        const item = self.table.getSelectedItem() orelse return null;
        return ResourceInfo{
            .name = item.name,
            .namespace = "cluster",
        };
    }

    pub fn applyFilter(self: *NamespacesView, filter: []const u8) !void {
        if (active_namespace_source == .data_plane) {
            if (self.projection != null) {
                const owned_filter: []const u8 = if (filter.len > 0)
                    try self.table.allocator.dupe(u8, filter)
                else
                    "";
                errdefer if (owned_filter.len > 0) self.table.allocator.free(owned_filter);
                try self.setProjectionViewAndSync(
                    filter,
                    self.table.sort_column orelse COL_NAME,
                    self.table.sort_ascending,
                );
                if (self.table.filter_text.len > 0) self.table.allocator.free(self.table.filter_text);
                self.table.filter_text = owned_filter;
                return;
            }
        }
        try self.table.applyFilter(filter, namespaceMatchFn);
        self.applySorting();
    }

    fn applySorting(self: *NamespacesView) void {
        if (active_namespace_source == .data_plane) {
            if (self.projection != null) {
                self.setProjectionViewAndSync(
                    self.table.filter_text,
                    self.table.sort_column orelse COL_NAME,
                    self.table.sort_ascending,
                ) catch return;
                return;
            }
        }
        if (self.table.sort_column) |col| {
            switch (col) {
                COL_NAME => self.table.sortBy(NamespaceInfo.getName),
                COL_AGE => self.table.sortBy(NamespaceInfo.getAge),
                COL_STATUS => self.table.sortBy(NamespaceInfo.getStatus),
                else => {},
            }
        }
    }

    fn setProjectionViewAndSync(
        self: *NamespacesView,
        filter: []const u8,
        column: u8,
        ascending: bool,
    ) !void {
        const projection = self.projection orelse return;
        var rollback = try projection.captureView();
        projection.setView(filter, column, ascending) catch |err| {
            rollback.deinit(projection.allocator);
            return err;
        };
        self.syncProjection() catch |err| {
            projection.restoreView(&rollback);
            return err;
        };
        rollback.deinit(projection.allocator);
    }

    fn namespaceMatchFn(item: *const NamespaceInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null;
    }

    /// Switch to the selected namespace
    fn switchNamespace(self: *NamespacesView) !bool {
        const item = self.table.getSelectedItem() orelse return false;
        const selected_ns = item.name;
        const replacement = try self.table.allocator.dupe(u8, selected_ns);
        errdefer self.table.allocator.free(replacement);

        try self.k8s_service.setCurrentNamespace(selected_ns);

        self.table.allocator.free(self.current_namespace);
        self.current_namespace = replacement;

        Logger.info("Switched to namespace: {s}", .{selected_ns});
        return true;
    }

    fn handleNamespaceEnter(self: *NamespacesView) KeyResult {
        const switched = self.switchNamespace() catch |err| {
            Logger.err("Failed to switch namespace: {}", .{err});
            return .handled;
        };
        return if (switched) .namespace_switched else .handled;
    }

    pub fn createView(self: *NamespacesView) View {
        return View.create(NamespacesView, self, &vtable);
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

    fn vtableApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        try self.applyFilter(filter);
    }

    fn vtableClearFilter(ptr: *anyopaque) anyerror!bool {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        if (self.table.filter_text.len > 0) {
            try self.applyFilter("");
            return true;
        }
        return false;
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        try self.refresh();
    }

    fn vtableGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        return self.getSelectedResourceInfo();
    }

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        self.table.visible_rows = if (height > 1) height - 1 else 0;

        if (try self.table.renderStatus(terminal, x, y, self.theme)) return;

        // Render header row with sort indicators
        const header_y = y;
        const name_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_AGE);
        const status_ind = sort_util.sortIndicator(self.table.sort_column, self.table.sort_ascending, COL_STATUS);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        var status_hdr_buf: [32]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        const status_hdr = std.fmt.bufPrint(&status_hdr_buf, "STATUS{s}", .{status_ind}) catch "STATUS";
        try Theme.writeStringWithTheme(terminal, x, header_y, name_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 39, header_y, status_hdr, self.theme.title, self.theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 59, header_y, age_hdr, self.theme.title, self.theme.main_bg);

        // Render namespaces
        const range = self.table.getVisibleRange();
        for (self.table.filtered_indices.items[range.start..range.end], 0..) |ns_idx, i| {
            const ns = self.table.items.items[ns_idx];
            const colors = self.table.rowColors(i, self.theme);
            const is_current = std.mem.eql(
                u8,
                ns.name,
                self.k8s_service.getCurrentNamespace(),
            );
            const row_y = y + 1 + @as(u16, @intCast(i));

            // Paint the full row background first so inter-column gaps share
            // the row bg (no black seams behind/between the segmented columns).
            if (width > 0) {
                try terminal.fillRow(x, row_y, width, colors.fg, colors.bg);
            }

            // Current namespace indicator
            const indicator = if (is_current) "* " else "  ";
            try Theme.writeStringWithTheme(terminal, x, row_y, indicator, colors.fg, colors.bg);

            // Name
            try Theme.writeStringWithTheme(terminal, x + 2, row_y, ns.name[0..@min(36, ns.name.len)], colors.fg, colors.bg);

            // Status
            try Theme.writeStringWithTheme(terminal, x + 39, row_y, ns.status, colors.fg, colors.bg);

            // Age
            try Theme.writeStringWithTheme(terminal, x + 59, row_y, ns.age, colors.fg, colors.bg);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));

        // Common navigation keys
        if (self.table.handleNavigationKey(key)) |result| return result;

        // View-specific keys
        switch (key) {
            .ctrl_r => {
                self.refresh() catch |err| {
                    Logger.err("Failed to refresh namespaces: {}", .{err});
                };
                return .handled;
            },
            .char => |c| switch (c) {
                'r' => {
                    self.refresh() catch |err| {
                        Logger.err("Failed to refresh namespaces: {}", .{err});
                    };
                    return .handled;
                },
                '\n', '\r' => return self.handleNamespaceEnter(),
                'N' => {
                    self.table.toggleSort(COL_NAME);
                    self.applySorting();
                    return .handled;
                },
                'A' => {
                    self.table.toggleSort(COL_AGE);
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
            .enter => return self.handleNamespaceEnter(),
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        Logger.info("NamespacesView: View activated", .{});
        // Refresh data when view is shown - catch ALL errors to prevent crashes
        self.refresh() catch |err| {
            Logger.err("Failed to refresh namespaces: {any}", .{err});
            // Set a fallback error message if one wasn't already set
            if (self.table.error_message == null) {
                self.table.setError("Unexpected error during refresh") catch {
                    Logger.err("Failed to allocate error message", .{});
                    return;
                };
            }
        };
    }

    fn onHide(_: *anyopaque) void {
        Logger.debug("NamespacesView hidden", .{});
    }

    fn getName(_: *anyopaque) []const u8 {
        return "namespaces";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *NamespacesView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }
};

fn installNamespaceTestSession(
    allocator: std.mem.Allocator,
    service: *K8sService,
    shared_event: *std.Io.Event,
    slot: *ActiveSessionSlot,
) !void {
    slot.* = ActiveSessionSlot.init(runtime.io(), shared_event);
    const session = session: {
        const client = try allocator.create(klient.K8sClient);
        errdefer allocator.destroy(client);
        client.* = try klient.K8sClient.init(allocator, runtime.io(), .{
            .server = "http://127.0.0.1",
            .namespace = "default",
        });
        errdefer client.deinit();
        break :session try ActiveContextSession.adopt(
            allocator,
            runtime.io(),
            1,
            .{
                .context_name = "test-context",
                .kubeconfig_path = null,
                .default_namespace = "default",
                .force_proxy = false,
                .readonly = false,
            },
            .{
                .shared_event = shared_event,
                .client = client,
                .cluster_name = "test-cluster",
                .user_name = "test-user",
                .readiness_verified = true,
            },
        );
    };
    errdefer session.deinit();
    _ = try slot.commit(session);
    service.bindSessionSlot(slot);
}

fn teardownNamespaceTestSession(
    service: *K8sService,
    slot: *ActiveSessionSlot,
) void {
    const removed = slot.invalidate(null) catch unreachable;
    service.detachSession();
    if (removed) |session| session.deinit();
    slot.deinit();
}

test "pressing Enter on a namespace signals namespace_switched" {
    // Behavioural, not structural. An earlier version of this guard only asserted
    // that the KeyResult variant EXISTED, which passed even with the return value
    // reverted to .handled -- decorative. This drives the real key handler.
    //
    // The bug: switching namespace updated the service and this view's own field but
    // signalled nothing, so the view returned to kept the PREVIOUS namespace's rows
    // (its onShow skips the network when rows exist) while getTitle read
    // current_namespace live. Title and rows disagreed, with nothing on screen saying
    // so. context_switched already worked; the namespace path never got it.
    const a = std.testing.allocator;

    var svc = try K8sService.init(a);
    defer svc.deinit();

    var shared_event: std.Io.Event = .unset;
    var slot = ActiveSessionSlot.init(runtime.io(), &shared_event);
    {
        const session = session: {
            const client = try a.create(klient.K8sClient);
            errdefer a.destroy(client);
            client.* = try klient.K8sClient.init(a, runtime.io(), .{
                .server = "http://127.0.0.1",
                .namespace = "default",
            });
            errdefer client.deinit();
            break :session try ActiveContextSession.adopt(
                a,
                runtime.io(),
                1,
                .{
                    .context_name = "test-context",
                    .kubeconfig_path = null,
                    .default_namespace = "default",
                    .force_proxy = false,
                    .readonly = false,
                },
                .{
                    .shared_event = &shared_event,
                    .client = client,
                    .cluster_name = "test-cluster",
                    .user_name = "test-user",
                    .readiness_verified = true,
                },
            );
        };
        errdefer session.deinit();
        _ = try slot.commit(session);
    }
    svc.bindSessionSlot(&slot);
    defer {
        const removed = slot.invalidate(null) catch unreachable;
        svc.detachSession();
        if (removed) |active| active.deinit();
        slot.deinit();
    }

    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);

    var view = try NamespacesView.init(a, &theme, &svc);
    defer view.deinit();

    try view.table.appendItem(.{
        .name = try a.dupe(u8, "kube-system"),
        .status = try a.dupe(u8, "Active"),
        .age = try a.dupe(u8, "1d"),
        .allocator = a,
    });
    try view.table.filtered_indices.append(a, 0);
    view.table.selected_row = 0;

    const result = try NamespacesView.handleKey(&view, .enter);
    try std.testing.expectEqual(KeyResult.namespace_switched, result);

    // And the switch actually took effect, so the signal is not cosmetic.
    try std.testing.expectEqualStrings("kube-system", svc.getCurrentNamespace());
}

test "namespace Enter is atomic when the view replacement allocation fails" {
    var view_failing = std.testing.FailingAllocator.init(std.testing.allocator, .{});
    const view_allocator = view_failing.allocator();

    var svc = try K8sService.init(std.testing.allocator);
    defer svc.deinit();
    var shared_event: std.Io.Event = .unset;
    var slot: ActiveSessionSlot = undefined;
    try installNamespaceTestSession(
        std.testing.allocator,
        &svc,
        &shared_event,
        &slot,
    );
    defer teardownNamespaceTestSession(&svc, &slot);

    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    var view = try NamespacesView.init(view_allocator, &theme, &svc);
    defer view.deinit();
    try view.table.appendItem(.{
        .name = try view_allocator.dupe(u8, "kube-system"),
        .status = try view_allocator.dupe(u8, "Active"),
        .age = try view_allocator.dupe(u8, "1d"),
        .allocator = view_allocator,
    });
    try view.table.filtered_indices.append(view_allocator, 0);

    view_failing.fail_index = view_failing.alloc_index;
    const result = try NamespacesView.handleKey(&view, .enter);

    try std.testing.expectEqual(KeyResult.handled, result);
    try std.testing.expectEqualStrings("default", svc.getCurrentNamespace());
    try std.testing.expectEqualStrings("default", view.current_namespace);
}

test "namespace Enter is atomic at every service replacement allocation" {
    for (0..2) |relative_fail_index| {
        var service_failing = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{},
        );
        const service_allocator = service_failing.allocator();

        var svc = try K8sService.init(service_allocator);
        defer svc.deinit();
        var shared_event: std.Io.Event = .unset;
        var slot: ActiveSessionSlot = undefined;
        try installNamespaceTestSession(
            service_allocator,
            &svc,
            &shared_event,
            &slot,
        );
        defer teardownNamespaceTestSession(&svc, &slot);

        var theme = try theme_loader.defaultTheme(std.testing.allocator);
        defer theme_loader.deinitTheme(&theme);
        var view = try NamespacesView.init(std.testing.allocator, &theme, &svc);
        defer view.deinit();
        try view.table.appendItem(.{
            .name = try std.testing.allocator.dupe(u8, "kube-system"),
            .status = try std.testing.allocator.dupe(u8, "Active"),
            .age = try std.testing.allocator.dupe(u8, "1d"),
            .allocator = std.testing.allocator,
        });
        try view.table.filtered_indices.append(std.testing.allocator, 0);

        service_failing.fail_index =
            service_failing.alloc_index + relative_fail_index;
        const result = try NamespacesView.handleKey(&view, .enter);

        try std.testing.expectEqual(KeyResult.handled, result);
        try std.testing.expectEqualStrings("default", svc.getCurrentNamespace());
        try std.testing.expectEqualStrings("default", view.current_namespace);
    }
}

test "namespace selection survives a reordered refresh" {
    const a = std.testing.allocator;

    var svc = try K8sService.init(a);
    defer svc.deinit();

    var theme = try theme_loader.defaultTheme(a);
    defer theme_loader.deinitTheme(&theme);

    var view = try NamespacesView.init(a, &theme, &svc);
    defer view.deinit();

    const names = [_][]const u8{ "alpha", "beta", "gamma", "delta" };
    for (names) |name| {
        try view.table.appendItem(.{
            .name = try a.dupe(u8, name),
            .status = try a.dupe(u8, "Active"),
            .age = try a.dupe(u8, "1d"),
            .allocator = a,
        });
    }
    try view.applyFilter("");
    view.table.selected_row = 2;
    view.table.scroll_offset = 1;
    view.table.visible_rows = 2;

    const preserve_name = try a.dupe(u8, "gamma");
    defer a.free(preserve_name);

    view.table.clearItems();
    const refreshed_names = [_][]const u8{ "delta", "gamma", "alpha", "beta" };
    for (refreshed_names) |name| {
        try view.table.appendItem(.{
            .name = try a.dupe(u8, name),
            .status = try a.dupe(u8, "Active"),
            .age = try a.dupe(u8, "2d"),
            .allocator = a,
        });
    }
    try view.applyFilter("");
    view.restoreSelectionAfterRefresh(preserve_name, 1);

    try std.testing.expectEqual(@as(u32, 1), view.table.selected_row);
    try std.testing.expectEqual(@as(u32, 1), view.table.scroll_offset);

    const selected = view.table.getSelectedItem().?;
    try std.testing.expectEqualStrings("gamma", selected.name);
}

test "namespace projection preserves current namespace and UID selection across watch update" {
    const keys = @import("../k8s/ResourceKey.zig");
    const allocator = std.testing.allocator;
    const ProjectionFns = struct {
        fn match(record: *const NamespaceRecord, filter: []const u8) bool {
            return filter.len == 0 or std.mem.indexOf(u8, record.key.name, filter) != null;
        }
        fn sort(record: *const NamespaceRecord, _: u8) []const u8 {
            return record.key.name;
        }
    };
    var projection = NamespaceProjection.init(allocator, .{
        .matchFn = ProjectionFns.match,
        .sortKeyFn = ProjectionFns.sort,
    });
    defer projection.deinit();
    var service = try K8sService.init(allocator);
    defer service.deinit();
    allocator.free(service.current_namespace);
    service.current_namespace = try allocator.dupe(u8, "team-a");
    var theme: theme_loader.ThemeColors = undefined;
    var view = try NamespacesView.init(allocator, &theme, &service);
    defer view.deinit();
    view.bindProjection(&projection);

    const initial = try allocator.alloc(keys.TypedChange(NamespaceRecord), 2);
    initial[0] = .{ .initial_upsert = .{
        .key = try (keys.ObjectKey{ .uid = "uid-a", .namespace = "", .name = "team-a" }).clone(allocator),
        .status = try allocator.dupe(u8, "Active"),
    } };
    initial[1] = .{ .initial_upsert = .{
        .key = try (keys.ObjectKey{ .uid = "uid-b", .namespace = "", .name = "team-b" }).clone(allocator),
        .status = try allocator.dupe(u8, "Active"),
    } };
    var batch = keys.TypedBatch(NamespaceRecord){
        .generation = 1,
        .subscription_id = 2,
        .revision = 1,
        .changes = initial,
        .sync = .list_started,
        .owned_bytes = 1,
    };
    defer batch.deinit(allocator);
    var plan = try NamespaceProjection.handler().preflight(@ptrCast(&projection), &batch, allocator);
    NamespaceProjection.handler().commit(@ptrCast(&projection), &batch, &plan);
    plan.deinit(allocator);
    try view.syncProjection();
    try std.testing.expectEqualStrings("team-a", view.current_namespace);
    view.table.selected_row = 1;
    try view.syncProjection();

    const update = try allocator.alloc(keys.TypedChange(NamespaceRecord), 1);
    update[0] = .{ .watch_upsert = .{
        .key = try (keys.ObjectKey{ .uid = "uid-b", .namespace = "", .name = "team-b" }).clone(allocator),
        .status = try allocator.dupe(u8, "Terminating"),
    } };
    var update_batch = keys.TypedBatch(NamespaceRecord){
        .generation = 1,
        .subscription_id = 2,
        .revision = 2,
        .changes = update,
        .sync = null,
        .owned_bytes = 1,
    };
    defer update_batch.deinit(allocator);
    var update_plan = try NamespaceProjection.handler().preflight(
        @ptrCast(&projection),
        &update_batch,
        allocator,
    );
    NamespaceProjection.handler().commit(@ptrCast(&projection), &update_batch, &update_plan);
    update_plan.deinit(allocator);
    try view.syncProjection();
    try std.testing.expectEqualStrings("team-a", view.current_namespace);
    try std.testing.expectEqualStrings("uid-b", projection.selectedUid().?);
    try std.testing.expectEqualStrings("team-b", view.table.getSelectedItem().?.name);
    try std.testing.expectEqualStrings("Terminating", view.table.getSelectedItem().?.status);
}

test "namespace projection sync OOM preserves table selection and current namespace" {
    const keys = @import("../k8s/ResourceKey.zig");
    const backing = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(backing, .{});
    const ProjectionFns = struct {
        fn match(_: *const NamespaceRecord, _: []const u8) bool {
            return true;
        }
        fn sort(record: *const NamespaceRecord, _: u8) []const u8 {
            return record.key.name;
        }
    };
    var projection = NamespaceProjection.init(backing, .{
        .matchFn = ProjectionFns.match,
        .sortKeyFn = ProjectionFns.sort,
    });
    defer projection.deinit();
    var service = try K8sService.init(backing);
    defer service.deinit();
    var theme: theme_loader.ThemeColors = undefined;
    var view = try NamespacesView.init(failing.allocator(), &theme, &service);
    defer view.deinit();
    view.bindProjection(&projection);

    const changes = try backing.alloc(keys.TypedChange(NamespaceRecord), 1);
    changes[0] = .{ .initial_upsert = .{
        .key = try (keys.ObjectKey{ .uid = "uid-a", .namespace = "", .name = "default" }).clone(backing),
        .status = try backing.dupe(u8, "Active"),
    } };
    var batch = keys.TypedBatch(NamespaceRecord){
        .generation = 1,
        .subscription_id = 2,
        .revision = 1,
        .changes = changes,
        .sync = .list_started,
        .owned_bytes = 1,
    };
    defer batch.deinit(backing);
    var plan = try NamespaceProjection.handler().preflight(@ptrCast(&projection), &batch, backing);
    NamespaceProjection.handler().commit(@ptrCast(&projection), &batch, &plan);
    plan.deinit(backing);
    try view.syncProjection();
    const selected_before = view.table.getSelectedItem().?.uid;
    const visible_before = projection.visibleUid(0).?;
    failing.fail_index = failing.alloc_index + 1;
    try std.testing.expectError(error.OutOfMemory, view.applyFilter("def"));
    try std.testing.expectEqualStrings("default", view.current_namespace);
    try std.testing.expectEqualStrings(selected_before, view.table.getSelectedItem().?.uid);
    try std.testing.expectEqualStrings(visible_before, projection.visibleUid(0).?);
    try std.testing.expectEqual(@as(usize, 1), projection.visibleCount());
    try std.testing.expectEqualStrings("", view.table.filter_text);
}

test "namespace rollback gate retains legacy list path" {
    const previous = active_namespace_source;
    defer active_namespace_source = previous;
    const previous_hook = legacy_loader_test_hook;
    defer legacy_loader_test_hook = previous_hook;
    const Probe = struct {
        var calls: usize = 0;
        fn load() void {
            calls += 1;
        }
    };
    Probe.calls = 0;
    active_namespace_source = .legacy_list;
    legacy_loader_test_hook = Probe.load;
    var service = try K8sService.init(std.testing.allocator);
    defer service.deinit();
    var theme: theme_loader.ThemeColors = undefined;
    var view = try NamespacesView.init(std.testing.allocator, &theme, &service);
    defer view.deinit();
    try view.refresh();
    try std.testing.expectEqual(@as(usize, 1), Probe.calls);
    try std.testing.expectEqual(NamespacesView.SubscriptionRequest.none, view.takeSubscriptionRequest());
}
