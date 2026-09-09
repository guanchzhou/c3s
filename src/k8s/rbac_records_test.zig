const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");
const keys = @import("ResourceKey.zig");
const k9s_query = @import("../viewmodel/k9s_query.zig");

const RoleRecord = @import("RoleRecord.zig");
const RoleBindingRecord = @import("RoleBindingRecord.zig");
const ClusterRoleRecord = @import("ClusterRoleRecord.zig");
const ClusterRoleBindingRecord = @import("ClusterRoleBindingRecord.zig");

pub const role_object_json =
    \\{"apiVersion":"rbac.authorization.k8s.io/v1","kind":"Role","metadata":{"uid":"role-1","namespace":"team-a","name":"reader","labels":{"app":"reader","tier":"rbac"}},"rules":[{"apiGroups":[""],"resources":["pods"],"verbs":["get","list","watch"]}]}
;
pub const role_binding_object_json =
    \\{"apiVersion":"rbac.authorization.k8s.io/v1","kind":"RoleBinding","metadata":{"uid":"rb-1","namespace":"team-a","name":"readers"},"subjects":[{"kind":"ServiceAccount","name":"viewer","namespace":"team-a"}],"roleRef":{"apiGroup":"rbac.authorization.k8s.io","kind":"Role","name":"reader"}}
;
pub const cluster_role_object_json =
    \\{"apiVersion":"rbac.authorization.k8s.io/v1","kind":"ClusterRole","metadata":{"uid":"cr-1","name":"cluster-reader","labels":{"app":"cluster-reader","scope":"cluster"}},"rules":[{"apiGroups":[""],"resources":["nodes"],"verbs":["get","list"]}]}
;
pub const cluster_role_binding_object_json =
    \\{"apiVersion":"rbac.authorization.k8s.io/v1","kind":"ClusterRoleBinding","metadata":{"uid":"crb-1","name":"cluster-readers"},"subjects":[{"kind":"Group","name":"readers","apiGroup":"rbac.authorization.k8s.io"}],"roleRef":{"apiGroup":"rbac.authorization.k8s.io","kind":"ClusterRole","name":"cluster-reader"}}
;

fn freeColumns(columns: anytype) void {
    for (columns) |column| std.testing.allocator.free(column);
}

fn expectCloneFailureSafe(comptime Record: type, source: Record) !void {
    const Exercise = struct {
        fn run(allocator: std.mem.Allocator, value: Record) !void {
            var copy = try value.clone(allocator);
            copy.deinit(allocator);
        }
    };
    try std.testing.checkAllAllocationFailures(std.testing.allocator, Exercise.run, .{source});
}

fn expectRules(comptime T: type) fn (*const T) anyerror!void {
    return struct {
        fn run(object: *const T) anyerror!void {
            const rules = object.rules orelse return error.MissingRules;
            try std.testing.expect(rules.len > 0);
            try std.testing.expect(rules[0].verbs.len > 0);
        }
    }.run;
}

fn expectBinding(
    comptime T: type,
    comptime kind: []const u8,
    comptime name: []const u8,
) fn (*const T) anyerror!void {
    return struct {
        fn run(object: *const T) anyerror!void {
            try std.testing.expectEqualStrings(kind, object.roleRef.kind);
            try std.testing.expectEqualStrings(name, object.roleRef.name);
            const subjects = object.subjects orelse return error.MissingSubjects;
            try std.testing.expect(subjects.len > 0);
            try std.testing.expect(subjects[0].kind.len > 0);
            try std.testing.expect(subjects[0].name.len > 0);
        }
    }.run;
}

/// A projected record must carry the flattened `metadata.labels` its object
/// declared, bounded, so `-l` filters work on rows that never left the wire.
fn expectProjectedLabels(labels: []const u8, expected_labels: []const u8) !void {
    try std.testing.expectEqualStrings(expected_labels, labels);
    try std.testing.expect(labels.len <= keys.max_projected_label_bytes);
    if (expected_labels.len > 0) {
        try std.testing.expect(k9s_query.labelsMatch(labels, expected_labels));
    }
}

fn exerciseRealShapedDecode(
    comptime T: type,
    comptime Record: type,
    comptime fromObject: fn (std.mem.Allocator, T) anyerror!Record,
    comptime object_json: []const u8,
    comptime path: []const u8,
    comptime expected: []const []const u8,
    comptime expected_labels: []const u8,
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
            var record = try fromObject(std.testing.allocator, items[0]);
            defer record.deinit(std.testing.allocator);
            try expectProjectedLabels(record.key.labels, expected_labels);
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
    var record = try fromObject(std.testing.allocator, object.*);
    defer record.deinit(std.testing.allocator);
    try expectProjectedLabels(record.key.labels, expected_labels);
    const columns = try record.columns(std.testing.allocator);
    defer freeColumns(columns);
    for (columns, expected) |actual, wanted|
        try std.testing.expectEqualStrings(wanted, actual);
}

test "real-shaped Role LIST and WATCH decode flat rules" {
    try exerciseRealShapedDecode(
        klient.Role,
        RoleRecord.RoleRecord,
        RoleRecord.fromRole,
        role_object_json,
        "/apis/rbac.authorization.k8s.io/v1/roles",
        &.{ "team-a", "reader", "n/a" },
        "app=reader,tier=rbac",
        expectRules(klient.Role),
    );
}

test "real-shaped RoleBinding LIST and WATCH decode flat roleRef and subjects" {
    try exerciseRealShapedDecode(
        klient.RoleBinding,
        RoleBindingRecord.RoleBindingRecord,
        RoleBindingRecord.fromRoleBinding,
        role_binding_object_json,
        "/apis/rbac.authorization.k8s.io/v1/rolebindings",
        &.{ "team-a", "readers", "Role/reader", "n/a" },
        "",
        expectBinding(klient.RoleBinding, "Role", "reader"),
    );
}

