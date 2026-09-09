const std = @import("std");
const klient = @import("klient");
const lifecycle = @import("LifecycleInbox.zig");
const read_transport = @import("ReadTransport.zig");
const keys = @import("ResourceKey.zig");
const PodRecord = @import("PodRecord.zig");
const PodProjection = @import("ResourceProjection.zig").ResourceProjection(PodRecord);

pub const default_poll_interval_ns: u64 = 30 * std.time.ns_per_s;
pub const min_poll_interval_ns: u64 = std.time.ns_per_s;
pub const max_poll_interval_ns: u64 = 5 * 60 * std.time.ns_per_s;
const max_response_bytes: usize = 16 << 20;

pub const PollResult = struct {
    records: []keys.PodMetricsRecord = &.{},
    status: keys.MetricsStatus = .available,

    pub fn deinit(self: *PollResult, allocator: std.mem.Allocator) void {
        for (self.records) |*record| record.deinit(allocator);
        if (self.records.len > 0) allocator.free(self.records);
        self.* = .{};
    }
};

pub const Source = struct {
    context: *anyopaque,
    pollFn: *const fn (*anyopaque, std.mem.Allocator) anyerror!PollResult,
    waitFn: *const fn (*anyopaque, std.Io, u64) anyerror!bool,

    pub fn poll(self: Source, allocator: std.mem.Allocator) !PollResult {
        return self.pollFn(self.context, allocator);
    }

    pub fn wait(self: Source, io: std.Io, delay_ns: u64) !bool {
        return self.waitFn(self.context, io, delay_ns);
    }
};

pub const Options = struct {
    namespace: ?[]const u8,
    projection: *PodProjection,
    poll_interval_ns: u64 = default_poll_interval_ns,
    source_override: ?Source = null,
    transport_override: ?read_transport.ReadTransport = null,
    poll_gate: ?*std.atomic.Value(bool) = null,
    deinit_counter: ?*std.atomic.Value(usize) = null,
};

const Spec = struct {
    namespace: ?[]u8,
    projection: *PodProjection,
    poll_interval_ns: u64,
    source_override: ?Source,
    transport_override: ?read_transport.ReadTransport,
    poll_gate: ?*std.atomic.Value(bool),
    deinit_counter: ?*std.atomic.Value(usize),
    generation: keys.Generation = 0,
    subscription_id: keys.SubscriptionId = 0,

    fn bind(raw: ?*anyopaque, generation: keys.Generation, subscription_id: keys.SubscriptionId) void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        self.generation = generation;
        self.subscription_id = subscription_id;
    }

    fn run(raw: ?*anyopaque, control: *lifecycle.ChildControl, io: std.Io) anyerror!void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        var production: ProductionSource = undefined;
        const source = if (self.source_override) |override|
            override
        else blk: {
            var lease = &(control.lease orelse return error.MissingLease);
            production = try ProductionSource.init(
                control.allocator,
                self.namespace,
                self.transport_override,
                try lease.readTransport(io, &control.cancel_requested),
            );
            break :blk production.source();
        };
        defer if (self.source_override == null) production.deinit();

        var revision: keys.Revision = 0;
        while (true) {
            if (self.poll_gate) |gate| {
                while (!gate.load(.acquire)) {
                    if (control.cancel_requested.load(.acquire)) return;
                    std.atomic.spinLoopHint();
                }
            }
            var result = source.poll(control.allocator) catch |err| switch (err) {
                error.Canceled => return error.Canceled,
                error.OutOfMemory => return error.OutOfMemory,
                else => PollResult{ .status = .degraded },
            };
            defer result.deinit(control.allocator);
            revision +|= 1;
            for (result.records) |*record| record.revision = revision;
            const envelope = try makeEnvelope(
                control.allocator,
                self,
                &result,
                revision,
            );
            const delivery = try control.publishDelivery(envelope);
            if (delivery != .accepted) return;
            if (control.cancel_requested.load(.acquire)) return;
            if (self.source_override != null) {
                if (!try source.wait(io, 0)) return;
            }
            var remaining: u64 = self.poll_interval_ns;
            while (remaining > 0) {
                if (control.cancel_requested.load(.acquire)) return;
                const slice = @min(remaining, std.time.ns_per_ms);
                io.sleep(.{ .nanoseconds = slice }, .awake) catch return;
                remaining -= slice;
            }
        }
    }

    fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
        const self: *Spec = @ptrCast(@alignCast(raw orelse return));
        if (self.namespace) |namespace| allocator.free(namespace);
        if (self.deinit_counter) |counter| _ = counter.fetchAdd(1, .acq_rel);
        allocator.destroy(self);
    }
};

