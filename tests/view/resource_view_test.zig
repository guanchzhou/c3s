// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Unit tests for the generic ResourceView comptime template.
// Tests RowData lifecycle, matchFn searchable filtering, sort key dispatch,
// cluster-scoped vs namespaced config, and getSelectedResourceInfo.

const std = @import("std");
const testing = std.testing;
const c3s = @import("c3s");
const resource_view = c3s.resource_view;
const table_layout = c3s.ui.table_layout;

// =========================================================================
// Mock types for testing ResourceView without a real klient or k8s_service.
// We only test the generated RowData and static config properties.
// =========================================================================

// ---------------------------------------------------------------------------
// RowData tests (via the generated type from a simple config)
// ---------------------------------------------------------------------------

// We cannot instantiate the full ResourceView without a K8sService, but we CAN
// test the RowData type and the matchFn/sort dispatch that are generated at
// comptime. We define a minimal config and extract the RowData type.

const test_namespaced_config = resource_view.Config{
    .name = "test-resources",
    .is_namespaced = true,
    .name_column = 1,
    .namespace_column = 0,
    .columns = &.{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = table_layout.ColumnPriority.MEDIUM, .searchable = true },
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = table_layout.ColumnPriority.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = table_layout.ColumnPriority.HIGH, .sort_key = 'S', .searchable = false },
    },
};

const test_cluster_config = resource_view.Config{
    .name = "test-cluster-resources",
    .is_namespaced = false,
    .name_column = 0,
    .namespace_column = null,
    .columns = &.{
        .{ .name = "NAME", .min_width = 12, .max_width = 40, .priority = table_layout.ColumnPriority.CRITICAL, .sort_key = 'N', .searchable = true },
        .{ .name = "AGE", .min_width = 6, .max_width = 12, .priority = table_layout.ColumnPriority.MEDIUM, .sort_key = 'A' },
    },
};

// =========================================================================
// Config property tests
// =========================================================================

test "ResourceView config: namespaced resource has namespace column" {
    try testing.expect(test_namespaced_config.is_namespaced);
    try testing.expectEqual(@as(?u8, 0), test_namespaced_config.namespace_column);
    try testing.expectEqual(@as(u8, 1), test_namespaced_config.name_column);
    try testing.expectEqualStrings("test-resources", test_namespaced_config.name);
}

test "ResourceView config: cluster-scoped resource has no namespace column" {
    try testing.expect(!test_cluster_config.is_namespaced);
    try testing.expectEqual(@as(?u8, null), test_cluster_config.namespace_column);
    try testing.expectEqual(@as(u8, 0), test_cluster_config.name_column);
    try testing.expectEqualStrings("test-cluster-resources", test_cluster_config.name);
}

test "ResourceView config: column count matches" {
    try testing.expectEqual(@as(usize, 3), test_namespaced_config.columns.len);
    try testing.expectEqual(@as(usize, 2), test_cluster_config.columns.len);
}

// =========================================================================
// ColumnDef default values
// =========================================================================

test "ColumnDef defaults" {
    const col = resource_view.ColumnDef{
        .name = "TEST",
    };
    try testing.expectEqual(@as(u16, 10), col.min_width);
    try testing.expectEqual(@as(?u16, null), col.max_width);
    try testing.expectEqual(table_layout.ColumnPriority.MEDIUM, col.priority);
    try testing.expectEqual(@as(?u8, null), col.sort_key);
    try testing.expect(!col.searchable);
}

test "ColumnDef with all fields set" {
    const col = resource_view.ColumnDef{
        .name = "NAME",
        .min_width = 12,
        .max_width = 40,
        .priority = table_layout.ColumnPriority.CRITICAL,
        .sort_key = 'N',
        .searchable = true,
    };
    try testing.expectEqual(@as(u16, 12), col.min_width);
    try testing.expectEqual(@as(?u16, 40), col.max_width);
    try testing.expectEqual(table_layout.ColumnPriority.CRITICAL, col.priority);
    try testing.expectEqual(@as(?u8, 'N'), col.sort_key);
    try testing.expect(col.searchable);
}

// =========================================================================
// Config defaults
// =========================================================================

test "Config default_all_namespaces defaults to false" {
    const cfg = resource_view.Config{
        .name = "test",
        .columns = &.{
            .{ .name = "NAME" },
        },
        .is_namespaced = true,
        .name_column = 0,
    };
    try testing.expect(!cfg.default_all_namespaces);
}

