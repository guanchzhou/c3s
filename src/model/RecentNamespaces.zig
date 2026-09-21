const std = @import("std");

pub const max_entries = 9;

pub const RecentNamespaces = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayListUnmanaged([]u8) = .empty,

    pub fn init(
        allocator: std.mem.Allocator,
        initial: []const []const u8,
    ) !RecentNamespaces {
        var self = RecentNamespaces{ .allocator = allocator };
        errdefer self.deinit();
        var index = @min(initial.len, max_entries);
        while (index > 0) {
            index -= 1;
            try self.record(initial[index]);
        }
        return self;
    }

    pub fn deinit(self: *RecentNamespaces) void {
        for (self.entries.items) |entry| self.allocator.free(entry);
        self.entries.deinit(self.allocator);
    }

    pub fn record(self: *RecentNamespaces, namespace: []const u8) !void {
        if (namespace.len == 0) return;
        var existing: ?usize = null;
        for (self.entries.items, 0..) |entry, index| {
            if (std.mem.eql(u8, entry, namespace)) {
                existing = index;
                break;
            }
        }

        if (existing) |index| {
            const owned = self.entries.orderedRemove(index);
            try self.entries.insert(self.allocator, 0, owned);
            return;
        }

        const owned = try self.allocator.dupe(u8, namespace);
        errdefer self.allocator.free(owned);
        try self.entries.insert(self.allocator, 0, owned);
        if (self.entries.items.len > max_entries) {
            self.allocator.free(self.entries.pop().?);
        }
    }

    pub fn at(self: *const RecentNamespaces, slot: u8) ?[]const u8 {
        if (slot == 0 or slot > max_entries) return null;
        const index: usize = slot - 1;
        if (index >= self.entries.items.len) return null;
        return self.entries.items[index];
    }

    pub fn shortcutFor(self: *const RecentNamespaces, namespace: []const u8) ?u8 {
        for (self.entries.items, 0..) |entry, index| {
            if (std.mem.eql(u8, entry, namespace)) return @intCast(index + 1);
        }
        return null;
    }
};

test "recent namespaces are unique MRU entries capped at nine" {
    var recent = try RecentNamespaces.init(std.testing.allocator, &.{
        "three", "two", "one",
    });
    defer recent.deinit();

    try std.testing.expectEqualStrings("three", recent.at(1).?);
    try recent.record("one");
    try std.testing.expectEqualStrings("one", recent.at(1).?);
    try std.testing.expectEqual(@as(u8, 1), recent.shortcutFor("one").?);

    for (1..11) |index| {
        var buffer: [16]u8 = undefined;
        try recent.record(try std.fmt.bufPrint(&buffer, "ns-{d}", .{index}));
    }
    try std.testing.expectEqual(@as(usize, max_entries), recent.entries.items.len);
    try std.testing.expectEqualStrings("ns-10", recent.at(1).?);
    try std.testing.expect(recent.shortcutFor("three") == null);
}
