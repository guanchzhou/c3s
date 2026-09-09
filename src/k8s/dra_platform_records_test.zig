const std = @import("std");
const klient = @import("klient");

fn freeColumns(columns: anytype) void {
    for (columns) |column| std.testing.allocator.free(column);
}

fn exerciseRealShapedDecode(
    comptime T: type,
    comptime constructor: anytype,
    comptime object_json: []const u8,
    comptime path: []const u8,
    comptime value_column: usize,
    comptime expected_value: []const u8,
    comptime verify: fn (*const T) anyerror!void,
) !void {
    const stream_list = @import("StreamList.zig");
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const ResponseScript = @import("FakeTransport.zig").ResponseScript;
    const read_transport = @import("ReadTransport.zig");
    const Capture = struct {
        fn receive(_: *@This(), items: []const T) !void {
            try std.testing.expectEqual(@as(usize, 1), items.len);
            try verify(&items[0]);
            var record = try constructor(std.testing.allocator, items[0]);
            defer record.deinit(std.testing.allocator);
            const columns = try record.columns(std.testing.allocator);
            defer freeColumns(columns);
            try std.testing.expectEqualStrings(expected_value, columns[value_column]);
        }
    };
    const Clock = struct {
        fn now(_: *anyopaque) u64 {
            return 0;
        }
    };
    const list_json = "{\"metadata\":{\"resourceVersion\":\"17\"},\"items\":[" ++ object_json ++ "]}";
    const scripts = [_]ResponseScript{.{ .body = list_json }};
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    var capture = Capture{};
    var clock_context: u8 = 0;
    var result = try stream_list.stream(
        T,
        std.testing.allocator,
        fake.transport(),
        try read_transport.ReadRequest.init(path),
        .{ .clock = .{ .ptr = &clock_context, .now_ns_fn = Clock.now } },
        &capture,
        Capture.receive,
    );
    defer result.deinit();
    try std.testing.expectEqualStrings("17", result.resource_version);

    const watch_json = "{\"type\":\"MODIFIED\",\"object\":" ++ object_json ++ "}";
    var parsed_watch = try std.json.parseFromSlice(
        klient.Watcher(T).WatchEnvelope,
        std.testing.allocator,
        watch_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed_watch.deinit();
    const object = &parsed_watch.value.object.?;
    try verify(object);
    var record = try constructor(std.testing.allocator, object.*);
    defer record.deinit(std.testing.allocator);
    const columns = try record.columns(std.testing.allocator);
    defer freeColumns(columns);
    try std.testing.expectEqualStrings(expected_value, columns[value_column]);
}

const resource_claim_json =
    \\{"apiVersion":"resource.k8s.io/v1","kind":"ResourceClaim","metadata":{"uid":"claim-1","namespace":"team","name":"gpu"},"spec":{"devices":{"requests":[]}},"status":{"allocation":{"devices":{"results":[]}}}}
;
const device_class_json =
    \\{"apiVersion":"resource.k8s.io/v1","kind":"DeviceClass","metadata":{"uid":"dc-1","name":"gpu"},"spec":{"selectors":[{"cel":{"expression":"device.driver == 'gpu.example.com'"}},{"cel":{"expression":"true"}}]}}
;
const priority_class_json =
    \\{"apiVersion":"scheduling.k8s.io/v1","kind":"PriorityClass","metadata":{"uid":"pc-1","name":"critical"},"value":1000,"globalDefault":true}
;
const runtime_class_json =
    \\{"apiVersion":"node.k8s.io/v1","kind":"RuntimeClass","metadata":{"uid":"rc-1","name":"sandboxed"},"handler":"runsc"}
;
const lease_json =
    \\{"apiVersion":"coordination.k8s.io/v1","kind":"Lease","metadata":{"uid":"lease-1","namespace":"kube-system","name":"leader"},"spec":{"holderIdentity":"controller-a"}}
;
const csr_json =
    \\{"apiVersion":"certificates.k8s.io/v1","kind":"CertificateSigningRequest","metadata":{"uid":"csr-1","name":"node"},"spec":{"request":"YQ==","signerName":"kubernetes.io/kubelet-serving"},"status":{"certificate":"Y2VydA=="}}
;
const svm_json =
    \\{"apiVersion":"storagemigration.k8s.io/v1","kind":"StorageVersionMigration","metadata":{"uid":"svm-1","name":"pods"},"spec":{"resource":{"group":"","version":"v1","resource":"pods"}},"status":{"resourceVersion":"42"}}
;
const event_series_json =
    \\{"apiVersion":"v1","kind":"Event","metadata":{"uid":"event-1","namespace":"team","name":"event-generated","creationTimestamp":"2024-01-01T00:00:00Z"},"involvedObject":{"kind":"Pod","name":"api-1"},"type":"Warning","reason":"BackOff","message":"restarting","eventTime":"2024-01-01T00:00:01Z","series":{"count":9,"lastObservedTime":"2024-01-01T00:05:00Z"}}
;
const event_deprecated_json =
    \\{"apiVersion":"v1","kind":"Event","metadata":{"uid":"event-2","namespace":"team","name":"legacy-event"},"involvedObject":{"kind":"Pod","name":"api-2"},"type":"Normal","reason":"Pulled","message":"ready","count":3,"lastTimestamp":"2024-01-01T00:03:00Z"}
;

fn verifyResourceClaim(value: *const klient.ResourceClaim) !void {
    const status = value.status orelse return error.MissingStatus;
    try std.testing.expect(status == .object);
    try std.testing.expect(status.object.get("allocation") != null);
}
fn verifyDeviceClass(value: *const klient.DeviceClass) !void {
    const spec = value.spec orelse return error.MissingSpec;
    try std.testing.expectEqual(@as(usize, 2), (spec.selectors orelse return error.MissingSelectors).len);
}
fn verifyPriorityClass(value: *const klient.PriorityClass) !void {
    try std.testing.expectEqual(@as(i32, 1000), value.value);
    try std.testing.expectEqual(true, value.globalDefault.?);
}
fn verifyRuntimeClass(value: *const klient.RuntimeClass) !void {
    try std.testing.expectEqualStrings("runsc", value.handler);
}
fn verifyLease(value: *const klient.Lease) !void {
    try std.testing.expectEqualStrings("controller-a", (value.spec orelse return error.MissingSpec).holderIdentity.?);
}
fn verifyCSR(value: *const klient.CertificateSigningRequest) !void {
    try std.testing.expectEqualStrings("kubernetes.io/kubelet-serving", (value.spec orelse return error.MissingSpec).signerName);
    const status = value.status orelse return error.MissingStatus;
    try std.testing.expect(status.object.get("certificate") != null);
}
fn verifySVM(value: *const klient.StorageVersionMigration) !void {
    const status = value.status orelse return error.MissingStatus;
    try std.testing.expectEqualStrings("42", status.object.get("resourceVersion").?.string);
}
fn verifySeriesEvent(value: *const klient.Event) !void {
    try std.testing.expect(value.involvedObject != null);
    try std.testing.expectEqualStrings("BackOff", value.reason.?);
    try std.testing.expectEqualStrings("Warning", value.type.?);
    try std.testing.expectEqualStrings("restarting", value.message.?);
    try std.testing.expect(value.count == null);
    try std.testing.expect(value.lastTimestamp == null);
    const series = value.series orelse return error.MissingTopLevelSeries;
    try std.testing.expectEqual(@as(i32, 9), series.count.?);
    try std.testing.expectEqualStrings("2024-01-01T00:05:00Z", series.lastObservedTime.?);
}
fn verifyDeprecatedEvent(value: *const klient.Event) !void {
    try std.testing.expect(value.series == null);
    try std.testing.expectEqual(@as(i32, 3), value.count.?);
    try std.testing.expectEqualStrings("2024-01-01T00:03:00Z", value.lastTimestamp.?);
}

test "real-shaped DRA LIST and WATCH decode spec and status fields" {
    try exerciseRealShapedDecode(klient.ResourceClaim, @import("ResourceClaimRecord.zig").fromResourceClaim, resource_claim_json, "/apis/resource.k8s.io/v1/namespaces/team/resourceclaims", 2, "bound", verifyResourceClaim);
    try exerciseRealShapedDecode(klient.DeviceClass, @import("DeviceClassRecord.zig").fromDeviceClass, device_class_json, "/apis/resource.k8s.io/v1/deviceclasses", 1, "2", verifyDeviceClass);
}

test "real-shaped platform LIST and WATCH preserve flat and spec wire placement" {
    try exerciseRealShapedDecode(klient.PriorityClass, @import("PriorityClassRecord.zig").fromPriorityClass, priority_class_json, "/apis/scheduling.k8s.io/v1/priorityclasses", 1, "1000", verifyPriorityClass);
    try exerciseRealShapedDecode(klient.RuntimeClass, @import("RuntimeClassRecord.zig").fromRuntimeClass, runtime_class_json, "/apis/node.k8s.io/v1/runtimeclasses", 1, "runsc", verifyRuntimeClass);
    try exerciseRealShapedDecode(klient.Lease, @import("LeaseRecord.zig").fromLease, lease_json, "/apis/coordination.k8s.io/v1/namespaces/kube-system/leases", 2, "controller-a", verifyLease);
    try exerciseRealShapedDecode(klient.CertificateSigningRequest, @import("CSRRecord.zig").fromCSR, csr_json, "/apis/certificates.k8s.io/v1/certificatesigningrequests", 2, "Issued", verifyCSR);
    try exerciseRealShapedDecode(klient.StorageVersionMigration, @import("StorageVersionMigrationRecord.zig").fromStorageVersionMigration, svm_json, "/apis/storagemigration.k8s.io/v1/storageversionmigrations", 1, "42", verifySVM);
}

test "series-only Event LIST and WATCH prefer top-level series count and last observed time" {
    try exerciseRealShapedDecode(klient.Event, @import("EventRecord.zig").fromEvent, event_series_json, "/api/v1/namespaces/team/events", 5, "9", verifySeriesEvent);
}

test "deprecated Event LIST and WATCH retain count and last timestamp fallback" {
    try exerciseRealShapedDecode(klient.Event, @import("EventRecord.zig").fromEvent, event_deprecated_json, "/api/v1/namespaces/team/events", 5, "3", verifyDeprecatedEvent);
}

test "Lease missing spec projects none" {
    var parsed = try std.json.parseFromSlice(
        klient.Lease,
        std.testing.allocator,
        \\{"metadata":{"uid":"lease-empty","namespace":"team","name":"unheld"}}
    ,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed.deinit();
    var record = try @import("LeaseRecord.zig").fromLease(std.testing.allocator, parsed.value);
    defer record.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("<none>", record.holder);
}
