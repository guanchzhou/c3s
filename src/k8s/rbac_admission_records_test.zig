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

pub const validating_policy_object_json =
    \\{"apiVersion":"admissionregistration.k8s.io/v1","kind":"ValidatingAdmissionPolicy","metadata":{"uid":"vap-1","name":"validate-images"},"spec":{"failurePolicy":"Ignore","validations":[{"expression":"object.spec.image != ''"},{"expression":"object.metadata.name != ''"}]}}
;
pub const validating_binding_object_json =
    \\{"apiVersion":"admissionregistration.k8s.io/v1","kind":"ValidatingAdmissionPolicyBinding","metadata":{"uid":"vapb-1","name":"validate-images-binding"},"spec":{"policyName":"validate-images","validationActions":["Deny"]}}
;
pub const mutating_policy_object_json =
    \\{"apiVersion":"admissionregistration.k8s.io/v1","kind":"MutatingAdmissionPolicy","metadata":{"uid":"map-1","name":"default-labels"},"spec":{"failurePolicy":"Ignore","mutations":[{"patchType":"ApplyConfiguration"},{"patchType":"JSONPatch"}]}}
;
pub const mutating_binding_object_json =
    \\{"apiVersion":"admissionregistration.k8s.io/v1","kind":"MutatingAdmissionPolicyBinding","metadata":{"uid":"mapb-1","name":"default-labels-binding"},"spec":{"policyName":"default-labels"}}
;
pub const validating_webhook_object_json =
    \\{"apiVersion":"admissionregistration.k8s.io/v1","kind":"ValidatingWebhookConfiguration","metadata":{"uid":"vwc-1","name":"validators"},"webhooks":[{"name":"one.example.com"},{"name":"two.example.com"}]}
;
pub const mutating_webhook_object_json =
    \\{"apiVersion":"admissionregistration.k8s.io/v1","kind":"MutatingWebhookConfiguration","metadata":{"uid":"mwc-1","name":"mutators"},"webhooks":[{"name":"one.example.com"},{"name":"two.example.com"}]}
;

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

fn freeColumns(columns: anytype) void {
    for (columns) |column| std.testing.allocator.free(column);
}

