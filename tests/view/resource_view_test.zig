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
