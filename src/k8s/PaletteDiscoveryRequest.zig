const std = @import("std");
const keys = @import("ResourceKey.zig");
const lifecycle = @import("LifecycleInbox.zig");
const dynamic_resource = @import("DynamicResource.zig");
const K8sService = @import("../services/K8sService.zig").K8sService;
const max_access_checks = 256;

pub const Payload = struct {
    generation: keys.Generation,
    subscription_id: keys.SubscriptionId,
    names: [][]u8,
};

pub const UiTarget = struct {
    ptr: *anyopaque,
    applyFn: *const fn (*anyopaque, [][]u8) void,
};

const Spec = struct {
    service: *K8sService,
    namespace: []u8,
    generation: keys.Generation = 0,
    subscription_id: keys.SubscriptionId = 0,

    fn bind(raw: ?*anyopaque, generation: keys.Generation, subscription_id: keys.SubscriptionId) void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        self.generation = generation;
        self.subscription_id = subscription_id;
    }

    fn run(raw: ?*anyopaque, control: *lifecycle.ChildControl, _: std.Io) anyerror!void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        if (control.cancel_requested.load(.acquire)) return error.Canceled;
        const catalog = try self.service.listApiResourcesCancelable(&control.cancel_requested);
        defer self.service.allocator.free(catalog);
        if (control.cancel_requested.load(.acquire)) return error.Canceled;
        const resources = try dynamic_resource.collectCompletionResources(control.allocator, catalog);
        defer {
            for (resources) |*resource| resource.deinit(control.allocator);
            control.allocator.free(resources);
        }

        var decisions: std.StringHashMapUnmanaged(bool) = .empty;
        defer {
            var iterator = decisions.keyIterator();
            while (iterator.next()) |key| control.allocator.free(key.*);
            decisions.deinit(control.allocator);
        }
        var names: std.ArrayListUnmanaged([]u8) = .empty;
        errdefer {
            for (names.items) |name| control.allocator.free(name);
            names.deinit(control.allocator);
        }
        var access_checks: usize = 0;
        for (resources) |resource| {
            if (control.cancel_requested.load(.acquire)) return error.Canceled;
            const decision_key = try std.fmt.allocPrint(control.allocator, "{s}/{s}", .{
                resource.group,
                resource.resource,
            });
            var keep_key = false;
            defer if (!keep_key) control.allocator.free(decision_key);
            const allowed = decisions.get(decision_key) orelse blk: {
                if (access_checks >= max_access_checks) break :blk false;
                access_checks += 1;
                const namespace = if (resource.namespaced) self.namespace else "";
                const value = self.service.canListResourceCancelable(
                    resource.group,
                    resource.resource,
                    namespace,
                    &control.cancel_requested,
                ) catch |err| {
                    if (err == error.Canceled or control.cancel_requested.load(.acquire))
                        return error.Canceled;
                    break :blk false;
                };
                try decisions.put(control.allocator, decision_key, value);
                keep_key = true;
                break :blk value;
            };
            if (!allowed) continue;
            try names.append(control.allocator, try control.allocator.dupe(u8, resource.name));
        }

        var owned_bytes: usize = @sizeOf(Payload) + names.items.len * @sizeOf([]u8);
        for (names.items) |name| owned_bytes +|= name.len;
        const payload = try control.allocator.create(Payload);
        var payload_owned = true;
        errdefer if (payload_owned) {
            payloadDeinit(payload, control.allocator);
            control.allocator.destroy(payload);
        };
        payload.* = .{
            .generation = self.generation,
            .subscription_id = self.subscription_id,
            .names = &.{},
        };
        payload.names = try names.toOwnedSlice(control.allocator);
        var envelope = try keys.erasePayload(
            Payload,
            control.allocator,
            .{ .palette_discovery = .{
                .generation = self.generation,
                .subscription_id = self.subscription_id,
            } },
            payload,
            &payload_handler,
            self.generation,
            self.subscription_id,
            0,
            owned_bytes,
            null,
        );
        payload_owned = false;
        const outcome = try control.publishDelivery(envelope);
        if (outcome == .abandoned) return;
        envelope = undefined;
        control.finish(.{ .request_finished = .{ .key = .{
            .generation = self.generation,
            .subscription_id = self.subscription_id,
        } } });
    }

    fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
        const self: *Spec = @ptrCast(@alignCast(raw orelse return));
        allocator.free(self.namespace);
        allocator.destroy(self);
    }
};

pub fn ownedTaskSpec(
    allocator: std.mem.Allocator,
    service: *K8sService,
    namespace: []const u8,
) !lifecycle.OwnedTaskSpec {
    const spec = try allocator.create(Spec);
    errdefer allocator.destroy(spec);
    spec.* = .{
        .service = service,
        .namespace = try allocator.dupe(u8, namespace),
    };
    return .{
        .ptr = spec,
        .alignment = .of(Spec),
        .owned_bytes = @sizeOf(Spec) + spec.namespace.len,
        .lease_purpose = .palette_discovery,
        .bindFn = Spec.bind,
        .runFn = Spec.run,
        .deinitFn = Spec.deinit,
    };
}

fn preflight(_: *Payload, _: *keys.UiRouter, _: std.mem.Allocator) !keys.ApplyPlan {
    return .{};
}

fn commit(payload: *Payload, router: *keys.UiRouter, _: *keys.ApplyPlan) void {
    const key = keys.RequestKey{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    };
    const raw = router.target(.{ .palette_discovery = key }) orelse return;
    const target: *UiTarget = @ptrCast(@alignCast(raw));
    target.applyFn(target.ptr, payload.names);
    payload.names = &.{};
}

fn payloadDeinit(payload: *Payload, allocator: std.mem.Allocator) void {
    for (payload.names) |name| allocator.free(name);
    if (payload.names.len > 0) allocator.free(payload.names);
}

pub const payload_handler = keys.PayloadHandler(Payload){
    .preflight = preflight,
    .commit = commit,
    .deinit = payloadDeinit,
};
