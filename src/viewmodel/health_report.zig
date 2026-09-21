const std = @import("std");

const ReportWriter = struct {
    allocator: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(u8),

    fn print(self: ReportWriter, comptime format: []const u8, args: anytype) !void {
        const text = try std.fmt.allocPrint(self.allocator, format, args);
        defer self.allocator.free(text);
        try self.out.appendSlice(self.allocator, text);
    }

    fn writeAll(self: ReportWriter, text: []const u8) !void {
        try self.out.appendSlice(self.allocator, text);
    }

    fn writeByte(self: ReportWriter, byte: u8) !void {
        try self.out.append(self.allocator, byte);
    }
};

pub const BuildOutput = struct {
    text: []u8,
    implicated_pod: ?[]u8,

    pub fn deinit(self: *BuildOutput, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.implicated_pod) |name| allocator.free(name);
        self.* = undefined;
    }
};

pub const Availability = struct {
    events: bool = true,
    related_pods: bool = true,
};

pub fn build(
    allocator: std.mem.Allocator,
    object_json: []const u8,
    events_json: []const u8,
) ![]u8 {
    const output = try buildWithPods(allocator, object_json, events_json, "");
    if (output.implicated_pod) |name| allocator.free(name);
    return output.text;
}

pub fn buildWithPods(
    allocator: std.mem.Allocator,
    object_json: []const u8,
    events_json: []const u8,
    pods_json: []const u8,
) !BuildOutput {
    return buildWithPodsStatus(allocator, object_json, events_json, pods_json, .{});
}

pub fn buildWithPodsStatus(
    allocator: std.mem.Allocator,
    object_json: []const u8,
    events_json: []const u8,
    pods_json: []const u8,
    availability: Availability,
) !BuildOutput {
    const object = try std.json.parseFromSlice(std.json.Value, allocator, object_json, .{});
    defer object.deinit();
    if (object.value != .object) return error.InvalidObject;

    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    const writer: ReportWriter = .{ .allocator = allocator, .out = &out };
    const root = object.value.object;
    const kind = stringAt(root, "kind") orelse "Resource";
    const metadata = objectAt(root, "metadata");
    const name = if (metadata) |value| stringAt(value, "name") orelse "unknown" else "unknown";
    try writer.print("{s}/{s}\n", .{ kind, name });

    var findings: usize = 0;
    if (objectAt(root, "status")) |status| {
        if (stringAt(status, "phase")) |phase| {
            try writer.print("Phase: {s}\n", .{phase});
            if (!std.ascii.eqlIgnoreCase(phase, "Running") and
                !std.ascii.eqlIgnoreCase(phase, "Succeeded") and
                !std.ascii.eqlIgnoreCase(phase, "Active"))
                findings += 1;
        }
        if (stringAt(status, "reason")) |reason| {
            try writer.print("Reason: {s}\n", .{reason});
            findings += 1;
        }
        findings += try appendConditions(writer, status);
        findings += try appendRollout(writer, root, status);
        findings += try appendContainerStatuses(writer, status, "initContainerStatuses");
        findings += try appendContainerStatuses(writer, status, "containerStatuses");
    }
    findings += try appendWarningEvents(allocator, writer, events_json);
    const implicated_pod = try appendRelatedPods(allocator, writer, pods_json, &findings);
    errdefer if (implicated_pod) |name_value| allocator.free(name_value);
    if (!availability.events) {
        try writer.writeAll("Warning events unavailable; report is partial.\n");
        findings += 1;
    }
    if (!availability.related_pods) {
        try writer.writeAll("Related pods unavailable; report is partial.\n");
        findings += 1;
    }
    if (findings == 0) try writer.writeAll("No deterministic unhealthy signal found.\n");
    return .{
        .text = try out.toOwnedSlice(allocator),
        .implicated_pod = implicated_pod,
    };
}

fn appendConditions(writer: anytype, status: std.json.ObjectMap) !usize {
    const value = status.get("conditions") orelse return 0;
    if (value != .array) return 0;
    var count: usize = 0;
    for (value.array.items) |condition| {
        if (condition != .object) continue;
        const state = stringAt(condition.object, "status") orelse continue;
        const condition_type = stringAt(condition.object, "type") orelse "Condition";
        const negative = std.mem.eql(u8, condition_type, "Failed") or
            std.mem.eql(u8, condition_type, "FailureTarget") or
            std.mem.eql(u8, condition_type, "ReplicaFailure") or
            std.mem.eql(u8, condition_type, "DisruptionTarget");
        if (negative == std.ascii.eqlIgnoreCase(state, "False")) continue;
        const reason = stringAt(condition.object, "reason") orelse state;
        const message = stringAt(condition.object, "message") orelse "";
        try writer.print("Condition {s}: {s}", .{ condition_type, reason });
        if (message.len > 0) try writer.print(" — {s}", .{message});
        try writer.writeByte('\n');
        count += 1;
    }
    return count;
}

