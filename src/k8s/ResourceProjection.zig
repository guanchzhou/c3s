const std = @import("std");
const age = @import("../viewmodel/age.zig");
const wall_clock = @import("../core/clock.zig");
const keys = @import("ResourceKey.zig");
const PodRecord = @import("PodRecord.zig");

pub const CellKey = struct {
    uid: []const u8,
    object_revision: keys.Revision,
    metrics_revision: keys.Revision,
    column: u16,
    width_generation: u64,
    time_generation: u64,

    fn eql(self: CellKey, other: CellKey) bool {
        return self.object_revision == other.object_revision and
            self.metrics_revision == other.metrics_revision and
            self.column == other.column and
            self.width_generation == other.width_generation and
            self.time_generation == other.time_generation and
            std.mem.eql(u8, self.uid, other.uid);
    }
};

pub const CellCache = struct {
    const Entry = struct {
        key: CellKey,
        value: []u8,
    };

    allocator: std.mem.Allocator,
    capacity: usize,
    entries: std.ArrayListUnmanaged(Entry) = .empty,

    pub fn init(allocator: std.mem.Allocator, capacity: usize) CellCache {
        return .{ .allocator = allocator, .capacity = capacity };
    }

    pub fn deinit(self: *CellCache) void {
        self.clear();
        self.entries.deinit(self.allocator);
    }

    pub fn clear(self: *CellCache) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.key.uid);
            self.allocator.free(entry.value);
        }
        self.entries.clearRetainingCapacity();
    }

    pub fn count(self: *const CellCache) usize {
        return self.entries.items.len;
    }

    pub fn get(self: *CellCache, key: CellKey) ?[]const u8 {
        for (self.entries.items) |entry| {
            if (entry.key.eql(key)) return entry.value;
        }
        return null;
    }

    pub fn put(self: *CellCache, key: CellKey, value: []const u8) ![]const u8 {
        if (self.capacity == 0) return error.CacheDisabled;
        if (self.get(key)) |existing| return existing;

        try self.entries.ensureUnusedCapacity(self.allocator, 1);
        const uid = try self.allocator.dupe(u8, key.uid);
        errdefer self.allocator.free(uid);
        const owned_value = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(owned_value);

        if (self.entries.items.len == self.capacity) {
            const evicted = self.entries.orderedRemove(0);
            self.allocator.free(evicted.key.uid);
            self.allocator.free(evicted.value);
        }
        var owned_key = key;
        owned_key.uid = uid;
        self.entries.appendAssumeCapacity(.{ .key = owned_key, .value = owned_value });
        return owned_value;
    }
};

pub const Clock = struct {
    context: *anyopaque,
    nowFn: *const fn (*anyopaque) i64,

    pub fn now(self: Clock) i64 {
        return self.nowFn(self.context);
    }

    pub fn system() Clock {
        return .{ .context = @ptrFromInt(1), .nowFn = systemNow };
    }

    fn systemNow(_: *anyopaque) i64 {
        return wall_clock.timestamp();
    }
};

pub const RouteResult = enum {
    applied,
    rejected,
};

/// The gate is intentionally generic so App can pass DataPlane without this
/// module owning or inventing an active resource subscription.
pub fn applyAcceptedEnvelope(
    gate: anytype,
    envelope: *keys.Envelope,
    router: *keys.UiRouter,
    allocator: std.mem.Allocator,
) !RouteResult {
    if (!gate.acceptsEnvelope(envelope.*)) {
        envelope.deinit(allocator);
        return .rejected;
    }
    try envelope.apply(router, allocator);
    return .applied;
}

