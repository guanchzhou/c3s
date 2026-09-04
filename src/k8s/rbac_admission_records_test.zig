const std = @import("std");
const klient = @import("klient");

const role = @import("RoleRecord.zig");
const role_binding = @import("RoleBindingRecord.zig");
const cluster_role = @import("ClusterRoleRecord.zig");
const cluster_role_binding = @import("ClusterRoleBindingRecord.zig");
const validating_policy = @import("ValidatingAdmissionPolicyRecord.zig");
const validating_binding = @import("ValidatingAdmissionPolicyBindingRecord.zig");
const mutating_policy = @import("MutatingAdmissionPolicyRecord.zig");
const mutating_binding = @import("MutatingAdmissionPolicyBindingRecord.zig");
const validating_webhook = @import("ValidatingWebhookConfigurationRecord.zig");
const mutating_webhook = @import("MutatingWebhookConfigurationRecord.zig");

fn verifyFixture(
    comptime T: type,
    comptime constructor: anytype,
    json: []const u8,
    expected_columns: []const []const u8,
) !void {
    var parsed = try std.json.parseFromSlice(T, std.testing.allocator, json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    var record = try constructor(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);

    const columns = try record.columns(std.testing.allocator);
    defer for (columns) |column| std.testing.allocator.free(column);
    try std.testing.expectEqual(expected_columns.len, columns.len);
    for (expected_columns, columns) |expected, actual| {
        try std.testing.expectEqualStrings(expected, actual);
    }

    var fail_index: usize = 0;
    while (true) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(
            std.testing.allocator,
            .{ .fail_index = fail_index },
        );
        if (record.clone(failing.allocator())) |copy_value| {
            var copy = copy_value;
            copy.deinit(failing.allocator());
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
        }
    }
}

fn verifyMissingUid(comptime T: type, comptime constructor: anytype, json: []const u8) !void {
    var parsed = try std.json.parseFromSlice(T, std.testing.allocator, json, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectError(error.MissingUid, constructor(std.testing.allocator, parsed.value));
}

test "12J RBAC records preserve exact legacy columns" {
    try verifyFixture(
        klient.Role,
        role.fromRole,
        \\{"metadata":{"uid":"r-1","namespace":"team","name":"reader"}}
    ,
        &.{ "team", "reader", "n/a" },
    );
    try verifyMissingUid(klient.Role, role.fromRole,
        \\{"metadata":{"namespace":"team","name":"reader"}}
    );

    try verifyFixture(
        klient.RoleBinding,
        role_binding.fromRoleBinding,
        \\{"metadata":{"uid":"rb-1","namespace":"team","name":"readers"},"roleRef":{"apiGroup":"rbac.authorization.k8s.io","kind":"Role","name":"reader"},"subjects":[]}
    ,
        &.{ "team", "readers", "Role/reader", "n/a" },
    );
    try verifyMissingUid(klient.RoleBinding, role_binding.fromRoleBinding,
        \\{"metadata":{"namespace":"team","name":"readers"},"roleRef":{"apiGroup":"rbac.authorization.k8s.io","kind":"Role","name":"reader"}}
    );

    try verifyFixture(
        klient.ClusterRole,
        cluster_role.fromClusterRole,
        \\{"metadata":{"uid":"cr-1","name":"cluster-reader"}}
    ,
        &.{ "cluster-reader", "n/a" },
    );
    try verifyMissingUid(klient.ClusterRole, cluster_role.fromClusterRole,
        \\{"metadata":{"name":"cluster-reader"}}
    );

    try verifyFixture(
        klient.ClusterRoleBinding,
        cluster_role_binding.fromClusterRoleBinding,
        \\{"metadata":{"uid":"crb-1","name":"cluster-readers"},"roleRef":{"apiGroup":"rbac.authorization.k8s.io","kind":"ClusterRole","name":"cluster-reader"},"subjects":[]}
    ,
        &.{ "cluster-readers", "ClusterRole/cluster-reader", "n/a" },
    );
    try verifyMissingUid(klient.ClusterRoleBinding, cluster_role_binding.fromClusterRoleBinding,
        \\{"metadata":{"name":"cluster-readers"},"roleRef":{"apiGroup":"rbac.authorization.k8s.io","kind":"ClusterRole","name":"cluster-reader"}}
    );
}

test "12K admission records preserve exact legacy columns" {
    try verifyFixture(
        klient.ValidatingAdmissionPolicy,
        validating_policy.fromValidatingAdmissionPolicy,
        \\{"metadata":{"uid":"vap-1","name":"validate-images"},"spec":{"failurePolicy":"Ignore","validations":[{},{}]}}
    ,
        &.{ "validate-images", "Ignore", "2", "n/a" },
    );
    try verifyMissingUid(klient.ValidatingAdmissionPolicy, validating_policy.fromValidatingAdmissionPolicy,
        \\{"metadata":{"name":"validate-images"}}
    );

    try verifyFixture(
        klient.ValidatingAdmissionPolicyBinding,
        validating_binding.fromValidatingAdmissionPolicyBinding,
        \\{"metadata":{"uid":"vapb-1","name":"validate-images-binding"},"spec":{"policyName":"validate-images"}}
    ,
        &.{ "validate-images-binding", "validate-images", "n/a" },
    );
    try verifyMissingUid(klient.ValidatingAdmissionPolicyBinding, validating_binding.fromValidatingAdmissionPolicyBinding,
        \\{"metadata":{"name":"validate-images-binding"}}
    );

    try verifyFixture(
        klient.MutatingAdmissionPolicy,
        mutating_policy.fromMutatingAdmissionPolicy,
        \\{"metadata":{"uid":"map-1","name":"default-labels"},"spec":{"failurePolicy":"Ignore","mutations":[{},{}]}}
    ,
        &.{ "default-labels", "Ignore", "2", "n/a" },
    );
    try verifyMissingUid(klient.MutatingAdmissionPolicy, mutating_policy.fromMutatingAdmissionPolicy,
        \\{"metadata":{"name":"default-labels"}}
    );

    try verifyFixture(
        klient.MutatingAdmissionPolicyBinding,
        mutating_binding.fromMutatingAdmissionPolicyBinding,
        \\{"metadata":{"uid":"mapb-1","name":"default-labels-binding"},"spec":{"policyName":"default-labels"}}
    ,
        &.{ "default-labels-binding", "default-labels", "n/a" },
    );
    try verifyMissingUid(klient.MutatingAdmissionPolicyBinding, mutating_binding.fromMutatingAdmissionPolicyBinding,
        \\{"metadata":{"name":"default-labels-binding"}}
    );

    try verifyFixture(
        klient.ValidatingWebhookConfiguration,
        validating_webhook.fromValidatingWebhookConfiguration,
        \\{"metadata":{"uid":"vwc-1","name":"validators"},"webhooks":[{},{}]}
    ,
        &.{ "validators", "2", "n/a" },
    );
    try verifyMissingUid(klient.ValidatingWebhookConfiguration, validating_webhook.fromValidatingWebhookConfiguration,
        \\{"metadata":{"name":"validators"}}
    );

    try verifyFixture(
        klient.MutatingWebhookConfiguration,
        mutating_webhook.fromMutatingWebhookConfiguration,
        \\{"metadata":{"uid":"mwc-1","name":"mutators"},"webhooks":[{},{}]}
    ,
        &.{ "mutators", "2", "n/a" },
    );
    try verifyMissingUid(klient.MutatingWebhookConfiguration, mutating_webhook.fromMutatingWebhookConfiguration,
        \\{"metadata":{"name":"mutators"}}
    );
}
