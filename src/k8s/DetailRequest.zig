const std = @import("std");

const keys = @import("ResourceKey.zig");
const lifecycle = @import("LifecycleInbox.zig");
const read_transport = @import("ReadTransport.zig");
const ResourceType = @import("../services/k8s_types.zig").ResourceType;
const secret_decode = @import("../viewmodel/secret_decode.zig");
const health_report = @import("../viewmodel/health_report.zig");
const argo_sync_report = @import("../viewmodel/argo_sync_report.zig");
const DetailView = @import("../view/DetailView.zig").DetailView;
const ExplainView = @import("../view/ExplainView.zig").ExplainView;
const ArgoSyncView = @import("../view/ArgoSyncView.zig").ArgoSyncView;
const ViewManager = @import("../viewmodel/ViewManager.zig").ViewManager;

const max_response_bytes = 16 << 20;

pub const Kind = enum {
    describe,
    yaml,
    decoded_secret,
    explain,
    argo_sync,
};

pub const DetailPayload = struct {
    generation: keys.Generation,
    subscription_id: keys.SubscriptionId,
    serial: u64,
    kind: Kind,
    resource_type: ResourceType,
    name: []u8,
    namespace: []u8,
    body: []u8,
    title: []u8,
};

pub const UiTarget = struct {
    view: *DetailView,
    explain_view: *ExplainView,
    argo_sync_view: *ArgoSyncView,
    view_manager: *ViewManager,
    active_key: keys.RequestKey,
    active_serial: u64,
    dirty: *bool,
};

pub const Options = struct {
    serial: u64,
    kind: Kind,
    resource_type: ResourceType,
    name: []const u8,
    namespace: []const u8,
    path_override: ?[]const u8 = null,
    transport_override: ?read_transport.ReadTransport = null,
};