pub fn ResourceProjection(comptime Record: type) type {
    return struct {
        const Self = @This();

        pub const MatchFn = *const fn (*const Record, []const u8) bool;
        pub const SortKeyFn = *const fn (*const Record, u8) []const u8;

        pub const Config = struct {
            matchFn: MatchFn,
            sortKeyFn: SortKeyFn,
            clock: Clock = Clock.system(),
            time_resolution_seconds: u64 = 1,
            cache_capacity: usize = 256,
        };

        pub const Metrics = struct {
            cpu_milli: u64,
            mem_bytes: u64,
            revision: keys.Revision,
        };

        pub const ViewSnapshot = struct {
            allocator: std.mem.Allocator,
            filter_text: []u8,
            visible: std.ArrayListUnmanaged(usize),
            selected_uid: ?[]const u8,
            sort_column: u8,
            sort_ascending: bool,
            consumed: bool = false,

            pub fn deinit(self: *ViewSnapshot, allocator: std.mem.Allocator) void {
                if (self.consumed) return;
                if (self.filter_text.len > 0) allocator.free(self.filter_text);
                self.visible.deinit(allocator);
                self.consumed = true;
            }
        };

        const RecordBox = struct {
            allocator: std.mem.Allocator,
            refs: usize = 1,
            record: Record,
            object_revision: keys.Revision,
            metrics_revision: keys.Revision,
            cpu_milli: u64 = 0,
            mem_bytes: u64 = 0,

            fn release(self: *RecordBox) void {
                std.debug.assert(self.refs > 0);
                self.refs -= 1;
                if (self.refs == 0) {
                    self.record.deinit(self.allocator);
                    self.allocator.destroy(self);
                }
            }
        };

        const Entry = struct {
            uid: []u8,
            box: *RecordBox,
            plan_owned: bool = false,
        };

        const State = struct {
            allocator: std.mem.Allocator,
            entries: std.ArrayListUnmanaged(Entry) = .empty,
            fqn_index: std.ArrayListUnmanaged(usize) = .empty,
            visible: std.ArrayListUnmanaged(usize) = .empty,
            selected_uid: ?[]const u8 = null,
            selection_hint: ?[]u8 = null,
            generation: keys.Generation = 0,
            subscription_id: keys.SubscriptionId = 0,
            revision: keys.Revision = 0,

            fn deinit(self: *State) void {
                for (self.entries.items) |entry| {
                    self.allocator.free(entry.uid);
                    entry.box.release();
                }
                self.entries.deinit(self.allocator);
                self.fqn_index.deinit(self.allocator);
                self.visible.deinit(self.allocator);
                if (self.selection_hint) |hint| self.allocator.free(hint);
                self.* = undefined;
            }
        };

        const Plan = struct {
            state: State,
            committed: bool = false,
            ignored: bool = false,

            fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
                const self: *Plan = @ptrCast(@alignCast(raw orelse return));
                if (!self.committed) {
                    for (self.state.entries.items) |entry| {
                        self.state.allocator.free(entry.uid);
                        if (entry.plan_owned) entry.box.release();
                    }
                    self.state.entries.deinit(self.state.allocator);
                    self.state.fqn_index.deinit(self.state.allocator);
                    self.state.visible.deinit(self.state.allocator);
                    if (self.state.selection_hint) |hint| self.state.allocator.free(hint);
                }
                allocator.destroy(self);
            }
        };

        allocator: std.mem.Allocator,
        config: Config,
        state: State,
        filter_text: []u8 = &.{},
        sort_column: u8 = 0,
        sort_ascending: bool = true,
        width_generation: u64 = 0,
        time_generation: u64 = 0,
        time_bucket: i64,
        cache: CellCache,

        pub fn init(allocator: std.mem.Allocator, config: Config) Self {
            const resolution: i64 = @intCast(@max(config.time_resolution_seconds, 1));
            const now = config.clock.now();
            return .{
                .allocator = allocator,
                .config = config,
                .state = .{ .allocator = allocator },
                .time_bucket = @divFloor(now, resolution),
                .cache = CellCache.init(allocator, config.cache_capacity),
            };
        }

        pub fn deinit(self: *Self) void {
            self.state.deinit();
            if (self.filter_text.len > 0) self.allocator.free(self.filter_text);
            self.cache.deinit();
            self.* = undefined;
        }

        pub fn count(self: *const Self) usize {
            return self.state.entries.items.len;
        }

        pub fn visibleCount(self: *const Self) usize {
            return self.state.visible.items.len;
        }

        pub fn record(self: *const Self, uid: []const u8) ?*const Record {
            const index = findEntry(self.state.entries.items, uid) orelse return null;
            return &self.state.entries.items[index].box.record;
        }

        pub fn objectRevision(self: *const Self, uid: []const u8) ?keys.Revision {
            const index = findEntry(self.state.entries.items, uid) orelse return null;
            return self.state.entries.items[index].box.object_revision;
        }

        pub fn metricsRevision(self: *const Self, uid: []const u8) ?keys.Revision {
            const index = findEntry(self.state.entries.items, uid) orelse return null;
            return self.state.entries.items[index].box.metrics_revision;
        }

        pub fn metricsFor(self: *const Self, uid: []const u8) ?Metrics {
            const index = findEntry(self.state.entries.items, uid) orelse return null;
            const box = self.state.entries.items[index].box;
            return .{
                .cpu_milli = box.cpu_milli,
                .mem_bytes = box.mem_bytes,
                .revision = box.metrics_revision,
            };
        }

        pub fn appliedRevision(self: *const Self) keys.Revision {
            return self.state.revision;
        }

        pub fn visibleUid(self: *const Self, row: usize) ?[]const u8 {
            if (row >= self.state.visible.items.len) return null;
            return self.state.entries.items[self.state.visible.items[row]].uid;
        }

        pub fn selectedUid(self: *const Self) ?[]const u8 {
            return self.state.selected_uid;
        }

        pub fn selectUid(self: *Self, uid: []const u8) bool {
            const index = findEntry(self.state.entries.items, uid) orelse return false;
            if (visibleRow(self.state.visible.items, index) == null) return false;
            const hint = self.allocator.dupe(u8, self.state.entries.items[index].uid) catch return false;
            if (self.state.selection_hint) |old| self.allocator.free(old);
            self.state.selection_hint = hint;
            self.state.selected_uid = self.state.entries.items[index].uid;
            return true;
        }

        pub fn captureView(self: *const Self) !ViewSnapshot {
            const filter_text: []u8 = if (self.filter_text.len > 0)
                try self.allocator.dupe(u8, self.filter_text)
            else
                @constCast(&.{});
            errdefer if (filter_text.len > 0) self.allocator.free(filter_text);
            var visible: std.ArrayListUnmanaged(usize) = .empty;
            errdefer visible.deinit(self.allocator);
            try visible.appendSlice(self.allocator, self.state.visible.items);
            return .{
                .allocator = self.allocator,
                .filter_text = filter_text,
                .visible = visible,
                .selected_uid = self.state.selected_uid,
                .sort_column = self.sort_column,
                .sort_ascending = self.sort_ascending,
            };
        }

        pub fn restoreView(self: *Self, snapshot: *ViewSnapshot) void {
            std.debug.assert(!snapshot.consumed);
            if (self.filter_text.len > 0) self.allocator.free(self.filter_text);
            self.state.visible.deinit(self.allocator);
            self.filter_text = snapshot.filter_text;
            self.state.visible = snapshot.visible;
            self.state.selected_uid = snapshot.selected_uid;
            self.sort_column = snapshot.sort_column;
            self.sort_ascending = snapshot.sort_ascending;
            snapshot.consumed = true;
        }

        /// Rebuilds only derived membership/order. All allocation completes before
        /// filter, sort, selection, or scroll-visible identity changes.
        pub fn setView(self: *Self, filter: []const u8, column: u8, ascending: bool) !void {
            const new_filter: []u8 = if (filter.len == 0)
                &.{}
            else
                try self.allocator.dupe(u8, filter);
            errdefer if (new_filter.len > 0) self.allocator.free(new_filter);

            var visible: std.ArrayListUnmanaged(usize) = .empty;
            errdefer visible.deinit(self.allocator);
            try buildVisible(
                self.config,
                self.state.entries.items,
                filter,
                column,
                ascending,
                self.allocator,
                &visible,
            );
            const old_row = selectedRow(&self.state);
            const selected = chooseSelection(self.state.entries.items, visible.items, self.state.selected_uid, old_row);

            if (self.filter_text.len > 0) self.allocator.free(self.filter_text);
            self.state.visible.deinit(self.state.allocator);
            self.filter_text = new_filter;
            self.state.visible = visible;
            self.state.selected_uid = selected;
            self.sort_column = column;
            self.sort_ascending = ascending;
        }

        pub fn setWidthGeneration(self: *Self, generation: u64) void {
            self.width_generation = generation;
        }

        pub fn refreshTimeGeneration(self: *Self) bool {
            const resolution: i64 = @intCast(@max(self.config.time_resolution_seconds, 1));
            const bucket = @divFloor(self.config.clock.now(), resolution);
            if (bucket == self.time_bucket) return false;
            self.time_bucket = bucket;
            self.time_generation +%= 1;
            return true;
        }

        pub fn cacheKey(self: *const Self, uid: []const u8, column: u16) ?CellKey {
            const index = findEntry(self.state.entries.items, uid) orelse return null;
            const box = self.state.entries.items[index].box;
            return .{
                .uid = uid,
                .object_revision = box.object_revision,
                .metrics_revision = box.metrics_revision,
                .column = column,
                .width_generation = self.width_generation,
                .time_generation = self.time_generation,
            };
        }

        pub fn ageCell(
            self: *Self,
            uid: []const u8,
            timestamp: ?[]const u8,
            column: u16,
        ) ![]const u8 {
            const now = self.config.clock.now();
            const resolution: i64 = @intCast(@max(self.config.time_resolution_seconds, 1));
            const bucket = @divFloor(now, resolution);
            const generation = if (bucket == self.time_bucket)
                self.time_generation
            else
                self.time_generation +% 1;
            const key = self.cacheKeyAt(uid, column, generation) orelse return error.UnknownUid;
            if (self.cache.get(key)) |cached| return cached;

            const created = age.parseTimestampToEpoch(timestamp);
            const seconds: u64 = if (created) |value|
                @intCast(@max(now - value, 0))
            else
                0;
            const formatted = if (created == null)
                try self.allocator.dupe(u8, "n/a")
            else
                try age.formatDuration(self.allocator, seconds);
            defer self.allocator.free(formatted);
            const cached = try self.cache.put(key, formatted);
            self.time_bucket = bucket;
            self.time_generation = generation;
            return cached;
        }

        pub fn handler() *const keys.BatchHandler(Record) {
            return &batch_handler;
        }

        pub fn metricsHandler() *const keys.BatchHandler(Record) {
            return &metrics_batch_handler;
        }

        fn preflight(
            raw: *anyopaque,
            batch: *keys.TypedBatch(Record),
            allocator: std.mem.Allocator,
        ) anyerror!keys.ApplyPlan {
            const self: *Self = @ptrCast(@alignCast(raw));
            const plan = try allocator.create(Plan);
            plan.* = .{ .state = .{ .allocator = allocator } };
            errdefer Plan.deinit(plan, .of(Plan), allocator);

            const new_identity = batch.generation != self.state.generation or
                batch.subscription_id != self.state.subscription_id;
            if (!new_identity and batch.revision <= self.state.revision) {
                plan.ignored = true;
                return .{
                    .scratch = plan,
                    .scratch_alignment = .of(Plan),
                    .revision = batch.revision,
                    .deinitFn = Plan.deinit,
                };
            }

            try plan.state.entries.ensureTotalCapacity(allocator, self.state.entries.items.len + batch.changes.len);
            const replaces_list = if (batch.sync) |sync| switch (sync) {
                .list_started => true,
                else => false,
            } else false;
            const selection_hint = self.state.selected_uid orelse self.state.selection_hint;
            if (selection_hint) |uid| {
                plan.state.selection_hint = try allocator.dupe(u8, uid);
            }
            if (!replaces_list) {
                for (self.state.entries.items) |entry| {
                    const uid = try allocator.dupe(u8, entry.uid);
                    plan.state.entries.appendAssumeCapacity(.{
                        .uid = uid,
                        .box = entry.box,
                        .plan_owned = false,
                    });
                }
            }

            for (batch.changes) |change| switch (change) {
                .initial_upsert, .watch_upsert => |maybe_record| {
                    if (maybe_record) |record_value| {
                        try planUpsert(&plan.state, record_value, batch.revision, allocator);
                    }
                },
                .delete => |key| planDelete(&plan.state, key.uid),
                .metrics => {},
            };
            try buildFqnIndex(&plan.state);
            for (batch.changes) |change| switch (change) {
                .metrics => |metrics| try planMetrics(&plan.state, metrics, allocator),
                else => {},
            };

            try buildVisible(
                self.config,
                plan.state.entries.items,
                self.filter_text,
                self.sort_column,
                self.sort_ascending,
                allocator,
                &plan.state.visible,
            );
            plan.state.selected_uid = chooseSelection(
                plan.state.entries.items,
                plan.state.visible.items,
                plan.state.selection_hint,
                selectedRow(&self.state),
            );
            plan.state.generation = batch.generation;
            plan.state.subscription_id = batch.subscription_id;
            plan.state.revision = batch.revision;
            return .{
                .scratch = plan,
                .scratch_alignment = .of(Plan),
                .revision = batch.revision,
                .deinitFn = Plan.deinit,
            };
        }

        fn commit(
            raw: *anyopaque,
            _: *keys.TypedBatch(Record),
            apply_plan: *keys.ApplyPlan,
        ) void {
            const self: *Self = @ptrCast(@alignCast(raw));
            const plan: *Plan = @ptrCast(@alignCast(apply_plan.scratch.?));
            if (plan.ignored) return;

            for (plan.state.entries.items) |*entry| {
                if (!entry.plan_owned) entry.box.refs +|= 1;
                entry.plan_owned = false;
            }
            var old = self.state;
            self.state = plan.state;
            plan.committed = true;
            old.deinit();
        }

        const batch_handler = keys.BatchHandler(Record){
            .preflight = preflight,
            .commit = commit,
        };

        fn metricsPreflight(
            raw: *anyopaque,
            batch: *keys.TypedBatch(Record),
            allocator: std.mem.Allocator,
        ) anyerror!keys.ApplyPlan {
            const self: *Self = @ptrCast(@alignCast(raw));
            const plan = try allocator.create(Plan);
            plan.* = .{ .state = .{ .allocator = allocator } };
            errdefer Plan.deinit(plan, .of(Plan), allocator);

            try plan.state.entries.ensureTotalCapacity(allocator, self.state.entries.items.len);
            const selection_hint = self.state.selected_uid orelse self.state.selection_hint;
            if (selection_hint) |uid| {
                plan.state.selection_hint = try allocator.dupe(u8, uid);
            }
            for (self.state.entries.items) |entry| {
                plan.state.entries.appendAssumeCapacity(.{
                    .uid = try allocator.dupe(u8, entry.uid),
                    .box = entry.box,
                    .plan_owned = false,
                });
            }
            try buildFqnIndex(&plan.state);
            for (batch.changes) |change| switch (change) {
                .metrics => |metrics| try planMetrics(&plan.state, metrics, allocator),
                else => {},
            };

            try plan.state.visible.appendSlice(allocator, self.state.visible.items);
            plan.state.selected_uid = chooseSelection(
                plan.state.entries.items,
                plan.state.visible.items,
                plan.state.selection_hint,
                selectedRow(&self.state),
            );
            plan.state.generation = self.state.generation;
            plan.state.subscription_id = self.state.subscription_id;
            plan.state.revision = self.state.revision;
            return .{
                .scratch = plan,
                .scratch_alignment = .of(Plan),
                .revision = batch.revision,
                .deinitFn = Plan.deinit,
            };
        }

        const metrics_batch_handler = keys.BatchHandler(Record){
            .preflight = metricsPreflight,
            .commit = commit,
        };

        fn planUpsert(
            state: *State,
            source: Record,
            revision: keys.Revision,
            allocator: std.mem.Allocator,
        ) !void {
            const existing = findEntry(state.entries.items, source.key.uid);
            const uid: ?[]u8 = if (existing == null)
                try allocator.dupe(u8, source.key.uid)
            else
                null;
            errdefer if (uid) |value| allocator.free(value);

            var owned = try source.clone(allocator);
            errdefer owned.deinit(allocator);
            const box = try allocator.create(RecordBox);
            errdefer allocator.destroy(box);
            const next_revision = if (existing) |index|
                @max(revision, state.entries.items[index].box.object_revision +| 1)
            else
                @max(revision, 1);
            const metrics_revision = if (existing) |index|
                state.entries.items[index].box.metrics_revision
            else
                0;
            const cpu_milli = if (existing) |index|
                state.entries.items[index].box.cpu_milli
            else
                0;
            const mem_bytes = if (existing) |index|
                state.entries.items[index].box.mem_bytes
            else
                0;
            box.* = .{
                .allocator = allocator,
                .record = owned,
                .object_revision = next_revision,
                .metrics_revision = metrics_revision,
                .cpu_milli = cpu_milli,
                .mem_bytes = mem_bytes,
            };
            owned = undefined;

            if (existing) |index| {
                const entry = &state.entries.items[index];
                if (entry.plan_owned) entry.box.release();
                entry.box = box;
                entry.plan_owned = true;
                return;
            }
            state.entries.appendAssumeCapacity(.{ .uid = uid.?, .box = box, .plan_owned = true });
        }

        fn planDelete(state: *State, uid: []const u8) void {
            const index = findEntry(state.entries.items, uid) orelse return;
            const removed = state.entries.orderedRemove(index);
            state.allocator.free(removed.uid);
            if (removed.plan_owned) removed.box.release();
        }

        fn planMetrics(
            state: *State,
            metrics: keys.PodMetricsRecord,
            allocator: std.mem.Allocator,
        ) !void {
            const index = resolveFqn(state, metrics.namespace, metrics.name) orelse return;
            const previous = state.entries.items[index].box;
            var owned = try previous.record.clone(allocator);
            errdefer owned.deinit(allocator);
            const box = try allocator.create(RecordBox);
            box.* = .{
                .allocator = allocator,
                .record = owned,
                .object_revision = previous.object_revision,
                .metrics_revision = @max(metrics.revision, previous.metrics_revision +| 1),
                .cpu_milli = metrics.cpu_milli,
                .mem_bytes = metrics.mem_bytes,
            };
            const entry = &state.entries.items[index];
            if (entry.plan_owned) entry.box.release();
            entry.box = box;
            entry.plan_owned = true;
        }

        fn buildFqnIndex(state: *State) !void {
            state.fqn_index.clearRetainingCapacity();
            try state.fqn_index.ensureTotalCapacity(state.allocator, state.entries.items.len);
            for (state.entries.items, 0..) |_, index| state.fqn_index.appendAssumeCapacity(index);
            const Context = struct {
                entries: []const Entry,

                fn lessThan(ctx: @This(), left: usize, right: usize) bool {
                    const a = ctx.entries[left].box.record.key;
                    const b = ctx.entries[right].box.record.key;
                    const namespace_order = std.mem.order(u8, a.namespace, b.namespace);
                    if (namespace_order != .eq) return namespace_order == .lt;
                    const name_order = std.mem.order(u8, a.name, b.name);
                    if (name_order != .eq) return name_order == .lt;
                    return std.mem.order(u8, a.uid, b.uid) == .lt;
                }
            };
            std.sort.pdq(
                usize,
                state.fqn_index.items,
                Context{ .entries = state.entries.items },
                Context.lessThan,
            );
        }

        fn resolveFqn(state: *const State, namespace: []const u8, name: []const u8) ?usize {
            var match: ?usize = null;
            for (state.fqn_index.items) |index| {
                const key = state.entries.items[index].box.record.key;
                if (!std.mem.eql(u8, key.namespace, namespace) or
                    !std.mem.eql(u8, key.name, name))
                {
                    continue;
                }
                if (match != null) return null;
                match = index;
            }
            return match;
        }

        fn buildVisible(
            config: Config,
            entries: []const Entry,
            filter: []const u8,
            column: u8,
            ascending: bool,
            allocator: std.mem.Allocator,
            visible: *std.ArrayListUnmanaged(usize),
        ) !void {
            try visible.ensureTotalCapacity(allocator, entries.len);
            for (entries, 0..) |entry, index| {
                if (filter.len == 0 or config.matchFn(&entry.box.record, filter)) {
                    visible.appendAssumeCapacity(index);
                }
            }
            const Context = struct {
                entries: []const Entry,
                keyFn: SortKeyFn,
                column: u8,
                ascending: bool,

                fn lessThan(ctx: @This(), left: usize, right: usize) bool {
                    const left_key = ctx.keyFn(&ctx.entries[left].box.record, ctx.column);
                    const right_key = ctx.keyFn(&ctx.entries[right].box.record, ctx.column);
                    const order = std.mem.order(u8, left_key, right_key);
                    if (order == .eq) {
                        const uid_order = std.mem.order(u8, ctx.entries[left].uid, ctx.entries[right].uid);
                        return if (ctx.ascending) uid_order == .lt else uid_order == .gt;
                    }
                    return if (ctx.ascending) order == .lt else order == .gt;
                }
            };
            std.sort.pdq(usize, visible.items, Context{
                .entries = entries,
                .keyFn = config.sortKeyFn,
                .column = column,
                .ascending = ascending,
            }, Context.lessThan);
        }

        fn findEntry(entries: []const Entry, uid: []const u8) ?usize {
            for (entries, 0..) |entry, index| {
                if (std.mem.eql(u8, entry.uid, uid)) return index;
            }
            return null;
        }

        fn cacheKeyAt(self: *const Self, uid: []const u8, column: u16, time_generation: u64) ?CellKey {
            const index = findEntry(self.state.entries.items, uid) orelse return null;
            const box = self.state.entries.items[index].box;
            return .{
                .uid = uid,
                .object_revision = box.object_revision,
                .metrics_revision = box.metrics_revision,
                .column = column,
                .width_generation = self.width_generation,
                .time_generation = time_generation,
            };
        }

        fn visibleRow(visible: []const usize, entry_index: usize) ?usize {
            for (visible, 0..) |index, row| {
                if (index == entry_index) return row;
            }
            return null;
        }

        fn selectedRow(state: *const State) ?usize {
            const uid = state.selected_uid orelse return null;
            const index = findEntry(state.entries.items, uid) orelse return null;
            return visibleRow(state.visible.items, index);
        }

        fn chooseSelection(
            entries: []const Entry,
            visible: []const usize,
            selected_uid: ?[]const u8,
            old_row: ?usize,
        ) ?[]const u8 {
            if (selected_uid) |uid| {
                if (findEntry(entries, uid)) |index| {
                    if (visibleRow(visible, index) != null) return entries[index].uid;
                }
            }
            if (visible.len == 0) return null;
            const fallback = @min(old_row orelse 0, visible.len - 1);
            return entries[visible[fallback]].uid;
        }
    };
}

