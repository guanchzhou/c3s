const std = @import("std");
const klient = @import("klient");
const clock = @import("../core/clock.zig");
const PerfTelemetry = @import("../core/perf_telemetry.zig").PerfTelemetry;
const perf = @import("../core/perf_telemetry.zig");
const lifecycle = @import("LifecycleInbox.zig");
const list_watch = @import("ListWatch.zig");
const stream_list = @import("StreamList.zig");
const read_transport = @import("ReadTransport.zig");
const keys = @import("ResourceKey.zig");
const PodRecord = @import("PodRecord.zig");
const PodProjection = @import("ResourceProjection.zig").ResourceProjection(PodRecord);

pub const Options = struct {
    namespace: ?[]const u8,
    context_name: []const u8,
    projection: *PodProjection,
    telemetry: *PerfTelemetry,
    deinit_counter: ?*std.atomic.Value(usize) = null,
    source_override: ?list_watch.Source(PodRecord) = null,
};

const Spec = struct {
    namespace: ?[]u8,
    context_name: []u8,
    projection: *PodProjection,
    telemetry: *PerfTelemetry,
    generation: keys.Generation = 0,
    subscription_id: keys.SubscriptionId = 0,
    deinit_counter: ?*std.atomic.Value(usize),
    source_override: ?list_watch.Source(PodRecord),

    fn bind(raw: ?*anyopaque, generation: keys.Generation, subscription_id: keys.SubscriptionId) void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        self.generation = generation;
        self.subscription_id = subscription_id;
    }

    fn run(raw: ?*anyopaque, control: *lifecycle.ChildControl, io: std.Io) anyerror!void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        var lease = &(control.lease orelse return error.MissingLease);
        const client = try lease.client();
        var sink_state = SinkState{
            .allocator = control.allocator,
            .control = control,
            .projection = self.projection,
            .telemetry = self.telemetry,
            .context_name = self.context_name,
            .scope = self.namespace orelse "all_namespaces",
        };
        self.telemetry.emit(event(
            .sync_start,
            self.context_name,
            self.namespace orelse "all_namespaces",
            self.generation,
            self.subscription_id,
            0,
            0,
            0,
        ));

        if (self.source_override) |source| {
            try self.runDriver(
                control,
                source,
                &sink_state,
                .{ .context = self, .wait_fn = noRetryWait },
            );
            return;
        }

        const descriptor = read_transport.ResourceDescriptor.forType(klient.Pod);
        const list_path = try descriptor.listPath(control.allocator, self.namespace);
        defer control.allocator.free(list_path);
        var transport_adapter = read_transport.KlientTransport{ .client = client, .io = io };
        var source_state = SourceState{
            .allocator = control.allocator,
            .io = io,
            .client = client,
            .transport = transport_adapter.transport(),
            .list_path = list_path,
            .namespace = self.namespace,
        };
        try self.runDriver(
            control,
            source_state.source(),
            &sink_state,
            .{ .context = &source_state, .wait_fn = SourceState.wait },
        );
    }

    fn runDriver(
        self: *Spec,
        control: *lifecycle.ChildControl,
        source: list_watch.Source(PodRecord),
        sink_state: *SinkState,
        retry_hooks: list_watch.RetryHooks,
    ) !void {
        var driver = list_watch.Driver(PodRecord){
            .allocator = control.allocator,
            .source = source,
            .sink = sink_state.sink(),
            .retry_hooks = retry_hooks,
            // The supervisor cancels the std.Io Future that owns this driver.
            // Watcher.streamGet and retry sleeps use this same Io instance, so
            // Future cancellation interrupts the outstanding operation and
            // unwinds the task; the token remains for Driver's between-call API.
            .cancel = list_watch.CancelToken.never(),
            .generation = self.generation,
            .subscription_id = self.subscription_id,
        };
        defer driver.deinit();
        _ = try driver.run();
    }

    fn noRetryWait(_: *anyopaque, _: u64, _: list_watch.CancelToken) anyerror!bool {
        return false;
    }

    fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
        const self: *Spec = @ptrCast(@alignCast(raw orelse return));
        if (self.namespace) |namespace| allocator.free(namespace);
        allocator.free(self.context_name);
        if (self.deinit_counter) |counter| _ = counter.fetchAdd(1, .acq_rel);
        allocator.destroy(self);
    }
};

