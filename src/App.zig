const std = @import("std");
const posix = std.posix;
const terminal = @import("core/Terminal.zig");
const runtime = @import("core/runtime.zig");
const clock = @import("core/clock.zig");
const Terminal = terminal.Terminal;
const Key = terminal.Key;
const Header = @import("ui/Header.zig").Header;
const Footer = @import("ui/Footer.zig").Footer;
const CommandInput = @import("ui/CommandInput.zig").CommandInput;
const Theme = theme_loader;
const BoxDrawing = @import("ui/box_drawing.zig");
const Cli = @import("cli.zig");
const Config = @import("model/config.zig");
const Logger = @import("core/logger.zig");
const PerfTelemetry = @import("core/perf_telemetry.zig").PerfTelemetry;
const perf = @import("core/perf_telemetry.zig");
const Wakeup = @import("core/Wakeup.zig").Wakeup;
const sys = @import("core/sys.zig");
const ChangeQueue = @import("k8s/ChangeQueue.zig").ChangeQueue;
const resource_key = @import("k8s/ResourceKey.zig");
const lifecycle = @import("k8s/LifecycleInbox.zig");
const lifecycle_supervisor = @import("k8s/LifecycleSupervisor.zig");
const data_plane_mod = @import("k8s/DataPlane.zig");
const DataPlane = data_plane_mod.DataPlane;
const PodRecord = @import("k8s/PodRecord.zig");
const PodProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(PodRecord);
const pod_subscription = @import("k8s/PodSubscription.zig");
const metrics_feed = @import("k8s/MetricsFeed.zig");
const NodeRecord = @import("k8s/NodeRecord.zig");
const NamespaceRecord = @import("k8s/NamespaceRecord.zig");
const NodeProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(NodeRecord);
const NamespaceProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(NamespaceRecord);
const resource_subscription = @import("k8s/ResourceSubscription.zig");
const NodeSubscription = resource_subscription.ResourceSubscription(
    klient.Node,
    NodeRecord,
    NodeRecord.fromNode,
);
const NamespaceSubscription = resource_subscription.ResourceSubscription(
    klient.Namespace,
    NamespaceRecord,
    NamespaceRecord.fromNamespace,
);
const ServiceRecord = @import("k8s/ServiceRecord.zig");
const EndpointRecord = @import("k8s/EndpointRecord.zig");
const EndpointSliceRecord = @import("k8s/EndpointSliceRecord.zig");
const ServiceProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ServiceRecord);
const EndpointProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(EndpointRecord);
const EndpointSliceProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(EndpointSliceRecord);
const ServiceSubscription = resource_subscription.ResourceSubscription(
    klient.Service,
    ServiceRecord,
    ServiceRecord.fromService,
);
const EndpointSubscription = resource_subscription.ResourceSubscription(
    klient.Endpoints,
    EndpointRecord,
    EndpointRecord.fromEndpoints,
);
const EndpointSliceSubscription = resource_subscription.ResourceSubscription(
    klient.EndpointSlice,
    EndpointSliceRecord,
    EndpointSliceRecord.fromEndpointSlice,
);
const ConfigMapRecord = @import("k8s/ConfigMapRecord.zig");
const SecretRecord = @import("k8s/SecretRecord.zig");
const ServiceAccountRecord = @import("k8s/ServiceAccountRecord.zig");
const ResourceQuotaRecord = @import("k8s/ResourceQuotaRecord.zig");
const LimitRangeRecord = @import("k8s/LimitRangeRecord.zig");
const ConfigMapProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ConfigMapRecord);
const SecretProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(SecretRecord);
const ServiceAccountProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ServiceAccountRecord);
const ResourceQuotaProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ResourceQuotaRecord);
const LimitRangeProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(LimitRangeRecord);
const ConfigMapSubscription = resource_subscription.ResourceSubscription(
    klient.ConfigMap,
    ConfigMapRecord,
    ConfigMapRecord.fromConfigMap,
);
const SecretSubscription = resource_subscription.ResourceSubscription(
    klient.Secret,
    SecretRecord,
    SecretRecord.fromSecret,
);
const ServiceAccountSubscription = resource_subscription.ResourceSubscription(
    klient.ServiceAccount,
    ServiceAccountRecord,
    ServiceAccountRecord.fromServiceAccount,
);
const ResourceQuotaSubscription = resource_subscription.ResourceSubscription(
    klient.ResourceQuota,
    ResourceQuotaRecord,
    ResourceQuotaRecord.fromResourceQuota,
);
const LimitRangeSubscription = resource_subscription.ResourceSubscription(
    klient.LimitRange,
    LimitRangeRecord,
    LimitRangeRecord.fromLimitRange,
);
const DeploymentRecord = @import("k8s/DeploymentRecord.zig");
const StatefulSetRecord = @import("k8s/StatefulSetRecord.zig");
const DaemonSetRecord = @import("k8s/DaemonSetRecord.zig");
const ReplicaSetRecord = @import("k8s/ReplicaSetRecord.zig");
const DeploymentProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(DeploymentRecord);
const StatefulSetProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(StatefulSetRecord);
const DaemonSetProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(DaemonSetRecord);
const ReplicaSetProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ReplicaSetRecord);
const DeploymentSubscription = resource_subscription.ResourceSubscription(
    klient.Deployment,
    DeploymentRecord,
    DeploymentRecord.fromDeployment,
);
const StatefulSetSubscription = resource_subscription.ResourceSubscription(
    klient.StatefulSet,
    StatefulSetRecord,
    StatefulSetRecord.fromStatefulSet,
);
const DaemonSetSubscription = resource_subscription.ResourceSubscription(
    klient.DaemonSet,
    DaemonSetRecord,
    DaemonSetRecord.fromDaemonSet,
);
const ReplicaSetSubscription = resource_subscription.ResourceSubscription(
    klient.ReplicaSet,
    ReplicaSetRecord,
    ReplicaSetRecord.fromReplicaSet,
);
const JobRecord = @import("k8s/JobRecord.zig");
const CronJobRecord = @import("k8s/CronJobRecord.zig");
const HPARecord = @import("k8s/HPARecord.zig");
const PDBRecord = @import("k8s/PDBRecord.zig");
const JobProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(JobRecord);
const CronJobProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(CronJobRecord);
const HPAProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(HPARecord);
const PDBProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(PDBRecord);
const JobSubscription = resource_subscription.ResourceSubscription(
    klient.Job,
    JobRecord,
    JobRecord.fromJob,
);
const CronJobSubscription = resource_subscription.ResourceSubscription(
    klient.CronJob,
    CronJobRecord,
    CronJobRecord.fromCronJob,
);
const HPASubscription = resource_subscription.ResourceSubscription(
    klient.HorizontalPodAutoscaler,
    HPARecord,
    HPARecord.fromHorizontalPodAutoscaler,
);
const PDBSubscription = resource_subscription.ResourceSubscription(
    klient.PodDisruptionBudget,
    PDBRecord,
    PDBRecord.fromPodDisruptionBudget,
);
const IngressRecord = @import("k8s/IngressRecord.zig");
const IngressClassRecord = @import("k8s/IngressClassRecord.zig");
const NetworkPolicyRecord = @import("k8s/NetworkPolicyRecord.zig");
const IPAddressRecord = @import("k8s/IPAddressRecord.zig");
const ServiceCIDRRecord = @import("k8s/ServiceCIDRRecord.zig");
const IngressProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(IngressRecord);
const IngressClassProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(IngressClassRecord);
const NetworkPolicyProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(NetworkPolicyRecord);
const IPAddressProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(IPAddressRecord);
const ServiceCIDRProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ServiceCIDRRecord);
const IngressSubscription = resource_subscription.ResourceSubscription(
    klient.types.Ingress,
    IngressRecord,
    IngressRecord.fromIngress,
);
const IngressClassSubscription = resource_subscription.ResourceSubscription(
    klient.IngressClass,
    IngressClassRecord,
    IngressClassRecord.fromIngressClass,
);
const NetworkPolicySubscription = resource_subscription.ResourceSubscription(
    klient.NetworkPolicy,
    NetworkPolicyRecord,
    NetworkPolicyRecord.fromNetworkPolicy,
);
const IPAddressSubscription = resource_subscription.ResourceSubscription(
    klient.IPAddress,
    IPAddressRecord,
    IPAddressRecord.fromIPAddress,
);
const ServiceCIDRSubscription = resource_subscription.ResourceSubscription(
    klient.ServiceCIDR,
    ServiceCIDRRecord,
    ServiceCIDRRecord.fromServiceCIDR,
);
const PVRecord = @import("k8s/PVRecord.zig");
const PVCRecord = @import("k8s/PVCRecord.zig");
const StorageClassRecord = @import("k8s/StorageClassRecord.zig");
const VolumeAttributesClassRecord = @import("k8s/VolumeAttributesClassRecord.zig");
const CSIDriverRecord = @import("k8s/CSIDriverRecord.zig");
const PVProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(PVRecord);
const PVCProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(PVCRecord);
const StorageClassProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(StorageClassRecord);
const VolumeAttributesClassProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(VolumeAttributesClassRecord);
const CSIDriverProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(CSIDriverRecord);
const PVSubscription = resource_subscription.ResourceSubscription(klient.PersistentVolume, PVRecord, PVRecord.fromPersistentVolume);
const PVCSubscription = resource_subscription.ResourceSubscription(klient.PersistentVolumeClaim, PVCRecord, PVCRecord.fromPersistentVolumeClaim);
const StorageClassSubscription = resource_subscription.ResourceSubscription(klient.StorageClass, StorageClassRecord, StorageClassRecord.fromStorageClass);
const VolumeAttributesClassSubscription = resource_subscription.ResourceSubscription(klient.VolumeAttributesClass, VolumeAttributesClassRecord, VolumeAttributesClassRecord.fromVolumeAttributesClass);
const CSIDriverSubscription = resource_subscription.ResourceSubscription(klient.CSIDriver, CSIDriverRecord, CSIDriverRecord.fromCSIDriver);
const family_registry = @import("k8s/ResourceFamilyRegistry.zig");
const resource_view = @import("view/resource_view.zig");
const version = @import("model/version.zig");
const theme_loader = @import("model/theme_loader.zig");
// MVVM imports
const View = @import("viewmodel/view.zig").View;
const ViewManager = @import("viewmodel/ViewManager.zig").ViewManager;
const Command = @import("viewmodel/command.zig").Command;
const CommandRegistry = @import("viewmodel/command.zig").CommandRegistry;

// View imports - generic resource views from single config file
const rc = @import("view/resource_configs.zig");
const PodsView = rc.PodsView;
const AliasesView = @import("view/AliasesView.zig").AliasesView;
const DeploymentsView = rc.DeploymentsView;
const ServicesView = rc.ServicesView;
const NamespacesView = @import("view/NamespacesView.zig").NamespacesView;
const PortForwardsView = @import("view/PortForwardsView.zig").PortForwardsView;
const PortForwardRegistry = @import("services/PortForwardRegistry.zig").PortForwardRegistry;
const secret_decode = @import("viewmodel/secret_decode.zig");
const NodesView = rc.NodesView;
const StatefulSetsView = rc.StatefulSetsView;
const DaemonSetsView = rc.DaemonSetsView;
const ReplicaSetsView = rc.ReplicaSetsView;
const JobsView = rc.JobsView;
const CronJobsView = rc.CronJobsView;
const ConfigMapsView = rc.ConfigMapsView;
const SecretsView = rc.SecretsView;
const PersistentVolumesView = rc.PersistentVolumesView;
const PersistentVolumeClaimsView = rc.PersistentVolumeClaimsView;
const IngressesView = rc.IngressesView;
const NetworkPoliciesView = rc.NetworkPoliciesView;
const ServiceAccountsView = rc.ServiceAccountsView;
const RolesView = rc.RolesView;
const RoleBindingsView = rc.RoleBindingsView;
const ClusterRolesView = rc.ClusterRolesView;
const ClusterRoleBindingsView = rc.ClusterRoleBindingsView;
const EventsView = rc.EventsView;
const ResourceQuotasView = rc.ResourceQuotasView;
const LimitRangesView = rc.LimitRangesView;
const PodDisruptionBudgetsView = rc.PodDisruptionBudgetsView;
const HPAView = rc.HPAView;
const EndpointsView = rc.EndpointsView;
const StorageClassesView = rc.StorageClassesView;
const GatewayClassesView = rc.GatewayClassesView;
const GatewaysView = rc.GatewaysView;
const HTTPRoutesView = rc.HTTPRoutesView;
const GRPCRoutesView = rc.GRPCRoutesView;
const ReferenceGrantsView = rc.ReferenceGrantsView;
const TCPRoutesView = rc.TCPRoutesView;
const TLSRoutesView = rc.TLSRoutesView;
const UDPRoutesView = rc.UDPRoutesView;
const BackendTLSPoliciesView = rc.BackendTLSPoliciesView;
const ListenerSetsView = rc.ListenerSetsView;
const EndpointSlicesView = rc.EndpointSlicesView;
const IngressClassesView = rc.IngressClassesView;
const IPAddressesView = rc.IPAddressesView;
const ServiceCIDRsView = rc.ServiceCIDRsView;
const VolumeAttributesClassesView = rc.VolumeAttributesClassesView;
const CSIDriversView = rc.CSIDriversView;
const ValidatingAdmissionPoliciesView = rc.ValidatingAdmissionPoliciesView;
const ValidatingAdmissionPolicyBindingsView = rc.ValidatingAdmissionPolicyBindingsView;
const MutatingAdmissionPoliciesView = rc.MutatingAdmissionPoliciesView;
const MutatingAdmissionPolicyBindingsView = rc.MutatingAdmissionPolicyBindingsView;
const ValidatingWebhookConfigurationsView = rc.ValidatingWebhookConfigurationsView;
const MutatingWebhookConfigurationsView = rc.MutatingWebhookConfigurationsView;
const ResourceClaimsView = rc.ResourceClaimsView;
const DeviceClassesView = rc.DeviceClassesView;
const PriorityClassesView = rc.PriorityClassesView;
const RuntimeClassesView = rc.RuntimeClassesView;
const LeasesView = rc.LeasesView;
const CertificateSigningRequestsView = rc.CertificateSigningRequestsView;
const StorageVersionMigrationsView = rc.StorageVersionMigrationsView;
const ContextsView = @import("view/ContextsView.zig").ContextsView;
const ThemesView = @import("view/ThemesView.zig").ThemesView;
const HelpView = @import("view/HelpView.zig").HelpView;
const ViewType = @import("viewmodel/keybindings_vm.zig").ViewType;
const DetailView = @import("view/DetailView.zig").DetailView;
const LogsView = @import("view/LogsView.zig").LogsView;
const AuthorizationView = @import("view/AuthorizationView.zig").AuthorizationView;
const TrafficView = @import("view/TrafficView.zig").TrafficView;

// Service imports
const klient = @import("klient");
const k8s_service_mod = @import("services/K8sService.zig");
const K8sService = k8s_service_mod.K8sService;
const K9sMigration = @import("services/K9sMigration.zig");
const ResourceType = k8s_service_mod.ResourceType;
const view_mod = @import("viewmodel/view.zig");
const ResourceInfo = view_mod.ResourceInfo;
const k9s_query = @import("viewmodel/k9s_query.zig");
const ActiveSessionSlot = @import("k8s/ActiveSessionSlot.zig").ActiveSessionSlot;

// Global flag for terminal resize signal
var terminal_resized: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

const ResourceFamilies = struct {
    const planned_family_capacity = 3 + 5 + 4 + 4 + 5 + 5 + 5 + 5 + 4 + 6 + 2 + 6;

    allocator: std.mem.Allocator,
    service_projection: ServiceProjection,
    endpoint_projection: EndpointProjection,
    endpoint_slice_projection: EndpointSliceProjection,
    config_map_projection: ConfigMapProjection,
    secret_projection: SecretProjection,
    service_account_projection: ServiceAccountProjection,
    resource_quota_projection: ResourceQuotaProjection,
    limit_range_projection: LimitRangeProjection,
    deployment_projection: DeploymentProjection,
    stateful_set_projection: StatefulSetProjection,
    daemon_set_projection: DaemonSetProjection,
    replica_set_projection: ReplicaSetProjection,
    job_projection: JobProjection,
    cron_job_projection: CronJobProjection,
    hpa_projection: HPAProjection,
    pdb_projection: PDBProjection,
    ingress_projection: IngressProjection,
    ingress_class_projection: IngressClassProjection,
    network_policy_projection: NetworkPolicyProjection,
    ip_address_projection: IPAddressProjection,
    service_cidr_projection: ServiceCIDRProjection,
    pv_projection: PVProjection,
    pvc_projection: PVCProjection,
    storage_class_projection: StorageClassProjection,
    volume_attributes_class_projection: VolumeAttributesClassProjection,
    csi_driver_projection: CSIDriverProjection,
    entries: std.ArrayListUnmanaged(family_registry.Entry) = .empty,
    registry: family_registry.Registry = undefined,

    fn init(allocator: std.mem.Allocator) ResourceFamilies {
        return .{
            .allocator = allocator,
            .service_projection = ServiceProjection.init(allocator, .{
                .matchFn = serviceProjectionMatch,
                .sortKeyFn = serviceProjectionSortKey,
            }),
            .endpoint_projection = EndpointProjection.init(allocator, .{
                .matchFn = endpointProjectionMatch,
                .sortKeyFn = endpointProjectionSortKey,
            }),
            .endpoint_slice_projection = EndpointSliceProjection.init(allocator, .{
                .matchFn = endpointSliceProjectionMatch,
                .sortKeyFn = endpointSliceProjectionSortKey,
            }),
            .config_map_projection = ConfigMapProjection.init(allocator, .{
                .matchFn = configMapProjectionMatch,
                .sortKeyFn = configMapProjectionSortKey,
            }),
            .secret_projection = SecretProjection.init(allocator, .{
                .matchFn = secretProjectionMatch,
                .sortKeyFn = secretProjectionSortKey,
            }),
            .service_account_projection = ServiceAccountProjection.init(allocator, .{
                .matchFn = serviceAccountProjectionMatch,
                .sortKeyFn = serviceAccountProjectionSortKey,
            }),
            .resource_quota_projection = ResourceQuotaProjection.init(allocator, .{
                .matchFn = resourceQuotaProjectionMatch,
                .sortKeyFn = resourceQuotaProjectionSortKey,
            }),
            .limit_range_projection = LimitRangeProjection.init(allocator, .{
                .matchFn = limitRangeProjectionMatch,
                .sortKeyFn = limitRangeProjectionSortKey,
            }),
            .deployment_projection = DeploymentProjection.init(allocator, .{
                .matchFn = deploymentProjectionMatch,
                .sortKeyFn = deploymentProjectionSortKey,
            }),
            .stateful_set_projection = StatefulSetProjection.init(allocator, .{
                .matchFn = statefulSetProjectionMatch,
                .sortKeyFn = statefulSetProjectionSortKey,
            }),
            .daemon_set_projection = DaemonSetProjection.init(allocator, .{
                .matchFn = daemonSetProjectionMatch,
                .sortKeyFn = daemonSetProjectionSortKey,
            }),
            .replica_set_projection = ReplicaSetProjection.init(allocator, .{
                .matchFn = replicaSetProjectionMatch,
                .sortKeyFn = replicaSetProjectionSortKey,
            }),
            .job_projection = JobProjection.init(allocator, .{
                .matchFn = jobProjectionMatch,
                .sortKeyFn = jobProjectionSortKey,
            }),
            .cron_job_projection = CronJobProjection.init(allocator, .{
                .matchFn = cronJobProjectionMatch,
                .sortKeyFn = cronJobProjectionSortKey,
            }),
            .hpa_projection = HPAProjection.init(allocator, .{
                .matchFn = hpaProjectionMatch,
                .sortKeyFn = hpaProjectionSortKey,
            }),
            .pdb_projection = PDBProjection.init(allocator, .{
                .matchFn = pdbProjectionMatch,
                .sortKeyFn = pdbProjectionSortKey,
            }),
            .ingress_projection = IngressProjection.init(allocator, .{
                .matchFn = ingressProjectionMatch,
                .sortKeyFn = ingressProjectionSortKey,
            }),
            .ingress_class_projection = IngressClassProjection.init(allocator, .{
                .matchFn = ingressClassProjectionMatch,
                .sortKeyFn = ingressClassProjectionSortKey,
            }),
            .network_policy_projection = NetworkPolicyProjection.init(allocator, .{
                .matchFn = networkPolicyProjectionMatch,
                .sortKeyFn = networkPolicyProjectionSortKey,
            }),
            .ip_address_projection = IPAddressProjection.init(allocator, .{
                .matchFn = ipAddressProjectionMatch,
                .sortKeyFn = ipAddressProjectionSortKey,
            }),
            .service_cidr_projection = ServiceCIDRProjection.init(allocator, .{
                .matchFn = serviceCIDRProjectionMatch,
                .sortKeyFn = serviceCIDRProjectionSortKey,
            }),
            .pv_projection = PVProjection.init(allocator, .{
                .matchFn = pvProjectionMatch,
                .sortKeyFn = pvProjectionSortKey,
            }),
            .pvc_projection = PVCProjection.init(allocator, .{
                .matchFn = pvcProjectionMatch,
                .sortKeyFn = pvcProjectionSortKey,
            }),
            .storage_class_projection = StorageClassProjection.init(allocator, .{
                .matchFn = storageClassProjectionMatch,
                .sortKeyFn = storageClassProjectionSortKey,
            }),
            .volume_attributes_class_projection = VolumeAttributesClassProjection.init(allocator, .{
                .matchFn = volumeAttributesClassProjectionMatch,
                .sortKeyFn = volumeAttributesClassProjectionSortKey,
            }),
            .csi_driver_projection = CSIDriverProjection.init(allocator, .{
                .matchFn = csiDriverProjectionMatch,
                .sortKeyFn = csiDriverProjectionSortKey,
            }),
        };
    }

    fn bind(
        self: *ResourceFamilies,
        comptime Record: type,
        comptime Subscription: type,
        comptime ResourceViewType: type,
        name: []const u8,
        projection: *@import("k8s/ResourceProjection.zig").ResourceProjection(Record),
        view: *ResourceViewType,
        comptime enabled_fn: fn () bool,
        comptime columns_fn: anytype,
    ) !void {
        view.bindProjection(ResourceViewType.ProjectionAdapter.init(
            Record,
            projection,
            enabled_fn,
            columns_fn,
        ));
        try self.entries.append(
            self.allocator,
            family_registry.Entry.init(
                Record,
                Subscription,
                ResourceViewType,
                name,
                projection,
                view,
                enabled_fn,
            ),
        );
        self.registry.rebind();
    }

    fn bindViews(self: *ResourceFamilies, app: anytype) !void {
        try self.entries.ensureTotalCapacity(self.allocator, planned_family_capacity);
        self.registry = family_registry.Registry.initDynamic(&self.entries);
        try self.bind(ServiceRecord, ServiceSubscription, ServicesView, "services", &self.service_projection, app.services_view, servicesDataPlaneEnabled, serviceProjectionColumns);
        try self.bind(EndpointRecord, EndpointSubscription, EndpointsView, "endpoints", &self.endpoint_projection, app.endpoints_view, servicesDataPlaneEnabled, endpointProjectionColumns);
        try self.bind(EndpointSliceRecord, EndpointSliceSubscription, EndpointSlicesView, "endpointslices", &self.endpoint_slice_projection, app.endpointslices_view, servicesDataPlaneEnabled, endpointSliceProjectionColumns);
        try self.bind(ConfigMapRecord, ConfigMapSubscription, ConfigMapsView, "configmaps", &self.config_map_projection, app.configmaps_view, configDataPlaneEnabled, configMapProjectionColumns);
        try self.bind(SecretRecord, SecretSubscription, SecretsView, "secrets", &self.secret_projection, app.secrets_view, configDataPlaneEnabled, secretProjectionColumns);
        try self.bind(ServiceAccountRecord, ServiceAccountSubscription, ServiceAccountsView, "serviceaccounts", &self.service_account_projection, app.serviceaccounts_view, configDataPlaneEnabled, serviceAccountProjectionColumns);
        try self.bind(ResourceQuotaRecord, ResourceQuotaSubscription, ResourceQuotasView, "resourcequotas", &self.resource_quota_projection, app.resourcequotas_view, configDataPlaneEnabled, resourceQuotaProjectionColumns);
        try self.bind(LimitRangeRecord, LimitRangeSubscription, LimitRangesView, "limitranges", &self.limit_range_projection, app.limitranges_view, configDataPlaneEnabled, limitRangeProjectionColumns);
        try self.bind(DeploymentRecord, DeploymentSubscription, DeploymentsView, "deployments", &self.deployment_projection, app.deployments_view, workloadsDataPlaneEnabled, deploymentProjectionColumns);
        try self.bind(StatefulSetRecord, StatefulSetSubscription, StatefulSetsView, "statefulsets", &self.stateful_set_projection, app.statefulsets_view, workloadsDataPlaneEnabled, statefulSetProjectionColumns);
        try self.bind(DaemonSetRecord, DaemonSetSubscription, DaemonSetsView, "daemonsets", &self.daemon_set_projection, app.daemonsets_view, workloadsDataPlaneEnabled, daemonSetProjectionColumns);
        try self.bind(ReplicaSetRecord, ReplicaSetSubscription, ReplicaSetsView, "replicasets", &self.replica_set_projection, app.replicasets_view, workloadsDataPlaneEnabled, replicaSetProjectionColumns);
        try self.bind(JobRecord, JobSubscription, JobsView, "jobs", &self.job_projection, app.jobs_view, batchDataPlaneEnabled, jobProjectionColumns);
        try self.bind(CronJobRecord, CronJobSubscription, CronJobsView, "cronjobs", &self.cron_job_projection, app.cronjobs_view, batchDataPlaneEnabled, cronJobProjectionColumns);
        try self.bind(HPARecord, HPASubscription, HPAView, "hpa", &self.hpa_projection, app.hpa_view, batchDataPlaneEnabled, hpaProjectionColumns);
        try self.bind(PDBRecord, PDBSubscription, PodDisruptionBudgetsView, "poddisruptionbudgets", &self.pdb_projection, app.poddisruptionbudgets_view, batchDataPlaneEnabled, pdbProjectionColumns);
        try self.bind(IngressRecord, IngressSubscription, IngressesView, "ingresses", &self.ingress_projection, app.ingresses_view, networkingDataPlaneEnabled, ingressProjectionColumns);
        try self.bind(IngressClassRecord, IngressClassSubscription, IngressClassesView, "ingressclasses", &self.ingress_class_projection, app.ingressclasses_view, networkingDataPlaneEnabled, ingressClassProjectionColumns);
        try self.bind(NetworkPolicyRecord, NetworkPolicySubscription, NetworkPoliciesView, "networkpolicies", &self.network_policy_projection, app.networkpolicies_view, networkingDataPlaneEnabled, networkPolicyProjectionColumns);
        try self.bind(IPAddressRecord, IPAddressSubscription, IPAddressesView, "ipaddresses", &self.ip_address_projection, app.ipaddresses_view, networkingDataPlaneEnabled, ipAddressProjectionColumns);
        try self.bind(ServiceCIDRRecord, ServiceCIDRSubscription, ServiceCIDRsView, "servicecidrs", &self.service_cidr_projection, app.servicecidrs_view, networkingDataPlaneEnabled, serviceCIDRProjectionColumns);
        try self.bind(PVRecord, PVSubscription, PersistentVolumesView, "persistentvolumes", &self.pv_projection, app.persistentvolumes_view, storageDataPlaneEnabled, pvProjectionColumns);
        try self.bind(PVCRecord, PVCSubscription, PersistentVolumeClaimsView, "persistentvolumeclaims", &self.pvc_projection, app.persistentvolumeclaims_view, storageDataPlaneEnabled, pvcProjectionColumns);
        try self.bind(StorageClassRecord, StorageClassSubscription, StorageClassesView, "storageclasses", &self.storage_class_projection, app.storageclasses_view, storageDataPlaneEnabled, storageClassProjectionColumns);
        try self.bind(VolumeAttributesClassRecord, VolumeAttributesClassSubscription, VolumeAttributesClassesView, "volumeattributesclasses", &self.volume_attributes_class_projection, app.volumeattributesclasses_view, storageDataPlaneEnabled, volumeAttributesClassProjectionColumns);
        try self.bind(CSIDriverRecord, CSIDriverSubscription, CSIDriversView, "csidrivers", &self.csi_driver_projection, app.csidrivers_view, storageDataPlaneEnabled, csiDriverProjectionColumns);
    }

    fn deinit(self: *ResourceFamilies) void {
        self.service_projection.deinit();
        self.endpoint_projection.deinit();
        self.endpoint_slice_projection.deinit();
        self.config_map_projection.deinit();
        self.secret_projection.deinit();
        self.service_account_projection.deinit();
        self.resource_quota_projection.deinit();
        self.limit_range_projection.deinit();
        self.deployment_projection.deinit();
        self.stateful_set_projection.deinit();
        self.daemon_set_projection.deinit();
        self.replica_set_projection.deinit();
        self.job_projection.deinit();
        self.cron_job_projection.deinit();
        self.hpa_projection.deinit();
        self.pdb_projection.deinit();
        self.ingress_projection.deinit();
        self.ingress_class_projection.deinit();
        self.network_policy_projection.deinit();
        self.ip_address_projection.deinit();
        self.service_cidr_projection.deinit();
        self.pv_projection.deinit();
        self.pvc_projection.deinit();
        self.storage_class_projection.deinit();
        self.volume_attributes_class_projection.deinit();
        self.csi_driver_projection.deinit();
        self.entries.deinit(self.allocator);
    }
};