const TestRecord = struct {
    key: keys.ObjectKey,
    value: []u8,

    fn make(allocator: std.mem.Allocator, uid: []const u8, namespace: []const u8, name: []const u8, value: []const u8) !TestRecord {
        const key = try (keys.ObjectKey{ .uid = uid, .namespace = namespace, .name = name }).clone(allocator);
        errdefer {
            var mutable = key;
            mutable.deinit(allocator);
        }
        return .{
            .key = key,
            .value = try allocator.dupe(u8, value),
        };
    }

    pub fn clone(self: TestRecord, allocator: std.mem.Allocator) !TestRecord {
        const key = try self.key.clone(allocator);
        errdefer {
            var mutable = key;
            mutable.deinit(allocator);
        }
        return .{ .key = key, .value = try allocator.dupe(u8, self.value) };
    }

    pub fn deinit(self: *TestRecord, allocator: std.mem.Allocator) void {
        self.key.deinit(allocator);
        allocator.free(self.value);
    }
};

fn testMatch(record: *const TestRecord, filter: []const u8) bool {
    return std.mem.indexOf(u8, record.value, filter) != null;
}

fn testSort(record: *const TestRecord, _: u8) []const u8 {
    return record.value;
}

const Projection = ResourceProjection(TestRecord);

fn applyBatch(projection: *Projection, batch: *keys.TypedBatch(TestRecord), allocator: std.mem.Allocator) !void {
    var plan = try Projection.handler().preflight(@ptrCast(projection), batch, allocator);
    Projection.handler().commit(@ptrCast(projection), batch, &plan);
    plan.deinit(allocator);
}

