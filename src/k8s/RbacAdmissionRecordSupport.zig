const std = @import("std");
const age_util = @import("../viewmodel/age.zig");
const keys = @import("ResourceKey.zig");

pub const NoExtra = struct {
    pub fn clone(_: NoExtra, _: std.mem.Allocator) !NoExtra {
        return .{};
    }

    pub fn deinit(_: *NoExtra, _: std.mem.Allocator) void {}

    pub fn appendColumns(_: *const NoExtra, _: std.mem.Allocator, _: anytype, _: *usize) !void {}
};

pub const TextExtra = struct {
    value: []const u8,

    pub fn clone(self: TextExtra, allocator: std.mem.Allocator) !TextExtra {
        return .{ .value = try allocator.dupe(u8, self.value) };
    }

    pub fn deinit(self: *TextExtra, allocator: std.mem.Allocator) void {
        allocator.free(self.value);
        self.* = undefined;
    }

    pub fn appendColumns(self: *const TextExtra, allocator: std.mem.Allocator, result: anytype, initialized: *usize) !void {
        result[initialized.*] = try allocator.dupe(u8, self.value);
        initialized.* += 1;
    }
};

pub const RoleRefExtra = struct {
    kind: []const u8,
    name: []const u8,

    pub fn clone(self: RoleRefExtra, allocator: std.mem.Allocator) !RoleRefExtra {
        const kind = try allocator.dupe(u8, self.kind);
        errdefer allocator.free(kind);
        const name = try allocator.dupe(u8, self.name);
        return .{ .kind = kind, .name = name };
    }

    pub fn deinit(self: *RoleRefExtra, allocator: std.mem.Allocator) void {
        allocator.free(self.kind);
        allocator.free(self.name);
        self.* = undefined;
    }

    pub fn appendColumns(self: *const RoleRefExtra, allocator: std.mem.Allocator, result: anytype, initialized: *usize) !void {
        result[initialized.*] = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ self.kind, self.name });
        initialized.* += 1;
    }
};

pub const PolicyExtra = struct {
    failure_policy: []const u8,
    count: usize,

    pub fn clone(self: PolicyExtra, allocator: std.mem.Allocator) !PolicyExtra {
        return .{
            .failure_policy = try allocator.dupe(u8, self.failure_policy),
            .count = self.count,
        };
    }

    pub fn deinit(self: *PolicyExtra, allocator: std.mem.Allocator) void {
        allocator.free(self.failure_policy);
        self.* = undefined;
    }

    pub fn appendColumns(self: *const PolicyExtra, allocator: std.mem.Allocator, result: anytype, initialized: *usize) !void {
        result[initialized.*] = try allocator.dupe(u8, self.failure_policy);
        initialized.* += 1;
        result[initialized.*] = try std.fmt.allocPrint(allocator, "{d}", .{self.count});
        initialized.* += 1;
    }
};

pub const CountExtra = struct {
    count: usize,

    pub fn clone(self: CountExtra, _: std.mem.Allocator) !CountExtra {
        return self;
    }

    pub fn deinit(_: *CountExtra, _: std.mem.Allocator) void {}

    pub fn appendColumns(self: *const CountExtra, allocator: std.mem.Allocator, result: anytype, initialized: *usize) !void {
        result[initialized.*] = try std.fmt.allocPrint(allocator, "{d}", .{self.count});
        initialized.* += 1;
    }
};

pub fn Record(comptime Extra: type, comptime is_namespaced: bool, comptime extra_columns: usize) type {
    return struct {
        const Self = @This();
        const column_count = @as(usize, if (is_namespaced) 2 else 1) + extra_columns + 1;

        key: keys.ObjectKey,
        extra: Extra,
        creation_timestamp: ?[]u8 = null,

        pub fn init(
            allocator: std.mem.Allocator,
            uid: ?[]const u8,
            namespace: ?[]const u8,
            name: []const u8,
            extra: Extra,
            creation_timestamp: ?[]const u8,
        ) !Self {
            const actual_uid = uid orelse return error.MissingUid;
            var key = try (keys.ObjectKey{
                .uid = actual_uid,
                .namespace = if (is_namespaced) namespace orelse "default" else "",
                .name = name,
            }).clone(allocator);
            errdefer key.deinit(allocator);
            var owned_extra = try extra.clone(allocator);
            errdefer owned_extra.deinit(allocator);
            const timestamp = if (creation_timestamp) |value|
                try allocator.dupe(u8, value)
            else
                null;
            return .{ .key = key, .extra = owned_extra, .creation_timestamp = timestamp };
        }

        pub fn clone(self: Self, allocator: std.mem.Allocator) !Self {
            return init(
                allocator,
                self.key.uid,
                if (is_namespaced) self.key.namespace else null,
                self.key.name,
                self.extra,
                self.creation_timestamp,
            );
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            self.key.deinit(allocator);
            self.extra.deinit(allocator);
            if (self.creation_timestamp) |value| allocator.free(value);
            self.* = undefined;
        }

        pub fn columns(self: *const Self, allocator: std.mem.Allocator) ![column_count][]const u8 {
            var result: [column_count][]const u8 = undefined;
            var initialized: usize = 0;
            errdefer for (result[0..initialized]) |column| allocator.free(column);
            if (is_namespaced) {
                result[initialized] = try allocator.dupe(u8, self.key.namespace);
                initialized += 1;
            }
            result[initialized] = try allocator.dupe(u8, self.key.name);
            initialized += 1;
            try self.extra.appendColumns(allocator, &result, &initialized);
            result[initialized] = try age_util.calculateAge(allocator, self.creation_timestamp);
            return result;
        }
    };
}
