const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");

pub const RoleBindingRecord = support.Record(support.RoleRefExtra, true, 1);

pub fn fromRoleBinding(allocator: std.mem.Allocator, value: klient.RoleBinding) !RoleBindingRecord {
    return RoleBindingRecord.init(
        allocator,
        value.metadata.uid,
        value.metadata.namespace,
        value.metadata.name,
        .{ .kind = value.roleRef.kind, .name = value.roleRef.name },
        value.metadata.creationTimestamp,
    );
}