fn applyMetricsBatch(projection: *Projection, batch: *keys.TypedBatch(TestRecord), allocator: std.mem.Allocator) !void {
    var plan = try Projection.metricsHandler().preflight(@ptrCast(projection), batch, allocator);
    Projection.metricsHandler().commit(@ptrCast(projection), batch, &plan);
    plan.deinit(allocator);
}

fn preflightOnly(
    allocator: std.mem.Allocator,
    projection: *Projection,
    batch: *keys.TypedBatch(TestRecord),
) !void {
    var plan = try Projection.handler().preflight(@ptrCast(projection), batch, allocator);
    plan.deinit(allocator);
}

fn makeBatch(revision: u64, changes: []keys.TypedChange(TestRecord)) keys.TypedBatch(TestRecord) {
    return .{
        .generation = 1,
        .subscription_id = 2,
        .revision = revision,
        .changes = changes,
        .sync = null,
        .owned_bytes = 1,
    };
}

test "upsert delete sorted filtered membership and UID selection stability" {
    const allocator = std.testing.allocator;
    var projection = Projection.init(allocator, .{ .matchFn = testMatch, .sortKeyFn = testSort });
    defer projection.deinit();

    const changes = try allocator.alloc(keys.TypedChange(TestRecord), 3);
    changes[0] = .{ .watch_upsert = try TestRecord.make(allocator, "a", "ns", "a", "charlie") };
    changes[1] = .{ .watch_upsert = try TestRecord.make(allocator, "b", "ns", "b", "alpha") };
    changes[2] = .{ .watch_upsert = try TestRecord.make(allocator, "c", "ns", "c", "bravo") };
    var batch = makeBatch(1, changes);
    defer batch.deinit(allocator);
    try applyBatch(&projection, &batch, allocator);
    try std.testing.expectEqualStrings("b", projection.visibleUid(0).?);
    try std.testing.expect(projection.selectUid("c"));

    const update = try allocator.alloc(keys.TypedChange(TestRecord), 2);
    update[0] = .{ .watch_upsert = try TestRecord.make(allocator, "a", "ns", "a", "aardvark") };
    update[1] = .{ .delete = try (keys.ObjectKey{ .uid = "b", .namespace = "ns", .name = "b" }).clone(allocator) };
    var second = makeBatch(2, update);
    defer second.deinit(allocator);
    try applyBatch(&projection, &second, allocator);
    try std.testing.expectEqualStrings("c", projection.selectedUid().?);
    try projection.setView("br", 0, true);
    try std.testing.expectEqual(@as(usize, 1), projection.visibleCount());
    try std.testing.expectEqualStrings("c", projection.visibleUid(0).?);
}