pub const App = struct {
    pub const LifecycleInbox = lifecycle.LifecycleInbox;
    pub const LifecycleProducer = lifecycle.LifecycleProducer;
    pub const CancellationIntents = lifecycle.CancellationIntents;
    pub const LifecycleCommand = lifecycle.LifecycleCommand;
    pub const OwnedTaskSpec = lifecycle.OwnedTaskSpec;
    pub const ChildControl = lifecycle.ChildControl;
    pub const ChildKey = lifecycle.ChildKey;
    pub const LifecycleSupervisor = lifecycle_supervisor.LifecycleSupervisor;

    allocator: std.mem.Allocator,
    perf_telemetry: PerfTelemetry,
    shared_event: *std.Io.Event,
    wakeup: *Wakeup,
    change_queue: *ChangeQueue,
    active_session_slot: *ActiveSessionSlot,
    lifecycle_inbox: *LifecycleInbox,
    cancellation_intents: *CancellationIntents,
    lifecycle_producer: LifecycleProducer,
    lifecycle_supervisor: *LifecycleSupervisor,
    data_plane: *DataPlane,
    pod_projection: *PodProjection,
    node_projection: *NodeProjection,
    namespace_projection: *NamespaceProjection,
    resource_families: *ResourceFamilies,
    active_pod_subscription: ?lifecycle.SubscriptionKey = null,
    active_node_subscription: ?lifecycle.SubscriptionKey = null,
    active_namespace_subscription: ?lifecycle.SubscriptionKey = null,
    active_metrics_subscription: ?lifecycle.SubscriptionKey = null,
    pod_metrics_started: bool = false,
    pod_initial_batch_applied: bool = false,
    pod_first_paint_emitted: bool = false,
    pod_list_complete_revision: ?resource_key.Revision = null,
    pod_complete_paint_emitted: bool = false,
    pod_restart_pending: bool = false,
    node_restart_pending: bool = false,
    namespace_restart_pending: bool = false,
    pending_context_switch: ?[]u8 = null,
    pod_projection_sync_pending: bool = false,
    pod_projection_apply_failed: bool = false,
    lifecycle_root_await_count: usize = 0,
    terminal: Terminal,
    header: Header,
    footer: Footer,
    command_input: CommandInput,
    config: Cli.Config,
    running: bool = true,
    prev_width: u16 = 0,
    prev_height: u16 = 0,
    header_height: u16 = 8,
    footer_visible: bool = true,
    dirty: bool = true,
    redraw_request: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    needs_connect: bool = true, // deferred K8s connection on first render
    last_render_time: i128 = 0,
    /// Milliseconds left in the current frame when the rate limiter dropped a render.
    /// null when nothing is pending. Keeps a dropped frame from waiting on the full
    /// resize-poll timeout.
    pending_frame_ms: ?i32 = null,
    /// Wall-clock nanos of the last automatic refresh.
    ///
    /// --refresh was parsed, unit-tested, and read NOWHERE, while --help advertised a
    /// 2-second default that did not exist: data only updated on `r`, `0`, connect,
    /// context switch, or onShow-when-empty. So a pod going CrashLoopBackOff never
    /// appeared until the user pressed a key -- the opposite of what a cluster monitor
    /// is for.
    last_auto_refresh_ns: i128 = 0,
    min_frame_time_ns: i128 = 16_666_667, // ~60 FPS (16.67ms)
    current_theme_name: []const u8,

    // MVVM components
    view_manager: ViewManager,
    command_registry: CommandRegistry,
    theme: *theme_loader.ThemeColors,
    /// All registered command names/aliases, kept alive for the fuzzy dropdown.
    /// Allocated after registerCommands(); freed in deinit().
    command_names: [][]const u8 = &.{},

    // Kubernetes service
    k8s_service: *K8sService,

    // Resource views
    pods_view: *PodsView,
    deployments_view: *DeploymentsView,
    services_view: *ServicesView,
    namespaces_view: *NamespacesView,
    nodes_view: *NodesView,
    statefulsets_view: *StatefulSetsView,
    daemonsets_view: *DaemonSetsView,
    replicasets_view: *ReplicaSetsView,
    jobs_view: *JobsView,
    cronjobs_view: *CronJobsView,
    configmaps_view: *ConfigMapsView,
    secrets_view: *SecretsView,
    persistentvolumes_view: *PersistentVolumesView,
    persistentvolumeclaims_view: *PersistentVolumeClaimsView,
    ingresses_view: *IngressesView,
    networkpolicies_view: *NetworkPoliciesView,
    serviceaccounts_view: *ServiceAccountsView,
    roles_view: *RolesView,
    rolebindings_view: *RoleBindingsView,
    clusterroles_view: *ClusterRolesView,
    clusterrolebindings_view: *ClusterRoleBindingsView,
    events_view: *EventsView,
    resourcequotas_view: *ResourceQuotasView,
    limitranges_view: *LimitRangesView,
    poddisruptionbudgets_view: *PodDisruptionBudgetsView,
    hpa_view: *HPAView,
    endpoints_view: *EndpointsView,
    storageclasses_view: *StorageClassesView,
    gatewayclasses_view: *GatewayClassesView,
    gateways_view: *GatewaysView,
    httproutes_view: *HTTPRoutesView,
    grpcroutes_view: *GRPCRoutesView,
    referencegrants_view: *ReferenceGrantsView,
    tcproutes_view: *TCPRoutesView,
    tlsroutes_view: *TLSRoutesView,
    udproutes_view: *UDPRoutesView,
    backendtlspolicies_view: *BackendTLSPoliciesView,
    listenersets_view: *ListenerSetsView,
    endpointslices_view: *EndpointSlicesView,
    ingressclasses_view: *IngressClassesView,
    ipaddresses_view: *IPAddressesView,
    servicecidrs_view: *ServiceCIDRsView,
    volumeattributesclasses_view: *VolumeAttributesClassesView,
    csidrivers_view: *CSIDriversView,
    validatingadmissionpolicies_view: *ValidatingAdmissionPoliciesView,
    validatingadmissionpolicybindings_view: *ValidatingAdmissionPolicyBindingsView,
    mutatingadmissionpolicies_view: *MutatingAdmissionPoliciesView,
    mutatingadmissionpolicybindings_view: *MutatingAdmissionPolicyBindingsView,
    validatingwebhookconfigurations_view: *ValidatingWebhookConfigurationsView,
    mutatingwebhookconfigurations_view: *MutatingWebhookConfigurationsView,
    resourceclaims_view: *ResourceClaimsView,
    deviceclasses_view: *DeviceClassesView,
    priorityclasses_view: *PriorityClassesView,
    runtimeclasses_view: *RuntimeClassesView,
    leases_view: *LeasesView,
    certificatesigningrequests_view: *CertificateSigningRequestsView,
    storageversionmigrations_view: *StorageVersionMigrationsView,
    contexts_view: *ContextsView,

    // UI views
    themes_view: *ThemesView,
    help_view: *HelpView,
    detail_view: *DetailView,
    aliases_view: *AliasesView,
    port_forwards_view: *PortForwardsView,
    logs_view: *LogsView,
    authorization_view: *AuthorizationView,
    traffic_view: *TrafficView,

    // Delete confirmation state
    delete_pending: bool = false,
    delete_force: bool = false,
    delete_resource_name: ?[]u8 = null,
    delete_resource_namespace: ?[]u8 = null,
    delete_resource_type: ?ResourceType = null,

    // Generic text-input prompt (set-image / port-forward / transfer / sanitize).
    pending_input: enum { none, set_image, port_forward, transfer, sanitize, drain, scale } = .none,
    pending_name: ?[]u8 = null,
    pending_namespace: ?[]u8 = null,
    pending_type: ?ResourceType = null,
    /// Active `kubectl port-forward` children. Heap-allocated so the view can hold a
    /// stable pointer: App is returned by value from init(), so &app.field would
    /// dangle (same reason k8s_service is a pointer).
    port_forward_registry: *PortForwardRegistry,

    // Track which primary view is active (matches view getName() return value)
    current_view_name: []const u8 = "pods",
    /// View to return to when the aliases overlay is toggled off (Ctrl-A).
    pre_aliases_view: []const u8 = "pods",
    /// View to return to after switching cluster context (k9s behavior:
    /// selecting a context drops you back where you were, not in contexts).
    pre_contexts_view: []const u8 = "pods",
    command_history: std.ArrayListUnmanaged([]u8) = .empty,
    history_cursor: usize = 0,
    crumbs_visible: bool = true,
    view_fullscreen: bool = false,
    crumb_buf: [160]u8 = undefined,

    pub fn init(allocator: std.mem.Allocator, config: Cli.Config) !App {
        var perf_telemetry = PerfTelemetry.initFromEnv();
        errdefer perf_telemetry.deinit();

        const shared_event = try allocator.create(std.Io.Event);
        shared_event.* = .unset;
        errdefer allocator.destroy(shared_event);

        const wakeup = try allocator.create(Wakeup);
        wakeup.* = try Wakeup.init();
        errdefer {
            wakeup.deinit();
            allocator.destroy(wakeup);
        }

        const change_queue = try allocator.create(ChangeQueue);
        change_queue.* = ChangeQueue.init(
            runtime.io(),
            allocator,
            resource_key.Limits.default,
            shared_event,
            wakeup,
        );
        errdefer {
            change_queue.deinit();
            allocator.destroy(change_queue);
        }

        const active_session_slot = try allocator.create(ActiveSessionSlot);
        active_session_slot.* = ActiveSessionSlot.init(runtime.io(), shared_event);
        errdefer {
            active_session_slot.deinit();
            allocator.destroy(active_session_slot);
        }

        const lifecycle_inbox = try allocator.create(LifecycleInbox);
        lifecycle_inbox.* = LifecycleInbox.init(runtime.io(), shared_event);
        errdefer {
            lifecycle_inbox.deinit(allocator);
            allocator.destroy(lifecycle_inbox);
        }

        const cancellation_intents = try allocator.create(CancellationIntents);
        cancellation_intents.* = CancellationIntents.init();
        errdefer allocator.destroy(cancellation_intents);

        const supervisor = try allocator.create(LifecycleSupervisor);
        supervisor.* = try LifecycleSupervisor.init(
            allocator,
            runtime.io(),
            shared_event,
            lifecycle_inbox,
            cancellation_intents,
            active_session_slot,
            change_queue,
            @import("k8s/ActiveContextSession.zig").SessionFactory.production(),
            null,
        );
        errdefer allocator.destroy(supervisor);

        const lifecycle_producer = LifecycleProducer.init(
            lifecycle_inbox,
            cancellation_intents,
            allocator,
        );
        const pod_projection = try allocator.create(PodProjection);
        pod_projection.* = PodProjection.init(allocator, .{
            .matchFn = podProjectionMatch,
            .sortKeyFn = podProjectionSortKey,
        });
        errdefer {
            pod_projection.deinit();
            allocator.destroy(pod_projection);
        }
        const node_projection = try allocator.create(NodeProjection);
        node_projection.* = NodeProjection.init(allocator, .{
            .matchFn = nodeProjectionMatch,
            .sortKeyFn = nodeProjectionSortKey,
        });
        errdefer {
            node_projection.deinit();
            allocator.destroy(node_projection);
        }
        const namespace_projection = try allocator.create(NamespaceProjection);
        namespace_projection.* = NamespaceProjection.init(allocator, .{
            .matchFn = namespaceProjectionMatch,
            .sortKeyFn = namespaceProjectionSortKey,
        });
        errdefer {
            namespace_projection.deinit();
            allocator.destroy(namespace_projection);
        }
        const resource_families = try allocator.create(ResourceFamilies);
        resource_families.* = ResourceFamilies.init(allocator);
        errdefer {
            resource_families.deinit();
            allocator.destroy(resource_families);
        }
        const data_plane = try allocator.create(DataPlane);
        data_plane.* = DataPlane.init(allocator, lifecycle_producer, change_queue);
        errdefer allocator.destroy(data_plane);

        // Initialize terminal
        var term = try Terminal.init(allocator);
        errdefer term.deinit();

        // Drop-in k9s support: import an existing k9s config tree (skins,
        // aliases, active skin → theme) before the config is first read.
        // Idempotent and best-effort; never blocks startup.
        K9sMigration.migrateIfNeeded(allocator);

        // Load UI config from file
        const ui_config = Config.load(allocator) catch Config.Config{
            .allocator = allocator,
            .ui = Config.UiConfig{},
            .theme_owned = null,
        };
        defer ui_config.deinit();

        // Load theme
        const theme = try allocator.create(theme_loader.ThemeColors);
        errdefer allocator.destroy(theme);
        theme.* = try theme_loader.loadTheme(allocator, ui_config.ui.theme);
        errdefer theme_loader.deinitTheme(theme);

        // Initialize Kubernetes service (heap-allocated so views get a stable pointer)
        const k8s_service = try allocator.create(K8sService);
        errdefer allocator.destroy(k8s_service);
        k8s_service.* = try K8sService.init(allocator);
        // --readonly was previously parsed and never consulted, so it blocked nothing.
        // The service rejects mutations; the UI additionally declines to prompt.
        k8s_service.readonly = config.readonly;
        k8s_service.setKubeconfigPath(config.kubeconfig);
        k8s_service.bindSessionSlot(active_session_slot);
        errdefer k8s_service.deinit();

        // K8s connection is deferred to first render — app starts instantly

        // Initialize MVVM components
        const view_manager = try ViewManager.init(allocator);
        const command_registry = try CommandRegistry.init(allocator);

        // Allocate all view pointers (comptime-generated)
        var app_views: struct {
            pods_view: *PodsView = undefined,
            deployments_view: *DeploymentsView = undefined,
            services_view: *ServicesView = undefined,
            namespaces_view: *NamespacesView = undefined,
            nodes_view: *NodesView = undefined,
            statefulsets_view: *StatefulSetsView = undefined,
            daemonsets_view: *DaemonSetsView = undefined,
            replicasets_view: *ReplicaSetsView = undefined,
            jobs_view: *JobsView = undefined,
            cronjobs_view: *CronJobsView = undefined,
            configmaps_view: *ConfigMapsView = undefined,
            secrets_view: *SecretsView = undefined,
            persistentvolumes_view: *PersistentVolumesView = undefined,
            persistentvolumeclaims_view: *PersistentVolumeClaimsView = undefined,
            ingresses_view: *IngressesView = undefined,
            networkpolicies_view: *NetworkPoliciesView = undefined,
            serviceaccounts_view: *ServiceAccountsView = undefined,
            roles_view: *RolesView = undefined,
            rolebindings_view: *RoleBindingsView = undefined,
            clusterroles_view: *ClusterRolesView = undefined,
            clusterrolebindings_view: *ClusterRoleBindingsView = undefined,
            events_view: *EventsView = undefined,
            resourcequotas_view: *ResourceQuotasView = undefined,
            limitranges_view: *LimitRangesView = undefined,
            poddisruptionbudgets_view: *PodDisruptionBudgetsView = undefined,
            hpa_view: *HPAView = undefined,
            endpoints_view: *EndpointsView = undefined,
            storageclasses_view: *StorageClassesView = undefined,
            gatewayclasses_view: *GatewayClassesView = undefined,
            gateways_view: *GatewaysView = undefined,
            httproutes_view: *HTTPRoutesView = undefined,
            grpcroutes_view: *GRPCRoutesView = undefined,
            referencegrants_view: *ReferenceGrantsView = undefined,
            tcproutes_view: *TCPRoutesView = undefined,
            tlsroutes_view: *TLSRoutesView = undefined,
            udproutes_view: *UDPRoutesView = undefined,
            backendtlspolicies_view: *BackendTLSPoliciesView = undefined,
            listenersets_view: *ListenerSetsView = undefined,
            endpointslices_view: *EndpointSlicesView = undefined,
            ingressclasses_view: *IngressClassesView = undefined,
            ipaddresses_view: *IPAddressesView = undefined,
            servicecidrs_view: *ServiceCIDRsView = undefined,
            volumeattributesclasses_view: *VolumeAttributesClassesView = undefined,
            csidrivers_view: *CSIDriversView = undefined,
            validatingadmissionpolicies_view: *ValidatingAdmissionPoliciesView = undefined,
            validatingadmissionpolicybindings_view: *ValidatingAdmissionPolicyBindingsView = undefined,
            mutatingadmissionpolicies_view: *MutatingAdmissionPoliciesView = undefined,
            mutatingadmissionpolicybindings_view: *MutatingAdmissionPolicyBindingsView = undefined,
            validatingwebhookconfigurations_view: *ValidatingWebhookConfigurationsView = undefined,
            mutatingwebhookconfigurations_view: *MutatingWebhookConfigurationsView = undefined,
            resourceclaims_view: *ResourceClaimsView = undefined,
            deviceclasses_view: *DeviceClassesView = undefined,
            priorityclasses_view: *PriorityClassesView = undefined,
            runtimeclasses_view: *RuntimeClassesView = undefined,
            leases_view: *LeasesView = undefined,
            certificatesigningrequests_view: *CertificateSigningRequestsView = undefined,
            storageversionmigrations_view: *StorageVersionMigrationsView = undefined,
            contexts_view: *ContextsView = undefined,
            authorization_view: *AuthorizationView = undefined,
        } = .{};
        inline for (k8s_view_types) |entry| {
            @field(app_views, entry[0]) = try allocator.create(entry[1]);
        }

        // Initialize UI views (these don't need k8s_service)

        // The registry outlives the view and owns the child processes; the view is
        // only a window onto it.
        const port_forward_registry = try allocator.create(PortForwardRegistry);
        port_forward_registry.* = PortForwardRegistry.init(allocator);
        errdefer port_forward_registry.deinit();

        const port_forwards_view = try allocator.create(PortForwardsView);
        port_forwards_view.* = try PortForwardsView.init(allocator, theme, port_forward_registry);
        errdefer port_forwards_view.deinit();

        const themes_view = try allocator.create(ThemesView);
        themes_view.* = try ThemesView.init(allocator, ui_config.ui.theme, theme);
        errdefer themes_view.deinit();

        const help_view = try allocator.create(HelpView);
        help_view.* = try HelpView.init(allocator, theme);
        errdefer help_view.deinit();

        const detail_view = try allocator.create(DetailView);
        detail_view.* = try DetailView.init(allocator, theme);
        errdefer detail_view.deinit();

        // AliasesView needs the stable k8s_service pointer; init after the App
        // struct is built (mirrors pods_view).
        const aliases_view = try allocator.create(AliasesView);

        const logs_view = try allocator.create(LogsView);
        logs_view.* = try LogsView.init(allocator, theme);
        errdefer logs_view.deinit();

        const traffic_view = try allocator.create(TrafficView);
        traffic_view.* = TrafficView.init(allocator, theme, k8s_service);

        // Initialize header — connection is deferred, so start with placeholder
        var header = try Header.initWithData(allocator, theme, .{
            .context = "connecting...",
            .cluster = "...",
            .user = "...",
            .k8s_version = "...",
            .cpu_usage = 0,
            .mem_usage = 0,
        });

        const footer = try Footer.init(allocator, theme);
        const command_input = try CommandInput.init(allocator, theme);

        // Apply UI config
        Logger.info("UI Config - compact: {}, footer: {}", .{ ui_config.ui.compact, ui_config.ui.footer });
        header.setCompact(ui_config.ui.compact);

        // Create app
        var app = App{
            .allocator = allocator,
            .perf_telemetry = perf_telemetry,
            .shared_event = shared_event,
            .wakeup = wakeup,
            .change_queue = change_queue,
            .active_session_slot = active_session_slot,
            .lifecycle_inbox = lifecycle_inbox,
            .cancellation_intents = cancellation_intents,
            .lifecycle_producer = lifecycle_producer,
            .lifecycle_supervisor = supervisor,
            .data_plane = data_plane,
            .pod_projection = pod_projection,
            .node_projection = node_projection,
            .namespace_projection = namespace_projection,
            .resource_families = resource_families,
            .terminal = term,
            .header = header,
            .footer = footer,
            .command_input = command_input,
            .config = config,
            .footer_visible = ui_config.ui.footer,
            .current_theme_name = try allocator.dupe(u8, ui_config.ui.theme),
            .view_manager = view_manager,
            .command_registry = command_registry,
            .theme = theme,
            .k8s_service = k8s_service,
            .pods_view = app_views.pods_view,
            .deployments_view = app_views.deployments_view,
            .services_view = app_views.services_view,
            .namespaces_view = app_views.namespaces_view,
            .nodes_view = app_views.nodes_view,
            .statefulsets_view = app_views.statefulsets_view,
            .daemonsets_view = app_views.daemonsets_view,
            .replicasets_view = app_views.replicasets_view,
            .jobs_view = app_views.jobs_view,
            .cronjobs_view = app_views.cronjobs_view,
            .configmaps_view = app_views.configmaps_view,
            .secrets_view = app_views.secrets_view,
            .persistentvolumes_view = app_views.persistentvolumes_view,
            .persistentvolumeclaims_view = app_views.persistentvolumeclaims_view,
            .ingresses_view = app_views.ingresses_view,
            .networkpolicies_view = app_views.networkpolicies_view,
            .serviceaccounts_view = app_views.serviceaccounts_view,
            .roles_view = app_views.roles_view,
            .rolebindings_view = app_views.rolebindings_view,
            .clusterroles_view = app_views.clusterroles_view,
            .clusterrolebindings_view = app_views.clusterrolebindings_view,
            .events_view = app_views.events_view,
            .resourcequotas_view = app_views.resourcequotas_view,
            .limitranges_view = app_views.limitranges_view,
            .poddisruptionbudgets_view = app_views.poddisruptionbudgets_view,
            .hpa_view = app_views.hpa_view,
            .endpoints_view = app_views.endpoints_view,
            .storageclasses_view = app_views.storageclasses_view,
            .gatewayclasses_view = app_views.gatewayclasses_view,
            .gateways_view = app_views.gateways_view,
            .httproutes_view = app_views.httproutes_view,
            .grpcroutes_view = app_views.grpcroutes_view,
            .referencegrants_view = app_views.referencegrants_view,
            .tcproutes_view = app_views.tcproutes_view,
            .tlsroutes_view = app_views.tlsroutes_view,
            .udproutes_view = app_views.udproutes_view,
            .backendtlspolicies_view = app_views.backendtlspolicies_view,
            .listenersets_view = app_views.listenersets_view,
            .endpointslices_view = app_views.endpointslices_view,
            .ingressclasses_view = app_views.ingressclasses_view,
            .ipaddresses_view = app_views.ipaddresses_view,
            .servicecidrs_view = app_views.servicecidrs_view,
            .volumeattributesclasses_view = app_views.volumeattributesclasses_view,
            .csidrivers_view = app_views.csidrivers_view,
            .validatingadmissionpolicies_view = app_views.validatingadmissionpolicies_view,
            .validatingadmissionpolicybindings_view = app_views.validatingadmissionpolicybindings_view,
            .mutatingadmissionpolicies_view = app_views.mutatingadmissionpolicies_view,
            .mutatingadmissionpolicybindings_view = app_views.mutatingadmissionpolicybindings_view,
            .validatingwebhookconfigurations_view = app_views.validatingwebhookconfigurations_view,
            .mutatingwebhookconfigurations_view = app_views.mutatingwebhookconfigurations_view,
            .resourceclaims_view = app_views.resourceclaims_view,
            .deviceclasses_view = app_views.deviceclasses_view,
            .priorityclasses_view = app_views.priorityclasses_view,
            .runtimeclasses_view = app_views.runtimeclasses_view,
            .leases_view = app_views.leases_view,
            .certificatesigningrequests_view = app_views.certificatesigningrequests_view,
            .storageversionmigrations_view = app_views.storageversionmigrations_view,
            .contexts_view = app_views.contexts_view,
            .themes_view = themes_view,
            .help_view = help_view,
            .detail_view = detail_view,
            .aliases_view = aliases_view,
            .port_forwards_view = port_forwards_view,
            .port_forward_registry = port_forward_registry,
            .logs_view = logs_view,
            .authorization_view = app_views.authorization_view,
            .traffic_view = traffic_view,
        };

        // Initialize all K8s resource views (comptime-generated loop, includes
        // pods_view). Must happen AFTER k8s_service is moved into the App struct
        // for a stable pointer.
        aliases_view.* = try AliasesView.init(allocator, theme, app.k8s_service);
        inline for (k8s_view_types) |entry| {
            @field(app, entry[0]).* = try entry[1].init(allocator, theme, app.k8s_service);
        }
        app.pods_view.bindPodProjection(app.pod_projection);
        app.nodes_view.bindProjection(NodesView.ProjectionAdapter.init(
            NodeRecord,
            app.node_projection,
            nodeDataPlaneEnabled,
            nodeProjectionColumns,
        ));
        app.namespaces_view.bindProjection(app.namespace_projection);
        try app.resource_families.bindViews(app);

        // Register commands
        try app.registerCommands();
        app.crumbs_visible = !config.crumbsless;

        // Build the candidate list for the fuzzy command palette dropdown.
        // Done once here; the slice lives for the entire app lifetime.
        app.command_names = try app.command_registry.getCommandNames();
        app.command_input.setCandidates(app.command_names);

        // Push initial view (PodsView is the reference implementation with all features working)
        try app.view_manager.pushView(app.pods_view.createView());

        try app.lifecycle_supervisor.startRoot();
        return app;
    }

    pub fn deinit(self: *App) void {
        self.finishLifecycle();
        self.clearPendingInput();
        if (self.pending_context_switch) |name| self.allocator.free(name);

        for (self.command_history.items) |cmd| self.allocator.free(cmd);
        self.command_history.deinit(self.allocator);

        // Tear down the view manager BEFORE destroying the view objects it
        // references. (ViewManager.deinit no longer touches the views, but
        // keeping this order documents the ownership and avoids any future
        // lifecycle-callback-on-freed-view hazard.)
        self.view_manager.deinit();

        // Clean up all K8s views (comptime-generated loop)
        inline for (k8s_view_types) |entry| {
            @field(self, entry[0]).deinit();
            self.allocator.destroy(@field(self, entry[0]));
        }

        // Clean up special views
        self.themes_view.deinit();
        self.allocator.destroy(self.themes_view);
        self.help_view.deinit();
        self.allocator.destroy(self.help_view);
        self.detail_view.deinit();
        self.allocator.destroy(self.detail_view);
        self.aliases_view.deinit();
        self.allocator.destroy(self.aliases_view);
        // View before registry: the view only holds a table, while the registry kills
        // and reaps the children.
        self.port_forwards_view.deinit();
        self.allocator.destroy(self.port_forwards_view);
        self.port_forward_registry.deinit();
        self.allocator.destroy(self.port_forward_registry);
        self.logs_view.deinit();
        self.allocator.destroy(self.logs_view);
        self.traffic_view.deinit();
        self.allocator.destroy(self.traffic_view);

        // Clean up delete state
        self.clearDeleteState();

        // Clean up MVVM components
        self.allocator.free(self.command_names);
        self.command_registry.deinit();

        self.k8s_service.detachSession();
        self.active_session_slot.deinit();
        self.allocator.destroy(self.active_session_slot);

        self.lifecycle_inbox.deinit(self.allocator);
        self.allocator.destroy(self.lifecycle_inbox);
        self.allocator.destroy(self.cancellation_intents);
        self.allocator.destroy(self.lifecycle_supervisor);
        self.change_queue.deinit();
        self.allocator.destroy(self.change_queue);
        self.allocator.destroy(self.data_plane);
        self.pod_projection.deinit();
        self.allocator.destroy(self.pod_projection);
        self.node_projection.deinit();
        self.allocator.destroy(self.node_projection);
        self.namespace_projection.deinit();
        self.allocator.destroy(self.namespace_projection);
        self.resource_families.deinit();
        self.allocator.destroy(self.resource_families);
        self.wakeup.deinit();
        self.allocator.destroy(self.wakeup);

        // Clean up Kubernetes service
        self.k8s_service.deinit();
        self.allocator.destroy(self.k8s_service);

        // Clean up theme
        theme_loader.deinitTheme(self.theme);
        self.allocator.destroy(self.theme);

        // Clean up other components
        self.header.deinit();
        self.footer.deinit();
        self.command_input.deinit();
        self.allocator.free(self.current_theme_name);
        self.terminal.deinit();
        self.perf_telemetry.deinit();
        self.allocator.destroy(self.shared_event);
    }

    fn registerCommands(self: *App) !void {
        // Special commands
        for ([_][]const u8{ "q", "q!", "qa", "Q", "quit", "exit" }) |alias| {
            try self.command_registry.register(alias, Command{ .name = alias, .execute = quitCommand });
        }
        for ([_][]const u8{ "?", "h", "help" }) |alias| {
            try self.command_registry.register(alias, Command{ .name = alias, .execute = helpCommand });
        }

        // Comptime-generated view switch commands from declarative table
        inline for (view_commands) |vc| {
            const cmd_fn = comptime makeViewCommand(vc.field, vc.view_name);
            for (vc.aliases) |alias| {
                try self.command_registry.register(alias, Command{ .name = alias, .execute = cmd_fn });
            }
        }

        // Aliases view (k9s Ctrl-A): also reachable via `:aliases` and the
        // fuzzy palette. Toggles the same as Ctrl-A.
        // k9s alias.go: AliGVR is "alias", "a". `:a` is the command; `a` on a
        // pod remains Attach because keys and commands are different namespaces.
        for ([_][]const u8{ "aliases", "alias", "al", "a" }) |alias| {
            try self.command_registry.register(alias, Command{ .name = alias, .execute = aliasesCommand });
        }

        // Mark manipulation (k9s-style multi-select), also bound to keys
        // '*' (all) / '\' (clear) / '^' (invert) in resource views.
        for ([_][]const u8{ "select-all", "mark-all" }) |alias| {
            try self.command_registry.register(alias, Command{ .name = alias, .execute = selectAllCommand });
        }
        for ([_][]const u8{ "clear-marks", "unmark-all", "clear-selection" }) |alias| {
            try self.command_registry.register(alias, Command{ .name = alias, .execute = clearMarksCommand });
        }
        for ([_][]const u8{ "invert-marks", "invert-selection" }) |alias| {
            try self.command_registry.register(alias, Command{ .name = alias, .execute = invertMarksCommand });
        }

        // Internal commands
        try self.command_registry.register("select_theme", Command{ .name = "select_theme", .execute = selectThemeCommand });
        try self.command_registry.register("restart", Command{ .name = "restart", .execute = restartCommand });
        try self.command_registry.register("scale", Command{ .name = "scale", .execute = scaleCommand });
        try self.command_registry.register("suspend", Command{ .name = "suspend", .execute = suspendCommand });
        try self.command_registry.register("trigger", Command{ .name = "trigger", .execute = triggerCommand });
        try self.command_registry.register("rollback", Command{ .name = "rollback", .execute = rollbackCommand });
    }

    pub fn run(self: *App) !void {
        defer self.finishLifecycle();
        try self.terminal.enterAlternateScreen();
        defer _ = self.terminal.exitAlternateScreen() catch {};

        try self.terminal.hideCursor();
        defer _ = self.terminal.showCursor() catch {};

        try self.terminal.enableRawMode();
        defer self.terminal.disableRawMode();

        // Generate 256-color palette from terminal's base16 theme
        const color256 = @import("model/color256.zig");
        const palette_applied = color256.queryAndApplyPalette(
            self.terminal.stdin.handle,
            self.terminal.stdout.handle,
        );
        defer if (palette_applied) {
            color256.resetPalette(self.terminal.stdout.handle, 16, 256) catch {};
        };

        // Setup SIGWINCH handler for terminal resize
        setupResizeHandler() catch |err| {
            Logger.warn("Failed to setup SIGWINCH handler: {}", .{err});
        };

        self.dirty = true;
        self.prev_width = 0;
        self.prev_height = 0;

        while (self.running) {
            if (self.lifecycle_inbox.isRootTerminated()) {
                self.running = false;
                continue;
            }
            if (self.redraw_request.swap(false, .acq_rel)) self.dirty = true;
            self.renderIfNeeded() catch |err| {
                Logger.err("Render error: {any}", .{err});
            };

            // Deferred K8s connection — runs after first render so UI appears instantly
            if (self.needs_connect) {
                self.needs_connect = false;
                self.k8s_service.connect(self.config.context) catch |err| {
                    Logger.warn("Failed to connect to Kubernetes: {}. Continuing without cluster connection.", .{err});
                };
                // Update header with connection info (cheap, no network).
                const cluster_info = self.k8s_service.getClusterInfo();
                self.header.updateClusterInfo(cluster_info.context, cluster_info.cluster, cluster_info.user) catch {};

                // Load + paint the resource data FIRST so the user sees pods
                // immediately, before the slower header version/metrics calls.
                if (self.view_manager.getCurrentView()) |current_view| {
                    current_view.refresh() catch {};
                }
                self.serviceResourceSubscriptionRequests() catch |err| {
                    Logger.err("resource subscription start failed: {any}", .{err});
                };
                self.markRefreshCompleted();
                self.dirty = true;
                self.renderIfNeeded() catch {};

                // Now fetch the slower header extras (server version + node
                // metrics) and repaint the header. Deferred so they never block
                // the initial data render.
                self.header.updateK8sVersion(self.k8s_service.getServerVersion()) catch {};
                self.updateHeaderMetrics();
                self.dirty = true;
            }

            // Check if terminal was resized
            if (terminal_resized.load(.acquire)) {
                terminal_resized.store(false, .release);
                self.dirty = true;
            }

            const poll_timeout: i32 = self.pending_frame_ms orelse 100;
            const poll = sys.pollInputAndWakeup(
                self.terminal.stdin.handle,
                self.wakeup.readHandle(),
                poll_timeout,
            ) catch |err| {
                return err;
            };

            if (poll.wakeup.hasAny()) {
                self.wakeup.drain();
                self.drainChangeQueue();
                if (self.change_queue.hasPending()) self.wakeup.notify();
            }

            if (poll.input.isTerminal()) {
                self.running = false;
                continue;
            }

            if (poll.readiness == .timeout) {
                self.maybeAutoRefresh();
                continue;
            }

            if (poll.input.readable) {
                if (self.terminal.readKey() catch |err| {
                    Logger.err("readKey error: {any}", .{err});
                    continue;
                }) |key| {
                    self.handleKey(key) catch |err| {
                        Logger.err("handleKey error: {any}", .{err});
                    };
                    // Paint loading feedback before a deferred list fetch blocks.
                    self.renderIfNeeded() catch |err| {
                        Logger.err("Render error: {any}", .{err});
                    };
                    if (self.view_manager.getCurrentView()) |v| {
                        if (v.flushPendingRefresh()) {
                            self.dirty = true;
                            self.renderIfNeeded() catch |err| {
                                Logger.err("Render error: {any}", .{err});
                            };
                        }
                    }
                }
            }
        }
    }

    pub fn finishLifecycle(self: *App) void {
        if (self.lifecycle_supervisor.root_future == null) return;
        self.cancelMetricsFeed();
        if (self.active_pod_subscription) |key| {
            _ = self.data_plane.cancelSubscription(key);
            self.active_pod_subscription = null;
            self.pods_view.markPodSubscriptionStopped();
        }
        if (self.active_node_subscription) |key| {
            _ = self.data_plane.cancelSubscription(key);
            self.active_node_subscription = null;
            self.nodes_view.markSubscriptionStopped();
        }
        if (self.active_namespace_subscription) |key| {
            _ = self.data_plane.cancelSubscription(key);
            self.active_namespace_subscription = null;
            self.namespaces_view.markSubscriptionStopped();
        }
        for (self.resource_families.registry.items()) |*entry| {
            if (entry.active) |key| _ = self.data_plane.cancelSubscription(key);
            entry.markStopped();
        }
        self.lifecycle_producer.enqueueShutdown() catch |err| switch (err) {
            error.Closed => {},
        };
        if (self.lifecycle_supervisor.awaitRoot()) self.lifecycle_root_await_count += 1;
        while (self.change_queue.hasPending()) self.drainChangeQueue();
    }

    fn acceptsActiveEnvelope(
        self: *const App,
        envelope: resource_key.Envelope,
    ) bool {
        return switch (envelope.target) {
            .lifecycle => true,
            .resource => |identity| matchesIdentity(self.active_pod_subscription, identity) or
                matchesIdentity(self.active_metrics_subscription, identity) or
                matchesIdentity(self.active_node_subscription, identity) or
                matchesIdentity(self.active_namespace_subscription, identity) or
                self.resource_families.registry.contains(identity),
            else => false,
        };
    }

    fn serviceResourceSubscriptionRequests(self: *App) !void {
        try self.servicePodSubscriptionRequest();
        try self.serviceNodeSubscriptionRequest();
        try self.serviceNamespaceSubscriptionRequest();
        try self.serviceResourceFamilyRequests();
    }

    fn servicePodSubscriptionRequest(self: *App) !void {
        if (resource_view.active_pod_source == .legacy_list) return;
        const request = self.pods_view.takePodSubscriptionRequest();
        if (request == .none) return;
        if (self.active_pod_subscription) |active| {
            if (request == .start) return;
            self.pod_restart_pending = true;
            self.cancelMetricsFeed();
            _ = self.data_plane.cancelSubscription(active);
            return;
        }
        try self.startPodSubscription();
    }

    fn serviceNodeSubscriptionRequest(self: *App) !void {
        if (resource_view.active_node_source == .legacy_list) return;
        const request = self.nodes_view.takeSubscriptionRequest();
        if (request == .none) return;
        if (self.active_node_subscription) |active| {
            if (request == .start) return;
            self.node_restart_pending = true;
            _ = self.data_plane.cancelSubscription(active);
            return;
        }
        try self.startNodeSubscription();
    }

    fn serviceNamespaceSubscriptionRequest(self: *App) !void {
        if (@import("view/NamespacesView.zig").active_namespace_source == .legacy_list) return;
        const request = self.namespaces_view.takeSubscriptionRequest();
        if (request == .none) return;
        if (self.active_namespace_subscription) |active| {
            if (request == .start) return;
            self.namespace_restart_pending = true;
            _ = self.data_plane.cancelSubscription(active);
            return;
        }
        try self.startNamespaceSubscription();
    }

    fn serviceResourceFamilyRequests(self: *App) !void {
        for (self.resource_families.registry.items(), 0..) |*entry, index| {
            const request = entry.takeRequest();
            if (request == .none) continue;
            if (entry.active) |active| {
                if (request == .start) continue;
                entry.restart_pending = true;
                _ = self.data_plane.cancelSubscription(active);
                continue;
            }
            self.startResourceFamilySubscription(index) catch |err| {
                markFamilyStartOutcome(entry, false);
                Logger.err("{s} subscription failed: {any}", .{ entry.name, err });
                continue;
            };
            markFamilyStartOutcome(entry, true);
        }
    }

    fn beginContextSwitch(self: *App, context_name: []const u8) !void {
        const owned_name = try self.allocator.dupe(u8, context_name);
        errdefer self.allocator.free(owned_name);
        if (self.pending_context_switch) |old_name| self.allocator.free(old_name);
        self.pending_context_switch = owned_name;
        self.pod_restart_pending = self.active_pod_subscription != null;
        self.node_restart_pending = self.active_node_subscription != null;
        self.namespace_restart_pending = self.active_namespace_subscription != null;
        self.resource_families.registry.markForContextRestart();
        self.cancelMetricsFeed();
        if (self.active_pod_subscription) |active| _ = self.data_plane.cancelSubscription(active);
        if (self.active_node_subscription) |active| _ = self.data_plane.cancelSubscription(active);
        if (self.active_namespace_subscription) |active| _ = self.data_plane.cancelSubscription(active);
        for (self.resource_families.registry.itemsConst()) |entry| {
            if (entry.active) |active| _ = self.data_plane.cancelSubscription(active);
        }
        if (self.hasActiveResourceSubscriptions()) return;
        try self.completeContextSwitch();
    }

    fn completeContextSwitch(self: *App) !void {
        const context_name = self.pending_context_switch orelse return;
        self.k8s_service.switchContext(context_name) catch |err| {
            self.allocator.free(context_name);
            self.pending_context_switch = null;
            return err;
        };
        self.allocator.free(context_name);
        self.pending_context_switch = null;
        try self.contexts_view.refresh();
        try self.switchToView(self.pre_contexts_view);
        if (self.pod_restart_pending) {
            self.pod_restart_pending = false;
            if (self.active_pod_subscription == null) try self.startPodSubscription();
        }
        if (self.node_restart_pending) {
            self.node_restart_pending = false;
            if (self.active_node_subscription == null) try self.startNodeSubscription();
        }
        if (self.namespace_restart_pending) {
            self.namespace_restart_pending = false;
            if (self.active_namespace_subscription == null) try self.startNamespaceSubscription();
        }
        startPendingFamilyEntries(
            &self.resource_families.registry,
            @ptrCast(self),
            struct {
                fn start(raw: *anyopaque, index: usize) anyerror!void {
                    const app: *App = @ptrCast(@alignCast(raw));
                    try app.startResourceFamilySubscription(index);
                }
            }.start,
            struct {
                fn failed(_: *anyopaque, entry: *family_registry.Entry, err: anyerror) void {
                    Logger.err("{s} subscription restart failed: {any}", .{ entry.name, err });
                }
            }.failed,
        );
        self.dirty = true;
    }

    fn startPodSubscription(self: *App) !void {
        if (!self.k8s_service.connected) return;
        const session_view = self.active_session_slot.view();
        if (session_view.state != .active) return error.NoActiveSession;
        const generation = session_view.generation;
        const namespace: ?[]const u8 = if (self.pods_view.table.show_all_namespaces)
            null
        else
            self.k8s_service.current_namespace;
        var spec = try pod_subscription.ownedTaskSpec(self.allocator, .{
            .namespace = namespace,
            .context_name = self.k8s_service.context_name,
            .projection = self.pod_projection,
            .telemetry = &self.perf_telemetry,
        });
        errdefer spec.deinit(self.allocator);
        const key = try self.data_plane.startSubscription(generation, &spec);
        self.active_pod_subscription = key;
        self.active_metrics_subscription = null;
        self.pod_metrics_started = false;
        self.pods_view.markPodSubscriptionStarted();
        self.pod_initial_batch_applied = false;
        self.pod_first_paint_emitted = false;
        self.pod_list_complete_revision = null;
        self.pod_complete_paint_emitted = false;
        self.pod_projection_apply_failed = false;
    }

    fn startNodeSubscription(self: *App) !void {
        if (!self.k8s_service.connected) return;
        const session_view = self.active_session_slot.view();
        if (session_view.state != .active) return error.NoActiveSession;
        var spec = try NodeSubscription.ownedTaskSpec(self.allocator, .{
            .context_name = self.k8s_service.context_name,
            .projection = self.node_projection,
        });
        errdefer spec.deinit(self.allocator);
        self.active_node_subscription = try self.data_plane.startSubscription(
            session_view.generation,
            &spec,
        );
        self.nodes_view.markSubscriptionStarted();
    }

    fn startNamespaceSubscription(self: *App) !void {
        if (!self.k8s_service.connected) return;
        const session_view = self.active_session_slot.view();
        if (session_view.state != .active) return error.NoActiveSession;
        var spec = try NamespaceSubscription.ownedTaskSpec(self.allocator, .{
            .context_name = self.k8s_service.context_name,
            .projection = self.namespace_projection,
        });
        errdefer spec.deinit(self.allocator);
        self.active_namespace_subscription = try self.data_plane.startSubscription(
            session_view.generation,
            &spec,
        );
        self.namespaces_view.markSubscriptionStarted();
    }

    fn startResourceFamilySubscription(self: *App, index: usize) !void {
        if (!self.k8s_service.connected) return;
        const session_view = self.active_session_slot.view();
        if (session_view.state != .active) return error.NoActiveSession;
        const entry = self.resource_families.registry.entryAt(index) orelse return error.InvalidFamilyIndex;
        const namespace = entry.namespace(self.k8s_service.current_namespace);
        var spec = try entry.taskSpecFn(
            self.allocator,
            self.k8s_service.context_name,
            namespace,
            entry.projection,
        );
        errdefer spec.deinit(self.allocator);
        entry.markStarted(try self.data_plane.startSubscription(
            session_view.generation,
            &spec,
        ));
    }

    fn hasActiveResourceSubscriptions(self: *const App) bool {
        return self.active_pod_subscription != null or
            self.active_node_subscription != null or
            self.active_namespace_subscription != null or
            self.resource_families.registry.hasActive();
    }

    fn startMetricsFeed(self: *App) !void {
        if (self.active_metrics_subscription != null) return;
        const pod_key = self.active_pod_subscription orelse return;
        const namespace: ?[]const u8 = if (self.pods_view.table.show_all_namespaces)
            null
        else
            self.k8s_service.current_namespace;
        var spec = try metrics_feed.ownedTaskSpec(self.allocator, .{
            .namespace = namespace,
            .projection = self.pod_projection,
        });
        errdefer spec.deinit(self.allocator);
        self.active_metrics_subscription = try self.data_plane.startSubscription(
            pod_key.generation,
            &spec,
        );
        self.pod_metrics_started = true;
    }

    fn cancelMetricsFeed(self: *App) void {
        if (self.active_metrics_subscription) |key| {
            _ = self.data_plane.cancelSubscription(key);
            self.active_metrics_subscription = null;
        }
    }

    fn emitPodTelemetry(
        self: *App,
        kind: perf.EventKind,
        revision: resource_key.Revision,
    ) void {
        self.perf_telemetry.emit(self.podTelemetryEvent(kind, revision));
    }

    fn emitMetricsTelemetry(self: *App, revision: resource_key.Revision) void {
        var event = self.podTelemetryEvent(.metrics_ready, revision);
        if (self.active_metrics_subscription) |key| {
            event.generation = key.generation;
            event.subscription_id = key.subscription_id;
        }
        self.perf_telemetry.emit(event);
    }

    fn podTelemetryEvent(
        self: *App,
        kind: perf.EventKind,
        revision: resource_key.Revision,
    ) perf.Event {
        const key = self.active_pod_subscription orelse lifecycle.SubscriptionKey{
            .generation = 0,
            .subscription_id = 0,
        };
        return .{
            .kind = kind,
            .monotonic_ns = @intCast(@max(clock.nanoTimestamp(), 0)),
            .context = self.k8s_service.context_name,
            .resource = "pods",
            .scope = if (self.pods_view.table.show_all_namespaces)
                "all_namespaces"
            else
                self.k8s_service.current_namespace,
            .generation = key.generation,
            .subscription_id = key.subscription_id,
            .applied_revision = revision,
            .object_count = self.pod_projection.count(),
            .queue_bytes = 0,
        };
    }

    fn drainChangeQueue(self: *App) void {
        var router = resource_key.UiRouter{
            .context = @ptrCast(self),
            .targetFn = appEnvelopeTarget,
            .lifecycleFn = appObserveLifecycle,
        };
        var n: usize = 0;
        while (n < resource_key.Limits.default.drain_batches) : (n += 1) {
            var popped = self.change_queue.popForRetry() orelse break;
            const envelope = &popped.envelope;
            if (!self.data_plane.acceptsEnvelope(envelope.*) or
                !self.acceptsActiveEnvelope(envelope.*))
            {
                popped.destroy(self.allocator);
                continue;
            }
            const target = envelope.target;
            const revision = envelope.revision;
            const sync_kind = envelope.sync_kind;
            const initial_changes = envelope.has_initial_changes;
            const effects = decideResourceDrainEffects(
                target,
                self.active_pod_subscription,
                self.active_metrics_subscription,
                self.active_node_subscription,
                self.active_namespace_subscription,
                sync_kind,
                initial_changes,
                self.pod_projection.count(),
                self.pod_metrics_started,
            );
            const is_pod_subscription = effects.sync_pod;
            const is_node_subscription = effects.sync_node;
            const is_namespace_subscription = effects.sync_namespace;
            const service_identity: ?resource_key.ResourceIdentity = switch (target) {
                .resource => |identity| if (self.resource_families.registry.contains(identity))
                    identity
                else
                    null,
                else => null,
            };
            envelope.apply(&router, self.allocator) catch |err| {
                Logger.err("envelope apply failed: {any}", .{err});
                if (is_pod_subscription) self.pod_projection_apply_failed = true;
                self.change_queue.retryPopped(&popped) catch popped.destroy(self.allocator);
                break;
            };
            popped.finishConsumed();
            if (target == .resource) {
                if (effects.sync_pod or effects.sync_metrics) {
                    self.pods_view.syncPodProjection() catch |err| {
                        Logger.err("pod projection adapter failed: {any}", .{err});
                        if (is_pod_subscription) self.pod_projection_apply_failed = true;
                        self.pod_projection_sync_pending = true;
                        self.dirty = true;
                        continue;
                    };
                    self.pod_projection_sync_pending = false;
                    if (effects.start_pod_metrics) {
                        self.pod_initial_batch_applied = true;
                        self.startMetricsFeed() catch |err| {
                            Logger.warn("metrics feed start failed: {any}", .{err});
                        };
                    }
                } else if (is_node_subscription) {
                    self.nodes_view.syncProjection() catch |err| {
                        Logger.err("node projection adapter failed: {any}", .{err});
                        self.dirty = true;
                        continue;
                    };
                } else if (is_namespace_subscription) {
                    self.namespaces_view.syncProjection() catch |err| {
                        Logger.err("namespace projection adapter failed: {any}", .{err});
                        self.dirty = true;
                        continue;
                    };
                } else if (service_identity) |identity| {
                    _ = self.resource_families.registry.sync(identity) catch |err| {
                        Logger.err("resource family projection adapter failed: {any}", .{err});
                        self.dirty = true;
                        continue;
                    };
                }
                if (sync_kind) |kind| switch (kind) {
                    .list_started => {},
                    .list_complete => if (effects.emit_pod_list_complete) {
                        self.pod_list_complete_revision = revision;
                        self.emitPodTelemetry(.list_complete_received, revision);
                    },
                    .watch_connected => if (effects.emit_pod_watch_connected) {
                        self.emitPodTelemetry(.watch_connected, revision);
                    },
                    .metrics_ready => if (effects.emit_metrics_ready)
                        self.emitMetricsTelemetry(revision),
                    .reconnecting => {},
                };
            }
            self.dirty = true;
        }
    }

    fn appEnvelopeTarget(raw: *anyopaque, target: resource_key.EnvelopeTarget) ?*anyopaque {
        const self: *App = @ptrCast(@alignCast(raw));
        return switch (target) {
            .resource => |identity| blk: {
                const active: ?lifecycle.SubscriptionKey, const projection: ?*anyopaque =
                    if (matchesIdentity(self.active_pod_subscription, identity))
                        .{ self.active_pod_subscription, @ptrCast(self.pod_projection) }
                    else if (matchesIdentity(self.active_metrics_subscription, identity))
                        .{ self.active_metrics_subscription, @ptrCast(self.pod_projection) }
                    else if (matchesIdentity(self.active_node_subscription, identity))
                        .{ self.active_node_subscription, @ptrCast(self.node_projection) }
                    else if (matchesIdentity(self.active_namespace_subscription, identity))
                        .{ self.active_namespace_subscription, @ptrCast(self.namespace_projection) }
                    else if (self.resource_families.registry.projectionFor(identity)) |projection|
                        .{ null, projection }
                    else
                        .{ null, null };
                if (projection == null) break :blk null;
                break :blk self.data_plane.resourceTarget(
                    target,
                    active orelse self.resource_families.registry.activeKeyFor(identity),
                    projection.?,
                );
            },
            .lifecycle => @ptrCast(self.data_plane),
            else => null,
        };
    }

    fn appObserveLifecycle(
        raw: *anyopaque,
        payload: *anyopaque,
        identity: ?resource_key.ResourceIdentity,
    ) void {
        const self: *App = @ptrCast(@alignCast(raw));
        const completion: *lifecycle.LifecycleCompletion = @ptrCast(@alignCast(payload));
        if (isActivePodCompletion(self.active_metrics_subscription, identity, completion.*)) {
            self.active_metrics_subscription = null;
            return;
        }
        if (isActivePodCompletion(self.active_pod_subscription, identity, completion.*)) {
            self.active_pod_subscription = null;
            self.cancelMetricsFeed();
            self.pods_view.markPodSubscriptionStopped();
            if (self.pod_restart_pending and self.pending_context_switch == null) {
                self.pod_restart_pending = false;
                self.startPodSubscription() catch |err| {
                    self.pods_view.table.setErrorFmt("Pod subscription failed: {any}", .{err}) catch {};
                    self.dirty = true;
                };
            }
        } else if (isActivePodCompletion(self.active_node_subscription, identity, completion.*)) {
            self.active_node_subscription = null;
            self.nodes_view.markSubscriptionStopped();
            if (self.node_restart_pending and self.pending_context_switch == null) {
                self.node_restart_pending = false;
                self.startNodeSubscription() catch |err| {
                    self.nodes_view.table.setErrorFmt("Node subscription failed: {any}", .{err}) catch {};
                    self.dirty = true;
                };
            }
        } else if (isActivePodCompletion(self.active_namespace_subscription, identity, completion.*)) {
            self.active_namespace_subscription = null;
            self.namespaces_view.markSubscriptionStopped();
            if (self.namespace_restart_pending and self.pending_context_switch == null) {
                self.namespace_restart_pending = false;
                self.startNamespaceSubscription() catch |err| {
                    self.namespaces_view.table.setErrorFmt("Namespace subscription failed: {any}", .{err}) catch {};
                    self.dirty = true;
                };
            }
        } else if (self.resource_families.registry.complete(identity, completion.*)) |index| {
            const entry = self.resource_families.registry.entryAt(index) orelse return;
            if (entry.enabled() and entry.restart_pending and self.pending_context_switch == null) {
                self.startResourceFamilySubscription(index) catch |err| {
                    markFamilyStartOutcome(entry, false);
                    Logger.err("{s} subscription failed: {any}", .{ entry.name, err });
                    self.dirty = true;
                    return;
                };
                markFamilyStartOutcome(entry, true);
            }
        } else return;

        if (self.pending_context_switch != null and !self.hasActiveResourceSubscriptions()) {
            self.completeContextSwitch() catch |err| {
                self.contexts_view.setError(err) catch {};
                self.dirty = true;
            };
        }
    }

    fn renderIfNeeded(self: *App) !void {
        if (self.pod_projection_sync_pending) {
            try self.pods_view.syncPodProjection();
            self.pod_projection_sync_pending = false;
            self.dirty = true;
        }
        const size = try self.terminal.getSize();
        const size_changed = self.prev_width != size.width or self.prev_height != size.height;
        if (!size_changed and !self.dirty) return;

        // Rate limit rendering to prevent excessive updates (60 FPS max).
        //
        // A dropped frame leaves dirty = true, but the loop then blocked in
        // poll(..., 100), so a keypress arriving just after a render was not drawn for
        // up to 100 ms -- visible as the highlight lagging behind a held arrow key.
        // Record how long is left in the frame so the loop can poll for exactly that.
        const now = clock.nanoTimestamp();
        const elapsed = now - self.last_render_time;
        if (!size_changed and elapsed < self.min_frame_time_ns) {
            const remaining_ns = self.min_frame_time_ns - elapsed;
            self.pending_frame_ms = @intCast(@divTrunc(remaining_ns, std.time.ns_per_ms) + 1);
            return;
        }
        self.pending_frame_ms = null;
        self.last_render_time = now;

        // Start DEC synchronized output mode
        try self.terminal.beginSyncOutput();
        var sync_output_open = true;
        defer if (sync_output_open) self.terminal.endSyncOutput() catch {};

        const new_header_height = if (self.view_fullscreen) 0 else self.header.height();
        const header_height_changed = self.header_height != new_header_height;
        self.header_height = new_header_height;
        const footer_height: u16 = if (self.footer_visible and !self.view_fullscreen) 1 else 0;
        const command_height: u16 = if (self.command_input.visible) 1 else 0;

        // Clear on resize OR header size change (compact toggle)
        if (size_changed or header_height_changed) {
            try self.terminal.clear();
        }

        // Update header and footer themes if we're previewing a theme
        const effective_theme = if (self.themes_view.preview_theme) |preview| preview else self.theme;
        self.header.setTheme(effective_theme);
        self.footer.setTheme(effective_theme);

        // Update header with current cluster info and server version
        // Only update header with cluster info after connection has been attempted
        if (self.k8s_service.hasAttemptedConnect()) {
            const cluster_info = self.k8s_service.getClusterInfo();
            self.header.updateClusterInfo(cluster_info.context, cluster_info.cluster, cluster_info.user) catch {};
            self.header.updateK8sVersion(self.k8s_service.getServerVersion()) catch {};
        }

        // Render header with hints from current view
        if (!self.view_fullscreen and size.height >= self.header_height) {
            if (self.view_manager.getCurrentView()) |current_view| {
                const hints = current_view.getHints();
                try self.header.render(&self.terminal, 0, 0, size.width, self.header_height, hints);
            } else {
                // No view on stack - render header with empty hints
                const hints_model = @import("model/hints.zig");
                const empty_hints: [0]hints_model.Hint = .{};
                const default_hints = hints_model.HintConfig{ .hints = &empty_hints };
                try self.header.render(&self.terminal, 0, 0, size.width, self.header_height, default_hints);
            }
        }

        // Calculate body area
        const body_start = if (size.height >= self.header_height + command_height)
            self.header_height + command_height
        else
            size.height;
        var body_height: u16 = 0;
        if (size.height > body_start) {
            const remaining = size.height - body_start;
            body_height = if (remaining > footer_height) remaining - footer_height else remaining;
        }

        // Render current view inside a box border
        if (body_height > 0) {
            if (self.view_manager.getCurrentView()) |current_view| {
                // Draw box border at framework level
                const view_name = current_view.getName();
                self.footer.current_resource = view_name;
                // Box header shows the decorated title (e.g. "pods(default)[8]"
                // or "aliases[123]") when the view provides one; otherwise the
                // plain name.
                const dyn_title = current_view.getTitle();
                const box_title = if (dyn_title.len == 0)
                    view_name
                else
                    dyn_title;
                try BoxDrawing.Box.createBox(&self.terminal, 0, body_start, size.width, body_height, effective_theme.proc_box, effective_theme.main_bg, box_title, .rounded, effective_theme.main_fg, effective_theme.title_highlight);
                // Render view inside the box (inner coordinates)
                if (body_height > 2 and size.width > 2) {
                    const inner_x: u16 = 1;
                    const inner_y = body_start + 1;
                    const inner_w = size.width - 2;
                    const inner_h = body_height - 2;

                    // Views that work without a cluster connection
                    const offline_ok = std.mem.eql(u8, view_name, "contexts") or
                        std.mem.eql(u8, view_name, "themes") or
                        std.mem.eql(u8, view_name, "help");

                    // NB: do NOT clearRegion here. createBox already fills the
                    // interior every frame with the theme's main_bg; clearRegion
                    // reset it to the terminal's DEFAULT bg, so cells (painted
                    // with main_bg) showed as lighter blocks on a darker
                    // interior — most visible in sparse layouts like namespaces.

                    if (!self.k8s_service.isConnected() and !offline_ok and self.k8s_service.hasAttemptedConnect()) {
                        try self.renderDisconnectedDialog(inner_x, inner_y, inner_w, inner_h);
                    } else {
                        try current_view.render(&self.terminal, inner_x, inner_y, inner_w, inner_h);
                    }
                }
            } else {
                // No view - show error message
                const error_msg = "No view loaded - press :pods to start";
                const msg_y = body_start + (body_height / 2);
                try Theme.writeStringWithTheme(&self.terminal, 2, msg_y, error_msg, self.theme.status_failed, self.theme.main_bg);
            }
        }

        // Render footer (only if visible)
        if (self.footer_visible and size.height >= footer_height and size.height > 0) {
            const footer_y = if (body_height > 0)
                body_start + body_height
            else if (size.height > 0)
                size.height - 1
            else
                0;
            if (footer_y < size.height) {
                // Update footer status before rendering
                if (self.themes_view.preview_theme != null) {
                    self.footer.setPreviewStatus(self.themes_view.getSelectedThemeName());
                } else {
                    self.footer.setPreviewStatus(null);
                }
                const view_hint = if (self.view_manager.getCurrentView()) |v| v.getStatusHint() else null;
                if (view_hint) |hint| {
                    self.footer.setStatus(hint);
                } else if (self.view_manager.getCurrentView()) |v| {
                    // Bridge (labeled — remove with maybeAutoRefresh's all-ns guard):
                    // Show a persistent hint when auto-refresh is intentionally deferred
                    // for all-namespace views. Keeps the user aware that data is static
                    // until they press r. Condition mirrors maybeAutoRefresh exactly.
                    if (v.showsAllNamespaces() and self.k8s_service.isConnected() and self.config.refresh_rate > 0) {
                        self.footer.setStatus("all-ns: press Ctrl-r to refresh");
                    } else if (self.k8s_service.isConnected()) {
                        self.footer.setStatus(null);
                    } else if (!self.k8s_service.hasAttemptedConnect()) {
                        self.footer.setStatus("Connecting...");
                    } else {
                        self.footer.setStatus("Not connected to Kubernetes cluster");
                    }
                } else if (self.k8s_service.isConnected()) {
                    self.footer.setStatus(null);
                } else if (!self.k8s_service.hasAttemptedConnect()) {
                    self.footer.setStatus("Connecting...");
                } else {
                    self.footer.setStatus("Not connected to Kubernetes cluster");
                }
                if (self.crumbs_visible and self.view_manager.getDepth() >= 2) {
                    self.footer.setCrumbs(self.view_manager.writeCrumbs(&self.crumb_buf));
                } else {
                    self.footer.setCrumbs("");
                }
                try self.footer.render(&self.terminal, 0, footer_y, size.width, footer_height);
            }
        }

        // Render command input (always call to clear when hidden)
        if (size.height > self.header_height) {
            try self.command_input.render(&self.terminal, 0, self.header_height, size.width);
        } else if (!self.command_input.visible) {
            try self.terminal.hideCursor();
        }

        try self.terminal.flush();
        try self.terminal.endSyncOutput();
        sync_output_open = false;
        self.markPodPaintsAfterFlush();
        self.prev_width = size.width;
        self.prev_height = size.height;
        self.dirty = false;
    }

    fn markPodPaintsAfterFlush(self: *App) void {
        const current = self.view_manager.getCurrentView() orelse return;
        const applied_revision = self.pod_projection.appliedRevision();
        perf.emitPodPaintsAfterFlush(
            &self.perf_telemetry,
            &self.pod_first_paint_emitted,
            &self.pod_complete_paint_emitted,
            .{
                .current_is_pods = std.mem.eql(u8, current.getName(), "pods"),
                .initial_applied = self.pod_initial_batch_applied,
                .loading = self.pods_view.table.loading,
                .has_error = self.pods_view.table.error_message != null,
                .visible_rows = self.pods_view.table.filtered_indices.items.len,
                .flush_succeeded = true,
                .close_succeeded = true,
                .list_complete_revision = self.pod_list_complete_revision,
                .applied_revision = applied_revision,
                .apply_failed = self.pod_projection_apply_failed,
            },
            self.podTelemetryEvent(.first_usable_paint, applied_revision),
            self.podTelemetryEvent(
                .complete_sync_paint,
                self.pod_list_complete_revision orelse applied_revision,
            ),
        );
    }

    fn updateHeaderMetrics(self: *App) void {
        if (!self.k8s_service.isConnected()) return;

        // Fetch node metrics via /apis/metrics.k8s.io/v1beta1/nodes
        const body = self.k8s_service.kubectlRequest("/apis/metrics.k8s.io/v1beta1/nodes") catch return;
        defer self.allocator.free(body);

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, body, .{
            .ignore_unknown_fields = true,
        }) catch return;
        defer parsed.deinit();

        const items = if (parsed.value == .object)
            if (parsed.value.object.get("items")) |it| if (it == .array) it.array.items else null else null
        else
            null;
        if (items == null) return;

        var total_cpu_millicores: u64 = 0;
        var total_mem_bytes: u64 = 0;

        for (items.?) |node| {
            if (node != .object) continue;
            const usage = node.object.get("usage") orelse continue;
            if (usage != .object) continue;

            if (usage.object.get("cpu")) |cpu_val| {
                if (cpu_val == .string) {
                    if (klient.MetricsClient.parseCpuMillicores(cpu_val.string)) |mc| {
                        total_cpu_millicores += mc;
                    }
                }
            }
            if (usage.object.get("memory")) |mem_val| {
                if (mem_val == .string) {
                    if (klient.MetricsClient.parseMemoryBytes(mem_val.string)) |bytes| {
                        total_mem_bytes += bytes;
                    }
                }
            }
        }

        // Convert to approximate percentages (rough estimate based on typical node capacity)
        // A more accurate approach would fetch node capacity and compute actual usage %
        const node_count = items.?.len;
        if (node_count == 0) return;

        // Rough heuristic: assume ~4 cores and ~16GB per node on average
        const est_total_cpu = node_count * 4000; // millicores
        const est_total_mem = node_count * 16 * 1024 * 1024 * 1024; // bytes

        const cpu_pct: u8 = if (est_total_cpu > 0) @intCast(@min(total_cpu_millicores * 100 / est_total_cpu, 100)) else 0;
        const mem_pct: u8 = if (est_total_mem > 0) @intCast(@min(total_mem_bytes * 100 / est_total_mem, 100)) else 0;

        self.header.updateCpuMem(cpu_pct, mem_pct) catch {};
    }

    fn renderDisconnectedDialog(self: *App, x: u16, y: u16, w: u16, h: u16) !void {
        const lines = [_][]const u8{
            "Not connected to Kubernetes cluster",
            "",
            "Ensure your kubeconfig is valid and",
            "the cluster is reachable.",
            "",
            "Press  r  to retry connection",
            "Press  :ctx  to switch context",
        };
        const box_w: u16 = 42;
        const box_h: u16 = lines.len + 2; // +2 for top/bottom border

        // Center the dialog
        const box_x = if (w > box_w) x + (w - box_w) / 2 else x;
        const box_y = if (h > box_h) y + (h - box_h) / 2 else y;
        const actual_w = @min(box_w, w);
        const actual_h = @min(box_h, h);

        // Draw dialog box
        try BoxDrawing.Box.createBox(&self.terminal, box_x, box_y, actual_w, actual_h, self.theme.status_failed, self.theme.main_bg, null, .rounded, self.theme.main_fg, self.theme.title_highlight);

        // Render lines centered inside the box
        for (lines, 0..) |line, i| {
            const row: u16 = @intCast(i);
            if (row + 1 >= actual_h) break;
            const inner_w = actual_w -| 2;
            const text_x = if (line.len < inner_w) box_x + 1 + @as(u16, @intCast((inner_w - line.len) / 2)) else box_x + 1;
            const fg = if (i == 0) self.theme.status_failed else self.theme.main_fg;
            try Theme.writeStringWithTheme(&self.terminal, text_x, box_y + 1 + row, line, fg, self.theme.main_bg);
        }
    }

    /// pub so tests can drive the REAL dispatch path. Both previous key features
    /// shipped unreachable because their tests called the view directly.
    pub fn handleKey(self: *App, key: Key) !void {
        // Handle command input first
        if (self.command_input.visible) {
            switch (key) {
                // Arrow keys and Tab navigate the suggestion dropdown
                .down => {
                    self.command_input.moveSelection(1);
                    self.dirty = true;
                    return;
                },
                .up => {
                    self.command_input.moveSelection(-1);
                    self.dirty = true;
                    return;
                },
                // Tab (arrives as char 9) also steps forward through suggestions
                .char => |c| {
                    if (c == 9) {
                        self.command_input.moveSelection(1);
                        self.dirty = true;
                        return;
                    }
                    if (std.mem.eql(u8, self.command_input.prompt, ":") and (c == '[' or c == ']')) {
                        try self.historyStep(if (c == '[') -1 else 1);
                        return;
                    }
                    if (c >= 32 and c <= 126) {
                        try self.command_input.addChar(c);
                        self.liveFilterIfActive();
                        self.dirty = true;
                    }
                },
                // Terminal.readKey turns ':' '?' and 'G' into distinct Key variants
                // before App sees them, so they never arrive as .char and used to
                // fall through to `else => {}` -- silently dropped. That made a colon
                // untypeable in any prompt and a pod named "Gateway" unfilterable.
                // While a prompt is open these are ordinary text.
                .colon => {
                    try self.command_input.addChar(':');
                    self.liveFilterIfActive();
                    self.dirty = true;
                },
                .question_mark => {
                    try self.command_input.addChar('?');
                    self.liveFilterIfActive();
                    self.dirty = true;
                },
                .shift_g => {
                    try self.command_input.addChar('G');
                    self.liveFilterIfActive();
                    self.dirty = true;
                },
                .backspace => {
                    self.command_input.backspace();
                    self.liveFilterIfActive();
                    self.dirty = true;
                },
                .enter => {
                    // For ':' prompt: prefer the highlighted suggestion over the
                    // raw buffer — but only when the first token is not already a
                    // registered command. `:po kube-system` and `:dp /fred` must
                    // keep extras; replacing the whole line with "pods" dropped them.
                    const prompt = self.command_input.prompt;
                    const typed = self.command_input.getCommand();
                    const cmd_text = if (std.mem.eql(u8, prompt, ":")) blk: {
                        const extras = k9s_query.parseCommand(typed);
                        if (self.command_registry.contains(extras.name)) break :blk typed;
                        break :blk self.command_input.currentSuggestion() orelse typed;
                    } else typed;

                    if (self.pending_input != .none) {
                        self.dispatchPendingInput(cmd_text);
                        self.command_input.hide();
                        self.dirty = true;
                        return;
                    }

                    if (std.mem.eql(u8, prompt, "/")) {
                        // Apply filter to current view
                        if (self.delete_pending) {
                            // During delete confirmation, "y" confirms
                            if (std.mem.eql(u8, cmd_text, "y") or std.mem.eql(u8, cmd_text, "yes")) {
                                self.executeDelete() catch |err| {
                                    Logger.err("Delete failed: {any}", .{err});
                                };
                            }
                            self.clearDeleteState();
                        } else {
                            try self.applyFilterToCurrentView(cmd_text);
                        }
                    } else if (std.mem.eql(u8, prompt, ":")) {
                        try self.executePaletteCommand(cmd_text, true);
                    }

                    self.command_input.hide();
                    self.dirty = true;
                },
                .escape => {
                    self.command_input.hide();
                    self.clearPendingInput();
                    self.clearDeleteState();
                    self.dirty = true;
                },
                .ctrl_c => {
                    self.running = false;
                },
                else => {},
            }
            return;
        }

        // View-first dispatch.
        //
        // The global switch below claims specific keys ('x', '/', ':', '?', Ctrl-D,
        // ...) and only its `else` arm ever reaches the current view. So any
        // view-specific binding that collided with a global one was silently dead.
        //
        // That is not hypothetical. `x` = Decode on secrets and Ctrl-D = Stop on
        // port-forwards both SHIPPED unreachable, each with a passing test -- because
        // the tests called the view's handleKey directly and never went through App.
        // Verifying the ends and not the join, twice.
        //
        // Offering the key to the view first and falling through only on .not_handled
        // fixes the class rather than those two keys. Deliberately scoped to .char and
        // .ctrl_d: Escape and Enter carry App-level meaning (pop a sub-view, clear a
        // pending delete, push pods after a namespace switch) that a view returning
        // .handled must not be able to swallow.
        switch (key) {
            .char, .ctrl_d, .ctrl_w, .ctrl_z, .ctrl_l, .ctrl_r, .ctrl_backslash, .ctrl_space, .shift_left, .shift_right => {
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result != .not_handled) {
                        try self.handleViewResult(result, current_view, key);
                        return;
                    }
                }
            },
            else => {},
        }

        // Handle global keys
        switch (key) {
            .char => |c| switch (c) {
                '-' => {
                    try self.replayLastCommand();
                },
                '[' => try self.historyStep(-1),
                ']' => try self.historyStep(1),
                'x' => {
                    // Clear filter with 'x' key (like delete)
                    try self.applyFilterToCurrentView("");
                    self.dirty = true;
                },
                '/' => {
                    self.command_input.showWithPrompt("/");
                    self.dirty = true;
                },
                ':' => {
                    self.command_input.showWithPrompt(":");
                    self.dirty = true;
                },
                '?' => {
                    // Toggle help view - if already open, close it; otherwise open it
                    const help_is_active = self.view_manager.isViewActive("help");
                    Logger.info("Shift+? pressed, help_is_active={}", .{help_is_active});
                    if (help_is_active) {
                        Logger.info("Closing help view", .{});
                        _ = self.view_manager.popView();
                    } else {
                        Logger.info("Opening help view", .{});
                        try self.help_view.setViewType(self.currentViewType());
                        try self.view_manager.pushView(self.help_view.createView());
                    }
                    self.dirty = true;
                },
                else => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        try self.handleViewResult(result, current_view, key);
                    }
                },
            },
            .up => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .down => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .left => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .right => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .home => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .end => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .page_up => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .page_down => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .mouse => {
                // Pass clicks to the current view (e.g. DetailView fold toggling).
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    try self.handleViewResult(result, current_view, key);
                }
            },
            .escape => {
                // Clear delete state if pending
                if (self.delete_pending) {
                    self.clearDeleteState();
                    self.dirty = true;
                    return;
                }

                // First, check if there's an active filter to clear
                const filter_cleared = self.clearCurrentViewFilter() catch false;
                if (filter_cleared) {
                    self.dirty = true;
                    return;
                }

                // Only pop if we're in a pushed sub-view (depth > 1, like help/detail/logs view)
                if (self.view_manager.getDepth() > 1) {
                    _ = self.view_manager.popView();
                    // Restore current view name based on what's now on top
                    if (self.view_manager.getCurrentView()) |v| {
                        self.current_view_name = v.getName();
                    }
                    self.dirty = true;
                }
            },
            .ctrl_c => {
                self.running = false;
            },
            .ctrl_a => {
                // Ctrl+A: toggle the aliases view (full view; Ctrl-A again exits).
                self.toggleAliases() catch |err| {
                    Logger.err("Failed to toggle aliases: {any}", .{err});
                };
            },
            .ctrl_d => {
                // Ctrl+D: delete resource (graceful)
                if (self.view_manager.getCurrentView()) |_| {
                    self.handleDeleteRequest(false) catch |err| {
                        Logger.err("Delete request failed: {any}", .{err});
                    };
                }
            },
            .ctrl_k => {
                // Ctrl+K: kill — pass to current view (returns request_kill).
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    try self.handleViewResult(result, current_view, key);
                }
            },
            .shift_g => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .ctrl_f => {
                // Pass to current view (e.g. kill-finalizers), routing results.
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    try self.handleViewResult(result, current_view, key);
                }
            },
            .ctrl_b => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
                }
            },
            .question_mark => {
                // Toggle help view (Shift+?)
                Logger.debug("question_mark key received", .{});
                const help_is_active = self.view_manager.isViewActive("help");
                Logger.debug("help_is_active={}", .{help_is_active});

                if (help_is_active) {
                    Logger.debug("Closing help view", .{});
                    _ = self.view_manager.popView();
                } else {
                    Logger.debug("Opening help view", .{});
                    try self.help_view.setViewType(self.currentViewType());
                    try self.view_manager.pushView(self.help_view.createView());
                }
                self.dirty = true;
            },
            .colon => {
                self.command_input.showWithPrompt(":");
                self.dirty = true;
            },
            .ctrl_p => {
                // Ctrl-P opens the fuzzy command palette, same as ':'.
                // Candidates were set once at startup (setCandidates).
                self.command_input.showWithPrompt(":");
                self.dirty = true;
            },
            .backspace => {},
            .enter => {
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    try self.handleViewResult(result, current_view, key);
                }
            },
            .unsupported => {},
            .ctrl_e => {
                self.header.toggleCompact();
                self.dirty = true;
            },
            .ctrl_s => try self.saveSelectedResource(),
            .ctrl_g => {
                self.crumbs_visible = !self.crumbs_visible;
                self.dirty = true;
            },
            .ctrl_w, .ctrl_z, .ctrl_l, .ctrl_r, .ctrl_backslash, .ctrl_space, .shift_left, .shift_right => {
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    try self.handleViewResult(result, current_view, key);
                }
            },
        }
    }

    /// Central handler for view KeyResult values
    fn handleViewResult(self: *App, result: View.KeyResult, current_view: View, key: Key) !void {
        defer self.serviceResourceSubscriptionRequests() catch |err| {
            Logger.err("resource subscription transition failed: {any}", .{err});
        };
        if (readonlyAction(result)) |action| {
            if (self.refuseIfReadonly(action)) return;
        }
        switch (result) {
            .handled => self.dirty = true,
            .not_handled => {},
            .request_command_palette => {
                if (std.mem.eql(u8, current_view.getName(), "themes") and key == .enter) {
                    const selected_theme = self.themes_view.getSelectedThemeName();
                    try self.saveThemeToConfig(selected_theme);
                    try self.themes_view.setCurrentTheme(selected_theme);
                    self.dirty = true;
                } else {
                    self.command_input.showWithPrompt(":");
                    self.dirty = true;
                }
            },
            .request_filter => {
                self.command_input.showWithPrompt("/");
                self.dirty = true;
            },
            .context_switched => {
                const context_name = self.contexts_view.selectedContextName() orelse return;
                try self.beginContextSwitch(context_name);
            },
            .namespace_switched => {
                // Keep namespaces under pods so Esc returns to the namespace picker.
                try self.view_manager.pushView(self.pods_view.createView());
                self.current_view_name = "pods";

                // onShow preserves existing rows for instant stack navigation, but
                // those rows belong to the previous namespace. Refresh the new
                // destination only after it is on top.
                if (self.view_manager.getCurrentView()) |v| {
                    v.refresh() catch |err| {
                        Logger.err("Refresh after namespace switch failed: {any}", .{err});
                    };
                }
                self.dirty = true;
            },
            .request_decode => self.showDecodedSecret() catch |e| Logger.err("decode secret: {any}", .{e}),
            .request_drain => self.promptDrain(),
            .request_cordon => {
                self.setSelectedNodeSchedulable(false) catch |err| {
                    Logger.err("cordon failed: {any}", .{err});
                };
            },
            .request_uncordon => {
                self.setSelectedNodeSchedulable(true) catch |err| {
                    Logger.err("uncordon failed: {any}", .{err});
                };
            },
            .request_quit => {
                self.running = false;
            },
            .request_describe => {
                self.showDetailView(true) catch |err| {
                    Logger.err("Failed to show describe view: {any}", .{err});
                };
            },
            .request_yaml => {
                self.showDetailView(false) catch |err| {
                    Logger.err("Failed to show YAML view: {any}", .{err});
                };
            },
            .request_logs => {
                self.showLogsView(false) catch |err| {
                    Logger.err("Failed to show logs view: {any}", .{err});
                };
            },
            .request_logs_previous => {
                self.showLogsView(true) catch |err| {
                    Logger.err("Failed to show previous logs: {any}", .{err});
                };
            },
            .request_delete => {
                self.handleDeleteRequest(false) catch |err| {
                    Logger.err("Delete request failed: {any}", .{err});
                };
            },
            .request_kill => {
                // Ctrl-K: force kill (--grace-period=0 --force), with confirm.
                self.handleDeleteRequest(true) catch |err| {
                    Logger.err("Kill request failed: {any}", .{err});
                };
            },
            .request_edit => {
                self.runResourceEdit() catch |err| {
                    Logger.err("edit failed: {any}", .{err});
                };
            },
            .request_shell => {
                self.runPodShell() catch |err| {
                    Logger.err("shell failed: {any}", .{err});
                };
            },
            .request_attach => {
                self.runPodAttach() catch |err| {
                    Logger.err("attach failed: {any}", .{err});
                };
            },
            .request_show_node => {
                self.showSelectedNode() catch |err| {
                    Logger.err("show-node failed: {any}", .{err});
                };
            },
            .request_aliases => {
                self.toggleAliases() catch |err| {
                    Logger.err("Failed to toggle aliases: {any}", .{err});
                };
            },
            .request_kill_finalizers => self.doKillFinalizers() catch |e| Logger.err("kill-finalizers failed: {any}", .{e}),
            .request_set_image => self.promptSetImage() catch |e| Logger.err("set-image prompt: {any}", .{e}),
            .request_port_forward => self.promptPortForward() catch |e| Logger.err("port-forward prompt: {any}", .{e}),
            .request_transfer => self.promptTransfer() catch |e| Logger.err("transfer prompt: {any}", .{e}),
            .request_sanitize => self.promptSanitize(),
            .request_traffic => self.showTrafficView() catch |e| Logger.err("traffic view failed: {any}", .{e}),
            .request_copy => self.copySelectedField(.name),
            .request_copy_namespace => self.copySelectedField(.namespace),
            .request_warp => self.warpToSelectedNamespace() catch |e| Logger.err("warp failed: {any}", .{e}),
            .request_jump_owner => self.jumpToOwner() catch |e| Logger.err("jump-owner failed: {any}", .{e}),
            .request_used_by => self.showUsedBy() catch |e| Logger.err("used-by failed: {any}", .{e}),
            .request_restart => self.doRestart() catch |e| Logger.err("restart failed: {any}", .{e}),
            .request_scale => self.promptScale() catch |e| Logger.err("scale prompt: {any}", .{e}),
            .request_suspend => self.doSuspendToggle() catch |e| Logger.err("suspend failed: {any}", .{e}),
            .request_trigger => self.doTrigger() catch |e| Logger.err("trigger failed: {any}", .{e}),
            .request_rollback => self.doRollback() catch |e| Logger.err("rollback failed: {any}", .{e}),
            .request_view_replicasets => self.viewReplicaSets() catch |e| Logger.err("view RS failed: {any}", .{e}),
            .request_fullscreen => {
                self.view_fullscreen = !self.view_fullscreen;
                self.dirty = true;
            },
            .request_show_port_forwards => {
                try self.switchToView("pf");
            },
        }
    }

    pub fn dispatchViewResultForTest(self: *App, result: View.KeyResult) !void {
        const current = self.view_manager.getCurrentView() orelse return error.NoCurrentView;
        try self.handleViewResult(result, current, .unsupported);
    }

    fn showTrafficView(self: *App) !void {
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        self.traffic_view.setTarget(info.name, info.namespace);
        self.traffic_view.setWake(&self.redraw_request);
        try self.view_manager.pushView(self.traffic_view.createView());
        self.dirty = true;
    }

    /// Suspend the TUI (leave raw mode + alternate screen), run an interactive
    /// command with the inherited terminal (so $EDITOR / shell work), then
    /// restore the TUI and refresh. Used by edit/shell/attach.
    fn runInteractive(self: *App, argv: []const []const u8) !void {
        // Pin kubectl to the app's active context: after an in-app context
        // switch, the shell kubeconfig's current-context may point at a
        // different cluster than the one the user is looking at.
        var pinned = std.ArrayListUnmanaged([]const u8).empty;
        defer pinned.deinit(self.allocator);
        const ctx_name = self.k8s_service.context_name;
        const final_argv = if (argv.len > 0 and
            std.mem.eql(u8, argv[0], "kubectl") and
            !std.mem.eql(u8, ctx_name, "unknown"))
        blk: {
            try pinned.append(self.allocator, "kubectl");
            try pinned.append(self.allocator, "--context");
            try pinned.append(self.allocator, ctx_name);
            try pinned.appendSlice(self.allocator, argv[1..]);
            break :blk pinned.items;
        } else argv;

        self.terminal.disableRawMode();
        _ = self.terminal.exitAlternateScreen() catch {};

        var child = std.process.spawn(runtime.io(), .{ .argv = final_argv }) catch |err| {
            Logger.err("spawn failed: {any}", .{err});
            // Restore TUI even on spawn failure.
            try self.terminal.enterAlternateScreen();
            try self.terminal.enableRawMode();
            self.dirty = true;
            return;
        };
        _ = child.wait(runtime.io()) catch {};

        try self.terminal.enterAlternateScreen();
        try self.terminal.enableRawMode();
        self.dirty = true;
        self.prev_width = 0; // force a full redraw
        self.prev_height = 0;
    }

    fn runResourceEdit(self: *App) !void {
        // `kubectl edit` is a mutation, and it does NOT go through K8sService -- it
        // spawns kubectl directly, so the service-level --readonly guard never sees
        // it. Without this check `c3s --readonly` still let you edit live objects,
        // which is a hole in that guard rather than a separate feature gap.
        if (self.k8s_service.readonly) {
            self.footer.setStatus("Read-only mode: edit refused");
            self.dirty = true;
            return;
        }
        const rt = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        const target = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ rt.resourceName(), info.name });
        defer self.allocator.free(target);
        try self.runInteractive(&.{ "kubectl", "edit", target, "-n", info.namespace });
    }

    fn runPodShell(self: *App) !void {
        // An interactive shell can do anything the container can, so --readonly
        // refuses it. Read-only is a promise about the cluster, not merely about
        // which API verbs this process happens to call.
        if (self.k8s_service.readonly) {
            self.footer.setStatus("Read-only mode: shell refused");
            self.dirty = true;
            return;
        }
        if (!std.mem.eql(u8, self.current_view_name, "pods")) return;
        const info = self.pods_view.getSelectedResourceInfo() orelse return;
        try self.runInteractive(&.{ "kubectl", "exec", "-it", info.name, "-n", info.namespace, "--", "sh", "-c", "bash || sh" });
    }

    fn runPodAttach(self: *App) !void {
        // attach gives stdin to the container's main process -- same reasoning as
        // runPodShell.
        if (self.k8s_service.readonly) {
            self.footer.setStatus("Read-only mode: attach refused");
            self.dirty = true;
            return;
        }
        if (!std.mem.eql(u8, self.current_view_name, "pods")) return;
        const info = self.pods_view.getSelectedResourceInfo() orelse return;
        try self.runInteractive(&.{ "kubectl", "attach", "-it", info.name, "-n", info.namespace });
    }

    fn showSelectedNode(self: *App) !void {
        // Switch to the nodes view (focusing the pod's node would need a node
        // filter; for now just open nodes).
        if (self.view_manager.getDepth() == 1) {
            _ = self.view_manager.popView();
            try self.view_manager.pushView(self.nodes_view.createView());
            self.current_view_name = "nodes";
            self.dirty = true;
        }
    }

    /// Toggle the aliases view (k9s Ctrl-A). It's a full depth-1 view (replaces
    /// the current one), so `:` commands work in it and Esc doesn't pop it;
    /// Ctrl-A again returns to the previous view.
    fn toggleAliases(self: *App) !void {
        if (std.mem.eql(u8, self.current_view_name, "aliases")) {
            try self.switchToView(self.pre_aliases_view);
            return;
        }
        self.pre_aliases_view = self.current_view_name;
        try self.aliases_view.refresh();
        // Replace whatever is showing with the aliases view at depth 1.
        while (self.view_manager.getDepth() > 1) _ = self.view_manager.popView();
        if (self.view_manager.getDepth() == 1) _ = self.view_manager.popView();
        try self.view_manager.pushView(self.aliases_view.createView());
        self.current_view_name = "aliases";
        self.dirty = true;
    }

    /// Switch to a view by its registered command alias (handles the depth-1
    /// pop+push), e.g. returning from the aliases view.
    pub fn switchToView(self: *App, name: []const u8) !void {
        var ctx = Command.CommandContext{
            .allocator = self.allocator,
            .view_manager = &self.view_manager,
            .data = self,
        };
        _ = self.command_registry.execute(name, &ctx) catch |err| {
            Logger.err("switchToView({s}) failed: {any}", .{ name, err });
        };
        try self.serviceResourceSubscriptionRequests();
        self.dirty = true;
    }

    fn clearPendingInput(self: *App) void {
        self.pending_input = .none;
        if (self.pending_name) |n| self.allocator.free(n);
        if (self.pending_namespace) |n| self.allocator.free(n);
        self.pending_name = null;
        self.pending_namespace = null;
        self.pending_type = null;
    }

    /// Capture the selected resource and open a labelled text-input prompt.
    fn beginResourcePrompt(self: *App, label: []const u8) !void {
        const rt = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        self.clearPendingInput();
        self.pending_type = rt;
        self.pending_name = try self.allocator.dupe(u8, info.name);
        self.pending_namespace = try self.allocator.dupe(u8, info.namespace);
        self.command_input.showWithPrompt(label);
        self.dirty = true;
    }

    fn promptSetImage(self: *App) !void {
        if (self.refuseIfReadonly("set-image")) return;
        try self.beginResourcePrompt("set image (container=image):");
        if (self.pending_name != null) self.pending_input = .set_image;
    }

    fn promptPortForward(self: *App) !void {
        if (self.refuseIfReadonly("port-forward")) return;
        try self.beginResourcePrompt("port-forward (local:remote):");
        if (self.pending_name != null) self.pending_input = .port_forward;
    }

    fn promptTransfer(self: *App) !void {
        if (self.refuseIfReadonly("cp")) return;
        try self.beginResourcePrompt("cp (src dst):");
        if (self.pending_name != null) self.pending_input = .transfer;
    }

    /// Refuse a mutation before any prompt is shown. A confirmation the flag will
    /// not honour is worse than no prompt -- same hole drain had before the
    /// call-site check.
    fn refuseIfReadonly(self: *App, action: []const u8) bool {
        if (!self.k8s_service.readonly) return false;
        var buf: [96]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "Read-only mode: {s} refused", .{action}) catch "Read-only mode: refused";
        self.footer.setStatus(msg);
        self.dirty = true;
        return true;
    }

    /// Ask before draining. Cordon needs no prompt -- it is reversible and evicts
    /// nothing -- but drain evicts running pods, so it gets the same y/n treatment
    /// sanitize has.
    fn promptDrain(self: *App) void {
        if (!std.mem.eql(u8, self.current_view_name, "nodes")) return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;

        // Refuse early, so --readonly never even shows a confirmation it will not honour.
        if (self.refuseIfReadonly("drain")) return;

        self.clearPendingInput();
        self.pending_name = self.allocator.dupe(u8, info.name) catch return;
        self.pending_input = .drain;
        var buf: [128]u8 = undefined;
        const label = std.fmt.bufPrint(&buf, "Drain {s}? [y/n]:", .{info.name}) catch "Drain node? [y/n]:";
        self.command_input.showWithPrompt(label);
        self.dirty = true;
    }

    /// Run `kubectl drain` with the TUI suspended, so the user sees eviction progress
    /// live and can Ctrl-C it.
    ///
    /// Drain can take minutes, so running it synchronously inside the render loop would
    /// freeze the UI with nothing on screen explaining why. runInteractive is the same
    /// mechanism edit/shell/attach use, and it inherits the terminal.
    ///
    /// Flag choices, both deliberate:
    ///   --ignore-daemonsets: without it drain fails on any cluster that runs a
    ///     DaemonSet, which is all of them.
    ///   --delete-emptydir-data: without it drain refuses pods with an emptyDir volume.
    /// `--force` is deliberately NOT passed: it deletes bare pods nothing will recreate,
    /// which is data loss rather than rescheduling. Without it kubectl refuses and says
    /// so, which is the right outcome for the user to decide on.
    fn doDrain(self: *App) !void {
        const name = self.pending_name orelse return;
        if (self.k8s_service.readonly) {
            self.footer.setStatus("Read-only mode: drain refused");
            self.dirty = true;
            return;
        }
        try self.runInteractive(&.{
            "kubectl",                "drain",
            name,                     "--ignore-daemonsets",
            "--delete-emptydir-data",
        });
        self.footer.setStatus("Drain finished");
        self.refreshCurrentView();
    }

    fn promptSanitize(self: *App) void {
        // Operates on the visible pods; no target capture needed.
        if (!std.mem.eql(u8, self.current_view_name, "pods")) return;
        if (self.refuseIfReadonly("sanitize")) return;
        self.clearPendingInput();
        self.pending_input = .sanitize;
        self.command_input.showWithPrompt("Sanitize completed/failed pods? [y/n]:");
        self.dirty = true;
    }

    /// Apply the value typed at a pending input prompt.
    fn dispatchPendingInput(self: *App, value: []const u8) void {
        if (self.k8s_service.readonly and self.pending_input != .none) {
            const action: []const u8 = switch (self.pending_input) {
                .set_image => "set-image",
                .port_forward => "port-forward",
                .transfer => "cp",
                .sanitize => "sanitize",
                .drain => "drain",
                .scale => "scale",
                .none => unreachable,
            };
            _ = self.refuseIfReadonly(action);
            self.clearPendingInput();
            return;
        }
        switch (self.pending_input) {
            .set_image => self.doSetImage(value) catch |e| Logger.err("set image failed: {any}", .{e}),
            .port_forward => self.doPortForward(value) catch |e| Logger.err("port-forward failed: {any}", .{e}),
            .transfer => self.doTransfer(value) catch |e| Logger.err("transfer failed: {any}", .{e}),
            .drain => {
                if (std.mem.eql(u8, value, "y") or std.mem.eql(u8, value, "yes")) {
                    self.doDrain() catch |e| Logger.err("drain failed: {any}", .{e});
                }
            },
            .sanitize => {
                if (std.mem.eql(u8, value, "y") or std.mem.eql(u8, value, "yes")) {
                    self.doSanitize() catch |e| Logger.err("sanitize failed: {any}", .{e});
                }
            },
            .scale => self.doScale(value) catch |e| Logger.err("scale failed: {any}", .{e}),
            .none => {},
        }
        self.clearPendingInput();
    }

    fn doSetImage(self: *App, value: []const u8) !void {
        const rt = self.pending_type orelse return;
        const name = self.pending_name orelse return;
        const ns = self.pending_namespace orelse return;
        const target = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ rt.resourceName(), name });
        defer self.allocator.free(target);
        try self.k8s_service.runKubectl(&.{ "set", "image", target, value, "-n", ns });
        self.footer.setStatus("image updated");
        self.refreshCurrentView();
    }

    fn doPortForward(self: *App, value: []const u8) !void {
        const rt = self.pending_type orelse return;
        const name = self.pending_name orelse return;
        const ns = self.pending_namespace orelse return;
        if (!PortForwardRegistry.isValidPortForwardSpec(value)) {
            self.footer.setStatus("invalid port-forward spec");
            self.dirty = true;
            return;
        }
        const target = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ rt.resourceName(), name });
        defer self.allocator.free(target);
        const child = try self.k8s_service.spawnKubectl(&.{ "port-forward", target, value, "-n", ns });
        // The registry copies the strings, so `target` is safe to free on return.
        self.port_forward_registry.add(target, value, ns, child) catch |err| {
            // Do not leak an untracked child: if we cannot record it, we can never
            // stop it either.
            var orphan = child;
            orphan.kill(runtime.io());
            return err;
        };
        self.footer.setStatus("port-forward started (:pf to list)");
    }

    fn doKillFinalizers(self: *App) !void {
        if (self.refuseIfReadonly("kill-finalizers")) return;
        const rt = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        const target = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ rt.resourceName(), info.name });
        defer self.allocator.free(target);
        try self.k8s_service.runKubectl(&.{ "patch", target, "-n", info.namespace, "--type=merge", "-p", "{\"metadata\":{\"finalizers\":null}}" });
        self.footer.setStatus("finalizers cleared");
        self.refreshCurrentView();
    }

    fn doTransfer(self: *App, value: []const u8) !void {
        // "src dst" — passed through to `kubectl cp` (e.g. ns/pod:/path ./local).
        var it = std.mem.tokenizeScalar(u8, value, ' ');
        const src = it.next() orelse return;
        const dst = it.next() orelse return;
        try self.k8s_service.runKubectl(&.{ "cp", src, dst });
        self.footer.setStatus("cp complete");
    }

    fn doSanitize(self: *App) !void {
        const rt = self.currentResourceType() orelse return;
        var killed: usize = 0;
        // pods_view rows are generic RowData: columns are namespace(0), name(1),
        // ready(2), status(3), cpu(4), mem(5), ip(6), node(7), age(8).
        for (self.pods_view.table.items.items) |pod| {
            const s = pod.columns[3];
            const is_terminal = std.mem.eql(u8, s, "Succeeded") or std.mem.eql(u8, s, "Failed") or
                std.mem.eql(u8, s, "Completed") or std.mem.eql(u8, s, "Error") or
                std.mem.eql(u8, s, "Evicted");
            if (!is_terminal) continue;
            self.k8s_service.deleteResource(rt, pod.columns[1], pod.columns[0], false) catch continue;
            killed += 1;
        }
        const msg = std.fmt.allocPrint(self.allocator, "Sanitized {d} pods", .{killed}) catch "Sanitized pods";
        defer if (!std.mem.eql(u8, msg, "Sanitized pods")) self.allocator.free(msg);
        self.footer.setStatus(msg);
        self.refreshCurrentView();
    }

    /// Map current view name to ViewType for context-aware help
    /// Test seam for currentViewType, which is private.
    pub fn currentViewTypeForTest(self: *App) ViewType {
        return self.currentViewType();
    }

    fn currentViewType(self: *App) ViewType {
        // Falls back to .generic, NOT .pods. Nine resource types (Ingresses,
        // NetworkPolicies, ResourceQuotas, LimitRanges, PDBs, HPA, PersistentVolumes,
        // Endpoints, StorageClasses) have no ViewType, and falling back to pods meant
        // `?` on an Ingress listed Shell, Logs, Attach and Sanitize -- none of which do
        // anything there. .generic lists only what is true on any resource view.
        return std.meta.stringToEnum(ViewType, self.current_view_name) orelse .generic;
    }

    /// Map current view name to ResourceType for describe/delete
    fn currentResourceType(self: *App) ?ResourceType {
        return std.meta.stringToEnum(ResourceType, self.current_view_name);
    }

    /// Get selected resource info from the current primary view
    fn getSelectedResourceFromCurrentView(self: *App) ?ResourceInfo {
        if (self.view_manager.getCurrentView()) |current| {
            return current.getSelectedResource();
        }
        return null;
    }

    /// Show detail view (describe or JSON)
    fn showDetailView(self: *App, describe: bool) !void {
        const resource_type = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;

        // Fetch raw JSON from K8s API
        const json_data = self.k8s_service.getRawJson(resource_type, info.name, info.namespace) catch |err| {
            Logger.err("Failed to get resource JSON: {any}", .{err});
            return;
        };
        defer self.allocator.free(json_data);

        // Secrets' `data`/`stringData` are credentials. `y` used to dump them
        // as raw JSON; `x` is the deliberate decode path. On parse failure we
        // refuse to show the body at all -- a truncated dump is still a leak.
        const display = if (resource_type == .secrets)
            secret_decode.redactSecretJson(self.allocator, json_data) catch {
                self.footer.setStatus("Secret response was not valid JSON");
                self.dirty = true;
                return;
            }
        else
            json_data;
        defer if (resource_type == .secrets) self.allocator.free(display);

        // Set content on detail view
        const title = if (describe)
            try std.fmt.allocPrint(self.allocator, "Describe {s}/{s}", .{ resource_type.resourceName(), info.name })
        else
            try std.fmt.allocPrint(self.allocator, "YAML {s}/{s}", .{ resource_type.resourceName(), info.name });
        defer self.allocator.free(title);

        if (describe) {
            try self.detail_view.setContentDescribe(display, title);
        } else {
            try self.detail_view.setContentJson(display, title);
        }

        // Push detail view as sub-view
        try self.view_manager.pushView(self.detail_view.createView());
        self.dirty = true;
    }

    /// Base64-decode the selected Secret and show it in the detail view.
    ///
    /// Not gated by --readonly: this reads, it does not mutate. RBAC still applies --
    /// the GET fails on its own if the user cannot read secrets.
    fn showDecodedSecret(self: *App) !void {
        if (!std.mem.eql(u8, self.current_view_name, "secrets")) return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;

        const json_data = self.k8s_service.getRawJson(.secrets, info.name, info.namespace) catch |err| {
            Logger.err("Failed to get secret JSON: {any}", .{err});
            self.footer.setStatus("Could not read secret");
            self.dirty = true;
            return;
        };
        defer self.allocator.free(json_data);

        const decoded = secret_decode.decodeSecretData(self.allocator, json_data) catch |err| {
            // NotAnObject means the body was not a Secret at all -- an HTML error page
            // from a TLS-intercepting proxy, or a metav1.Status. Saying "empty" here
            // would be a lie about the user's cluster.
            Logger.err("Failed to decode secret: {any}", .{err});
            self.footer.setStatus("Secret response was not valid JSON");
            self.dirty = true;
            return;
        };
        defer self.allocator.free(decoded);

        const title = try std.fmt.allocPrint(self.allocator, "Decoded secret/{s}", .{info.name});
        defer self.allocator.free(title);

        try self.detail_view.setContentText(decoded, title);
        try self.view_manager.pushView(self.detail_view.createView());
        self.dirty = true;
    }

    /// Show logs view for selected pod
    fn showLogsView(self: *App, previous: bool) !void {
        if (!std.mem.eql(u8, self.current_view_name, "pods")) return;

        const info = self.pods_view.getSelectedResourceInfo() orelse return;

        // Fetch logs from K8s API (previous = the prior container instance).
        const log_data = self.k8s_service.getPodLogs(info.name, info.namespace, previous) catch |err| {
            Logger.err("Failed to get pod logs: {any}", .{err});
            return;
        };
        defer self.allocator.free(log_data);

        try self.logs_view.setContent(log_data, info.name);

        // Push logs view as sub-view
        try self.view_manager.pushView(self.logs_view.createView());
        self.dirty = true;
    }

    /// Handle delete request - enter confirmation mode
    fn handleDeleteRequest(self: *App, force: bool) !void {
        const resource_type = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;

        // Store delete state
        self.clearDeleteState();
        if (self.k8s_service.readonly) {
            self.footer.setStatus("Read-only mode: delete refused");
            self.dirty = true;
            return;
        }

        self.delete_pending = true;
        self.delete_force = force;
        self.delete_resource_name = try self.allocator.dupe(u8, info.name);
        self.delete_resource_namespace = try self.allocator.dupe(u8, info.namespace);
        self.delete_resource_type = resource_type;

        // Show confirmation prompt
        const verb = if (force) "Kill" else "Delete";
        const prompt_text = try std.fmt.allocPrint(self.allocator, "{s} {s}/{s}? [y/n]: ", .{ verb, resource_type.resourceName(), info.name });
        defer self.allocator.free(prompt_text);
        self.command_input.showWithPrompt("/");
        self.footer.setStatus(prompt_text);
        self.dirty = true;
    }

    /// Execute pending delete
    fn executeDelete(self: *App) !void {
        if (!self.delete_pending) return;

        const name = self.delete_resource_name orelse return;
        const namespace = self.delete_resource_namespace orelse return;
        const resource_type = self.delete_resource_type orelse return;

        self.k8s_service.deleteResource(resource_type, name, namespace, self.delete_force) catch |err| {
            Logger.err("Failed to delete {s}/{s}: {any}", .{ resource_type.resourceName(), name, err });
            self.footer.setStatus(if (err == error.ReadOnlyMode)
                "Read-only mode: delete refused"
            else
                "Delete failed");
            return;
        };

        Logger.info("Deleted {s}/{s} in namespace {s}", .{ resource_type.resourceName(), name, namespace });
        self.footer.setStatus(null);

        // Refresh current view
        self.refreshCurrentView();
        self.dirty = true;
    }

    /// Clear delete confirmation state
    fn clearDeleteState(self: *App) void {
        self.delete_pending = false;
        self.delete_force = false;
        if (self.delete_resource_name) |n| self.allocator.free(n);
        if (self.delete_resource_namespace) |n| self.allocator.free(n);
        self.delete_resource_name = null;
        self.delete_resource_namespace = null;
        self.delete_resource_type = null;
    }

    /// Apply filter to the current view
    /// Apply the in-progress filter text while the `/` prompt is being typed.
    ///
    /// k9s filters as you type; c3s only filtered on Enter, so you could not see what
    /// a pattern matched until you committed it.
    ///
    /// Three guards, and they are not optional:
    /// - only for the `/` prompt, since `:` is the command palette and filtering on
    ///   each keystroke of a command name is meaningless;
    /// - NOT while a delete confirmation is pending -- that reuses the same `/` prompt
    ///   for its y/n, so live-filtering there would rewrite the row list underneath a
    ///   destructive confirmation;
    /// - NOT while pending_input is set (set-image, port-forward, transfer,
    ///   sanitize), which also borrows the prompt for a value.
    fn liveFilterIfActive(self: *App) void {
        if (!shouldLiveFilter(
            self.command_input.visible,
            self.command_input.prompt,
            self.delete_pending,
            self.pending_input == .none,
        )) return;

        self.applyFilterToCurrentView(self.command_input.getCommand()) catch |err| {
            // A failed filter must not eat the keystroke; the Enter path will retry.
            Logger.warn("live filter failed: {any}", .{err});
        };
    }

    /// Whether an in-progress prompt keystroke should re-filter the current view.
    ///
    /// Pure so the guards are testable. The delete case is the one that matters: a
    /// pending confirmation borrows the SAME "/" prompt for its y/n, so getting this
    /// wrong would rewrite the row list under a destructive confirmation. That is not
    /// something to leave to an untested inline condition.
    fn shouldLiveFilter(
        visible: bool,
        prompt: []const u8,
        delete_pending: bool,
        pending_input_is_none: bool,
    ) bool {
        if (!visible) return false;
        if (!std.mem.eql(u8, prompt, "/")) return false;
        if (delete_pending) return false;
        if (!pending_input_is_none) return false;
        return true;
    }

    pub fn applyFilterToCurrentView(self: *App, filter: []const u8) !void {
        if (self.view_manager.getCurrentView()) |current| {
            try current.applyFilter(filter);
        }
        self.dirty = true;
    }

    /// Check if current view has an active filter and clear it
    fn clearCurrentViewFilter(self: *App) !bool {
        if (self.view_manager.getCurrentView()) |current| {
            return current.clearFilter();
        }
        return false;
    }

    /// Refresh the current view when the --refresh interval has elapsed.
    ///
    /// Called from the poll-timeout branch, which fires at least every 100 ms, so the
    /// interval is honoured without adding a timer or a thread.
    ///
    /// Deliberately skipped while a prompt is open or a delete confirmation is
    /// pending: refreshing under the user's cursor would move the selection out from
    /// under a `y/n` they are about to answer, and a destructive confirmation must
    /// stay pinned to the row it was opened for.
    fn maybeAutoRefresh(self: *App) void {
        if (!self.k8s_service.isConnected()) return;
        // Never refresh under an open prompt or a pending delete confirmation:
        // moving the selection while the user is answering y/n could retarget a
        // destructive action at a different row.
        if (self.command_input.visible or self.delete_pending) return;

        // Bridge (labeled — remove when background LIST+WATCH lands):
        //
        // refreshCurrentView() is a synchronous blocking LIST. In all-namespace
        // mode on large clusters (4 k+ pods) it takes 3–12 s. The main loop
        // DOES reach poll() after the LIST returns, but with the pre-fix timestamp
        // placement shouldAutoRefresh immediately re-fired on the next 100 ms tick
        // (elapsed ≥ interval), causing near-continuous blocking with ~100 ms gaps.
        //
        // The timestamp fix (last = completion time) gives a responsive window after
        // each LIST, but the LIST itself still blocks for 3–12 s, making the app feel
        // unresponsive for the duration. Deferring auto-refresh for all-namespace
        // views eliminates those stalls entirely; manual Ctrl-r still works. The footer
        // shows "all-ns: press Ctrl-r to refresh" (set in the render loop) so the user
        // knows data is not auto-refreshing.
        //
        // Delete this guard and the render-loop status message when watch snapshots
        // deliver data via redraw_request from a background thread.
        if (self.view_manager.getCurrentView()) |v| {
            if (!timerRefreshAllowed(
                v.getName(),
                resource_view.active_pod_source,
                resource_view.active_node_source,
                @import("view/NamespacesView.zig").active_namespace_source,
                resource_view.active_services_source,
                resource_view.active_config_source,
                resource_view.active_workloads_source,
                resource_view.active_batch_source,
                resource_view.active_networking_source,
                resource_view.active_storage_source,
            )) return;
            if (v.showsAllNamespaces()) return;
        }

        _ = App.runAutoRefreshCycle(
            self.config.refresh_rate,
            &self.last_auto_refresh_ns,
            clock.nanoTimestamp(),
            *App,
            self,
            struct {
                fn f(app: *App) void {
                    app.refreshCurrentView();
                }
            }.f,
            clock.nanoTimestamp,
        );
    }

    /// Scheduling primitive for periodic refresh. Calls refreshFn when the
    /// interval has elapsed; then records the time returned by clockFn — called
    /// AFTER refreshFn returns — as the new *last_ns.
    ///
    /// Keeping the clock capture after the refresh is the invariant that prevents
    /// a refresh storm: if refreshFn blocks longer than the interval, the next
    /// deadline is still `interval` seconds from completion, not from start.
    ///
    /// clockFn is injectable so tests can supply a known completion timestamp and
    /// assert that *last_ns holds that value (not the pre-call now_ns).
    ///
    /// Returns true when a refresh was performed.
    pub fn runAutoRefreshCycle(
        interval_s: f32,
        last_ns: *i128,
        now_ns: i128,
        comptime Ctx: type,
        ctx: Ctx,
        comptime refreshFn: fn (Ctx) void,
        comptime clockFn: fn () i128,
    ) bool {
        if (!shouldAutoRefresh(interval_s, last_ns.*, now_ns)) return false;
        refreshFn(ctx);
        last_ns.* = clockFn();
        return true;
    }

    /// Whether the auto-refresh interval has elapsed.
    ///
    /// Split out as a pure function so the timing rules are unit-testable; the rest of
    /// maybeAutoRefresh needs a live App and a cluster, and an untestable branch is
    /// how --refresh came to be parsed-but-never-read in the first place.
    ///
    /// `interval_s <= 0` disables refreshing. `last_ns == 0` means "never refreshed",
    /// which refreshes immediately rather than waiting out one interval first.
    fn shouldAutoRefresh(interval_s: f32, last_ns: i128, now_ns: i128) bool {
        if (!(interval_s > 0)) return false; // also rejects NaN
        if (last_ns == 0) return true;
        if (now_ns <= last_ns) return false; // clock went backwards; wait it out
        const interval_ns: i128 = @intFromFloat(@as(f64, interval_s) * @as(f64, std.time.ns_per_s));
        return now_ns - last_ns >= interval_ns;
    }

    /// Cordon or uncordon the selected node.
    ///
    /// No confirmation prompt: cordon is reversible and affects no running workload
    /// (it only stops NEW pods being scheduled). Drain, which evicts, would need the
    /// same confirmation flow delete has -- which is why it is not bound.
    fn setSelectedNodeSchedulable(self: *App, schedulable: bool) !void {
        if (!std.mem.eql(u8, self.current_view_name, "nodes")) return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;

        self.k8s_service.setNodeSchedulable(info.name, schedulable) catch |err| {
            self.footer.setStatus(if (err == error.ReadOnlyMode)
                "Read-only mode: cordon refused"
            else
                "Cordon failed");
            self.dirty = true;
            return err;
        };

        self.footer.setStatus(if (schedulable) "Node uncordoned" else "Node cordoned");
        self.refreshCurrentView();
    }

    fn executePaletteCommand(self: *App, cmd_text: []const u8, record: bool) !void {
        const extras = k9s_query.parseCommand(cmd_text);
        if (extras.context) |ctx_name| {
            if (ctx_name.len > 0) {
                self.k8s_service.switchContext(ctx_name) catch {
                    self.footer.setStatus("context switch failed");
                    self.dirty = true;
                    return;
                };
            }
        }

        var ctx = Command.CommandContext{
            .allocator = self.allocator,
            .view_manager = &self.view_manager,
            .data = self,
        };
        const ok = try self.command_registry.execute(extras.name, &ctx);
        if (!ok) {
            self.footer.setStatus("unknown command");
            self.dirty = true;
            return;
        }
        if (record) try self.recordHistory(cmd_text);

        if (extras.namespace) |ns| {
            try self.k8s_service.setCurrentNamespace(ns);
            if (self.view_manager.getCurrentView()) |v| v.setShowAllNamespaces(false);
            self.refreshCurrentView();
        }
        if (extras.labels) |sel| {
            var buf: [256]u8 = undefined;
            const f = std.fmt.bufPrint(&buf, "-l {s}", .{sel}) catch sel;
            try self.applyFilterToCurrentView(f);
        }
        if (extras.filter) |f| {
            try self.applyFilterToCurrentView(f);
        }
    }

    fn recordHistory(self: *App, cmd: []const u8) !void {
        const owned = try self.allocator.dupe(u8, cmd);
        errdefer self.allocator.free(owned);
        if (self.command_history.items.len >= 50) {
            const old = self.command_history.orderedRemove(0);
            self.allocator.free(old);
        }
        try self.command_history.append(self.allocator, owned);
        self.history_cursor = self.command_history.items.len;
    }

    fn replayLastCommand(self: *App) !void {
        if (self.command_history.items.len == 0) return;
        const last = self.command_history.items[self.command_history.items.len - 1];
        try self.executePaletteCommand(last, false);
    }

    fn historyStep(self: *App, delta: i32) !void {
        if (self.command_history.items.len == 0) return;
        var idx: i32 = @intCast(self.history_cursor);
        idx += delta;
        const max: i32 = @intCast(self.command_history.items.len - 1);
        if (idx < 0) idx = 0;
        if (idx > max) idx = max;
        self.history_cursor = @intCast(idx);
        if (!self.command_input.visible or !std.mem.eql(u8, self.command_input.prompt, ":")) {
            self.command_input.showWithPrompt(":");
        }
        try self.command_input.setText(self.command_history.items[self.history_cursor]);
        self.dirty = true;
    }

    fn copySelectedField(self: *App, field: enum { name, namespace }) void {
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        const text = switch (field) {
            .name => info.name,
            .namespace => info.namespace,
        };
        self.terminal.copyToClipboard(text) catch {
            self.footer.setStatus("copy failed");
            self.dirty = true;
            return;
        };
        self.footer.setStatus("copied");
        self.dirty = true;
    }

    fn warpToSelectedNamespace(self: *App) !void {
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        if (std.mem.eql(u8, info.namespace, "cluster")) return;
        try self.k8s_service.setCurrentNamespace(info.namespace);
        if (self.view_manager.getCurrentView()) |v| v.setShowAllNamespaces(false);
        self.refreshCurrentView();
    }

    fn jumpToOwner(self: *App) !void {
        const rt = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        const json_data = self.k8s_service.getRawJson(rt, info.name, info.namespace) catch {
            self.footer.setStatus("cannot fetch owner");
            self.dirty = true;
            return;
        };
        defer self.allocator.free(json_data);
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch {
            self.footer.setStatus("cannot parse owner");
            self.dirty = true;
            return;
        };
        defer parsed.deinit();
        const owner = k9s_query.firstOwnerRef(parsed.value) orelse {
            self.footer.setStatus("no owner");
            self.dirty = true;
            return;
        };
        const view = k9s_query.viewForOwnerKind(owner.kind) orelse {
            self.footer.setStatus("unknown owner kind");
            self.dirty = true;
            return;
        };
        const name = try self.allocator.dupe(u8, owner.name);
        defer self.allocator.free(name);
        try self.switchToView(view);
        try self.applyFilterToCurrentView(name);
    }

    fn showUsedBy(self: *App) !void {
        if (!k9s_query.usedByApplies(self.current_view_name)) return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        const name = try self.allocator.dupe(u8, info.name);
        defer self.allocator.free(name);
        const ns = try self.allocator.dupe(u8, info.namespace);
        defer self.allocator.free(ns);
        try self.k8s_service.setCurrentNamespace(ns);
        try self.switchToView("po");
        if (self.view_manager.getCurrentView()) |v| v.setShowAllNamespaces(false);
        self.refreshCurrentView();
        try self.applyFilterToCurrentView(name);
    }

    fn viewReplicaSets(self: *App) !void {
        if (!std.mem.eql(u8, self.current_view_name, "deployments")) return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        const name = try self.allocator.dupe(u8, info.name);
        defer self.allocator.free(name);
        const ns = try self.allocator.dupe(u8, info.namespace);
        defer self.allocator.free(ns);
        try self.k8s_service.setCurrentNamespace(ns);
        try self.switchToView("rs");
        if (self.view_manager.getCurrentView()) |v| v.setShowAllNamespaces(false);
        self.refreshCurrentView();
        try self.applyFilterToCurrentView(name);
    }

    fn runRollout(self: *App, verb: []const u8) !void {
        const rt = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        var target_buf: [256]u8 = undefined;
        const target = std.fmt.bufPrint(&target_buf, "{s}/{s}", .{ rt.resourceName(), info.name }) catch return;
        try self.k8s_service.runKubectl(&.{ "rollout", verb, target, "-n", info.namespace });
        self.footer.setStatus("rollout updated");
        self.refreshCurrentView();
    }

    fn doRestart(self: *App) !void {
        if (!k9s_query.restartApplies(self.current_view_name)) return;
        if (self.refuseIfReadonly("restart")) return;
        try self.runRollout("restart");
    }

    fn doRollback(self: *App) !void {
        if (!k9s_query.rollbackApplies(self.current_view_name)) return;
        if (self.refuseIfReadonly("rollback")) return;
        try self.runRollout("undo");
    }

    fn promptScale(self: *App) !void {
        if (!k9s_query.scaleApplies(self.current_view_name)) return;
        if (self.refuseIfReadonly("scale")) return;
        try self.beginResourcePrompt("replicas:");
        if (self.pending_name != null) self.pending_input = .scale;
    }

    fn doScale(self: *App, value: []const u8) !void {
        const replicas = std.mem.trim(u8, value, " \t");
        _ = std.fmt.parseInt(u32, replicas, 10) catch {
            self.footer.setStatus("invalid replica count");
            self.dirty = true;
            return;
        };
        const rt = self.pending_type orelse return;
        const name = self.pending_name orelse return;
        const ns = self.pending_namespace orelse return;
        var target_buf: [256]u8 = undefined;
        const target = std.fmt.bufPrint(&target_buf, "{s}/{s}", .{ rt.resourceName(), name }) catch return;
        var flag_buf: [40]u8 = undefined;
        const flag = std.fmt.bufPrint(&flag_buf, "--replicas={s}", .{replicas}) catch return;
        try self.k8s_service.runKubectl(&.{ "scale", target, flag, "-n", ns });
        self.footer.setStatus("scaled");
        self.refreshCurrentView();
    }

    fn doSuspendToggle(self: *App) !void {
        if (!std.mem.eql(u8, self.current_view_name, "cronjobs")) return;
        if (self.refuseIfReadonly("suspend")) return;
        const rt = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        const json_data = self.k8s_service.getRawJson(rt, info.name, info.namespace) catch {
            self.footer.setStatus("cannot fetch cronjob");
            self.dirty = true;
            return;
        };
        defer self.allocator.free(json_data);
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_data, .{}) catch {
            self.footer.setStatus("cannot parse cronjob");
            self.dirty = true;
            return;
        };
        defer parsed.deinit();
        const suspend_now = k9s_query.specSuspend(parsed.value);
        const patch: []const u8 = if (suspend_now)
            "{\"spec\":{\"suspend\":false}}"
        else
            "{\"spec\":{\"suspend\":true}}";
        var target_buf: [256]u8 = undefined;
        const target = std.fmt.bufPrint(&target_buf, "cronjobs/{s}", .{info.name}) catch return;
        try self.k8s_service.runKubectl(&.{ "patch", target, "-n", info.namespace, "--type=merge", "-p", patch });
        self.footer.setStatus(if (suspend_now) "cronjob resumed" else "cronjob suspended");
        self.refreshCurrentView();
    }

    fn doTrigger(self: *App) !void {
        if (!std.mem.eql(u8, self.current_view_name, "cronjobs")) return;
        if (self.refuseIfReadonly("trigger")) return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        var from_buf: [160]u8 = undefined;
        const from = std.fmt.bufPrint(&from_buf, "--from=cronjob/{s}", .{info.name}) catch return;
        var job_buf: [80]u8 = undefined;
        const ts: u64 = @intCast(@max(clock.timestamp(), 0));
        const job_name = std.fmt.bufPrint(&job_buf, "{s}-{d}", .{ info.name, ts }) catch return;
        const clipped = if (job_name.len > 63) job_name[0..63] else job_name;
        try self.k8s_service.runKubectl(&.{ "create", "job", clipped, from, "-n", info.namespace });
        self.footer.setStatus("job created");
        self.refreshCurrentView();
    }

    fn saveSelectedResource(self: *App) !void {
        const rt = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        const json_data = self.k8s_service.getRawJson(rt, info.name, info.namespace) catch {
            self.footer.setStatus("save failed");
            self.dirty = true;
            return;
        };
        defer self.allocator.free(json_data);
        const xdg = @import("core/xdg.zig");
        const dir = self.config.screen_dump_dir orelse (try xdg.ensurePaths()).dumps_dir;
        var path_buf: [512]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "{s}/{s}-{d}.json", .{ dir, info.name, clock.timestamp() }) catch {
            self.footer.setStatus("save path too long");
            self.dirty = true;
            return;
        };
        std.Io.Dir.cwd().writeFile(runtime.io(), .{ .sub_path = path, .data = json_data }) catch {
            self.footer.setStatus("save failed");
            self.dirty = true;
            return;
        };
        self.footer.setStatus("saved");
        self.dirty = true;
    }

    fn markRefreshCompleted(self: *App) void {
        self.last_auto_refresh_ns = clock.nanoTimestamp();
    }

    fn refreshCurrentView(self: *App) void {
        if (self.view_manager.getCurrentView()) |current| {
            current.refresh() catch |err| {
                Logger.err("Failed to refresh view: {any}", .{err});
            };
        }
        self.serviceResourceSubscriptionRequests() catch |err| {
            Logger.err("Failed to refresh resource subscription: {any}", .{err});
        };
        self.markRefreshCompleted();
        self.dirty = true;
    }

    /// Persist the selected theme.
    ///
    /// The rewriting itself is config.withTheme -- a pure function, so its edge cases
    /// (no `ui:` section, a commented-out `theme:`, CRLF, no trailing newline) are
    /// testable without an App. It used to be ~100 lines inlined here, and it was
    /// wrong: it emitted the new theme line and then let the OLD one through, and
    /// parseUiConfig takes the LAST match -- so choosing a theme applied for the
    /// session and silently reverted on restart, leaving a stale line behind each time.
    fn saveThemeToConfig(self: *App, theme_name: []const u8) !void {
        const xdg = @import("core/xdg.zig");
        const paths = try xdg.ensurePaths();

        const existing = std.Io.Dir.cwd().readFileAlloc(
            runtime.io(),
            paths.config_file,
            self.allocator,
            .limited(1024 * 1024),
        ) catch "";
        defer if (existing.len > 0) self.allocator.free(existing);

        const updated = try Config.withTheme(self.allocator, existing, theme_name);
        defer self.allocator.free(updated);

        try std.Io.Dir.cwd().writeFile(runtime.io(), .{
            .sub_path = paths.config_file,
            .data = updated,
        });

        // Keep the in-memory name in step with what was just written.
        self.allocator.free(self.current_theme_name);
        self.current_theme_name = try self.allocator.dupe(u8, theme_name);
        Logger.info("Theme saved: {s}", .{theme_name});
    }
};

