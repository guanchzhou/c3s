const std = @import("std");
const lifecycle = @import("LifecycleInbox.zig");
const keys = @import("ResourceKey.zig");

pub const Request = enum { none, start, restart };

pub const Entry = struct {
    name: []const u8,
    projection: *anyopaque,
    view: *anyopaque,
    active: ?lifecycle.SubscriptionKey = null,
    restart_pending: bool = false,
    enabledFn: *const fn () bool,
    takeRequestFn: *const fn (*anyopaque) Request,
    markStartedFn: *const fn (*anyopaque) void,
    markStoppedFn: *const fn (*anyopaque) void,
    allNamespacesFn: *const fn (*anyopaque) bool,
    syncFn: *const fn (*anyopaque) anyerror!void,
    taskSpecFn: *const fn (
        std.mem.Allocator,
        []const u8,
        ?[]const u8,
        *anyopaque,
    ) anyerror!lifecycle.OwnedTaskSpec,

    pub fn init(
        comptime Record: type,
        comptime Subscription: type,
        comptime ViewType: type,
        name: []const u8,
        projection: *@import("ResourceProjection.zig").ResourceProjection(Record),
        view: *ViewType,
        comptime enabled_fn: fn () bool,
    ) Entry {
        const SubscriptionType = Subscription;
        const Adapter = struct {
            fn typedView(raw: *anyopaque) *ViewType {
                return @ptrCast(@alignCast(raw));
            }

            fn takeRequest(raw: *anyopaque) Request {
                return switch (typedView(raw).takeSubscriptionRequest()) {
                    .none => .none,
                    .start => .start,
                    .restart => .restart,
                };
            }

            fn markStarted(raw: *anyopaque) void {
                typedView(raw).markSubscriptionStarted();
            }

            fn markStopped(raw: *anyopaque) void {
                typedView(raw).markSubscriptionStopped();
            }

            fn allNamespaces(raw: *anyopaque) bool {
                return !ViewType.view_config.is_namespaced or
                    typedView(raw).table.show_all_namespaces;
            }

            fn sync(raw: *anyopaque) anyerror!void {
                try typedView(raw).syncProjection();
            }

            fn taskSpec(
                allocator: std.mem.Allocator,
                context_name: []const u8,
                scope_namespace: ?[]const u8,
                raw_projection: *anyopaque,
            ) anyerror!lifecycle.OwnedTaskSpec {
                const Projection = @import("ResourceProjection.zig").ResourceProjection(Record);
                const typed_projection: *Projection = @ptrCast(@alignCast(raw_projection));
                return SubscriptionType.ownedTaskSpec(allocator, .{
                    .context_name = context_name,
                    .namespace = scope_namespace,
                    .projection = typed_projection,
                });
            }
        };
        return .{
            .name = name,
            .projection = @ptrCast(projection),
            .view = @ptrCast(view),
            .enabledFn = enabled_fn,
            .takeRequestFn = Adapter.takeRequest,
            .markStartedFn = Adapter.markStarted,
            .markStoppedFn = Adapter.markStopped,
            .allNamespacesFn = Adapter.allNamespaces,
            .syncFn = Adapter.sync,
            .taskSpecFn = Adapter.taskSpec,
        };
    }

    pub fn takeRequest(self: *Entry) Request {
        if (!self.enabledFn()) return .none;
        return self.takeRequestFn(self.view);
    }

    pub fn namespace(self: *const Entry, current_namespace: []const u8) ?[]const u8 {
        return if (self.allNamespacesFn(self.view)) null else current_namespace;
    }

    pub fn enabled(self: *const Entry) bool {
        return self.enabledFn();
    }

    pub fn markStarted(self: *Entry, active: lifecycle.SubscriptionKey) void {
        self.active = active;
        self.markStartedFn(self.view);
    }

    pub fn markStopped(self: *Entry) void {
        self.active = null;
        self.markStoppedFn(self.view);
    }
};