const Spec = struct {
    serial: u64,
    kind: Kind,
    resource_type: ResourceType,
    name: []u8,
    namespace: []u8,
    path_override: ?[]u8,
    transport_override: ?read_transport.ReadTransport,
    generation: keys.Generation = 0,
    subscription_id: keys.SubscriptionId = 0,

    fn bind(raw: ?*anyopaque, generation: keys.Generation, subscription_id: keys.SubscriptionId) void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        self.generation = generation;
        self.subscription_id = subscription_id;
    }

    fn run(raw: ?*anyopaque, control: *lifecycle.ChildControl, io: std.Io) anyerror!void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        var adapter: read_transport.TransportAdapter = undefined;
        const transport = if (self.transport_override) |override|
            override
        else blk: {
            var lease = &(control.lease orelse return error.MissingLease);
            adapter = try lease.readTransport(io, &control.cancel_requested);
            break :blk adapter.transport();
        };

        const path = if (self.path_override) |override|
            try control.allocator.dupe(u8, override)
        else
            try objectPath(control.allocator, self.resource_type, self.name, self.namespace);
        defer control.allocator.free(path);
        const object_body = try fetchBody(control.allocator, transport, path);
        var object_body_owned = true;
        errdefer if (object_body_owned) control.allocator.free(object_body);
        var body = object_body;
        var payload_resource_type = self.resource_type;
        var payload_name_source: []const u8 = self.name;
        var implicated_pod: ?[]u8 = null;
        defer if (implicated_pod) |name| control.allocator.free(name);
        if (self.kind == .explain) {
            const events_path = try eventsPath(control.allocator, self.namespace, object_body);
            defer if (events_path) |value| control.allocator.free(value);
            const events_owned: ?[]u8 = if (events_path) |value|
                fetchBody(control.allocator, transport, value) catch blk: {
                    if (control.cancel_requested.load(.acquire)) return error.Canceled;
                    break :blk null;
                }
            else
                null;
            defer if (events_owned) |value| control.allocator.free(value);
            const events: []const u8 = events_owned orelse "";
            const pods_path = try relatedPodsPath(control.allocator, self.namespace, object_body);
            defer if (pods_path) |value| control.allocator.free(value);
            const pods_owned: ?[]u8 = if (pods_path) |value|
                fetchBody(control.allocator, transport, value) catch blk: {
                    if (control.cancel_requested.load(.acquire)) return error.Canceled;
                    break :blk null;
                }
            else
                null;
            defer if (pods_owned) |value| control.allocator.free(value);
            const pods: []const u8 = pods_owned orelse "";
            var report = try health_report.buildWithPodsStatus(
                control.allocator,
                object_body,
                events,
                pods,
                .{
                    .events = events_path == null or events_owned != null,
                    .related_pods = pods_path == null or pods_owned != null,
                },
            );
            body = report.text;
            implicated_pod = report.implicated_pod;
            report.implicated_pod = null;
            if (implicated_pod) |name| {
                payload_resource_type = .pods;
                payload_name_source = name;
            }
            control.allocator.free(object_body);
            object_body_owned = false;
        } else if (self.kind == .argo_sync) {
            body = try argo_sync_report.build(control.allocator, object_body);
            control.allocator.free(object_body);
            object_body_owned = false;
        }
        var body_owned = true;
        errdefer if (body_owned) control.allocator.free(body);
        if (body.ptr == object_body.ptr) object_body_owned = false;
        const title = try titleFor(control.allocator, self.kind, self.resource_type, self.name);
        var title_owned = true;
        errdefer if (title_owned) control.allocator.free(title);
        const name = try control.allocator.dupe(u8, payload_name_source);
        var name_owned = true;
        errdefer if (name_owned) control.allocator.free(name);
        const namespace = try control.allocator.dupe(u8, self.namespace);
        var namespace_owned = true;
        errdefer if (namespace_owned) control.allocator.free(namespace);
        const payload = try control.allocator.create(DetailPayload);
        var payload_owned = true;
        errdefer if (payload_owned) {
            payloadDeinit(payload, control.allocator);
            control.allocator.destroy(payload);
        };
        payload.* = .{
            .generation = self.generation,
            .subscription_id = self.subscription_id,
            .serial = self.serial,
            .kind = self.kind,
            .resource_type = payload_resource_type,
            .name = name,
            .namespace = namespace,
            .body = body,
            .title = title,
        };
        body_owned = false;
        title_owned = false;
        name_owned = false;
        namespace_owned = false;
        var envelope = try keys.erasePayload(
            DetailPayload,
            control.allocator,
            targetFor(self.kind, .{
                .generation = self.generation,
                .subscription_id = self.subscription_id,
            }),
            payload,
            &payload_handler,
            self.generation,
            self.subscription_id,
            self.serial,
            @sizeOf(DetailPayload) + name.len + namespace.len + body.len + title.len,
            null,
        );
        payload_owned = false;
        const outcome = try control.publishDelivery(envelope);
        if (outcome == .abandoned) return;
        envelope = undefined;
        control.finish(.{ .request_finished = .{
            .key = .{
                .generation = self.generation,
                .subscription_id = self.subscription_id,
            },
        } });
    }

    fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
        const self: *Spec = @ptrCast(@alignCast(raw orelse return));
        allocator.free(self.name);
        allocator.free(self.namespace);
        if (self.path_override) |value| allocator.free(value);
        allocator.destroy(self);
    }
};

