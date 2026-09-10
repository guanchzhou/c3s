const std = @import("std");
const klient = @import("klient");
const support = @import("RbacAdmissionRecordSupport.zig");

pub const ValidatingWebhookConfigurationRecord = support.Record(support.CountExtra, false, 1);

pub fn fromValidatingWebhookConfiguration(
    allocator: std.mem.Allocator,
    value: klient.ValidatingWebhookConfiguration,
) !ValidatingWebhookConfigurationRecord {
    return ValidatingWebhookConfigurationRecord.init(
        allocator,
        value.metadata,
        .{ .count = if (value.webhooks) |webhooks| webhooks.len else 0 },
    );
}