pub fn ownedTaskSpec(allocator: std.mem.Allocator, options: Options) !lifecycle.OwnedTaskSpec {
    const spec = try allocator.create(Spec);
    errdefer allocator.destroy(spec);
    const namespace = if (options.namespace) |value| try allocator.dupe(u8, value) else null;
    errdefer if (namespace) |value| allocator.free(value);
    const context_name = try allocator.dupe(u8, options.context_name);
    spec.* = .{
        .namespace = namespace,
        .context_name = context_name,
        .projection = options.projection,
        .telemetry = options.telemetry,
        .deinit_counter = options.deinit_counter,
        .source_override = options.source_override,
    };
    return .{
        .ptr = spec,
        .alignment = .of(Spec),
        .owned_bytes = @sizeOf(Spec) + context_name.len + if (namespace) |value| value.len else 0,
        .bindFn = Spec.bind,
        .runFn = Spec.run,
        .deinitFn = Spec.deinit,
    };
}

const SourceState = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    client: *klient.K8sClient,
    transport: read_transport.ReadTransport,
    list_path: []const u8,
    namespace: ?[]const u8,

    fn source(self: *SourceState) list_watch.Source(PodRecord) {
        return .{ .context = self, .list_fn = list, .watch_fn = watch };
    }

    fn list(
        raw: *anyopaque,
        _: list_watch.CancelToken,
        receiver_context: *anyopaque,
        receiver: *const fn (*anyopaque, PodRecord) anyerror!void,
        chunk_end: *const fn (*anyopaque) anyerror!void,
    ) anyerror!list_watch.ListOutcome {
        const self: *SourceState = @ptrCast(@alignCast(raw));
        const Batch = struct {
            source: *SourceState,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, PodRecord) anyerror!void,
            chunk_end: *const fn (*anyopaque) anyerror!void,

            fn receive(ctx: *@This(), pods: []const klient.Pod) anyerror!void {
                for (pods) |pod| {
                    const record = try PodRecord.fromPod(ctx.source.allocator, pod, .{});
                    try ctx.receiver(ctx.receiver_context, record);
                }
                try ctx.chunk_end(ctx.receiver_context);
            }
        };
        var batch = Batch{
            .source = self,
            .receiver_context = receiver_context,
            .receiver = receiver,
            .chunk_end = chunk_end,
        };
        var result = stream_list.stream(
            klient.Pod,
            self.allocator,
            self.transport,
            try read_transport.ReadRequest.init(self.list_path),
            .{ .clock = .{ .ptr = self, .now_ns_fn = nowNs } },
            &batch,
            Batch.receive,
        ) catch |err| return .{ .failure = classifyListError(err) };
        defer result.deinit();
        return .{ .complete = try keys.OwnedBytes.clone(self.allocator, result.resource_version) };
    }

    fn watch(
        raw: *anyopaque,
        resource_version: []const u8,
        _: list_watch.CancelToken,
        receiver_context: *anyopaque,
        receiver: *const fn (*anyopaque, *list_watch.WatchEvent(PodRecord)) anyerror!void,
    ) anyerror!list_watch.Failure {
        const self: *SourceState = @ptrCast(@alignCast(raw));
        var watcher = klient.Watcher(klient.Pod).init(
            self.client,
            "/api/v1",
            "pods",
            self.namespace,
            .{ .resource_version = resource_version, .allow_watch_bookmarks = true },
        );
        defer watcher.deinit();
        const Callback = struct {
            source: *SourceState,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, *list_watch.WatchEvent(PodRecord)) anyerror!void,

            fn receive(ctx: *@This(), event_value: *klient.watch.WatchEvent(klient.Pod)) anyerror!void {
                defer event_value.deinit();
                var watch_event: list_watch.WatchEvent(PodRecord) = switch (event_value.type_) {
                    .ADDED => .{ .added = try PodRecord.fromPod(ctx.source.allocator, event_value.object, .{}) },
                    .MODIFIED => .{ .modified = try PodRecord.fromPod(ctx.source.allocator, event_value.object, .{}) },
                    .DELETED => blk: {
                        var record = try PodRecord.fromPod(ctx.source.allocator, event_value.object, .{});
                        defer record.deinit(ctx.source.allocator);
                        break :blk .{ .deleted = try record.key.clone(ctx.source.allocator) };
                    },
                    .ERROR, .BOOKMARK => return,
                };
                defer watch_event.deinit(ctx.source.allocator);
                try ctx.receiver(ctx.receiver_context, &watch_event);
            }
        };
        var callback = Callback{
            .source = self,
            .receiver_context = receiver_context,
            .receiver = receiver,
        };
        const outcome = watcher.watchWithContextOutcome(*Callback, &callback, Callback.receive) catch |err| {
            if (classifyWatchObjectError(err)) |failure| return failure;
            return err;
        };
        if (watcher.resource_version) |version| {
            if (!std.mem.eql(u8, version, resource_version)) {
                var bookmark: list_watch.WatchEvent(PodRecord) = .{
                    .bookmark = try keys.OwnedBytes.clone(self.allocator, version),
                };
                defer bookmark.deinit(self.allocator);
                try receiver(receiver_context, &bookmark);
            }
        }
        return list_watch.failureFromKlient(outcome) orelse .transport;
    }

    fn wait(raw: *anyopaque, delay_ns: u64, _: list_watch.CancelToken) anyerror!bool {
        const self: *SourceState = @ptrCast(@alignCast(raw));
        try self.io.sleep(.{ .nanoseconds = delay_ns }, .awake);
        return true;
    }

    fn nowNs(_: *anyopaque) u64 {
        return @intCast(@max(clock.nanoTimestamp(), 0));
    }
};