pub fn ownedTaskSpec(allocator: std.mem.Allocator, options: Options) !lifecycle.OwnedTaskSpec {
    const spec = try allocator.create(Spec);
    errdefer allocator.destroy(spec);
    const name = try allocator.dupe(u8, options.name);
    errdefer allocator.free(name);
    const path_override = if (options.path_override) |value|
        try allocator.dupe(u8, value)
    else
        null;
    errdefer if (path_override) |value| allocator.free(value);
    const namespace = try allocator.dupe(u8, options.namespace);
    errdefer allocator.free(namespace);
    spec.* = .{
        .serial = options.serial,
        .kind = options.kind,
        .resource_type = options.resource_type,
        .name = name,
        .namespace = namespace,
        .path_override = path_override,
        .transport_override = options.transport_override,
    };
    return .{
        .ptr = spec,
        .alignment = .of(Spec),
        .owned_bytes = @sizeOf(Spec) + spec.name.len + spec.namespace.len +
            if (spec.path_override) |value| value.len else 0,
        .lease_purpose = if (options.kind == .yaml) .yaml else .detail,
        .bindFn = Spec.bind,
        .runFn = Spec.run,
        .deinitFn = Spec.deinit,
    };
}

pub fn objectPath(
    allocator: std.mem.Allocator,
    resource_type: ResourceType,
    name: []const u8,
    namespace: []const u8,
) ![]u8 {
    if (!read_transport.validPathSegment(name)) return error.InvalidReadPath;
    if (resource_type.isClusterScoped()) {
        return try std.fmt.allocPrint(
            allocator,
            "{s}/{s}/{s}",
            .{ resource_type.apiPath(), resource_type.resourceName(), name },
        );
    }
    if (!read_transport.validPathSegment(namespace)) return error.InvalidReadPath;
    return try std.fmt.allocPrint(
        allocator,
        "{s}/namespaces/{s}/{s}/{s}",
        .{ resource_type.apiPath(), namespace, resource_type.resourceName(), name },
    );
}

fn eventsPath(
    allocator: std.mem.Allocator,
    namespace: []const u8,
    object_json: []const u8,
) !?[]u8 {
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, object_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    const metadata = parsed.value.object.get("metadata") orelse return null;
    if (metadata != .object) return null;
    const uid = metadata.object.get("uid") orelse return null;
    if (uid != .string or !read_transport.validQueryValue(uid.string)) return null;
    if (namespace.len > 0 and !std.mem.eql(u8, namespace, "cluster")) {
        if (!read_transport.validPathSegment(namespace)) return null;
        const path = try std.fmt.allocPrint(
            allocator,
            "/api/v1/namespaces/{s}/events?fieldSelector=involvedObject.uid%3D{s}",
            .{ namespace, uid.string },
        );
        return path;
    }
    const path = try std.fmt.allocPrint(
        allocator,
        "/api/v1/events?fieldSelector=involvedObject.uid%3D{s}",
        .{uid.string},
    );
    return path;
}

fn relatedPodsPath(
    allocator: std.mem.Allocator,
    namespace: []const u8,
    object_json: []const u8,
) !?[]u8 {
    if (!read_transport.validPathSegment(namespace)) return null;
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, object_json, .{}) catch return null;
    defer parsed.deinit();
    if (parsed.value != .object) return null;
    if (std.mem.eql(u8, stringAt(parsed.value.object, "kind") orelse "", "Pod")) return null;
    const spec = objectAt(parsed.value.object, "spec") orelse return null;
    const selector = objectAt(spec, "selector") orelse return null;

    var raw: std.ArrayListUnmanaged(u8) = .empty;
    defer raw.deinit(allocator);
    if (objectAt(selector, "matchLabels")) |labels| {
        var iterator = labels.iterator();
        while (iterator.next()) |entry| {
            if (entry.value_ptr.* != .string) continue;
            if (raw.items.len > 0) try raw.append(allocator, ',');
            try raw.appendSlice(allocator, entry.key_ptr.*);
            try raw.append(allocator, '=');
            try raw.appendSlice(allocator, entry.value_ptr.string);
        }
    }
    if (selector.get("matchExpressions")) |expressions| {
        if (expressions == .array) {
            for (expressions.array.items) |expression| {
                if (expression != .object) continue;
                const key = stringAt(expression.object, "key") orelse continue;
                const operator = stringAt(expression.object, "operator") orelse continue;
                if (raw.items.len > 0) try raw.append(allocator, ',');
                if (std.mem.eql(u8, operator, "DoesNotExist")) try raw.append(allocator, '!');
                try raw.appendSlice(allocator, key);
                if (std.mem.eql(u8, operator, "Exists") or std.mem.eql(u8, operator, "DoesNotExist"))
                    continue;
                if (!std.mem.eql(u8, operator, "In") and !std.mem.eql(u8, operator, "NotIn")) return null;
                try raw.appendSlice(allocator, if (std.mem.eql(u8, operator, "In")) " in (" else " notin (");
                const values = expression.object.get("values") orelse return null;
                if (values != .array or values.array.items.len == 0) return null;
                for (values.array.items, 0..) |value, index| {
                    if (value != .string) return null;
                    if (index > 0) try raw.append(allocator, ',');
                    try raw.appendSlice(allocator, value.string);
                }
                try raw.append(allocator, ')');
            }
        }
    }
    if (raw.items.len == 0) return null;
    var query: std.ArrayListUnmanaged(u8) = .empty;
    defer query.deinit(allocator);
    try appendPercentEncoded(allocator, &query, raw.items);
    return try std.fmt.allocPrint(
        allocator,
        "/api/v1/namespaces/{s}/pods?labelSelector={s}",
        .{ namespace, query.items },
    );
}