test "Config default_all_namespaces can be set to true" {
    const cfg = resource_view.Config{
        .name = "test",
        .columns = &.{
            .{ .name = "NAME" },
        },
        .is_namespaced = true,
        .name_column = 0,
        .default_all_namespaces = true,
    };
    try testing.expect(cfg.default_all_namespaces);
}

// =========================================================================
// Verify searchable column marking
// =========================================================================

test "searchable columns are correctly marked in config" {
    const cols = test_namespaced_config.columns;
    // NAMESPACE - searchable
    try testing.expect(cols[0].searchable);
    // NAME - searchable
    try testing.expect(cols[1].searchable);
    // STATUS - NOT searchable
    try testing.expect(!cols[2].searchable);
}

// =========================================================================
// Sort key assignment
// =========================================================================

test "sort_key is assigned to correct columns" {
    const cols = test_namespaced_config.columns;
    // NAMESPACE has no sort key
    try testing.expectEqual(@as(?u8, null), cols[0].sort_key);
    // NAME has sort key 'N'
    try testing.expectEqual(@as(?u8, 'N'), cols[1].sort_key);
    // STATUS has sort key 'S'
    try testing.expectEqual(@as(?u8, 'S'), cols[2].sort_key);
}

// =========================================================================
// resource_configs: verify all 25 configs have valid properties
// =========================================================================

test "resource_configs: DeploymentsView config is valid" {
    // Access the type to trigger comptime instantiation
    const T = c3s.DeploymentsView;
    _ = T;
    // If this compiles, the ResourceView was successfully instantiated
}

test "resource_configs: ServicesView config is valid" {
    const T = c3s.ServicesView;
    _ = T;
}

test "resource_configs: ConfigMapsView config is valid" {
    const T = c3s.ConfigMapsView;
    _ = T;
}

test "resource_configs: SecretsView config is valid" {
    const T = c3s.SecretsView;
    _ = T;
}

test "resource_configs: StatefulSetsView config is valid" {
    const T = c3s.StatefulSetsView;
    _ = T;
}

test "resource_configs: DaemonSetsView config is valid" {
    const T = c3s.DaemonSetsView;
    _ = T;
}

test "resource_configs: ReplicaSetsView config is valid" {
    const T = c3s.ReplicaSetsView;
    _ = T;
}

test "resource_configs: JobsView config is valid" {
    const T = c3s.JobsView;
    _ = T;
}

test "resource_configs: CronJobsView config is valid" {
    const T = c3s.CronJobsView;
    _ = T;
}

test "resource_configs: IngressesView config is valid" {
    const T = c3s.IngressesView;
    _ = T;
}

test "resource_configs: NetworkPoliciesView config is valid" {
    const T = c3s.NetworkPoliciesView;
    _ = T;
}

test "resource_configs: ServiceAccountsView config is valid" {
    const T = c3s.ServiceAccountsView;
    _ = T;
}

test "resource_configs: RolesView config is valid" {
    const T = c3s.RolesView;
    _ = T;
}

test "resource_configs: RoleBindingsView config is valid" {
    const T = c3s.RoleBindingsView;
    _ = T;
}

test "resource_configs: ClusterRolesView config is valid" {
    const T = c3s.ClusterRolesView;
    _ = T;
}

test "resource_configs: ClusterRoleBindingsView config is valid" {
    const T = c3s.ClusterRoleBindingsView;
    _ = T;
}

test "resource_configs: EventsView config is valid" {
    const T = c3s.EventsView;
    _ = T;
}

test "resource_configs: NodesView config is valid" {
    const T = c3s.NodesView;
    _ = T;
}

test "resource_configs: ResourceQuotasView config is valid" {
    const T = c3s.ResourceQuotasView;
    _ = T;
}

test "resource_configs: LimitRangesView config is valid" {
    const T = c3s.LimitRangesView;
    _ = T;
}

test "resource_configs: PodDisruptionBudgetsView config is valid" {
    const T = c3s.PodDisruptionBudgetsView;
    _ = T;
}

test "resource_configs: HPAView config is valid" {
    const T = c3s.HPAView;
    _ = T;
}

test "resource_configs: PersistentVolumesView config is valid" {
    const T = c3s.PersistentVolumesView;
    _ = T;
}

test "resource_configs: PersistentVolumeClaimsView config is valid" {
    const T = c3s.PersistentVolumeClaimsView;
    _ = T;
}

test "resource_configs: EndpointsView config is valid" {
    const T = c3s.EndpointsView;
    _ = T;
}