const SinkState = struct {
    allocator: std.mem.Allocator,
    control: *lifecycle.ChildControl,
    projection: *PodProjection,
    telemetry: *PerfTelemetry,
    context_name: []const u8,
    scope: []const u8,
    first_batch_queued: bool = false,

    fn sink(self: *SinkState) list_watch.BatchSink(PodRecord) {
        return .{ .context = self, .emit_fn = emit };
    }

    fn emit(raw: *anyopaque, batch: *keys.TypedBatch(PodRecord)) anyerror!void {
        const self: *SinkState = @ptrCast(@alignCast(raw));
        const heap_batch = try self.allocator.create(keys.TypedBatch(PodRecord));
        heap_batch.* = batch.*;
        batch.* = undefined;
        const envelope = keys.eraseBatch(
            PodRecord,
            self.allocator,
            heap_batch,
            PodProjection.handler(),
            @ptrCast(self.projection),
        ) catch |err| {
            heap_batch.deinit(self.allocator);
            self.allocator.destroy(heap_batch);
            return err;
        };
        const is_first_real = !self.first_batch_queued and envelope.change_count > 0;
        const delivery = try self.control.publishDelivery(envelope);
        if (is_first_real and delivery == .accepted) {
            self.first_batch_queued = true;
            self.telemetry.emit(event(
                .first_batch_queued,
                self.context_name,
                self.scope,
                envelope.generation,
                envelope.subscription_id,
                envelope.revision,
                0,
                envelope.owned_bytes,
            ));
        }
    }
};

fn classifyListError(err: anyerror) list_watch.Failure {
    return switch (err) {
        error.Canceled => .canceled,
        error.OutOfMemory => .transport,
        error.HttpStatus => .server,
        error.MalformedOuterJson,
        error.ItemsNotArray,
        error.MalformedItem,
        error.MissingItems,
        error.MissingResourceVersion,
        error.ObjectTooLarge,
        error.ResponseTooLarge,
        error.MissingUid,
        => .{ .malformed = detail(err) },
        else => .transport,
    };
}

fn classifyWatchObjectError(err: anyerror) ?list_watch.Failure {
    return switch (err) {
        error.MissingUid, error.MalformedWatchEvent => .{ .malformed = detail(err) },
        else => null,
    };
}