pub fn ownedTaskSpec(allocator: std.mem.Allocator, options: Options) !lifecycle.OwnedTaskSpec {
    const spec = try allocator.create(Spec);
    errdefer allocator.destroy(spec);
    const namespace = if (options.namespace) |value| try allocator.dupe(u8, value) else null;
    spec.* = .{
        .namespace = namespace,
        .projection = options.projection,
        .poll_interval_ns = std.math.clamp(
            options.poll_interval_ns,
            min_poll_interval_ns,
            max_poll_interval_ns,
        ),
        .source_override = options.source_override,
        .transport_override = options.transport_override,
        .poll_gate = options.poll_gate,
        .deinit_counter = options.deinit_counter,
    };
    return .{
        .ptr = spec,
        .alignment = .of(Spec),
        .owned_bytes = @sizeOf(Spec) + if (namespace) |value| value.len else 0,
        .lease_purpose = .metrics,
        .bindFn = Spec.bind,
        .runFn = Spec.run,
        .deinitFn = Spec.deinit,
    };
}

fn makeEnvelope(
    allocator: std.mem.Allocator,
    spec: *Spec,
    result: *PollResult,
    revision: keys.Revision,
) !keys.Envelope {
    const batch = try allocator.create(keys.TypedBatch(PodRecord));
    errdefer allocator.destroy(batch);
    const changes = try allocator.alloc(keys.TypedChange(PodRecord), result.records.len);
    errdefer allocator.free(changes);
    var owned_bytes = @sizeOf(@TypeOf(batch.*)) + changes.len * @sizeOf(keys.TypedChange(PodRecord));
    const records = result.records;
    for (records, 0..) |record, index| {
        changes[index] = .{ .metrics = record };
        owned_bytes +|= record.namespace.len + record.name.len;
    }
    result.records = &.{};
    if (records.len > 0) allocator.free(records);
    batch.* = .{
        .generation = spec.generation,
        .subscription_id = spec.subscription_id,
        .revision = revision,
        .changes = changes,
        .sync = .{ .metrics_ready = result.status },
        .owned_bytes = owned_bytes,
    };
    return keys.eraseBatch(
        PodRecord,
        allocator,
        batch,
        PodProjection.metricsHandler(),
        @ptrCast(spec.projection),
    ) catch |err| {
        batch.deinit(allocator);
        allocator.destroy(batch);
        return err;
    };
}

