const std = @import("std");
pub const c3s = @import("c3s");

pub const family_names = [_][]const u8{
    "services",                      "endpoints",                         "endpointslices",            "configmaps",                      "secrets",
    "serviceaccounts",               "resourcequotas",                    "limitranges",               "deployments",                     "statefulsets",
    "daemonsets",                    "replicasets",                       "jobs",                      "cronjobs",                        "hpa",
    "poddisruptionbudgets",          "ingresses",                         "ingressclasses",            "networkpolicies",                 "ipaddresses",
    "servicecidrs",                  "persistentvolumes",                 "persistentvolumeclaims",    "storageclasses",                  "volumeattributesclasses",
    "csidrivers",                    "gatewayclasses",                    "gateways",                  "httproutes",                      "grpcroutes",
    "referencegrants",               "tcproutes",                         "tlsroutes",                 "udproutes",                       "backendtlspolicies",
    "listenersets",                  "roles",                             "rolebindings",              "clusterroles",                    "clusterrolebindings",
    "validatingadmissionpolicies",   "validatingadmissionpolicybindings", "mutatingadmissionpolicies", "mutatingadmissionpolicybindings", "validatingwebhookconfigurations",
    "mutatingwebhookconfigurations", "resourceclaims",                    "deviceclasses",             "priorityclasses",                 "runtimeclasses",
    "leases",                        "certificatesigningrequests",        "storageversionmigrations",  "events",
};

pub const ancillary_classes = [_][]const u8{
    "header_metrics", "traffic", "detail", "yaml", "logs", "authorization",
};

pub fn expectUnique(values: []const []const u8) !void {
    for (values, 0..) |value, i| {
        try std.testing.expect(value.len != 0);
        for (values[i + 1 ..]) |other| {
            try std.testing.expect(!std.mem.eql(u8, value, other));
        }
    }
}

pub fn exerciseFakeGet(path: []const u8, body: []const u8) !void {
    const fake_mod = c3s.k8s_fake_transport;
    const read_mod = c3s.k8s_read_transport;
    var fake = fake_mod.FakeTransport.init(std.testing.allocator, &.{.{ .body = body }});
    defer fake.deinit();
    const Capture = struct {
        fn receive(raw: *anyopaque, meta: read_mod.ResponseMeta, reader: *std.Io.Reader) anyerror!void {
            const count: *usize = @ptrCast(@alignCast(raw));
            try std.testing.expectEqual(std.http.Status.ok, meta.status);
            while (reader.takeByte()) |_| count.* += 1 else |err| {
                if (err != error.EndOfStream) return err;
            }
        }
    };
    var bytes: usize = 0;
    try fake.transport().get(try read_mod.ReadRequest.init(path), &bytes, Capture.receive);
    try std.testing.expectEqual(body.len, bytes);
    try std.testing.expectEqual(@as(usize, 1), fake.requests.items.len);
    try std.testing.expectEqualStrings(path, fake.requests.items[0].path);
}

pub fn expectGetOnlyTransport() !void {
    const VTable = c3s.k8s_read_transport.ReadTransport.VTable;
    const vtable_info = @typeInfo(VTable).@"struct";
    const field_count = if (comptime @hasField(@TypeOf(vtable_info), "fields"))
        vtable_info.fields.len
    else
        vtable_info.field_names.len;
    try std.testing.expectEqual(@as(usize, 1), field_count);
    try std.testing.expect(@hasField(VTable, "get"));
    inline for (.{ "post", "put", "patch", "delete", "write" }) |name| {
        try std.testing.expect(!@hasField(VTable, name));
    }
}