fn detail(err: anyerror) keys.ErrorDetail {
    const name = @errorName(err);
    var result: keys.ErrorDetail = .{ .code = .decode };
    result.len = @intCast(@min(name.len, result.bytes.len));
    @memcpy(result.bytes[0..result.len], name[0..result.len]);
    return result;
}

fn event(
    kind: perf.EventKind,
    context_name: []const u8,
    scope: []const u8,
    generation: keys.Generation,
    subscription_id: keys.SubscriptionId,
    revision: keys.Revision,
    object_count: usize,
    queue_bytes: usize,
) perf.Event {
    return .{
        .kind = kind,
        .monotonic_ns = @intCast(@max(clock.nanoTimestamp(), 0)),
        .context = context_name,
        .resource = "pods",
        .scope = scope,
        .generation = generation,
        .subscription_id = subscription_id,
        .applied_revision = revision,
        .object_count = object_count,
        .queue_bytes = queue_bytes,
    };
}

test "owned pod task binds subscription identity and owns scope strings" {
    const allocator = std.testing.allocator;
    var projection: PodProjection = undefined;
    var telemetry: PerfTelemetry = undefined;
    var task = try ownedTaskSpec(allocator, .{
        .namespace = "team-a",
        .context_name = "dev",
        .projection = &projection,
        .telemetry = &telemetry,
    });
    defer task.deinit(allocator);

    task.bindFn(task.ptr, 41, 9);
    const spec: *Spec = @ptrCast(@alignCast(task.ptr.?));
    try std.testing.expectEqual(@as(keys.Generation, 41), spec.generation);
    try std.testing.expectEqual(@as(keys.SubscriptionId, 9), spec.subscription_id);
    try std.testing.expectEqualStrings("team-a", spec.namespace.?);
    try std.testing.expectEqualStrings("dev", spec.context_name);
}

test "owned pod task allocation failure unwinds" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{
        .fail_index = 1,
    });
    var projection: PodProjection = undefined;
    var telemetry: PerfTelemetry = undefined;
    try std.testing.expectError(error.OutOfMemory, ownedTaskSpec(failing.allocator(), .{
        .namespace = "team-a",
        .context_name = "dev",
        .projection = &projection,
        .telemetry = &telemetry,
    }));
}

test "UID-less LIST and WATCH objects share malformed failure policy" {
    const list_failure = classifyListError(error.MissingUid);
    const watch_failure = classifyWatchObjectError(error.MissingUid) orelse
        return error.MissingWatchClassification;
    try std.testing.expect(list_failure == .malformed);
    try std.testing.expect(watch_failure == .malformed);
    try std.testing.expectEqual(
        list_failure.malformed.code,
        watch_failure.malformed.code,
    );
}

test "DataPlane failure destroys a real pod task exactly once" {
    const runtime = @import("../core/runtime.zig");
    const DataPlane = @import("DataPlane.zig").DataPlane;
    const ChangeQueue = @import("ChangeQueue.zig").ChangeQueue;
    const io = runtime.io();
    var shared_event: std.Io.Event = .unset;
    var inbox = lifecycle.LifecycleInbox.init(io, &shared_event);
    defer inbox.deinit(std.testing.allocator);
    inbox.markRootTerminated();
    var cancellations = lifecycle.CancellationIntents.init();
    const producer = lifecycle.LifecycleProducer.init(
        &inbox,
        &cancellations,
        std.testing.allocator,
    );
    var queue = ChangeQueue.init(
        io,
        std.testing.allocator,
        keys.Limits.default,
        &shared_event,
        null,
    );
    defer queue.deinit();
    var plane = DataPlane.init(std.testing.allocator, producer, &queue);
    var projection: PodProjection = undefined;
    var telemetry: PerfTelemetry = undefined;
    var destroyed: std.atomic.Value(usize) = .init(0);
    var task = try ownedTaskSpec(std.testing.allocator, .{
        .namespace = "team-a",
        .context_name = "dev",
        .projection = &projection,
        .telemetry = &telemetry,
        .deinit_counter = &destroyed,
    });
    defer task.deinit(std.testing.allocator);

    try std.testing.expectError(error.Closed, plane.startSubscription(1, &task));
    try std.testing.expect(task.ptr == null);
    try std.testing.expectEqual(@as(usize, 1), destroyed.load(.acquire));
}