fn appendRollout(writer: anytype, root: std.json.ObjectMap, status: std.json.ObjectMap) !usize {
    const spec = objectAt(root, "spec") orelse return 0;
    const desired = integerAt(spec, "replicas") orelse return 0;
    const ready = integerAt(status, "readyReplicas") orelse
        integerAt(status, "availableReplicas") orelse 0;
    if (ready >= desired) return 0;
    try writer.print("Rollout: {d}/{d} replicas ready\n", .{ ready, desired });
    return 1;
}

fn appendContainerStatuses(writer: anytype, status: std.json.ObjectMap, key: []const u8) !usize {
    const value = status.get(key) orelse return 0;
    if (value != .array) return 0;
    var count: usize = 0;
    for (value.array.items) |container| {
        if (container != .object) continue;
        const name = stringAt(container.object, "name") orelse "container";
        if (integerAt(container.object, "restartCount")) |restarts| {
            if (restarts > 0) {
                try writer.print("Container {s}: {d} restart(s)\n", .{ name, restarts });
                count += 1;
            }
        }
        const state = objectAt(container.object, "state") orelse continue;
        for ([_][]const u8{ "waiting", "terminated" }) |state_name| {
            const detail = objectAt(state, state_name) orelse continue;
            const reason = stringAt(detail, "reason") orelse state_name;
            const message = stringAt(detail, "message") orelse "";
            try writer.print("Container {s}: {s}", .{ name, reason });
            if (message.len > 0) try writer.print(" — {s}", .{message});
            try writer.writeByte('\n');
            count += 1;
        }
    }
    return count;
}

fn appendWarningEvents(
    allocator: std.mem.Allocator,
    writer: anytype,
    events_json: []const u8,
) !usize {
    if (events_json.len == 0) return 0;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, events_json, .{}) catch return 0;
    defer parsed.deinit();
    if (parsed.value != .object) return 0;
    const items = parsed.value.object.get("items") orelse return 0;
    if (items != .array) return 0;
    var count: usize = 0;
    for (items.array.items) |event| {
        if (event != .object) continue;
        const event_type = stringAt(event.object, "type") orelse continue;
        if (!std.ascii.eqlIgnoreCase(event_type, "Warning")) continue;
        const reason = stringAt(event.object, "reason") orelse "Warning";
        const message = stringAt(event.object, "message") orelse "";
        try writer.print("Warning event {s}", .{reason});
        if (message.len > 0) try writer.print(": {s}", .{message});
        try writer.writeByte('\n');
        count += 1;
    }
    return count;
}

fn appendRelatedPods(
    allocator: std.mem.Allocator,
    writer: anytype,
    pods_json: []const u8,
    findings: *usize,
) !?[]u8 {
    if (pods_json.len == 0) return null;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, pods_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const items = parsed.value.object.get("items") orelse return null;
    if (items != .array) return null;
    var implicated: ?[]u8 = null;
    errdefer if (implicated) |name| allocator.free(name);
    for (items.array.items) |pod| {
        if (pod != .object) continue;
        const status = objectAt(pod.object, "status") orelse continue;
        if (!podIsUnhealthy(status)) continue;
        const metadata = objectAt(pod.object, "metadata");
        const name = if (metadata) |value| stringAt(value, "name") orelse "unknown" else "unknown";
        if (implicated == null) implicated = try allocator.dupe(u8, name);
        try writer.print("Blocking pod {s}: phase={s}\n", .{
            name,
            stringAt(status, "phase") orelse "Unknown",
        });
        findings.* += 1;
        findings.* += try appendConditions(writer, status);
        findings.* += try appendContainerStatuses(writer, status, "initContainerStatuses");
        findings.* += try appendContainerStatuses(writer, status, "containerStatuses");
    }
    return implicated;
}

