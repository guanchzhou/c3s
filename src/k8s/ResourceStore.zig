const std = @import("std");
const resource_key = @import("ResourceKey.zig");

pub const ObjectKey = resource_key.ObjectKey;

pub const LookupError = error{AmbiguousName};

/// Producer-side owned state. Record must expose `key: ObjectKey`, `clone`, and
/// `deinit`. The map owns its UID keys separately from the records.
pub fn ResourceStore(comptime Record: type) type {
    return struct {
        allocator: std.mem.Allocator,
        by_uid: std.StringHashMapUnmanaged(Record) = .empty,

        const Self = @This();

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            var iterator = self.by_uid.iterator();
            while (iterator.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                entry.value_ptr.deinit(self.allocator);
            }
            self.by_uid.deinit(self.allocator);
            self.* = undefined;
        }

        pub fn count(self: *const Self) usize {
            return self.by_uid.count();
        }

        /// Deep-copies record. No caller-owned slice survives this call.
        pub fn upsert(self: *Self, record: Record) !void {
            var owned = try record.clone(self.allocator);
            errdefer owned.deinit(self.allocator);
            try self.putOwned(&owned);
        }

        /// Takes record on success and leaves it untouched on allocation failure.
        pub fn putOwned(self: *Self, record: *Record) !void {
            const map_key = try self.allocator.dupe(u8, record.key.uid);
            errdefer self.allocator.free(map_key);

            const result = try self.by_uid.getOrPut(self.allocator, map_key);
            if (result.found_existing) {
                self.allocator.free(map_key);
                result.value_ptr.deinit(self.allocator);
            }
            result.value_ptr.* = record.*;
            record.* = undefined;
        }

        pub fn delete(self: *Self, uid: []const u8) bool {
            const removed = self.by_uid.fetchRemove(uid) orelse return false;
            self.allocator.free(removed.key);
            var record = removed.value;
            record.deinit(self.allocator);
            return true;
        }

        /// Returns a deep copy so mutations cannot invalidate a consumer.
        pub fn getOwned(self: *const Self, uid: []const u8) !?Record {
            const record = self.by_uid.get(uid) orelse return null;
            return try record.clone(self.allocator);
        }

        /// Namespace/name is intentionally a secondary lookup. Duplicate names
        /// with distinct UIDs are represented faithfully and reported ambiguous.
        pub fn getByNameOwned(
            self: *const Self,
            namespace: []const u8,
            name: []const u8,
        ) (LookupError || std.mem.Allocator.Error)!?Record {
            var match: ?*const Record = null;
            var iterator = self.by_uid.valueIterator();
            while (iterator.next()) |record| {
                if (!std.mem.eql(u8, namespace, record.key.namespace)) continue;
                if (!std.mem.eql(u8, name, record.key.name)) continue;
                if (match != null) return error.AmbiguousName;
                match = record;
            }
            return if (match) |record| try record.clone(self.allocator) else null;
        }

        pub fn snapshot(self: *const Self) ![]Record {
            var records = try self.allocator.alloc(Record, self.by_uid.count());
            errdefer self.allocator.free(records);

            var initialized: usize = 0;
            errdefer for (records[0..initialized]) |*record| record.deinit(self.allocator);

            var iterator = self.by_uid.valueIterator();
            while (iterator.next()) |record| {
                records[initialized] = try record.clone(self.allocator);
                initialized += 1;
            }
            return records;
        }

        /// Applies a batch by cloning upserts. The caller retains the batch and
        /// may always deinit it, including after a partial allocation failure.
        pub fn applyBatch(
            self: *Self,
            batch: *const resource_key.TypedBatch(Record),
        ) !void {
            for (batch.changes) |change| switch (change) {
                .initial_upsert, .watch_upsert => |record| {
                    if (record) |value| try self.upsert(value);
                },
                .delete => |key| _ = self.delete(key.uid),
                .metrics => {},
            };
        }

        pub fn freeSnapshot(self: *const Self, records: []Record) void {
            for (records) |*record| record.deinit(self.allocator);
            self.allocator.free(records);
        }
    };
}

