const std = @import("std");

const ReportWriter = struct {
    allocator: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(u8),

    fn print(self: ReportWriter, comptime format: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, format, args);
        defer self.allocator.free(text);
        try self.out.appendSlice(self.allocator, text);
    }

    fn writeByte(self: ReportWriter, byte: u8) !void {
        try self.out.append(self.allocator, byte);
    }
};

pub fn build(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, raw, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidApplication;
    const root = parsed.value.object;
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    const writer: ReportWriter = .{ .allocator = allocator, .out = &out };

    const metadata = objectAt(root, "metadata");
    const name = if (metadata) |value| stringAt(value, "name") orelse "unknown" else "unknown";
    try writer.print("Application: {s}\n", .{name});
    if (objectAt(root, "status")) |status| {
        if (objectAt(status, "sync")) |sync|
            try writer.print("Sync: {s}\n", .{stringAt(sync, "status") orelse "Unknown"});
        if (objectAt(status, "health")) |health|
            try writer.print("Health: {s}\n", .{stringAt(health, "status") orelse "Unknown"});
        if (stringNested(status, "sync", "revision")) |revision|
            try writer.print("Revision: {s}\n", .{revision});
        try appendConditions(writer, status);
        try appendResources(writer, status, "resources", "Live resources");
        if (objectAt(status, "operationState")) |operation| {
            try writer.print("Operation: {s}\n", .{stringAt(operation, "phase") orelse "Unknown"});
            if (objectAt(operation, "syncResult")) |result|
                try appendResources(writer, result, "resources", "Latest operation");
        }
    }
    if (objectAt(root, "spec")) |spec| {
        if (objectAt(spec, "source")) |source| {
            if (stringAt(source, "repoURL")) |value| try writer.print("Source: {s}\n", .{value});
            if (stringAt(source, "path")) |value| try writer.print("Path: {s}\n", .{value});
            if (stringAt(source, "targetRevision")) |value| try writer.print("Target revision: {s}\n", .{value});
        }
    }
    return out.toOwnedSlice(allocator);
}

fn appendConditions(writer: anytype, status: std.json.ObjectMap) !void {
    const value = status.get("conditions") orelse return;
    if (value != .array) return;
    for (value.array.items) |condition| {
        if (condition != .object) continue;
        try writer.print("Condition {s}: {s}\n", .{
            stringAt(condition.object, "type") orelse "Unknown",
            stringAt(condition.object, "message") orelse "",
        });
    }
}

fn appendResources(writer: anytype, object: std.json.ObjectMap, key: []const u8, heading: []const u8) !void {
    const value = object.get(key) orelse return;
    if (value != .array or value.array.items.len == 0) return;
    try writer.print("{s}:\n", .{heading});
    for (value.array.items) |resource| {
        if (resource != .object) continue;
        try writer.print("  {s}/{s} ns={s} status={s} health={s}", .{
            stringAt(resource.object, "kind") orelse "?",
            stringAt(resource.object, "name") orelse "?",
            stringAt(resource.object, "namespace") orelse "-",
            stringAt(resource.object, "status") orelse "-",
            stringNested(resource.object, "health", "status") orelse "-",
        });
        if (stringAt(resource.object, "message")) |message| try writer.print(" — {s}", .{message});
        try writer.writeByte('\n');
    }
}

fn objectAt(object: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
    const value = object.get(key) orelse return null;
    return if (value == .object) value.object else null;
}

fn stringAt(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return if (value == .string) value.string else null;
}

fn stringNested(object: std.json.ObjectMap, parent: []const u8, key: []const u8) ?[]const u8 {
    const nested = objectAt(object, parent) orelse return null;
    return stringAt(nested, key);
}

test "Argo sync details report is truthful status data" {
    const raw =
        \\{"metadata":{"name":"web"},"spec":{"source":{"repoURL":"https://example/repo","path":"apps/web","targetRevision":"main"}},"status":{"sync":{"status":"OutOfSync","revision":"abc"},"health":{"status":"Degraded"},"resources":[{"kind":"Deployment","name":"web","namespace":"prod","status":"OutOfSync","health":{"status":"Degraded"}}]}}
    ;
    const report = try build(std.testing.allocator, raw);
    defer std.testing.allocator.free(report);
    try std.testing.expect(std.mem.indexOf(u8, report, "Sync: OutOfSync") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Health: Degraded") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Deployment/web") != null);
}

test "Argo sync details reject non-objects and tolerate missing status" {
    try std.testing.expectError(error.InvalidApplication, build(std.testing.allocator, "[]"));
    const report = try build(std.testing.allocator, "{\"metadata\":{\"name\":\"empty\"}}");
    defer std.testing.allocator.free(report);
    try std.testing.expectEqualStrings("Application: empty\n", report);
}