fn appendPercentEncoded(
    allocator: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(u8),
    value: []const u8,
) !void {
    const hex = "0123456789ABCDEF";
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '-' or byte == '_' or byte == '.' or byte == '~') {
            try out.append(allocator, byte);
        } else {
            try out.appendSlice(allocator, &.{ '%', hex[byte >> 4], hex[byte & 0x0f] });
        }
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

fn fetchBody(
    allocator: std.mem.Allocator,
    transport: read_transport.ReadTransport,
    path: []const u8,
) ![]u8 {
    const Capture = struct {
        allocator: std.mem.Allocator,
        body: ?[]u8 = null,

        fn receive(
            raw: *anyopaque,
            meta: read_transport.ResponseMeta,
            reader: *std.Io.Reader,
        ) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (meta.status.class() != .success) return error.HttpStatus;
            var body: std.ArrayList(u8) = .empty;
            defer body.deinit(self.allocator);
            try reader.appendRemaining(self.allocator, &body, .limited(max_response_bytes));
            self.body = try body.toOwnedSlice(self.allocator);
        }
    };
    var capture = Capture{ .allocator = allocator };
    errdefer if (capture.body) |body| allocator.free(body);
    try transport.get(try read_transport.ReadRequest.init(path), &capture, Capture.receive);
    return capture.body orelse error.MissingResponse;
}

fn titleFor(
    allocator: std.mem.Allocator,
    kind: Kind,
    resource_type: ResourceType,
    name: []const u8,
) ![]u8 {
    return switch (kind) {
        .describe => std.fmt.allocPrint(
            allocator,
            "Describe {s}/{s}",
            .{ resource_type.resourceName(), name },
        ),
        .yaml => std.fmt.allocPrint(
            allocator,
            "YAML {s}/{s}",
            .{ resource_type.resourceName(), name },
        ),
        .decoded_secret => std.fmt.allocPrint(allocator, "Decoded secret/{s}", .{name}),
        .explain => std.fmt.allocPrint(
            allocator,
            "Explain unhealthy {s}/{s}",
            .{ resource_type.resourceName(), name },
        ),
        .argo_sync => std.fmt.allocPrint(allocator, "Sync details application/{s}", .{name}),
    };
}

fn targetFor(kind: Kind, key: keys.RequestKey) keys.EnvelopeTarget {
    return if (kind == .yaml) .{ .yaml = key } else .{ .detail = key };
}

const Prepared = struct {
    body: ?[]u8 = null,
};

