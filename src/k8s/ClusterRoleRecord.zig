const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");

pub const ClusterRoleRecord = support.Record(support.NoExtra, false, 0);

pub fn fromClusterRole(allocator: std.mem.Allocator, value: klient.ClusterRole) !ClusterRoleRecord {
    return ClusterRoleRecord.init(
        allocator,
        value.metadata,
        .{},
    );
}