test "same namespace name with new UID does not inherit selection and fallback is deterministic" {
    const allocator = std.testing.allocator;
    var projection = Projection.init(allocator, .{ .matchFn = testMatch, .sortKeyFn = testSort });
    defer projection.deinit();
    const initial = try allocator.alloc(keys.TypedChange(TestRecord), 2);
    initial[0] = .{ .watch_upsert = try TestRecord.make(allocator, "old", "ns", "pod", "alpha") };
    initial[1] = .{ .watch_upsert = try TestRecord.make(allocator, "keep", "ns", "keep", "beta") };
    var batch = makeBatch(1, initial);
    defer batch.deinit(allocator);
    try applyBatch(&projection, &batch, allocator);
    try std.testing.expect(projection.selectUid("old"));

    const replace = try allocator.alloc(keys.TypedChange(TestRecord), 2);
    replace[0] = .{ .delete = try (keys.ObjectKey{ .uid = "old", .namespace = "ns", .name = "pod" }).clone(allocator) };
    replace[1] = .{ .watch_upsert = try TestRecord.make(allocator, "new", "ns", "pod", "gamma") };
    var second = makeBatch(2, replace);
    defer second.deinit(allocator);
    try applyBatch(&projection, &second, allocator);
    try std.testing.expectEqualStrings("keep", projection.selectedUid().?);
    try projection.setView("gamma", 0, true);
    try std.testing.expectEqualStrings("new", projection.selectedUid().?);
}