fn payloadPreflight(
    payload: *DetailPayload,
    router: *keys.UiRouter,
    allocator: std.mem.Allocator,
) anyerror!keys.ApplyPlan {
    const key = keys.RequestKey{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    };
    const target_raw = router.target(targetFor(payload.kind, key)) orelse
        return error.StaleDetailTarget;
    const target: *UiTarget = @ptrCast(@alignCast(target_raw));
    if (!target.active_key.eql(key) or target.active_serial != payload.serial)
        return error.StaleDetailTarget;
    try target.view_manager.view_ptrs.ensureUnusedCapacity(allocator, 1);
    try target.view_manager.view_vtables.ensureUnusedCapacity(allocator, 1);

    const prepared = try allocator.create(Prepared);
    errdefer allocator.destroy(prepared);
    prepared.* = .{};
    prepared.body = switch (payload.kind) {
        .decoded_secret => try secret_decode.decodeSecretData(allocator, payload.body),
        .describe, .yaml => if (payload.resource_type == .secrets)
            try secret_decode.redactSecretJson(allocator, payload.body)
        else
            null,
        .explain => null,
        .argo_sync => null,
    };
    return .{
        .scratch = prepared,
        .scratch_alignment = .of(Prepared),
        .deinitFn = preparedDeinit,
    };
}

fn payloadCommit(
    payload: *DetailPayload,
    router: *keys.UiRouter,
    plan: *keys.ApplyPlan,
) void {
    const key = keys.RequestKey{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    };
    const target_raw = router.target(targetFor(payload.kind, key)) orelse return;
    const target: *UiTarget = @ptrCast(@alignCast(target_raw));
    if (!target.active_key.eql(key) or target.active_serial != payload.serial) return;
    const prepared: *Prepared = @ptrCast(@alignCast(plan.scratch.?));
    const body = prepared.body orelse payload.body;
    const view = switch (payload.kind) {
        .describe => blk: {
            target.view.setContentDescribe(body, payload.title) catch return;
            break :blk target.view.createView();
        },
        .yaml => blk: {
            target.view.setContentJson(body, payload.title) catch return;
            break :blk target.view.createView();
        },
        .decoded_secret => blk: {
            target.view.setContentText(body, payload.title) catch return;
            break :blk target.view.createView();
        },
        .explain => blk: {
            target.explain_view.setExplainContent(
                body,
                payload.title,
                payload.name,
                payload.namespace,
                payload.resource_type.resourceName(),
            ) catch return;
            break :blk target.explain_view.createView();
        },
        .argo_sync => blk: {
            target.argo_sync_view.setArgoSyncContent(body, payload.title) catch return;
            break :blk target.argo_sync_view.createView();
        },
    };
    target.view_manager.pushView(view) catch return;
    target.dirty.* = true;
}

fn preparedDeinit(
    raw: ?*anyopaque,
    _: std.mem.Alignment,
    allocator: std.mem.Allocator,
) void {
    const prepared: *Prepared = @ptrCast(@alignCast(raw orelse return));
    if (prepared.body) |body| allocator.free(body);
    allocator.destroy(prepared);
}

fn payloadDeinit(payload: *DetailPayload, allocator: std.mem.Allocator) void {
    allocator.free(payload.name);
    allocator.free(payload.namespace);
    allocator.free(payload.body);
    allocator.free(payload.title);
}

pub const payload_handler = keys.PayloadHandler(DetailPayload){
    .preflight = payloadPreflight,
    .commit = payloadCommit,
    .deinit = payloadDeinit,
};

test "object paths are GET-safe for namespaced and cluster resources" {
    inline for (.{ ResourceType.pods, ResourceType.nodes }) |resource_type| {
        const path = try objectPath(std.testing.allocator, resource_type, "item-a", "team-a");
        defer std.testing.allocator.free(path);
        _ = try read_transport.ReadRequest.init(path);
    }
}

