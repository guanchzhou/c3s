const std = @import("std");
const klient = @import("klient");
const resource_key = @import("ResourceKey.zig");

pub const ObjectKey = resource_key.ObjectKey;

pub const Error = error{MissingUid};

pub const Owner = struct {
    kind: []const u8 = "",
    name: []const u8 = "",
    uid: []const u8 = "",
};

/// Metadata not represented by klient.Pod but available to a LIST/WATCH adapter.
pub const SourceMetadata = struct {
    owner: ?Owner = null,
};

key: ObjectKey,
resource_version: []u8 = &.{},
creation_timestamp: []u8 = &.{},
phase: []u8 = &.{},
status_reason: []u8 = &.{},
node_name: []u8 = &.{},
pod_ip: []u8 = &.{},
service_account_name: []u8 = &.{},
owner_kind: []u8 = &.{},
owner_name: []u8 = &.{},
owner_uid: []u8 = &.{},
container_names: [][]u8 = &.{},
ready_count: u32 = 0,
container_count: u32 = 0,
restart_count: u64 = 0,
cpu_request_milli: u64 = 0,
mem_request_bytes: u64 = 0,

const PodRecord = @This();

pub fn fromPod(
    allocator: std.mem.Allocator,
    pod: klient.Pod,
    source: SourceMetadata,
) (Error || std.mem.Allocator.Error)!PodRecord {
    var record: PodRecord = .{
        .key = try resource_key.fromMetadata(allocator, pod.metadata, "default"),
    };
    errdefer record.deinit(allocator);

    record.resource_version = try cloneBytes(allocator, pod.metadata.resourceVersion);
    record.creation_timestamp = try cloneBytes(allocator, pod.metadata.creationTimestamp);

    if (pod.spec) |spec| {
        record.node_name = try cloneBytes(allocator, spec.nodeName);
        record.service_account_name = try cloneBytes(allocator, spec.serviceAccountName);
        if (spec.containers) |containers| {
            record.container_names = try allocator.alloc([]u8, containers.len);
            var initialized: usize = 0;
            errdefer {
                for (record.container_names[0..initialized]) |name| allocator.free(name);
                allocator.free(record.container_names);
                record.container_names = &.{};
            }
            for (containers) |container| {
                record.container_names[initialized] = try allocator.dupe(u8, container.name orelse "");
                initialized += 1;
                const requests = (container.resources orelse continue).requests orelse continue;
                if (requests != .object) continue;
                if (requests.object.get("cpu")) |cpu| {
                    if (cpu == .string) {
                        if (klient.MetricsClient.parseCpuMillicores(cpu.string)) |value| {
                            record.cpu_request_milli +|= value;
                        }
                    }
                }
                if (requests.object.get("memory")) |memory| {
                    if (memory == .string) {
                        if (klient.MetricsClient.parseMemoryBytes(memory.string)) |value| {
                            record.mem_request_bytes +|= value;
                        }
                    }
                }
            }
        }
    }

    if (pod.status) |status| {
        record.phase = try cloneBytes(allocator, status.phase);
        record.status_reason = try allocator.dupe(u8, displayReason(status));
        record.pod_ip = try cloneBytes(allocator, status.podIP);
        if (status.containerStatuses) |statuses| {
            record.container_count = @intCast(statuses.len);
            for (statuses) |container_status| {
                if (container_status.ready) record.ready_count += 1;
                if (container_status.restartCount > 0) {
                    record.restart_count +|= @intCast(container_status.restartCount);
                }
            }
        }
    }

    if (source.owner) |owner| {
        record.owner_kind = try allocator.dupe(u8, owner.kind);
        record.owner_name = try allocator.dupe(u8, owner.name);
        record.owner_uid = try allocator.dupe(u8, owner.uid);
    }
    return record;
}

fn displayReason(status: klient.types.PodStatus) []const u8 {
    if (status.containerStatuses) |statuses| {
        for (statuses) |container_status| {
            if (container_status.state) |state| {
                if (state.waiting) |waiting| {
                    if (waiting.reason) |reason| return reason;
                }
                if (state.terminated) |terminated| {
                    if (terminated.reason) |reason| return reason;
                }
            }
        }
    }
    return status.reason orelse status.phase orelse "Unknown";
}

fn cloneBytes(allocator: std.mem.Allocator, value: ?[]const u8) std.mem.Allocator.Error![]u8 {
    const bytes = value orelse return &.{};
    if (bytes.len == 0) return &.{};
    return allocator.dupe(u8, bytes);
}