test "list_started atomically clears old list and initial chunks repopulate" {
    const allocator = std.testing.allocator;
    var projection = Projection.init(allocator, .{ .matchFn = testMatch, .sortKeyFn = testSort });
    defer projection.deinit();

    const old_changes = try allocator.alloc(keys.TypedChange(TestRecord), 2);
    old_changes[0] = .{ .watch_upsert = try TestRecord.make(allocator, "ghost", "ns", "gone", "alpha") };
    old_changes[1] = .{ .watch_upsert = try TestRecord.make(allocator, "keep", "ns", "keep", "beta") };
    var old_batch = makeBatch(1, old_changes);
    defer old_batch.deinit(allocator);
    try applyBatch(&projection, &old_batch, allocator);
    try std.testing.expect(projection.selectUid("ghost"));

    var boundary = makeBatch(2, &.{});
    boundary.sync = .list_started;
    try applyBatch(&projection, &boundary, allocator);
    try std.testing.expectEqual(@as(usize, 0), projection.count());
    try std.testing.expectEqual(@as(usize, 0), projection.visibleCount());
    try std.testing.expect(projection.selectedUid() == null);

    const initial = try allocator.alloc(keys.TypedChange(TestRecord), 1);
    initial[0] = .{ .initial_upsert = try TestRecord.make(allocator, "keep", "ns", "keep", "updated") };
    var initial_batch = makeBatch(3, initial);
    defer initial_batch.deinit(allocator);
    try applyBatch(&projection, &initial_batch, allocator);
    try std.testing.expectEqual(@as(usize, 1), projection.count());
    try std.testing.expect(projection.record("ghost") == null);
    try std.testing.expectEqualStrings("keep", projection.selectedUid().?);
    try std.testing.expectEqualStrings("updated", projection.record("keep").?.value);
}

test "preflight failure preserves projection and retryable payload while commit allocates nothing" {
    const backing = std.testing.allocator;
    var projection = Projection.init(backing, .{ .matchFn = testMatch, .sortKeyFn = testSort });
    defer projection.deinit();
    const changes = try backing.alloc(keys.TypedChange(TestRecord), 1);
    changes[0] = .{ .watch_upsert = try TestRecord.make(backing, "u", "ns", "pod", "value") };
    var batch = makeBatch(1, changes);
    defer batch.deinit(backing);

    var failing = std.testing.FailingAllocator.init(backing, .{ .fail_index = 0 });
    try std.testing.expectError(
        error.OutOfMemory,
        Projection.handler().preflight(@ptrCast(&projection), &batch, failing.allocator()),
    );
    try std.testing.expectEqual(@as(usize, 0), projection.count());
    try std.testing.expect(batch.changes[0].watch_upsert != null);

    var plan = try Projection.handler().preflight(@ptrCast(&projection), &batch, backing);
    Projection.handler().commit(@ptrCast(&projection), &batch, &plan);
    plan.deinit(backing);
    try std.testing.expectEqual(@as(usize, 1), projection.count());
    try std.testing.expect(batch.changes[0].watch_upsert != null);
}

test "metrics values update repeatedly survive object upsert and unwind allocation failure" {
    const backing = std.testing.allocator;
    var projection = Projection.init(backing, .{ .matchFn = testMatch, .sortKeyFn = testSort });
    defer projection.deinit();
    const changes = try backing.alloc(keys.TypedChange(TestRecord), 1);
    changes[0] = .{ .watch_upsert = try TestRecord.make(backing, "u", "ns", "pod", "one") };
    var batch = makeBatch(1, changes);
    defer batch.deinit(backing);
    try applyBatch(&projection, &batch, backing);

    const first_metrics = try backing.alloc(keys.TypedChange(TestRecord), 1);
    first_metrics[0] = .{ .metrics = .{
        .namespace = try backing.dupe(u8, "ns"),
        .name = try backing.dupe(u8, "pod"),
        .cpu_milli = 125,
        .mem_bytes = 4096,
        .revision = 7,
    } };
    var metrics_batch = makeBatch(2, first_metrics);
    defer metrics_batch.deinit(backing);
    try applyBatch(&projection, &metrics_batch, backing);
    try std.testing.expectEqual(
        Projection.Metrics{ .cpu_milli = 125, .mem_bytes = 4096, .revision = 7 },
        projection.metricsFor("u").?,
    );

    const object_update = try backing.alloc(keys.TypedChange(TestRecord), 1);
    object_update[0] = .{ .watch_upsert = try TestRecord.make(backing, "u", "ns", "pod", "two") };
    var object_batch = makeBatch(3, object_update);
    defer object_batch.deinit(backing);
    try applyBatch(&projection, &object_batch, backing);
    try std.testing.expectEqual(@as(u64, 125), projection.metricsFor("u").?.cpu_milli);
    try std.testing.expectEqual(@as(u64, 4096), projection.metricsFor("u").?.mem_bytes);
    try std.testing.expectEqual(@as(keys.Revision, 7), projection.metricsRevision("u").?);

    const second_metrics = try backing.alloc(keys.TypedChange(TestRecord), 1);
    second_metrics[0] = .{ .metrics = .{
        .namespace = try backing.dupe(u8, "ns"),
        .name = try backing.dupe(u8, "pod"),
        .cpu_milli = 250,
        .mem_bytes = 8192,
        .revision = 8,
    } };
    var second_batch = makeBatch(4, second_metrics);
    defer second_batch.deinit(backing);
    try std.testing.checkAllAllocationFailures(
        backing,
        preflightOnly,
        .{ &projection, &second_batch },
    );
    try std.testing.expectEqual(@as(u64, 125), projection.metricsFor("u").?.cpu_milli);
    try std.testing.expect(second_batch.changes[0].metrics.cpu_milli == 250);

    try applyBatch(&projection, &second_batch, backing);
    try std.testing.expectEqual(
        Projection.Metrics{ .cpu_milli = 250, .mem_bytes = 8192, .revision = 8 },
        projection.metricsFor("u").?,
    );
}