test "related pod path uses encoded workload matchLabels" {
    const object =
        \\{"kind":"Deployment","spec":{"selector":{"matchLabels":{"app.kubernetes.io/name":"web api","tier":"frontend"}}}}
    ;
    const path = (try relatedPodsPath(std.testing.allocator, "team-a", object)).?;
    defer std.testing.allocator.free(path);
    _ = try read_transport.ReadRequest.init(path);
    try std.testing.expect(std.mem.startsWith(u8, path, "/api/v1/namespaces/team-a/pods?labelSelector="));
    try std.testing.expect(std.mem.indexOf(u8, path, "app.kubernetes.io%2Fname%3Dweb%20api") != null);
    try std.testing.expect(std.mem.indexOf(u8, path, "tier%3Dfrontend") != null);
}

test "related pod path supports expression-only selectors" {
    const object =
        \\{"kind":"DaemonSet","spec":{"selector":{"matchExpressions":[{"key":"tier","operator":"In","values":["frontend","edge"]},{"key":"debug","operator":"DoesNotExist"}]}}}
    ;
    const path = (try relatedPodsPath(std.testing.allocator, "team-a", object)).?;
    defer std.testing.allocator.free(path);
    try std.testing.expect(std.mem.indexOf(u8, path, "tier%20in%20%28frontend%2Cedge%29") != null);
    try std.testing.expect(std.mem.indexOf(u8, path, "%21debug") != null);
}

test "events path rejects query delimiters in object uid" {
    const object =
        \\{"metadata":{"uid":"abc&fieldSelector=everything"}}
    ;
    try std.testing.expect((try eventsPath(std.testing.allocator, "default", object)) == null);
}

test "Argo sync details consume Application status through read transport" {
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const application =
        \\{"metadata":{"name":"web"},"status":{"sync":{"status":"OutOfSync"},"health":{"status":"Degraded"}}}
    ;
    var fake = FakeTransport.init(std.testing.allocator, &.{.{ .body = application }});
    defer fake.deinit();

    const path = "/apis/argoproj.io/v1alpha1/namespaces/argocd/applications/web";
    const body = try fetchBody(std.testing.allocator, fake.transport(), path);
    defer std.testing.allocator.free(body);
    const report = try argo_sync_report.build(std.testing.allocator, body);
    defer std.testing.allocator.free(report);

    try std.testing.expectEqual(@as(usize, 1), fake.requests.items.len);
    try std.testing.expectEqualStrings(path, fake.requests.items[0].path);
    try std.testing.expect(std.mem.indexOf(u8, report, "Sync: OutOfSync") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "Health: Degraded") != null);
}

test "detail preflight redacts normal Secret and decodes only explicit reveal" {
    const secret =
        \\{"kind":"Secret","data":{"password":"aHVudGVyMg=="}}
    ;
    const key = keys.RequestKey{ .generation = 2, .subscription_id = 4 };
    const theme_loader = @import("../model/theme_loader.zig");
    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    var view = try DetailView.init(std.testing.allocator, &theme);
    defer view.deinit();
    var manager = try ViewManager.init(std.testing.allocator);
    defer manager.deinit();
    var dirty = false;
    var target = UiTarget{
        .view = &view,
        .explain_view = &view,
        .argo_sync_view = &view,
        .view_manager = &manager,
        .active_key = key,
        .active_serial = 8,
        .dirty = &dirty,
    };
    const Route = struct {
        fn route(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            if (keys.requestKey(target_value) == null) return null;
            return raw;
        }
    };
    var router = keys.UiRouter{ .context = &target, .targetFn = Route.route };

    inline for (.{ Kind.yaml, Kind.decoded_secret }) |kind| {
        const payload = try std.testing.allocator.create(DetailPayload);
        payload.* = .{
            .generation = key.generation,
            .subscription_id = key.subscription_id,
            .serial = 8,
            .kind = kind,
            .resource_type = .secrets,
            .name = try std.testing.allocator.dupe(u8, "credentials"),
            .namespace = try std.testing.allocator.dupe(u8, "default"),
            .body = try std.testing.allocator.dupe(u8, secret),
            .title = try std.testing.allocator.dupe(u8, "secret"),
        };
        var envelope = try keys.erasePayload(
            DetailPayload,
            std.testing.allocator,
            targetFor(kind, key),
            payload,
            &payload_handler,
            key.generation,
            key.subscription_id,
            8,
            @sizeOf(DetailPayload),
            null,
        );
        try envelope.apply(&router, std.testing.allocator);
        var found_secret = false;
        for (view.lines.items) |line| {
            if (std.mem.indexOf(u8, line, "hunter2") != null) found_secret = true;
        }
        try std.testing.expectEqual(kind == .decoded_secret, found_secret);
        _ = manager.popView();
    }
}

