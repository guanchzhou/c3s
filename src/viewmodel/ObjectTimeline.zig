const std = @import("std");

pub const ObjectTimeline = struct {
    pub const max_entries = 128;

    pub const Entry = struct {
        timestamp: i64,
        revision: u64,
        summary: []u8,
    };

    allocator: std.mem.Allocator,
    source: []u8 = &.{},
    uid: []u8 = &.{},
    entries: std.ArrayListUnmanaged(Entry) = .empty,

    pub fn init(allocator: std.mem.Allocator) ObjectTimeline {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ObjectTimeline) void {
        self.clear();
        self.entries.deinit(self.allocator);
    }

    pub fn clear(self: *ObjectTimeline) void {
        for (self.entries.items) |entry| self.allocator.free(entry.summary);
        self.entries.clearRetainingCapacity();
        if (self.source.len > 0) self.allocator.free(self.source);
        if (self.uid.len > 0) self.allocator.free(self.uid);
        self.source = &.{};
        self.uid = &.{};
    }

    pub fn record(
        self: *ObjectTimeline,
        source: []const u8,
        uid: []const u8,
        revision: u64,
        timestamp: i64,
        summary: []const u8,
    ) !void {
        if (!std.mem.eql(u8, self.source, source) or !std.mem.eql(u8, self.uid, uid)) {
            self.clear();
            self.source = try self.allocator.dupe(u8, source);
            errdefer {
                self.allocator.free(self.source);
                self.source = &.{};
            }
            self.uid = try self.allocator.dupe(u8, uid);
        }
        if (self.entries.items.len > 0) {
            const previous = self.entries.items[self.entries.items.len - 1];
            if (previous.revision == revision or std.mem.eql(u8, previous.summary, summary)) return;
        }
        const owned = try self.allocator.dupe(u8, summary);
        errdefer self.allocator.free(owned);
        try self.entries.ensureUnusedCapacity(self.allocator, 1);
        if (self.entries.items.len == max_entries) {
            const removed = self.entries.orderedRemove(0);
            self.allocator.free(removed.summary);
        }
        self.entries.appendAssumeCapacity(.{
            .timestamp = timestamp,
            .revision = revision,
            .summary = owned,
        });
    }
};

test "timeline is bounded and resets on selected object replacement" {
    var timeline = ObjectTimeline.init(std.testing.allocator);
    defer timeline.deinit();
    for (0..ObjectTimeline.max_entries + 4) |index| {
        var buffer: [32]u8 = undefined;
        const summary = try std.fmt.bufPrint(&buffer, "state-{d}", .{index});
        try timeline.record("pods", "uid-a", index + 1, @intCast(index), summary);
    }
    try std.testing.expectEqual(ObjectTimeline.max_entries, timeline.entries.items.len);
    try timeline.record("pods", "uid-b", 1, 0, "Pending");
    try std.testing.expectEqual(@as(usize, 1), timeline.entries.items.len);
    try std.testing.expectEqualStrings("uid-b", timeline.uid);
}

test "timeline skips duplicate revisions and unchanged summaries" {
    var timeline = ObjectTimeline.init(std.testing.allocator);
    defer timeline.deinit();
    try timeline.record("pods", "uid-a", 1, 1, "Pending");
    try timeline.record("pods", "uid-a", 1, 2, "Running");
    try timeline.record("pods", "uid-a", 2, 3, "Pending");
    try std.testing.expectEqual(@as(usize, 1), timeline.entries.items.len);
}
