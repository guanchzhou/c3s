const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");

pub const ValidatingAdmissionPolicyBindingRecord = support.Record(support.TextExtra, false, 1);

pub fn fromValidatingAdmissionPolicyBinding(
    allocator: std.mem.Allocator,
    value: klient.ValidatingAdmissionPolicyBinding,
) !ValidatingAdmissionPolicyBindingRecord {
    const policy_name: []const u8 = if (value.spec) |spec| spec.policyName else "<none>";
    return ValidatingAdmissionPolicyBindingRecord.init(
        allocator,
        value.metadata,
        .{ .value = policy_name },
    );
}