fn podIsUnhealthy(status: std.json.ObjectMap) bool {
    if (stringAt(status, "phase")) |phase| {
        if (std.ascii.eqlIgnoreCase(phase, "Succeeded")) return false;
        if (!std.ascii.eqlIgnoreCase(phase, "Running")) return true;
    }
    if (status.get("conditions")) |conditions| {
        if (conditions == .array) {
            for (conditions.array.items) |condition| {
                if (condition != .object) continue;
                if (std.mem.eql(u8, stringAt(condition.object, "type") orelse "", "Ready") and
                    !std.ascii.eqlIgnoreCase(stringAt(condition.object, "status") orelse "", "True"))
                    return true;
            }
        }
    }
    for ([_][]const u8{ "initContainerStatuses", "containerStatuses" }) |key| {
        const statuses = status.get(key) orelse continue;
        if (statuses != .array) continue;
        for (statuses.array.items) |container| {
            if (container != .object) continue;
            const state = objectAt(container.object, "state") orelse continue;
            if (state.contains("waiting")) return true;
            if (objectAt(state, "terminated")) |terminated|
                if ((integerAt(terminated, "exitCode") orelse 0) != 0) return true;
        }
    }
    return false;
}

fn objectAt(object: std.json.ObjectMap, key: []const u8) ?std.json.ObjectMap {
    const value = object.get(key) orelse return null;
    return if (value == .object) value.object else null;
}

fn stringAt(object: std.json.ObjectMap, key: []const u8) ?[]const u8 {
    const value = object.get(key) orelse return null;
    return if (value == .string) value.string else null;
}

fn integerAt(object: std.json.ObjectMap, key: []const u8) ?i64 {
    const value = object.get(key) orelse return null;
    return if (value == .integer) value.integer else null;
}

test "health report combines rollout containers conditions and warning events" {
    const object =
        \\{"kind":"Deployment","metadata":{"name":"web"},"spec":{"replicas":3},"status":{"readyReplicas":1,"conditions":[{"type":"Available","status":"False","reason":"MinimumReplicasUnavailable"}],"containerStatuses":[{"name":"web","restartCount":2,"state":{"waiting":{"reason":"CrashLoopBackOff"}}}]}}
    ;
    const events =
        \\{"items":[{"type":"Warning","reason":"BackOff","message":"restarting failed container"}]}
    ;
    const report = try build(std.testing.allocator, object, events);
    defer std.testing.allocator.free(report);
    try std.testing.expect(std.mem.indexOf(u8, report, "Rollout: 1/3") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "CrashLoopBackOff") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Warning event BackOff") != null);
}

test "health report identifies the first blocking related pod" {
    const object =
        \\{"kind":"Deployment","metadata":{"name":"web"},"spec":{"replicas":2},"status":{"readyReplicas":1}}
    ;
    const pods =
        \\{"items":[{"metadata":{"name":"web-bad"},"status":{"phase":"Pending","containerStatuses":[{"name":"web","restartCount":0,"state":{"waiting":{"reason":"ImagePullBackOff"}}}]}},{"metadata":{"name":"web-ok"},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"}]}}]}
    ;
    var output = try buildWithPods(std.testing.allocator, object, "", pods);
    defer output.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("web-bad", output.implicated_pod.?);
    try std.testing.expect(std.mem.indexOf(u8, output.text, "Blocking pod web-bad") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text, "ImagePullBackOff") != null);
}

test "health report rejects non-objects and tolerates malformed optional events" {
    try std.testing.expectError(
        error.InvalidObject,
        build(std.testing.allocator, "[]", ""),
    );
    const healthy =
        \\{"kind":"Pod","metadata":{"name":"ok"},"status":{"phase":"Running","conditions":[{"type":"Ready","status":"True"}]}}
    ;
    const report = try build(std.testing.allocator, healthy, "not-json");
    defer std.testing.allocator.free(report);
    try std.testing.expect(std.mem.indexOf(u8, report, "No deterministic unhealthy signal found.") != null);
}

test "health report marks unavailable optional evidence as partial" {
    const healthy =
        \\{"kind":"Deployment","metadata":{"name":"web"},"spec":{"replicas":1},"status":{"readyReplicas":1}}
    ;
    var output = try buildWithPodsStatus(std.testing.allocator, healthy, "", "", .{
        .events = false,
        .related_pods = false,
    });
    defer output.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.indexOf(u8, output.text, "Warning events unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text, "Related pods unavailable") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.text, "No deterministic unhealthy signal") == null);
}

test "health report treats negative conditions with true polarity as failures" {
    const job =
        \\{"kind":"Job","metadata":{"name":"broken"},"status":{"conditions":[{"type":"Failed","status":"True","reason":"BackoffLimitExceeded"},{"type":"Complete","status":"False","reason":"Running"}]}}
    ;
    const report = try build(std.testing.allocator, job, "");
    defer std.testing.allocator.free(report);
    try std.testing.expect(std.mem.indexOf(u8, report, "Condition Failed: BackoffLimitExceeded") != null);
}
