const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");

pub const ValidatingAdmissionPolicyRecord = support.Record(support.PolicyExtra, false, 2);

pub fn fromValidatingAdmissionPolicy(
    allocator: std.mem.Allocator,
    value: klient.ValidatingAdmissionPolicy,
) !ValidatingAdmissionPolicyRecord {
    const failure_policy: []const u8 = if (value.spec) |spec| spec.failurePolicy orelse "Fail" else "Fail";
    const validation_count: usize = if (value.spec) |spec|
        if (spec.validations) |validations| validations.len else 0
    else
        0;
    return ValidatingAdmissionPolicyRecord.init(
        allocator,
        value.metadata,
        .{ .failure_policy = failure_policy, .count = validation_count },
    );
}