test "production pod task reaches exact projection and table through supervisor queue" {
    const runtime = @import("../core/runtime.zig");
    const DataPlane = @import("DataPlane.zig").DataPlane;
    const ChangeQueue = @import("ChangeQueue.zig").ChangeQueue;
    const Supervisor = @import("LifecycleSupervisor.zig").LifecycleSupervisor;
    const active_context = @import("ActiveContextSession.zig");
    const ActiveSessionSlot = @import("ActiveSessionSlot.zig").ActiveSessionSlot;
    const resource_configs = @import("../view/resource_configs.zig");
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const allocator = std.testing.allocator;
    const io = runtime.io();

    const ProjectionFns = struct {
        fn match(record: *const PodRecord, filter: []const u8) bool {
            return filter.len == 0 or std.mem.indexOf(u8, record.key.name, filter) != null;
        }
        fn sort(record: *const PodRecord, _: u8) []const u8 {
            return record.key.name;
        }
    };
    const Script = struct {
        allocator: std.mem.Allocator,

        fn source(self: *@This()) list_watch.Source(PodRecord) {
            return .{ .context = self, .list_fn = list, .watch_fn = watch };
        }

        fn list(
            raw: *anyopaque,
            _: list_watch.CancelToken,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, PodRecord) anyerror!void,
            chunk_end: *const fn (*anyopaque) anyerror!void,
        ) anyerror!list_watch.ListOutcome {
            const self: *@This() = @ptrCast(@alignCast(raw));
            var record = PodRecord{
                .key = try (keys.ObjectKey{
                    .uid = "uid-1",
                    .namespace = "default",
                    .name = "streamed-pod",
                }).clone(self.allocator),
                .phase = try self.allocator.dupe(u8, "Running"),
                .ready_count = 1,
                .container_count = 1,
            };
            var record_owned = true;
            errdefer if (record_owned) record.deinit(self.allocator);
            try receiver(receiver_context, record);
            record_owned = false;
            try chunk_end(receiver_context);
            return .{ .complete = try keys.OwnedBytes.clone(self.allocator, "10") };
        }

        fn watch(
            _: *anyopaque,
            _: []const u8,
            _: list_watch.CancelToken,
            _: *anyopaque,
            _: *const fn (*anyopaque, *list_watch.WatchEvent(PodRecord)) anyerror!void,
        ) anyerror!list_watch.Failure {
            return .canceled;
        }
    };
    const Route = struct {
        plane: *DataPlane,
        projection: *PodProjection,
        active: lifecycle.SubscriptionKey,
        completed: bool = false,

        fn target(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return switch (target_value) {
                .resource => self.plane.resourceTarget(
                    target_value,
                    self.active,
                    @ptrCast(self.projection),
                ),
                .lifecycle => @ptrCast(self.plane),
                else => null,
            };
        }

        fn lifecycleObserved(
            raw: *anyopaque,
            payload: *anyopaque,
            identity: ?keys.ResourceIdentity,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const completion: *lifecycle.LifecycleCompletion = @ptrCast(@alignCast(payload));
            const exact = identity orelse return;
            if (exact.generation != self.active.generation or
                exact.subscription_id != self.active.subscription_id)
                return;
            if (completion.* == .subscription_stopped) self.completed = true;
        }
    };

    var shared_event: std.Io.Event = .unset;
    var inbox = lifecycle.LifecycleInbox.init(io, &shared_event);
    defer inbox.deinit(allocator);
    var cancellations = lifecycle.CancellationIntents.init();
    var slot = ActiveSessionSlot.init(io, &shared_event);
    defer slot.deinit();
    var queue = ChangeQueue.init(io, allocator, keys.Limits.default, &shared_event, null);
    defer queue.deinit();
    const client = try allocator.create(klient.K8sClient);
    var client_owned = true;
    errdefer if (client_owned) allocator.destroy(client);
    client.* = try klient.K8sClient.init(allocator, io, .{
        .server = "http://127.0.0.1",
        .namespace = "default",
    });
    errdefer if (client_owned) client.deinit();
    const session = try active_context.ActiveContextSession.adopt(
        allocator,
        io,
        1,
        .{
            .context_name = "test",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
        .{
            .shared_event = &shared_event,
            .client = client,
            .cluster_name = "cluster",
            .user_name = "user",
            .readiness_verified = true,
        },
    );
    client_owned = false;
    _ = try slot.commit(session);
    var supervisor = try Supervisor.init(
        allocator,
        io,
        &shared_event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        active_context.SessionFactory.production(),
        session,
    );
    try supervisor.startRoot();
    var producer = lifecycle.LifecycleProducer.init(&inbox, &cancellations, allocator);
    defer {
        producer.enqueueShutdown() catch {};
        _ = supervisor.awaitRoot();
    }
    var plane = DataPlane.init(allocator, producer, &queue);
    var projection = PodProjection.init(allocator, .{
        .matchFn = ProjectionFns.match,
        .sortKeyFn = ProjectionFns.sort,
    });
    defer projection.deinit();
    var service: K8sService = undefined;
    var theme: Theme = undefined;
    var pods = try resource_configs.PodsView.init(allocator, &theme, &service);
    defer pods.deinit();
    pods.bindPodProjection(&projection);
    var telemetry = PerfTelemetry.initFromFd(null);
    defer telemetry.deinit();
    var script = Script{ .allocator = allocator };
    var destroyed: std.atomic.Value(usize) = .init(0);
    var task = try ownedTaskSpec(allocator, .{
        .namespace = "default",
        .context_name = "test",
        .projection = &projection,
        .telemetry = &telemetry,
        .deinit_counter = &destroyed,
        .source_override = script.source(),
    });
    defer task.deinit(allocator);
    const key = try plane.startSubscription(1, &task);
    var route = Route{ .plane = &plane, .projection = &projection, .active = key };
    var router = keys.UiRouter{
        .context = &route,
        .targetFn = Route.target,
        .lifecycleFn = Route.lifecycleObserved,
    };

    var attempts: usize = 0;
    while (!route.completed and attempts < 100) : (attempts += 1) {
        while (queue.pop()) |value| {
            var envelope = value;
            if (!plane.acceptsEnvelope(envelope)) {
                envelope.deinit(allocator);
                continue;
            }
            const target_value = envelope.target;
            try envelope.apply(&router, allocator);
            if (target_value == .resource) try pods.syncPodProjection();
        }
        if (route.completed) break;
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }

    try std.testing.expect(route.completed);
    if (destroyed.load(.acquire) != 1) return error.TaskNotDestroyedExactlyOnce;
    if (projection.count() != 1) return error.ProjectedPodMissing;
    if (pods.table.filtered_indices.items.len != 1) return error.TablePodMissing;
    try std.testing.expectEqualStrings("streamed-pod", pods.table.items.items[0].columns[1]);
    var first_paint = false;
    var complete_paint = false;
    const paint_event = perf.Event{
        .kind = .first_usable_paint,
        .monotonic_ns = 1,
        .context = "test",
        .resource = "pods",
        .scope = "default",
        .generation = key.generation,
        .subscription_id = key.subscription_id,
        .applied_revision = projection.appliedRevision(),
        .object_count = projection.count(),
        .queue_bytes = 0,
    };
    var complete_event = paint_event;
    complete_event.kind = .complete_sync_paint;
    perf.emitPodPaintsAfterFlush(
        &telemetry,
        &first_paint,
        &complete_paint,
        .{
            .current_is_pods = true,
            .initial_applied = true,
            .loading = pods.table.loading,
            .has_error = pods.table.error_message != null,
            .visible_rows = pods.table.filtered_indices.items.len,
            .flush_succeeded = true,
            .close_succeeded = true,
            .list_complete_revision = projection.appliedRevision(),
            .applied_revision = projection.appliedRevision(),
            .apply_failed = false,
        },
        paint_event,
        complete_event,
    );
    try std.testing.expect(first_paint);
    try std.testing.expect(complete_paint);
}
