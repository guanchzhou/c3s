const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");

pub const MutatingWebhookConfigurationRecord = support.Record(support.CountExtra, false, 1);

pub fn fromMutatingWebhookConfiguration(
    allocator: std.mem.Allocator,
    value: klient.MutatingWebhookConfiguration,
) !MutatingWebhookConfigurationRecord {
    return MutatingWebhookConfigurationRecord.init(
        allocator,
        value.metadata,
        .{ .count = if (value.webhooks) |webhooks| webhooks.len else 0 },
    );
}