const ProductionSource = struct {
    allocator: std.mem.Allocator,
    transport_adapter: read_transport.TransportAdapter,
    transport_override: ?read_transport.ReadTransport,
    path: []u8,

    fn init(
        allocator: std.mem.Allocator,
        namespace: ?[]const u8,
        transport_override: ?read_transport.ReadTransport,
        transport_adapter: read_transport.TransportAdapter,
    ) !ProductionSource {
        const path = if (namespace) |ns|
            try std.fmt.allocPrint(
                allocator,
                "/apis/metrics.k8s.io/v1beta1/namespaces/{s}/pods",
                .{ns},
            )
        else
            try allocator.dupe(u8, "/apis/metrics.k8s.io/v1beta1/pods");
        errdefer allocator.free(path);
        _ = try read_transport.ReadRequest.init(path);
        return .{
            .allocator = allocator,
            .transport_adapter = transport_adapter,
            .transport_override = transport_override,
            .path = path,
        };
    }

    fn deinit(self: *ProductionSource) void {
        self.allocator.free(self.path);
    }

    fn source(self: *ProductionSource) Source {
        return .{ .context = self, .pollFn = poll, .waitFn = wait };
    }

    fn poll(raw: *anyopaque, allocator: std.mem.Allocator) anyerror!PollResult {
        const self: *ProductionSource = @ptrCast(@alignCast(raw));
        return pollReadTransport(
            allocator,
            self.transport_override orelse self.transport_adapter.transport(),
            self.path,
        );
    }

    fn wait(_: *anyopaque, io: std.Io, delay_ns: u64) anyerror!bool {
        @import("../core/runtime.zig").sleepCancelable(io, @intCast(delay_ns)) catch return false;
        return true;
    }
};

fn pollReadTransport(
    allocator: std.mem.Allocator,
    transport: read_transport.ReadTransport,
    path: []const u8,
) !PollResult {
    const Capture = struct {
        allocator: std.mem.Allocator,
        result: PollResult = .{ .status = .degraded },

        fn receive(
            erased: *anyopaque,
            meta: read_transport.ResponseMeta,
            reader: *std.Io.Reader,
        ) anyerror!void {
            const capture: *@This() = @ptrCast(@alignCast(erased));
            if (meta.status == .not_found or meta.status == .forbidden or
                meta.status == .unauthorized)
            {
                capture.result.status = .unavailable;
                return;
            }
            if (meta.status.class() != .success) {
                capture.result.status = .degraded;
                return;
            }
            var body: std.ArrayList(u8) = .empty;
            defer body.deinit(capture.allocator);
            try reader.appendRemaining(capture.allocator, &body, .limited(max_response_bytes));
            capture.result = parseMetrics(capture.allocator, body.items) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => .{ .status = .degraded },
            };
        }
    };
    var capture = Capture{ .allocator = allocator };
    errdefer capture.result.deinit(allocator);
    try transport.get(try read_transport.ReadRequest.init(path), &capture, Capture.receive);
    return capture.result;
}

fn parseMetrics(allocator: std.mem.Allocator, body: []const u8) !PollResult {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.MalformedMetrics;
    const items = parsed.value.object.get("items") orelse return error.MalformedMetrics;
    if (items != .array) return error.MalformedMetrics;

    var records: std.ArrayList(keys.PodMetricsRecord) = .empty;
    errdefer {
        for (records.items) |*record| record.deinit(allocator);
        records.deinit(allocator);
    }
    var degraded = false;
    for (items.array.items) |item| {
        const record = parseRecord(allocator, item) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                degraded = true;
                continue;
            },
        };
        records.append(allocator, record) catch |err| {
            var owned = record;
            owned.deinit(allocator);
            return err;
        };
    }
    return .{
        .records = try records.toOwnedSlice(allocator),
        .status = if (degraded) .degraded else .available,
    };
}

