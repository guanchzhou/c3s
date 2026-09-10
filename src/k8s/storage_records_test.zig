const std = @import("std");
const klient = @import("klient");

pub const pv_object_json =
    \\{"apiVersion":"v1","kind":"PersistentVolume","metadata":{"uid":"pv-1","name":"data"},"spec":{"capacity":{"storage":"10Gi"},"accessModes":["ReadWriteOnce","ReadOnlyMany"],"persistentVolumeReclaimPolicy":"Retain","claimRef":{"namespace":"team","name":"cache"},"storageClassName":"fast"},"status":{"phase":"Bound"}}
;
pub const pvc_object_json =
    \\{"apiVersion":"v1","kind":"PersistentVolumeClaim","metadata":{"uid":"pvc-1","namespace":"team","name":"cache"},"spec":{"volumeName":"pv-1","accessModes":["ReadWriteMany"],"storageClassName":"fast"},"status":{"phase":"Bound","capacity":{"storage":"20Gi"}}}
;
pub const storage_class_object_json =
    \\{"apiVersion":"storage.k8s.io/v1","kind":"StorageClass","metadata":{"uid":"sc-1","name":"fast"},"provisioner":"csi.example","reclaimPolicy":"Retain","volumeBindingMode":"WaitForFirstConsumer","allowVolumeExpansion":true}
;
pub const volume_attributes_class_object_json =
    \\{"apiVersion":"storage.k8s.io/v1","kind":"VolumeAttributesClass","metadata":{"uid":"vac-1","name":"gold"},"driverName":"csi.example"}
;
pub const csi_driver_object_json =
    \\{"apiVersion":"storage.k8s.io/v1","kind":"CSIDriver","metadata":{"uid":"csi-1","name":"csi.example"},"spec":{"attachRequired":false,"podInfoOnMount":true}}
;

