const std = @import("std");
const klient = @import("klient");
const clock = @import("../core/clock.zig");
const lifecycle = @import("LifecycleInbox.zig");
const list_watch = @import("ListWatch.zig");
const stream_list = @import("StreamList.zig");
const read_transport = @import("ReadTransport.zig");
const keys = @import("ResourceKey.zig");
const projection_mod = @import("ResourceProjection.zig");

pub fn ResourceSubscription(
    comptime KlientType: type,
    comptime Record: type,
    comptime fromObject: fn (std.mem.Allocator, KlientType) anyerror!Record,
) type {
    const Projection = projection_mod.ResourceProjection(Record);

    return struct {
        const Self = @This();

        pub const Options = struct {
            context_name: []const u8,
            namespace: ?[]const u8 = null,
            projection: *Projection,
            deinit_counter: ?*std.atomic.Value(usize) = null,
            source_override: ?list_watch.Source(Record) = null,
        };

        const Spec = struct {
            context_name: []u8,
            namespace: ?[]u8,
            projection: *Projection,
            generation: keys.Generation = 0,
            subscription_id: keys.SubscriptionId = 0,
            deinit_counter: ?*std.atomic.Value(usize),
            source_override: ?list_watch.Source(Record),

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
                };
                if (self.source_override) |source| {
                    try self.runDriver(
                        control,
                        source,
                        &sink_state,
                        .{ .context = self, .wait_fn = noRetryWait },
                    );
                    return;
                }

                const descriptor = read_transport.ResourceDescriptor.forType(KlientType);
                const list_path = try descriptor.listPath(control.allocator, self.namespace);
                defer control.allocator.free(list_path);
                var transport_adapter = read_transport.KlientTransport{ .client = client, .io = io };
                var source_state = SourceState{
                    .allocator = control.allocator,
                    .io = io,
                    .client = client,
                    .transport = transport_adapter.transport(),
                    .descriptor = descriptor,
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
                source: list_watch.Source(Record),
                sink_state: *SinkState,
                retry_hooks: list_watch.RetryHooks,
            ) !void {
                var driver = list_watch.Driver(Record){
                    .allocator = control.allocator,
                    .source = source,
                    .sink = sink_state.sink(),
                    .retry_hooks = retry_hooks,
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
                allocator.free(self.context_name);
                if (self.namespace) |namespace| allocator.free(namespace);
                if (self.deinit_counter) |counter| _ = counter.fetchAdd(1, .acq_rel);
                allocator.destroy(self);
            }
        };

        pub fn ownedTaskSpec(
            allocator: std.mem.Allocator,
            options: Options,
        ) !lifecycle.OwnedTaskSpec {
            const spec = try allocator.create(Spec);
            errdefer allocator.destroy(spec);
            const context_name = try allocator.dupe(u8, options.context_name);
            errdefer allocator.free(context_name);
            const namespace = if (options.namespace) |value|
                try allocator.dupe(u8, value)
            else
                null;
            spec.* = .{
                .context_name = context_name,
                .namespace = namespace,
                .projection = options.projection,
                .deinit_counter = options.deinit_counter,
                .source_override = options.source_override,
            };
            return .{
                .ptr = spec,
                .alignment = .of(Spec),
                .owned_bytes = @sizeOf(Spec) + context_name.len +
                    (if (namespace) |value| value.len else 0),
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
            descriptor: read_transport.ResourceDescriptor,
            list_path: []const u8,
            namespace: ?[]const u8,

            fn source(self: *SourceState) list_watch.Source(Record) {
                return .{ .context = self, .list_fn = list, .watch_fn = watch };
            }

            fn list(
                raw: *anyopaque,
                _: list_watch.CancelToken,
                receiver_context: *anyopaque,
                receiver: *const fn (*anyopaque, Record) anyerror!void,
                chunk_end: *const fn (*anyopaque) anyerror!void,
            ) anyerror!list_watch.ListOutcome {
                const self: *SourceState = @ptrCast(@alignCast(raw));
                const Batch = struct {
                    source: *SourceState,
                    receiver_context: *anyopaque,
                    receiver: *const fn (*anyopaque, Record) anyerror!void,
                    chunk_end: *const fn (*anyopaque) anyerror!void,

                    fn receive(ctx: *@This(), objects: []const KlientType) anyerror!void {
                        for (objects) |object| {
                            const record = try fromObject(ctx.source.allocator, object);
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
                    KlientType,
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
                receiver: *const fn (*anyopaque, *list_watch.WatchEvent(Record)) anyerror!void,
            ) anyerror!list_watch.Failure {
                const self: *SourceState = @ptrCast(@alignCast(raw));
                var watcher = klient.Watcher(KlientType).init(
                    self.client,
                    self.descriptor.api_path,
                    self.descriptor.resource_name,
                    self.namespace,
                    .{ .resource_version = resource_version, .allow_watch_bookmarks = true },
                );
                defer watcher.deinit();
                const Callback = struct {
                    source: *SourceState,
                    receiver_context: *anyopaque,
                    receiver: *const fn (*anyopaque, *list_watch.WatchEvent(Record)) anyerror!void,

                    fn receive(
                        ctx: *@This(),
                        event_value: *klient.watch.WatchEvent(KlientType),
                    ) anyerror!void {
                        defer event_value.deinit();
                        var event: list_watch.WatchEvent(Record) = switch (event_value.type_) {
                            .ADDED => .{ .added = try fromObject(ctx.source.allocator, event_value.object) },
                            .MODIFIED => .{ .modified = try fromObject(ctx.source.allocator, event_value.object) },
                            .DELETED => blk: {
                                var record = try fromObject(ctx.source.allocator, event_value.object);
                                defer record.deinit(ctx.source.allocator);
                                break :blk .{ .deleted = try record.key.clone(ctx.source.allocator) };
                            },
                            .ERROR, .BOOKMARK => return,
                        };
                        defer event.deinit(ctx.source.allocator);
                        try ctx.receiver(ctx.receiver_context, &event);
                    }
                };
                var callback = Callback{
                    .source = self,
                    .receiver_context = receiver_context,
                    .receiver = receiver,
                };
                const outcome = watcher.watchWithContextOutcome(
                    *Callback,
                    &callback,
                    Callback.receive,
                ) catch |err| {
                    if (classifyWatchObjectError(err)) |failure| return failure;
                    return err;
                };
                if (watcher.resource_version) |version| {
                    if (!std.mem.eql(u8, version, resource_version)) {
                        var bookmark: list_watch.WatchEvent(Record) = .{
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
            projection: *Projection,

            fn sink(self: *SinkState) list_watch.BatchSink(Record) {
                return .{ .context = self, .emit_fn = emit };
            }

            fn emit(raw: *anyopaque, batch: *keys.TypedBatch(Record)) anyerror!void {
                const self: *SinkState = @ptrCast(@alignCast(raw));
                const heap_batch = try self.allocator.create(keys.TypedBatch(Record));
                heap_batch.* = batch.*;
                batch.* = undefined;
                const envelope = keys.eraseBatch(
                    Record,
                    self.allocator,
                    heap_batch,
                    Projection.handler(),
                    @ptrCast(self.projection),
                ) catch |err| {
                    heap_batch.deinit(self.allocator);
                    self.allocator.destroy(heap_batch);
                    return err;
                };
                _ = try self.control.publishDelivery(envelope);
            }
        };
    };
}

fn classifyListError(err: anyerror) list_watch.Failure {
    return switch (err) {
        error.Canceled => .canceled,
        error.HttpStatus => .server,
        error.MalformedOuterJson,
        error.ItemsNotArray,
        error.MalformedItem,
        error.MissingItems,
        error.MissingResourceVersion,
        error.ObjectTooLarge,
        error.ResponseTooLarge,
        error.MissingUid,
        error.MissingController,
        => .{ .malformed = detail(err) },
        else => .transport,
    };
}

fn classifyWatchObjectError(err: anyerror) ?list_watch.Failure {
    return switch (err) {
        error.MissingUid,
        error.MissingController,
        error.MalformedWatchEvent,
        => .{ .malformed = detail(err) },
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

test "cluster subscription specs own context and clean up independently" {
    const NodeRecord = @import("NodeRecord.zig");
    const NamespaceRecord = @import("NamespaceRecord.zig");
    const NodeProjection = projection_mod.ResourceProjection(NodeRecord);
    const NamespaceProjection = projection_mod.ResourceProjection(NamespaceRecord);
    const NodeSubscription = ResourceSubscription(
        klient.Node,
        NodeRecord,
        NodeRecord.fromNode,
    );
    const NamespaceSubscription = ResourceSubscription(
        klient.Namespace,
        NamespaceRecord,
        NamespaceRecord.fromNamespace,
    );
    var node_projection: NodeProjection = undefined;
    var namespace_projection: NamespaceProjection = undefined;
    var node_destroyed: std.atomic.Value(usize) = .init(0);
    var namespace_destroyed: std.atomic.Value(usize) = .init(0);
    var node_task = try NodeSubscription.ownedTaskSpec(std.testing.allocator, .{
        .context_name = "dev",
        .projection = &node_projection,
        .deinit_counter = &node_destroyed,
    });
    var namespace_task = try NamespaceSubscription.ownedTaskSpec(std.testing.allocator, .{
        .context_name = "dev",
        .projection = &namespace_projection,
        .deinit_counter = &namespace_destroyed,
    });
    node_task.bindFn(node_task.ptr, 7, 11);
    namespace_task.bindFn(namespace_task.ptr, 7, 12);
    node_task.deinit(std.testing.allocator);
    namespace_task.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), node_destroyed.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), namespace_destroyed.load(.acquire));
}

test "cluster subscription malformed policy includes UID-less objects" {
    try std.testing.expect(classifyListError(error.MissingUid) == .malformed);
    try std.testing.expect(classifyWatchObjectError(error.MissingUid).? == .malformed);
}

fn exerciseQueueRestart(
    comptime Record: type,
    comptime Subscription: type,
    comptime discriminating_rows: bool,
    comptime name_column: u8,
    projection: *projection_mod.ResourceProjection(Record),
    table_context: *anyopaque,
    comptime sync_table: fn (*anyopaque) anyerror!void,
) !void {
    const runtime = @import("../core/runtime.zig");
    const DataPlane = @import("DataPlane.zig").DataPlane;
    const ChangeQueue = @import("ChangeQueue.zig").ChangeQueue;
    const Supervisor = @import("LifecycleSupervisor.zig").LifecycleSupervisor;
    const active_context = @import("ActiveContextSession.zig");
    const ActiveSessionSlot = @import("ActiveSessionSlot.zig").ActiveSessionSlot;
    const NodeRecord = @import("NodeRecord.zig");
    const NamespaceRecord = @import("NamespaceRecord.zig");
    const ServiceRecord = @import("ServiceRecord.zig");
    const EndpointRecord = @import("EndpointRecord.zig");
    const EndpointSliceRecord = @import("EndpointSliceRecord.zig");
    const ConfigMapRecord = @import("ConfigMapRecord.zig");
    const SecretRecord = @import("SecretRecord.zig");
    const ServiceAccountRecord = @import("ServiceAccountRecord.zig");
    const ResourceQuotaRecord = @import("ResourceQuotaRecord.zig");
    const LimitRangeRecord = @import("LimitRangeRecord.zig");
    const DeploymentRecord = @import("DeploymentRecord.zig");
    const StatefulSetRecord = @import("StatefulSetRecord.zig");
    const DaemonSetRecord = @import("DaemonSetRecord.zig");
    const ReplicaSetRecord = @import("ReplicaSetRecord.zig");
    const JobRecord = @import("JobRecord.zig");
    const CronJobRecord = @import("CronJobRecord.zig");
    const HPARecord = @import("HPARecord.zig");
    const PDBRecord = @import("PDBRecord.zig");
    const IngressRecord = @import("IngressRecord.zig");
    const IngressClassRecord = @import("IngressClassRecord.zig");
    const NetworkPolicyRecord = @import("NetworkPolicyRecord.zig");
    const IPAddressRecord = @import("IPAddressRecord.zig");
    const ServiceCIDRRecord = @import("ServiceCIDRRecord.zig");
    const PVRecord = @import("PVRecord.zig");
    const PVCRecord = @import("PVCRecord.zig");
    const StorageClassRecord = @import("StorageClassRecord.zig");
    const VolumeAttributesClassRecord = @import("VolumeAttributesClassRecord.zig");
    const CSIDriverRecord = @import("CSIDriverRecord.zig");
    const allocator = std.testing.allocator;
    const io = runtime.io();

    const Script = struct {
        allocator: std.mem.Allocator,
        list_value: []const u8,
        watch_value: []const u8,

        fn source(self: *@This()) list_watch.Source(Record) {
            return .{ .context = self, .list_fn = list, .watch_fn = watch };
        }

        fn makeRecord(
            self: *@This(),
            uid: []const u8,
            name: []const u8,
            value: []const u8,
            timestamp: []const u8,
        ) !Record {
            const key = try (keys.ObjectKey{
                .uid = uid,
                .namespace = if (Record == NodeRecord or
                    Record == NamespaceRecord or
                    Record == IngressClassRecord or
                    Record == IPAddressRecord or
                    Record == ServiceCIDRRecord or
                    Record == PVRecord or
                    Record == StorageClassRecord or
                    Record == VolumeAttributesClassRecord or
                    Record == CSIDriverRecord) "" else "default",
                .name = name,
            }).clone(self.allocator);
            if (comptime Record == NodeRecord) {
                return .{
                    .key = key,
                    .status = try self.allocator.dupe(u8, value),
                    .roles = try self.allocator.dupe(u8, "worker"),
                    .version = try self.allocator.dupe(u8, "v1.31.0"),
                    .internal_ip = try self.allocator.dupe(u8, "10.0.0.1"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            }
            if (comptime Record == NamespaceRecord)
                return .{
                    .key = key,
                    .status = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ServiceRecord)
                return .{
                    .key = key,
                    .service_type = try self.allocator.dupe(u8, value),
                    .cluster_ip = try self.allocator.dupe(u8, "10.96.0.1"),
                    .external_ip = try self.allocator.dupe(u8, "1.2.3.4"),
                    .ports = try self.allocator.dupe(u8, "80/TCP"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == EndpointRecord)
                return .{
                    .key = key,
                    .endpoints = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == EndpointSliceRecord)
                return .{
                    .key = key,
                    .address_type = try self.allocator.dupe(u8, "IPv4"),
                    .endpoints = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ConfigMapRecord)
                return .{
                    .key = key,
                    .data_count = if (std.mem.endsWith(u8, value, "watch")) 3 else if (std.mem.eql(u8, value, "secondary")) 2 else 1,
                    .data_sort_key = ConfigMapRecord.numericSortKey(if (std.mem.endsWith(u8, value, "watch")) 3 else if (std.mem.eql(u8, value, "secondary")) 2 else 1),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == SecretRecord)
                return .{
                    .key = key,
                    .secret_type = try self.allocator.dupe(u8, value),
                    .data_count = if (std.mem.endsWith(u8, value, "watch")) 3 else 1,
                    .data_sort_key = ConfigMapRecord.numericSortKey(if (std.mem.endsWith(u8, value, "watch")) 3 else 1),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ServiceAccountRecord)
                return .{
                    .key = key,
                    .secret_count = if (std.mem.endsWith(u8, value, "watch")) 3 else if (std.mem.eql(u8, value, "secondary")) 2 else 1,
                    .secret_sort_key = ConfigMapRecord.numericSortKey(if (std.mem.endsWith(u8, value, "watch")) 3 else if (std.mem.eql(u8, value, "secondary")) 2 else 1),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ResourceQuotaRecord or Record == LimitRangeRecord)
                return .{
                    .key = key,
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            const count: i32 = if (std.mem.endsWith(u8, value, "watch")) 7 else if (std.mem.eql(u8, value, "secondary")) 4 else 2;
            if (comptime Record == DeploymentRecord)
                return .{
                    .key = key,
                    .ready_replicas = count,
                    .desired_replicas = 8,
                    .updated_replicas = count + 1,
                    .available_replicas = count - 1,
                    .ready_sort_key = DeploymentRecord.ratioSortKey(count, 8),
                    .updated_sort_key = DeploymentRecord.countSortKey(count + 1),
                    .available_sort_key = DeploymentRecord.countSortKey(count - 1),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == StatefulSetRecord)
                return .{
                    .key = key,
                    .ready_replicas = count,
                    .desired_replicas = 8,
                    .ready_sort_key = DeploymentRecord.ratioSortKey(count, 8),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == DaemonSetRecord)
                return .{
                    .key = key,
                    .desired = count,
                    .current = count - 1,
                    .ready = count - 2,
                    .updated = count - 3,
                    .desired_sort_key = DeploymentRecord.countSortKey(count),
                    .current_sort_key = DeploymentRecord.countSortKey(count - 1),
                    .ready_sort_key = DeploymentRecord.countSortKey(count - 2),
                    .updated_sort_key = DeploymentRecord.countSortKey(count - 3),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ReplicaSetRecord)
                return .{
                    .key = key,
                    .desired = count,
                    .current = count - 1,
                    .ready = count - 2,
                    .desired_sort_key = DeploymentRecord.countSortKey(count),
                    .current_sort_key = DeploymentRecord.countSortKey(count - 1),
                    .ready_sort_key = DeploymentRecord.countSortKey(count - 2),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == JobRecord)
                return .{
                    .key = key,
                    .succeeded = count,
                    .desired = 8,
                    .completions_sort_key = JobRecord.ratioSortKey(count, 8),
                    .start_time = try self.allocator.dupe(u8, "2024-01-01T00:00:00Z"),
                    .completion_time = try self.allocator.dupe(u8, "2024-01-01T01:00:00Z"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == CronJobRecord)
                return .{
                    .key = key,
                    .schedule = try self.allocator.dupe(u8, "0 0 * * *"),
                    .@"suspend" = false,
                    .active = count,
                    .active_sort_key = CronJobRecord.countSortKey(count),
                    .last_schedule_time = try self.allocator.dupe(u8, timestamp),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == HPARecord)
                return .{
                    .key = key,
                    .min_replicas = 1,
                    .max_replicas = 8,
                    .current_replicas = count,
                    .min_sort_key = HPARecord.countSortKey(1),
                    .max_sort_key = HPARecord.countSortKey(8),
                    .current_sort_key = HPARecord.countSortKey(count),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == PDBRecord)
                return .{
                    .key = key,
                    .min_available = try self.allocator.dupe(u8, "1"),
                    .max_unavailable = try self.allocator.dupe(u8, "1"),
                    .allowed_disruptions = count,
                    .allowed_sort_key = PDBRecord.countSortKey(count),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == IngressRecord)
                return .{
                    .key = key,
                    .class = try self.allocator.dupe(u8, "nginx"),
                    .hosts = try self.allocator.dupe(u8, value),
                    .address = try self.allocator.dupe(u8, value),
                    .ports = try self.allocator.dupe(u8, "80, 443"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == IngressClassRecord)
                return .{
                    .key = key,
                    .controller = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == NetworkPolicyRecord)
                return .{
                    .key = key,
                    .pod_selector = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == IPAddressRecord)
                return .{
                    .key = key,
                    .parent = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == ServiceCIDRRecord)
                return .{
                    .key = key,
                    .cidrs = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == PVRecord)
                return .{
                    .key = key,
                    .capacity = try self.allocator.dupe(u8, value),
                    .capacity_sort_key = PVRecord.capacitySortKey(value),
                    .access = try self.allocator.dupe(u8, "RWO"),
                    .reclaim = try self.allocator.dupe(u8, "Retain"),
                    .status = try self.allocator.dupe(u8, value),
                    .claim = try self.allocator.dupe(u8, "default/cache"),
                    .storage_class = try self.allocator.dupe(u8, "fast"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == PVCRecord)
                return .{
                    .key = key,
                    .status = try self.allocator.dupe(u8, value),
                    .volume = try self.allocator.dupe(u8, "pv-1"),
                    .capacity = try self.allocator.dupe(u8, value),
                    .capacity_sort_key = PVRecord.capacitySortKey(value),
                    .access = try self.allocator.dupe(u8, "RWX"),
                    .storage_class = try self.allocator.dupe(u8, "fast"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == StorageClassRecord)
                return .{
                    .key = key,
                    .provisioner = try self.allocator.dupe(u8, value),
                    .reclaim_policy = try self.allocator.dupe(u8, "Retain"),
                    .bind_mode = try self.allocator.dupe(u8, "Immediate"),
                    .expansion = true,
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == VolumeAttributesClassRecord)
                return .{
                    .key = key,
                    .driver = try self.allocator.dupe(u8, value),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            if (comptime Record == CSIDriverRecord)
                return .{
                    .key = key,
                    .attach_required = !std.mem.endsWith(u8, value, "watch"),
                    .pod_info = std.mem.endsWith(u8, value, "watch"),
                    .creation_timestamp = try self.allocator.dupe(u8, timestamp),
                };
            unreachable;
        }

        fn list(
            raw: *anyopaque,
            _: list_watch.CancelToken,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, Record) anyerror!void,
            chunk_end: *const fn (*anyopaque) anyerror!void,
        ) anyerror!list_watch.ListOutcome {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try receiver(receiver_context, try self.makeRecord(
                "stable-uid",
                "alpha-resource",
                self.list_value,
                "2024-01-01T00:00:00Z",
            ));
            if (comptime discriminating_rows) {
                try receiver(receiver_context, try self.makeRecord(
                    "other-uid",
                    "beta-resource",
                    "secondary",
                    "2024-02-01T00:00:00Z",
                ));
            }
            try chunk_end(receiver_context);
            return .{ .complete = try keys.OwnedBytes.clone(self.allocator, "10") };
        }

        fn watch(
            raw: *anyopaque,
            _: []const u8,
            _: list_watch.CancelToken,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, *list_watch.WatchEvent(Record)) anyerror!void,
        ) anyerror!list_watch.Failure {
            const self: *@This() = @ptrCast(@alignCast(raw));
            var event: list_watch.WatchEvent(Record) = .{
                .modified = try self.makeRecord(
                    "stable-uid",
                    "alpha-resource",
                    self.watch_value,
                    "2024-01-01T00:00:00Z",
                ),
            };
            defer event.deinit(self.allocator);
            try receiver(receiver_context, &event);
            return .canceled;
        }
    };

    const Route = struct {
        plane: *DataPlane,
        projection: *projection_mod.ResourceProjection(Record),
        active: lifecycle.SubscriptionKey,
        table_context: *anyopaque,
        io: std.Io,
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
            _: *anyopaque,
            identity: ?keys.ResourceIdentity,
        ) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const exact = identity orelse return;
            if (exact.generation == self.active.generation and
                exact.subscription_id == self.active.subscription_id)
            {
                self.completed = true;
            }
        }

        fn drain(self: *@This(), queue: *ChangeQueue) !void {
            var router = keys.UiRouter{
                .context = self,
                .targetFn = target,
                .lifecycleFn = lifecycleObserved,
            };
            var attempts: usize = 0;
            while (!self.completed and attempts < 200) : (attempts += 1) {
                while (queue.pop()) |value| {
                    var envelope = value;
                    if (!self.plane.acceptsEnvelope(envelope)) {
                        envelope.deinit(allocator);
                        continue;
                    }
                    const target_value = envelope.target;
                    try envelope.apply(&router, allocator);
                    if (target_value == .resource) {
                        try sync_table(self.table_context);
                    }
                }
                if (!self.completed) try self.io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
            }
            try std.testing.expect(self.completed);
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
    var script = Script{
        .allocator = allocator,
        .list_value = "first-list",
        .watch_value = "first-watch",
    };
    var first_spec = try Subscription.ownedTaskSpec(allocator, .{
        .context_name = "test",
        .projection = projection,
        .source_override = script.source(),
    });
    defer first_spec.deinit(allocator);
    const first_key = try plane.startSubscription(1, &first_spec);
    var first_route = Route{
        .plane = &plane,
        .projection = projection,
        .active = first_key,
        .table_context = table_context,
        .io = io,
    };
    try first_route.drain(&queue);
    if (comptime discriminating_rows) {
        try std.testing.expectEqual(@as(usize, 2), projection.count());
        try projection.setView("", name_column, false);
        try sync_table(table_context);
        try std.testing.expectEqualStrings("other-uid", projection.visibleUid(0).?);
        try projection.setView("alpha", name_column, true);
        try std.testing.expectEqual(@as(usize, 1), projection.visibleCount());
        try std.testing.expectEqualStrings("stable-uid", projection.visibleUid(0).?);
    }
    try std.testing.expect(projection.selectUid("stable-uid"));
    try sync_table(table_context);

    script.list_value = "second-list";
    script.watch_value = "second-watch";
    var second_spec = try Subscription.ownedTaskSpec(allocator, .{
        .context_name = "test",
        .projection = projection,
        .source_override = script.source(),
    });
    defer second_spec.deinit(allocator);
    const second_key = try plane.startSubscription(1, &second_spec);
    try std.testing.expect(second_key.subscription_id != first_key.subscription_id);
    var second_route = Route{
        .plane = &plane,
        .projection = projection,
        .active = second_key,
        .table_context = table_context,
        .io = io,
    };
    try second_route.drain(&queue);
    try std.testing.expectEqualStrings("stable-uid", projection.selectedUid().?);
    try std.testing.expectEqual(@as(usize, 1), projection.visibleCount());
    try std.testing.expectEqualStrings("stable-uid", projection.visibleUid(0).?);
}

test "node LIST WATCH supervisor queue populates table and preserves selection on restart" {
    const NodeRecord = @import("NodeRecord.zig");
    const Projection = projection_mod.ResourceProjection(NodeRecord);
    const Subscription = ResourceSubscription(klient.Node, NodeRecord, NodeRecord.fromNode);
    const NodesView = @import("../view/resource_configs.zig").NodesView;
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const ProjectionFns = struct {
        fn match(_: *const NodeRecord, _: []const u8) bool {
            return true;
        }
        fn sort(record: *const NodeRecord, _: u8) []const u8 {
            return record.key.name;
        }
        fn enabled() bool {
            return true;
        }
        fn columns(_: *Projection, record: *const NodeRecord, allocator: std.mem.Allocator) ![6][]const u8 {
            return record.columns(allocator);
        }
        fn sync(raw: *anyopaque) !void {
            const view: *NodesView = @ptrCast(@alignCast(raw));
            try view.syncProjection();
        }
    };
    var projection = Projection.init(std.testing.allocator, .{
        .matchFn = ProjectionFns.match,
        .sortKeyFn = ProjectionFns.sort,
    });
    defer projection.deinit();
    var service: K8sService = undefined;
    var theme: Theme = undefined;
    var view = try NodesView.init(std.testing.allocator, &theme, &service);
    defer view.deinit();
    view.bindProjection(NodesView.ProjectionAdapter.init(
        NodeRecord,
        &projection,
        ProjectionFns.enabled,
        ProjectionFns.columns,
    ));
    try exerciseQueueRestart(
        NodeRecord,
        Subscription,
        false,
        0,
        &projection,
        @ptrCast(&view),
        ProjectionFns.sync,
    );
    try std.testing.expectEqual(@as(usize, 1), view.table.items.items.len);
    try std.testing.expectEqualStrings("second-watch", view.table.items.items[0].columns[1]);
}

test "namespace LIST WATCH supervisor queue populates table and preserves selection on restart" {
    const NamespaceRecord = @import("NamespaceRecord.zig");
    const Projection = projection_mod.ResourceProjection(NamespaceRecord);
    const Subscription = ResourceSubscription(
        klient.Namespace,
        NamespaceRecord,
        NamespaceRecord.fromNamespace,
    );
    const NamespacesView = @import("../view/NamespacesView.zig").NamespacesView;
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const ProjectionFns = struct {
        fn match(_: *const NamespaceRecord, _: []const u8) bool {
            return true;
        }
        fn sort(record: *const NamespaceRecord, _: u8) []const u8 {
            return record.key.name;
        }
        fn sync(raw: *anyopaque) !void {
            const view: *NamespacesView = @ptrCast(@alignCast(raw));
            try view.syncProjection();
        }
    };
    var projection = Projection.init(std.testing.allocator, .{
        .matchFn = ProjectionFns.match,
        .sortKeyFn = ProjectionFns.sort,
    });
    defer projection.deinit();
    var service = try K8sService.init(std.testing.allocator);
    defer service.deinit();
    var theme: Theme = undefined;
    var view = try NamespacesView.init(std.testing.allocator, &theme, &service);
    defer view.deinit();
    view.bindProjection(&projection);
    try exerciseQueueRestart(
        NamespaceRecord,
        Subscription,
        false,
        0,
        &projection,
        @ptrCast(&view),
        ProjectionFns.sync,
    );
    try std.testing.expectEqual(@as(usize, 1), view.table.items.items.len);
    try std.testing.expectEqualStrings("second-watch", view.table.items.items[0].status);
}

fn exerciseNamespacedFamily(
    comptime Record: type,
    comptime Subscription: type,
    comptime ViewType: type,
    value_column: ?usize,
    expected_value: []const u8,
) !void {
    const Projection = projection_mod.ResourceProjection(Record);
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const Fns = struct {
        fn containsIgnoreCase(value: []const u8, needle: []const u8) bool {
            if (needle.len > value.len) return false;
            var index: usize = 0;
            while (index + needle.len <= value.len) : (index += 1) {
                if (std.ascii.eqlIgnoreCase(value[index .. index + needle.len], needle))
                    return true;
            }
            return false;
        }
        fn match(record: *const Record, filter: []const u8) bool {
            return filter.len == 0 or
                containsIgnoreCase(record.key.namespace, filter) or
                containsIgnoreCase(record.key.name, filter);
        }
        fn sort(record: *const Record, column: u8) []const u8 {
            const ServiceRecord = @import("ServiceRecord.zig");
            const EndpointRecord = @import("EndpointRecord.zig");
            const ConfigMapRecord = @import("ConfigMapRecord.zig");
            const SecretRecord = @import("SecretRecord.zig");
            const ServiceAccountRecord = @import("ServiceAccountRecord.zig");
            const ResourceQuotaRecord = @import("ResourceQuotaRecord.zig");
            const LimitRangeRecord = @import("LimitRangeRecord.zig");
            const DeploymentRecord = @import("DeploymentRecord.zig");
            const StatefulSetRecord = @import("StatefulSetRecord.zig");
            const DaemonSetRecord = @import("DaemonSetRecord.zig");
            const ReplicaSetRecord = @import("ReplicaSetRecord.zig");
            const JobRecord = @import("JobRecord.zig");
            const CronJobRecord = @import("CronJobRecord.zig");
            const HPARecord = @import("HPARecord.zig");
            const PDBRecord = @import("PDBRecord.zig");
            const IngressRecord = @import("IngressRecord.zig");
            const IngressClassRecord = @import("IngressClassRecord.zig");
            const NetworkPolicyRecord = @import("NetworkPolicyRecord.zig");
            const IPAddressRecord = @import("IPAddressRecord.zig");
            const ServiceCIDRRecord = @import("ServiceCIDRRecord.zig");
            const PVRecord = @import("PVRecord.zig");
            const PVCRecord = @import("PVCRecord.zig");
            const StorageClassRecord = @import("StorageClassRecord.zig");
            const VolumeAttributesClassRecord = @import("VolumeAttributesClassRecord.zig");
            const CSIDriverRecord = @import("CSIDriverRecord.zig");
            if (comptime Record == ServiceRecord) {
                return switch (column) {
                    0 => record.key.namespace,
                    1 => record.key.name,
                    2 => record.service_type,
                    3 => record.cluster_ip,
                    4 => record.external_ip,
                    5 => record.ports,
                    6 => record.creation_timestamp orelse "",
                    else => record.key.name,
                };
            }
            if (comptime Record == EndpointRecord) {
                return switch (column) {
                    0 => record.key.namespace,
                    1 => record.key.name,
                    2 => record.endpoints,
                    3 => record.creation_timestamp orelse "",
                    else => record.key.name,
                };
            }
            if (comptime Record == ConfigMapRecord or Record == ServiceAccountRecord) {
                return switch (column) {
                    0 => record.key.namespace,
                    1 => record.key.name,
                    2 => if (Record == ConfigMapRecord) &record.data_sort_key else &record.secret_sort_key,
                    3 => record.creation_timestamp orelse "",
                    else => record.key.name,
                };
            }
            if (comptime Record == SecretRecord) {
                return switch (column) {
                    0 => record.key.namespace,
                    1 => record.key.name,
                    2 => record.secret_type,
                    3 => &record.data_sort_key,
                    4 => record.creation_timestamp orelse "",
                    else => record.key.name,
                };
            }
            if (comptime Record == ResourceQuotaRecord or Record == LimitRangeRecord) {
                return switch (column) {
                    0 => record.key.namespace,
                    1 => record.key.name,
                    2 => record.creation_timestamp orelse "",
                    else => record.key.name,
                };
            }
            if (comptime Record == DeploymentRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.ready_sort_key,
                3 => &record.updated_sort_key,
                4 => &record.available_sort_key,
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == StatefulSetRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.ready_sort_key,
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == DaemonSetRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.desired_sort_key,
                3 => &record.current_sort_key,
                4 => &record.ready_sort_key,
                5 => &record.updated_sort_key,
                6 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ReplicaSetRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.desired_sort_key,
                3 => &record.current_sort_key,
                4 => &record.ready_sort_key,
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == JobRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.completions_sort_key,
                3 => record.start_time orelse "",
                4 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == CronJobRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.schedule,
                3 => if (record.@"suspend") "True" else "False",
                4 => &record.active_sort_key,
                5 => record.last_schedule_time orelse "",
                else => record.key.name,
            };
            if (comptime Record == HPARecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.min_sort_key,
                3 => &record.max_sort_key,
                4 => &record.current_sort_key,
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == PDBRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => &record.min_available_sort_key,
                3 => &record.max_unavailable_sort_key,
                4 => &record.allowed_sort_key,
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == IngressRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.class,
                3 => record.hosts,
                4 => record.address,
                5 => record.ports,
                6 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == IngressClassRecord) return switch (column) {
                0 => record.key.name,
                1 => record.controller,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == NetworkPolicyRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.pod_selector,
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == IPAddressRecord) return switch (column) {
                0 => record.key.name,
                1 => record.parent,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == ServiceCIDRRecord) return switch (column) {
                0 => record.key.name,
                1 => record.cidrs,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == PVRecord) return switch (column) {
                0 => record.key.name,
                1 => &record.capacity_sort_key,
                2 => record.access,
                3 => record.reclaim,
                4 => record.status,
                5 => record.claim,
                6 => record.storage_class,
                7 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == PVCRecord) return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.status,
                3 => record.volume,
                4 => &record.capacity_sort_key,
                5 => record.access,
                6 => record.storage_class,
                7 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == StorageClassRecord) return switch (column) {
                0 => record.key.name,
                1 => record.provisioner,
                2 => record.reclaim_policy,
                3 => record.bind_mode,
                4 => if (record.expansion) "true" else "false",
                5 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == VolumeAttributesClassRecord) return switch (column) {
                0 => record.key.name,
                1 => record.driver,
                2 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            if (comptime Record == CSIDriverRecord) return switch (column) {
                0 => record.key.name,
                1 => if (record.attach_required) "true" else "false",
                2 => if (record.pod_info) "true" else "false",
                3 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
            return switch (column) {
                0 => record.key.namespace,
                1 => record.key.name,
                2 => record.address_type,
                3 => record.endpoints,
                4 => record.creation_timestamp orelse "",
                else => record.key.name,
            };
        }
        fn enabled() bool {
            return true;
        }
        fn columns(
            _: *Projection,
            record: *const Record,
            allocator: std.mem.Allocator,
        ) ![ViewType.view_config.columns.len][]const u8 {
            return record.columns(allocator);
        }
        fn sync(raw: *anyopaque) !void {
            const view: *ViewType = @ptrCast(@alignCast(raw));
            try view.syncProjection();
        }
    };
    var projection = Projection.init(std.testing.allocator, .{
        .matchFn = Fns.match,
        .sortKeyFn = Fns.sort,
    });
    defer projection.deinit();
    var service = try K8sService.init(std.testing.allocator);
    defer service.deinit();
    var theme: Theme = undefined;
    var view = try ViewType.init(std.testing.allocator, &theme, &service);
    defer view.deinit();
    view.bindProjection(ViewType.ProjectionAdapter.init(
        Record,
        &projection,
        Fns.enabled,
        Fns.columns,
    ));
    try exerciseQueueRestart(
        Record,
        Subscription,
        true,
        ViewType.view_config.name_column,
        &projection,
        @ptrCast(&view),
        Fns.sync,
    );
    try std.testing.expectEqual(@as(usize, 1), view.table.items.items.len);
    if (value_column) |column| {
        try std.testing.expectEqualStrings(
            expected_value,
            view.table.items.items[0].columns[column],
        );
    }
}

test "services family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("ServiceRecord.zig"),
        ResourceSubscription(klient.Service, @import("ServiceRecord.zig"), @import("ServiceRecord.zig").fromService),
        configs.ServicesView,
        2,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("EndpointRecord.zig"),
        ResourceSubscription(klient.Endpoints, @import("EndpointRecord.zig"), @import("EndpointRecord.zig").fromEndpoints),
        configs.EndpointsView,
        2,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("EndpointSliceRecord.zig"),
        ResourceSubscription(klient.EndpointSlice, @import("EndpointSliceRecord.zig"), @import("EndpointSliceRecord.zig").fromEndpointSlice),
        configs.EndpointSlicesView,
        3,
        "second-watch",
    );
}

test "config family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("ConfigMapRecord.zig"),
        ResourceSubscription(klient.ConfigMap, @import("ConfigMapRecord.zig"), @import("ConfigMapRecord.zig").fromConfigMap),
        configs.ConfigMapsView,
        2,
        "3",
    );
    try exerciseNamespacedFamily(
        @import("SecretRecord.zig"),
        ResourceSubscription(klient.Secret, @import("SecretRecord.zig"), @import("SecretRecord.zig").fromSecret),
        configs.SecretsView,
        2,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("ServiceAccountRecord.zig"),
        ResourceSubscription(klient.ServiceAccount, @import("ServiceAccountRecord.zig"), @import("ServiceAccountRecord.zig").fromServiceAccount),
        configs.ServiceAccountsView,
        2,
        "3",
    );
    try exerciseNamespacedFamily(
        @import("ResourceQuotaRecord.zig"),
        ResourceSubscription(klient.ResourceQuota, @import("ResourceQuotaRecord.zig"), @import("ResourceQuotaRecord.zig").fromResourceQuota),
        configs.ResourceQuotasView,
        null,
        "",
    );
    try exerciseNamespacedFamily(
        @import("LimitRangeRecord.zig"),
        ResourceSubscription(klient.LimitRange, @import("LimitRangeRecord.zig"), @import("LimitRangeRecord.zig").fromLimitRange),
        configs.LimitRangesView,
        null,
        "",
    );
}

test "workloads family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("DeploymentRecord.zig"),
        ResourceSubscription(klient.Deployment, @import("DeploymentRecord.zig"), @import("DeploymentRecord.zig").fromDeployment),
        configs.DeploymentsView,
        2,
        "7/8",
    );
    try exerciseNamespacedFamily(
        @import("StatefulSetRecord.zig"),
        ResourceSubscription(klient.StatefulSet, @import("StatefulSetRecord.zig"), @import("StatefulSetRecord.zig").fromStatefulSet),
        configs.StatefulSetsView,
        2,
        "7/8",
    );
    try exerciseNamespacedFamily(
        @import("DaemonSetRecord.zig"),
        ResourceSubscription(klient.DaemonSet, @import("DaemonSetRecord.zig"), @import("DaemonSetRecord.zig").fromDaemonSet),
        configs.DaemonSetsView,
        2,
        "7",
    );
    try exerciseNamespacedFamily(
        @import("ReplicaSetRecord.zig"),
        ResourceSubscription(klient.ReplicaSet, @import("ReplicaSetRecord.zig"), @import("ReplicaSetRecord.zig").fromReplicaSet),
        configs.ReplicaSetsView,
        2,
        "7",
    );
}

test "batch family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("JobRecord.zig"),
        ResourceSubscription(klient.Job, @import("JobRecord.zig"), @import("JobRecord.zig").fromJob),
        configs.JobsView,
        2,
        "7/8",
    );
    try exerciseNamespacedFamily(
        @import("CronJobRecord.zig"),
        ResourceSubscription(klient.CronJob, @import("CronJobRecord.zig"), @import("CronJobRecord.zig").fromCronJob),
        configs.CronJobsView,
        4,
        "7",
    );
    try exerciseNamespacedFamily(
        @import("HPARecord.zig"),
        ResourceSubscription(klient.HorizontalPodAutoscaler, @import("HPARecord.zig"), @import("HPARecord.zig").fromHorizontalPodAutoscaler),
        configs.HPAView,
        4,
        "7",
    );
    try exerciseNamespacedFamily(
        @import("PDBRecord.zig"),
        ResourceSubscription(klient.PodDisruptionBudget, @import("PDBRecord.zig"), @import("PDBRecord.zig").fromPodDisruptionBudget),
        configs.PodDisruptionBudgetsView,
        4,
        "7",
    );
}

test "networking family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("IngressRecord.zig"),
        ResourceSubscription(klient.types.Ingress, @import("IngressRecord.zig"), @import("IngressRecord.zig").fromIngress),
        configs.IngressesView,
        3,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("IngressClassRecord.zig"),
        ResourceSubscription(klient.IngressClass, @import("IngressClassRecord.zig"), @import("IngressClassRecord.zig").fromIngressClass),
        configs.IngressClassesView,
        1,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("NetworkPolicyRecord.zig"),
        ResourceSubscription(klient.NetworkPolicy, @import("NetworkPolicyRecord.zig"), @import("NetworkPolicyRecord.zig").fromNetworkPolicy),
        configs.NetworkPoliciesView,
        2,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("IPAddressRecord.zig"),
        ResourceSubscription(klient.IPAddress, @import("IPAddressRecord.zig"), @import("IPAddressRecord.zig").fromIPAddress),
        configs.IPAddressesView,
        1,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("ServiceCIDRRecord.zig"),
        ResourceSubscription(klient.ServiceCIDR, @import("ServiceCIDRRecord.zig"), @import("ServiceCIDRRecord.zig").fromServiceCIDR),
        configs.ServiceCIDRsView,
        1,
        "second-watch",
    );
}

test "storage family LIST WATCH supervisor queue populates tables across restart" {
    const configs = @import("../view/resource_configs.zig");
    try exerciseNamespacedFamily(
        @import("PVRecord.zig"),
        ResourceSubscription(klient.PersistentVolume, @import("PVRecord.zig"), @import("PVRecord.zig").fromPersistentVolume),
        configs.PersistentVolumesView,
        4,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("PVCRecord.zig"),
        ResourceSubscription(klient.PersistentVolumeClaim, @import("PVCRecord.zig"), @import("PVCRecord.zig").fromPersistentVolumeClaim),
        configs.PersistentVolumeClaimsView,
        2,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("StorageClassRecord.zig"),
        ResourceSubscription(klient.StorageClass, @import("StorageClassRecord.zig"), @import("StorageClassRecord.zig").fromStorageClass),
        configs.StorageClassesView,
        1,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("VolumeAttributesClassRecord.zig"),
        ResourceSubscription(klient.VolumeAttributesClass, @import("VolumeAttributesClassRecord.zig"), @import("VolumeAttributesClassRecord.zig").fromVolumeAttributesClass),
        configs.VolumeAttributesClassesView,
        1,
        "second-watch",
    );
    try exerciseNamespacedFamily(
        @import("CSIDriverRecord.zig"),
        ResourceSubscription(klient.CSIDriver, @import("CSIDriverRecord.zig"), @import("CSIDriverRecord.zig").fromCSIDriver),
        configs.CSIDriversView,
        2,
        "true",
    );
}