fn parseRecord(allocator: std.mem.Allocator, value: std.json.Value) !keys.PodMetricsRecord {
    if (value != .object) return error.MalformedMetric;
    const metadata = value.object.get("metadata") orelse return error.MalformedMetric;
    if (metadata != .object) return error.MalformedMetric;
    const name_value = metadata.object.get("name") orelse return error.MalformedMetric;
    const namespace_value = metadata.object.get("namespace") orelse return error.MalformedMetric;
    if (name_value != .string or namespace_value != .string or
        name_value.string.len == 0 or namespace_value.string.len == 0)
    {
        return error.MalformedMetric;
    }
    const containers = value.object.get("containers") orelse return error.MalformedMetric;
    if (containers != .array) return error.MalformedMetric;
    var cpu_milli: u64 = 0;
    var mem_bytes: u64 = 0;
    for (containers.array.items) |container| {
        if (container != .object) return error.MalformedMetric;
        const usage = container.object.get("usage") orelse return error.MalformedMetric;
        if (usage != .object) return error.MalformedMetric;
        const cpu = usage.object.get("cpu") orelse return error.MalformedMetric;
        const memory = usage.object.get("memory") orelse return error.MalformedMetric;
        if (cpu != .string or memory != .string) return error.MalformedMetric;
        cpu_milli = std.math.add(
            u64,
            cpu_milli,
            klient.MetricsClient.parseCpuMillicores(cpu.string) orelse return error.MalformedMetric,
        ) catch return error.MalformedMetric;
        mem_bytes = std.math.add(
            u64,
            mem_bytes,
            klient.MetricsClient.parseMemoryBytes(memory.string) orelse return error.MalformedMetric,
        ) catch return error.MalformedMetric;
    }
    const namespace = try allocator.dupe(u8, namespace_value.string);
    errdefer allocator.free(namespace);
    return .{
        .namespace = namespace,
        .name = try allocator.dupe(u8, name_value.string),
        .cpu_milli = cpu_milli,
        .mem_bytes = mem_bytes,
    };
}

test "parser owns FQN records and skips malformed single items" {
    var result = try parseMetrics(std.testing.allocator,
        \\{"items":[{"metadata":{"namespace":"ns","name":"pod"},"containers":[{"usage":{"cpu":"125m","memory":"4Ki"}}]},{"metadata":{"namespace":"ns"},"containers":[]}]}
    );
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(keys.MetricsStatus.degraded, result.status);
    try std.testing.expectEqual(@as(usize, 1), result.records.len);
    try std.testing.expectEqualStrings("ns", result.records[0].namespace);
    try std.testing.expectEqualStrings("pod", result.records[0].name);
    try std.testing.expectEqual(@as(u64, 125), result.records[0].cpu_milli);
    try std.testing.expectEqual(@as(u64, 4096), result.records[0].mem_bytes);
}

test "owned metrics task selects metrics lease and bounds interval" {
    var projection: PodProjection = undefined;
    var task = try ownedTaskSpec(std.testing.allocator, .{
        .namespace = "ns",
        .projection = &projection,
        .poll_interval_ns = 1,
    });
    defer task.deinit(std.testing.allocator);
    try std.testing.expectEqual(@import("ActiveContextSession.zig").LeasePurpose.metrics, task.lease_purpose);
    const spec: *Spec = @ptrCast(@alignCast(task.ptr.?));
    try std.testing.expectEqual(min_poll_interval_ns, spec.poll_interval_ns);
}

test "GET metrics transport reports missing API and server errors nonfatally" {
    const FakeTransport = @import("FakeTransport.zig").FakeTransport;
    const scripts = [_]@import("FakeTransport.zig").ResponseScript{
        .{ .status = .not_found },
        .{ .status = .forbidden },
        .{ .status = .service_unavailable },
    };
    var fake = FakeTransport.init(std.testing.allocator, &scripts);
    defer fake.deinit();
    const path = "/apis/metrics.k8s.io/v1beta1/pods";
    const expected = [_]keys.MetricsStatus{ .unavailable, .unavailable, .degraded };
    for (expected) |status| {
        var result = try pollReadTransport(std.testing.allocator, fake.transport(), path);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(status, result.status);
        try std.testing.expectEqual(@as(usize, 0), result.records.len);
    }
    try std.testing.expectEqual(@as(usize, 3), fake.requests.items.len);
    for (fake.requests.items) |request| try std.testing.expectEqualStrings(path, request.path);
}

