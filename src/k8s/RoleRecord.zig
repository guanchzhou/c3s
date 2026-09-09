const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");

pub const RoleRecord = support.Record(support.NoExtra, true, 0);

pub fn fromRole(allocator: std.mem.Allocator, value: klient.Role) !RoleRecord {
    return RoleRecord.init(
        allocator,
        value.metadata,
        .{},
    );
}