test "resource_configs: StorageClassesView config is valid" {
    const T = c3s.StorageClassesView;
    _ = T;
}

// ---------------------------------------------------------------------------
// Per-view action keys
//
// These press the key and assert the KeyResult, rather than asserting a config
// property. That distinction matters: a mutation that deleted the `x` -> decode
// mapping in resource_view.zig survived the whole suite, because every existing test
// here inspects configs and none drives handleKey.
// ---------------------------------------------------------------------------

test "x on the secrets view requests a decode" {
    const allocator = testing.allocator;

    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    var view = try c3s.SecretsView.init(allocator, &theme, &svc);
    defer view.deinit();

    const result = try c3s.SecretsView.handleKey(&view, .{ .char = 'x' });
    try testing.expectEqual(c3s.View.KeyResult.request_decode, result);
}

test "x on a non-secrets view is not a decode" {
    // The branch is comptime-gated on config.name, so this proves the gate works
    // rather than 'x' being globally bound.
    const allocator = testing.allocator;

    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    var view = try c3s.ConfigMapsView.init(allocator, &theme, &svc);
    defer view.deinit();

    const result = try c3s.ConfigMapsView.handleKey(&view, .{ .char = 'x' });
    try testing.expect(result != c3s.View.KeyResult.request_decode);
}

test "u on the nodes view toggles cordon; c copies the name" {
    const allocator = testing.allocator;
    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    var view = try c3s.NodesView.init(allocator, &theme, &svc);
    defer view.deinit();

    const t = &view.table;
    try t.appendItem(.{ .columns = .{
        try allocator.dupe(u8, "ready-node"), try allocator.dupe(u8, "Ready"),
        try allocator.dupe(u8, "worker"),     try allocator.dupe(u8, "v1.33.0"),
        try allocator.dupe(u8, "10.0.0.1"),   try allocator.dupe(u8, "1d"),
    }, .allocator = allocator });
    try t.appendItem(.{ .columns = .{
        try allocator.dupe(u8, "cordoned"), try allocator.dupe(u8, "Ready,SchedulingDisabled"),
        try allocator.dupe(u8, "worker"),   try allocator.dupe(u8, "v1.33.0"),
        try allocator.dupe(u8, "10.0.0.2"), try allocator.dupe(u8, "1d"),
    }, .allocator = allocator });
    try t.filtered_indices.append(allocator, 0);
    try t.filtered_indices.append(allocator, 1);
    t.selected_row = 0;

    try testing.expectEqual(
        c3s.View.KeyResult.request_cordon,
        try c3s.NodesView.handleKey(&view, .{ .char = 'u' }),
    );
    try testing.expectEqual(
        c3s.View.KeyResult.request_copy,
        try c3s.NodesView.handleKey(&view, .{ .char = 'c' }),
    );

    t.selected_row = 1;
    try testing.expectEqual(
        c3s.View.KeyResult.request_uncordon,
        try c3s.NodesView.handleKey(&view, .{ .char = 'u' }),
    );
}

test "every advertised sort key maps to a column that can actually sort" {
    // ~14 advertised sort keys pointed at columns with no `sort_key`, so pressing them
    // did nothing. Rather than delete the hints, the columns gained the keys -- which
    // only helps if something checks the two sides still agree.
    //
    // This asserts the CONFIG side: each key a view advertises for sorting exists as a
    // sort_key on one of that view's columns. The key-press side is covered below.
    const Case = struct { name: []const u8, keys: []const u8 };
    const cases = [_]Case{
        // pods advertises Shift- A C I M N O P R S T
        .{ .name = "pods", .keys = "ACIMNOPRST" },
        .{ .name = "nodes", .keys = "ANRS" },
        .{ .name = "services", .keys = "ANT" },
        .{ .name = "jobs", .keys = "ACN" },
        .{ .name = "persistentvolumeclaims", .keys = "ACNS" },
    };

    inline for (cases) |case| {
        const cfg = @field(c3s, blk: {
            // "pods" -> "PodsView" style lookup is not derivable, so map explicitly.
            break :blk if (std.mem.eql(u8, case.name, "pods"))
                "PodsView"
            else if (std.mem.eql(u8, case.name, "nodes"))
                "NodesView"
            else if (std.mem.eql(u8, case.name, "services"))
                "ServicesView"
            else if (std.mem.eql(u8, case.name, "jobs"))
                "JobsView"
            else
                "PersistentVolumeClaimsView";
        }).view_config;

        for (case.keys) |want| {
            var found = false;
            for (cfg.columns) |col| {
                if (col.sort_key) |sk| {
                    if (sk == want) found = true;
                }
            }
            if (!found) {
                std.debug.print("{s} advertises sort key '{c}' with no column for it\n", .{ case.name, want });
                return error.AdvertisedSortKeyHasNoColumn;
            }
        }
    }
}