// ============================================================================
// Comptime-generated view command handlers
// ============================================================================
/// Comptime table mapping App field names to view types.
/// Used by init/deinit loops and command generation.
/// All views in this table take (allocator, theme, k8s_service) for init.
const k8s_view_types = .{
    .{ "pods_view", PodsView },
    .{ "deployments_view", DeploymentsView },
    .{ "services_view", ServicesView },
    .{ "namespaces_view", NamespacesView },
    .{ "nodes_view", NodesView },
    .{ "statefulsets_view", StatefulSetsView },
    .{ "daemonsets_view", DaemonSetsView },
    .{ "replicasets_view", ReplicaSetsView },
    .{ "jobs_view", JobsView },
    .{ "cronjobs_view", CronJobsView },
    .{ "configmaps_view", ConfigMapsView },
    .{ "secrets_view", SecretsView },
    .{ "persistentvolumes_view", PersistentVolumesView },
    .{ "persistentvolumeclaims_view", PersistentVolumeClaimsView },
    .{ "ingresses_view", IngressesView },
    .{ "networkpolicies_view", NetworkPoliciesView },
    .{ "serviceaccounts_view", ServiceAccountsView },
    .{ "roles_view", RolesView },
    .{ "rolebindings_view", RoleBindingsView },
    .{ "clusterroles_view", ClusterRolesView },
    .{ "clusterrolebindings_view", ClusterRoleBindingsView },
    .{ "events_view", EventsView },
    .{ "resourcequotas_view", ResourceQuotasView },
    .{ "limitranges_view", LimitRangesView },
    .{ "poddisruptionbudgets_view", PodDisruptionBudgetsView },
    .{ "hpa_view", HPAView },
    .{ "endpoints_view", EndpointsView },
    .{ "storageclasses_view", StorageClassesView },
    .{ "gatewayclasses_view", GatewayClassesView },
    .{ "gateways_view", GatewaysView },
    .{ "httproutes_view", HTTPRoutesView },
    .{ "grpcroutes_view", GRPCRoutesView },
    .{ "referencegrants_view", ReferenceGrantsView },
    .{ "tcproutes_view", TCPRoutesView },
    .{ "tlsroutes_view", TLSRoutesView },
    .{ "udproutes_view", UDPRoutesView },
    .{ "backendtlspolicies_view", BackendTLSPoliciesView },
    .{ "listenersets_view", ListenerSetsView },
    .{ "endpointslices_view", EndpointSlicesView },
    .{ "ingressclasses_view", IngressClassesView },
    .{ "ipaddresses_view", IPAddressesView },
    .{ "servicecidrs_view", ServiceCIDRsView },
    .{ "volumeattributesclasses_view", VolumeAttributesClassesView },
    .{ "csidrivers_view", CSIDriversView },
    .{ "validatingadmissionpolicies_view", ValidatingAdmissionPoliciesView },
    .{ "validatingadmissionpolicybindings_view", ValidatingAdmissionPolicyBindingsView },
    .{ "mutatingadmissionpolicies_view", MutatingAdmissionPoliciesView },
    .{ "mutatingadmissionpolicybindings_view", MutatingAdmissionPolicyBindingsView },
    .{ "validatingwebhookconfigurations_view", ValidatingWebhookConfigurationsView },
    .{ "mutatingwebhookconfigurations_view", MutatingWebhookConfigurationsView },
    .{ "resourceclaims_view", ResourceClaimsView },
    .{ "deviceclasses_view", DeviceClassesView },
    .{ "priorityclasses_view", PriorityClassesView },
    .{ "runtimeclasses_view", RuntimeClassesView },
    .{ "leases_view", LeasesView },
    .{ "certificatesigningrequests_view", CertificateSigningRequestsView },
    .{ "storageversionmigrations_view", StorageVersionMigrationsView },
    .{ "contexts_view", ContextsView },
    .{ "authorization_view", AuthorizationView },
};