test "metrics FQN resolution skips missing and ambiguous then resolves exact UID later" {
    const allocator = std.testing.allocator;
    var projection = Projection.init(allocator, .{ .matchFn = testMatch, .sortKeyFn = testSort });
    defer projection.deinit();

    const initial = try allocator.alloc(keys.TypedChange(TestRecord), 2);
    initial[0] = .{ .watch_upsert = try TestRecord.make(allocator, "first", "ns", "pod", "alpha") };
    initial[1] = .{ .watch_upsert = try TestRecord.make(allocator, "second", "ns", "pod", "beta") };
    var initial_batch = makeBatch(1, initial);
    defer initial_batch.deinit(allocator);
    try applyBatch(&projection, &initial_batch, allocator);
    try std.testing.expect(projection.selectUid("second"));

    const unresolved = try allocator.alloc(keys.TypedChange(TestRecord), 2);
    unresolved[0] = .{ .metrics = .{
        .namespace = try allocator.dupe(u8, "ns"),
        .name = try allocator.dupe(u8, "pod"),
        .cpu_milli = 10,
        .revision = 1,
    } };
    unresolved[1] = .{ .metrics = .{
        .namespace = try allocator.dupe(u8, "missing"),
        .name = try allocator.dupe(u8, "pod"),
        .cpu_milli = 20,
        .revision = 1,
    } };
    var unresolved_batch = makeBatch(1, unresolved);
    defer unresolved_batch.deinit(allocator);
    try applyMetricsBatch(&projection, &unresolved_batch, allocator);
    try std.testing.expectEqual(@as(keys.Revision, 0), projection.metricsRevision("first").?);
    try std.testing.expectEqual(@as(keys.Revision, 0), projection.metricsRevision("second").?);

    const deletion = try allocator.alloc(keys.TypedChange(TestRecord), 1);
    deletion[0] = .{ .delete = try (keys.ObjectKey{
        .uid = "first",
        .namespace = "ns",
        .name = "pod",
    }).clone(allocator) };
    var deletion_batch = makeBatch(2, deletion);
    defer deletion_batch.deinit(allocator);
    try applyBatch(&projection, &deletion_batch, allocator);

    const before_object_revision = projection.objectRevision("second").?;
    const before_applied_revision = projection.appliedRevision();
    const before_selection = try allocator.dupe(u8, projection.selectedUid().?);
    defer allocator.free(before_selection);
    const old_cache_key = projection.cacheKey("second", 5).?;
    _ = try projection.cache.put(old_cache_key, "old");

    const resolved = try allocator.alloc(keys.TypedChange(TestRecord), 1);
    resolved[0] = .{ .metrics = .{
        .namespace = try allocator.dupe(u8, "ns"),
        .name = try allocator.dupe(u8, "pod"),
        .cpu_milli = 250,
        .mem_bytes = 8192,
        .revision = 2,
    } };
    var resolved_batch = makeBatch(2, resolved);
    defer resolved_batch.deinit(allocator);
    try applyMetricsBatch(&projection, &resolved_batch, allocator);

    try std.testing.expectEqual(@as(u64, 250), projection.metricsFor("second").?.cpu_milli);
    try std.testing.expectEqual(before_object_revision, projection.objectRevision("second").?);
    try std.testing.expectEqual(before_applied_revision, projection.appliedRevision());
    try std.testing.expectEqualStrings(before_selection, projection.selectedUid().?);
    try std.testing.expect(projection.cache.get(projection.cacheKey("second", 5).?) == null);
}

test "stale revisions are ignored and duplicate UID in accepted batch is last write" {
    const allocator = std.testing.allocator;
    var projection = Projection.init(allocator, .{ .matchFn = testMatch, .sortKeyFn = testSort });
    defer projection.deinit();
    const first = try allocator.alloc(keys.TypedChange(TestRecord), 1);
    first[0] = .{ .watch_upsert = try TestRecord.make(allocator, "u", "ns", "pod", "current") };
    var first_batch = makeBatch(5, first);
    defer first_batch.deinit(allocator);
    try applyBatch(&projection, &first_batch, allocator);

    const stale = try allocator.alloc(keys.TypedChange(TestRecord), 1);
    stale[0] = .{ .watch_upsert = try TestRecord.make(allocator, "u", "ns", "pod", "stale") };
    var stale_batch = makeBatch(4, stale);
    defer stale_batch.deinit(allocator);
    try applyBatch(&projection, &stale_batch, allocator);
    try std.testing.expectEqual(@as(keys.Revision, 5), projection.appliedRevision());
    try std.testing.expectEqualStrings("current", projection.record("u").?.value);
    try std.testing.expect(stale_batch.changes[0].watch_upsert != null);

    const duplicate = try allocator.alloc(keys.TypedChange(TestRecord), 2);
    duplicate[0] = .{ .watch_upsert = try TestRecord.make(allocator, "u", "ns", "pod", "first") };
    duplicate[1] = .{ .watch_upsert = try TestRecord.make(allocator, "u", "ns", "pod", "last") };
    var duplicate_batch = makeBatch(6, duplicate);
    defer duplicate_batch.deinit(allocator);
    try applyBatch(&projection, &duplicate_batch, allocator);
    try std.testing.expectEqualStrings("last", projection.record("u").?.value);
}

test "cache key generations invalidate and bounded eviction works" {
    const allocator = std.testing.allocator;
    var projection = Projection.init(allocator, .{
        .matchFn = testMatch,
        .sortKeyFn = testSort,
        .cache_capacity = 2,
    });
    defer projection.deinit();
    const changes = try allocator.alloc(keys.TypedChange(TestRecord), 1);
    changes[0] = .{ .watch_upsert = try TestRecord.make(allocator, "u", "ns", "pod", "value") };
    var batch = makeBatch(1, changes);
    defer batch.deinit(allocator);
    try applyBatch(&projection, &batch, allocator);

    const first = projection.cacheKey("u", 1).?;
    _ = try projection.cache.put(first, "one");
    projection.setWidthGeneration(1);
    const width = projection.cacheKey("u", 1).?;
    try std.testing.expect(projection.cache.get(width) == null);
    _ = try projection.cache.put(width, "two");
    projection.time_generation = 1;
    const timed = projection.cacheKey("u", 1).?;
    _ = try projection.cache.put(timed, "three");
    try std.testing.expectEqual(@as(usize, 2), projection.cache.count());
    try std.testing.expect(projection.cache.get(first) == null);

    const metrics_changes = try allocator.alloc(keys.TypedChange(TestRecord), 1);
    metrics_changes[0] = .{ .metrics = .{
        .namespace = try allocator.dupe(u8, "ns"),
        .name = try allocator.dupe(u8, "pod"),
        .revision = 5,
    } };
    var metrics_batch = makeBatch(2, metrics_changes);
    defer metrics_batch.deinit(allocator);
    try applyBatch(&projection, &metrics_batch, allocator);
    try std.testing.expect(projection.cache.get(projection.cacheKey("u", 1).?) == null);

    const object_changes = try allocator.alloc(keys.TypedChange(TestRecord), 1);
    object_changes[0] = .{ .watch_upsert = try TestRecord.make(allocator, "u", "ns", "pod", "next") };
    var object_batch = makeBatch(3, object_changes);
    defer object_batch.deinit(allocator);
    const before = projection.objectRevision("u").?;
    try applyBatch(&projection, &object_batch, allocator);
    try std.testing.expect(projection.objectRevision("u").? > before);
}

