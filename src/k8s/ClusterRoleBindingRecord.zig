const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");

pub const ClusterRoleBindingRecord = support.Record(support.RoleRefExtra, false, 1);

pub fn fromClusterRoleBinding(allocator: std.mem.Allocator, value: klient.ClusterRoleBinding) !ClusterRoleBindingRecord {
    return ClusterRoleBindingRecord.init(
        allocator,
        value.metadata,
        .{ .kind = value.roleRef.kind, .name = value.roleRef.name },
    );
}