const ViewCommandEntry = struct {
    field: []const u8,
    view_name: []const u8,
    aliases: []const []const u8,
};

const view_commands = [_]ViewCommandEntry{
    .{ .field = "pods_view", .view_name = "pods", .aliases = &.{ "pods", "po" } },
    .{ .field = "port_forwards_view", .view_name = "portforwards", .aliases = &.{ "portforwards", "port-forwards", "portforward", "pf" } },
    .{ .field = "deployments_view", .view_name = "deployments", .aliases = &.{ "deployments", "deploy", "dp" } },
    .{ .field = "services_view", .view_name = "services", .aliases = &.{ "services", "svc" } },
    .{ .field = "namespaces_view", .view_name = "namespaces", .aliases = &.{ "namespaces", "namespace", "ns" } },
    .{ .field = "nodes_view", .view_name = "nodes", .aliases = &.{ "nodes", "no" } },
    .{ .field = "statefulsets_view", .view_name = "statefulsets", .aliases = &.{ "statefulsets", "sts" } },
    .{ .field = "daemonsets_view", .view_name = "daemonsets", .aliases = &.{ "daemonsets", "ds" } },
    .{ .field = "replicasets_view", .view_name = "replicasets", .aliases = &.{ "replicasets", "rs" } },
    .{ .field = "jobs_view", .view_name = "jobs", .aliases = &.{ "jobs", "job", "jo" } },
    .{ .field = "cronjobs_view", .view_name = "cronjobs", .aliases = &.{ "cronjobs", "cj" } },
    .{ .field = "configmaps_view", .view_name = "configmaps", .aliases = &.{ "configmaps", "cm" } },
    .{ .field = "secrets_view", .view_name = "secrets", .aliases = &.{ "secrets", "secret" } },
    .{ .field = "persistentvolumes_view", .view_name = "persistentvolumes", .aliases = &.{ "persistentvolumes", "pv" } },
    .{ .field = "persistentvolumeclaims_view", .view_name = "persistentvolumeclaims", .aliases = &.{ "persistentvolumeclaims", "pvc" } },
    .{ .field = "ingresses_view", .view_name = "ingresses", .aliases = &.{ "ingresses", "ing" } },
    .{ .field = "networkpolicies_view", .view_name = "networkpolicies", .aliases = &.{ "networkpolicies", "netpol" } },
    .{ .field = "serviceaccounts_view", .view_name = "serviceaccounts", .aliases = &.{ "serviceaccounts", "sa" } },
    .{ .field = "roles_view", .view_name = "roles", .aliases = &.{ "roles", "role" } },
    .{ .field = "rolebindings_view", .view_name = "rolebindings", .aliases = &.{ "rolebindings", "rb" } },
    .{ .field = "clusterroles_view", .view_name = "clusterroles", .aliases = &.{ "clusterroles", "cr" } },
    .{ .field = "clusterrolebindings_view", .view_name = "clusterrolebindings", .aliases = &.{ "clusterrolebindings", "crb" } },
    .{ .field = "events_view", .view_name = "events", .aliases = &.{ "events", "ev" } },
    .{ .field = "resourcequotas_view", .view_name = "resourcequotas", .aliases = &.{ "resourcequotas", "quota" } },
    .{ .field = "limitranges_view", .view_name = "limitranges", .aliases = &.{ "limitranges", "limits" } },
    .{ .field = "poddisruptionbudgets_view", .view_name = "poddisruptionbudgets", .aliases = &.{ "poddisruptionbudgets", "pdb" } },
    .{ .field = "hpa_view", .view_name = "hpa", .aliases = &.{ "horizontalpodautoscalers", "hpa" } },
    .{ .field = "endpoints_view", .view_name = "endpoints", .aliases = &.{ "endpoints", "ep" } },
    .{ .field = "storageclasses_view", .view_name = "storageclasses", .aliases = &.{ "storageclasses", "sc" } },
    .{ .field = "gatewayclasses_view", .view_name = "gatewayclasses", .aliases = &.{ "gatewayclasses", "gtwc" } },
    .{ .field = "gateways_view", .view_name = "gateways", .aliases = &.{ "gateways", "gtw", "gw" } },
    .{ .field = "httproutes_view", .view_name = "httproutes", .aliases = &.{ "httproutes", "htr" } },
    .{ .field = "grpcroutes_view", .view_name = "grpcroutes", .aliases = &.{ "grpcroutes", "grpcr" } },
    .{ .field = "referencegrants_view", .view_name = "referencegrants", .aliases = &.{ "referencegrants", "refgrant" } },
    .{ .field = "tcproutes_view", .view_name = "tcproutes", .aliases = &.{"tcproutes"} },
    .{ .field = "tlsroutes_view", .view_name = "tlsroutes", .aliases = &.{"tlsroutes"} },
    .{ .field = "udproutes_view", .view_name = "udproutes", .aliases = &.{"udproutes"} },
    .{ .field = "backendtlspolicies_view", .view_name = "backendtlspolicies", .aliases = &.{ "backendtlspolicies", "btlsp" } },
    .{ .field = "listenersets_view", .view_name = "listenersets", .aliases = &.{"listenersets"} },
    .{ .field = "endpointslices_view", .view_name = "endpointslices", .aliases = &.{ "endpointslices", "eps" } },
    .{ .field = "ingressclasses_view", .view_name = "ingressclasses", .aliases = &.{ "ingressclasses", "ic" } },
    .{ .field = "ipaddresses_view", .view_name = "ipaddresses", .aliases = &.{ "ipaddresses", "ipa" } },
    .{ .field = "servicecidrs_view", .view_name = "servicecidrs", .aliases = &.{"servicecidrs"} },
    .{ .field = "volumeattributesclasses_view", .view_name = "volumeattributesclasses", .aliases = &.{ "volumeattributesclasses", "vac" } },
    .{ .field = "csidrivers_view", .view_name = "csidrivers", .aliases = &.{ "csidrivers", "csi" } },
    .{ .field = "validatingadmissionpolicies_view", .view_name = "validatingadmissionpolicies", .aliases = &.{ "validatingadmissionpolicies", "vap" } },
    .{ .field = "validatingadmissionpolicybindings_view", .view_name = "validatingadmissionpolicybindings", .aliases = &.{ "validatingadmissionpolicybindings", "vapb" } },
    .{ .field = "mutatingadmissionpolicies_view", .view_name = "mutatingadmissionpolicies", .aliases = &.{ "mutatingadmissionpolicies", "mapolicy" } },
    .{ .field = "mutatingadmissionpolicybindings_view", .view_name = "mutatingadmissionpolicybindings", .aliases = &.{"mutatingadmissionpolicybindings"} },
    .{ .field = "validatingwebhookconfigurations_view", .view_name = "validatingwebhookconfigurations", .aliases = &.{ "validatingwebhookconfigurations", "vwc" } },
    .{ .field = "mutatingwebhookconfigurations_view", .view_name = "mutatingwebhookconfigurations", .aliases = &.{ "mutatingwebhookconfigurations", "mwc" } },
    .{ .field = "resourceclaims_view", .view_name = "resourceclaims", .aliases = &.{ "resourceclaims", "rclaim" } },
    .{ .field = "deviceclasses_view", .view_name = "deviceclasses", .aliases = &.{ "deviceclasses", "devicec" } },
    .{ .field = "priorityclasses_view", .view_name = "priorityclasses", .aliases = &.{ "priorityclasses", "pc" } },
    .{ .field = "runtimeclasses_view", .view_name = "runtimeclasses", .aliases = &.{ "runtimeclasses", "rtc" } },
    .{ .field = "leases_view", .view_name = "leases", .aliases = &.{"leases"} },
    .{ .field = "certificatesigningrequests_view", .view_name = "certificatesigningrequests", .aliases = &.{ "certificatesigningrequests", "csr" } },
    .{ .field = "storageversionmigrations_view", .view_name = "storageversionmigrations", .aliases = &.{"storageversionmigrations"} },
    .{ .field = "contexts_view", .view_name = "contexts", .aliases = &.{ "contexts", "context", "ctx" } },
    .{ .field = "themes_view", .view_name = "themes", .aliases = &.{"themes"} },
    .{ .field = "authorization_view", .view_name = "authorization", .aliases = &.{ "authorization", "auth" } },
};