test "transient metrics retry is cancelable and leaves pod subscription active" {
    const runtime = @import("../core/runtime.zig");
    const DataPlane = @import("DataPlane.zig").DataPlane;
    const ChangeQueue = @import("ChangeQueue.zig").ChangeQueue;
    const Supervisor = @import("LifecycleSupervisor.zig").LifecycleSupervisor;
    const active_context = @import("ActiveContextSession.zig");
    const ActiveSessionSlot = @import("ActiveSessionSlot.zig").ActiveSessionSlot;
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
    const Hold = struct {
        fn run(_: ?*anyopaque, control: *lifecycle.ChildControl, task_io: std.Io) anyerror!void {
            while (!control.cancel_requested.load(.acquire)) {
                task_io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake) catch return;
            }
        }
    };
    const Script = struct {
        polls: usize = 0,
        waits: usize = 0,

        fn poll(raw: *anyopaque, _: std.mem.Allocator) anyerror!PollResult {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.polls += 1;
            return error.TransientMetricsFailure;
        }

        fn wait(raw: *anyopaque, task_io: std.Io, delay_ns: u64) anyerror!bool {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.waits += 1;
            try task_io.sleep(.{ .nanoseconds = delay_ns }, .awake);
            return true;
        }
    };
    const Route = struct {
        plane: *DataPlane,
        projection: *PodProjection,
        metrics_key: lifecycle.SubscriptionKey,

        fn target(raw: *anyopaque, target_value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return switch (target_value) {
                .resource => self.plane.resourceTarget(
                    target_value,
                    self.metrics_key,
                    @ptrCast(self.projection),
                ),
                .lifecycle => @ptrCast(self.plane),
                else => null,
            };
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

    var pod_spec = lifecycle.OwnedTaskSpec{ .runFn = Hold.run };
    const pod_key = try plane.startSubscription(1, &pod_spec);
    var script = Script{};
    var destroyed: std.atomic.Value(usize) = .init(0);
    var metrics_spec = try ownedTaskSpec(allocator, .{
        .namespace = "default",
        .projection = &projection,
        .poll_interval_ns = min_poll_interval_ns,
        .source_override = .{
            .context = &script,
            .pollFn = Script.poll,
            .waitFn = Script.wait,
        },
        .deinit_counter = &destroyed,
    });
    const metrics_key = try plane.startSubscription(1, &metrics_spec);
    var route = Route{
        .plane = &plane,
        .projection = &projection,
        .metrics_key = metrics_key,
    };
    var router = keys.UiRouter{ .context = &route, .targetFn = Route.target };

    var applied_boundary = false;
    var attempts: usize = 0;
    while (!applied_boundary and attempts < 100) : (attempts += 1) {
        while (queue.pop()) |value| {
            var envelope = value;
            if (envelope.sync_kind == .metrics_ready) {
                try std.testing.expect(plane.acceptsEnvelope(envelope));
                try envelope.apply(&router, allocator);
                applied_boundary = true;
            } else {
                envelope.deinit(allocator);
            }
        }
        if (!applied_boundary) try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    try std.testing.expect(applied_boundary);
    var wait_attempts: usize = 0;
    while (script.waits == 0 and wait_attempts < 100) : (wait_attempts += 1) {
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    try std.testing.expectEqual(@as(usize, 1), script.polls);
    try std.testing.expectEqual(@as(usize, 1), script.waits);
    try std.testing.expectEqual(@as(usize, 2), plane.activeCount());
    try std.testing.expectEqual(@import("DataPlane.zig").CancelResult.requested, plane.cancelSubscription(metrics_key));
    try std.testing.expectEqual(@as(usize, 1), plane.activeCount());
    try std.testing.expect(plane.cancelSubscription(pod_key) == .requested);

    producer.enqueueShutdown() catch {};
    _ = supervisor.awaitRoot();
    while (queue.pop()) |value| {
        var envelope = value;
        envelope.deinit(allocator);
    }
    try std.testing.expectEqual(@as(usize, 1), destroyed.load(.acquire));
}

fn allocationExercise(allocator: std.mem.Allocator) !void {
    var result = try parseMetrics(allocator,
        \\{"items":[{"metadata":{"namespace":"ns","name":"pod"},"containers":[{"usage":{"cpu":"1","memory":"1Gi"}}]}]}
    );
    defer result.deinit(allocator);
}

test "metrics parsing unwinds every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}
