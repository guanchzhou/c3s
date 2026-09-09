const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");

pub const MutatingAdmissionPolicyBindingRecord = support.Record(support.TextExtra, false, 1);

pub fn fromMutatingAdmissionPolicyBinding(
    allocator: std.mem.Allocator,
    value: klient.MutatingAdmissionPolicyBinding,
) !MutatingAdmissionPolicyBindingRecord {
    const policy_name: []const u8 = if (value.spec) |spec| spec.policyName else "<none>";
    return MutatingAdmissionPolicyBindingRecord.init(
        allocator,
        value.metadata,
        .{ .value = policy_name },
    );
}