/// Generate a view switch command from a field name and primary view enum.
fn makeViewCommand(comptime field_name: []const u8, comptime view_name: []const u8) *const fn (*Command.CommandContext) anyerror!void {
    return &struct {
        fn command(ctx_arg: *Command.CommandContext) anyerror!void {
            const app: *App = @ptrCast(@alignCast(ctx_arg.data.?));
            if (ctx_arg.view_manager.getDepth() == 1) {
                // Entering the contexts view: remember where we came from so
                // a context switch can return there (KeyResult.context_switched).
                if (comptime std.mem.eql(u8, view_name, "contexts")) {
                    if (!std.mem.eql(u8, app.current_view_name, "contexts")) {
                        app.pre_contexts_view = app.current_view_name;
                    }
                }
                _ = ctx_arg.view_manager.popView();
                try ctx_arg.view_manager.pushView(@field(app, field_name).createView());
                app.current_view_name = view_name;
            }
        }
    }.command;
}

// Special command handlers (non-generic)
fn quitCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    app.running = false;
}

fn helpCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    if (ctx.view_manager.isViewActive("help")) {
        _ = ctx.view_manager.popView();
    } else {
        try ctx.view_manager.pushView(app.help_view.createView());
    }
}

/// `:aliases` / `:al` — open the aliases view. No-op when already showing it
/// (so re-running from the palette doesn't bounce back to the previous view).
fn aliasesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    if (std.mem.eql(u8, app.current_view_name, "aliases")) return;
    try app.toggleAliases();
}

