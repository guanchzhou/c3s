const std = @import("std");

pub fn dupeOrNone(allocator: std.mem.Allocator, value: ?[]const u8) ![]u8 {
    return allocator.dupe(u8, value orelse "<none>");
}

pub fn dupeTimestamp(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    return if (value) |timestamp| try allocator.dupe(u8, timestamp) else null;
}

pub fn firstObjectString(
    allocator: std.mem.Allocator,
    values: ?[]const std.json.Value,
    field: []const u8,
) ![]u8 {
    const items = values orelse return dupeOrNone(allocator, null);
    if (items.len == 0 or items[0] != .object) return dupeOrNone(allocator, null);
    const value = items[0].object.get(field) orelse return dupeOrNone(allocator, null);
    return dupeOrNone(allocator, if (value == .string) value.string else null);
}

pub fn objectString(
    allocator: std.mem.Allocator,
    value: ?std.json.Value,
    field: []const u8,
) ![]u8 {
    const object = value orelse return dupeOrNone(allocator, null);
    if (object != .object) return dupeOrNone(allocator, null);
    const member = object.object.get(field) orelse return dupeOrNone(allocator, null);
    return dupeOrNone(allocator, if (member == .string) member.string else null);
}

pub fn joinStrings(allocator: std.mem.Allocator, values: ?[][]const u8) ![]u8 {
    const items = values orelse return dupeOrNone(allocator, null);
    if (items.len == 0) return dupeOrNone(allocator, null);
    var result: std.ArrayListUnmanaged(u8) = .empty;
    defer result.deinit(allocator);
    for (items, 0..) |item, index| {
        if (index > 0) try result.append(allocator, ',');
        try result.appendSlice(allocator, item);
    }
    return result.toOwnedSlice(allocator);
}

pub fn joinObjectStrings(
    allocator: std.mem.Allocator,
    container: ?std.json.Value,
    array_field: []const u8,
    value_field: []const u8,
) ![]u8 {
    const object = container orelse return dupeOrNone(allocator, null);
    if (object != .object) return dupeOrNone(allocator, null);
    const array = object.object.get(array_field) orelse return dupeOrNone(allocator, null);
    if (array != .array) return dupeOrNone(allocator, null);
    var result: std.ArrayListUnmanaged(u8) = .empty;
    defer result.deinit(allocator);
    for (array.array.items) |entry| {
        if (entry != .object) continue;
        const value = entry.object.get(value_field) orelse continue;
        if (value != .string) continue;
        if (result.items.len > 0) try result.append(allocator, ',');
        try result.appendSlice(allocator, value.string);
    }
    if (result.items.len == 0) return dupeOrNone(allocator, null);
    return result.toOwnedSlice(allocator);
}

pub fn freeColumns(allocator: std.mem.Allocator, columns: []const []const u8) void {
    for (columns) |column| allocator.free(column);
}