test "real-shaped ClusterRole LIST and WATCH decode flat rules" {
    try exerciseRealShapedDecode(
        klient.ClusterRole,
        ClusterRoleRecord.ClusterRoleRecord,
        ClusterRoleRecord.fromClusterRole,
        cluster_role_object_json,
        "/apis/rbac.authorization.k8s.io/v1/clusterroles",
        &.{ "cluster-reader", "n/a" },
        "app=cluster-reader,scope=cluster",
        expectRules(klient.ClusterRole),
    );
}

test "real-shaped ClusterRoleBinding LIST and WATCH decode flat roleRef and subjects" {
    try exerciseRealShapedDecode(
        klient.ClusterRoleBinding,
        ClusterRoleBindingRecord.ClusterRoleBindingRecord,
        ClusterRoleBindingRecord.fromClusterRoleBinding,
        cluster_role_binding_object_json,
        "/apis/rbac.authorization.k8s.io/v1/clusterrolebindings",
        &.{ "cluster-readers", "ClusterRole/cluster-reader", "n/a" },
        "",
        expectBinding(klient.ClusterRoleBinding, "ClusterRole", "cluster-reader"),
    );
}

test "Role decoding permits omitted rules" {
    var parsed = try std.json.parseFromSlice(
        klient.Role,
        std.testing.allocator,
        \\{"apiVersion":"rbac.authorization.k8s.io/v1","kind":"Role","metadata":{"uid":"role-empty","namespace":"team-a","name":"empty"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    try std.testing.expect(parsed.value.rules == null);
}

test "RBAC namespaced records retain default namespace fallback" {
    var role_parsed = try std.json.parseFromSlice(
        klient.Role,
        std.testing.allocator,
        \\{"metadata":{"uid":"role-default","name":"reader"},"rules":[]}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer role_parsed.deinit();
    var role = try RoleRecord.fromRole(std.testing.allocator, role_parsed.value);
    defer role.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("default", role.key.namespace);

    var binding_parsed = try std.json.parseFromSlice(
        klient.RoleBinding,
        std.testing.allocator,
        \\{"metadata":{"uid":"binding-default","name":"readers"},"roleRef":{"apiGroup":"rbac.authorization.k8s.io","kind":"Role","name":"reader"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer binding_parsed.deinit();
    var binding = try RoleBindingRecord.fromRoleBinding(std.testing.allocator, binding_parsed.value);
    defer binding.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("default", binding.key.namespace);
}

test "RBAC records reject UID-less resources" {
    try std.testing.expectError(error.MissingUid, RoleRecord.fromRole(std.testing.allocator, .{
        .metadata = .{ .name = "role" },
    }));
    try std.testing.expectError(error.MissingUid, RoleBindingRecord.fromRoleBinding(std.testing.allocator, .{
        .metadata = .{ .name = "binding" },
        .roleRef = .{ .apiGroup = "rbac.authorization.k8s.io", .kind = "Role", .name = "role" },
    }));
    try std.testing.expectError(error.MissingUid, ClusterRoleRecord.fromClusterRole(std.testing.allocator, .{
        .metadata = .{ .name = "cluster-role" },
    }));
    try std.testing.expectError(error.MissingUid, ClusterRoleBindingRecord.fromClusterRoleBinding(std.testing.allocator, .{
        .metadata = .{ .name = "cluster-binding" },
        .roleRef = .{ .apiGroup = "rbac.authorization.k8s.io", .kind = "ClusterRole", .name = "cluster-role" },
    }));
}

test "RBAC record clones are allocation failure safe" {
    var role_parsed = try std.json.parseFromSlice(klient.Role, std.testing.allocator, role_object_json, .{ .ignore_unknown_fields = true });
    defer role_parsed.deinit();
    var role = try RoleRecord.fromRole(std.testing.allocator, role_parsed.value);
    defer role.deinit(std.testing.allocator);
    try expectCloneFailureSafe(RoleRecord.RoleRecord, role);

    var role_binding_parsed = try std.json.parseFromSlice(klient.RoleBinding, std.testing.allocator, role_binding_object_json, .{ .ignore_unknown_fields = true });
    defer role_binding_parsed.deinit();
    var role_binding = try RoleBindingRecord.fromRoleBinding(std.testing.allocator, role_binding_parsed.value);
    defer role_binding.deinit(std.testing.allocator);
    try expectCloneFailureSafe(RoleBindingRecord.RoleBindingRecord, role_binding);

    var cluster_role_parsed = try std.json.parseFromSlice(klient.ClusterRole, std.testing.allocator, cluster_role_object_json, .{ .ignore_unknown_fields = true });
    defer cluster_role_parsed.deinit();
    var cluster_role = try ClusterRoleRecord.fromClusterRole(std.testing.allocator, cluster_role_parsed.value);
    defer cluster_role.deinit(std.testing.allocator);
    try expectCloneFailureSafe(ClusterRoleRecord.ClusterRoleRecord, cluster_role);

    var cluster_role_binding_parsed = try std.json.parseFromSlice(klient.ClusterRoleBinding, std.testing.allocator, cluster_role_binding_object_json, .{ .ignore_unknown_fields = true });
    defer cluster_role_binding_parsed.deinit();
    var cluster_role_binding = try ClusterRoleBindingRecord.fromClusterRoleBinding(std.testing.allocator, cluster_role_binding_parsed.value);
    defer cluster_role_binding.deinit(std.testing.allocator);
    try expectCloneFailureSafe(ClusterRoleBindingRecord.ClusterRoleBindingRecord, cluster_role_binding);
}
