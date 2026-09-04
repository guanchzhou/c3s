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
const k9s_query = @import("../viewmodel/k9s_query.zig");
const filter_util = @import("../viewmodel/filter.zig");
const PodRecord = @import("../k8s/PodRecord.zig");
const PodProjection = @import("../k8s/ResourceProjection.zig").ResourceProjection(PodRecord);
const projection_mod = @import("../k8s/ResourceProjection.zig");

pub const Source = enum { data_plane, legacy_list };
pub const PodSource = Source;
pub const ResourceFamily = enum { services, config, workloads, batch, networking, storage };
pub const ResourceSourceRegistry = struct {
    services: Source = .data_plane,
    config: Source = .data_plane,
    workloads: Source = .data_plane,
    batch: Source = .data_plane,
    networking: Source = .data_plane,
    storage: Source = .data_plane,

    pub fn sourceFor(self: ResourceSourceRegistry, family: ResourceFamily) Source {
        return switch (family) {
            .services => self.services,
            .config => self.config,
            .workloads => self.workloads,
            .batch => self.batch,
            .networking => self.networking,
            .storage => self.storage,
        };
    }
};
pub var active_pod_source: Source = .data_plane;
pub var active_node_source: Source = .data_plane;
pub var active_services_source: Source = .data_plane;
pub var active_config_source: Source = .data_plane;
pub var active_workloads_source: Source = .data_plane;
pub var active_batch_source: Source = .data_plane;
pub var active_networking_source: Source = .data_plane;
pub var active_storage_source: Source = .data_plane;
pub var legacy_loader_test_hook: ?*const fn ([]const u8) void = null;

pub fn familySourceRegistry() ResourceSourceRegistry {
    return .{
        .services = active_services_source,
        .config = active_config_source,
        .workloads = active_workloads_source,
        .batch = active_batch_source,
        .networking = active_networking_source,
        .storage = active_storage_source,
    };
}

test "resource family source gates are independent" {
    const previous_services = active_services_source;
    const previous_config = active_config_source;
    const previous_workloads = active_workloads_source;
    const previous_batch = active_batch_source;
    const previous_networking = active_networking_source;
    const previous_storage = active_storage_source;
    defer {
        active_services_source = previous_services;
        active_config_source = previous_config;
        active_workloads_source = previous_workloads;
        active_batch_source = previous_batch;
        active_networking_source = previous_networking;
        active_storage_source = previous_storage;
    }
    active_services_source = .data_plane;
    active_config_source = .legacy_list;
    active_workloads_source = .data_plane;
    active_batch_source = .legacy_list;
    active_networking_source = .data_plane;
    active_storage_source = .legacy_list;
    var registry = familySourceRegistry();
    try std.testing.expectEqual(Source.data_plane, registry.sourceFor(.services));
    try std.testing.expectEqual(Source.legacy_list, registry.sourceFor(.config));
    try std.testing.expectEqual(Source.data_plane, registry.sourceFor(.workloads));
    try std.testing.expectEqual(Source.legacy_list, registry.sourceFor(.batch));
    try std.testing.expectEqual(Source.data_plane, registry.sourceFor(.networking));
    try std.testing.expectEqual(Source.legacy_list, registry.sourceFor(.storage));
    active_services_source = .legacy_list;
    active_config_source = .data_plane;
    active_workloads_source = .legacy_list;
    active_batch_source = .data_plane;
    active_networking_source = .legacy_list;
    active_storage_source = .data_plane;
    registry = familySourceRegistry();
    try std.testing.expectEqual(Source.legacy_list, registry.sourceFor(.services));
    try std.testing.expectEqual(Source.data_plane, registry.sourceFor(.config));
    try std.testing.expectEqual(Source.legacy_list, registry.sourceFor(.workloads));
    try std.testing.expectEqual(Source.data_plane, registry.sourceFor(.batch));
    try std.testing.expectEqual(Source.legacy_list, registry.sourceFor(.networking));
    try std.testing.expectEqual(Source.data_plane, registry.sourceFor(.storage));
}

test "batch source changes do not alter existing family gates" {
    const previous_services = active_services_source;
    const previous_config = active_config_source;
    const previous_workloads = active_workloads_source;
    const previous_batch = active_batch_source;
    defer {
        active_services_source = previous_services;
        active_config_source = previous_config;
        active_workloads_source = previous_workloads;
        active_batch_source = previous_batch;
    }
    active_services_source = .data_plane;
    active_config_source = .legacy_list;
    active_workloads_source = .data_plane;
    active_batch_source = .data_plane;
    const before = familySourceRegistry();
    active_batch_source = .legacy_list;
    const after = familySourceRegistry();
    try std.testing.expectEqual(before.services, after.services);
    try std.testing.expectEqual(before.config, after.config);
    try std.testing.expectEqual(before.workloads, after.workloads);
    try std.testing.expect(before.batch != after.batch);
}

test "networking source changes do not alter existing family gates" {
    const previous_services = active_services_source;
    const previous_config = active_config_source;
    const previous_workloads = active_workloads_source;
    const previous_batch = active_batch_source;
    const previous_networking = active_networking_source;
    defer {
        active_services_source = previous_services;
        active_config_source = previous_config;
        active_workloads_source = previous_workloads;
        active_batch_source = previous_batch;
        active_networking_source = previous_networking;
    }
    active_services_source = .legacy_list;
    active_config_source = .data_plane;
    active_workloads_source = .legacy_list;
    active_batch_source = .data_plane;
    active_networking_source = .data_plane;
    const before = familySourceRegistry();
    active_networking_source = .legacy_list;
    const after = familySourceRegistry();
    try std.testing.expectEqual(before.services, after.services);
    try std.testing.expectEqual(before.config, after.config);
    try std.testing.expectEqual(before.workloads, after.workloads);
    try std.testing.expectEqual(before.batch, after.batch);
    try std.testing.expect(before.networking != after.networking);
}