fn selectThemeCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    const selected_theme = app.themes_view.getSelectedThemeName();
    try app.saveThemeToConfig(selected_theme);
    try app.themes_view.setCurrentTheme(selected_theme);
}

/// Mark-manipulation palette commands. They drive the current view's existing
/// key handler so there is a single source of truth for the operation.
fn markChar(app: *App, c: u8) !void {
    if (app.view_manager.getCurrentView()) |v| {
        _ = try v.handleKey(.{ .char = c });
        app.dirty = true;
    }
}
fn selectAllCommand(ctx: *Command.CommandContext) !void {
    try markChar(@ptrCast(@alignCast(ctx.data.?)), '*');
}
fn clearMarksCommand(ctx: *Command.CommandContext) !void {
    try markChar(@ptrCast(@alignCast(ctx.data.?)), '\\');
}
fn invertMarksCommand(ctx: *Command.CommandContext) !void {
    try markChar(@ptrCast(@alignCast(ctx.data.?)), '^');
}

fn restartCommand(ctx: *Command.CommandContext) !void {
    try @as(*App, @ptrCast(@alignCast(ctx.data.?))).doRestart();
}
fn scaleCommand(ctx: *Command.CommandContext) !void {
    try @as(*App, @ptrCast(@alignCast(ctx.data.?))).promptScale();
}
fn suspendCommand(ctx: *Command.CommandContext) !void {
    try @as(*App, @ptrCast(@alignCast(ctx.data.?))).doSuspendToggle();
}
fn triggerCommand(ctx: *Command.CommandContext) !void {
    try @as(*App, @ptrCast(@alignCast(ctx.data.?))).doTrigger();
}
fn rollbackCommand(ctx: *Command.CommandContext) !void {
    try @as(*App, @ptrCast(@alignCast(ctx.data.?))).doRollback();
}

