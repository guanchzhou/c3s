const std = @import("std");

const keys = @import("ResourceKey.zig");
const lifecycle = @import("LifecycleInbox.zig");
const read_transport = @import("ReadTransport.zig");
const ResourceType = @import("../services/k8s_types.zig").ResourceType;
const secret_decode = @import("../viewmodel/secret_decode.zig");
const DetailView = @import("../view/DetailView.zig").DetailView;
const ViewManager = @import("../viewmodel/ViewManager.zig").ViewManager;

const max_response_bytes = 16 << 20;

pub const Kind = enum {
    describe,
    yaml,
    decoded_secret,
};

pub const DetailPayload = struct {
    generation: keys.Generation,
    subscription_id: keys.SubscriptionId,
    serial: u64,
    kind: Kind,
    resource_type: ResourceType,
    name: []u8,
    body: []u8,
    title: []u8,
};

pub const UiTarget = struct {
    view: *DetailView,
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
    transport_override: ?read_transport.ReadTransport = null,
};

const Spec = struct {
    serial: u64,
    kind: Kind,
    resource_type: ResourceType,
    name: []u8,
    namespace: []u8,
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

        const path = try objectPath(control.allocator, self.resource_type, self.name, self.namespace);
        defer control.allocator.free(path);
        const body = try fetchBody(control.allocator, transport, path);
        var body_owned = true;
        errdefer if (body_owned) control.allocator.free(body);
        const title = try titleFor(control.allocator, self.kind, self.resource_type, self.name);
        var title_owned = true;
        errdefer if (title_owned) control.allocator.free(title);
        const name = try control.allocator.dupe(u8, self.name);
        var name_owned = true;
        errdefer if (name_owned) control.allocator.free(name);
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
            .resource_type = self.resource_type,
            .name = name,
            .body = body,
            .title = title,
        };
        body_owned = false;
        title_owned = false;
        name_owned = false;
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
            @sizeOf(DetailPayload) + name.len + body.len + title.len,
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
        allocator.destroy(self);
    }
};

pub fn ownedTaskSpec(allocator: std.mem.Allocator, options: Options) !lifecycle.OwnedTaskSpec {
    const spec = try allocator.create(Spec);
    errdefer allocator.destroy(spec);
    spec.* = .{
        .serial = options.serial,
        .kind = options.kind,
        .resource_type = options.resource_type,
        .name = try allocator.dupe(u8, options.name),
        .namespace = undefined,
        .transport_override = options.transport_override,
    };
    errdefer allocator.free(spec.name);
    spec.namespace = try allocator.dupe(u8, options.namespace);
    return .{
        .ptr = spec,
        .alignment = .of(Spec),
        .owned_bytes = @sizeOf(Spec) + spec.name.len + spec.namespace.len,
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
        return std.fmt.allocPrint(
            allocator,
            "{s}/{s}/{s}",
            .{ resource_type.apiPath(), resource_type.resourceName(), name },
        );
    }
    if (!read_transport.validPathSegment(namespace)) return error.InvalidReadPath;
    return std.fmt.allocPrint(
        allocator,
        "{s}/namespaces/{s}/{s}/{s}",
        .{ resource_type.apiPath(), namespace, resource_type.resourceName(), name },
    );
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
    switch (payload.kind) {
        .describe => target.view.setContentDescribe(body, payload.title) catch return,
        .yaml => target.view.setContentJson(body, payload.title) catch return,
        .decoded_secret => target.view.setContentText(body, payload.title) catch return,
    }
    target.view_manager.pushView(target.view.createView()) catch return;
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