pub fn clone(self: PodRecord, allocator: std.mem.Allocator) std.mem.Allocator.Error!PodRecord {
    var result: PodRecord = .{ .key = try self.key.clone(allocator) };
    errdefer result.deinit(allocator);

    result.resource_version = try cloneBytes(allocator, self.resource_version);
    result.creation_timestamp = try cloneBytes(allocator, self.creation_timestamp);
    result.phase = try cloneBytes(allocator, self.phase);
    result.status_reason = try cloneBytes(allocator, self.status_reason);
    result.node_name = try cloneBytes(allocator, self.node_name);
    result.pod_ip = try cloneBytes(allocator, self.pod_ip);
    result.service_account_name = try cloneBytes(allocator, self.service_account_name);
    result.owner_kind = try cloneBytes(allocator, self.owner_kind);
    result.owner_name = try cloneBytes(allocator, self.owner_name);
    result.owner_uid = try cloneBytes(allocator, self.owner_uid);
    result.ready_count = self.ready_count;
    result.container_count = self.container_count;
    result.restart_count = self.restart_count;
    result.cpu_request_milli = self.cpu_request_milli;
    result.mem_request_bytes = self.mem_request_bytes;

    if (self.container_names.len > 0) {
        result.container_names = try allocator.alloc([]u8, self.container_names.len);
        var initialized: usize = 0;
        errdefer {
            for (result.container_names[0..initialized]) |name| allocator.free(name);
            allocator.free(result.container_names);
            result.container_names = &.{};
        }
        for (self.container_names) |name| {
            result.container_names[initialized] = try allocator.dupe(u8, name);
            initialized += 1;
        }
    }
    return result;
}

pub fn ownedBytes(self: PodRecord) usize {
    var total = @sizeOf(PodRecord) +
        self.key.uid.len +
        self.key.namespace.len +
        self.key.name.len +
        self.key.labels.len +
        self.resource_version.len +
        self.creation_timestamp.len +
        self.phase.len +
        self.status_reason.len +
        self.node_name.len +
        self.pod_ip.len +
        self.service_account_name.len +
        self.owner_kind.len +
        self.owner_name.len +
        self.owner_uid.len +
        self.container_names.len * @sizeOf([]u8);
    for (self.container_names) |name| total +|= name.len;
    return total;
}

pub fn deinit(self: *PodRecord, allocator: std.mem.Allocator) void {
    self.key.deinit(allocator);
    freeBytes(allocator, self.resource_version);
    freeBytes(allocator, self.creation_timestamp);
    freeBytes(allocator, self.phase);
    freeBytes(allocator, self.status_reason);
    freeBytes(allocator, self.node_name);
    freeBytes(allocator, self.pod_ip);
    freeBytes(allocator, self.service_account_name);
    freeBytes(allocator, self.owner_kind);
    freeBytes(allocator, self.owner_name);
    freeBytes(allocator, self.owner_uid);
    for (self.container_names) |name| allocator.free(name);
    if (self.container_names.len > 0) allocator.free(self.container_names);
    self.* = undefined;
}

fn freeBytes(allocator: std.mem.Allocator, bytes: []u8) void {
    if (bytes.len > 0) allocator.free(bytes);
}

test "real pod without UID is rejected" {
    const pod: klient.Pod = .{ .metadata = .{ .name = "missing" } };
    try std.testing.expectError(error.MissingUid, fromPod(std.testing.allocator, pod, .{}));
}

test "record owns borrowed pod input and compact command metadata" {
    const allocator = std.testing.allocator;
    var uid = [_]u8{ 'u', 'i', 'd' };
    var name = [_]u8{ 'p', 'o', 'd' };
    var container_name = [_]u8{ 'a', 'p', 'p' };
    var containers = [_]klient.types.Container{.{ .name = &container_name }};
    var statuses = [_]klient.types.ContainerStatus{.{
        .name = "app",
        .ready = true,
        .restartCount = 2,
    }};
    const pod: klient.Pod = .{
        .apiVersion = "v1",
        .kind = "Pod",
        .metadata = .{
            .name = &name,
            .namespace = "ns",
            .uid = &uid,
            .resourceVersion = "42",
            .creationTimestamp = "2026-01-01T00:00:00Z",
        },
        .spec = .{
            .containers = containers[0..],
            .nodeName = "node-a",
            .serviceAccountName = "runner",
        },
        .status = .{
            .phase = "Running",
            .podIP = "10.0.0.1",
            .containerStatuses = statuses[0..],
        },
    };
    var record = try fromPod(allocator, pod, .{ .owner = .{
        .kind = "ReplicaSet",
        .name = "web-abc",
        .uid = "owner-1",
    } });
    defer record.deinit(allocator);

    uid[0] = 'x';
    name[0] = 'x';
    container_name[0] = 'x';
    try std.testing.expectEqualStrings("uid", record.key.uid);
    try std.testing.expectEqualStrings("pod", record.key.name);
    try std.testing.expectEqualStrings("app", record.container_names[0]);
    try std.testing.expectEqualStrings("ReplicaSet", record.owner_kind);
    try std.testing.expectEqual(@as(u64, 2), record.restart_count);
}