// SIGWINCH signal handler for terminal resize.
// Zig 0.16: Sigaction.handler_fn takes the SIG enum, not c_int.
fn handleResize(_: posix.SIG) callconv(.c) void {
    terminal_resized.store(true, .release);
}

fn setupResizeHandler() !void {
    const empty_set = std.mem.zeroes(posix.sigset_t);
    var sa = posix.Sigaction{
        .handler = .{ .handler = handleResize },
        .mask = empty_set,
        .flags = posix.SA.RESTART,
    };
    posix.sigaction(posix.SIG.WINCH, &sa, null);
}

fn podProjectionMatch(record: *const PodRecord, filter: []const u8) bool {
    if (filter.len == 0) return true;
    return containsIgnoreCase(record.key.name, filter) or
        containsIgnoreCase(record.key.namespace, filter) or
        containsIgnoreCase(record.phase, filter) or
        containsIgnoreCase(record.status_reason, filter) or
        containsIgnoreCase(record.node_name, filter) or
        containsIgnoreCase(record.pod_ip, filter);
}

fn containsIgnoreCase(value: []const u8, needle: []const u8) bool {
    if (needle.len > value.len) return false;
    var index: usize = 0;
    while (index + needle.len <= value.len) : (index += 1) {
        if (std.ascii.eqlIgnoreCase(value[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn podProjectionSortKey(record: *const PodRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        3 => if (record.status_reason.len > 0) record.status_reason else record.phase,
        9 => record.pod_ip,
        10 => record.node_name,
        else => record.key.name,
    };
}

fn nodeDataPlaneEnabled() bool {
    return resource_view.active_node_source == .data_plane;
}

fn nodeProjectionColumns(
    _: *NodeProjection,
    record: *const NodeRecord,
    allocator: std.mem.Allocator,
) ![6][]const u8 {
    return record.columns(allocator);
}

fn nodeProjectionMatch(record: *const NodeRecord, filter: []const u8) bool {
    if (filter.len == 0) return true;
    return containsIgnoreCase(record.key.name, filter);
}

fn nodeProjectionSortKey(record: *const NodeRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => record.status,
        2 => record.roles,
        3 => record.version,
        4 => record.internal_ip,
        5 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn namespaceProjectionMatch(record: *const NamespaceRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter);
}

fn namespaceProjectionSortKey(record: *const NamespaceRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => record.creation_timestamp orelse "",
        2 => record.status,
        else => record.key.name,
    };
}

fn servicesDataPlaneEnabled() bool {
    return resource_view.active_services_source == .data_plane;
}

fn serviceProjectionColumns(
    _: *ServiceProjection,
    record: *const ServiceRecord,
    allocator: std.mem.Allocator,
) ![7][]const u8 {
    return record.columns(allocator);
}

fn endpointProjectionColumns(
    _: *EndpointProjection,
    record: *const EndpointRecord,
    allocator: std.mem.Allocator,
) ![4][]const u8 {
    return record.columns(allocator);
}

fn endpointSliceProjectionColumns(
    _: *EndpointSliceProjection,
    record: *const EndpointSliceRecord,
    allocator: std.mem.Allocator,
) ![5][]const u8 {
    return record.columns(allocator);
}

fn serviceProjectionMatch(record: *const ServiceRecord, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.namespace, filter) or
        containsIgnoreCase(record.key.name, filter);
}

fn endpointProjectionMatch(record: *const EndpointRecord, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.namespace, filter) or
        containsIgnoreCase(record.key.name, filter);
}

fn endpointSliceProjectionMatch(record: *const EndpointSliceRecord, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.namespace, filter) or
        containsIgnoreCase(record.key.name, filter);
}