pub const Registry = struct {
    entries: []Entry,
    entries_source: ?*std.ArrayListUnmanaged(Entry) = null,

    pub fn initDynamic(source: *std.ArrayListUnmanaged(Entry)) Registry {
        return .{
            .entries = source.items,
            .entries_source = source,
        };
    }

    pub fn rebind(self: *Registry) void {
        if (self.entries_source) |source| self.entries = source.items;
    }

    pub fn items(self: *Registry) []Entry {
        self.rebind();
        return self.entries;
    }

    pub fn itemsConst(self: *const Registry) []const Entry {
        return if (self.entries_source) |source| source.items else self.entries;
    }

    pub fn entryAt(self: *Registry, index: usize) ?*Entry {
        const current = self.items();
        if (index >= current.len) return null;
        return &current[index];
    }

    pub fn contains(self: *const Registry, identity: keys.ResourceIdentity) bool {
        return self.find(identity) != null;
    }

    pub fn projectionFor(self: *Registry, identity: keys.ResourceIdentity) ?*anyopaque {
        const index = self.find(identity) orelse return null;
        return self.entryAt(index).?.projection;
    }

    pub fn activeKeyFor(
        self: *const Registry,
        identity: keys.ResourceIdentity,
    ) ?lifecycle.SubscriptionKey {
        const index = self.find(identity) orelse return null;
        return self.itemsConst()[index].active;
    }

    pub fn sync(self: *Registry, identity: keys.ResourceIdentity) !bool {
        const index = self.find(identity) orelse return false;
        const entry = self.entryAt(index).?;
        try entry.syncFn(entry.view);
        return true;
    }

    pub fn markForContextRestart(self: *Registry) void {
        for (self.items()) |*entry| {
            entry.restart_pending = entry.active != null;
        }
    }

    pub fn hasActive(self: *const Registry) bool {
        for (self.itemsConst()) |entry| if (entry.active != null) return true;
        return false;
    }

    pub fn complete(
        self: *Registry,
        identity: ?keys.ResourceIdentity,
        completion: lifecycle.LifecycleCompletion,
    ) ?usize {
        switch (completion) {
            .subscription_stopped, .start_rejected => {},
            else => return null,
        }
        const exact = identity orelse return null;
        const index = self.find(exact) orelse return null;
        self.entryAt(index).?.markStopped();
        return index;
    }

    fn find(self: *const Registry, identity: keys.ResourceIdentity) ?usize {
        for (self.itemsConst(), 0..) |entry, index| {
            const active = entry.active orelse continue;
            if (active.generation == identity.generation and
                active.subscription_id == identity.subscription_id)
                return index;
        }
        return null;
    }
};

test "dynamic registry rebind survives entry buffer reallocation" {
    const Probe = struct {
        request: Request = .start,

        fn enabled() bool {
            return true;
        }

        fn take(raw: *anyopaque) Request {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return self.request;
        }

        fn mark(_: *anyopaque) void {}
    };
    var probe = Probe{};
    const template = Entry{
        .name = "entry",
        .projection = @ptrCast(&probe),
        .view = @ptrCast(&probe),
        .enabledFn = Probe.enabled,
        .takeRequestFn = Probe.take,
        .markStartedFn = Probe.mark,
        .markStoppedFn = Probe.mark,
        .allNamespacesFn = undefined,
        .syncFn = undefined,
        .taskSpecFn = undefined,
    };
    var storage: std.ArrayListUnmanaged(Entry) = .empty;
    defer storage.deinit(std.testing.allocator);
    try storage.ensureTotalCapacity(std.testing.allocator, 1);
    try storage.append(std.testing.allocator, template);
    var registry = Registry.initDynamic(&storage);
    registry.rebind();
    registry.entryAt(0).?.active = .{ .generation = 11, .subscription_id = 17 };
    const original_pointer = storage.items.ptr;
    var reallocated = false;
    while (storage.items.len < 128) {
        try storage.append(std.testing.allocator, template);
        registry.rebind();
        if (storage.items.ptr != original_pointer) {
            reallocated = true;
            break;
        }
    }
    try std.testing.expect(reallocated);
    try std.testing.expect(registry.contains(.{ .generation = 11, .subscription_id = 17 }));
    try std.testing.expectEqual(Request.start, registry.entryAt(0).?.takeRequest());
}

test "family registry matches and completes only exact identities" {
    var entries = [_]Entry{undefined};
    var registry = Registry{ .entries = &entries };
    const key = lifecycle.SubscriptionKey{ .generation = 7, .subscription_id = 9 };
    entries[0].active = key;
    entries[0].view = undefined;
    entries[0].enabledFn = struct {
        fn call() bool {
            return true;
        }
    }.call;
    entries[0].markStoppedFn = struct {
        fn call(_: *anyopaque) void {}
    }.call;
    try std.testing.expect(registry.contains(.{ .generation = 7, .subscription_id = 9 }));
    const unrelated_pod = keys.ResourceIdentity{ .generation = 7, .subscription_id = 8 };
    try std.testing.expect(!registry.contains(unrelated_pod));
    try std.testing.expect(registry.complete(.{
        .generation = 7,
        .subscription_id = 8,
    }, .{ .subscription_stopped = .{ .key = key, .detail = null } }) == null);
    try std.testing.expectEqual(@as(?usize, 0), registry.complete(.{
        .generation = 7,
        .subscription_id = 9,
    }, .{ .subscription_stopped = .{ .key = key, .detail = null } }));
    try std.testing.expect(!registry.hasActive());
}

