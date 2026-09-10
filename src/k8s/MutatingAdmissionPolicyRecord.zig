const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");

pub const MutatingAdmissionPolicyRecord = support.Record(support.PolicyExtra, false, 2);

pub fn fromMutatingAdmissionPolicy(
    allocator: std.mem.Allocator,
    value: klient.MutatingAdmissionPolicy,
) !MutatingAdmissionPolicyRecord {
    const failure_policy: []const u8 = if (value.spec) |spec| spec.failurePolicy orelse "Fail" else "Fail";
    const mutation_count: usize = if (value.spec) |spec|
        if (spec.mutations) |mutations| mutations.len else 0
    else
        0;
    return MutatingAdmissionPolicyRecord.init(
        allocator,
        value.metadata,
        .{ .failure_policy = failure_policy, .count = mutation_count },
    );
}