test "pressing an advertised sort key actually sorts" {
    // The key-press half. Before this, a sort key could be present in the config and
    // still unreachable -- App's global switch used to eat view keys.
    const allocator = testing.allocator;

    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    var view = try c3s.ServicesView.init(allocator, &theme, &svc);
    defer view.deinit();

    // TYPE gained sort_key 'T' in this commit; Shift-t was advertised and did nothing.
    try testing.expectEqual(@as(?u8, null), view.table.sort_column);
    const result = try c3s.ServicesView.handleKey(&view, .{ .char = 'T' });
    try testing.expectEqual(c3s.View.KeyResult.handled, result);
    try testing.expect(view.table.sort_column != null);
}

// ---------------------------------------------------------------------------
// views.yaml column selection and ordering
//
// Driving applyViewsConfig through the process-wide cache would need a temp XDG tree,
// so these seed the parsed config directly and then assert on the view's resulting
// column_order / visible_columns -- which is exactly what render iterates.
// ---------------------------------------------------------------------------

fn makePodsView(allocator: std.mem.Allocator, svc: *c3s.K8sService, theme: *const c3s.theme_loader.ThemeColors) !c3s.PodsView {
    return try c3s.PodsView.init(allocator, theme, svc);
}

test "with no views.yaml every column shows in config order" {
    const allocator = testing.allocator;
    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    var view = try makePodsView(allocator, &svc, &theme);
    defer view.deinit();

    const n = c3s.PodsView.view_config.columns.len;
    try testing.expectEqual(@as(u8, @intCast(n)), view.visible_columns);
    for (0..n) |i| try testing.expectEqual(@as(u8, @intCast(i)), view.column_order[i]);
}

test "views_config selects a subset and preserves the requested order" {
    // The parser and the view agree on matching by uppercase name, so this asserts the
    // join between them rather than either half.
    const allocator = testing.allocator;
    var cfg = try c3s.views_config.parse(allocator,
        \\views:
        \\  pods:
        \\    columns: [AGE, NAME, STATUS]
    );
    defer cfg.deinit();

    const wanted = cfg.forView("pods").?;
    const cols = c3s.PodsView.view_config.columns;

    // Resolve the same way applyViewsConfig does, and check we land on real indices in
    // the requested order.
    var resolved: [3]usize = undefined;
    for (wanted, 0..) |want, wi| {
        var found: ?usize = null;
        for (cols, 0..) |cd, ci| {
            if (std.ascii.eqlIgnoreCase(cd.name, want)) found = ci;
        }
        resolved[wi] = found orelse return error.ColumnNotFound;
    }
    try testing.expectEqualStrings("AGE", cols[resolved[0]].name);
    try testing.expectEqualStrings("NAME", cols[resolved[1]].name);
    try testing.expectEqualStrings("STATUS", cols[resolved[2]].name);
    // And the order really differs from config order, so the test would catch a
    // no-op implementation.
    try testing.expect(resolved[0] > resolved[1]);
}

test "an unknown column name in views.yaml is skipped, not fatal" {
    const allocator = testing.allocator;
    var cfg = try c3s.views_config.parse(allocator,
        \\views:
        \\  pods:
        \\    columns: [NAME, TOTALLY_MADE_UP, AGE]
    );
    defer cfg.deinit();

    const wanted = cfg.forView("pods").?;
    try testing.expectEqual(@as(usize, 3), wanted.len);

    var matched: usize = 0;
    for (wanted) |want| {
        for (c3s.PodsView.view_config.columns) |cd| {
            if (std.ascii.eqlIgnoreCase(cd.name, want)) matched += 1;
        }
    }
    // Two of the three resolve; the made-up one simply does not, and the view logs it.
    try testing.expectEqual(@as(usize, 2), matched);
}

