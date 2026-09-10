const std = @import("std");

pub fn format(allocator: std.mem.Allocator, status: ?std.json.Value) !?[]u8 {
    const value = status orelse return null;
    if (value != .object) return null;
    const load_balancer = value.object.get("loadBalancer") orelse return null;
    if (load_balancer != .object) return null;
    const ingress = load_balancer.object.get("ingress") orelse
        return try allocator.dupe(u8, "<pending>");
    if (ingress != .array) return null;
    if (ingress.array.items.len == 0) return try allocator.dupe(u8, "<pending>");

    var result: std.ArrayListUnmanaged(u8) = .empty;
    defer result.deinit(allocator);
    for (ingress.array.items) |entry| {
        if (entry != .object) continue;
        const address = stringField(entry, "ip") orelse
            stringField(entry, "hostname") orelse continue;
        if (result.items.len > 0) try result.append(allocator, ',');
        try result.appendSlice(allocator, address);
    }
    if (result.items.len == 0) return try allocator.dupe(u8, "<pending>");
    return try result.toOwnedSlice(allocator);
}

fn stringField(value: std.json.Value, field: []const u8) ?[]const u8 {
    if (value != .object) return null;
    const member = value.object.get(field) orelse return null;
    return if (member == .string) member.string else null;
}

test "formats load balancer IPs and hostnames" {
    var parsed = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        \\{"loadBalancer":{"ingress":[{"ip":"10.0.0.1"},{"hostname":"lb.example"}]}}
    ,
        .{},
    );
    defer parsed.deinit();
    const addresses = (try format(std.testing.allocator, parsed.value)).?;
    defer std.testing.allocator.free(addresses);
    try std.testing.expectEqualStrings("10.0.0.1,lb.example", addresses);
}