test "storage source changes do not alter existing family gates" {
    const previous = familySourceRegistry();
    const previous_storage = active_storage_source;
    defer active_storage_source = previous_storage;
    active_storage_source = if (previous_storage == .data_plane) .legacy_list else .data_plane;
    const after = familySourceRegistry();
    try std.testing.expectEqual(previous.services, after.services);
    try std.testing.expectEqual(previous.config, after.config);
    try std.testing.expectEqual(previous.workloads, after.workloads);
    try std.testing.expectEqual(previous.batch, after.batch);
    try std.testing.expectEqual(previous.networking, after.networking);
    try std.testing.expect(previous.storage != after.storage);
}

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
        const is_pods = std.mem.eql(u8, config.name, "pods");

        pub const SubscriptionRequest = enum { none, start, restart };
        pub const PodSubscriptionRequest = SubscriptionRequest;

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
        projection_adapter: ?ProjectionAdapter = null,
        subscription_started: bool = false,
        subscription_request: SubscriptionRequest = .none,
        /// Column display order, and how many of them are shown.
        ///
        /// Populated once at init from views.yaml. `column_order[0..visible_columns]`
        /// are the indices to render, in order; anything not listed is hidden by being
        /// excluded here AND force-hidden in the width calc, so its space is handed to
        /// the remaining columns rather than left blank.
        ///
        /// Defaults to identity order with everything visible, so an absent views.yaml
        /// changes nothing.
        column_order: [col_count]u8 = undefined,
        visible_columns: u8 = col_count,
        /// Scratch buffer for the decorated box title ("pods(default)[8]").
        title_buf: [192]u8 = undefined,
        /// k9s ctrl-w: when false, VERY_LOW (CPU/MEM) columns are force-hidden.
        /// Defaults true so an existing wide terminal still shows metrics.
        show_wide: bool = true,
        /// k9s ctrl-z: keep only rows whose STATUS/READY look unhealthy.
        faults_only: bool = false,
        cached_show_wide: bool = true,
        /// Set by handleKey when a refresh must paint a loading frame first.
        refresh_pending: bool = false,

        /// Row data: uniform array of display strings
        pub const RowData = struct {
            columns: [col_count][]const u8,
            allocator: std.mem.Allocator,
            uid: []const u8 = &.{},
            /// Flattened `k=v,k=v` from metadata.labels. Empty slice is not owned.
            labels: []const u8 = &.{},

            pub fn deinit(self: *RowData) void {
                for (&self.columns) |*col| {
                    self.allocator.free(col.*);
                }
                if (self.labels.len > 0) self.allocator.free(self.labels);
                if (self.uid.len > 0) self.allocator.free(self.uid);
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

        pub const ProjectionAdapter = struct {
            pub const ViewRollback = struct {
                ptr: *anyopaque,
                alignment: std.mem.Alignment,
                restoreFn: *const fn (*anyopaque, *anyopaque, std.mem.Allocator) void,
                deinitFn: *const fn (*anyopaque, std.mem.Alignment, std.mem.Allocator) void,

                fn restore(self: *ViewRollback, projection: *anyopaque, allocator: std.mem.Allocator) void {
                    self.restoreFn(projection, self.ptr, allocator);
                    self.ptr = undefined;
                }

                fn deinit(self: *ViewRollback, allocator: std.mem.Allocator) void {
                    self.deinitFn(self.ptr, self.alignment, allocator);
                    self.ptr = undefined;
                }
            };

            ptr: *anyopaque,
            enabledFn: *const fn () bool,
            countFn: *const fn (*anyopaque) usize,
            visibleCountFn: *const fn (*anyopaque) usize,
            visibleUidFn: *const fn (*anyopaque, usize) ?[]const u8,
            selectedUidFn: *const fn (*anyopaque) ?[]const u8,
            selectUidFn: *const fn (*anyopaque, []const u8) bool,
            captureViewFn: *const fn (*anyopaque, std.mem.Allocator) anyerror!ViewRollback,
            setViewFn: *const fn (*anyopaque, []const u8, u8, bool) anyerror!void,
            columnsFn: *const fn (*anyopaque, []const u8, std.mem.Allocator) anyerror!?[col_count][]const u8,

            fn enabled(self: ProjectionAdapter) bool {
                return self.enabledFn();
            }

            pub fn init(
                comptime Record: type,
                projection: *projection_mod.ResourceProjection(Record),
                comptime enabled_fn: fn () bool,
                comptime columns_fn: fn (
                    *projection_mod.ResourceProjection(Record),
                    *const Record,
                    std.mem.Allocator,
                ) anyerror![col_count][]const u8,
            ) ProjectionAdapter {
                const Projection = projection_mod.ResourceProjection(Record);
                const Adapter = struct {
                    fn typedProjection(raw: *anyopaque) *Projection {
                        return @ptrCast(@alignCast(raw));
                    }
                    fn count(raw: *anyopaque) usize {
                        return typedProjection(raw).count();
                    }
                    fn visibleCount(raw: *anyopaque) usize {
                        return typedProjection(raw).visibleCount();
                    }
                    fn visibleUid(raw: *anyopaque, row: usize) ?[]const u8 {
                        return typedProjection(raw).visibleUid(row);
                    }
                    fn selectedUid(raw: *anyopaque) ?[]const u8 {
                        return typedProjection(raw).selectedUid();
                    }
                    fn selectUid(raw: *anyopaque, uid: []const u8) bool {
                        return typedProjection(raw).selectUid(uid);
                    }
                    fn captureView(raw: *anyopaque, allocator: std.mem.Allocator) anyerror!ViewRollback {
                        const Snapshot = Projection.ViewSnapshot;
                        const snapshot = try allocator.create(Snapshot);
                        errdefer allocator.destroy(snapshot);
                        snapshot.* = try typedProjection(raw).captureView();
                        return .{
                            .ptr = snapshot,
                            .alignment = .of(Snapshot),
                            .restoreFn = restoreView,
                            .deinitFn = adapterDeinitView,
                        };
                    }
                    fn restoreView(raw: *anyopaque, erased: *anyopaque, allocator: std.mem.Allocator) void {
                        const snapshot: *Projection.ViewSnapshot = @ptrCast(@alignCast(erased));
                        typedProjection(raw).restoreView(snapshot);
                        allocator.destroy(snapshot);
                    }
                    fn adapterDeinitView(
                        erased: *anyopaque,
                        _: std.mem.Alignment,
                        allocator: std.mem.Allocator,
                    ) void {
                        const snapshot: *Projection.ViewSnapshot = @ptrCast(@alignCast(erased));
                        snapshot.deinit(snapshot.allocator);
                        allocator.destroy(snapshot);
                    }
                    fn setView(
                        raw: *anyopaque,
                        filter: []const u8,
                        column: u8,
                        ascending: bool,
                    ) anyerror!void {
                        try typedProjection(raw).setView(filter, column, ascending);
                    }
                    fn columns(
                        raw: *anyopaque,
                        uid: []const u8,
                        allocator: std.mem.Allocator,
                    ) anyerror!?[col_count][]const u8 {
                        const typed = typedProjection(raw);
                        const record = typed.record(uid) orelse return null;
                        return try columns_fn(typed, record, allocator);
                    }
                };
                return .{
                    .ptr = @ptrCast(projection),
                    .enabledFn = enabled_fn,
                    .countFn = Adapter.count,
                    .visibleCountFn = Adapter.visibleCount,
                    .visibleUidFn = Adapter.visibleUid,
                    .selectedUidFn = Adapter.selectedUid,
                    .selectUidFn = Adapter.selectUid,
                    .captureViewFn = Adapter.captureView,
                    .setViewFn = Adapter.setView,
                    .columnsFn = Adapter.columns,
                };
            }
        };

        /// Build column_order / visible_columns from views.yaml, if it names this view.
        ///
        /// Unknown column names are skipped with a warning rather than being an error:
        /// a stale views.yaml naming a column that was renamed must not blank the view.
        /// The name column is always included, wherever the user put it -- it is the
        /// row identity used by describe, delete and marks, and a table of unlabelled
        /// rows is useless.
        /// Which columns the width calculator must give zero width to.
        ///
        /// Two sources: the NAMESPACE column in single-namespace scope (every row shares
        /// the value, so showing it wastes a column), and any column views.yaml left
        /// out. Both go through force-hiding rather than being skipped at draw time,
        /// because that is what hands their width budget to the columns that ARE shown
        /// -- skipping later would leave a gap and needlessly drop a low-priority column
        /// to make room for one that is never drawn.
        ///
        /// pub so a test can assert the mask rather than infer it from rendered output.
        pub fn hiddenMask(self: *const Self) [col_count]bool {
            var mask = [_]bool{false} ** col_count;

            if (config.is_namespaced and !self.table.show_all_namespaces) {
                if (config.namespace_column) |ns_col| mask[ns_col] = true;
            }

            if (self.visible_columns < col_count) {
                var listed = [_]bool{false} ** col_count;
                for (self.column_order[0..self.visible_columns]) |ci| listed[ci] = true;
                for (0..col_count) |ci| {
                    if (!listed[ci]) mask[ci] = true;
                }
            }

            if (!self.show_wide) {
                inline for (config.columns, 0..) |cd, ci| {
                    if (cd.priority == table_layout.ColumnPriority.VERY_LOW) mask[ci] = true;
                }
            }
            return mask;
        }

        pub fn applyViewsConfig(self: *Self) void {
            for (0..col_count) |i| self.column_order[i] = @intCast(i);
            self.visible_columns = col_count;

            const views_config = @import("../model/views_config.zig");
            const cfg = views_config.get() orelse return;
            const wanted = cfg.forView(config.name) orelse return;

            var order: [col_count]u8 = undefined;
            var n: u8 = 0;
            var used = [_]bool{false} ** col_count;

            for (wanted) |want| {
                var found = false;
                inline for (config.columns, 0..) |cd, ci| {
                    if (!used[ci] and std.ascii.eqlIgnoreCase(cd.name, want)) {
                        order[n] = @intCast(ci);
                        used[ci] = true;
                        n += 1;
                        found = true;
                    }
                }
                if (!found) {
                    Logger.warn("views.yaml: {s} has no column '{s}'", .{ config.name, want });
                }
            }

            if (n == 0) {
                Logger.warn("views.yaml: {s} listed no known columns; using defaults", .{config.name});
                return;
            }

            // Always keep the name column: it is the row identity for describe, delete
            // and marks, and rows without it cannot be told apart.
            if (!used[config.name_column]) {
                Logger.warn("views.yaml: {s} omitted the name column; keeping it", .{config.name});
                order[n] = @intCast(config.name_column);
                n += 1;
            }

            self.column_order = order;
            self.visible_columns = n;
        }

        pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !Self {
            var tbl = TableState(RowData).init(allocator);
            if (config.default_all_namespaces) tbl.show_all_namespaces = true;
            var self = Self{
                .theme = theme,
                .k8s_service = k8s_service,
                .table = tbl,
            };
            // Read views.yaml once, here, rather than per frame.
            self.applyViewsConfig();
            return self;
        }

        pub fn deinit(self: *Self) void {
            if (self.cached_col_widths) |*w| w.deinit();
            self.table.deinit();
        }

        pub fn bindProjection(self: *Self, adapter: ProjectionAdapter) void {
            self.projection_adapter = adapter;
        }

        pub fn bindPodProjection(self: *Self, projection: *PodProjection) void {
            if (is_pods) {
                self.bindProjection(ProjectionAdapter.init(
                    PodRecord,
                    projection,
                    podDataPlaneEnabled,
                    podProjectionColumns,
                ));
            }
        }

        fn usesDataPlane(self: *const Self) bool {
            const adapter = self.projection_adapter orelse
                return is_pods and active_pod_source == .data_plane;
            return adapter.enabled();
        }

        pub fn markSubscriptionStarted(self: *Self) void {
            self.subscription_started = true;
            self.subscription_request = .none;
        }

        pub fn markSubscriptionStopped(self: *Self) void {
            self.subscription_started = false;
        }

        pub fn takeSubscriptionRequest(self: *Self) SubscriptionRequest {
            const request = self.subscription_request;
            self.subscription_request = .none;
            return request;
        }

        pub fn markPodSubscriptionStarted(self: *Self) void {
            if (is_pods) self.markSubscriptionStarted();
        }

        pub fn markPodSubscriptionStopped(self: *Self) void {
            if (is_pods) self.markSubscriptionStopped();
        }

        pub fn takePodSubscriptionRequest(self: *Self) PodSubscriptionRequest {
            if (!is_pods) return .none;
            return self.takeSubscriptionRequest();
        }

        pub fn refresh(self: *Self) !void {
            if (self.usesDataPlane()) {
                self.table.loading = self.table.items.items.len == 0;
                self.table.loading_detail = "Loading " ++ config.name ++ "...";
                self.subscription_request = if (self.subscription_started) .restart else .start;
                return;
            }
            if (legacy_loader_test_hook) |hook| {
                hook(config.name);
                return;
            }
            // If connection not yet attempted, stay in loading state
            if (!self.k8s_service.isConnected() and !self.k8s_service.hasAttemptedConnect()) {
                self.table.loading = true;
                return;
            }

            const preserve_key_owned: ?[]const u8 = blk: {
                if (self.table.getSelectedItem()) |item| {
                    const name = item.columns[config.name_column];
                    if (config.namespace_column) |ns_col| {
                        break :blk try std.fmt.allocPrint(
                            self.table.allocator,
                            "{s}/{s}",
                            .{ item.columns[ns_col], name },
                        );
                    }
                    break :blk try self.table.allocator.dupe(u8, name);
                }
                break :blk null;
            };
            defer if (preserve_key_owned) |key| self.table.allocator.free(key);
            const preserve_scroll = self.table.scroll_offset;

            const had_items = self.table.items.items.len > 0;
            if (!had_items) self.table.loading = true;
            defer {
                self.table.loading = false;
                self.table.loading_detail = "";
            }
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
                const labels: []const u8 = blk: {
                    if (@hasField(KlientType, "metadata") and @hasField(@TypeOf(item.metadata), "labels")) {
                        if (item.metadata.labels) |lv| {
                            break :blk k9s_query.formatLabels(self.table.allocator, lv) catch &.{};
                        }
                    }
                    break :blk &.{};
                };
                errdefer if (labels.len > 0) self.table.allocator.free(labels);
                try self.table.appendItem(.{
                    .columns = cols,
                    .allocator = self.table.allocator,
                    .labels = labels,
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

            const restore_idx: ?usize = if (preserve_key_owned) |key| blk: {
                for (self.table.items.items, 0..) |row, i| {
                    const name = row.columns[config.name_column];
                    const matches = if (config.namespace_column) |ns_col| blk2: {
                        var keybuf: [512]u8 = undefined;
                        const row_key = std.fmt.bufPrint(
                            &keybuf,
                            "{s}/{s}",
                            .{ row.columns[ns_col], name },
                        ) catch continue;
                        break :blk2 std.mem.eql(u8, row_key, key);
                    } else std.mem.eql(u8, name, key);
                    if (matches) break :blk i;
                }
                break :blk null;
            } else null;
            if (restore_idx != null) self.table.scroll_offset = preserve_scroll;
            _ = filter_util.restoreSelectionByItemIndex(
                self.table.filtered_indices.items,
                restore_idx,
                &self.table.selected_row,
                &self.table.scroll_offset,
                self.table.visible_rows,
            );
        }

        /// Queue refresh so App can paint loading before the blocking list fetch.
        pub fn scheduleRefresh(self: *Self, hint: []const u8) void {
            self.table.loading = true;
            self.table.loading_detail = hint;
            if (self.usesDataPlane()) {
                self.subscription_request = if (self.subscription_started) .restart else .start;
                return;
            }
            self.refresh_pending = true;
        }

        pub fn flushPendingRefresh(self: *Self) bool {
            if (self.usesDataPlane()) return false;
            if (!self.refresh_pending) return false;
            self.refresh_pending = false;
            self.refresh() catch |err| {
                Logger.err("Failed to refresh {s}: {}", .{ config.name, err });
                self.table.loading = false;
                self.table.loading_detail = "";
            };
            return true;
        }

        pub fn getStatusHint(self: *const Self) ?[]const u8 {
            if (self.refresh_pending or self.table.loading) {
                if (self.table.loading_detail.len > 0) return self.table.loading_detail;
                return "Loading...";
            }
            return null;
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
            if (self.usesDataPlane()) {
                if (self.projection_adapter != null) {
                    const owned_filter: []const u8 = if (filter.len > 0)
                        try self.table.allocator.dupe(u8, filter)
                    else
                        "";
                    errdefer if (owned_filter.len > 0) self.table.allocator.free(owned_filter);
                    try self.setProjectionViewAndSync(
                        filter,
                        self.table.sort_column orelse config.name_column,
                        self.table.sort_ascending,
                    );
                    if (self.table.filter_text.len > 0) self.table.allocator.free(self.table.filter_text);
                    self.table.filter_text = owned_filter;
                    if (self.faults_only) self.retainFaultsOnly();
                    return;
                }
            } else try self.table.applyFilter(filter, matchFn);
            if (self.faults_only) self.retainFaultsOnly();
            self.applySorting();
        }

        fn setProjectionViewAndSync(
            self: *Self,
            filter: []const u8,
            column: u8,
            ascending: bool,
        ) !void {
            const adapter = self.projection_adapter orelse return;
            var rollback = try adapter.captureViewFn(adapter.ptr, self.table.allocator);
            adapter.setViewFn(adapter.ptr, filter, column, ascending) catch |err| {
                rollback.deinit(self.table.allocator);
                return err;
            };
            self.syncProjection() catch |err| {
                rollback.restore(adapter.ptr, self.table.allocator);
                return err;
            };
            rollback.deinit(self.table.allocator);
        }

        fn retainFaultsOnly(self: *Self) void {
            const status_i: ?u8 = comptime blk: {
                for (config.columns, 0..) |cd, i| {
                    if (std.mem.eql(u8, cd.name, "STATUS")) break :blk @as(u8, @intCast(i));
                }
                break :blk null;
            };
            const ready_i: ?u8 = comptime blk: {
                for (config.columns, 0..) |cd, i| {
                    if (std.mem.eql(u8, cd.name, "READY")) break :blk @as(u8, @intCast(i));
                }
                break :blk null;
            };
            const desired_i: ?u8 = comptime blk: {
                for (config.columns, 0..) |cd, i| {
                    if (std.mem.eql(u8, cd.name, "DESIRED")) break :blk @as(u8, @intCast(i));
                }
                break :blk null;
            };
            if (status_i == null and ready_i == null) return;

            var write: usize = 0;
            for (self.table.filtered_indices.items) |idx| {
                const row = &self.table.items.items[idx];
                const st: ?[]const u8 = if (status_i) |si| row.columns[si] else null;
                const rd: ?[]const u8 = if (ready_i) |ri| row.columns[ri] else null;
                const bare_ready_fault = if (rd) |ready|
                    if (desired_i) |di|
                        std.mem.indexOfScalar(u8, ready, '/') == null and
                            !std.mem.eql(u8, ready, row.columns[di])
                    else
                        false
                else
                    false;
                if (k9s_query.isFault(st, rd) or bare_ready_fault) {
                    self.table.filtered_indices.items[write] = idx;
                    write += 1;
                }
            }
            self.table.filtered_indices.shrinkRetainingCapacity(write);
            if (self.table.selected_row >= self.table.filtered_indices.items.len) {
                self.table.selected_row = if (self.table.filtered_indices.items.len == 0)
                    0
                else
                    @intCast(self.table.filtered_indices.items.len - 1);
            }
            if (self.table.selected_row < self.table.scroll_offset) {
                self.table.scroll_offset = self.table.selected_row;
            }
        }

        /// Bulk mark operations over the currently-filtered rows.
        /// `.all` marks every filtered row (idempotent); `.invert` toggles each;
        /// `.range` fills from the nearest already-marked filtered row to the
        /// cursor (k9s Ctrl-Space). Clearing is `table.clearMarks()` directly.
        /// toggleMark dupes the key, so reusing one stack buffer across rows is safe.
        const MarkOp = enum { all, invert, range };
        fn applyMarkOp(self: *Self, op: MarkOp) void {
            var key_buf: [512]u8 = undefined;
            const n = self.table.filtered_indices.items.len;
            if (n == 0) return;

            if (op == .range) {
                const sel = @min(self.table.selected_row, @as(u32, @intCast(n - 1)));
                var anchor: ?u32 = null;
                var best: u32 = std.math.maxInt(u32);
                for (self.table.filtered_indices.items, 0..) |idx, i| {
                    const item: *const RowData = &self.table.items.items[idx];
                    const key = rowKey(item, &key_buf);
                    if (!self.table.isMarked(key)) continue;
                    const ui: u32 = @intCast(i);
                    const dist = if (ui > sel) ui - sel else sel - ui;
                    if (dist < best) {
                        best = dist;
                        anchor = ui;
                    }
                }
                const a = anchor orelse sel;
                var i = @min(a, sel);
                const hi = @max(a, sel);
                while (i <= hi) : (i += 1) {
                    const idx = self.table.filtered_indices.items[i];
                    const item: *const RowData = &self.table.items.items[idx];
                    const key = rowKey(item, &key_buf);
                    if (!self.table.isMarked(key)) {
                        self.table.toggleMark(key) catch |err|
                            Logger.err("Failed to mark range in {s}: {}", .{ config.name, err });
                    }
                }
                return;
            }

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
                    .range => unreachable,
                }
            }
        }

        fn applySorting(self: *Self) void {
            if (self.usesDataPlane()) {
                if (self.projection_adapter != null) {
                    self.setProjectionViewAndSync(
                        self.table.filter_text,
                        self.table.sort_column orelse config.name_column,
                        self.table.sort_ascending,
                    ) catch return;
                    if (self.faults_only) self.retainFaultsOnly();
                }
                return;
            }
            if (self.table.sort_column) |col| {
                if (col < col_count) {
                    self.table.sortByColumn(&RowData.getColumnAt, col);
                }
            }
        }

        fn invalidateWidths(self: *Self) void {
            if (self.cached_col_widths) |*w| {
                w.deinit();
                self.cached_col_widths = null;
            }
        }

        fn rotateColumns(self: *Self, dir: i8) void {
            const n = self.visible_columns;
            if (n < 2) return;
            if (dir > 0) {
                const last = self.column_order[n - 1];
                var i = n;
                while (i > 1) : (i -= 1) {
                    self.column_order[i - 1] = self.column_order[i - 2];
                }
                self.column_order[0] = last;
            } else {
                const first = self.column_order[0];
                var i: u8 = 0;
                while (i + 1 < n) : (i += 1) {
                    self.column_order[i] = self.column_order[i + 1];
                }
                self.column_order[n - 1] = first;
            }
            self.invalidateWidths();
        }

        fn matchFn(item: *const RowData, filter: []const u8) bool {
            var cols: [col_count][]const u8 = undefined;
            var n: usize = 0;
            inline for (config.columns, 0..) |col_def, idx| {
                if (col_def.searchable) {
                    cols[n] = item.columns[idx];
                    n += 1;
                }
            }
            return k9s_query.matchSearchable(cols[0..n], item.labels, filter);
        }

        pub fn syncProjection(self: *Self) !void {
            const adapter = self.projection_adapter orelse return;
            self.syncProjectionSelection();

            var next_items: std.ArrayListUnmanaged(RowData) = .empty;
            errdefer {
                for (next_items.items) |*row| row.deinit();
                next_items.deinit(self.table.allocator);
            }
            var next_indices: std.ArrayListUnmanaged(usize) = .empty;
            errdefer next_indices.deinit(self.table.allocator);
            const visible_count = adapter.visibleCountFn(adapter.ptr);
            try next_items.ensureTotalCapacity(self.table.allocator, visible_count);
            try next_indices.ensureTotalCapacity(self.table.allocator, visible_count);

            var row_index: usize = 0;
            while (row_index < visible_count) : (row_index += 1) {
                const uid = adapter.visibleUidFn(adapter.ptr, row_index) orelse continue;
                const columns = try adapter.columnsFn(adapter.ptr, uid, self.table.allocator) orelse continue;
                var columns_owned = true;
                errdefer if (columns_owned) for (columns) |column| self.table.allocator.free(column);
                const row = RowData{
                    .columns = columns,
                    .allocator = self.table.allocator,
                    .uid = try self.table.allocator.dupe(u8, uid),
                };
                next_items.appendAssumeCapacity(row);
                columns_owned = false;
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
            self.table.loading_detail = "";

            if (adapter.selectedUidFn(adapter.ptr)) |selected_uid| {
                for (self.table.filtered_indices.items, 0..) |item_index, visible_index| {
                    if (std.mem.eql(u8, self.table.items.items[item_index].uid, selected_uid)) {
                        self.table.selected_row = @intCast(visible_index);
                        break;
                    }
                }
            }
            self.invalidateWidths();
        }

        pub fn syncPodProjection(self: *Self) !void {
            if (is_pods) try self.syncProjection();
        }

        fn syncProjectionSelection(self: *Self) void {
            const adapter = self.projection_adapter orelse return;
            const selected = self.table.getSelectedItem() orelse return;
            if (selected.uid.len > 0) _ = adapter.selectUidFn(adapter.ptr, selected.uid);
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
            const force_hidden = self.hiddenMask();

            const use_cache = self.cached_col_widths != null and
                self.cached_terminal_width == available_width and
                self.cached_show_all == self.table.show_all_namespaces and
                self.cached_show_wide == self.show_wide;

            const col_widths = if (use_cache) blk: {
                break :blk &self.cached_col_widths.?;
            } else blk: {
                // Build rows data for width calculation
                var rows_data = try std.ArrayList([]const []const u8).initCapacity(allocator, self.table.filtered_indices.items.len);
                defer rows_data.deinit(allocator);

                // Scanning 4k+ rows every redraw was freezing navigation after
                // all-namespaces toggle. Sample the first N filtered rows for
                // width — enough for representative column sizing.
                const width_sample_max = 256;
                const width_sample_len = @min(self.table.filtered_indices.items.len, width_sample_max);
                for (self.table.filtered_indices.items[0..width_sample_len]) |item_idx| {
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
                self.cached_show_wide = self.show_wide;
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
                // Iterate in views.yaml order (identity by default), not config order.
                for (self.column_order[0..self.visible_columns]) |ci| {
                    const cd = col_defs[ci];
                    const w = eff_widths[ci];
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
                for (self.column_order[0..self.visible_columns]) |ci| {
                    const cell = item.columns[ci];
                    const w = eff_widths[ci];
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

        // Node-specific keys, mirroring the is_pods branch below.
        const is_nodes = std.mem.eql(u8, config.name, "nodes");
        const is_secrets = std.mem.eql(u8, config.name, "secrets");
        const is_services = std.mem.eql(u8, config.name, "services");
        const is_deployments = std.mem.eql(u8, config.name, "deployments");
        const is_statefulsets = std.mem.eql(u8, config.name, "statefulsets");
        const is_daemonsets = std.mem.eql(u8, config.name, "daemonsets");
        const is_replicasets = std.mem.eql(u8, config.name, "replicasets");
        const is_cronjobs = std.mem.eql(u8, config.name, "cronjobs");
        const is_used_by_view = std.mem.eql(u8, config.name, "serviceaccounts") or
            std.mem.eql(u8, config.name, "secrets") or
            std.mem.eql(u8, config.name, "configmaps") or
            std.mem.eql(u8, config.name, "persistentvolumeclaims");
        const is_restart_view = is_deployments or is_statefulsets or is_daemonsets;
        const is_scale_view = is_deployments or is_statefulsets or is_replicasets;
        const is_rollback_view = is_restart_view or is_replicasets;

        /// pub so tests can drive the real key handler. It is already reachable
        /// through the vtable; a mutation that deleted the secrets `x` mapping survived
        /// the whole suite because every test here inspected configs instead.
        pub fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
            const self: *Self = @ptrCast(@alignCast(ptr));

            if (self.table.handleNavigationKey(key)) |result| {
                self.syncProjectionSelection();
                return result;
            }

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
                        // k9s: `u` toggles cordon. STATUS carries kubectl's
                        // `,SchedulingDisabled` when spec.unschedulable is set.
                        'u' => {
                            const item = self.table.getSelectedItem() orelse return .handled;
                            if (std.mem.indexOf(u8, item.columns[1], "SchedulingDisabled") != null)
                                return .request_uncordon;
                            return .request_cordon;
                        },
                        // k9s drain is `r`. `D` stays as a silent extra.
                        'r', 'D' => return .request_drain,
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
                        'f' => return .request_show_port_forwards,
                        else => {},
                    },
                    else => {},
                }
            }

            if (is_services) {
                switch (key) {
                    .char => |c| switch (c) {
                        'F' => return .request_port_forward,
                        'f' => return .request_show_port_forwards,
                        else => {},
                    },
                    else => {},
                }
            }

            if (is_cronjobs) {
                switch (key) {
                    .char => |c| switch (c) {
                        'p' => return .request_suspend,
                        't' => return .request_trigger,
                        else => {},
                    },
                    else => {},
                }
            }

            if (is_used_by_view) {
                switch (key) {
                    .char => |c| if (c == 'u') return .request_used_by,
                    else => {},
                }
            }

            switch (key) {
                .ctrl_r => {
                    self.refresh() catch |err| Logger.err("Failed to refresh {s}: {}", .{ config.name, err });
                    return .handled;
                },
                .ctrl_backslash => {
                    self.table.clearMarks();
                    return .handled;
                },
                .ctrl_space => {
                    self.applyMarkOp(.range);
                    return .handled;
                },
                .ctrl_w => {
                    self.show_wide = !self.show_wide;
                    self.invalidateWidths();
                    return .handled;
                },
                .ctrl_z => {
                    self.faults_only = !self.faults_only;
                    self.applyFilter(self.table.filter_text) catch |err|
                        Logger.err("Failed to apply faults filter on {s}: {}", .{ config.name, err });
                    return .handled;
                },
                .ctrl_l => if (is_rollback_view) return .request_rollback else return .not_handled,
                .shift_left => {
                    self.rotateColumns(-1);
                    return .handled;
                },
                .shift_right => {
                    self.rotateColumns(1);
                    return .handled;
                },
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

                    // Edit is a generic resource action (`kubectl edit`), not
                    // pod-specific. Kept out of the is_pods branch so Ingresses,
                    // ConfigMaps, Gateways, etc. get the same `e` as Pods.
                    if (c == 'e') {
                        return .request_edit;
                    }

                    // Refresh. k9s uses Ctrl-r. Lowercase `r` stays refresh only
                    // where it is not drain (nodes, handled above) or restart.
                    if (c == 'r') {
                        if (is_restart_view) return .request_restart;
                        self.refresh() catch |err| Logger.err("Failed to refresh {s}: {}", .{ config.name, err });
                        return .handled;
                    }

                    // Traffic view (deployments only)
                    if (c == 't' and is_deployments) {
                        return .request_traffic;
                    }

                    // Namespace toggle (only for namespaced resources)
                    if (config.is_namespaced and c == '0') {
                        self.table.show_all_namespaces = !self.table.show_all_namespaces;
                        self.table.gotoTop();
                        const hint = if (self.table.show_all_namespaces)
                            "Loading all namespaces (large clusters may take a minute)..."
                        else
                            "Loading namespace...";
                        self.scheduleRefresh(hint);
                        return .handled;
                    }

                    if (c == 'z' and is_deployments) return .request_view_replicasets;
                    if (c == 'R' and is_restart_view) return .request_restart;
                    if (c == 's' and is_scale_view) return .request_scale;

                    // Copy/warp/jump. Nodes `u` is cordon-toggle (handled above);
                    // `c` is copy there too, matching k9s.
                    if (c == 'c') return .request_copy;
                    if (c == 'n') return .request_copy_namespace;
                    if (c == 'w' and config.is_namespaced) return .request_warp;
                    if (c == 'J') return .request_jump_owner;

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
            if (self.usesDataPlane()) {
                if (!self.subscription_started and self.subscription_request == .none)
                    self.subscription_request = .start;
                return;
            }
            // Re-showing must be instant (Esc back from a sub-view / switching
            // back): show already-loaded rows, never block on kubectl. Only
            // auto-load when empty; Ctrl-r (and `r` where it is not drain/restart)
            // forces a refresh. See PodsView.
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

        fn vtableSetShowAllNamespaces(ptr: *anyopaque, all: bool) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.table.show_all_namespaces = all;
        }

        fn vtableShowsAllNamespaces(ptr: *anyopaque) bool {
            const self: *const Self = @ptrCast(@alignCast(ptr));
            return self.table.show_all_namespaces;
        }

        fn vtableFlushPendingRefresh(ptr: *anyopaque) bool {
            const self: *Self = @ptrCast(@alignCast(ptr));
            return self.flushPendingRefresh();
        }

        fn vtableGetStatusHint(ptr: *anyopaque) ?[]const u8 {
            const self: *const Self = @ptrCast(@alignCast(ptr));
            return self.getStatusHint();
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
            .setShowAllNamespaces = vtableSetShowAllNamespaces,
            .showsAllNamespaces = vtableShowsAllNamespaces,
            .flushPendingRefresh = vtableFlushPendingRefresh,
            .getStatusHint = vtableGetStatusHint,
        };
    };
}

fn podDataPlaneEnabled() bool {
    return active_pod_source == .data_plane;
}

fn podProjectionColumns(
    projection: *PodProjection,
    record: *const PodRecord,
    allocator: std.mem.Allocator,
) ![12][]const u8 {
    var columns: [12][]const u8 = undefined;
    var initialized: usize = 0;
    errdefer for (columns[0..initialized]) |column| allocator.free(column);
    columns[0] = try allocator.dupe(u8, record.key.namespace);
    initialized += 1;
    columns[1] = try allocator.dupe(u8, record.key.name);
    initialized += 1;
    columns[2] = try std.fmt.allocPrint(allocator, "{d}/{d}", .{
        record.ready_count,
        record.container_count,
    });
    initialized += 1;
    columns[3] = try allocator.dupe(
        u8,
        if (record.status_reason.len > 0)
            record.status_reason
        else if (record.phase.len > 0)
            record.phase
        else
            "Unknown",
    );
    initialized += 1;
    columns[4] = try std.fmt.allocPrint(allocator, "{d}", .{record.restart_count});
    initialized += 1;
    const metrics = projection.metricsFor(record.key.uid);
    if (metrics != null and metrics.?.revision > 0) {
        columns[5] = try formatPodCpu(allocator, metrics.?.cpu_milli);
        initialized += 1;
        columns[6] = try formatPodMemory(allocator, metrics.?.mem_bytes);
        initialized += 1;
    } else {
        columns[5] = try allocator.dupe(u8, "n/a");
        initialized += 1;
        columns[6] = try allocator.dupe(u8, "n/a");
        initialized += 1;
    }
    columns[7] = try allocator.dupe(u8, "n/a");
    initialized += 1;
    columns[8] = try allocator.dupe(u8, "n/a");
    initialized += 1;
    columns[9] = try allocator.dupe(u8, if (record.pod_ip.len > 0) record.pod_ip else "-");
    initialized += 1;
    columns[10] = try allocator.dupe(u8, if (record.node_name.len > 0) record.node_name else "-");
    initialized += 1;
    const age = try projection.ageCell(record.key.uid, record.creation_timestamp, 11);
    columns[11] = try allocator.dupe(u8, age);
    return columns;
}

fn formatPodCpu(allocator: std.mem.Allocator, milli: u64) ![]u8 {
    if (milli >= 1000 and milli % 1000 == 0)
        return std.fmt.allocPrint(allocator, "{d}", .{milli / 1000});
    return std.fmt.allocPrint(allocator, "{d}m", .{milli});
}

fn formatPodMemory(allocator: std.mem.Allocator, bytes: u64) ![]u8 {
    if (bytes >= 1024 * 1024 * 1024 and bytes % (1024 * 1024 * 1024) == 0)
        return std.fmt.allocPrint(allocator, "{d}Gi", .{bytes / (1024 * 1024 * 1024)});
    if (bytes >= 1024 * 1024)
        return std.fmt.allocPrint(allocator, "{d}Mi", .{bytes / (1024 * 1024)});
    if (bytes >= 1024)
        return std.fmt.allocPrint(allocator, "{d}Ki", .{bytes / 1024});
    return std.fmt.allocPrint(allocator, "{d}", .{bytes});
}

test "pod projection metrics format raw CPU and memory values" {
    const cpu = try formatPodCpu(std.testing.allocator, 125);
    defer std.testing.allocator.free(cpu);
    const memory = try formatPodMemory(std.testing.allocator, 4 * 1024);
    defer std.testing.allocator.free(memory);
    try std.testing.expectEqualStrings("125m", cpu);
    try std.testing.expectEqualStrings("4Ki", memory);
}