const TestRecord = struct {
    key: ObjectKey,
    value: u32,

    fn make(
        allocator: std.mem.Allocator,
        uid: []const u8,
        namespace: []const u8,
        name: []const u8,
        value: u32,
    ) !TestRecord {
        return .{
            .key = try (ObjectKey{
                .uid = uid,
                .namespace = namespace,
                .name = name,
            }).clone(allocator),
            .value = value,
        };
    }

    pub fn clone(self: TestRecord, allocator: std.mem.Allocator) !TestRecord {
        return .{ .key = try self.key.clone(allocator), .value = self.value };
    }

    pub fn deinit(self: *TestRecord, allocator: std.mem.Allocator) void {
        self.key.deinit(allocator);
    }
};

test "duplicate namespace name with distinct UID remains distinct" {
    const allocator = std.testing.allocator;
    const Store = ResourceStore(TestRecord);
    var store = Store.init(allocator);
    defer store.deinit();

    var first = try TestRecord.make(allocator, "uid-1", "ns", "pod", 1);
    defer first.deinit(allocator);
    var second = try TestRecord.make(allocator, "uid-2", "ns", "pod", 2);
    defer second.deinit(allocator);
    try store.upsert(first);
    try store.upsert(second);

    try std.testing.expectEqual(@as(usize, 2), store.count());
    try std.testing.expectError(error.AmbiguousName, store.getByNameOwned("ns", "pod"));
}

test "same UID replacement and deletion clean old ownership" {
    const allocator = std.testing.allocator;
    const Store = ResourceStore(TestRecord);
    var store = Store.init(allocator);
    defer store.deinit();

    var old = try TestRecord.make(allocator, "uid", "ns", "old", 1);
    defer old.deinit(allocator);
    var replacement = try TestRecord.make(allocator, "uid", "other", "new", 9);
    defer replacement.deinit(allocator);
    try store.upsert(old);
    try store.upsert(replacement);
    try std.testing.expectEqual(@as(usize, 1), store.count());

    var fetched = (try store.getOwned("uid")).?;
    defer fetched.deinit(allocator);
    try std.testing.expectEqualStrings("new", fetched.key.name);
    try std.testing.expectEqual(@as(u32, 9), fetched.value);
    try std.testing.expect(store.delete("uid"));
    try std.testing.expect(!store.delete("uid"));
}

test "store and snapshot do not borrow inputs" {
    const allocator = std.testing.allocator;
    const Store = ResourceStore(TestRecord);
    var store = Store.init(allocator);
    defer store.deinit();

    var uid = [_]u8{ 'u', 'i', 'd' };
    var record = try TestRecord.make(allocator, &uid, "ns", "pod", 4);
    try store.putOwned(&record);
    uid[0] = 'x';

    const snapshot = try store.snapshot();
    defer store.freeSnapshot(snapshot);
    try std.testing.expectEqualStrings("uid", snapshot[0].key.uid);
    @constCast(snapshot[0].key.name)[0] = 'X';

    var fetched = (try store.getOwned("uid")).?;
    defer fetched.deinit(allocator);
    try std.testing.expectEqualStrings("pod", fetched.key.name);
}

test "allocation failures leave owned input valid and leak free" {
    const backing = std.testing.allocator;
    const Store = ResourceStore(TestRecord);
    var fail_index: usize = 0;
    while (fail_index < 8) : (fail_index += 1) {
        var failing = std.testing.FailingAllocator.init(backing, .{ .fail_index = fail_index });
        var store = Store.init(failing.allocator());
        defer store.deinit();
        var record = try TestRecord.make(backing, "uid", "ns", "pod", 1);
        defer record.deinit(backing);

        if (store.upsert(record)) |_| {
            try std.testing.expectEqual(@as(usize, 1), store.count());
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(@as(usize, 0), store.count());
        }
    }
}

test "batch application does not consume caller ownership" {
    const allocator = std.testing.allocator;
    const Store = ResourceStore(TestRecord);
    var store = Store.init(allocator);
    defer store.deinit();

    const changes = try allocator.alloc(resource_key.TypedChange(TestRecord), 1);
    changes[0] = .{ .watch_upsert = try TestRecord.make(allocator, "uid", "ns", "pod", 5) };
    var batch = resource_key.TypedBatch(TestRecord){
        .generation = 1,
        .subscription_id = 1,
        .revision = 1,
        .changes = changes,
        .sync = null,
        .owned_bytes = 1,
    };
    defer batch.deinit(allocator);

    try store.applyBatch(&batch);
    try std.testing.expect(batch.changes[0].watch_upsert != null);
    var fetched = (try store.getOwned("uid")).?;
    defer fetched.deinit(allocator);
    try std.testing.expectEqual(@as(u32, 5), fetched.value);
}