fn exerciseRealShapedDecode(
    comptime T: type,
    comptime Record: type,
    comptime fromObject: fn (std.mem.Allocator, T) anyerror!Record,
    object_json: []const u8,
    list_json: []const u8,
    watch_json: []const u8,
    path: []const u8,
    expected: []const []const u8,
) !void {
    const stream_list = @import("StreamList.zig");
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const ResponseScript = @import("FakeTransport.zig").ResponseScript;
    const read_transport = @import("ReadTransport.zig");
    const Capture = struct {
        expected: []const []const u8,

        fn receive(self: *@This(), items: []const T) !void {
            try std.testing.expectEqual(@as(usize, 1), items.len);
            var record = try fromObject(std.testing.allocator, items[0]);
            defer record.deinit(std.testing.allocator);
            const columns = try record.columns(std.testing.allocator);
            defer for (columns) |column| std.testing.allocator.free(column);
            for (columns, self.expected) |actual, wanted|
                try std.testing.expectEqualStrings(wanted, actual);
        }
    };
    const Clock = struct {
        fn now(_: *anyopaque) u64 {
            return 0;
        }
    };
    const scripts = [_]ResponseScript{.{ .body = list_json }};
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    var capture = Capture{ .expected = expected };
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

    const Envelope = klient.Watcher(T).WatchEnvelope;
    var parsed_watch = try std.json.parseFromSlice(
        Envelope,
        std.testing.allocator,
        watch_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed_watch.deinit();
    var watch_record = try fromObject(std.testing.allocator, parsed_watch.value.object.?);
    defer watch_record.deinit(std.testing.allocator);
    const watch_columns = try watch_record.columns(std.testing.allocator);
    defer for (watch_columns) |column| std.testing.allocator.free(column);
    for (watch_columns, expected) |actual, wanted|
        try std.testing.expectEqualStrings(wanted, actual);

    var parsed_object = try std.json.parseFromSlice(
        T,
        std.testing.allocator,
        object_json,
        .{ .ignore_unknown_fields = true },
    );
    defer parsed_object.deinit();
    var direct_record = try fromObject(std.testing.allocator, parsed_object.value);
    direct_record.deinit(std.testing.allocator);
}

test "real-shaped persistent volume LIST and WATCH decode projected columns" {
    const Record = @import("PVRecord.zig");
    try exerciseRealShapedDecode(
        klient.PersistentVolume,
        Record,
        Record.fromPersistentVolume,
        pv_object_json,
        \\{"apiVersion":"v1","kind":"PersistentVolumeList","metadata":{"resourceVersion":"17"},"items":[
    ++ pv_object_json ++ "]}",
        "{\"type\":\"MODIFIED\",\"object\":" ++ pv_object_json ++ "}",
        "/api/v1/persistentvolumes",
        &.{ "data", "10Gi", "RWO,ROX", "Retain", "Bound", "team/cache", "fast", "n/a" },
    );
}

test "real-shaped persistent volume claim LIST and WATCH decode projected columns" {
    const Record = @import("PVCRecord.zig");
    try exerciseRealShapedDecode(
        klient.PersistentVolumeClaim,
        Record,
        Record.fromPersistentVolumeClaim,
        pvc_object_json,
        \\{"apiVersion":"v1","kind":"PersistentVolumeClaimList","metadata":{"resourceVersion":"17"},"items":[
    ++ pvc_object_json ++ "]}",
        "{\"type\":\"MODIFIED\",\"object\":" ++ pvc_object_json ++ "}",
        "/api/v1/persistentvolumeclaims",
        &.{ "team", "cache", "Bound", "pv-1", "20Gi", "RWX", "fast", "n/a" },
    );
}

test "real-shaped storage class LIST and WATCH decode projected columns" {
    const Record = @import("StorageClassRecord.zig");
    try exerciseRealShapedDecode(
        klient.StorageClass,
        Record,
        Record.fromStorageClass,
        storage_class_object_json,
        \\{"apiVersion":"storage.k8s.io/v1","kind":"StorageClassList","metadata":{"resourceVersion":"17"},"items":[
    ++ storage_class_object_json ++ "]}",
        "{\"type\":\"MODIFIED\",\"object\":" ++ storage_class_object_json ++ "}",
        "/apis/storage.k8s.io/v1/storageclasses",
        &.{ "fast", "csi.example", "Retain", "WaitForFirstConsumer", "true", "n/a" },
    );
}

test "real-shaped volume attributes class LIST and WATCH decode projected columns" {
    const Record = @import("VolumeAttributesClassRecord.zig");
    try exerciseRealShapedDecode(
        klient.VolumeAttributesClass,
        Record,
        Record.fromVolumeAttributesClass,
        volume_attributes_class_object_json,
        \\{"apiVersion":"storage.k8s.io/v1","kind":"VolumeAttributesClassList","metadata":{"resourceVersion":"17"},"items":[
    ++ volume_attributes_class_object_json ++ "]}",
        "{\"type\":\"MODIFIED\",\"object\":" ++ volume_attributes_class_object_json ++ "}",
        "/apis/storage.k8s.io/v1/volumeattributesclasses",
        &.{ "gold", "csi.example", "n/a" },
    );
}

test "real-shaped CSI driver LIST and WATCH decode projected columns" {
    const Record = @import("CSIDriverRecord.zig");
    try exerciseRealShapedDecode(
        klient.CSIDriver,
        Record,
        Record.fromCSIDriver,
        csi_driver_object_json,
        \\{"apiVersion":"storage.k8s.io/v1","kind":"CSIDriverList","metadata":{"resourceVersion":"17"},"items":[
    ++ csi_driver_object_json ++ "]}",
        "{\"type\":\"MODIFIED\",\"object\":" ++ csi_driver_object_json ++ "}",
        "/apis/storage.k8s.io/v1/csidrivers",
        &.{ "csi.example", "false", "true", "n/a" },
    );
}

test {
    _ = @import("PVRecord.zig");
    _ = @import("PVCRecord.zig");
    _ = @import("StorageClassRecord.zig");
    _ = @import("VolumeAttributesClassRecord.zig");
    _ = @import("CSIDriverRecord.zig");
}