pub fn runTask14DetailIdentityGate() !void {
    const theme_loader = @import("../model/theme_loader.zig");
    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    var view = try DetailView.init(std.testing.allocator, &theme);
    defer view.deinit();
    try view.setContentText("existing", "existing");
    var manager = try ViewManager.init(std.testing.allocator);
    defer manager.deinit();
    var dirty = false;
    const current_key = keys.RequestKey{ .generation = 5, .subscription_id = 2 };
    var target = UiTarget{
        .view = &view,
        .explain_view = &view,
        .argo_sync_view = &view,
        .view_manager = &manager,
        .active_key = current_key,
        .active_serial = 2,
        .dirty = &dirty,
    };
    const Route = struct {
        fn route(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *UiTarget = @ptrCast(@alignCast(raw));
            const key = keys.requestKey(target_value) orelse return null;
            if (!key.eql(self.active_key)) return null;
            return raw;
        }
    };
    var router = keys.UiRouter{ .context = &target, .targetFn = Route.route };

    const malformed = try std.testing.allocator.create(DetailPayload);
    malformed.* = .{
        .generation = current_key.generation,
        .subscription_id = current_key.subscription_id,
        .serial = 2,
        .kind = .decoded_secret,
        .resource_type = .secrets,
        .name = try std.testing.allocator.dupe(u8, "broken"),
        .namespace = try std.testing.allocator.dupe(u8, "default"),
        .body = try std.testing.allocator.dupe(u8, "<html>not a Secret</html>"),
        .title = try std.testing.allocator.dupe(u8, "broken"),
    };
    var malformed_envelope = try keys.erasePayload(
        DetailPayload,
        std.testing.allocator,
        .{ .detail = current_key },
        malformed,
        &payload_handler,
        current_key.generation,
        current_key.subscription_id,
        2,
        @sizeOf(DetailPayload),
        null,
    );
    try std.testing.expectError(
        secret_decode.Error.NotAnObject,
        malformed_envelope.apply(&router, std.testing.allocator),
    );
    malformed_envelope.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("existing", view.lines.items[0]);

    const stale_key = keys.RequestKey{ .generation = 5, .subscription_id = 1 };
    const stale = try std.testing.allocator.create(DetailPayload);
    stale.* = .{
        .generation = stale_key.generation,
        .subscription_id = stale_key.subscription_id,
        .serial = 1,
        .kind = .yaml,
        .resource_type = .pods,
        .name = try std.testing.allocator.dupe(u8, "old"),
        .namespace = try std.testing.allocator.dupe(u8, "default"),
        .body = try std.testing.allocator.dupe(u8, "{\"name\":\"old\"}"),
        .title = try std.testing.allocator.dupe(u8, "old"),
    };
    var stale_envelope = try keys.erasePayload(
        DetailPayload,
        std.testing.allocator,
        .{ .yaml = stale_key },
        stale,
        &payload_handler,
        stale_key.generation,
        stale_key.subscription_id,
        1,
        @sizeOf(DetailPayload),
        null,
    );
    try stale_envelope.apply(&router, std.testing.allocator);
    try std.testing.expectEqualStrings("existing", view.lines.items[0]);
}

test "newer detail serial wins and malformed Secret preserves existing content" {
    try runTask14DetailIdentityGate();
}