test "time bucket changes AGE without Kubernetes data changes" {
    const allocator = std.testing.allocator;
    var now: i64 = 1704067201;
    const FakeClock = struct {
        fn read(raw: *anyopaque) i64 {
            const value: *i64 = @ptrCast(@alignCast(raw));
            return value.*;
        }
    };
    var projection = Projection.init(allocator, .{
        .matchFn = testMatch,
        .sortKeyFn = testSort,
        .clock = .{ .context = @ptrCast(&now), .nowFn = FakeClock.read },
    });
    defer projection.deinit();
    const changes = try allocator.alloc(keys.TypedChange(TestRecord), 1);
    changes[0] = .{ .watch_upsert = try TestRecord.make(allocator, "u", "ns", "pod", "value") };
    var batch = makeBatch(1, changes);
    defer batch.deinit(allocator);
    try applyBatch(&projection, &batch, allocator);
    try std.testing.expectEqualStrings("1s", try projection.ageCell("u", "2024-01-01T00:00:00Z", 1));
    now = 1704067202;
    try std.testing.expectEqualStrings("2s", try projection.ageCell("u", "2024-01-01T00:00:00Z", 1));
    try std.testing.expectEqual(@as(keys.Revision, 1), projection.objectRevision("u").?);
}

test "AGE cache failure does not publish prospective time generation" {
    const backing = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(backing, .{});
    const allocator = failing.allocator();
    var now: i64 = 1704067201;
    const FakeClock = struct {
        fn read(raw: *anyopaque) i64 {
            const value: *i64 = @ptrCast(@alignCast(raw));
            return value.*;
        }
    };
    var projection = Projection.init(allocator, .{
        .matchFn = testMatch,
        .sortKeyFn = testSort,
        .clock = .{ .context = @ptrCast(&now), .nowFn = FakeClock.read },
    });
    defer projection.deinit();
    const changes = try allocator.alloc(keys.TypedChange(TestRecord), 1);
    changes[0] = .{ .watch_upsert = try TestRecord.make(allocator, "u", "ns", "pod", "value") };
    var batch = makeBatch(1, changes);
    defer batch.deinit(allocator);
    try applyBatch(&projection, &batch, allocator);
    try std.testing.expectEqualStrings("1s", try projection.ageCell("u", "2024-01-01T00:00:00Z", 1));

    const old_bucket = projection.time_bucket;
    const old_generation = projection.time_generation;
    const old_key = projection.cacheKey("u", 1).?;
    const old_count = projection.cache.count();
    now += 1;
    failing.fail_index = failing.alloc_index;
    try std.testing.expectError(
        error.OutOfMemory,
        projection.ageCell("u", "2024-01-01T00:00:00Z", 1),
    );
    try std.testing.expectEqual(old_bucket, projection.time_bucket);
    try std.testing.expectEqual(old_generation, projection.time_generation);
    try std.testing.expectEqual(old_count, projection.cache.count());
    try std.testing.expectEqualStrings("1s", projection.cache.get(old_key).?);
}

fn podMatch(record: *const PodRecord, filter: []const u8) bool {
    return std.mem.indexOf(u8, record.key.name, filter) != null;
}

fn podSort(record: *const PodRecord, _: u8) []const u8 {
    return record.key.name;
}

test "production PodRecord projection exposes metrics and handler API" {
    const allocator = std.testing.allocator;
    const PodProjection = ResourceProjection(PodRecord);
    var projection = PodProjection.init(allocator, .{ .matchFn = podMatch, .sortKeyFn = podSort });
    defer projection.deinit();

    const changes = try allocator.alloc(keys.TypedChange(PodRecord), 2);
    changes[0] = .{ .initial_upsert = PodRecord{
        .key = try (keys.ObjectKey{ .uid = "pod-uid", .namespace = "ns", .name = "pod" }).clone(allocator),
    } };
    changes[1] = .{ .metrics = .{
        .namespace = try allocator.dupe(u8, "ns"),
        .name = try allocator.dupe(u8, "pod"),
        .cpu_milli = 333,
        .mem_bytes = 16 * 1024,
        .revision = 9,
    } };
    var batch = keys.TypedBatch(PodRecord){
        .generation = 1,
        .subscription_id = 2,
        .revision = 1,
        .changes = changes,
        .sync = null,
        .owned_bytes = 1,
    };
    defer batch.deinit(allocator);
    var plan = try PodProjection.handler().preflight(@ptrCast(&projection), &batch, allocator);
    PodProjection.handler().commit(@ptrCast(&projection), &batch, &plan);
    plan.deinit(allocator);
    try std.testing.expectEqual(@as(u64, 333), projection.metricsFor("pod-uid").?.cpu_milli);
    try std.testing.expectEqual(@as(u64, 16 * 1024), projection.metricsFor("pod-uid").?.mem_bytes);
    try std.testing.expectEqualStrings("pod", projection.record("pod-uid").?.key.name);
}

test "routing seam rejects wrong subscription before envelope apply" {
    const allocator = std.testing.allocator;
    const Gate = struct {
        fn acceptsEnvelope(_: *@This(), envelope: keys.Envelope) bool {
            const identity = envelope.target.resource;
            return identity.generation == 7 and identity.subscription_id == 9;
        }
    };
    const targetFn = struct {
        fn target(context: *anyopaque, _: keys.EnvelopeTarget) ?*anyopaque {
            return context;
        }
    }.target;
    var gate = Gate{};
    var router = keys.UiRouter{ .context = @ptrCast(&gate), .targetFn = targetFn };
    const payload = try allocator.create(u8);
    payload.* = 1;
    var envelope = try keys.erasePayload(
        u8,
        allocator,
        .{ .resource = .{ .generation = 7, .subscription_id = 8 } },
        payload,
        &keys.test_noop_u8_handler,
        7,
        8,
        1,
        1,
        null,
    );
    try std.testing.expectEqual(RouteResult.rejected, try applyAcceptedEnvelope(&gate, &envelope, &router, allocator));
    try std.testing.expectEqual(keys.Envelope.State.consumed, envelope.state);
}

fn allocationExercise(allocator: std.mem.Allocator) !void {
    var projection = Projection.init(allocator, .{ .matchFn = testMatch, .sortKeyFn = testSort });
    defer projection.deinit();
    const changes = try allocator.alloc(keys.TypedChange(TestRecord), 2);
    var initialized: usize = 0;
    var batch_owns_changes = false;
    errdefer {
        if (!batch_owns_changes) {
            for (changes[0..initialized]) |*change| change.deinit(allocator);
            allocator.free(changes);
        }
    }
    changes[0] = .{ .watch_upsert = try TestRecord.make(allocator, "a", "ns", "a", "alpha") };
    initialized += 1;
    changes[1] = .{ .watch_upsert = try TestRecord.make(allocator, "b", "ns", "b", "beta") };
    initialized += 1;
    var batch = makeBatch(1, changes);
    batch_owns_changes = true;
    defer batch.deinit(allocator);
    try applyBatch(&projection, &batch, allocator);
    try projection.setView("a", 0, true);
    _ = try projection.ageCell("a", "2024-01-01T00:00:00Z", 1);
}

test "projection allocation paths are leak safe" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationExercise, .{});
}