test "applyViewsConfig itself selects, reorders, and keeps the name column" {
    // Drives the REAL consumer, not a reimplementation of its matching rules. The two
    // tests above resolve column names themselves, which would pass even if
    // applyViewsConfig did nothing -- the mistake this whole series keeps re-learning.
    const allocator = testing.allocator;
    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    const cols = c3s.PodsView.view_config.columns;
    const name_col = c3s.PodsView.view_config.name_column;

    // Case 1: subset, deliberately out of config order and lowercase.
    {
        c3s.views_config.setForTests(try c3s.views_config.parse(std.heap.page_allocator,
            \\views:
            \\  pods:
            \\    columns: [age, name, status]
        ));
        defer c3s.views_config.resetForTests();

        var view = try c3s.PodsView.init(allocator, &theme, &svc);
        defer view.deinit();

        try testing.expectEqual(@as(u8, 3), view.visible_columns);
        try testing.expectEqualStrings("AGE", cols[view.column_order[0]].name);
        try testing.expectEqualStrings("NAME", cols[view.column_order[1]].name);
        try testing.expectEqualStrings("STATUS", cols[view.column_order[2]].name);
    }

    // Case 2: omitting the name column must not produce unlabelled rows -- it is the
    // identity used by describe, delete and marks, so it is appended back.
    {
        c3s.views_config.setForTests(try c3s.views_config.parse(std.heap.page_allocator,
            \\views:
            \\  pods:
            \\    columns: [STATUS, AGE]
        ));
        defer c3s.views_config.resetForTests();

        var view = try c3s.PodsView.init(allocator, &theme, &svc);
        defer view.deinit();

        try testing.expectEqual(@as(u8, 3), view.visible_columns);
        var has_name = false;
        for (view.column_order[0..view.visible_columns]) |ci| {
            if (ci == name_col) has_name = true;
        }
        try testing.expect(has_name);
    }

    // Case 3: a config naming nothing real falls back to all columns rather than
    // rendering an empty table.
    {
        c3s.views_config.setForTests(try c3s.views_config.parse(std.heap.page_allocator,
            \\views:
            \\  pods:
            \\    columns: [NOPE, ALSO_NOPE]
        ));
        defer c3s.views_config.resetForTests();

        var view = try c3s.PodsView.init(allocator, &theme, &svc);
        defer view.deinit();
        try testing.expectEqual(@as(u8, @intCast(cols.len)), view.visible_columns);
    }

    // Case 4: a config for a DIFFERENT view leaves this one at its defaults.
    {
        c3s.views_config.setForTests(try c3s.views_config.parse(std.heap.page_allocator,
            \\views:
            \\  services:
            \\    columns: [NAME]
        ));
        defer c3s.views_config.resetForTests();

        var view = try c3s.PodsView.init(allocator, &theme, &svc);
        defer view.deinit();
        try testing.expectEqual(@as(u8, @intCast(cols.len)), view.visible_columns);
    }
}

test "hiddenMask hides the namespace column in single-namespace scope" {
    // The NAMESPACE rule predates views.yaml; asserting it here pins the behaviour the
    // views.yaml mask is now sharing a code path with.
    const allocator = testing.allocator;
    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    var view = try c3s.PodsView.init(allocator, &theme, &svc);
    defer view.deinit();

    const ns_col = c3s.PodsView.view_config.namespace_column.?;

    view.table.show_all_namespaces = false;
    try testing.expect(view.hiddenMask()[ns_col]);

    view.table.show_all_namespaces = true;
    try testing.expect(!view.hiddenMask()[ns_col]);
}

test "0 toggling all-namespaces schedules deferred refresh with loading hint" {
    const allocator = testing.allocator;
    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    var view = try c3s.PodsView.init(allocator, &theme, &svc);
    defer view.deinit();

    try testing.expect(!view.refresh_pending);
    try testing.expect(!view.table.show_all_namespaces);

    const result = try c3s.PodsView.handleKey(&view, .{ .char = '0' });
    try testing.expectEqual(c3s.View.KeyResult.handled, result);
    try testing.expect(view.refresh_pending);
    try testing.expect(view.table.loading);
    try testing.expect(view.table.show_all_namespaces);
    try testing.expect(view.table.loading_detail.len > 0);
    try testing.expect(view.getStatusHint() != null);

    _ = view.flushPendingRefresh();
    try testing.expect(!view.refresh_pending);
}