fn exerciseEntryScope(
    comptime Record: type,
    comptime Subscription: type,
    comptime ViewType: type,
    comptime columns_count: usize,
) !void {
    const Projection = @import("ResourceProjection.zig").ResourceProjection(Record);
    const K8sService = @import("../services/K8sService.zig").K8sService;
    const Theme = @import("../model/theme_loader.zig").ThemeColors;
    const Fns = struct {
        fn match(_: *const Record, _: []const u8) bool {
            return true;
        }
        fn sort(record: *const Record, _: u8) []const u8 {
            return record.key.name;
        }
        fn enabled() bool {
            return true;
        }
        fn columns(
            _: *Projection,
            record: *const Record,
            allocator: std.mem.Allocator,
        ) ![columns_count][]const u8 {
            return record.columns(allocator);
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
    var entry = Entry.init(
        Record,
        Subscription,
        ViewType,
        ViewType.view_config.name,
        &projection,
        &view,
        Fns.enabled,
    );
    try std.testing.expectEqual(
        ViewType.view_config.default_all_namespaces,
        view.table.show_all_namespaces,
    );
    view.table.show_all_namespaces = false;
    if (ViewType.view_config.is_namespaced) {
        try std.testing.expectEqualStrings("team-a", entry.namespace("team-a").?);
    } else {
        try std.testing.expect(entry.namespace("team-a") == null);
    }
    var namespaced_spec = try entry.taskSpecFn(
        std.testing.allocator,
        "context",
        entry.namespace("team-a"),
        entry.projection,
    );
    defer namespaced_spec.deinit(std.testing.allocator);

    view.table.show_all_namespaces = true;
    try std.testing.expect(entry.namespace("team-a") == null);
    var all_namespaces_spec = try entry.taskSpecFn(
        std.testing.allocator,
        "context",
        entry.namespace("team-a"),
        entry.projection,
    );
    defer all_namespaces_spec.deinit(std.testing.allocator);
    if (ViewType.view_config.is_namespaced) {
        try std.testing.expectEqual(
            all_namespaces_spec.owned_bytes + "team-a".len,
            namespaced_spec.owned_bytes,
        );
    } else {
        try std.testing.expectEqual(all_namespaces_spec.owned_bytes, namespaced_spec.owned_bytes);
    }
}

test "production family entries map all namespace scope to null task specs" {
    const klient = @import("klient");
    const SubscriptionFactory = @import("ResourceSubscription.zig").ResourceSubscription;
    const configs = @import("../view/resource_configs.zig");
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
    try exerciseEntryScope(
        ServiceRecord,
        SubscriptionFactory(klient.Service, ServiceRecord, ServiceRecord.fromService),
        configs.ServicesView,
        7,
    );
    try exerciseEntryScope(
        EndpointRecord,
        SubscriptionFactory(klient.Endpoints, EndpointRecord, EndpointRecord.fromEndpoints),
        configs.EndpointsView,
        4,
    );
    try exerciseEntryScope(
        EndpointSliceRecord,
        SubscriptionFactory(klient.EndpointSlice, EndpointSliceRecord, EndpointSliceRecord.fromEndpointSlice),
        configs.EndpointSlicesView,
        5,
    );
    try exerciseEntryScope(
        ConfigMapRecord,
        SubscriptionFactory(klient.ConfigMap, ConfigMapRecord, ConfigMapRecord.fromConfigMap),
        configs.ConfigMapsView,
        4,
    );
    try exerciseEntryScope(
        SecretRecord,
        SubscriptionFactory(klient.Secret, SecretRecord, SecretRecord.fromSecret),
        configs.SecretsView,
        5,
    );
    try exerciseEntryScope(
        ServiceAccountRecord,
        SubscriptionFactory(klient.ServiceAccount, ServiceAccountRecord, ServiceAccountRecord.fromServiceAccount),
        configs.ServiceAccountsView,
        4,
    );
    try exerciseEntryScope(
        ResourceQuotaRecord,
        SubscriptionFactory(klient.ResourceQuota, ResourceQuotaRecord, ResourceQuotaRecord.fromResourceQuota),
        configs.ResourceQuotasView,
        3,
    );
    try exerciseEntryScope(
        LimitRangeRecord,
        SubscriptionFactory(klient.LimitRange, LimitRangeRecord, LimitRangeRecord.fromLimitRange),
        configs.LimitRangesView,
        3,
    );
    try exerciseEntryScope(
        DeploymentRecord,
        SubscriptionFactory(klient.Deployment, DeploymentRecord, DeploymentRecord.fromDeployment),
        configs.DeploymentsView,
        6,
    );
    try exerciseEntryScope(
        StatefulSetRecord,
        SubscriptionFactory(klient.StatefulSet, StatefulSetRecord, StatefulSetRecord.fromStatefulSet),
        configs.StatefulSetsView,
        4,
    );
    try exerciseEntryScope(
        DaemonSetRecord,
        SubscriptionFactory(klient.DaemonSet, DaemonSetRecord, DaemonSetRecord.fromDaemonSet),
        configs.DaemonSetsView,
        7,
    );
    try exerciseEntryScope(
        ReplicaSetRecord,
        SubscriptionFactory(klient.ReplicaSet, ReplicaSetRecord, ReplicaSetRecord.fromReplicaSet),
        configs.ReplicaSetsView,
        6,
    );
    try exerciseEntryScope(
        JobRecord,
        SubscriptionFactory(klient.Job, JobRecord, JobRecord.fromJob),
        configs.JobsView,
        5,
    );
    try exerciseEntryScope(
        CronJobRecord,
        SubscriptionFactory(klient.CronJob, CronJobRecord, CronJobRecord.fromCronJob),
        configs.CronJobsView,
        6,
    );
    try exerciseEntryScope(
        HPARecord,
        SubscriptionFactory(klient.HorizontalPodAutoscaler, HPARecord, HPARecord.fromHorizontalPodAutoscaler),
        configs.HPAView,
        6,
    );
    try exerciseEntryScope(
        PDBRecord,
        SubscriptionFactory(klient.PodDisruptionBudget, PDBRecord, PDBRecord.fromPodDisruptionBudget),
        configs.PodDisruptionBudgetsView,
        6,
    );
    try exerciseEntryScope(
        IngressRecord,
        SubscriptionFactory(klient.types.Ingress, IngressRecord, IngressRecord.fromIngress),
        configs.IngressesView,
        7,
    );
    try exerciseEntryScope(
        IngressClassRecord,
        SubscriptionFactory(klient.IngressClass, IngressClassRecord, IngressClassRecord.fromIngressClass),
        configs.IngressClassesView,
        3,
    );
    try exerciseEntryScope(
        NetworkPolicyRecord,
        SubscriptionFactory(klient.NetworkPolicy, NetworkPolicyRecord, NetworkPolicyRecord.fromNetworkPolicy),
        configs.NetworkPoliciesView,
        4,
    );
    try exerciseEntryScope(
        IPAddressRecord,
        SubscriptionFactory(klient.IPAddress, IPAddressRecord, IPAddressRecord.fromIPAddress),
        configs.IPAddressesView,
        3,
    );
    try exerciseEntryScope(
        ServiceCIDRRecord,
        SubscriptionFactory(klient.ServiceCIDR, ServiceCIDRRecord, ServiceCIDRRecord.fromServiceCIDR),
        configs.ServiceCIDRsView,
        3,
    );
    try exerciseEntryScope(
        PVRecord,
        SubscriptionFactory(klient.PersistentVolume, PVRecord, PVRecord.fromPersistentVolume),
        configs.PersistentVolumesView,
        8,
    );
    try exerciseEntryScope(
        PVCRecord,
        SubscriptionFactory(klient.PersistentVolumeClaim, PVCRecord, PVCRecord.fromPersistentVolumeClaim),
        configs.PersistentVolumeClaimsView,
        8,
    );
    try exerciseEntryScope(
        StorageClassRecord,
        SubscriptionFactory(klient.StorageClass, StorageClassRecord, StorageClassRecord.fromStorageClass),
        configs.StorageClassesView,
        6,
    );
    try exerciseEntryScope(
        VolumeAttributesClassRecord,
        SubscriptionFactory(klient.VolumeAttributesClass, VolumeAttributesClassRecord, VolumeAttributesClassRecord.fromVolumeAttributesClass),
        configs.VolumeAttributesClassesView,
        3,
    );
    try exerciseEntryScope(
        CSIDriverRecord,
        SubscriptionFactory(klient.CSIDriver, CSIDriverRecord, CSIDriverRecord.fromCSIDriver),
        configs.CSIDriversView,
        4,
    );
}