fn serviceProjectionSortKey(record: *const ServiceRecord, column: u8) []const u8 {
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

fn endpointProjectionSortKey(record: *const EndpointRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.endpoints,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn endpointSliceProjectionSortKey(record: *const EndpointSliceRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.address_type,
        3 => record.endpoints,
        4 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn configDataPlaneEnabled() bool {
    return resource_view.active_config_source == .data_plane;
}

fn workloadsDataPlaneEnabled() bool {
    return resource_view.active_workloads_source == .data_plane;
}

fn batchDataPlaneEnabled() bool {
    return resource_view.active_batch_source == .data_plane;
}

fn networkingDataPlaneEnabled() bool {
    return resource_view.active_networking_source == .data_plane;
}

fn storageDataPlaneEnabled() bool {
    return resource_view.active_storage_source == .data_plane;
}

fn configMapProjectionColumns(
    _: *ConfigMapProjection,
    record: *const ConfigMapRecord,
    allocator: std.mem.Allocator,
) ![4][]const u8 {
    return record.columns(allocator);
}

fn secretProjectionColumns(
    _: *SecretProjection,
    record: *const SecretRecord,
    allocator: std.mem.Allocator,
) ![5][]const u8 {
    return record.columns(allocator);
}

fn serviceAccountProjectionColumns(
    _: *ServiceAccountProjection,
    record: *const ServiceAccountRecord,
    allocator: std.mem.Allocator,
) ![4][]const u8 {
    return record.columns(allocator);
}

fn resourceQuotaProjectionColumns(
    _: *ResourceQuotaProjection,
    record: *const ResourceQuotaRecord,
    allocator: std.mem.Allocator,
) ![3][]const u8 {
    return record.columns(allocator);
}

fn limitRangeProjectionColumns(
    _: *LimitRangeProjection,
    record: *const LimitRangeRecord,
    allocator: std.mem.Allocator,
) ![3][]const u8 {
    return record.columns(allocator);
}

fn configMapProjectionMatch(record: *const ConfigMapRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn secretProjectionMatch(record: *const SecretRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn serviceAccountProjectionMatch(record: *const ServiceAccountRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn resourceQuotaProjectionMatch(record: *const ResourceQuotaRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn limitRangeProjectionMatch(record: *const LimitRangeRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn namespacedRecordMatches(record: anytype, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.namespace, filter) or
        containsIgnoreCase(record.key.name, filter);
}

fn configMapProjectionSortKey(record: *const ConfigMapRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => &record.data_sort_key,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn secretProjectionSortKey(record: *const SecretRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.secret_type,
        3 => &record.data_sort_key,
        4 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn serviceAccountProjectionSortKey(record: *const ServiceAccountRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => &record.secret_sort_key,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn resourceQuotaProjectionSortKey(record: *const ResourceQuotaRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn limitRangeProjectionSortKey(record: *const LimitRangeRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn deploymentProjectionColumns(
    _: *DeploymentProjection,
    record: *const DeploymentRecord,
    allocator: std.mem.Allocator,
) ![6][]const u8 {
    return record.columns(allocator);
}

fn statefulSetProjectionColumns(
    _: *StatefulSetProjection,
    record: *const StatefulSetRecord,
    allocator: std.mem.Allocator,
) ![4][]const u8 {
    return record.columns(allocator);
}

fn daemonSetProjectionColumns(
    _: *DaemonSetProjection,
    record: *const DaemonSetRecord,
    allocator: std.mem.Allocator,
) ![7][]const u8 {
    return record.columns(allocator);
}

fn replicaSetProjectionColumns(
    _: *ReplicaSetProjection,
    record: *const ReplicaSetRecord,
    allocator: std.mem.Allocator,
) ![6][]const u8 {
    return record.columns(allocator);
}

fn deploymentProjectionMatch(record: *const DeploymentRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn statefulSetProjectionMatch(record: *const StatefulSetRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn daemonSetProjectionMatch(record: *const DaemonSetRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn replicaSetProjectionMatch(record: *const ReplicaSetRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn deploymentProjectionSortKey(record: *const DeploymentRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => &record.ready_sort_key,
        3 => &record.updated_sort_key,
        4 => &record.available_sort_key,
        5 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn statefulSetProjectionSortKey(record: *const StatefulSetRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => &record.ready_sort_key,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn daemonSetProjectionSortKey(record: *const DaemonSetRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => &record.desired_sort_key,
        3 => &record.current_sort_key,
        4 => &record.ready_sort_key,
        5 => &record.updated_sort_key,
        6 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn replicaSetProjectionSortKey(record: *const ReplicaSetRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => &record.desired_sort_key,
        3 => &record.current_sort_key,
        4 => &record.ready_sort_key,
        5 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn jobProjectionColumns(
    _: *JobProjection,
    record: *const JobRecord,
    allocator: std.mem.Allocator,
) ![5][]const u8 {
    return record.columns(allocator);
}

fn cronJobProjectionColumns(
    _: *CronJobProjection,
    record: *const CronJobRecord,
    allocator: std.mem.Allocator,
) ![6][]const u8 {
    return record.columns(allocator);
}

fn hpaProjectionColumns(
    _: *HPAProjection,
    record: *const HPARecord,
    allocator: std.mem.Allocator,
) ![6][]const u8 {
    return record.columns(allocator);
}

fn pdbProjectionColumns(
    _: *PDBProjection,
    record: *const PDBRecord,
    allocator: std.mem.Allocator,
) ![6][]const u8 {
    return record.columns(allocator);
}

fn jobProjectionMatch(record: *const JobRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn cronJobProjectionMatch(record: *const CronJobRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn hpaProjectionMatch(record: *const HPARecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn pdbProjectionMatch(record: *const PDBRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn jobProjectionSortKey(record: *const JobRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => &record.completions_sort_key,
        3 => record.start_time orelse "",
        4 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn cronJobProjectionSortKey(record: *const CronJobRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.schedule,
        3 => if (record.@"suspend") "True" else "False",
        4 => &record.active_sort_key,
        5 => record.last_schedule_time orelse "",
        else => record.key.name,
    };
}

fn hpaProjectionSortKey(record: *const HPARecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => &record.min_sort_key,
        3 => &record.max_sort_key,
        4 => &record.current_sort_key,
        5 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn pdbProjectionSortKey(record: *const PDBRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => &record.min_available_sort_key,
        3 => &record.max_unavailable_sort_key,
        4 => &record.allowed_sort_key,
        5 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn ingressProjectionColumns(
    _: *IngressProjection,
    record: *const IngressRecord,
    allocator: std.mem.Allocator,
) ![7][]const u8 {
    return record.columns(allocator);
}

fn ingressClassProjectionColumns(
    _: *IngressClassProjection,
    record: *const IngressClassRecord,
    allocator: std.mem.Allocator,
) ![3][]const u8 {
    return record.columns(allocator);
}

fn networkPolicyProjectionColumns(
    _: *NetworkPolicyProjection,
    record: *const NetworkPolicyRecord,
    allocator: std.mem.Allocator,
) ![4][]const u8 {
    return record.columns(allocator);
}

fn ipAddressProjectionColumns(
    _: *IPAddressProjection,
    record: *const IPAddressRecord,
    allocator: std.mem.Allocator,
) ![3][]const u8 {
    return record.columns(allocator);
}

fn serviceCIDRProjectionColumns(
    _: *ServiceCIDRProjection,
    record: *const ServiceCIDRRecord,
    allocator: std.mem.Allocator,
) ![3][]const u8 {
    return record.columns(allocator);
}

fn ingressProjectionMatch(record: *const IngressRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn ingressClassProjectionMatch(record: *const IngressClassRecord, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.name, filter) or
        containsIgnoreCase(record.controller, filter);
}

fn networkPolicyProjectionMatch(record: *const NetworkPolicyRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn ipAddressProjectionMatch(record: *const IPAddressRecord, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.name, filter) or
        containsIgnoreCase(record.parent, filter);
}

fn serviceCIDRProjectionMatch(record: *const ServiceCIDRRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter);
}

fn ingressProjectionSortKey(record: *const IngressRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.class,
        3 => record.hosts,
        4 => record.address,
        5 => record.ports,
        6 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn ingressClassProjectionSortKey(record: *const IngressClassRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => record.controller,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn networkPolicyProjectionSortKey(record: *const NetworkPolicyRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.pod_selector,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn ipAddressProjectionSortKey(record: *const IPAddressRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => record.parent,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn serviceCIDRProjectionSortKey(record: *const ServiceCIDRRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => record.cidrs,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn pvProjectionColumns(_: *PVProjection, record: *const PVRecord, allocator: std.mem.Allocator) ![8][]const u8 {
    return record.columns(allocator);
}

fn pvcProjectionColumns(_: *PVCProjection, record: *const PVCRecord, allocator: std.mem.Allocator) ![8][]const u8 {
    return record.columns(allocator);
}

fn storageClassProjectionColumns(_: *StorageClassProjection, record: *const StorageClassRecord, allocator: std.mem.Allocator) ![6][]const u8 {
    return record.columns(allocator);
}

fn volumeAttributesClassProjectionColumns(_: *VolumeAttributesClassProjection, record: *const VolumeAttributesClassRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}

fn csiDriverProjectionColumns(_: *CSIDriverProjection, record: *const CSIDriverRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}

fn pvProjectionMatch(record: *const PVRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter) or containsIgnoreCase(record.claim, filter);
}

fn pvcProjectionMatch(record: *const PVCRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn storageClassProjectionMatch(record: *const StorageClassRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter) or containsIgnoreCase(record.provisioner, filter);
}

fn volumeAttributesClassProjectionMatch(record: *const VolumeAttributesClassRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter) or containsIgnoreCase(record.driver, filter);
}

fn csiDriverProjectionMatch(record: *const CSIDriverRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter);
}

fn pvProjectionSortKey(record: *const PVRecord, column: u8) []const u8 {
    return switch (column) {
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
}

fn pvcProjectionSortKey(record: *const PVCRecord, column: u8) []const u8 {
    return switch (column) {
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
}

fn storageClassProjectionSortKey(record: *const StorageClassRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => record.provisioner,
        2 => record.reclaim_policy,
        3 => record.bind_mode,
        4 => if (record.expansion) "true" else "false",
        5 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn volumeAttributesClassProjectionSortKey(record: *const VolumeAttributesClassRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => record.driver,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn csiDriverProjectionSortKey(record: *const CSIDriverRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => if (record.attach_required) "true" else "false",
        2 => if (record.pod_info) "true" else "false",
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn matchesPodEnvelope(
    active: ?lifecycle.SubscriptionKey,
    envelope: resource_key.Envelope,
) bool {
    return switch (envelope.target) {
        .lifecycle => true,
        .resource => |identity| if (active) |key|
            key.generation == identity.generation and
                key.subscription_id == identity.subscription_id
        else
            false,
        else => false,
    };
}

fn readonlyAction(result: View.KeyResult) ?[]const u8 {
    return switch (result) {
        .request_delete => "delete",
        .request_kill => "kill",
        .request_edit => "edit",
        .request_shell => "shell",
        .request_attach => "attach",
        .request_port_forward => "port-forward",
        .request_set_image => "set-image",
        .request_sanitize => "sanitize",
        .request_transfer => "cp",
        .request_kill_finalizers => "kill-finalizers",
        .request_drain => "drain",
        .request_cordon => "cordon",
        .request_uncordon => "uncordon",
        .request_restart => "restart",
        .request_scale => "scale",
        .request_suspend => "suspend",
        .request_trigger => "trigger",
        .request_rollback => "rollback",
        else => null,
    };
}

fn shouldStartMetricsFeed(
    is_pod_subscription: bool,
    initial_changes: bool,
    pod_count: usize,
    already_started: bool,
) bool {
    return is_pod_subscription and initial_changes and pod_count > 0 and !already_started;
}

fn markFamilyStartOutcome(entry: *family_registry.Entry, succeeded: bool) void {
    if (succeeded) entry.restart_pending = false;
}

fn startPendingFamilyEntries(
    registry: *family_registry.Registry,
    context: *anyopaque,
    startFn: *const fn (*anyopaque, usize) anyerror!void,
    failureFn: *const fn (*anyopaque, *family_registry.Entry, anyerror) void,
) void {
    for (registry.items(), 0..) |*entry, index| {
        if (!entry.restart_pending or !entry.enabled() or entry.active != null) continue;
        startFn(context, index) catch |err| {
            markFamilyStartOutcome(entry, false);
            failureFn(context, entry, err);
            continue;
        };
        markFamilyStartOutcome(entry, true);
    }
}

const ResourceDrainEffects = struct {
    sync_pod: bool = false,
    sync_metrics: bool = false,
    sync_node: bool = false,
    sync_namespace: bool = false,
    start_pod_metrics: bool = false,
    emit_pod_list_complete: bool = false,
    emit_pod_watch_connected: bool = false,
    emit_metrics_ready: bool = false,
};

fn decideResourceDrainEffects(
    target: resource_key.EnvelopeTarget,
    pod: ?lifecycle.SubscriptionKey,
    metrics: ?lifecycle.SubscriptionKey,
    node: ?lifecycle.SubscriptionKey,
    namespace: ?lifecycle.SubscriptionKey,
    sync_kind: ?resource_key.SyncKind,
    initial_changes: bool,
    pod_count: usize,
    pod_metrics_started: bool,
) ResourceDrainEffects {
    const identity = switch (target) {
        .resource => |value| value,
        else => return .{},
    };
    const sync_pod = matchesIdentity(pod, identity);
    const sync_metrics = matchesIdentity(metrics, identity);
    const sync_node = matchesIdentity(node, identity);
    const sync_namespace = matchesIdentity(namespace, identity);
    return .{
        .sync_pod = sync_pod,
        .sync_metrics = sync_metrics,
        .sync_node = sync_node,
        .sync_namespace = sync_namespace,
        .start_pod_metrics = shouldStartMetricsFeed(
            sync_pod,
            initial_changes,
            pod_count,
            pod_metrics_started,
        ),
        .emit_pod_list_complete = sync_pod and sync_kind == .list_complete,
        .emit_pod_watch_connected = sync_pod and sync_kind == .watch_connected,
        .emit_metrics_ready = sync_metrics and sync_kind == .metrics_ready,
    };
}

test "metrics feed starts only after first applied real pod batch and only once" {
    try std.testing.expect(!shouldStartMetricsFeed(false, true, 1, false));
    try std.testing.expect(!shouldStartMetricsFeed(true, false, 0, false));
    try std.testing.expect(!shouldStartMetricsFeed(true, true, 0, false));
    try std.testing.expect(shouldStartMetricsFeed(true, true, 1, false));
    try std.testing.expect(!shouldStartMetricsFeed(true, true, 1, true));
}

test "family restart pending clears only after successful start" {
    var entry: family_registry.Entry = undefined;
    entry.restart_pending = true;
    markFamilyStartOutcome(&entry, false);
    try std.testing.expect(entry.restart_pending);
    markFamilyStartOutcome(&entry, true);
    try std.testing.expect(!entry.restart_pending);
}

test "one family start failure does not block later registry entries" {
    const enabled = struct {
        fn call() bool {
            return true;
        }
    }.call;
    var entries = [_]family_registry.Entry{ undefined, undefined };
    for (&entries, 0..) |*entry, index| {
        entry.name = if (index == 0) "first" else "second";
        entry.active = null;
        entry.restart_pending = true;
        entry.enabledFn = enabled;
    }
    var registry = family_registry.Registry{ .entries = &entries };
    var started: usize = 0;
    startPendingFamilyEntries(
        &registry,
        @ptrCast(&started),
        struct {
            fn start(raw: *anyopaque, index: usize) !void {
                if (index == 0) return error.InjectedStartFailure;
                const count: *usize = @ptrCast(@alignCast(raw));
                count.* += 1;
            }
        }.start,
        struct {
            fn failed(_: *anyopaque, _: *family_registry.Entry, _: anyerror) void {}
        }.failed,
    );
    try std.testing.expect(entries[0].restart_pending);
    try std.testing.expect(!entries[1].restart_pending);
    try std.testing.expectEqual(@as(usize, 1), started);
}

test "unified resource registry contains cutover family entries with exact projections" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    const expected = [_][]const u8{
        "services",
        "endpoints",
        "endpointslices",
        "configmaps",
        "secrets",
        "serviceaccounts",
        "resourcequotas",
        "limitranges",
        "deployments",
        "statefulsets",
        "daemonsets",
        "replicasets",
        "jobs",
        "cronjobs",
        "hpa",
        "poddisruptionbudgets",
        "ingresses",
        "ingressclasses",
        "networkpolicies",
        "ipaddresses",
        "servicecidrs",
        "persistentvolumes",
        "persistentvolumeclaims",
        "storageclasses",
        "volumeattributesclasses",
        "csidrivers",
    };
    try std.testing.expectEqual(expected.len, app.resource_families.registry.itemsConst().len);
    for (app.resource_families.registry.items(), 0..) |*entry, index| {
        try std.testing.expectEqualStrings(expected[index], entry.name);
        const key = lifecycle.SubscriptionKey{
            .generation = 17,
            .subscription_id = @intCast(index + 1),
        };
        entry.markStarted(key);
        const identity = resource_key.ResourceIdentity{
            .generation = key.generation,
            .subscription_id = key.subscription_id,
        };
        try std.testing.expect(app.resource_families.registry.projectionFor(identity) == entry.projection);
        entry.markStopped();
    }
}

test "networking views preserve scope and request exact restarts" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    inline for (.{ app.ingresses_view, app.networkpolicies_view }) |view| {
        try std.testing.expect(!view.table.show_all_namespaces);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .{ .char = '0' });
        try std.testing.expect(view.table.show_all_namespaces);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
    inline for (.{ app.ingressclasses_view, app.ipaddresses_view, app.servicecidrs_view }) |view| {
        try std.testing.expect(!@TypeOf(view.*).view_config.is_namespaced);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
}

test "storage views preserve scope and request exact restarts" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    try std.testing.expect(!app.persistentvolumeclaims_view.table.show_all_namespaces);
    app.persistentvolumeclaims_view.markSubscriptionStarted();
    _ = try PersistentVolumeClaimsView.handleKey(app.persistentvolumeclaims_view, .{ .char = '0' });
    try std.testing.expect(app.persistentvolumeclaims_view.table.show_all_namespaces);
    try std.testing.expectEqual(.restart, app.persistentvolumeclaims_view.takeSubscriptionRequest());
    app.persistentvolumeclaims_view.markSubscriptionStarted();
    _ = try PersistentVolumeClaimsView.handleKey(app.persistentvolumeclaims_view, .ctrl_r);
    try std.testing.expectEqual(.restart, app.persistentvolumeclaims_view.takeSubscriptionRequest());
    inline for (.{
        app.persistentvolumes_view,
        app.storageclasses_view,
        app.volumeattributesclasses_view,
        app.csidrivers_view,
    }) |view| {
        try std.testing.expect(!@TypeOf(view.*).view_config.is_namespaced);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
}

test "batch views preserve default scope and request exact restart on toggle" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    inline for (.{
        .{ app.jobs_view, false },
        .{ app.cronjobs_view, false },
        .{ app.hpa_view, true },
        .{ app.poddisruptionbudgets_view, true },
    }) |case| {
        const view = case[0];
        try std.testing.expectEqual(case[1], view.table.show_all_namespaces);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .{ .char = '0' });
        try std.testing.expectEqual(!case[1], view.table.show_all_namespaces);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
}

test "workload views preserve default scope and request exact restart on toggle" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    inline for (.{
        .{ app.deployments_view, false },
        .{ app.statefulsets_view, false },
        .{ app.daemonsets_view, true },
        .{ app.replicasets_view, false },
    }) |case| {
        const view = case[0];
        try std.testing.expectEqual(case[1], view.table.show_all_namespaces);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .{ .char = '0' });
        try std.testing.expectEqual(!case[1], view.table.show_all_namespaces);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
}

test "config views preserve default scope and request exact restart on toggle" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    inline for (.{
        .{ app.configmaps_view, true },
        .{ app.secrets_view, false },
        .{ app.serviceaccounts_view, false },
        .{ app.resourcequotas_view, true },
        .{ app.limitranges_view, true },
    }) |case| {
        const view = case[0];
        try std.testing.expectEqual(case[1], view.table.show_all_namespaces);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .{ .char = '0' });
        try std.testing.expectEqual(!case[1], view.table.show_all_namespaces);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
}

test "config count columns use numeric projection sort keys" {
    const low_config = ConfigMapRecord{ .key = undefined, .data_count = 2, .data_sort_key = ConfigMapRecord.numericSortKey(2) };
    const high_config = ConfigMapRecord{ .key = undefined, .data_count = 10, .data_sort_key = ConfigMapRecord.numericSortKey(10) };
    try std.testing.expect(std.mem.order(
        u8,
        configMapProjectionSortKey(&low_config, 2),
        configMapProjectionSortKey(&high_config, 2),
    ) == .lt);

    const low_secret = SecretRecord{
        .key = undefined,
        .secret_type = undefined,
        .data_count = 2,
        .data_sort_key = ConfigMapRecord.numericSortKey(2),
    };
    const high_secret = SecretRecord{
        .key = undefined,
        .secret_type = undefined,
        .data_count = 10,
        .data_sort_key = ConfigMapRecord.numericSortKey(10),
    };
    try std.testing.expect(std.mem.order(
        u8,
        secretProjectionSortKey(&low_secret, 3),
        secretProjectionSortKey(&high_secret, 3),
    ) == .lt);

    const low_account = ServiceAccountRecord{
        .key = undefined,
        .secret_count = 2,
        .secret_sort_key = ConfigMapRecord.numericSortKey(2),
    };
    const high_account = ServiceAccountRecord{
        .key = undefined,
        .secret_count = 10,
        .secret_sort_key = ConfigMapRecord.numericSortKey(10),
    };
    try std.testing.expect(std.mem.order(
        u8,
        serviceAccountProjectionSortKey(&low_account, 2),
        serviceAccountProjectionSortKey(&high_account, 2),
    ) == .lt);
}

test "workload replica columns use numeric projection sort keys" {
    const low_deployment = DeploymentRecord{
        .key = undefined,
        .ready_replicas = 2,
        .desired_replicas = 10,
        .updated_replicas = 2,
        .available_replicas = 2,
        .ready_sort_key = DeploymentRecord.ratioSortKey(2, 10),
        .updated_sort_key = DeploymentRecord.countSortKey(2),
        .available_sort_key = DeploymentRecord.countSortKey(2),
    };
    const high_deployment = DeploymentRecord{
        .key = undefined,
        .ready_replicas = 10,
        .desired_replicas = 10,
        .updated_replicas = 10,
        .available_replicas = 10,
        .ready_sort_key = DeploymentRecord.ratioSortKey(10, 10),
        .updated_sort_key = DeploymentRecord.countSortKey(10),
        .available_sort_key = DeploymentRecord.countSortKey(10),
    };
    inline for (2..5) |column| {
        try std.testing.expect(std.mem.order(
            u8,
            deploymentProjectionSortKey(&low_deployment, column),
            deploymentProjectionSortKey(&high_deployment, column),
        ) == .lt);
    }

    const low_stateful = StatefulSetRecord{
        .key = undefined,
        .ready_replicas = 2,
        .desired_replicas = 10,
        .ready_sort_key = DeploymentRecord.ratioSortKey(2, 10),
    };
    const high_stateful = StatefulSetRecord{
        .key = undefined,
        .ready_replicas = 10,
        .desired_replicas = 10,
        .ready_sort_key = DeploymentRecord.ratioSortKey(10, 10),
    };
    try std.testing.expect(std.mem.order(
        u8,
        statefulSetProjectionSortKey(&low_stateful, 2),
        statefulSetProjectionSortKey(&high_stateful, 2),
    ) == .lt);

    const low_daemon = DaemonSetRecord{
        .key = undefined,
        .desired = 2,
        .current = 2,
        .ready = 2,
        .updated = 2,
        .desired_sort_key = DeploymentRecord.countSortKey(2),
        .current_sort_key = DeploymentRecord.countSortKey(2),
        .ready_sort_key = DeploymentRecord.countSortKey(2),
        .updated_sort_key = DeploymentRecord.countSortKey(2),
    };
    const high_daemon = DaemonSetRecord{
        .key = undefined,
        .desired = 10,
        .current = 10,
        .ready = 10,
        .updated = 10,
        .desired_sort_key = DeploymentRecord.countSortKey(10),
        .current_sort_key = DeploymentRecord.countSortKey(10),
        .ready_sort_key = DeploymentRecord.countSortKey(10),
        .updated_sort_key = DeploymentRecord.countSortKey(10),
    };
    inline for (2..6) |column| {
        try std.testing.expect(std.mem.order(
            u8,
            daemonSetProjectionSortKey(&low_daemon, column),
            daemonSetProjectionSortKey(&high_daemon, column),
        ) == .lt);
    }

    const low_replica = ReplicaSetRecord{
        .key = undefined,
        .desired = 2,
        .current = 2,
        .ready = 2,
        .desired_sort_key = DeploymentRecord.countSortKey(2),
        .current_sort_key = DeploymentRecord.countSortKey(2),
        .ready_sort_key = DeploymentRecord.countSortKey(2),
    };
    const high_replica = ReplicaSetRecord{
        .key = undefined,
        .desired = 10,
        .current = 10,
        .ready = 10,
        .desired_sort_key = DeploymentRecord.countSortKey(10),
        .current_sort_key = DeploymentRecord.countSortKey(10),
        .ready_sort_key = DeploymentRecord.countSortKey(10),
    };
    inline for (2..5) |column| {
        try std.testing.expect(std.mem.order(
            u8,
            replicaSetProjectionSortKey(&low_replica, column),
            replicaSetProjectionSortKey(&high_replica, column),
        ) == .lt);
    }
}

test "batch count columns use numeric projection sort keys" {
    const low_job = JobRecord{
        .key = undefined,
        .succeeded = 2,
        .desired = 10,
        .completions_sort_key = JobRecord.ratioSortKey(2, 10),
    };
    const high_job = JobRecord{
        .key = undefined,
        .succeeded = 10,
        .desired = 10,
        .completions_sort_key = JobRecord.ratioSortKey(10, 10),
    };
    try std.testing.expect(std.mem.order(
        u8,
        jobProjectionSortKey(&low_job, 2),
        jobProjectionSortKey(&high_job, 2),
    ) == .lt);

    const low_cron = CronJobRecord{
        .key = undefined,
        .schedule = undefined,
        .@"suspend" = false,
        .active = 2,
        .active_sort_key = CronJobRecord.countSortKey(2),
    };
    const high_cron = CronJobRecord{
        .key = undefined,
        .schedule = undefined,
        .@"suspend" = false,
        .active = 10,
        .active_sort_key = CronJobRecord.countSortKey(10),
    };
    try std.testing.expect(std.mem.order(
        u8,
        cronJobProjectionSortKey(&low_cron, 4),
        cronJobProjectionSortKey(&high_cron, 4),
    ) == .lt);

    const low_hpa = HPARecord{
        .key = undefined,
        .min_replicas = 2,
        .max_replicas = 2,
        .current_replicas = 2,
        .min_sort_key = HPARecord.countSortKey(2),
        .max_sort_key = HPARecord.countSortKey(2),
        .current_sort_key = HPARecord.countSortKey(2),
    };
    const high_hpa = HPARecord{
        .key = undefined,
        .min_replicas = 10,
        .max_replicas = 10,
        .current_replicas = 10,
        .min_sort_key = HPARecord.countSortKey(10),
        .max_sort_key = HPARecord.countSortKey(10),
        .current_sort_key = HPARecord.countSortKey(10),
    };
    inline for (2..5) |column| {
        try std.testing.expect(std.mem.order(
            u8,
            hpaProjectionSortKey(&low_hpa, column),
            hpaProjectionSortKey(&high_hpa, column),
        ) == .lt);
    }

    const low_pdb = PDBRecord{
        .key = undefined,
        .min_available = undefined,
        .max_unavailable = undefined,
        .min_available_sort_key = PDBRecord.intOrStringSortKey("2"),
        .max_unavailable_sort_key = PDBRecord.intOrStringSortKey("2"),
        .allowed_disruptions = 2,
        .allowed_sort_key = PDBRecord.countSortKey(2),
    };
    const high_pdb = PDBRecord{
        .key = undefined,
        .min_available = undefined,
        .max_unavailable = undefined,
        .min_available_sort_key = PDBRecord.intOrStringSortKey("10"),
        .max_unavailable_sort_key = PDBRecord.intOrStringSortKey("10"),
        .allowed_disruptions = 10,
        .allowed_sort_key = PDBRecord.countSortKey(10),
    };
    inline for (2..5) |column| {
        try std.testing.expect(std.mem.order(
            u8,
            pdbProjectionSortKey(&low_pdb, column),
            pdbProjectionSortKey(&high_pdb, column),
        ) == .lt);
    }
}

test "storage capacity columns use padded numeric projection sort keys" {
    const low_key = PVRecord.capacitySortKey("2Gi");
    const high_key = PVRecord.capacitySortKey("10Gi");
    const low = PVCRecord{
        .key = undefined,
        .status = undefined,
        .volume = undefined,
        .capacity = undefined,
        .capacity_sort_key = low_key,
        .access = undefined,
        .storage_class = undefined,
    };
    const high = PVCRecord{
        .key = undefined,
        .status = undefined,
        .volume = undefined,
        .capacity = undefined,
        .capacity_sort_key = high_key,
        .access = undefined,
        .storage_class = undefined,
    };
    try std.testing.expect(std.mem.order(
        u8,
        pvcProjectionSortKey(&low, 4),
        pvcProjectionSortKey(&high, 4),
    ) == .lt);
}

test "resource family identities isolate envelopes and pod side effects" {
    const pod = lifecycle.SubscriptionKey{ .generation = 8, .subscription_id = 1 };
    const node = lifecycle.SubscriptionKey{ .generation = 8, .subscription_id = 2 };
    const namespace = lifecycle.SubscriptionKey{ .generation = 8, .subscription_id = 3 };
    try std.testing.expect(matchesIdentity(pod, .{
        .generation = 8,
        .subscription_id = 1,
    }));
    try std.testing.expect(!matchesIdentity(pod, .{
        .generation = 8,
        .subscription_id = 2,
    }));
    try std.testing.expect(matchesIdentity(node, .{
        .generation = 8,
        .subscription_id = 2,
    }));
    try std.testing.expect(matchesIdentity(namespace, .{
        .generation = 8,
        .subscription_id = 3,
    }));
    try std.testing.expect(!shouldStartMetricsFeed(false, true, 2, false));

    const families = [_]struct {
        key: lifecycle.SubscriptionKey,
        expect_node: bool,
        expect_namespace: bool,
    }{
        .{ .key = node, .expect_node = true, .expect_namespace = false },
        .{ .key = namespace, .expect_node = false, .expect_namespace = true },
    };
    for (families) |family| {
        const effects = decideResourceDrainEffects(
            .{ .resource = .{
                .generation = family.key.generation,
                .subscription_id = family.key.subscription_id,
            } },
            pod,
            .{ .generation = 8, .subscription_id = 4 },
            node,
            namespace,
            .list_complete,
            true,
            2,
            false,
        );
        try std.testing.expectEqual(family.expect_node, effects.sync_node);
        try std.testing.expectEqual(family.expect_namespace, effects.sync_namespace);
        try std.testing.expect(!effects.sync_pod);
        try std.testing.expect(!effects.sync_metrics);
        try std.testing.expect(!effects.start_pod_metrics);
        try std.testing.expect(!effects.emit_pod_list_complete);
        try std.testing.expect(!effects.emit_pod_watch_connected);
        try std.testing.expect(!effects.emit_metrics_ready);
    }

    const service_identity = resource_key.ResourceIdentity{
        .generation = 8,
        .subscription_id = 5,
    };
    const service_effects = decideResourceDrainEffects(
        .{ .resource = service_identity },
        pod,
        .{ .generation = 8, .subscription_id = 4 },
        node,
        namespace,
        .list_complete,
        true,
        2,
        false,
    );
    try std.testing.expectEqual(ResourceDrainEffects{}, service_effects);

    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    const entry = app.resource_families.registry.entryAt(3).?;
    entry.markStarted(.{ .generation = 8, .subscription_id = 5 });
    defer entry.markStopped();
    try std.testing.expect(app.resource_families.registry.contains(service_identity));
    try std.testing.expect(!app.resource_families.registry.contains(.{
        .generation = pod.generation,
        .subscription_id = pod.subscription_id,
    }));

    const batch_entry = app.resource_families.registry.entryAt(12).?;
    const batch_identity = resource_key.ResourceIdentity{
        .generation = 8,
        .subscription_id = 6,
    };
    batch_entry.markStarted(.{
        .generation = batch_identity.generation,
        .subscription_id = batch_identity.subscription_id,
    });
    defer batch_entry.markStopped();
    try std.testing.expect(app.resource_families.registry.contains(batch_identity));
    try std.testing.expect(!matchesIdentity(pod, batch_identity));
    try std.testing.expectEqual(ResourceDrainEffects{}, decideResourceDrainEffects(
        .{ .resource = batch_identity },
        pod,
        .{ .generation = 8, .subscription_id = 4 },
        node,
        namespace,
        .list_complete,
        true,
        2,
        false,
    ));

    const networking_entry = app.resource_families.registry.entryAt(16).?;
    const networking_identity = resource_key.ResourceIdentity{
        .generation = 8,
        .subscription_id = 7,
    };
    networking_entry.markStarted(.{
        .generation = networking_identity.generation,
        .subscription_id = networking_identity.subscription_id,
    });
    defer networking_entry.markStopped();
    try std.testing.expect(app.resource_families.registry.contains(networking_identity));
    try std.testing.expect(!matchesIdentity(pod, networking_identity));
    try std.testing.expectEqual(ResourceDrainEffects{}, decideResourceDrainEffects(
        .{ .resource = networking_identity },
        pod,
        .{ .generation = 8, .subscription_id = 4 },
        node,
        namespace,
        .list_complete,
        true,
        2,
        false,
    ));

    const storage_entry = app.resource_families.registry.entryAt(21).?;
    const storage_identity = resource_key.ResourceIdentity{
        .generation = 8,
        .subscription_id = 8,
    };
    storage_entry.markStarted(.{
        .generation = storage_identity.generation,
        .subscription_id = storage_identity.subscription_id,
    });
    defer storage_entry.markStopped();
    try std.testing.expect(app.resource_families.registry.contains(storage_identity));
    try std.testing.expect(!matchesIdentity(pod, storage_identity));
    try std.testing.expectEqual(ResourceDrainEffects{}, decideResourceDrainEffects(
        .{ .resource = storage_identity },
        pod,
        .{ .generation = 8, .subscription_id = 4 },
        node,
        namespace,
        .list_complete,
        true,
        2,
        false,
    ));
}

test "readonly dispatch classification exhaustively gates mutations and permits reads" {
    const mutations = [_]View.KeyResult{
        .request_delete,
        .request_kill,
        .request_edit,
        .request_shell,
        .request_attach,
        .request_port_forward,
        .request_set_image,
        .request_sanitize,
        .request_transfer,
        .request_kill_finalizers,
        .request_drain,
        .request_cordon,
        .request_uncordon,
        .request_restart,
        .request_scale,
        .request_suspend,
        .request_trigger,
        .request_rollback,
    };
    for (mutations) |result| try std.testing.expect(readonlyAction(result) != null);

    const reads = [_]View.KeyResult{
        .handled,
        .request_describe,
        .request_yaml,
        .request_logs,
        .request_logs_previous,
        .request_decode,
        .request_traffic,
        .request_show_node,
        .request_show_port_forwards,
        .request_copy,
        .request_copy_namespace,
        .request_warp,
        .request_jump_owner,
        .request_used_by,
        .request_view_replicasets,
    };
    for (reads) |result| try std.testing.expect(readonlyAction(result) == null);
}

fn matchesIdentity(
    active: ?lifecycle.SubscriptionKey,
    identity: resource_key.ResourceIdentity,
) bool {
    const key = active orelse return false;
    return key.generation == identity.generation and
        key.subscription_id == identity.subscription_id;
}

fn matchesEitherEnvelope(
    first: ?lifecycle.SubscriptionKey,
    second: ?lifecycle.SubscriptionKey,
    envelope: resource_key.Envelope,
) bool {
    return switch (envelope.target) {
        .lifecycle => true,
        .resource => |identity| matchesIdentity(first, identity) or
            matchesIdentity(second, identity),
        else => false,
    };
}

fn timerRefreshAllowed(
    view_name: []const u8,
    pod_source: resource_view.Source,
    node_source: resource_view.Source,
    namespace_source: resource_view.Source,
    services_source: resource_view.Source,
    config_source: resource_view.Source,
    workloads_source: resource_view.Source,
    batch_source: resource_view.Source,
    networking_source: resource_view.Source,
    storage_source: resource_view.Source,
) bool {
    if (std.mem.eql(u8, view_name, "pods")) return pod_source != .data_plane;
    if (std.mem.eql(u8, view_name, "nodes")) return node_source != .data_plane;
    if (std.mem.eql(u8, view_name, "namespaces")) return namespace_source != .data_plane;
    if (services_source == .data_plane and
        (std.mem.eql(u8, view_name, "services") or
            std.mem.eql(u8, view_name, "endpoints") or
            std.mem.eql(u8, view_name, "endpointslices")))
        return false;
    if (config_source == .data_plane and
        (std.mem.eql(u8, view_name, "configmaps") or
            std.mem.eql(u8, view_name, "secrets") or
            std.mem.eql(u8, view_name, "serviceaccounts") or
            std.mem.eql(u8, view_name, "resourcequotas") or
            std.mem.eql(u8, view_name, "limitranges")))
        return false;
    if (workloads_source == .data_plane and
        (std.mem.eql(u8, view_name, "deployments") or
            std.mem.eql(u8, view_name, "statefulsets") or
            std.mem.eql(u8, view_name, "daemonsets") or
            std.mem.eql(u8, view_name, "replicasets")))
        return false;
    if (batch_source == .data_plane and
        (std.mem.eql(u8, view_name, "jobs") or
            std.mem.eql(u8, view_name, "cronjobs") or
            std.mem.eql(u8, view_name, "hpa") or
            std.mem.eql(u8, view_name, "poddisruptionbudgets")))
        return false;
    if (networking_source == .data_plane and
        (std.mem.eql(u8, view_name, "ingresses") or
            std.mem.eql(u8, view_name, "ingressclasses") or
            std.mem.eql(u8, view_name, "networkpolicies") or
            std.mem.eql(u8, view_name, "ipaddresses") or
            std.mem.eql(u8, view_name, "servicecidrs")))
        return false;
    if (storage_source == .data_plane and
        (std.mem.eql(u8, view_name, "persistentvolumes") or
            std.mem.eql(u8, view_name, "persistentvolumeclaims") or
            std.mem.eql(u8, view_name, "storageclasses") or
            std.mem.eql(u8, view_name, "volumeattributesclasses") or
            std.mem.eql(u8, view_name, "csidrivers")))
        return false;
    return true;
}

fn isActivePodCompletion(
    active: ?lifecycle.SubscriptionKey,
    identity: ?resource_key.ResourceIdentity,
    completion: lifecycle.LifecycleCompletion,
) bool {
    switch (completion) {
        .subscription_stopped, .start_rejected => {},
        else => return false,
    }
    const active_key = active orelse return false;
    const completed = identity orelse return false;
    return active_key.generation == completed.generation and
        active_key.subscription_id == completed.subscription_id;
}

test "pod envelope routing requires exact active identity" {
    const active = lifecycle.SubscriptionKey{ .generation = 4, .subscription_id = 7 };
    try std.testing.expect(matchesPodEnvelope(active, .{
        .generation = 4,
        .subscription_id = 7,
        .target = .{ .resource = .{
            .generation = 4,
            .subscription_id = 7,
        } },
    }));
    try std.testing.expect(!matchesPodEnvelope(active, .{
        .target = .{ .resource = .{
            .generation = 3,
            .subscription_id = 7,
        } },
    }));
    try std.testing.expect(!matchesPodEnvelope(active, .{
        .target = .{ .resource = .{
            .generation = 4,
            .subscription_id = 8,
        } },
    }));
    try std.testing.expect(!matchesPodEnvelope(null, .{
        .target = .{ .resource = .{
            .generation = 4,
            .subscription_id = 7,
        } },
    }));
    try std.testing.expect(matchesPodEnvelope(active, .{ .target = .lifecycle }));
}

test "pod paint gates require applied data and revisions" {
    const ready = perf.PodPaintEvidence{
        .current_is_pods = true,
        .initial_applied = true,
        .loading = false,
        .has_error = false,
        .visible_rows = 1,
        .flush_succeeded = true,
        .close_succeeded = true,
        .list_complete_revision = 11,
        .applied_revision = 11,
        .apply_failed = false,
    };
    try std.testing.expect(perf.shouldMarkFirstPodPaint(false, ready));
    try std.testing.expect(perf.shouldMarkCompletePodPaint(false, ready));
    var hidden = ready;
    hidden.visible_rows = 0;
    try std.testing.expect(!perf.shouldMarkFirstPodPaint(false, hidden));
    var failed = ready;
    failed.apply_failed = true;
    try std.testing.expect(!perf.shouldMarkCompletePodPaint(false, failed));
    var failed_close = ready;
    failed_close.close_succeeded = false;
    try std.testing.expect(!perf.shouldMarkFirstPodPaint(false, failed_close));
    try std.testing.expect(!perf.shouldMarkCompletePodPaint(false, failed_close));
}

test "pod transitions require the exact subscription completion" {
    const active = lifecycle.SubscriptionKey{ .generation = 4, .subscription_id = 7 };
    const exact = resource_key.ResourceIdentity{ .generation = 4, .subscription_id = 7 };
    const unrelated = resource_key.ResourceIdentity{ .generation = 4, .subscription_id = 8 };
    try std.testing.expect(isActivePodCompletion(active, exact, .{
        .subscription_stopped = .{ .key = active, .detail = null },
    }));
    try std.testing.expect(isActivePodCompletion(active, exact, .{
        .start_rejected = .{
            .child_key = .{ .slot = 2, .generation = 3 },
            .code = .stale_generation,
        },
    }));
    try std.testing.expect(!isActivePodCompletion(active, unrelated, .{
        .subscription_stopped = .{ .key = .{ .generation = 4, .subscription_id = 8 }, .detail = null },
    }));
    try std.testing.expect(!isActivePodCompletion(active, exact, .shutdown_complete));
}

test "timer auto-refresh does not restart live data-plane watches" {
    try std.testing.expect(!timerRefreshAllowed("pods", .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
    try std.testing.expect(timerRefreshAllowed("pods", .legacy_list, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
    try std.testing.expect(!timerRefreshAllowed("nodes", .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
    try std.testing.expect(!timerRefreshAllowed("namespaces", .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
    try std.testing.expect(!timerRefreshAllowed("services", .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
    try std.testing.expect(!timerRefreshAllowed("endpoints", .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
    try std.testing.expect(!timerRefreshAllowed("endpointslices", .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
    try std.testing.expect(timerRefreshAllowed("services", .data_plane, .data_plane, .data_plane, .legacy_list, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
    inline for (.{ "configmaps", "secrets", "serviceaccounts", "resourcequotas", "limitranges" }) |name| {
        try std.testing.expect(!timerRefreshAllowed(name, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
        try std.testing.expect(timerRefreshAllowed(name, .data_plane, .data_plane, .data_plane, .data_plane, .legacy_list, .data_plane, .data_plane, .data_plane, .data_plane));
    }
    inline for (.{ "deployments", "statefulsets", "daemonsets", "replicasets" }) |name| {
        try std.testing.expect(!timerRefreshAllowed(name, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
        try std.testing.expect(timerRefreshAllowed(name, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .legacy_list, .data_plane, .data_plane, .data_plane));
    }
    inline for (.{ "jobs", "cronjobs", "hpa", "poddisruptionbudgets" }) |name| {
        try std.testing.expect(!timerRefreshAllowed(name, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
        try std.testing.expect(timerRefreshAllowed(name, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .legacy_list, .data_plane, .data_plane));
    }
    inline for (.{ "ingresses", "ingressclasses", "networkpolicies", "ipaddresses", "servicecidrs" }) |name| {
        try std.testing.expect(!timerRefreshAllowed(name, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
        try std.testing.expect(timerRefreshAllowed(name, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .legacy_list, .data_plane));
    }
    inline for (.{ "persistentvolumes", "persistentvolumeclaims", "storageclasses", "volumeattributesclasses", "csidrivers" }) |name| {
        try std.testing.expect(!timerRefreshAllowed(name, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane));
        try std.testing.expect(timerRefreshAllowed(name, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .data_plane, .legacy_list));
    }
}

test "shouldAutoRefresh: interval, disabling, and clock sanity" {
    const ns = std.time.ns_per_s;

    // Never refreshed yet -> refresh now, rather than waiting out one interval.
    try std.testing.expect(App.shouldAutoRefresh(2.0, 0, 12345));

    // Inside the interval -> no.
    try std.testing.expect(!App.shouldAutoRefresh(2.0, 1000 * ns, 1001 * ns));
    // Exactly at the interval -> yes.
    try std.testing.expect(App.shouldAutoRefresh(2.0, 1000 * ns, 1002 * ns));
    // Past it -> yes.
    try std.testing.expect(App.shouldAutoRefresh(2.0, 1000 * ns, 1005 * ns));

    // Sub-second intervals must work; truncating to whole seconds would silently
    // turn --refresh 0.5 into "never".
    try std.testing.expect(App.shouldAutoRefresh(0.5, 1000 * ns, 1000 * ns + 600_000_000));
    try std.testing.expect(!App.shouldAutoRefresh(0.5, 1000 * ns, 1000 * ns + 400_000_000));

    // 0 is the documented way to disable it; negatives and NaN must not enable it.
    try std.testing.expect(!App.shouldAutoRefresh(0, 1000 * ns, 9999 * ns));
    try std.testing.expect(!App.shouldAutoRefresh(-1, 1000 * ns, 9999 * ns));
    try std.testing.expect(!App.shouldAutoRefresh(std.math.nan(f32), 1000 * ns, 9999 * ns));

    // A backwards clock must not trigger a refresh storm.
    try std.testing.expect(!App.shouldAutoRefresh(2.0, 1000 * ns, 900 * ns));
}

test "runAutoRefreshCycle: last_ns stores completion time, not pre-refresh start time" {
    // Mutation-effective regression for the refresh-storm bug.
    //
    // The bug: maybeAutoRefresh wrote `last_auto_refresh_ns = now` BEFORE calling
    // refreshCurrentView(). On a large cluster a single LIST call takes 3–12 s —
    // well above the default 2 s interval. With last set at T_start:
    //
    //   now_after_list = T_start + 3 s
    //   shouldAutoRefresh(2.0, T_start, now_after_list) → elapsed 3 s ≥ 2 s → true
    //
    // The main loop does reach poll() after the LIST returns, but the very next
    // 100 ms timeout immediately fires another blocking LIST. Near-continuous
    // blocking with ~100 ms gaps leaves the app effectively unresponsive.
    //
    // The fix: last_ns = clockFn(), called AFTER refreshFn() returns.
    //
    // This test fails if the assignment order is reversed (last_ns would become
    // now_ns = 1000*ns instead of the injected clock value 1003*ns).
    const ns = std.time.ns_per_s;

    const MockClock = struct {
        fn now() i128 {
            return 1003 * std.time.ns_per_s; // simulates a 3 s blocking LIST
        }
    };
    const MockRefresh = struct {
        fn run(count: *usize) void {
            count.* += 1;
        }
    };

    var refresh_count: usize = 0;
    var last_ns: i128 = 0;

    const fired = App.runAutoRefreshCycle(
        2.0,
        &last_ns,
        1000 * ns, // now = T+1s; last=0 (never refreshed) → should fire
        *usize,
        &refresh_count,
        MockRefresh.run,
        MockClock.now,
    );

    try std.testing.expect(fired);
    try std.testing.expectEqual(@as(usize, 1), refresh_count);

    // last_ns must equal MockClock.now() — the value returned AFTER the refresh.
    // If assignment happens before refreshFn (old bug), last_ns == 1000*ns here
    // and the expectEqual below fails, catching the regression.
    try std.testing.expectEqual(@as(i128, 1003 * ns), last_ns);

    // Consequence: 100 ms after completion, the interval (2 s) has not elapsed.
    // No re-entry fire — this is the responsive window the fix provides.
    try std.testing.expect(!App.shouldAutoRefresh(2.0, last_ns, @as(i128, 1003 * ns) + 100_000_000));
}

test "shouldLiveFilter refuses every prompt that is not a live filter" {
    // Filtering as you type is only correct for the "/" filter prompt. The same
    // prompt is reused for a delete confirmation's y/n and for value prompts
    // (set-image, port-forward, transfer, sanitize); re-filtering during those would
    // rewrite the row list underneath the answer -- and for a delete confirmation
    // that means the "yes" could land on a different row than the one the user saw.
    try std.testing.expect(App.shouldLiveFilter(true, "/", false, true));

    // Not visible -> nothing to filter with.
    try std.testing.expect(!App.shouldLiveFilter(false, "/", false, true));

    // The command palette is not a filter.
    try std.testing.expect(!App.shouldLiveFilter(true, ":", false, true));

    // The two that would be actively dangerous.
    try std.testing.expect(!App.shouldLiveFilter(true, "/", true, true));
    try std.testing.expect(!App.shouldLiveFilter(true, "/", false, false));

    // Both at once is still refused.
    try std.testing.expect(!App.shouldLiveFilter(true, "/", true, false));
}

test "App owns inherited telemetry without emitting paint markers" {
    if (std.c.getenv("C3S_PERF_FD") != null) return error.SkipZigTest;
    const Env = struct {
        extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
        extern "c" fn unsetenv(name: [*:0]const u8) c_int;
    };

    var fds: [2]std.c.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&fds));
    defer _ = std.c.close(fds[0]);
    defer if (std.c.fcntl(fds[1], std.c.F.GETFD) >= 0) {
        _ = std.c.close(fds[1]);
    };

    const read_flags = std.c.fcntl(fds[0], std.c.F.GETFL);
    try std.testing.expect(read_flags >= 0);
    const nonblocking: c_int = @bitCast(std.c.O{ .NONBLOCK = true });
    try std.testing.expectEqual(@as(c_int, 0), std.c.fcntl(fds[0], std.c.F.SETFL, read_flags | nonblocking));

    const write_flags = std.c.fcntl(fds[1], std.c.F.GETFD);
    try std.testing.expect(write_flags >= 0);
    try std.testing.expectEqual(
        @as(c_int, 0),
        std.c.fcntl(fds[1], std.c.F.SETFD, write_flags & ~@as(c_int, std.c.FD_CLOEXEC)),
    );

    var fd_buf: [32]u8 = undefined;
    const fd_value = try std.fmt.bufPrintZ(&fd_buf, "{d}", .{fds[1]});
    try std.testing.expectEqual(@as(c_int, 0), Env.setenv("C3S_PERF_FD", fd_value.ptr, 1));
    defer _ = Env.unsetenv("C3S_PERF_FD");

    var app = try App.init(std.testing.allocator, .{});
    var app_live = true;
    defer if (app_live) app.deinit();

    try std.testing.expect(std.c.fcntl(fds[1], std.c.F.GETFD) & std.c.FD_CLOEXEC != 0);
    var byte: [1]u8 = undefined;
    const before_deinit = std.c.read(fds[0], &byte, byte.len);
    try std.testing.expectEqual(@as(isize, -1), before_deinit);
    try std.testing.expectEqual(std.c.E.AGAIN, std.c.errno(before_deinit));

    app.deinit();
    app_live = false;
    try std.testing.expectEqual(@as(c_int, -1), std.c.fcntl(fds[1], std.c.F.GETFD));
    try std.testing.expectEqual(std.c.E.BADF, std.c.errno(-1));
    try std.testing.expectEqual(@as(isize, 0), std.c.read(fds[0], &byte, byte.len));
}