test "hiddenMask hides every column views.yaml left out" {
    // Force-hiding is what hands the unused width to the columns that ARE shown. A
    // mutation removing it survived until this test existed, because nothing else
    // inspects the mask.
    const allocator = testing.allocator;
    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    c3s.views_config.setForTests(try c3s.views_config.parse(std.heap.page_allocator,
        \\views:
        \\  pods:
        \\    columns: [NAME, STATUS]
    ));
    defer c3s.views_config.resetForTests();

    var view = try c3s.PodsView.init(allocator, &theme, &svc);
    defer view.deinit();
    view.table.show_all_namespaces = true; // isolate from the NAMESPACE rule

    const cols = c3s.PodsView.view_config.columns;
    const mask = view.hiddenMask();

    var shown: usize = 0;
    for (cols, 0..) |cd, ci| {
        const is_kept = std.mem.eql(u8, cd.name, "NAME") or std.mem.eql(u8, cd.name, "STATUS");
        if (is_kept) {
            try testing.expect(!mask[ci]);
            shown += 1;
        } else {
            try testing.expect(mask[ci]);
        }
    }
    try testing.expectEqual(@as(usize, 2), shown);
}

test "calculateColumnWidthsHidden gives a masked column zero width and reassigns its budget" {
    // This function had no test at all despite backing every view's NAMESPACE hiding,
    // which is why a mutation disabling the views.yaml mask initially survived.
    const allocator = testing.allocator;
    const P = table_layout.ColumnPriority;

    const headers = [_][]const u8{ "NAMESPACE", "NAME", "STATUS" };
    const row = [_][]const u8{ "kube-system", "some-pod-name", "Running" };
    const rows = [_][]const []const u8{&row};
    const columns = [_]table_layout.ColumnInfo{
        .{ .name = "NAMESPACE", .min_width = 10, .max_width = 20, .priority = P.MEDIUM },
        .{ .name = "NAME", .min_width = 12, .max_width = null, .priority = P.CRITICAL },
        .{ .name = "STATUS", .min_width = 8, .max_width = 12, .priority = P.HIGH },
    };

    var unmasked = try table_layout.calculateColumnWidthsHidden(
        allocator,
        &headers,
        &rows,
        &columns,
        80,
        null,
    );
    defer unmasked.deinit();

    const mask = [_]bool{ true, false, false };
    var masked = try table_layout.calculateColumnWidthsHidden(
        allocator,
        &headers,
        &rows,
        &columns,
        80,
        &mask,
    );
    defer masked.deinit();

    // The masked column disappears entirely...
    try testing.expectEqual(@as(u16, 0), masked.widths[0]);
    try testing.expect(unmasked.widths[0] > 0);
    // ...and its space is not simply lost: NAME (the CRITICAL column) grows.
    try testing.expect(masked.widths[1] > unmasked.widths[1]);
}

test "r on the nodes view requests a drain, and only on nodes" {
    const allocator = testing.allocator;
    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    var nodes = try c3s.NodesView.init(allocator, &theme, &svc);
    defer nodes.deinit();
    try testing.expectEqual(
        c3s.View.KeyResult.request_drain,
        try c3s.NodesView.handleKey(&nodes, .{ .char = 'r' }),
    );
    try testing.expectEqual(
        c3s.View.KeyResult.request_drain,
        try c3s.NodesView.handleKey(&nodes, .{ .char = 'D' }),
    );
    try testing.expectEqual(
        c3s.View.KeyResult.handled,
        try c3s.NodesView.handleKey(&nodes, .ctrl_r),
    );

    var pods = try c3s.PodsView.init(allocator, &theme, &svc);
    defer pods.deinit();
    try testing.expect(try c3s.PodsView.handleKey(&pods, .{ .char = 'r' }) != c3s.View.KeyResult.request_drain);
    try testing.expect(try c3s.PodsView.handleKey(&pods, .{ .char = 'D' }) != c3s.View.KeyResult.request_drain);
    try testing.expectEqual(
        c3s.View.KeyResult.request_show_port_forwards,
        try c3s.PodsView.handleKey(&pods, .{ .char = 'f' }),
    );
}

test "r on deployments requests a restart; ctrl-r refreshes" {
    const allocator = testing.allocator;
    var svc = try c3s.K8sService.init(allocator);
    defer svc.deinit();
    var theme = try c3s.theme_loader.defaultTheme(allocator);
    defer c3s.theme_loader.deinitTheme(&theme);

    var dp = try c3s.DeploymentsView.init(allocator, &theme, &svc);
    defer dp.deinit();
    try testing.expectEqual(
        c3s.View.KeyResult.request_restart,
        try c3s.DeploymentsView.handleKey(&dp, .{ .char = 'r' }),
    );
    try testing.expectEqual(
        c3s.View.KeyResult.handled,
        try c3s.DeploymentsView.handleKey(&dp, .ctrl_r),
    );
}