test "record retains bounded labels and summed resource requests" {
    const allocator = std.testing.allocator;
    const parsed = try std.json.parseFromSlice(
        klient.Pod,
        allocator,
        \\{"metadata":{"uid":"uid","namespace":"ns","name":"pod","labels":{"app":"web","env":"prod"}},"spec":{"containers":[{"name":"app","resources":{"requests":{"cpu":"250m","memory":"32Mi"}}},{"name":"sidecar","resources":{"requests":{"cpu":"1","memory":"1Gi"}}}]}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try fromPod(allocator, parsed.value, .{});
    defer record.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 1_250), record.cpu_request_milli);
    try std.testing.expectEqual(@as(u64, 1_056 * 1024 * 1024), record.mem_request_bytes);
    try std.testing.expect(std.mem.indexOf(u8, record.key.labels, "app=web") != null);
    try std.testing.expect(std.mem.indexOf(u8, record.key.labels, "env=prod") != null);
    try std.testing.expect(record.key.labels.len <= resource_key.max_projected_label_bytes);
}

fn labeledPodExercise(allocator: std.mem.Allocator, pod: klient.Pod) !void {
    var record = try fromPod(allocator, pod, .{});
    defer record.deinit(allocator);
    var copy = try record.clone(allocator);
    defer copy.deinit(allocator);
    try std.testing.expectEqualStrings("app=web,env=prod", copy.key.labels);
}

test "labeled pod decode and clone survive allocation failure at every step" {
    const parsed = try std.json.parseFromSlice(
        klient.Pod,
        std.testing.allocator,
        \\{"metadata":{"uid":"uid","namespace":"ns","name":"pod","labels":{"app":"web","env":"prod"}},"spec":{"containers":[{"name":"app"}]},"status":{"phase":"Running"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        labeledPodExercise,
        .{parsed.value},
    );
}

test "waiting status takes precedence over phase" {
    var statuses = [_]klient.types.ContainerStatus{.{
        .name = "app",
        .ready = false,
        .restartCount = 7,
        .state = .{ .waiting = .{ .reason = "CrashLoopBackOff" } },
    }};
    const pod: klient.Pod = .{
        .metadata = .{ .name = "pod", .uid = "u" },
        .status = .{ .phase = "Running", .containerStatuses = statuses[0..] },
    };
    var record = try fromPod(std.testing.allocator, pod, .{});
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("CrashLoopBackOff", record.status_reason);
}

fn allocationFailurePodRecord(allocator: std.mem.Allocator, pod: klient.Pod) !void {
    var record = try fromPod(allocator, pod, .{
        .owner = .{ .kind = "ReplicaSet", .name = "owner", .uid = "owner-uid" },
    });
    defer record.deinit(allocator);
    var copy = try record.clone(allocator);
    defer copy.deinit(allocator);
}

test "construction and clone unwind every allocation failure" {
    var containers = [_]klient.types.Container{
        .{ .name = "one" },
        .{ .name = "two" },
    };
    var statuses = [_]klient.types.ContainerStatus{.{
        .name = "one",
        .ready = true,
        .restartCount = 1,
    }};
    const pod: klient.Pod = .{
        .metadata = .{
            .name = "pod",
            .namespace = "ns",
            .uid = "uid",
            .resourceVersion = "10",
            .creationTimestamp = "2026-01-01T00:00:00Z",
        },
        .spec = .{
            .containers = containers[0..],
            .nodeName = "node",
            .serviceAccountName = "service-account",
        },
        .status = .{
            .phase = "Running",
            .podIP = "10.0.0.1",
            .containerStatuses = statuses[0..],
        },
    };
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        allocationFailurePodRecord,
        .{pod},
    );
}