fn exerciseRealShapedAdmissionDecode(
    comptime T: type,
    comptime constructor: anytype,
    comptime object_json: []const u8,
    comptime path: []const u8,
    comptime expected: []const []const u8,
    comptime verify: fn (*const T) anyerror!void,
) !void {
    const stream_list = @import("StreamList.zig");
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const ResponseScript = @import("FakeTransport.zig").ResponseScript;
    const read_transport = @import("ReadTransport.zig");
    const Capture = struct {
        expected: []const []const u8,

        fn receive(self: *@This(), items: []const T) !void {
            try std.testing.expectEqual(@as(usize, 1), items.len);
            try verify(&items[0]);
            var record = try constructor(std.testing.allocator, items[0]);
            defer record.deinit(std.testing.allocator);
            const columns = try record.columns(std.testing.allocator);
            defer freeColumns(columns);
            for (columns, self.expected) |actual, wanted|
                try std.testing.expectEqualStrings(wanted, actual);
        }
    };
    const Clock = struct {
        fn now(_: *anyopaque) u64 {
            return 0;
        }
    };
    const list_json = "{\"metadata\":{\"resourceVersion\":\"17\"},\"items\":[" ++ object_json ++ "]}";
    const scripts = [_]ResponseScript{.{ .body = list_json }};
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    var capture = Capture{ .expected = expected };
    var clock_context: u8 = 0;
    var result = try stream_list.stream(
        T,
        std.testing.allocator,
        fake.transport(),
        try read_transport.ReadRequest.init(path),
        .{ .clock = .{ .ptr = &clock_context, .now_ns_fn = Clock.now } },
        &capture,
        Capture.receive,
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("17", result.resource_version);

    const watch_json = "{\"type\":\"MODIFIED\",\"object\":" ++ object_json ++ "}";
    var parsed_watch = try std.json.parseFromSlice(
        klient.Watcher(T).WatchEnvelope,
        std.testing.allocator,
        watch_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed_watch.deinit();
    const object = &parsed_watch.value.object.?;
    try verify(object);
    var record = try constructor(std.testing.allocator, object.*);
    defer record.deinit(std.testing.allocator);
    const columns = try record.columns(std.testing.allocator);
    defer freeColumns(columns);
    for (columns, expected) |actual, wanted|
        try std.testing.expectEqualStrings(wanted, actual);
}

fn expectValidatingPolicy(object: *const klient.ValidatingAdmissionPolicy) !void {
    const spec = object.spec orelse return error.MissingSpec;
    try std.testing.expectEqualStrings("Ignore", spec.failurePolicy orelse return error.MissingFailurePolicy);
    try std.testing.expectEqual(@as(usize, 2), (spec.validations orelse return error.MissingValidations).len);
}

fn expectValidatingBinding(object: *const klient.ValidatingAdmissionPolicyBinding) !void {
    const spec = object.spec orelse return error.MissingSpec;
    try std.testing.expectEqualStrings("validate-images", spec.policyName);
}

fn expectMutatingPolicy(object: *const klient.MutatingAdmissionPolicy) !void {
    const spec = object.spec orelse return error.MissingSpec;
    try std.testing.expectEqualStrings("Ignore", spec.failurePolicy orelse return error.MissingFailurePolicy);
    try std.testing.expectEqual(@as(usize, 2), (spec.mutations orelse return error.MissingMutations).len);
}

fn expectMutatingBinding(object: *const klient.MutatingAdmissionPolicyBinding) !void {
    const spec = object.spec orelse return error.MissingSpec;
    try std.testing.expectEqualStrings("default-labels", spec.policyName);
}

fn expectValidatingWebhooks(object: *const klient.ValidatingWebhookConfiguration) !void {
    try std.testing.expectEqual(@as(usize, 2), (object.webhooks orelse return error.MissingTopLevelWebhooks).len);
}

fn expectMutatingWebhooks(object: *const klient.MutatingWebhookConfiguration) !void {
    try std.testing.expectEqual(@as(usize, 2), (object.webhooks orelse return error.MissingTopLevelWebhooks).len);
}

test "real-shaped ValidatingAdmissionPolicy LIST and WATCH decode spec fields" {
    try exerciseRealShapedAdmissionDecode(klient.ValidatingAdmissionPolicy, validating_policy.fromValidatingAdmissionPolicy, validating_policy_object_json, "/apis/admissionregistration.k8s.io/v1/validatingadmissionpolicies", &.{ "validate-images", "Ignore", "2", "n/a" }, expectValidatingPolicy);
}

test "real-shaped ValidatingAdmissionPolicyBinding LIST and WATCH decode spec policyName" {
    try exerciseRealShapedAdmissionDecode(klient.ValidatingAdmissionPolicyBinding, validating_binding.fromValidatingAdmissionPolicyBinding, validating_binding_object_json, "/apis/admissionregistration.k8s.io/v1/validatingadmissionpolicybindings", &.{ "validate-images-binding", "validate-images", "n/a" }, expectValidatingBinding);
}

test "real-shaped MutatingAdmissionPolicy LIST and WATCH decode spec mutations" {
    try exerciseRealShapedAdmissionDecode(klient.MutatingAdmissionPolicy, mutating_policy.fromMutatingAdmissionPolicy, mutating_policy_object_json, "/apis/admissionregistration.k8s.io/v1/mutatingadmissionpolicies", &.{ "default-labels", "Ignore", "2", "n/a" }, expectMutatingPolicy);
}

test "real-shaped MutatingAdmissionPolicyBinding LIST and WATCH decode spec policyName" {
    try exerciseRealShapedAdmissionDecode(klient.MutatingAdmissionPolicyBinding, mutating_binding.fromMutatingAdmissionPolicyBinding, mutating_binding_object_json, "/apis/admissionregistration.k8s.io/v1/mutatingadmissionpolicybindings", &.{ "default-labels-binding", "default-labels", "n/a" }, expectMutatingBinding);
}

test "real-shaped ValidatingWebhookConfiguration LIST and WATCH decode flat webhooks" {
    try exerciseRealShapedAdmissionDecode(klient.ValidatingWebhookConfiguration, validating_webhook.fromValidatingWebhookConfiguration, validating_webhook_object_json, "/apis/admissionregistration.k8s.io/v1/validatingwebhookconfigurations", &.{ "validators", "2", "n/a" }, expectValidatingWebhooks);
}

test "real-shaped MutatingWebhookConfiguration LIST and WATCH decode flat webhooks" {
    try exerciseRealShapedAdmissionDecode(klient.MutatingWebhookConfiguration, mutating_webhook.fromMutatingWebhookConfiguration, mutating_webhook_object_json, "/apis/admissionregistration.k8s.io/v1/mutatingwebhookconfigurations", &.{ "mutators", "2", "n/a" }, expectMutatingWebhooks);
}

test "admission decoding preserves missing optional defaults" {
    var policy = try std.json.parseFromSlice(
        klient.ValidatingAdmissionPolicy,
        std.testing.allocator,
        \\{"metadata":{"uid":"vap-default","name":"default-failure"},"spec":{"validations":[]}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer policy.deinit();
    var policy_record = try validating_policy.fromValidatingAdmissionPolicy(std.testing.allocator, policy.value);
    defer policy_record.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("Fail", policy_record.extra.failure_policy);

    var binding = try std.json.parseFromSlice(
        klient.MutatingAdmissionPolicyBinding,
        std.testing.allocator,
        \\{"metadata":{"uid":"mapb-default","name":"missing-spec"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer binding.deinit();
    var binding_record = try mutating_binding.fromMutatingAdmissionPolicyBinding(std.testing.allocator, binding.value);
    defer binding_record.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("<none>", binding_record.extra.value);

    var webhook = try std.json.parseFromSlice(
        klient.ValidatingWebhookConfiguration,
        std.testing.allocator,
        \\{"metadata":{"uid":"vwc-empty","name":"empty"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer webhook.deinit();
    var webhook_record = try validating_webhook.fromValidatingWebhookConfiguration(std.testing.allocator, webhook.value);
    defer webhook_record.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), webhook_record.extra.count);
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
