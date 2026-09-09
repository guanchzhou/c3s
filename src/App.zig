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
const task15 = @import("task15_diagnostics.zig");
const Wakeup = @import("core/Wakeup.zig").Wakeup;
const sys = @import("core/sys.zig");
const ChangeQueue = @import("k8s/ChangeQueue.zig").ChangeQueue;
const resource_key = @import("k8s/ResourceKey.zig");
const read_transport = @import("k8s/ReadTransport.zig");
const list_watch = @import("k8s/ListWatch.zig");
const lifecycle = @import("k8s/LifecycleInbox.zig");
const lifecycle_supervisor = @import("k8s/LifecycleSupervisor.zig");
const data_plane_mod = @import("k8s/DataPlane.zig");
const DataPlane = data_plane_mod.DataPlane;
const AncillaryRequests = @import("k8s/AncillaryRequests.zig").AncillaryRequests;
const header_metrics_request = @import("k8s/HeaderMetricsRequest.zig");
const traffic_request = @import("k8s/TrafficRequest.zig");
const detail_request = @import("k8s/DetailRequest.zig");
const logs_request = @import("k8s/LogsRequest.zig");
const authorization_request = @import("k8s/AuthorizationRequest.zig");
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
const GatewayClassRecord = @import("k8s/GatewayClassRecord.zig");
const GatewayRecord = @import("k8s/GatewayRecord.zig");
const HTTPRouteRecord = @import("k8s/HTTPRouteRecord.zig");
const GRPCRouteRecord = @import("k8s/GRPCRouteRecord.zig");
const ReferenceGrantRecord = @import("k8s/ReferenceGrantRecord.zig");
const TCPRouteRecord = @import("k8s/TCPRouteRecord.zig");
const TLSRouteRecord = @import("k8s/TLSRouteRecord.zig");
const UDPRouteRecord = @import("k8s/UDPRouteRecord.zig");
const BackendTLSPolicyRecord = @import("k8s/BackendTLSPolicyRecord.zig");
const ListenerSetRecord = @import("k8s/ListenerSetRecord.zig");
const GatewayClassProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(GatewayClassRecord);
const GatewayProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(GatewayRecord);
const HTTPRouteProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(HTTPRouteRecord);
const GRPCRouteProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(GRPCRouteRecord);
const ReferenceGrantProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ReferenceGrantRecord);
const TCPRouteProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(TCPRouteRecord);
const TLSRouteProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(TLSRouteRecord);
const UDPRouteProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(UDPRouteRecord);
const BackendTLSPolicyProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(BackendTLSPolicyRecord);
const ListenerSetProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ListenerSetRecord);
const GatewayClassSubscription = resource_subscription.ResourceSubscription(klient.GatewayClass, GatewayClassRecord, GatewayClassRecord.fromGatewayClass);
const GatewaySubscription = resource_subscription.ResourceSubscription(klient.Gateway, GatewayRecord, GatewayRecord.fromGateway);
const HTTPRouteSubscription = resource_subscription.ResourceSubscription(klient.HTTPRoute, HTTPRouteRecord, HTTPRouteRecord.fromHTTPRoute);
const GRPCRouteSubscription = resource_subscription.ResourceSubscription(klient.GRPCRoute, GRPCRouteRecord, GRPCRouteRecord.fromGRPCRoute);
const ReferenceGrantSubscription = resource_subscription.ResourceSubscription(klient.ReferenceGrant, ReferenceGrantRecord, ReferenceGrantRecord.fromReferenceGrant);
const TCPRouteSubscription = resource_subscription.ResourceSubscription(klient.TCPRoute, TCPRouteRecord, TCPRouteRecord.fromTCPRoute);
const TLSRouteSubscription = resource_subscription.ResourceSubscription(klient.TLSRoute, TLSRouteRecord, TLSRouteRecord.fromTLSRoute);
const UDPRouteSubscription = resource_subscription.ResourceSubscription(klient.UDPRoute, UDPRouteRecord, UDPRouteRecord.fromUDPRoute);
const BackendTLSPolicySubscription = resource_subscription.ResourceSubscription(klient.BackendTLSPolicy, BackendTLSPolicyRecord, BackendTLSPolicyRecord.fromBackendTLSPolicy);
const ListenerSetSubscription = resource_subscription.ResourceSubscription(klient.ListenerSet, ListenerSetRecord, ListenerSetRecord.fromListenerSet);
const role_record = @import("k8s/RoleRecord.zig");
const role_binding_record = @import("k8s/RoleBindingRecord.zig");
const cluster_role_record = @import("k8s/ClusterRoleRecord.zig");
const cluster_role_binding_record = @import("k8s/ClusterRoleBindingRecord.zig");
const RoleRecord = role_record.RoleRecord;
const RoleBindingRecord = role_binding_record.RoleBindingRecord;
const ClusterRoleRecord = cluster_role_record.ClusterRoleRecord;
const ClusterRoleBindingRecord = cluster_role_binding_record.ClusterRoleBindingRecord;
const RoleProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(RoleRecord);
const RoleBindingProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(RoleBindingRecord);
const ClusterRoleProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ClusterRoleRecord);
const ClusterRoleBindingProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ClusterRoleBindingRecord);
const RoleSubscription = resource_subscription.ResourceSubscription(klient.Role, RoleRecord, role_record.fromRole);
const RoleBindingSubscription = resource_subscription.ResourceSubscription(klient.RoleBinding, RoleBindingRecord, role_binding_record.fromRoleBinding);
const ClusterRoleSubscription = resource_subscription.ResourceSubscription(klient.ClusterRole, ClusterRoleRecord, cluster_role_record.fromClusterRole);
const ClusterRoleBindingSubscription = resource_subscription.ResourceSubscription(klient.ClusterRoleBinding, ClusterRoleBindingRecord, cluster_role_binding_record.fromClusterRoleBinding);
const validating_admission_policy_record = @import("k8s/ValidatingAdmissionPolicyRecord.zig");
const validating_admission_policy_binding_record = @import("k8s/ValidatingAdmissionPolicyBindingRecord.zig");
const mutating_admission_policy_record = @import("k8s/MutatingAdmissionPolicyRecord.zig");
const mutating_admission_policy_binding_record = @import("k8s/MutatingAdmissionPolicyBindingRecord.zig");
const validating_webhook_configuration_record = @import("k8s/ValidatingWebhookConfigurationRecord.zig");
const mutating_webhook_configuration_record = @import("k8s/MutatingWebhookConfigurationRecord.zig");
const ValidatingAdmissionPolicyRecord = validating_admission_policy_record.ValidatingAdmissionPolicyRecord;
const ValidatingAdmissionPolicyBindingRecord = validating_admission_policy_binding_record.ValidatingAdmissionPolicyBindingRecord;
const MutatingAdmissionPolicyRecord = mutating_admission_policy_record.MutatingAdmissionPolicyRecord;
const MutatingAdmissionPolicyBindingRecord = mutating_admission_policy_binding_record.MutatingAdmissionPolicyBindingRecord;
const ValidatingWebhookConfigurationRecord = validating_webhook_configuration_record.ValidatingWebhookConfigurationRecord;
const MutatingWebhookConfigurationRecord = mutating_webhook_configuration_record.MutatingWebhookConfigurationRecord;
const ValidatingAdmissionPolicyProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ValidatingAdmissionPolicyRecord);
const ValidatingAdmissionPolicyBindingProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ValidatingAdmissionPolicyBindingRecord);
const MutatingAdmissionPolicyProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(MutatingAdmissionPolicyRecord);
const MutatingAdmissionPolicyBindingProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(MutatingAdmissionPolicyBindingRecord);
const ValidatingWebhookConfigurationProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ValidatingWebhookConfigurationRecord);
const MutatingWebhookConfigurationProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(MutatingWebhookConfigurationRecord);
const ValidatingAdmissionPolicySubscription = resource_subscription.ResourceSubscription(klient.ValidatingAdmissionPolicy, ValidatingAdmissionPolicyRecord, validating_admission_policy_record.fromValidatingAdmissionPolicy);
const ValidatingAdmissionPolicyBindingSubscription = resource_subscription.ResourceSubscription(klient.ValidatingAdmissionPolicyBinding, ValidatingAdmissionPolicyBindingRecord, validating_admission_policy_binding_record.fromValidatingAdmissionPolicyBinding);
const MutatingAdmissionPolicySubscription = resource_subscription.ResourceSubscription(klient.MutatingAdmissionPolicy, MutatingAdmissionPolicyRecord, mutating_admission_policy_record.fromMutatingAdmissionPolicy);
const MutatingAdmissionPolicyBindingSubscription = resource_subscription.ResourceSubscription(klient.MutatingAdmissionPolicyBinding, MutatingAdmissionPolicyBindingRecord, mutating_admission_policy_binding_record.fromMutatingAdmissionPolicyBinding);
const ValidatingWebhookConfigurationSubscription = resource_subscription.ResourceSubscription(klient.ValidatingWebhookConfiguration, ValidatingWebhookConfigurationRecord, validating_webhook_configuration_record.fromValidatingWebhookConfiguration);
const MutatingWebhookConfigurationSubscription = resource_subscription.ResourceSubscription(klient.MutatingWebhookConfiguration, MutatingWebhookConfigurationRecord, mutating_webhook_configuration_record.fromMutatingWebhookConfiguration);
const ResourceClaimRecord = @import("k8s/ResourceClaimRecord.zig");
const DeviceClassRecord = @import("k8s/DeviceClassRecord.zig");
const PriorityClassRecord = @import("k8s/PriorityClassRecord.zig");
const RuntimeClassRecord = @import("k8s/RuntimeClassRecord.zig");
const LeaseRecord = @import("k8s/LeaseRecord.zig");
const CSRRecord = @import("k8s/CSRRecord.zig");
const StorageVersionMigrationRecord = @import("k8s/StorageVersionMigrationRecord.zig");
const EventRecord = @import("k8s/EventRecord.zig");
const ResourceClaimProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(ResourceClaimRecord);
const DeviceClassProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(DeviceClassRecord);
const PriorityClassProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(PriorityClassRecord);
const RuntimeClassProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(RuntimeClassRecord);
const LeaseProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(LeaseRecord);
const CSRProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(CSRRecord);
const StorageVersionMigrationProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(StorageVersionMigrationRecord);
const EventProjection = @import("k8s/ResourceProjection.zig").ResourceProjection(EventRecord);
const ResourceClaimSubscription = resource_subscription.ResourceSubscription(klient.ResourceClaim, ResourceClaimRecord, ResourceClaimRecord.fromResourceClaim);
const DeviceClassSubscription = resource_subscription.ResourceSubscription(klient.DeviceClass, DeviceClassRecord, DeviceClassRecord.fromDeviceClass);
const PriorityClassSubscription = resource_subscription.ResourceSubscription(klient.PriorityClass, PriorityClassRecord, PriorityClassRecord.fromPriorityClass);
const RuntimeClassSubscription = resource_subscription.ResourceSubscription(klient.RuntimeClass, RuntimeClassRecord, RuntimeClassRecord.fromRuntimeClass);
const LeaseSubscription = resource_subscription.ResourceSubscription(klient.Lease, LeaseRecord, LeaseRecord.fromLease);
const CSRSubscription = resource_subscription.ResourceSubscription(klient.CertificateSigningRequest, CSRRecord, CSRRecord.fromCSR);
const StorageVersionMigrationSubscription = resource_subscription.ResourceSubscription(klient.StorageVersionMigration, StorageVersionMigrationRecord, StorageVersionMigrationRecord.fromStorageVersionMigration);
const EventSubscription = resource_subscription.ResourceSubscription(klient.Event, EventRecord, EventRecord.fromEvent);
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
const ActiveContextSession = @import("k8s/ActiveContextSession.zig").ActiveContextSession;
const ContextSpec = @import("k8s/ActiveContextSession.zig").ContextSpec;
const SessionFactory = @import("k8s/ActiveContextSession.zig").SessionFactory;

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
    gateway_class_projection: GatewayClassProjection,
    gateway_projection: GatewayProjection,
    http_route_projection: HTTPRouteProjection,
    grpc_route_projection: GRPCRouteProjection,
    reference_grant_projection: ReferenceGrantProjection,
    tcp_route_projection: TCPRouteProjection,
    tls_route_projection: TLSRouteProjection,
    udp_route_projection: UDPRouteProjection,
    backend_tls_policy_projection: BackendTLSPolicyProjection,
    listener_set_projection: ListenerSetProjection,
    role_projection: RoleProjection,
    role_binding_projection: RoleBindingProjection,
    cluster_role_projection: ClusterRoleProjection,
    cluster_role_binding_projection: ClusterRoleBindingProjection,
    validating_admission_policy_projection: ValidatingAdmissionPolicyProjection,
    validating_admission_policy_binding_projection: ValidatingAdmissionPolicyBindingProjection,
    mutating_admission_policy_projection: MutatingAdmissionPolicyProjection,
    mutating_admission_policy_binding_projection: MutatingAdmissionPolicyBindingProjection,
    validating_webhook_configuration_projection: ValidatingWebhookConfigurationProjection,
    mutating_webhook_configuration_projection: MutatingWebhookConfigurationProjection,
    resource_claim_projection: ResourceClaimProjection,
    device_class_projection: DeviceClassProjection,
    priority_class_projection: PriorityClassProjection,
    runtime_class_projection: RuntimeClassProjection,
    lease_projection: LeaseProjection,
    csr_projection: CSRProjection,
    storage_version_migration_projection: StorageVersionMigrationProjection,
    event_projection: EventProjection,
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
            .gateway_class_projection = GatewayClassProjection.init(allocator, .{ .matchFn = gatewayClassProjectionMatch, .sortKeyFn = gatewayClassProjectionSortKey }),
            .gateway_projection = GatewayProjection.init(allocator, .{ .matchFn = gatewayProjectionMatch, .sortKeyFn = gatewayProjectionSortKey }),
            .http_route_projection = HTTPRouteProjection.init(allocator, .{ .matchFn = httpRouteProjectionMatch, .sortKeyFn = httpRouteProjectionSortKey }),
            .grpc_route_projection = GRPCRouteProjection.init(allocator, .{ .matchFn = grpcRouteProjectionMatch, .sortKeyFn = grpcRouteProjectionSortKey }),
            .reference_grant_projection = ReferenceGrantProjection.init(allocator, .{ .matchFn = referenceGrantProjectionMatch, .sortKeyFn = referenceGrantProjectionSortKey }),
            .tcp_route_projection = TCPRouteProjection.init(allocator, .{ .matchFn = tcpRouteProjectionMatch, .sortKeyFn = tcpRouteProjectionSortKey }),
            .tls_route_projection = TLSRouteProjection.init(allocator, .{ .matchFn = tlsRouteProjectionMatch, .sortKeyFn = tlsRouteProjectionSortKey }),
            .udp_route_projection = UDPRouteProjection.init(allocator, .{ .matchFn = udpRouteProjectionMatch, .sortKeyFn = udpRouteProjectionSortKey }),
            .backend_tls_policy_projection = BackendTLSPolicyProjection.init(allocator, .{ .matchFn = backendTLSPolicyProjectionMatch, .sortKeyFn = backendTLSPolicyProjectionSortKey }),
            .listener_set_projection = ListenerSetProjection.init(allocator, .{ .matchFn = listenerSetProjectionMatch, .sortKeyFn = listenerSetProjectionSortKey }),
            .role_projection = RoleProjection.init(allocator, .{ .matchFn = roleProjectionMatch, .sortKeyFn = roleProjectionSortKey }),
            .role_binding_projection = RoleBindingProjection.init(allocator, .{ .matchFn = roleBindingProjectionMatch, .sortKeyFn = roleBindingProjectionSortKey }),
            .cluster_role_projection = ClusterRoleProjection.init(allocator, .{ .matchFn = clusterRoleProjectionMatch, .sortKeyFn = clusterRoleProjectionSortKey }),
            .cluster_role_binding_projection = ClusterRoleBindingProjection.init(allocator, .{ .matchFn = clusterRoleBindingProjectionMatch, .sortKeyFn = clusterRoleBindingProjectionSortKey }),
            .validating_admission_policy_projection = ValidatingAdmissionPolicyProjection.init(allocator, .{ .matchFn = validatingAdmissionPolicyProjectionMatch, .sortKeyFn = validatingAdmissionPolicyProjectionSortKey }),
            .validating_admission_policy_binding_projection = ValidatingAdmissionPolicyBindingProjection.init(allocator, .{ .matchFn = validatingAdmissionPolicyBindingProjectionMatch, .sortKeyFn = validatingAdmissionPolicyBindingProjectionSortKey }),
            .mutating_admission_policy_projection = MutatingAdmissionPolicyProjection.init(allocator, .{ .matchFn = mutatingAdmissionPolicyProjectionMatch, .sortKeyFn = mutatingAdmissionPolicyProjectionSortKey }),
            .mutating_admission_policy_binding_projection = MutatingAdmissionPolicyBindingProjection.init(allocator, .{ .matchFn = mutatingAdmissionPolicyBindingProjectionMatch, .sortKeyFn = mutatingAdmissionPolicyBindingProjectionSortKey }),
            .validating_webhook_configuration_projection = ValidatingWebhookConfigurationProjection.init(allocator, .{ .matchFn = validatingWebhookConfigurationProjectionMatch, .sortKeyFn = validatingWebhookConfigurationProjectionSortKey }),
            .mutating_webhook_configuration_projection = MutatingWebhookConfigurationProjection.init(allocator, .{ .matchFn = mutatingWebhookConfigurationProjectionMatch, .sortKeyFn = mutatingWebhookConfigurationProjectionSortKey }),
            .resource_claim_projection = ResourceClaimProjection.init(allocator, .{ .matchFn = resourceClaimProjectionMatch, .sortKeyFn = resourceClaimProjectionSortKey }),
            .device_class_projection = DeviceClassProjection.init(allocator, .{ .matchFn = deviceClassProjectionMatch, .sortKeyFn = deviceClassProjectionSortKey }),
            .priority_class_projection = PriorityClassProjection.init(allocator, .{ .matchFn = priorityClassProjectionMatch, .sortKeyFn = priorityClassProjectionSortKey }),
            .runtime_class_projection = RuntimeClassProjection.init(allocator, .{ .matchFn = runtimeClassProjectionMatch, .sortKeyFn = runtimeClassProjectionSortKey }),
            .lease_projection = LeaseProjection.init(allocator, .{ .matchFn = leaseProjectionMatch, .sortKeyFn = leaseProjectionSortKey }),
            .csr_projection = CSRProjection.init(allocator, .{ .matchFn = csrProjectionMatch, .sortKeyFn = csrProjectionSortKey }),
            .storage_version_migration_projection = StorageVersionMigrationProjection.init(allocator, .{ .matchFn = storageVersionMigrationProjectionMatch, .sortKeyFn = storageVersionMigrationProjectionSortKey }),
            .event_projection = EventProjection.init(allocator, .{ .matchFn = eventProjectionMatch, .sortKeyFn = eventProjectionSortKey }),
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
        comptime columns_fn: anytype,
    ) !void {
        view.bindProjection(ResourceViewType.ProjectionAdapter.init(
            Record,
            projection,
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
            ),
        );
        self.registry.rebind();
    }

    fn bindViews(self: *ResourceFamilies, app: anytype) !void {
        try self.entries.ensureTotalCapacity(self.allocator, planned_family_capacity);
        self.registry = family_registry.Registry.initDynamic(&self.entries);
        try self.bind(ServiceRecord, ServiceSubscription, ServicesView, "services", &self.service_projection, app.services_view, serviceProjectionColumns);
        try self.bind(EndpointRecord, EndpointSubscription, EndpointsView, "endpoints", &self.endpoint_projection, app.endpoints_view, endpointProjectionColumns);
        try self.bind(EndpointSliceRecord, EndpointSliceSubscription, EndpointSlicesView, "endpointslices", &self.endpoint_slice_projection, app.endpointslices_view, endpointSliceProjectionColumns);
        try self.bind(ConfigMapRecord, ConfigMapSubscription, ConfigMapsView, "configmaps", &self.config_map_projection, app.configmaps_view, configMapProjectionColumns);
        try self.bind(SecretRecord, SecretSubscription, SecretsView, "secrets", &self.secret_projection, app.secrets_view, secretProjectionColumns);
        try self.bind(ServiceAccountRecord, ServiceAccountSubscription, ServiceAccountsView, "serviceaccounts", &self.service_account_projection, app.serviceaccounts_view, serviceAccountProjectionColumns);
        try self.bind(ResourceQuotaRecord, ResourceQuotaSubscription, ResourceQuotasView, "resourcequotas", &self.resource_quota_projection, app.resourcequotas_view, resourceQuotaProjectionColumns);
        try self.bind(LimitRangeRecord, LimitRangeSubscription, LimitRangesView, "limitranges", &self.limit_range_projection, app.limitranges_view, limitRangeProjectionColumns);
        try self.bind(DeploymentRecord, DeploymentSubscription, DeploymentsView, "deployments", &self.deployment_projection, app.deployments_view, deploymentProjectionColumns);
        try self.bind(StatefulSetRecord, StatefulSetSubscription, StatefulSetsView, "statefulsets", &self.stateful_set_projection, app.statefulsets_view, statefulSetProjectionColumns);
        try self.bind(DaemonSetRecord, DaemonSetSubscription, DaemonSetsView, "daemonsets", &self.daemon_set_projection, app.daemonsets_view, daemonSetProjectionColumns);
        try self.bind(ReplicaSetRecord, ReplicaSetSubscription, ReplicaSetsView, "replicasets", &self.replica_set_projection, app.replicasets_view, replicaSetProjectionColumns);
        try self.bind(JobRecord, JobSubscription, JobsView, "jobs", &self.job_projection, app.jobs_view, jobProjectionColumns);
        try self.bind(CronJobRecord, CronJobSubscription, CronJobsView, "cronjobs", &self.cron_job_projection, app.cronjobs_view, cronJobProjectionColumns);
        try self.bind(HPARecord, HPASubscription, HPAView, "hpa", &self.hpa_projection, app.hpa_view, hpaProjectionColumns);
        try self.bind(PDBRecord, PDBSubscription, PodDisruptionBudgetsView, "poddisruptionbudgets", &self.pdb_projection, app.poddisruptionbudgets_view, pdbProjectionColumns);
        try self.bind(IngressRecord, IngressSubscription, IngressesView, "ingresses", &self.ingress_projection, app.ingresses_view, ingressProjectionColumns);
        try self.bind(IngressClassRecord, IngressClassSubscription, IngressClassesView, "ingressclasses", &self.ingress_class_projection, app.ingressclasses_view, ingressClassProjectionColumns);
        try self.bind(NetworkPolicyRecord, NetworkPolicySubscription, NetworkPoliciesView, "networkpolicies", &self.network_policy_projection, app.networkpolicies_view, networkPolicyProjectionColumns);
        try self.bind(IPAddressRecord, IPAddressSubscription, IPAddressesView, "ipaddresses", &self.ip_address_projection, app.ipaddresses_view, ipAddressProjectionColumns);
        try self.bind(ServiceCIDRRecord, ServiceCIDRSubscription, ServiceCIDRsView, "servicecidrs", &self.service_cidr_projection, app.servicecidrs_view, serviceCIDRProjectionColumns);
        try self.bind(PVRecord, PVSubscription, PersistentVolumesView, "persistentvolumes", &self.pv_projection, app.persistentvolumes_view, pvProjectionColumns);
        try self.bind(PVCRecord, PVCSubscription, PersistentVolumeClaimsView, "persistentvolumeclaims", &self.pvc_projection, app.persistentvolumeclaims_view, pvcProjectionColumns);
        try self.bind(StorageClassRecord, StorageClassSubscription, StorageClassesView, "storageclasses", &self.storage_class_projection, app.storageclasses_view, storageClassProjectionColumns);
        try self.bind(VolumeAttributesClassRecord, VolumeAttributesClassSubscription, VolumeAttributesClassesView, "volumeattributesclasses", &self.volume_attributes_class_projection, app.volumeattributesclasses_view, volumeAttributesClassProjectionColumns);
        try self.bind(CSIDriverRecord, CSIDriverSubscription, CSIDriversView, "csidrivers", &self.csi_driver_projection, app.csidrivers_view, csiDriverProjectionColumns);
        try self.bind(GatewayClassRecord, GatewayClassSubscription, GatewayClassesView, "gatewayclasses", &self.gateway_class_projection, app.gatewayclasses_view, gatewayClassProjectionColumns);
        try self.bind(GatewayRecord, GatewaySubscription, GatewaysView, "gateways", &self.gateway_projection, app.gateways_view, gatewayProjectionColumns);
        try self.bind(HTTPRouteRecord, HTTPRouteSubscription, HTTPRoutesView, "httproutes", &self.http_route_projection, app.httproutes_view, httpRouteProjectionColumns);
        try self.bind(GRPCRouteRecord, GRPCRouteSubscription, GRPCRoutesView, "grpcroutes", &self.grpc_route_projection, app.grpcroutes_view, grpcRouteProjectionColumns);
        try self.bind(ReferenceGrantRecord, ReferenceGrantSubscription, ReferenceGrantsView, "referencegrants", &self.reference_grant_projection, app.referencegrants_view, referenceGrantProjectionColumns);
        try self.bind(TCPRouteRecord, TCPRouteSubscription, TCPRoutesView, "tcproutes", &self.tcp_route_projection, app.tcproutes_view, tcpRouteProjectionColumns);
        try self.bind(TLSRouteRecord, TLSRouteSubscription, TLSRoutesView, "tlsroutes", &self.tls_route_projection, app.tlsroutes_view, tlsRouteProjectionColumns);
        try self.bind(UDPRouteRecord, UDPRouteSubscription, UDPRoutesView, "udproutes", &self.udp_route_projection, app.udproutes_view, udpRouteProjectionColumns);
        try self.bind(BackendTLSPolicyRecord, BackendTLSPolicySubscription, BackendTLSPoliciesView, "backendtlspolicies", &self.backend_tls_policy_projection, app.backendtlspolicies_view, backendTLSPolicyProjectionColumns);
        try self.bind(ListenerSetRecord, ListenerSetSubscription, ListenerSetsView, "listenersets", &self.listener_set_projection, app.listenersets_view, listenerSetProjectionColumns);
        try self.bind(RoleRecord, RoleSubscription, RolesView, "roles", &self.role_projection, app.roles_view, roleProjectionColumns);
        try self.bind(RoleBindingRecord, RoleBindingSubscription, RoleBindingsView, "rolebindings", &self.role_binding_projection, app.rolebindings_view, roleBindingProjectionColumns);
        try self.bind(ClusterRoleRecord, ClusterRoleSubscription, ClusterRolesView, "clusterroles", &self.cluster_role_projection, app.clusterroles_view, clusterRoleProjectionColumns);
        try self.bind(ClusterRoleBindingRecord, ClusterRoleBindingSubscription, ClusterRoleBindingsView, "clusterrolebindings", &self.cluster_role_binding_projection, app.clusterrolebindings_view, clusterRoleBindingProjectionColumns);
        try self.bind(ValidatingAdmissionPolicyRecord, ValidatingAdmissionPolicySubscription, ValidatingAdmissionPoliciesView, "validatingadmissionpolicies", &self.validating_admission_policy_projection, app.validatingadmissionpolicies_view, validatingAdmissionPolicyProjectionColumns);
        try self.bind(ValidatingAdmissionPolicyBindingRecord, ValidatingAdmissionPolicyBindingSubscription, ValidatingAdmissionPolicyBindingsView, "validatingadmissionpolicybindings", &self.validating_admission_policy_binding_projection, app.validatingadmissionpolicybindings_view, validatingAdmissionPolicyBindingProjectionColumns);
        try self.bind(MutatingAdmissionPolicyRecord, MutatingAdmissionPolicySubscription, MutatingAdmissionPoliciesView, "mutatingadmissionpolicies", &self.mutating_admission_policy_projection, app.mutatingadmissionpolicies_view, mutatingAdmissionPolicyProjectionColumns);
        try self.bind(MutatingAdmissionPolicyBindingRecord, MutatingAdmissionPolicyBindingSubscription, MutatingAdmissionPolicyBindingsView, "mutatingadmissionpolicybindings", &self.mutating_admission_policy_binding_projection, app.mutatingadmissionpolicybindings_view, mutatingAdmissionPolicyBindingProjectionColumns);
        try self.bind(ValidatingWebhookConfigurationRecord, ValidatingWebhookConfigurationSubscription, ValidatingWebhookConfigurationsView, "validatingwebhookconfigurations", &self.validating_webhook_configuration_projection, app.validatingwebhookconfigurations_view, validatingWebhookConfigurationProjectionColumns);
        try self.bind(MutatingWebhookConfigurationRecord, MutatingWebhookConfigurationSubscription, MutatingWebhookConfigurationsView, "mutatingwebhookconfigurations", &self.mutating_webhook_configuration_projection, app.mutatingwebhookconfigurations_view, mutatingWebhookConfigurationProjectionColumns);
        try self.bind(ResourceClaimRecord, ResourceClaimSubscription, ResourceClaimsView, "resourceclaims", &self.resource_claim_projection, app.resourceclaims_view, resourceClaimProjectionColumns);
        try self.bind(DeviceClassRecord, DeviceClassSubscription, DeviceClassesView, "deviceclasses", &self.device_class_projection, app.deviceclasses_view, deviceClassProjectionColumns);
        try self.bind(PriorityClassRecord, PriorityClassSubscription, PriorityClassesView, "priorityclasses", &self.priority_class_projection, app.priorityclasses_view, priorityClassProjectionColumns);
        try self.bind(RuntimeClassRecord, RuntimeClassSubscription, RuntimeClassesView, "runtimeclasses", &self.runtime_class_projection, app.runtimeclasses_view, runtimeClassProjectionColumns);
        try self.bind(LeaseRecord, LeaseSubscription, LeasesView, "leases", &self.lease_projection, app.leases_view, leaseProjectionColumns);
        try self.bind(CSRRecord, CSRSubscription, CertificateSigningRequestsView, "certificatesigningrequests", &self.csr_projection, app.certificatesigningrequests_view, csrProjectionColumns);
        try self.bind(StorageVersionMigrationRecord, StorageVersionMigrationSubscription, StorageVersionMigrationsView, "storageversionmigrations", &self.storage_version_migration_projection, app.storageversionmigrations_view, storageVersionMigrationProjectionColumns);
        try self.bind(EventRecord, EventSubscription, EventsView, "events", &self.event_projection, app.events_view, eventProjectionColumns);
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
        self.gateway_class_projection.deinit();
        self.gateway_projection.deinit();
        self.http_route_projection.deinit();
        self.grpc_route_projection.deinit();
        self.reference_grant_projection.deinit();
        self.tcp_route_projection.deinit();
        self.tls_route_projection.deinit();
        self.udp_route_projection.deinit();
        self.backend_tls_policy_projection.deinit();
        self.listener_set_projection.deinit();
        self.role_projection.deinit();
        self.role_binding_projection.deinit();
        self.cluster_role_projection.deinit();
        self.cluster_role_binding_projection.deinit();
        self.validating_admission_policy_projection.deinit();
        self.validating_admission_policy_binding_projection.deinit();
        self.mutating_admission_policy_projection.deinit();
        self.mutating_admission_policy_binding_projection.deinit();
        self.validating_webhook_configuration_projection.deinit();
        self.mutating_webhook_configuration_projection.deinit();
        self.resource_claim_projection.deinit();
        self.device_class_projection.deinit();
        self.priority_class_projection.deinit();
        self.runtime_class_projection.deinit();
        self.lease_projection.deinit();
        self.csr_projection.deinit();
        self.storage_version_migration_projection.deinit();
        self.event_projection.deinit();
        self.entries.deinit(self.allocator);
    }
};

pub const Task14Injection = struct {
    spec_allocator: ?std.mem.Allocator = null,
    drain_allocator: ?std.mem.Allocator = null,
    transport: ?read_transport.ReadTransport = null,
    hold_watch: bool = false,
    deinit_counter: ?*std.atomic.Value(usize) = null,
    retry_wait_entered: ?*std.atomic.Value(bool) = null,
    fail_family_index: ?usize = null,
    retry_family_index: ?usize = null,
    retry_transport: ?read_transport.ReadTransport = null,
    metrics_transport: ?read_transport.ReadTransport = null,
    metrics_poll_interval_ns: ?u64 = null,
    header_transport: ?read_transport.ReadTransport = null,
    auth_backend: ?authorization_request.Backend = null,
    convert_allocator: ?std.mem.Allocator = null,
    emit_allocator: ?std.mem.Allocator = null,
    drain_batch_limit: ?usize = null,
    cancel_flag: ?*std.atomic.Value(bool) = null,
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
    diagnostic_writer: task15.Writer,
    shared_event: *std.Io.Event,
    wakeup: *Wakeup,
    change_queue: *ChangeQueue,
    active_session_slot: *ActiveSessionSlot,
    lifecycle_inbox: *LifecycleInbox,
    cancellation_intents: *CancellationIntents,
    lifecycle_producer: LifecycleProducer,
    lifecycle_supervisor: *LifecycleSupervisor,
    data_plane: *DataPlane,
    ancillary_requests: *AncillaryRequests,
    pod_projection: *PodProjection,
    node_projection: *NodeProjection,
    namespace_projection: *NamespaceProjection,
    resource_families: *ResourceFamilies,
    active_pod_subscription: ?lifecycle.SubscriptionKey = null,
    active_node_subscription: ?lifecycle.SubscriptionKey = null,
    active_namespace_subscription: ?lifecycle.SubscriptionKey = null,
    active_metrics_subscription: ?lifecycle.SubscriptionKey = null,
    active_header_metrics_request: ?resource_key.RequestKey = null,
    last_header_metrics_ns: i128 = 0,
    active_traffic_request: ?resource_key.RequestKey = null,
    last_traffic_ns: i128 = 0,
    traffic_relaunch_pending: bool = false,
    active_detail_request: ?resource_key.RequestKey = null,
    detail_request_serial: u64 = 0,
    detail_request_target: detail_request.UiTarget = undefined,
    active_logs_request: ?resource_key.RequestKey = null,
    logs_request_serial: u64 = 0,
    logs_request_target: logs_request.UiTarget = undefined,
    authorization_request_target: authorization_request.UiTarget = undefined,
    pod_metrics_started: bool = false,
    pod_initial_batch_applied: bool = false,
    pod_first_paint_emitted: bool = false,
    pod_list_complete_revision: ?resource_key.Revision = null,
    pod_complete_paint_emitted: bool = false,
    pod_restart_pending: bool = false,
    node_restart_pending: bool = false,
    namespace_restart_pending: bool = false,
    task15_control_exercised: bool = false,
    task15_control_not_before_ns: i128 = 0,
    task15_last_snapshot_ns: i128 = 0,
    task15_last_active_identities: usize = std.math.maxInt(usize),
    task15_first_paint_pending: u32 = 0,
    task15_complete_paint_pending: u32 = 0,
    pending_context_switch: ?[]u8 = null,
    task14: Task14Injection = .{},
    task14_cancel_intents_before_await: usize = 0,
    task14_context_install_after_drain: bool = false,
    task14_views_alive_after_await: bool = false,
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
        const diagnostic_writer = task15.Writer.initFromEnv();

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
        const ancillary_requests = try allocator.create(AncillaryRequests);
        ancillary_requests.* = AncillaryRequests.init(
            allocator,
            lifecycle_producer,
            change_queue,
        );
        errdefer allocator.destroy(ancillary_requests);

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
        if (config.namespace) |namespace| try k8s_service.setConfiguredNamespace(namespace);
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
            .context = config.context orelse "connecting...",
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
            .diagnostic_writer = diagnostic_writer,
            .shared_event = shared_event,
            .wakeup = wakeup,
            .change_queue = change_queue,
            .active_session_slot = active_session_slot,
            .lifecycle_inbox = lifecycle_inbox,
            .cancellation_intents = cancellation_intents,
            .lifecycle_producer = lifecycle_producer,
            .lifecycle_supervisor = supervisor,
            .data_plane = data_plane,
            .ancillary_requests = ancillary_requests,
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
            if (config.all_namespaces and @hasDecl(entry[1], "view_config") and
                entry[1].view_config.is_namespaced)
            {
                @field(app, entry[0]).table.show_all_namespaces = true;
            }
        }
        app.pods_view.bindPodProjection(app.pod_projection);
        app.nodes_view.bindProjection(NodesView.ProjectionAdapter.init(
            NodeRecord,
            app.node_projection,
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
        app.emitTask15LaunchStatus();
        return app;
    }

    fn emitTask15LaunchStatus(self: *App) void {
        const context = self.config.context orelse "";
        const scope = if (self.config.all_namespaces)
            "all-namespaces"
        else
            self.config.namespace orelse self.k8s_service.current_namespace;
        self.diagnostic_writer.emit(.{
            .event = .readonly_status,
            .context = context,
            .scope = scope,
            .readonly = self.config.readonly,
        });
        self.emitTask15Snapshot();
    }

    fn emitTask15Snapshot(self: *App) void {
        const stats = self.change_queue.snapshot();
        self.diagnostic_writer.emit(.{
            .event = .diagnostics_snapshot,
            .context = self.config.context orelse "",
            .scope = if (self.config.all_namespaces) "all-namespaces" else self.k8s_service.current_namespace,
            .snapshot = .{
                .queue = .{
                    .count = stats.count,
                    .bytes = stats.bytes,
                    .high_water_count = stats.high_water_count,
                    .high_water_bytes = stats.high_water_bytes,
                    .retries = stats.retries,
                    .drops = stats.drops,
                },
                .supervisor = .{
                    .live = self.lifecycle_supervisor.liveChildren(),
                    .launched = self.lifecycle_supervisor.metrics.launched,
                    .reaped = self.lifecycle_supervisor.metrics.reaped,
                    .canceled = self.lifecycle_supervisor.metrics.canceled,
                    .max_live = self.lifecycle_supervisor.metrics.max_live,
                    .active_identities = self.activeIdentityCount(),
                },
                .leases = .{
                    .active = self.active_session_slot.leaseCount(),
                    .retiring = self.lifecycle_supervisor.retiringLeaseCount(),
                },
            },
        });
    }

    pub fn activeIdentityCount(self: *const App) usize {
        return @intFromBool(self.active_pod_subscription != null) +
            @intFromBool(self.active_node_subscription != null) +
            @intFromBool(self.active_namespace_subscription != null) +
            @intFromBool(self.active_metrics_subscription != null) +
            self.resource_families.registry.activeIdentityCount() +
            self.ancillary_requests.activeIdentityCount();
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
        self.ancillary_requests.deinit();
        self.allocator.destroy(self.ancillary_requests);
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
                self.task15_control_not_before_ns = clock.nanoTimestamp() + std.time.ns_per_s;
                self.dirty = true;
                self.renderIfNeeded() catch {};

                // Server version remains a deferred UI update. Header metrics
                // are submitted as a supervised one-shot child.
                self.header.updateK8sVersion(self.k8s_service.getServerVersion()) catch {};
                self.startHeaderMetricsRequest() catch |err| {
                    Logger.warn("header metrics start failed: {any}", .{err});
                };
                self.dirty = true;
            }

            // Check if terminal was resized
            if (terminal_resized.load(.acquire)) {
                terminal_resized.store(false, .release);
                self.dirty = true;
            }
            self.maybeRunTask15Control();
            self.maybeEmitTask15Snapshot();

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
                self.servicePollTimeout();
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
                    self.serviceAuthorizationRequest();
                    // Paint loading feedback before a subscription restart is queued.
                    self.renderIfNeeded() catch |err| {
                        Logger.err("Render error: {any}", .{err});
                    };
                }
            }
        }
    }

    fn servicePollTimeout(self: *App) void {
        self.maybeRefreshHeaderMetrics();
        self.serviceTrafficRequest();
        self.serviceAuthorizationRequest();
    }

    pub fn finishLifecycle(self: *App) void {
        if (self.lifecycle_supervisor.root_future == null) return;
        if (self.task14.cancel_flag) |flag| flag.store(true, .release);
        var intents: usize = 0;
        if (self.active_metrics_subscription) |key| {
            if (self.data_plane.cancelSubscription(key) == .requested) intents += 1;
            self.active_metrics_subscription = null;
        }
        intents += self.ancillary_requests.cancelAll();
        if (self.active_pod_subscription) |key| {
            if (self.data_plane.cancelSubscription(key) == .requested) intents += 1;
            self.active_pod_subscription = null;
            self.pods_view.markPodSubscriptionStopped();
        }
        if (self.active_node_subscription) |key| {
            if (self.data_plane.cancelSubscription(key) == .requested) intents += 1;
            self.active_node_subscription = null;
            self.nodes_view.markSubscriptionStopped();
        }
        if (self.active_namespace_subscription) |key| {
            if (self.data_plane.cancelSubscription(key) == .requested) intents += 1;
            self.active_namespace_subscription = null;
            self.namespaces_view.markSubscriptionStopped();
        }
        for (self.resource_families.registry.items()) |*entry| {
            if (entry.active) |key| {
                if (self.data_plane.cancelSubscription(key) == .requested) intents += 1;
            }
            entry.markStopped();
        }
        self.lifecycle_producer.enqueueShutdown() catch |err| switch (err) {
            error.Closed => {},
        };
        self.task14_cancel_intents_before_await = intents;
        while (!self.lifecycle_inbox.isRootTerminated()) {
            self.drainChangeQueueForShutdown();
            if (self.lifecycle_inbox.isRootTerminated()) break;
            runtime.io().sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake) catch {};
        }
        if (self.lifecycle_supervisor.awaitRoot()) {
            self.lifecycle_root_await_count += 1;
            if (self.task14.transport != null) {
                _ = self.pod_projection.count();
                _ = self.node_projection.count();
                _ = self.namespace_projection.count();
                _ = self.pods_view.table.items.items.len;
                _ = self.resource_families.registry.itemsConst().len;
                self.task14_views_alive_after_await = true;
            }
        }
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
            else => self.ancillary_requests.acceptsEnvelope(envelope),
        };
    }

    fn serviceResourceSubscriptionRequests(self: *App) !void {
        try self.servicePodSubscriptionRequest();
        try self.serviceNodeSubscriptionRequest();
        try self.serviceNamespaceSubscriptionRequest();
        try self.serviceResourceFamilyRequests();
    }

    fn maybeRunTask15Control(self: *App) void {
        if (self.task15_control_exercised or self.config.diagnostic_control == null) return;
        if (clock.nanoTimestamp() < self.task15_control_not_before_ns) return;
        const control = self.config.diagnostic_control.?;
        const family = switch (control) {
            .reconnect => |value| value,
            .stale_rv => |value| value,
        };
        if (control == .stale_rv) task15.armStaleRv(family);
        switch (family) {
            .pod => if (self.active_pod_subscription) |key| {
                self.pod_restart_pending = true;
                self.cancelMetricsFeed();
                _ = self.data_plane.cancelSubscription(key);
            },
            .node => if (self.active_node_subscription) |key| {
                self.node_restart_pending = true;
                _ = self.data_plane.cancelSubscription(key);
            },
            .namespace => if (self.active_namespace_subscription) |key| {
                self.namespace_restart_pending = true;
                _ = self.data_plane.cancelSubscription(key);
            },
            else => for (self.resource_families.registry.items()) |*entry| {
                if (task15.familyForResource(entry.name) != family) continue;
                if (entry.active) |key| {
                    entry.restart_pending = true;
                    _ = self.data_plane.cancelSubscription(key);
                }
            },
        }
        self.diagnostic_writer.emit(.{
            .event = switch (control) {
                .reconnect => .diagnostic_reconnect,
                .stale_rv => .diagnostic_stale_rv,
            },
            .context = self.config.context orelse "",
            .scope = self.k8s_service.current_namespace,
            .family = family,
        });
        self.task15_control_exercised = true;
    }

    fn maybeEmitTask15Snapshot(self: *App) void {
        const now = clock.nanoTimestamp();
        const active_identities = self.activeIdentityCount();
        if (active_identities != self.task15_last_active_identities) {
            self.task15_last_active_identities = active_identities;
            self.task15_last_snapshot_ns = now;
            self.emitTask15Snapshot();
            return;
        }
        if (now - self.task15_last_snapshot_ns < std.time.ns_per_s) return;
        self.task15_last_snapshot_ns = now;
        self.emitTask15Snapshot();
    }

    fn servicePodSubscriptionRequest(self: *App) !void {
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
        if (task15.isLiveMode()) return error.Task15ContextSwitchDisabled;
        const owned_name = try self.allocator.dupe(u8, context_name);
        errdefer self.allocator.free(owned_name);
        if (self.pending_context_switch) |old_name| self.allocator.free(old_name);
        self.pending_context_switch = owned_name;
        self.pod_restart_pending = self.active_pod_subscription != null;
        self.node_restart_pending = self.active_node_subscription != null;
        self.namespace_restart_pending = self.active_namespace_subscription != null;
        self.resource_families.registry.markForContextRestart();
        self.cancelMetricsFeed();
        const session_view = self.active_session_slot.view();
        if (session_view.state == .active) {
            _ = self.ancillary_requests.invalidateGeneration(session_view.generation);
        }
        self.active_detail_request = null;
        self.detail_request_serial +%= 1;
        self.active_logs_request = null;
        self.logs_request_serial +%= 1;
        inline for (.{ AuthorizationView.Tab.access_review, .policy_browser, .condition_inspector }) |tab| {
            self.authorization_view.activeKey(tab).* = null;
            _ = self.authorization_view.beginRequest(tab);
            self.authorization_view.loading = false;
        }
        if (self.active_pod_subscription) |active| _ = self.data_plane.cancelSubscription(active);
        if (self.active_node_subscription) |active| _ = self.data_plane.cancelSubscription(active);
        if (self.active_namespace_subscription) |active| _ = self.data_plane.cancelSubscription(active);
        for (self.resource_families.registry.itemsConst()) |entry| {
            if (entry.active) |active| _ = self.data_plane.cancelSubscription(active);
        }
        if (self.hasActiveResourceSubscriptions()) return;
        self.tryFinishContextSwitch();
    }

    fn tryFinishContextSwitch(self: *App) void {
        if (self.pending_context_switch == null) return;
        if (self.lifecycle_supervisor.liveChildren() != 0) return;
        if (self.active_session_slot.leaseCount() != 0) return;
        if (self.change_queue.hasPending()) return;
        if (self.hasActiveResourceSubscriptions() or self.active_metrics_subscription != null) {
            self.active_pod_subscription = null;
            self.active_metrics_subscription = null;
            self.active_node_subscription = null;
            self.active_namespace_subscription = null;
            for (self.resource_families.registry.items()) |*entry| {
                if (entry.active != null) entry.markStopped();
            }
        }
        self.completeContextSwitch() catch |err| {
            self.contexts_view.setError(err) catch {};
            self.dirty = true;
        };
    }

    fn task14SpecAllocator(self: *const App) std.mem.Allocator {
        return self.task14.spec_allocator orelse self.allocator;
    }

    fn task14FamilyExtras(self: *const App, index: usize) ?family_registry.Task14SpecExtras {
        if (self.task14.retry_family_index) |retry_index| {
            if (index == retry_index) {
                const transport = self.task14.retry_transport orelse return null;
                return .{
                    .transport = transport,
                    .hold_watch = false,
                    .deinit_counter = self.task14.deinit_counter,
                    .retry_wait_entered = self.task14.retry_wait_entered,
                    .convert_allocator = self.task14.convert_allocator,
                    .emit_allocator = self.task14.emit_allocator,
                };
            }
        }
        const transport = self.task14.transport orelse return null;
        return .{
            .transport = transport,
            .hold_watch = self.task14.hold_watch,
            .deinit_counter = self.task14.deinit_counter,
            .retry_wait_entered = null,
            .convert_allocator = self.task14.convert_allocator,
            .emit_allocator = self.task14.emit_allocator,
        };
    }

    fn completeContextSwitch(self: *App) !void {
        const context_name = self.pending_context_switch orelse return;
        if (self.task14.transport != null) {
            self.task14_context_install_after_drain =
                self.lifecycle_supervisor.liveChildren() == 0 and
                self.active_session_slot.leaseCount() == 0 and
                !self.change_queue.hasPending();
        }
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
        const spec_allocator = self.task14SpecAllocator();
        var spec = try pod_subscription.ownedTaskSpec(spec_allocator, .{
            .namespace = namespace,
            .context_name = self.k8s_service.context_name,
            .projection = self.pod_projection,
            .telemetry = &self.perf_telemetry,
            .transport_override = self.task14.transport,
            .hold_watch = self.task14.hold_watch,
            .deinit_counter = self.task14.deinit_counter,
            .convert_allocator = self.task14.convert_allocator,
            .emit_allocator = self.task14.emit_allocator,
        });
        errdefer spec.deinit(spec_allocator);
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
        const spec_allocator = self.task14SpecAllocator();
        var spec = try NodeSubscription.ownedTaskSpec(spec_allocator, .{
            .context_name = self.k8s_service.context_name,
            .projection = self.node_projection,
            .transport_override = self.task14.transport,
            .hold_watch = self.task14.hold_watch,
            .deinit_counter = self.task14.deinit_counter,
            .convert_allocator = self.task14.convert_allocator,
            .emit_allocator = self.task14.emit_allocator,
        });
        errdefer spec.deinit(spec_allocator);
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
        const spec_allocator = self.task14SpecAllocator();
        var spec = try NamespaceSubscription.ownedTaskSpec(spec_allocator, .{
            .context_name = self.k8s_service.context_name,
            .projection = self.namespace_projection,
            .transport_override = self.task14.transport,
            .hold_watch = self.task14.hold_watch,
            .deinit_counter = self.task14.deinit_counter,
            .convert_allocator = self.task14.convert_allocator,
            .emit_allocator = self.task14.emit_allocator,
        });
        errdefer spec.deinit(spec_allocator);
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
        if (self.task14.fail_family_index) |fail_index| {
            if (index == fail_index) {
                self.task14.fail_family_index = null;
                return error.InjectedStartFailure;
            }
        }
        const namespace = entry.namespace(self.k8s_service.current_namespace);
        const spec_allocator = self.task14SpecAllocator();
        var spec = if (self.task14FamilyExtras(index)) |extras|
            try entry.task14InjectedSpecFn(
                spec_allocator,
                self.k8s_service.context_name,
                namespace,
                entry.projection,
                extras,
            )
        else
            try entry.taskSpecFn(
                spec_allocator,
                self.k8s_service.context_name,
                namespace,
                entry.projection,
            );
        errdefer spec.deinit(spec_allocator);
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
        const spec_allocator = self.task14SpecAllocator();
        var spec = try metrics_feed.ownedTaskSpec(spec_allocator, .{
            .namespace = namespace,
            .projection = self.pod_projection,
            .poll_interval_ns = self.task14.metrics_poll_interval_ns orelse metrics_feed.default_poll_interval_ns,
            .transport_override = self.task14.metrics_transport,
            .deinit_counter = self.task14.deinit_counter,
        });
        errdefer spec.deinit(spec_allocator);
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
            .monotonic_ns = @intCast(@max(clock.monotonicNanoTimestamp(), 0)),
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
        self.drainChangeQueueWithPolicy(false);
    }

    fn drainChangeQueueForShutdown(self: *App) void {
        self.drainChangeQueueWithPolicy(true);
    }

    fn drainChangeQueueWithPolicy(self: *App, shutting_down: bool) void {
        var router = resource_key.UiRouter{
            .context = @ptrCast(self),
            .targetFn = appEnvelopeTarget,
            .lifecycleFn = appObserveLifecycle,
        };
        var n: usize = 0;
        const drain_limit = self.task14.drain_batch_limit orelse
            resource_key.Limits.default.drain_batches;
        while (n < drain_limit) : (n += 1) {
            var popped = self.change_queue.popForRetry() orelse break;
            const envelope = &popped.envelope;
            const apply_allocator = self.task14.drain_allocator orelse self.allocator;
            if (!self.data_plane.acceptsEnvelope(envelope.*) or
                !self.acceptsActiveEnvelope(envelope.*))
            {
                popped.destroy(apply_allocator);
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
            envelope.apply(&router, apply_allocator) catch |err| {
                Logger.err("envelope apply failed: {any}", .{err});
                if (is_pod_subscription) self.pod_projection_apply_failed = true;
                if (shutting_down or self.lifecycle_supervisor.root_future == null) {
                    popped.destroy(apply_allocator);
                } else {
                    self.change_queue.retryPopped(&popped) catch popped.destroy(apply_allocator);
                }
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
                if (self.task15FamilyForTarget(target)) |family| {
                    const bit = @as(u32, 1) << @intFromEnum(family);
                    if (initial_changes) self.task15_first_paint_pending |= bit;
                    if (sync_kind == .list_complete) self.task15_complete_paint_pending |= bit;
                }
            }
            self.dirty = true;
        }
        self.tryFinishContextSwitch();
    }

    fn task15FamilyForTarget(self: *const App, target: resource_key.EnvelopeTarget) ?task15.Family {
        const identity = switch (target) {
            .resource => |value| value,
            else => return null,
        };
        if (matchesIdentity(self.active_pod_subscription, identity)) return .pod;
        if (matchesIdentity(self.active_node_subscription, identity)) return .node;
        if (matchesIdentity(self.active_namespace_subscription, identity)) return .namespace;
        for (self.resource_families.registry.itemsConst()) |entry| {
            const active = entry.active orelse continue;
            if (active.generation == identity.generation and
                active.subscription_id == identity.subscription_id)
                return task15.familyForResource(entry.name);
        }
        return null;
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
            .header_metrics => |key| if (self.ancillary_requests.contains(key, .header_metrics))
                @ptrCast(&self.header)
            else
                null,
            .traffic => |key| if (self.ancillary_requests.contains(key, .traffic))
                @ptrCast(self.traffic_view)
            else
                null,
            .detail => |key| self.detailEnvelopeTarget(key, .detail),
            .yaml => |key| self.detailEnvelopeTarget(key, .yaml),
            .logs => |key| blk: {
                const active = self.active_logs_request orelse break :blk null;
                if (!active.eql(key) or !self.ancillary_requests.contains(key, .logs))
                    break :blk null;
                self.logs_request_target = .{
                    .view = self.logs_view,
                    .view_manager = &self.view_manager,
                    .active_key = active,
                    .active_serial = self.logs_request_serial,
                    .dirty = &self.dirty,
                };
                break :blk @ptrCast(&self.logs_request_target);
            },
            .authorization => |key| blk: {
                if (!self.ancillary_requests.contains(key, .authorization)) break :blk null;
                var matched = false;
                inline for (.{ AuthorizationView.Tab.access_review, .policy_browser, .condition_inspector }) |tab| {
                    if (self.authorization_view.activeKey(tab).*) |active| {
                        if (active.eql(key)) matched = true;
                    }
                }
                if (!matched) break :blk null;
                self.authorization_request_target = .{ .view = self.authorization_view };
                break :blk @ptrCast(&self.authorization_request_target);
            },
        };
    }

    fn detailEnvelopeTarget(
        self: *App,
        key: resource_key.RequestKey,
        class: resource_key.RequestClass,
    ) ?*anyopaque {
        const active = self.active_detail_request orelse return null;
        if (!active.eql(key) or !self.ancillary_requests.contains(key, class)) return null;
        self.detail_request_target = .{
            .view = self.detail_view,
            .view_manager = &self.view_manager,
            .active_key = active,
            .active_serial = self.detail_request_serial,
            .dirty = &self.dirty,
        };
        return @ptrCast(&self.detail_request_target);
    }

    pub fn appObserveLifecycle(
        raw: *anyopaque,
        payload: *anyopaque,
        identity: ?resource_key.ResourceIdentity,
    ) void {
        const self: *App = @ptrCast(@alignCast(raw));
        defer if (task15.isLiveMode()) self.maybeEmitTask15Snapshot();
        const completion: *lifecycle.LifecycleCompletion = @ptrCast(@alignCast(payload));
        if (self.ancillary_requests.handleCompletion(completion.*)) {
            const key: ?resource_key.RequestKey = switch (completion.*) {
                .request_finished => |finished| finished.key,
                .start_rejected => |rejected| rejected.request_key,
                else => null,
            };
            if (key) |completed| {
                if (self.active_header_metrics_request) |active| {
                    if (active.eql(completed)) {
                        self.active_header_metrics_request = null;
                        self.last_header_metrics_ns = clock.nanoTimestamp();
                    }
                }
                if (self.active_traffic_request) |active| {
                    if (active.eql(completed)) {
                        self.active_traffic_request = null;
                        self.last_traffic_ns = clock.nanoTimestamp();
                        self.serviceTrafficRequest();
                    }
                }
                if (self.active_detail_request) |active| {
                    if (active.eql(completed)) self.active_detail_request = null;
                }
                if (self.active_logs_request) |active| {
                    if (active.eql(completed)) self.active_logs_request = null;
                }
                var authorization_completed = false;
                inline for (.{ AuthorizationView.Tab.access_review, .policy_browser, .condition_inspector }) |tab| {
                    const active_ptr = self.authorization_view.activeKey(tab);
                    if (active_ptr.*) |active| {
                        if (active.eql(completed)) {
                            active_ptr.* = null;
                            authorization_completed = true;
                        }
                    }
                }
                if (authorization_completed) switch (completion.*) {
                    .start_rejected => {
                        if (self.authorization_view.error_message) |message|
                            self.allocator.free(message);
                        self.authorization_view.error_message = self.allocator.dupe(
                            u8,
                            "Authorization request could not start",
                        ) catch null;
                    },
                    else => {},
                };
                self.authorization_view.loading = self.authorization_view.hasActiveRequests();
            }
            self.tryFinishContextSwitch();
            return;
        }
        if (isActivePodCompletion(self.active_metrics_subscription, identity, completion.*)) {
            self.active_metrics_subscription = null;
            self.tryFinishContextSwitch();
            return;
        }
        if (isActivePodCompletion(self.active_pod_subscription, identity, completion.*)) {
            self.active_pod_subscription = null;
            self.cancelMetricsFeed();
            self.pods_view.markPodSubscriptionStopped();
            if (task15TerminalMessage(completion.*)) |message| {
                self.pods_view.table.loading = false;
                self.pods_view.table.setError(message) catch {};
                self.dirty = true;
            }
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
            if (task15TerminalMessage(completion.*)) |message| {
                self.nodes_view.table.loading = false;
                self.nodes_view.table.setError(message) catch {};
                self.dirty = true;
            }
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
            if (task15TerminalMessage(completion.*)) |message| {
                self.namespaces_view.table.loading = false;
                self.namespaces_view.table.setError(message) catch {};
                self.dirty = true;
            }
            if (self.namespace_restart_pending and self.pending_context_switch == null) {
                self.namespace_restart_pending = false;
                self.startNamespaceSubscription() catch |err| {
                    self.namespaces_view.table.setErrorFmt("Namespace subscription failed: {any}", .{err}) catch {};
                    self.dirty = true;
                };
            }
        } else if (self.resource_families.registry.complete(identity, completion.*)) |index| {
            const entry = self.resource_families.registry.entryAt(index) orelse return;
            if (task15TerminalMessage(completion.*)) |message| {
                entry.setError(message) catch {};
                self.dirty = true;
            }
            if (entry.restart_pending and self.pending_context_switch == null) {
                self.startResourceFamilySubscription(index) catch |err| {
                    markFamilyStartOutcome(entry, false);
                    Logger.err("{s} subscription failed: {any}", .{ entry.name, err });
                    self.dirty = true;
                    return;
                };
                markFamilyStartOutcome(entry, true);
            }
        } else {
            self.tryFinishContextSwitch();
            return;
        }

        self.tryFinishContextSwitch();
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

        const safety_visible = self.config.readonly;
        const new_header_height = if (self.view_fullscreen and !safety_visible) 0 else self.header.height();
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
        const namespace_scope = if (self.view_manager.getCurrentView()) |current|
            if (current.showsAllNamespaces()) "all-namespaces" else self.k8s_service.current_namespace
        else if (self.config.all_namespaces)
            "all-namespaces"
        else
            self.k8s_service.current_namespace;
        try self.header.setReadonlyScope(self.config.readonly, namespace_scope);

        // Render header with hints from current view
        if ((!self.view_fullscreen or safety_visible) and size.height >= self.header_height) {
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
        self.emitTask15PaintsAfterFlush();
        self.prev_width = size.width;
        self.prev_height = size.height;
        self.dirty = false;
    }

    fn emitTask15PaintsAfterFlush(self: *App) void {
        const view = self.view_manager.getCurrentView() orelse return;
        const family = task15.familyForResource(view.getName()) orelse return;
        const bit = @as(u32, 1) << @intFromEnum(family);
        const base: task15.Record = .{
            .event = .first_usable_paint,
            .context = self.config.context orelse self.k8s_service.context_name,
            .scope = if (view.showsAllNamespaces()) "all-namespaces" else self.k8s_service.current_namespace,
            .family = family,
            .resource = view.getName(),
        };
        if (self.task15_first_paint_pending & bit != 0) {
            self.diagnostic_writer.emit(base);
            self.task15_first_paint_pending &= ~bit;
        }
        if (self.task15_complete_paint_pending & bit != 0) {
            var complete = base;
            complete.event = .complete_sync_paint;
            self.diagnostic_writer.emit(complete);
            self.task15_complete_paint_pending &= ~bit;
        }
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

    fn startHeaderMetricsRequest(self: *App) !void {
        if (!self.k8s_service.isConnected() or self.active_header_metrics_request != null) return;
        if (self.view_manager.getCurrentView()) |view| {
            if (std.mem.eql(u8, view.getName(), "pods") and !self.pod_first_paint_emitted)
                return;
        }
        const session_view = self.active_session_slot.view();
        if (session_view.state != .active) return error.NoActiveSession;
        var spec = try header_metrics_request.ownedTaskSpec(self.allocator, .{
            .transport_override = self.task14.header_transport,
        });
        errdefer spec.deinit(self.allocator);
        self.active_header_metrics_request = try self.ancillary_requests.startRequest(
            .header_metrics,
            session_view.generation,
            &spec,
        );
    }

    fn maybeRefreshHeaderMetrics(self: *App) void {
        if (!self.k8s_service.isConnected() or self.active_header_metrics_request != null) return;
        const interval = self.config.refresh_rate;
        if (!(interval > 0) or !std.math.isFinite(interval)) return;
        const now = clock.nanoTimestamp();
        if (self.last_header_metrics_ns != 0) {
            const elapsed = now - self.last_header_metrics_ns;
            if (elapsed < 0 or elapsed < @as(i128, @intFromFloat(interval * std.time.ns_per_s)))
                return;
        }
        self.startHeaderMetricsRequest() catch |err| {
            self.last_header_metrics_ns = now;
            Logger.warn("header metrics refresh failed: {any}", .{err});
        };
    }

    fn startTrafficRequest(self: *App) !void {
        if (!self.k8s_service.isConnected() or self.active_traffic_request != null) return;
        const session_view = self.active_session_slot.view();
        if (session_view.state != .active) return error.NoActiveSession;
        var spec = try traffic_request.ownedTaskSpec(self.allocator, .{
            .workload = self.traffic_view.workload,
            .namespace = self.traffic_view.namespace,
        });
        errdefer spec.deinit(self.allocator);
        self.active_traffic_request = try self.ancillary_requests.startRequest(
            .traffic,
            session_view.generation,
            &spec,
        );
    }

    fn serviceTrafficRequest(self: *App) void {
        const shown = self.view_manager.isViewActive("traffic");
        if (!shown) {
            self.traffic_relaunch_pending = false;
            if (self.active_traffic_request) |active| {
                _ = self.ancillary_requests.cancelRequest(active);
            }
            return;
        }
        if (self.traffic_view.takeRefreshRequest()) {
            self.traffic_relaunch_pending = true;
            if (self.active_traffic_request) |active| {
                _ = self.ancillary_requests.cancelRequest(active);
                return;
            }
        }
        if (self.active_traffic_request != null) return;

        const now = clock.nanoTimestamp();
        if (!self.traffic_relaunch_pending and self.last_traffic_ns != 0) {
            const elapsed = now - self.last_traffic_ns;
            if (elapsed >= 0 and elapsed < 5 * std.time.ns_per_s) return;
        }
        self.startTrafficRequest() catch |err| {
            self.last_traffic_ns = now;
            Logger.warn("traffic refresh failed: {any}", .{err});
            return;
        };
        self.traffic_relaunch_pending = false;
    }

    fn serviceAuthorizationRequest(self: *App) void {
        var request = self.authorization_view.takeRefreshRequest() orelse return;
        defer request.deinit(self.allocator);
        const tab = std.meta.activeTag(request);
        const session_view = self.active_session_slot.view();
        if (session_view.state != .active) {
            self.authorization_view.loading = false;
            return;
        }
        const serial = self.authorization_view.beginRequest(tab);
        const resource, const group = switch (request) {
            .condition_inspector => |value| .{ value.resource, value.group },
            else => .{ "", "" },
        };
        var spec = authorization_request.ownedTaskSpec(self.allocator, .{
            .serial = serial,
            .tab = tab,
            .service = self.k8s_service,
            .namespace = self.k8s_service.getCurrentNamespace(),
            .resource = resource,
            .group = group,
            .conditional_auth_available = self.authorization_view.access_tab.conditional_auth_available,
            .cedar_available = self.authorization_view.policy_tab.cedar_available,
            .backend_override = self.task14.auth_backend,
        }) catch |err| {
            Logger.warn("authorization request build failed: {any}", .{err});
            self.authorization_view.loading = false;
            return;
        };
        defer spec.deinit(self.allocator);
        const active_ptr = self.authorization_view.activeKey(tab);
        if (active_ptr.*) |active| _ = self.ancillary_requests.cancelRequest(active);
        active_ptr.* = null;
        active_ptr.* = self.ancillary_requests.startRequest(
            .authorization,
            session_view.generation,
            &spec,
        ) catch |err| {
            Logger.warn("authorization request start failed: {any}", .{err});
            self.authorization_view.loading = false;
            return;
        };
        self.dirty = true;
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
        try self.view_manager.pushView(self.traffic_view.createView());
        self.serviceTrafficRequest();
        self.dirty = true;
    }

    /// Suspend the TUI (leave raw mode + alternate screen), run an interactive
    /// command with the inherited terminal (so $EDITOR / shell work), then
    /// restore the TUI and refresh. Used by edit/shell/attach.
    fn runInteractive(self: *App, argv: []const []const u8) !void {
        const owned_argv = if (argv.len > 0 and std.mem.eql(u8, argv[0], "kubectl"))
            try self.k8s_service.buildInteractiveKubectlArgv(argv[1..])
        else
            null;
        defer if (owned_argv) |args| self.allocator.free(args);
        const final_argv = owned_argv orelse argv;

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
        // Refuse before selecting and formatting the target. runInteractive also
        // enforces readonly through K8sService as the non-bypassable boundary.
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
        self.serviceAuthorizationRequest();
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

    /// Submit one supervised detail or YAML request.
    fn showDetailView(self: *App, describe: bool) !void {
        const resource_type = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        const session_view = self.active_session_slot.view();
        if (session_view.state != .active) return error.NoActiveSession;
        self.detail_request_serial +%= 1;
        if (self.detail_request_serial == 0) self.detail_request_serial = 1;
        const serial = self.detail_request_serial;
        var spec = try detail_request.ownedTaskSpec(self.allocator, .{
            .serial = serial,
            .kind = if (describe) .describe else .yaml,
            .resource_type = resource_type,
            .name = info.name,
            .namespace = info.namespace,
        });
        errdefer spec.deinit(self.allocator);
        if (self.active_detail_request) |active| {
            _ = self.ancillary_requests.cancelRequest(active);
        }
        self.active_detail_request = null;
        self.active_detail_request = try self.ancillary_requests.startRequest(
            if (describe) .detail else .yaml,
            session_view.generation,
            &spec,
        );
    }

    /// Base64-decode the selected Secret and show it in the detail view.
    ///
    /// Not gated by --readonly: this reads, it does not mutate. RBAC still applies --
    /// the GET fails on its own if the user cannot read secrets.
    fn showDecodedSecret(self: *App) !void {
        if (!std.mem.eql(u8, self.current_view_name, "secrets")) return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;
        const session_view = self.active_session_slot.view();
        if (session_view.state != .active) return error.NoActiveSession;
        self.detail_request_serial +%= 1;
        if (self.detail_request_serial == 0) self.detail_request_serial = 1;
        const serial = self.detail_request_serial;
        var spec = try detail_request.ownedTaskSpec(self.allocator, .{
            .serial = serial,
            .kind = .decoded_secret,
            .resource_type = .secrets,
            .name = info.name,
            .namespace = info.namespace,
        });
        errdefer spec.deinit(self.allocator);
        if (self.active_detail_request) |active| {
            _ = self.ancillary_requests.cancelRequest(active);
        }
        self.active_detail_request = null;
        self.active_detail_request = try self.ancillary_requests.startRequest(
            .detail,
            session_view.generation,
            &spec,
        );
    }

    /// Submit one supervised pod-log request.
    fn showLogsView(self: *App, previous: bool) !void {
        if (!std.mem.eql(u8, self.current_view_name, "pods")) return;
        const info = self.pods_view.getSelectedResourceInfo() orelse return;
        const session_view = self.active_session_slot.view();
        if (session_view.state != .active) return error.NoActiveSession;
        self.logs_request_serial +%= 1;
        if (self.logs_request_serial == 0) self.logs_request_serial = 1;
        const serial = self.logs_request_serial;
        var spec = try logs_request.ownedTaskSpec(self.allocator, .{
            .serial = serial,
            .pod_name = info.name,
            .namespace = info.namespace,
            .previous = previous,
        });
        errdefer spec.deinit(self.allocator);
        if (self.active_logs_request) |active| {
            _ = self.ancillary_requests.cancelRequest(active);
        }
        self.active_logs_request = null;
        self.active_logs_request = try self.ancillary_requests.startRequest(
            .logs,
            session_view.generation,
            &spec,
        );
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
                self.beginContextSwitch(ctx_name) catch {
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
            if (self.k8s_service.isConnected())
                try self.k8s_service.setCurrentNamespace(ns)
            else
                try self.k8s_service.setConfiguredNamespace(ns);
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
        try self.serviceResourceSubscriptionRequests();
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

    fn refreshCurrentView(self: *App) void {
        if (self.view_manager.getCurrentView()) |current| {
            current.refresh() catch |err| {
                Logger.err("Failed to refresh view: {any}", .{err});
            };
        }
        self.serviceResourceSubscriptionRequests() catch |err| {
            Logger.err("Failed to refresh resource subscription: {any}", .{err});
        };
        self.serviceAuthorizationRequest();
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

fn resourceClaimProjectionColumns(_: *ResourceClaimProjection, record: *const ResourceClaimRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}
fn deviceClassProjectionColumns(_: *DeviceClassProjection, record: *const DeviceClassRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}
fn priorityClassProjectionColumns(_: *PriorityClassProjection, record: *const PriorityClassRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}
fn runtimeClassProjectionColumns(_: *RuntimeClassProjection, record: *const RuntimeClassRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}
fn leaseProjectionColumns(_: *LeaseProjection, record: *const LeaseRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}
fn csrProjectionColumns(_: *CSRProjection, record: *const CSRRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}
fn storageVersionMigrationProjectionColumns(_: *StorageVersionMigrationProjection, record: *const StorageVersionMigrationRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}
fn eventProjectionColumns(_: *EventProjection, record: *const EventRecord, allocator: std.mem.Allocator) ![7][]const u8 {
    return record.columns(allocator);
}

fn resourceClaimProjectionMatch(record: *const ResourceClaimRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.status, filter);
}
fn deviceClassProjectionMatch(record: *const DeviceClassRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter);
}
fn priorityClassProjectionMatch(record: *const PriorityClassRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter);
}
fn runtimeClassProjectionMatch(record: *const RuntimeClassRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter) or containsIgnoreCase(record.handler, filter);
}
fn leaseProjectionMatch(record: *const LeaseRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.holder, filter);
}
fn csrProjectionMatch(record: *const CSRRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter) or containsIgnoreCase(record.signer, filter);
}
fn storageVersionMigrationProjectionMatch(record: *const StorageVersionMigrationRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter) or containsIgnoreCase(record.resource_version, filter);
}
fn eventProjectionMatch(record: *const EventRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or
        containsIgnoreCase(record.event_type, filter) or
        containsIgnoreCase(record.reason, filter) or
        containsIgnoreCase(record.object, filter) or
        containsIgnoreCase(record.message, filter);
}

fn resourceClaimProjectionSortKey(record: *const ResourceClaimRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.status,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}
fn deviceClassProjectionSortKey(record: *const DeviceClassRecord, column: u8) []const u8 {
    return if (column == 2) record.creation_timestamp orelse "" else record.key.name;
}
fn priorityClassProjectionSortKey(record: *const PriorityClassRecord, column: u8) []const u8 {
    return if (column == 3) record.creation_timestamp orelse "" else record.key.name;
}
fn runtimeClassProjectionSortKey(record: *const RuntimeClassRecord, column: u8) []const u8 {
    return switch (column) {
        1 => record.handler,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}
fn leaseProjectionSortKey(record: *const LeaseRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.holder,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}
fn csrProjectionSortKey(record: *const CSRRecord, column: u8) []const u8 {
    return switch (column) {
        1 => record.signer,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}
fn storageVersionMigrationProjectionSortKey(record: *const StorageVersionMigrationRecord, column: u8) []const u8 {
    return switch (column) {
        1 => record.resource_version,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}
fn eventProjectionSortKey(record: *const EventRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.last_seen_timestamp orelse "",
        2 => record.event_type,
        3 => record.reason,
        4 => record.object,
        6 => record.message,
        else => record.key.name,
    };
}

fn validatingAdmissionPolicyProjectionColumns(_: *ValidatingAdmissionPolicyProjection, record: *const ValidatingAdmissionPolicyRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}

fn validatingAdmissionPolicyBindingProjectionColumns(_: *ValidatingAdmissionPolicyBindingProjection, record: *const ValidatingAdmissionPolicyBindingRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}

fn mutatingAdmissionPolicyProjectionColumns(_: *MutatingAdmissionPolicyProjection, record: *const MutatingAdmissionPolicyRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}

fn mutatingAdmissionPolicyBindingProjectionColumns(_: *MutatingAdmissionPolicyBindingProjection, record: *const MutatingAdmissionPolicyBindingRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}

fn validatingWebhookConfigurationProjectionColumns(_: *ValidatingWebhookConfigurationProjection, record: *const ValidatingWebhookConfigurationRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}

fn mutatingWebhookConfigurationProjectionColumns(_: *MutatingWebhookConfigurationProjection, record: *const MutatingWebhookConfigurationRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}

fn validatingAdmissionPolicyProjectionMatch(record: *const ValidatingAdmissionPolicyRecord, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.name, filter) or
        containsIgnoreCase(record.extra.failure_policy, filter);
}

fn mutatingAdmissionPolicyProjectionMatch(record: *const MutatingAdmissionPolicyRecord, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.name, filter) or
        containsIgnoreCase(record.extra.failure_policy, filter);
}

fn validatingAdmissionPolicyBindingProjectionMatch(record: *const ValidatingAdmissionPolicyBindingRecord, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.name, filter) or
        containsIgnoreCase(record.extra.value, filter);
}

fn mutatingAdmissionPolicyBindingProjectionMatch(record: *const MutatingAdmissionPolicyBindingRecord, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.name, filter) or
        containsIgnoreCase(record.extra.value, filter);
}

fn validatingWebhookConfigurationProjectionMatch(record: *const ValidatingWebhookConfigurationRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter);
}

fn mutatingWebhookConfigurationProjectionMatch(record: *const MutatingWebhookConfigurationRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter);
}

fn validatingAdmissionPolicyProjectionSortKey(record: *const ValidatingAdmissionPolicyRecord, column: u8) []const u8 {
    return switch (column) {
        1 => record.extra.failure_policy,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn mutatingAdmissionPolicyProjectionSortKey(record: *const MutatingAdmissionPolicyRecord, column: u8) []const u8 {
    return switch (column) {
        1 => record.extra.failure_policy,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn validatingAdmissionPolicyBindingProjectionSortKey(record: *const ValidatingAdmissionPolicyBindingRecord, column: u8) []const u8 {
    return switch (column) {
        1 => record.extra.value,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn mutatingAdmissionPolicyBindingProjectionSortKey(record: *const MutatingAdmissionPolicyBindingRecord, column: u8) []const u8 {
    return switch (column) {
        1 => record.extra.value,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn validatingWebhookConfigurationProjectionSortKey(record: *const ValidatingWebhookConfigurationRecord, column: u8) []const u8 {
    return if (column == 2) record.creation_timestamp orelse "" else record.key.name;
}

fn mutatingWebhookConfigurationProjectionSortKey(record: *const MutatingWebhookConfigurationRecord, column: u8) []const u8 {
    return if (column == 2) record.creation_timestamp orelse "" else record.key.name;
}

fn roleProjectionColumns(_: *RoleProjection, record: *const RoleRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}

fn roleBindingProjectionColumns(_: *RoleBindingProjection, record: *const RoleBindingRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}

fn clusterRoleProjectionColumns(_: *ClusterRoleProjection, record: *const ClusterRoleRecord, allocator: std.mem.Allocator) ![2][]const u8 {
    return record.columns(allocator);
}

fn clusterRoleBindingProjectionColumns(_: *ClusterRoleBindingProjection, record: *const ClusterRoleBindingRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}

fn roleProjectionMatch(record: *const RoleRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter);
}

fn roleBindingProjectionMatch(record: *const RoleBindingRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or
        containsIgnoreCase(record.extra.kind, filter) or
        containsIgnoreCase(record.extra.name, filter);
}

fn clusterRoleProjectionMatch(record: *const ClusterRoleRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter);
}

fn clusterRoleBindingProjectionMatch(record: *const ClusterRoleBindingRecord, filter: []const u8) bool {
    return filter.len == 0 or
        containsIgnoreCase(record.key.name, filter) or
        containsIgnoreCase(record.extra.kind, filter) or
        containsIgnoreCase(record.extra.name, filter);
}

fn roleProjectionSortKey(record: *const RoleRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn roleBindingProjectionSortKey(record: *const RoleBindingRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.extra.name,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn clusterRoleProjectionSortKey(record: *const ClusterRoleRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn clusterRoleBindingProjectionSortKey(record: *const ClusterRoleBindingRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => record.extra.name,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn gatewayClassProjectionColumns(_: *GatewayClassProjection, record: *const GatewayClassRecord, allocator: std.mem.Allocator) ![3][]const u8 {
    return record.columns(allocator);
}

fn gatewayProjectionColumns(_: *GatewayProjection, record: *const GatewayRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    return record.columns(allocator);
}

fn httpRouteProjectionColumns(_: *HTTPRouteProjection, record: *const HTTPRouteRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    return record.columns(allocator);
}

fn grpcRouteProjectionColumns(_: *GRPCRouteProjection, record: *const GRPCRouteRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    return record.columns(allocator);
}

fn referenceGrantProjectionColumns(_: *ReferenceGrantProjection, record: *const ReferenceGrantRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    return record.columns(allocator);
}

fn tcpRouteProjectionColumns(_: *TCPRouteProjection, record: *const TCPRouteRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}

fn tlsRouteProjectionColumns(_: *TLSRouteProjection, record: *const TLSRouteRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    return record.columns(allocator);
}

fn udpRouteProjectionColumns(_: *UDPRouteProjection, record: *const UDPRouteRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}

fn backendTLSPolicyProjectionColumns(_: *BackendTLSPolicyProjection, record: *const BackendTLSPolicyRecord, allocator: std.mem.Allocator) ![4][]const u8 {
    return record.columns(allocator);
}

fn listenerSetProjectionColumns(_: *ListenerSetProjection, record: *const ListenerSetRecord, allocator: std.mem.Allocator) ![5][]const u8 {
    return record.columns(allocator);
}

fn gatewayClassProjectionMatch(record: *const GatewayClassRecord, filter: []const u8) bool {
    return filter.len == 0 or containsIgnoreCase(record.key.name, filter) or containsIgnoreCase(record.controller, filter);
}

fn gatewayProjectionMatch(record: *const GatewayRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.gateway_class, filter) or containsIgnoreCase(record.address, filter);
}

fn httpRouteProjectionMatch(record: *const HTTPRouteRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.parent, filter) or containsIgnoreCase(record.hostnames, filter);
}

fn grpcRouteProjectionMatch(record: *const GRPCRouteRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.parent, filter) or containsIgnoreCase(record.hostnames, filter);
}

fn referenceGrantProjectionMatch(record: *const ReferenceGrantRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.from_kind, filter) or containsIgnoreCase(record.to_kind, filter);
}

fn tcpRouteProjectionMatch(record: *const TCPRouteRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.parent, filter);
}

fn tlsRouteProjectionMatch(record: *const TLSRouteRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.parent, filter) or containsIgnoreCase(record.hostnames, filter);
}

fn udpRouteProjectionMatch(record: *const UDPRouteRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.parent, filter);
}

fn backendTLSPolicyProjectionMatch(record: *const BackendTLSPolicyRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.target, filter);
}

fn listenerSetProjectionMatch(record: *const ListenerSetRecord, filter: []const u8) bool {
    return namespacedRecordMatches(record, filter) or containsIgnoreCase(record.parent, filter);
}

fn gatewayClassProjectionSortKey(record: *const GatewayClassRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.name,
        1 => record.controller,
        2 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn gatewayProjectionSortKey(record: *const GatewayRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.gateway_class,
        3 => record.address,
        4 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn httpRouteProjectionSortKey(record: *const HTTPRouteRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.parent,
        3 => record.hostnames,
        4 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn grpcRouteProjectionSortKey(record: *const GRPCRouteRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.parent,
        3 => record.hostnames,
        4 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn referenceGrantProjectionSortKey(record: *const ReferenceGrantRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.from_kind,
        3 => record.to_kind,
        4 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn tcpRouteProjectionSortKey(record: *const TCPRouteRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.parent,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn tlsRouteProjectionSortKey(record: *const TLSRouteRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.parent,
        3 => record.hostnames,
        4 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn udpRouteProjectionSortKey(record: *const UDPRouteRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.parent,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn backendTLSPolicyProjectionSortKey(record: *const BackendTLSPolicyRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.target,
        3 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
}

fn listenerSetProjectionSortKey(record: *const ListenerSetRecord, column: u8) []const u8 {
    return switch (column) {
        0 => record.key.namespace,
        1 => record.key.name,
        2 => record.parent,
        4 => record.creation_timestamp orelse "",
        else => record.key.name,
    };
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
        if (!entry.restart_pending or entry.active != null) continue;
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

fn task14ComposedRecord(
    comptime Record: type,
    allocator: std.mem.Allocator,
    uid: []const u8,
    name: []const u8,
) !Record {
    var key = try (resource_key.ObjectKey{
        .uid = uid,
        .namespace = if (Record == NodeRecord or Record == NamespaceRecord) "" else "default",
        .name = name,
    }).clone(allocator);
    errdefer key.deinit(allocator);
    if (Record == PodRecord) return .{ .key = key };
    if (Record == ServiceRecord) {
        const service_type = try allocator.dupe(u8, "ClusterIP");
        errdefer allocator.free(service_type);
        const cluster_ip = try allocator.dupe(u8, "10.96.0.10");
        errdefer allocator.free(cluster_ip);
        const external_ip = try allocator.dupe(u8, "<none>");
        errdefer allocator.free(external_ip);
        const ports = try allocator.dupe(u8, "80/TCP");
        return .{
            .key = key,
            .service_type = service_type,
            .cluster_ip = cluster_ip,
            .external_ip = external_ip,
            .ports = ports,
        };
    }
    if (Record == NodeRecord) {
        const status = try allocator.dupe(u8, "Ready");
        errdefer allocator.free(status);
        const roles = try allocator.dupe(u8, "worker");
        errdefer allocator.free(roles);
        const node_version = try allocator.dupe(u8, "v1.33.0");
        errdefer allocator.free(node_version);
        const internal_ip = try allocator.dupe(u8, "10.0.0.10");
        return .{
            .key = key,
            .status = status,
            .roles = roles,
            .version = node_version,
            .internal_ip = internal_ip,
        };
    }
    if (Record == NamespaceRecord) {
        return .{ .key = key, .status = try allocator.dupe(u8, "Active") };
    }
    if (Record == GatewayRecord) {
        const gateway_class = try allocator.dupe(u8, "task-14");
        errdefer allocator.free(gateway_class);
        const address = try allocator.dupe(u8, "10.0.0.20");
        return .{ .key = key, .gateway_class = gateway_class, .address = address };
    }
    @compileError("unsupported Task 14 composed record");
}

fn Task14ComposedWatch(comptime Record: type) type {
    return struct {
        allocator: std.mem.Allocator,
        entered: *std.atomic.Value(usize),
        observed_rv: *std.atomic.Value(bool),

        fn source(self: *@This()) list_watch.Source(Record) {
            return .{ .context = self, .list_fn = unusedList, .watch_fn = watch };
        }

        fn unusedList(
            _: *anyopaque,
            _: list_watch.CancelToken,
            _: *anyopaque,
            _: *const fn (*anyopaque, Record) anyerror!void,
            _: *const fn (*anyopaque) anyerror!void,
        ) anyerror!list_watch.ListOutcome {
            return error.Unused;
        }

        fn watch(
            raw: *anyopaque,
            resource_version: []const u8,
            _: list_watch.CancelToken,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, *list_watch.WatchEvent(Record)) anyerror!void,
        ) anyerror!list_watch.Failure {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.observed_rv.store(std.mem.eql(u8, resource_version, "10"), .release);
            _ = self.entered.fetchAdd(1, .acq_rel);
            var event: list_watch.WatchEvent(Record) = .{
                .added = try task14ComposedRecord(
                    Record,
                    self.allocator,
                    "watch-uid",
                    "watch-resource",
                ),
            };
            defer event.deinit(self.allocator);
            try receiver(receiver_context, &event);
            return .canceled;
        }
    };
}

fn Task14IdentitySource(comptime Record: type) type {
    return struct {
        allocator: std.mem.Allocator,
        io: std.Io,
        allow_finish: ?*std.atomic.Value(bool) = null,

        fn source(self: *@This()) list_watch.Source(Record) {
            return .{ .context = self, .list_fn = list, .watch_fn = watch };
        }

        fn list(
            raw: *anyopaque,
            _: list_watch.CancelToken,
            receiver_context: *anyopaque,
            receiver: *const fn (*anyopaque, Record) anyerror!void,
            chunk_end: *const fn (*anyopaque) anyerror!void,
        ) anyerror!list_watch.ListOutcome {
            const self: *@This() = @ptrCast(@alignCast(raw));
            try receiver(receiver_context, try task14ComposedRecord(
                Record,
                self.allocator,
                if (Record == PodRecord) "pod-uid" else "family-uid",
                if (Record == PodRecord) "pod-a" else "family-a",
            ));
            if (Record == PodRecord) {
                try receiver(receiver_context, try task14ComposedRecord(
                    Record,
                    self.allocator,
                    "other-pod-uid",
                    "pod-b",
                ));
            }
            try chunk_end(receiver_context);
            return .{ .complete = try resource_key.OwnedBytes.clone(self.allocator, "14") };
        }

        fn watch(
            raw: *anyopaque,
            _: []const u8,
            cancel: list_watch.CancelToken,
            _: *anyopaque,
            _: *const fn (*anyopaque, *list_watch.WatchEvent(Record)) anyerror!void,
        ) anyerror!list_watch.Failure {
            const self: *@This() = @ptrCast(@alignCast(raw));
            if (self.allow_finish) |allowed| {
                // Park the way a production held watch does: yield to the runtime on
                // a 1ms cadence instead of spinning, so holding this task open cannot
                // starve the metrics feed and family tasks sharing the same io.
                while (!allowed.load(.acquire)) {
                    if (cancel.isCanceled()) return .canceled;
                    self.io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake) catch return .canceled;
                }
            }
            return .canceled;
        }
    };
}

pub fn runTask14ComposedOrderingGate() !void {
    const allocator = std.testing.allocator;
    const io = runtime.io();
    var app = try App.init(allocator, .{});
    defer app.deinit();

    const client = try allocator.create(klient.K8sClient);
    var client_owned = true;
    errdefer if (client_owned) allocator.destroy(client);
    client.* = try klient.K8sClient.init(allocator, io, .{
        .server = "http://127.0.0.1",
        .namespace = "default",
    });
    errdefer if (client_owned) client.deinit();
    const active_session = try @import("k8s/ActiveContextSession.zig").ActiveContextSession.adopt(
        allocator,
        io,
        1,
        .{
            .context_name = "task-14",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
        .{
            .shared_event = app.shared_event,
            .client = client,
            .cluster_name = "local",
            .user_name = "test",
            .readiness_verified = true,
        },
    );
    client_owned = false;
    _ = try app.active_session_slot.commit(active_session);
    app.k8s_service.connected = true;

    const PodFamily = resource_subscription.ResourceSubscription(
        klient.Pod,
        PodRecord,
        struct {
            fn convert(record_allocator: std.mem.Allocator, pod: klient.Pod) anyerror!PodRecord {
                return PodRecord.fromPod(record_allocator, pod, .{});
            }
        }.convert,
    );
    var pod_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{ .body = resource_subscription.task14TypeShapedListBody(PodRecord) }});
    defer pod_fake.deinit();
    var service_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{ .body = resource_subscription.task14TypeShapedListBody(ServiceRecord) }});
    defer service_fake.deinit();
    var node_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{ .body = resource_subscription.task14TypeShapedListBody(NodeRecord) }});
    defer node_fake.deinit();
    var gateway_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{ .body = resource_subscription.task14TypeShapedListBody(GatewayRecord) }});
    defer gateway_fake.deinit();

    var service_index: usize = undefined;
    var gateway_index: usize = undefined;
    for (app.resource_families.registry.itemsConst(), 0..) |entry, index| {
        if (std.mem.eql(u8, entry.name, "services")) service_index = index;
        if (std.mem.eql(u8, entry.name, "gateways")) gateway_index = index;
    }
    const service_entry = app.resource_families.registry.entryAt(service_index).?;
    const gateway_entry = app.resource_families.registry.entryAt(gateway_index).?;
    const service_projection: *@import("k8s/ResourceProjection.zig").ResourceProjection(ServiceRecord) =
        @ptrCast(@alignCast(service_entry.projection));
    const gateway_projection: *@import("k8s/ResourceProjection.zig").ResourceProjection(GatewayRecord) =
        @ptrCast(@alignCast(gateway_entry.projection));

    var entered: std.atomic.Value(usize) = .init(0);
    var rv_seen = [_]std.atomic.Value(bool){ .init(false), .init(false), .init(false), .init(false) };
    var pod_watch = Task14ComposedWatch(PodRecord){ .allocator = allocator, .entered = &entered, .observed_rv = &rv_seen[0] };
    var service_watch = Task14ComposedWatch(ServiceRecord){ .allocator = allocator, .entered = &entered, .observed_rv = &rv_seen[1] };
    var node_watch = Task14ComposedWatch(NodeRecord){ .allocator = allocator, .entered = &entered, .observed_rv = &rv_seen[2] };
    var gateway_watch = Task14ComposedWatch(GatewayRecord){ .allocator = allocator, .entered = &entered, .observed_rv = &rv_seen[3] };

    var pod_spec = try PodFamily.ownedTaskSpec(allocator, .{
        .context_name = "task-14",
        .namespace = "default",
        .projection = app.pod_projection,
        .transport_override = pod_fake.transport(),
        .watch_override = pod_watch.source(),
    });
    defer pod_spec.deinit(allocator);
    const pod_key = try app.data_plane.startSubscription(1, &pod_spec);
    app.active_pod_subscription = pod_key;
    var service_spec = try ServiceSubscription.ownedTaskSpec(allocator, .{
        .context_name = "task-14",
        .namespace = "default",
        .projection = service_projection,
        .transport_override = service_fake.transport(),
        .watch_override = service_watch.source(),
    });
    defer service_spec.deinit(allocator);
    const service_key = try app.data_plane.startSubscription(1, &service_spec);
    service_entry.markStarted(service_key);
    var node_spec = try NodeSubscription.ownedTaskSpec(allocator, .{
        .context_name = "task-14",
        .projection = app.node_projection,
        .transport_override = node_fake.transport(),
        .watch_override = node_watch.source(),
    });
    defer node_spec.deinit(allocator);
    const node_key = try app.data_plane.startSubscription(1, &node_spec);
    app.active_node_subscription = node_key;
    var gateway_spec = try GatewaySubscription.ownedTaskSpec(allocator, .{
        .context_name = "task-14",
        .namespace = "default",
        .projection = gateway_projection,
        .transport_override = gateway_fake.transport(),
        .watch_override = gateway_watch.source(),
    });
    defer gateway_spec.deinit(allocator);
    const gateway_key = try app.data_plane.startSubscription(1, &gateway_spec);
    gateway_entry.markStarted(gateway_key);

    var launch_attempts: usize = 0;
    while (app.lifecycle_supervisor.metrics.max_live < 4 and launch_attempts < 10_000) : (launch_attempts += 1) {
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    try std.testing.expect(app.lifecycle_supervisor.metrics.max_live >= 4);
    const identities = [_]lifecycle.SubscriptionKey{ pod_key, service_key, node_key, gateway_key };
    var stages = [_]u8{0} ** identities.len;
    var forced_failure = false;
    var failed_sequence: u64 = 0;
    var router = resource_key.UiRouter{
        .context = @ptrCast(&app),
        .targetFn = App.appEnvelopeTarget,
        .lifecycleFn = App.appObserveLifecycle,
    };
    var attempts: usize = 0;
    while (attempts < 30_000) : (attempts += 1) {
        var popped = app.change_queue.popForRetry() orelse {
            if (app.lifecycle_supervisor.metrics.reaped >= 4) break;
            try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
            continue;
        };
        errdefer if (popped.active) popped.destroy(allocator);
        const envelope = &popped.envelope;
        const identity_index: ?usize = for (identities, 0..) |key, index| {
            if (key.generation == envelope.generation and
                key.subscription_id == envelope.subscription_id) break index;
        } else null;
        if (identity_index == 1 and envelope.has_initial_changes and !forced_failure) {
            const before = service_projection.count();
            var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 0 });
            try std.testing.expectError(error.OutOfMemory, envelope.apply(&router, failing.allocator()));
            try std.testing.expectEqual(before, service_projection.count());
            failed_sequence = popped.sequence;
            try app.change_queue.retryPopped(&popped);
            forced_failure = true;
            continue;
        }
        if (forced_failure and failed_sequence != 0 and identity_index == 1 and envelope.has_initial_changes) {
            try std.testing.expectEqual(failed_sequence, popped.sequence);
            failed_sequence = 0;
        }
        try envelope.apply(&router, allocator);
        popped.finishConsumed();
        if (identity_index) |index| {
            if (envelope.sync_kind) |kind| switch (kind) {
                .list_started => {
                    try std.testing.expectEqual(@as(u8, 0), stages[index]);
                    stages[index] = 1;
                },
                .list_complete => {
                    try std.testing.expectEqual(@as(u8, 1), stages[index]);
                    stages[index] = 2;
                },
                .watch_connected => {
                    try std.testing.expectEqual(@as(u8, 2), stages[index]);
                    stages[index] = 3;
                },
                else => {},
            } else if (envelope.change_count > 0) {
                if (envelope.has_initial_changes) {
                    try std.testing.expectEqual(@as(u8, 1), stages[index]);
                } else {
                    try std.testing.expectEqual(@as(u8, 3), stages[index]);
                    stages[index] = 4;
                }
            }
            if (index == 0) try app.pods_view.syncPodProjection();
            if (index == 1) _ = try app.resource_families.registry.sync(.{
                .generation = service_key.generation,
                .subscription_id = service_key.subscription_id,
            });
            if (index == 2) try app.nodes_view.syncProjection();
            if (index == 3) _ = try app.resource_families.registry.sync(.{
                .generation = gateway_key.generation,
                .subscription_id = gateway_key.subscription_id,
            });
        }
    }
    try std.testing.expect(forced_failure);
    try std.testing.expectEqual(@as(u64, 0), failed_sequence);
    try std.testing.expect(app.lifecycle_supervisor.metrics.max_live >= 4);
    for (stages) |stage| try std.testing.expectEqual(@as(u8, 4), stage);
    for (&rv_seen) |*seen| try std.testing.expect(seen.load(.acquire));
    try std.testing.expect(app.pods_view.table.items.items.len > 0);
    try std.testing.expect(app.nodes_view.table.items.items.len > 0);
    try std.testing.expect(service_projection.count() > 0);
    try std.testing.expect(gateway_projection.count() > 0);
}

pub fn runTask14IdentityGate() !void {
    const allocator = std.testing.allocator;
    const io = runtime.io();
    var app = try App.init(allocator, .{});

    const client = try allocator.create(klient.K8sClient);
    var client_owned = true;
    errdefer if (client_owned) allocator.destroy(client);
    client.* = try klient.K8sClient.init(allocator, io, .{
        .server = "http://127.0.0.1",
        .namespace = "default",
    });
    errdefer if (client_owned) client.deinit();
    const active_session = try @import("k8s/ActiveContextSession.zig").ActiveContextSession.adopt(
        allocator,
        io,
        1,
        .{
            .context_name = "task-14",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
        .{
            .shared_event = app.shared_event,
            .client = client,
            .cluster_name = "local",
            .user_name = "test",
            .readiness_verified = true,
        },
    );
    client_owned = false;
    _ = try app.active_session_slot.commit(active_session);
    app.k8s_service.connected = true;

    var service_index: usize = undefined;
    for (app.resource_families.registry.itemsConst(), 0..) |entry, index| {
        if (std.mem.eql(u8, entry.name, "services")) service_index = index;
    }
    const service_entry = app.resource_families.registry.entryAt(service_index).?;
    const service_projection: *ServiceProjection = @ptrCast(@alignCast(service_entry.projection));
    const PodFamily = resource_subscription.ResourceSubscription(
        klient.Pod,
        PodRecord,
        struct {
            fn convert(record_allocator: std.mem.Allocator, pod: klient.Pod) anyerror!PodRecord {
                return PodRecord.fromPod(record_allocator, pod, .{});
            }
        }.convert,
    );
    var pod_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{
        .body = resource_subscription.task14TypeShapedListBody(PodRecord),
    }});
    defer pod_fake.deinit();
    var service_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{
        .body = resource_subscription.task14TypeShapedListBody(ServiceRecord),
    }});
    defer service_fake.deinit();
    var node_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{
        .body = resource_subscription.task14TypeShapedListBody(NodeRecord),
    }});
    defer node_fake.deinit();
    var metrics_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{
        .body =
        \\{"items":[{"metadata":{"namespace":"default","name":"alpha-resource"},"containers":[{"usage":{"cpu":"321m","memory":"4Ki"}}]}]}
        ,
    }});
    defer metrics_fake.deinit();
    defer app.deinit();
    var allow_pod_finish: std.atomic.Value(bool) = .init(false);
    defer allow_pod_finish.store(true, .release);
    var pod_source = Task14IdentitySource(PodRecord){
        .allocator = allocator,
        .io = io,
        .allow_finish = &allow_pod_finish,
    };
    var service_source = Task14IdentitySource(ServiceRecord){ .allocator = allocator, .io = io };
    var node_source = Task14IdentitySource(NodeRecord){ .allocator = allocator, .io = io };
    var allow_metrics: std.atomic.Value(bool) = .init(false);
    defer allow_metrics.store(true, .release);

    var pod_spec = try PodFamily.ownedTaskSpec(allocator, .{
        .namespace = "default",
        .context_name = "task-14",
        .projection = app.pod_projection,
        .transport_override = pod_fake.transport(),
        .watch_override = pod_source.source(),
    });
    defer pod_spec.deinit(allocator);
    const pod = try app.data_plane.startSubscription(1, &pod_spec);
    app.active_pod_subscription = pod;
    var metrics_spec = try metrics_feed.ownedTaskSpec(allocator, .{
        .namespace = "default",
        .projection = app.pod_projection,
        .transport_override = metrics_fake.transport(),
        .poll_gate = &allow_metrics,
        .poll_interval_ns = std.time.ns_per_hour,
    });
    defer metrics_spec.deinit(allocator);
    const metrics = try app.data_plane.startSubscription(1, &metrics_spec);
    app.active_metrics_subscription = metrics;
    var service_spec = try ServiceSubscription.ownedTaskSpec(allocator, .{
        .context_name = "task-14",
        .namespace = "default",
        .projection = service_projection,
        .transport_override = service_fake.transport(),
        .watch_override = service_source.source(),
    });
    defer service_spec.deinit(allocator);
    const service = try app.data_plane.startSubscription(1, &service_spec);
    service_entry.markStarted(service);
    var node_spec = try NodeSubscription.ownedTaskSpec(allocator, .{
        .context_name = "task-14",
        .projection = app.node_projection,
        .transport_override = node_fake.transport(),
        .watch_override = node_source.source(),
    });
    defer node_spec.deinit(allocator);
    const node = try app.data_plane.startSubscription(1, &node_spec);
    app.active_node_subscription = node;

    const service_identity = resource_key.ResourceIdentity{
        .generation = service.generation,
        .subscription_id = service.subscription_id,
    };
    const wrong_identity = resource_key.ResourceIdentity{
        .generation = service.generation + 1,
        .subscription_id = service.subscription_id,
    };
    try std.testing.expect(app.resource_families.registry.complete(
        wrong_identity,
        .{ .subscription_stopped = .{ .key = service, .detail = null } },
    ) == null);
    try std.testing.expectEqual(@as(?lifecycle.SubscriptionKey, pod), app.active_pod_subscription);
    try std.testing.expectEqual(@as(?lifecycle.SubscriptionKey, metrics), app.active_metrics_subscription);
    try std.testing.expectEqual(@as(?lifecycle.SubscriptionKey, node), app.active_node_subscription);
    try std.testing.expect(app.resource_families.registry.contains(service_identity));

    var router = resource_key.UiRouter{
        .context = @ptrCast(&app),
        .targetFn = App.appEnvelopeTarget,
        .lifecycleFn = App.appObserveLifecycle,
    };
    const StalePayload = struct {
        destroyed: *std.atomic.Value(usize),
        fn preflight(
            _: *@This(),
            _: *resource_key.UiRouter,
            _: std.mem.Allocator,
        ) !resource_key.ApplyPlan {
            return .{};
        }
        fn commit(_: *@This(), _: *resource_key.UiRouter, _: *resource_key.ApplyPlan) void {}
        fn deinit(self: *@This(), _: std.mem.Allocator) void {
            _ = self.destroyed.fetchAdd(1, .acq_rel);
        }
    };
    const stale_handler = resource_key.PayloadHandler(StalePayload){
        .preflight = StalePayload.preflight,
        .commit = StalePayload.commit,
        .deinit = StalePayload.deinit,
    };
    var stale_destroyed: std.atomic.Value(usize) = .init(0);
    const stale_payload = try allocator.create(StalePayload);
    stale_payload.* = .{ .destroyed = &stale_destroyed };
    var stale = try resource_key.erasePayload(
        StalePayload,
        allocator,
        .{ .resource = wrong_identity },
        stale_payload,
        &stale_handler,
        wrong_identity.generation,
        wrong_identity.subscription_id,
        1,
        @sizeOf(StalePayload),
        null,
    );
    try std.testing.expect(!app.acceptsActiveEnvelope(stale));
    stale.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), stale_destroyed.load(.acquire));

    // The pod and metrics tasks are held open until every piece of evidence this
    // gate exists to observe has been collected: the metrics envelope applied, the
    // family reaching watch_connected (its terminal sync stage, not the earlier
    // list_complete), the pod rows materialised in the view, and the metrics values
    // rendered onto exactly the pod they belong to. Releasing on a partial set let
    // the pod task finish -- which cancels the metrics feed -- while later envelopes
    // were still being drained, so the isolation assertions raced teardown.
    var saw_family_list_complete = false;
    var saw_family_watch_connected = false;
    var metrics_applied = false;
    var released = false;
    var attempts: usize = 0;
    while (attempts < 30_000) : (attempts += 1) {
        var envelope = app.change_queue.pop() orelse {
            if (app.lifecycle_supervisor.metrics.reaped >= 4) break;
            try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
            continue;
        };
        if (envelope.target == .resource) {
            const original_target = envelope.target;
            const identity = original_target.resource;
            envelope.target = .{ .resource = .{
                .generation = identity.generation + 1,
                .subscription_id = identity.subscription_id,
            } };
            try std.testing.expect(!app.acceptsActiveEnvelope(envelope));
            envelope.target = .{ .resource = .{
                .generation = identity.generation,
                .subscription_id = identity.subscription_id + 1000,
            } };
            try std.testing.expect(!app.acceptsActiveEnvelope(envelope));
            envelope.target = original_target;
        }
        const target = envelope.target;
        const sync_kind = envelope.sync_kind;
        const initial_changes = envelope.has_initial_changes;
        try envelope.apply(&router, allocator);
        if (target == .resource) {
            const identity = target.resource;
            if (matchesIdentity(pod, identity)) {
                try app.pods_view.syncPodProjection();
                if (initial_changes) allow_metrics.store(true, .release);
            } else if (matchesIdentity(metrics, identity)) {
                try app.pods_view.syncPodProjection();
                metrics_applied = true;
                // A single polled envelope is the whole point of the feed here, so
                // shut the gate again: any later poll must stay parked until the
                // cancellation that follows the pod task finishing.
                allow_metrics.store(false, .release);
            } else if (matchesIdentity(node, identity)) {
                try app.nodes_view.syncProjection();
            } else if (app.resource_families.registry.contains(identity)) {
                _ = try app.resource_families.registry.sync(identity);
                if (sync_kind) |kind| switch (kind) {
                    .list_complete => saw_family_list_complete = true,
                    .watch_connected => {
                        try std.testing.expect(saw_family_list_complete);
                        saw_family_watch_connected = true;
                    },
                    else => {},
                };
            }
            // Family traffic must never disturb the pod-side identities. This only
            // holds while both tasks are still held open; once the gate is released
            // the pod task finishes and cancelling the metrics feed is correct, so
            // the live slots are no longer a meaningful invariant.
            try std.testing.expect(!app.pod_metrics_started);
            if (!released) {
                try std.testing.expectEqual(
                    @as(?lifecycle.SubscriptionKey, pod),
                    app.active_pod_subscription,
                );
                try std.testing.expectEqual(
                    @as(?lifecycle.SubscriptionKey, metrics),
                    app.active_metrics_subscription,
                );
            }
        }
        if (!released and metrics_applied and saw_family_watch_connected and
            task14IdentityMetricsDisplayed(&app))
        {
            released = true;
            allow_pod_finish.store(true, .release);
        }
    }
    try std.testing.expect(metrics_applied);
    try std.testing.expect(saw_family_list_complete);
    try std.testing.expect(saw_family_watch_connected);
    try std.testing.expect(released);
    try std.testing.expectEqual(@as(usize, 2), app.pod_projection.count());
    try std.testing.expectEqual(@as(u64, 321), app.pod_projection.metricsFor("stable-uid").?.cpu_milli);
    try std.testing.expectEqual(@as(u64, 4096), app.pod_projection.metricsFor("stable-uid").?.mem_bytes);
    try std.testing.expectEqual(@as(u64, 0), app.pod_projection.metricsRevision("other-uid").?);
    try std.testing.expect(task14IdentityMetricsDisplayed(&app));
    try std.testing.expect(service_projection.count() > 0);
    try std.testing.expect(app.node_projection.count() > 0);
}

/// True once the polled metrics have landed on `stable-uid` alone and the pods view
/// renders them: the second pod must still show `n/a`, which is what proves the
/// metrics envelope was routed by exact identity rather than sprayed across rows.
fn task14IdentityMetricsDisplayed(app: *const App) bool {
    const metrics = app.pod_projection.metricsFor("stable-uid") orelse return false;
    if (metrics.revision == 0) return false;
    if (metrics.cpu_milli != 321 or metrics.mem_bytes != 4096) return false;
    if ((app.pod_projection.metricsRevision("other-uid") orelse return false) != 0) return false;
    var saw_stable = false;
    var saw_other = false;
    for (app.pods_view.table.items.items) |row| {
        if (std.mem.eql(u8, row.uid, "stable-uid")) {
            if (!std.mem.eql(u8, row.columns[5], "321m")) return false;
            if (!std.mem.eql(u8, row.columns[6], "4Ki")) return false;
            saw_stable = true;
        } else if (std.mem.eql(u8, row.uid, "other-uid")) {
            if (!std.mem.eql(u8, row.columns[5], "n/a")) return false;
            if (!std.mem.eql(u8, row.columns[6], "n/a")) return false;
            saw_other = true;
        }
    }
    return saw_stable and saw_other;
}

fn task14PrepareLocalSession(
    _: *anyopaque,
    allocator: std.mem.Allocator,
    io: std.Io,
    shared_event: *std.Io.Event,
    generation: resource_key.Generation,
    spec: ContextSpec,
) anyerror!*ActiveContextSession {
    const client = try allocator.create(klient.K8sClient);
    var client_owned = true;
    errdefer if (client_owned) allocator.destroy(client);
    client.* = try klient.K8sClient.init(allocator, io, .{
        .server = "http://127.0.0.1",
        .namespace = spec.default_namespace,
    });
    errdefer if (client_owned) client.deinit();
    const session = try ActiveContextSession.adopt(
        allocator,
        io,
        generation,
        spec,
        .{
            .shared_event = shared_event,
            .client = client,
            .cluster_name = "local",
            .user_name = "test",
            .readiness_verified = true,
        },
    );
    client_owned = false;
    return session;
}

fn task14LocalSessionFactory() SessionFactory {
    return .{
        .context = @ptrFromInt(1),
        .prepare_fn = task14PrepareLocalSession,
    };
}

fn task14Pump(app: *App, io: std.Io) !void {
    app.drainChangeQueue();
    try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
}

fn task14FamilyIndex(app: *const App, name: []const u8) !usize {
    for (app.resource_families.registry.itemsConst(), 0..) |entry, index| {
        if (std.mem.eql(u8, entry.name, name)) return index;
    }
    return error.MissingFamily;
}

fn task14HoldAuthBackend(cancel_flag: *std.atomic.Value(bool)) authorization_request.Backend {
    const Adapter = struct {
        fn connected(_: *anyopaque) bool {
            return true;
        }

        fn check(
            ctx: *anyopaque,
            _: []const u8,
            _: []const u8,
            _: []const u8,
            _: []const u8,
        ) !K8sService.AccessCheckResult {
            const flag: *std.atomic.Value(bool) = @ptrCast(@alignCast(ctx));
            while (!flag.load(.acquire)) {
                runtime.io().sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake) catch break;
            }
            return .{ .allowed = false, .conditional = false, .condition_count = 0 };
        }

        fn conditional(_: *anyopaque) !bool {
            return false;
        }

        fn rbac(_: *anyopaque) ![]K8sService.PolicyInfo {
            return &.{};
        }

        fn cedarAvailable(_: *anyopaque) !bool {
            return false;
        }

        fn cedar(_: *anyopaque) ![]K8sService.PolicyInfo {
            return &.{};
        }

        fn conditions(
            _: *anyopaque,
            _: []const u8,
            _: []const u8,
            _: []const u8,
        ) ![]K8sService.ConditionInfo {
            return &.{};
        }
    };
    return .{
        .context = cancel_flag,
        .isConnectedFn = Adapter.connected,
        .checkAccessFn = Adapter.check,
        .detectConditionalFn = Adapter.conditional,
        .listRbacFn = Adapter.rbac,
        .detectCedarFn = Adapter.cedarAvailable,
        .listCedarFn = Adapter.cedar,
        .conditionsFn = Adapter.conditions,
    };
}

pub fn runTask14ContextSwitchGate() !void {
    const allocator = std.testing.allocator;
    const io = runtime.io();
    var lists = @import("k8s/FakeTransport.zig").PathListTransport.init(
        allocator,
        resource_subscription.task14ListBodyForPath,
    );
    defer lists.deinit();
    var metrics_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
    });
    defer metrics_fake.deinit();
    var app = try App.init(allocator, .{});
    defer app.deinit();

    app.k8s_service.session_factory = task14LocalSessionFactory();
    const gen1 = try task14PrepareLocalSession(
        undefined,
        allocator,
        io,
        app.shared_event,
        1,
        .{
            .context_name = "gen-1",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
    );
    _ = try app.active_session_slot.commit(gen1);
    app.k8s_service.connected = true;

    app.task14 = .{
        .transport = lists.transport(),
        .hold_watch = true,
        .metrics_transport = metrics_fake.transport(),
        .metrics_poll_interval_ns = metrics_feed.max_poll_interval_ns,
    };

    try app.startPodSubscription();
    var row_attempts: usize = 0;
    while (app.pod_projection.count() == 0 and row_attempts < 30_000) : (row_attempts += 1) {
        try task14Pump(&app, io);
    }
    try std.testing.expectEqual(@as(usize, 2), app.pod_projection.count());
    try std.testing.expect(app.pod_projection.selectUid("stable-uid"));

    try app.startMetricsFeed();
    try app.startNodeSubscription();
    try app.startNamespaceSubscription();
    for (0..app.resource_families.registry.items().len) |index| {
        try app.startResourceFamilySubscription(index);
    }

    var launch_attempts: usize = 0;
    while ((app.lifecycle_supervisor.liveChildren() != 58 or
        app.active_metrics_subscription == null) and launch_attempts < 30_000) : (launch_attempts += 1)
    {
        if (app.active_metrics_subscription == null) app.startMetricsFeed() catch {};
        try task14Pump(&app, io);
    }
    try std.testing.expectEqual(@as(usize, 58), app.lifecycle_supervisor.liveChildren());
    try std.testing.expect(app.active_metrics_subscription != null);
    try std.testing.expectEqual(@as(usize, 58), gen1.leaseCount());
    try std.testing.expect(app.pod_projection.selectUid("stable-uid"));

    var old_family_keys: [54]lifecycle.SubscriptionKey = undefined;
    try std.testing.expectEqual(old_family_keys.len, app.resource_families.registry.items().len);
    for (app.resource_families.registry.itemsConst(), 0..) |entry, index| {
        old_family_keys[index] = entry.active orelse return error.MissingFamilyKey;
    }
    const old_pod = app.active_pod_subscription orelse return error.MissingPodKey;
    const old_metrics = app.active_metrics_subscription orelse return error.MissingMetricsKey;
    const old_node = app.active_node_subscription orelse return error.MissingNodeKey;
    const old_namespace = app.active_namespace_subscription orelse return error.MissingNamespaceKey;

    var queued_payload_destroyed: std.atomic.Value(usize) = .init(0);
    var queued_gen1 = app.change_queue.popForRetry() orelse return error.MissingQueuedGen1Envelope;
    errdefer if (queued_gen1.active) queued_gen1.destroy(allocator);
    const queued_identity = queued_gen1.envelope.target.resource;
    try std.testing.expect(queued_gen1.envelope.payload != null);
    try std.testing.expect(app.data_plane.acceptsEnvelope(queued_gen1.envelope));
    try std.testing.expect(app.acceptsActiveEnvelope(queued_gen1.envelope));
    queued_gen1.envelope.destroy_counter = &queued_payload_destroyed;
    try app.change_queue.retryPopped(&queued_gen1);

    const injected_failure_index: usize = 17;
    app.task14.fail_family_index = injected_failure_index;
    try app.beginContextSwitch("gen-2");
    try std.testing.expectEqual(@as(usize, 1), queued_payload_destroyed.load(.acquire));
    try std.testing.expect(!app.data_plane.acceptsEnvelope(.{
        .generation = queued_identity.generation,
        .subscription_id = queued_identity.subscription_id,
        .target = .{ .resource = queued_identity },
    }));

    var reap_attempts: usize = 0;
    while (app.pending_context_switch != null and reap_attempts < 30_000) : (reap_attempts += 1) {
        while (app.change_queue.hasPending()) app.drainChangeQueue();
        try task14Pump(&app, io);
    }
    try std.testing.expect(app.pending_context_switch == null);
    try std.testing.expectEqual(@as(usize, 0), gen1.leaseCount());
    try std.testing.expect(app.task14_context_install_after_drain);

    const session_view = app.active_session_slot.view();
    try std.testing.expectEqual(@as(resource_key.Generation, 2), session_view.generation);
    const new_pod = app.active_pod_subscription orelse return error.MissingGen2Pod;
    try std.testing.expectEqual(@as(resource_key.Generation, 2), new_pod.generation);
    try std.testing.expect(new_pod.subscription_id != old_pod.subscription_id);
    try std.testing.expect(app.active_node_subscription.?.subscription_id != old_node.subscription_id);
    try std.testing.expect(app.active_namespace_subscription.?.subscription_id != old_namespace.subscription_id);

    var later_entry_started = false;
    for (app.resource_families.registry.itemsConst(), 0..) |entry, index| {
        if (index == injected_failure_index) {
            try std.testing.expect(entry.restart_pending);
            try std.testing.expect(entry.active == null);
            continue;
        }
        const key = entry.active orelse return error.MissingGen2Family;
        try std.testing.expectEqual(@as(resource_key.Generation, 2), key.generation);
        try std.testing.expect(key.subscription_id != old_family_keys[index].subscription_id);
        try std.testing.expect(!entry.restart_pending);
        if (index > injected_failure_index) later_entry_started = true;
    }
    try std.testing.expect(later_entry_started);

    var gen2_attempts: usize = 0;
    while ((app.active_metrics_subscription == null or
        app.active_metrics_subscription.?.generation != 2) and gen2_attempts < 30_000) : (gen2_attempts += 1)
    {
        if (app.active_metrics_subscription == null) app.startMetricsFeed() catch {};
        try task14Pump(&app, io);
    }
    const new_metrics = app.active_metrics_subscription orelse return error.MissingGen2Metrics;
    try std.testing.expectEqual(@as(resource_key.Generation, 2), new_metrics.generation);
    try std.testing.expect(new_metrics.subscription_id != old_metrics.subscription_id);
    var uid_attempts: usize = 0;
    while (!app.pod_projection.selectUid("stable-uid") and uid_attempts < 30_000) : (uid_attempts += 1) {
        try task14Pump(&app, io);
    }
    try std.testing.expect(app.pod_projection.selectUid("stable-uid"));

    while (app.change_queue.hasPending()) app.drainChangeQueue();
    try std.testing.expectEqual(@as(usize, 1), queued_payload_destroyed.load(.acquire));
    var late_gen1 = resource_key.Envelope{
        .generation = queued_identity.generation,
        .subscription_id = queued_identity.subscription_id,
        .target = .{ .resource = queued_identity },
    };
    try std.testing.expect(!app.acceptsActiveEnvelope(late_gen1));
    late_gen1.deinit(allocator);

    startPendingFamilyEntries(
        &app.resource_families.registry,
        @ptrCast(&app),
        struct {
            fn start(raw: *anyopaque, index: usize) anyerror!void {
                const gate_app: *App = @ptrCast(@alignCast(raw));
                try gate_app.startResourceFamilySubscription(index);
            }
        }.start,
        struct {
            fn failed(_: *anyopaque, _: *family_registry.Entry, _: anyerror) void {}
        }.failed,
    );
    const retried = app.resource_families.registry.entryAt(injected_failure_index).?;
    try std.testing.expect(!retried.restart_pending);
    try std.testing.expectEqual(
        @as(resource_key.Generation, 2),
        retried.active.?.generation,
    );
    try std.testing.expect(retried.active.?.subscription_id != old_family_keys[injected_failure_index].subscription_id);
}

pub fn runTask14AllocationOrdinalsGate() !void {
    const allocator = std.testing.allocator;
    const io = runtime.io();
    var lists = @import("k8s/FakeTransport.zig").PathListTransport.init(
        allocator,
        resource_subscription.task14ListBodyForPath,
    );
    defer lists.deinit();
    var app = try App.init(allocator, .{});
    defer app.deinit();

    const session = try task14PrepareLocalSession(
        undefined,
        allocator,
        io,
        app.shared_event,
        1,
        .{
            .context_name = "allocation",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
    );
    _ = try app.active_session_slot.commit(session);
    app.k8s_service.connected = true;

    var destroyed: std.atomic.Value(usize) = .init(0);
    app.task14 = .{
        .transport = lists.transport(),
        .hold_watch = true,
        .deinit_counter = &destroyed,
    };
    const service_index = try task14FamilyIndex(&app, "services");
    const gateway_index = try task14FamilyIndex(&app, "gateways");
    const Representative = enum { pod, service, node, gateway };
    const Matrix = struct {
        fn rowCount(gate_app: *const App, kind: Representative) usize {
            return switch (kind) {
                .pod => gate_app.pod_projection.count(),
                .service => gate_app.resource_families.service_projection.count(),
                .node => gate_app.node_projection.count(),
                .gateway => gate_app.resource_families.gateway_projection.count(),
            };
        }

        fn tableCount(gate_app: *const App, kind: Representative) usize {
            return switch (kind) {
                .pod => gate_app.pods_view.table.items.items.len,
                .service => gate_app.services_view.table.items.items.len,
                .node => gate_app.nodes_view.table.items.items.len,
                .gateway => gate_app.gateways_view.table.items.items.len,
            };
        }

        fn start(gate_app: *App, kind: Representative, service: usize, gateway: usize) !void {
            switch (kind) {
                .pod => {
                    try gate_app.startPodSubscription();
                    gate_app.pod_metrics_started = true;
                },
                .service => try gate_app.startResourceFamilySubscription(service),
                .node => try gate_app.startNodeSubscription(),
                .gateway => try gate_app.startResourceFamilySubscription(gateway),
            }
        }

        fn cancel(gate_app: *App, kind: Representative, service: usize, gateway: usize) void {
            switch (kind) {
                .pod => if (gate_app.active_pod_subscription) |key| {
                    _ = gate_app.data_plane.cancelSubscription(key);
                    gate_app.active_pod_subscription = null;
                },
                .service => if (gate_app.resource_families.registry.entryAt(service).?.active) |key| {
                    _ = gate_app.data_plane.cancelSubscription(key);
                    gate_app.resource_families.registry.entryAt(service).?.markStopped();
                },
                .node => if (gate_app.active_node_subscription) |key| {
                    _ = gate_app.data_plane.cancelSubscription(key);
                    gate_app.active_node_subscription = null;
                },
                .gateway => if (gate_app.resource_families.registry.entryAt(gateway).?.active) |key| {
                    _ = gate_app.data_plane.cancelSubscription(key);
                    gate_app.resource_families.registry.entryAt(gateway).?.markStopped();
                },
            }
        }

        fn reap(gate_app: *App, gate_io: std.Io) !void {
            var attempts: usize = 0;
            while ((gate_app.lifecycle_supervisor.liveChildren() != 0 or
                gate_app.data_plane.trackedCount() != 0) and attempts < 30_000) : (attempts += 1)
            {
                try task14Pump(gate_app, gate_io);
            }
            if (gate_app.lifecycle_supervisor.liveChildren() != 0 or
                gate_app.data_plane.trackedCount() != 0)
            {
                return error.AllocationChildDidNotReap;
            }
            while (gate_app.change_queue.hasPending()) gate_app.drainChangeQueue();
        }
    };

    inline for (.{ Representative.pod, .service, .node, .gateway }) |kind| {
        const prior_rows = Matrix.rowCount(&app, kind);
        const prior_table_rows = Matrix.tableCount(&app, kind);
        var ordinal: usize = 0;
        var reached_success = false;
        while (ordinal < 128) : (ordinal += 1) {
            var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = ordinal });
            app.task14.convert_allocator = failing.allocator();
            const destroyed_before = destroyed.load(.acquire);
            try Matrix.start(&app, kind, service_index, gateway_index);
            var attempts: usize = 0;
            while (Matrix.rowCount(&app, kind) == prior_rows and attempts < 500) : (attempts += 1) {
                try task14Pump(&app, io);
            }
            const success = Matrix.rowCount(&app, kind) > prior_rows;
            Matrix.cancel(&app, kind, service_index, gateway_index);
            try Matrix.reap(&app, io);
            try std.testing.expectEqual(destroyed_before + 1, destroyed.load(.acquire));
            if (failing.has_induced_failure) {
                try std.testing.expect(!success);
                try std.testing.expectEqual(prior_rows, Matrix.rowCount(&app, kind));
                try std.testing.expectEqual(prior_table_rows, Matrix.tableCount(&app, kind));
                continue;
            }
            try std.testing.expect(success);
            reached_success = true;
            break;
        }
        if (!reached_success) return error.ConversionAllocationNeverSucceeded;
    }
    app.task14.convert_allocator = null;
    try @import("k8s/PodSubscription.zig").runTask14PodEmitAllocationOrdinalsGate();
    try resource_subscription.runTask14ResourceEmitAllocationOrdinalsGate();

    try app.startPodSubscription();
    app.pod_metrics_started = true;

    var launch_attempts: usize = 0;
    while (!app.change_queue.hasPending() and launch_attempts < 30_000) : (launch_attempts += 1) {
        try task14Pump(&app, io);
    }
    try std.testing.expect(app.change_queue.hasPending());

    const preflight_revision = app.pod_projection.appliedRevision();
    var first_popped = app.change_queue.popForRetry() orelse return error.MissingPreflightEnvelope;
    errdefer if (first_popped.active) first_popped.destroy(allocator);
    const preflight_sequence = first_popped.sequence;
    const preflight_payload = first_popped.envelope.payload orelse return error.MissingPreflightPayload;
    try app.change_queue.retryPopped(&first_popped);
    app.task14.drain_batch_limit = 1;
    var preflight_ordinal: usize = 0;
    var preflight_reached_success = false;
    while (preflight_ordinal < 128) : (preflight_ordinal += 1) {
        var failing = std.testing.FailingAllocator.init(allocator, .{
            .fail_index = preflight_ordinal,
        });
        app.task14.drain_allocator = failing.allocator();
        app.drainChangeQueue();
        var next = app.change_queue.popForRetry() orelse {
            try std.testing.expect(!failing.has_induced_failure);
            preflight_reached_success = true;
            break;
        };
        errdefer if (next.active) next.destroy(allocator);
        const same_envelope = next.sequence == preflight_sequence;
        if (same_envelope) {
            try std.testing.expect(failing.has_induced_failure);
            try std.testing.expectEqual(preflight_payload, next.envelope.payload.?);
            try std.testing.expectEqual(preflight_revision, app.pod_projection.appliedRevision());
            try app.change_queue.retryPopped(&next);
            continue;
        }
        try std.testing.expect(!failing.has_induced_failure);
        try std.testing.expect(next.sequence > preflight_sequence);
        try app.change_queue.retryPopped(&next);
        preflight_reached_success = true;
        break;
    }
    if (!preflight_reached_success) return error.PreflightAllocationNeverSucceeded;
    app.task14.drain_allocator = null;
    app.task14.drain_batch_limit = null;

    if (app.resource_families.registry.entryAt(service_index).?.active == null)
        try app.startResourceFamilySubscription(service_index);
    var row_attempts: usize = 0;
    while (app.services_view.table.items.items.len == 0 and row_attempts < 30_000) : (row_attempts += 1) {
        try task14Pump(&app, io);
    }
    try app.services_view.syncProjection();
    const old_service_rows = app.services_view.table.items.items.len;
    try std.testing.expect(old_service_rows > 0);
    const saved_table_allocator = app.services_view.table.allocator;
    var view_ordinal: usize = 0;
    var view_saw_failure = false;
    while (view_ordinal < 128) : (view_ordinal += 1) {
        var view_failing = std.testing.FailingAllocator.init(allocator, .{
            .fail_index = view_ordinal,
        });
        app.services_view.table.allocator = view_failing.allocator();
        const result = app.services_view.syncProjection();
        app.services_view.table.allocator = saved_table_allocator;
        if (result) |_| {
            break;
        } else |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            view_saw_failure = true;
            try std.testing.expectEqual(old_service_rows, app.services_view.table.items.items.len);
        }
    } else return error.ViewAllocationNeverSucceeded;
    try std.testing.expect(view_saw_failure);
    try std.testing.expectEqual(old_service_rows, app.services_view.table.items.items.len);

    const service_entry = app.resource_families.registry.entryAt(service_index).?;
    service_entry.restart_pending = false;
    _ = app.data_plane.cancelSubscription(service_entry.active.?);
    var restart_attempts: usize = 0;
    while (service_entry.active != null and restart_attempts < 30_000) : (restart_attempts += 1) {
        try task14Pump(&app, io);
    }
    try std.testing.expect(service_entry.active == null);
    service_entry.restart_pending = true;
    var restart_ordinal: usize = 0;
    var restart_saw_failure = false;
    while (restart_ordinal < 128) : (restart_ordinal += 1) {
        var restart_failing = std.testing.FailingAllocator.init(allocator, .{
            .fail_index = restart_ordinal,
        });
        app.task14.spec_allocator = restart_failing.allocator();
        app.startResourceFamilySubscription(service_index) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            restart_saw_failure = true;
            try std.testing.expect(service_entry.restart_pending);
            try std.testing.expect(service_entry.active == null);
            continue;
        };
        markFamilyStartOutcome(service_entry, true);
        break;
    } else return error.RestartAllocationNeverSucceeded;
    app.task14.spec_allocator = null;
    try std.testing.expect(restart_saw_failure);
    try std.testing.expect(!service_entry.restart_pending);
    try std.testing.expect(service_entry.active != null);

    const destroyed_before_shutdown = destroyed.load(.acquire);
    app.finishLifecycle();
    try std.testing.expectEqual(@as(usize, 1), app.lifecycle_root_await_count);
    try std.testing.expect(destroyed.load(.acquire) > destroyed_before_shutdown);
    try std.testing.expectEqual(@as(usize, 0), app.lifecycle_supervisor.liveChildren());
    try std.testing.expect(!app.change_queue.hasPending());
    app.finishLifecycle();
    try std.testing.expectEqual(@as(usize, 1), app.lifecycle_root_await_count);
}

pub fn runTask14ShutdownGate() !void {
    const allocator = std.testing.allocator;
    const io = runtime.io();
    var lists = @import("k8s/FakeTransport.zig").PathListTransport.init(
        allocator,
        resource_subscription.task14ListBodyForPath,
    );
    defer lists.deinit();
    var metrics_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
        .{ .body = "{\"items\":[]}" },
    });
    defer metrics_fake.deinit();
    var retry_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{
        .{ .status = .internal_server_error, .body = "{}" },
    });
    defer retry_fake.deinit();
    var header_hold = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{}});
    header_hold.block_until_cancel = true;
    defer header_hold.deinit();
    var traffic_hold = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{}});
    traffic_hold.block_until_cancel = true;
    defer traffic_hold.deinit();
    var detail_hold = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{}});
    detail_hold.block_until_cancel = true;
    defer detail_hold.deinit();
    var yaml_hold = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{}});
    yaml_hold.block_until_cancel = true;
    defer yaml_hold.deinit();
    var logs_hold = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{}});
    logs_hold.block_until_cancel = true;
    defer logs_hold.deinit();
    var app = try App.init(allocator, .{});
    defer app.deinit();

    const active_session = try task14PrepareLocalSession(
        undefined,
        allocator,
        io,
        app.shared_event,
        1,
        .{
            .context_name = "task-14",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
    );
    _ = try app.active_session_slot.commit(active_session);
    app.k8s_service.connected = true;

    var destroyed: std.atomic.Value(usize) = .init(0);
    var retry_wait_entered: std.atomic.Value(bool) = .init(false);
    var cancel_flag: std.atomic.Value(bool) = .init(false);
    header_hold.cancel_flag = &cancel_flag;
    traffic_hold.cancel_flag = &cancel_flag;
    detail_hold.cancel_flag = &cancel_flag;
    yaml_hold.cancel_flag = &cancel_flag;
    logs_hold.cancel_flag = &cancel_flag;
    const retry_family_index: usize = 3;
    app.task14 = .{
        .transport = lists.transport(),
        .hold_watch = true,
        .deinit_counter = &destroyed,
        .retry_wait_entered = &retry_wait_entered,
        .retry_family_index = retry_family_index,
        .retry_transport = retry_fake.transport(),
        .metrics_transport = metrics_fake.transport(),
        .metrics_poll_interval_ns = metrics_feed.max_poll_interval_ns,
        .cancel_flag = &cancel_flag,
    };

    try app.startResourceFamilySubscription(retry_family_index);
    var retry_attempts: usize = 0;
    while (!retry_wait_entered.load(.acquire) and retry_attempts < 30_000) : (retry_attempts += 1) {
        try task14Pump(&app, io);
    }
    try std.testing.expect(retry_wait_entered.load(.acquire));

    try app.startPodSubscription();
    try app.startNodeSubscription();
    try app.startNamespaceSubscription();
    for (0..app.resource_families.registry.items().len) |index| {
        if (index == retry_family_index) continue;
        try app.startResourceFamilySubscription(index);
    }
    try app.startMetricsFeed();

    var header_spec = try header_metrics_request.ownedTaskSpec(allocator, .{
        .transport_override = header_hold.transport(),
    });
    _ = try app.ancillary_requests.startRequest(.header_metrics, 1, &header_spec);
    var traffic_spec = try traffic_request.ownedTaskSpec(allocator, .{
        .workload = "web",
        .namespace = "default",
        .transport_override = traffic_hold.transport(),
    });
    _ = try app.ancillary_requests.startRequest(.traffic, 1, &traffic_spec);
    var detail_spec = try detail_request.ownedTaskSpec(allocator, .{
        .serial = 1,
        .kind = .describe,
        .resource_type = .pods,
        .name = "alpha-resource",
        .namespace = "default",
        .transport_override = detail_hold.transport(),
    });
    _ = try app.ancillary_requests.startRequest(.detail, 1, &detail_spec);
    var yaml_spec = try detail_request.ownedTaskSpec(allocator, .{
        .serial = 2,
        .kind = .yaml,
        .resource_type = .pods,
        .name = "alpha-resource",
        .namespace = "default",
        .transport_override = yaml_hold.transport(),
    });
    _ = try app.ancillary_requests.startRequest(.yaml, 1, &yaml_spec);
    var logs_spec = try logs_request.ownedTaskSpec(allocator, .{
        .serial = 1,
        .pod_name = "alpha-resource",
        .namespace = "default",
        .previous = false,
        .transport_override = logs_hold.transport(),
    });
    _ = try app.ancillary_requests.startRequest(.logs, 1, &logs_spec);
    var auth_spec = try authorization_request.ownedTaskSpec(allocator, .{
        .serial = 1,
        .tab = .access_review,
        .service = app.k8s_service,
        .namespace = "default",
        .backend_override = task14HoldAuthBackend(&cancel_flag),
    });
    _ = try app.ancillary_requests.startRequest(.authorization, 1, &auth_spec);

    var wait_attempts: usize = 0;
    while ((!retry_wait_entered.load(.acquire) or
        app.lifecycle_supervisor.deliveryReadyCount() == 0 or
        app.lifecycle_supervisor.liveChildren() < 64) and wait_attempts < 30_000) : (wait_attempts += 1)
    {
        try task14Pump(&app, io);
    }
    try std.testing.expect(retry_wait_entered.load(.acquire));
    try std.testing.expect(app.lifecycle_supervisor.deliveryReadyCount() > 0);
    try std.testing.expectEqual(@as(usize, 64), app.lifecycle_supervisor.liveChildren());

    for (0..resource_key.Limits.default.ordinary_control_batches) |_| {
        const payload = try allocator.create(u8);
        payload.* = 1;
        var envelope = resource_key.erasePayload(
            u8,
            allocator,
            .lifecycle,
            payload,
            &resource_key.test_noop_u8_handler,
            0,
            0,
            0,
            1,
            null,
        ) catch |err| {
            allocator.destroy(payload);
            return err;
        };
        app.change_queue.tryPushControl(envelope) catch |err| {
            envelope.deinit(allocator);
            if (err == error.Full) break;
            return err;
        };
    }

    app.finishLifecycle();
    try std.testing.expectEqual(@as(usize, 64), app.task14_cancel_intents_before_await);
    try std.testing.expectEqual(@as(usize, 1), app.lifecycle_root_await_count);
    try std.testing.expect(app.task14_views_alive_after_await);
    try std.testing.expectEqual(@as(usize, 58), destroyed.load(.acquire));
    try std.testing.expectEqual(@as(usize, 64), app.lifecycle_supervisor.taskSpecsDestroyed());
    try std.testing.expectEqual(@as(usize, 0), app.lifecycle_supervisor.liveChildren());
    try std.testing.expectEqual(
        app.lifecycle_supervisor.metrics.launched,
        app.lifecycle_supervisor.metrics.reaped,
    );
    try std.testing.expectEqual(@as(usize, 0), active_session.leaseCount());
    try std.testing.expect(!app.change_queue.hasPending());
    app.finishLifecycle();
    try std.testing.expectEqual(@as(usize, 1), app.lifecycle_root_await_count);
}

pub fn runTask14RollbackIsolationGate() !void {
    const allocator = std.testing.allocator;
    const io = runtime.io();
    var lists = @import("k8s/FakeTransport.zig").PathListTransport.init(
        allocator,
        resource_subscription.task14ListBodyForPath,
    );
    defer lists.deinit();
    var app = try App.init(allocator, .{});
    defer app.deinit();

    const active_session = try task14PrepareLocalSession(
        undefined,
        allocator,
        io,
        app.shared_event,
        1,
        .{
            .context_name = "rollback",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
    );
    _ = try app.active_session_slot.commit(active_session);
    app.k8s_service.connected = true;
    app.task14 = .{ .transport = lists.transport(), .hold_watch = true };

    const service_index = try task14FamilyIndex(&app, "services");
    const gateway_index = try task14FamilyIndex(&app, "gateways");
    const storage_index = try task14FamilyIndex(&app, "persistentvolumes");
    try app.startResourceFamilySubscription(service_index);
    try app.startResourceFamilySubscription(gateway_index);

    var attempts: usize = 0;
    while (app.lifecycle_supervisor.liveChildren() != 2 and attempts < 30_000) : (attempts += 1) {
        try task14Pump(&app, io);
    }
    try std.testing.expectEqual(@as(usize, 2), app.lifecycle_supervisor.liveChildren());
    const service_key = app.resource_families.registry.entryAt(service_index).?.active.?;
    const gateway_key = app.resource_families.registry.entryAt(gateway_index).?.active.?;

    // Source gate rollback removed: storage always uses data-plane. Verify that
    // starting a storage subscription does not disturb existing service/gateway.
    const storage_entry = app.resource_families.registry.entryAt(storage_index).?;
    _ = storage_entry.takeRequest();
    try storage_entry.refresh();
    try std.testing.expectEqual(family_registry.Request.start, storage_entry.takeRequest());
    try app.startResourceFamilySubscription(storage_index);
    try std.testing.expectEqual(service_key, app.resource_families.registry.entryAt(service_index).?.active.?);
    try std.testing.expectEqual(gateway_key, app.resource_families.registry.entryAt(gateway_index).?.active.?);
    try std.testing.expectEqual(@as(usize, 3), app.data_plane.activeCount());

    const service_entry = app.resource_families.registry.entryAt(service_index).?;
    try service_entry.refresh();
    try app.serviceResourceFamilyRequests();
    attempts = 0;
    while (attempts < 30_000) : (attempts += 1) {
        try task14Pump(&app, io);
        const active = service_entry.active orelse continue;
        if (active.subscription_id != service_key.subscription_id) break;
    }
    const restarted_service_key = service_entry.active orelse return error.ServiceRestartMissing;
    try std.testing.expect(restarted_service_key.subscription_id != service_key.subscription_id);
    try std.testing.expectEqual(gateway_key, app.resource_families.registry.entryAt(gateway_index).?.active.?);
    try std.testing.expect(storage_entry.active != null);
    try std.testing.expectEqual(@as(usize, 3), app.data_plane.activeCount());

    app.finishLifecycle();
    try std.testing.expectEqual(@as(usize, 0), app.lifecycle_supervisor.liveChildren());
    try std.testing.expectEqual(@as(usize, 0), active_session.leaseCount());
    try std.testing.expect(!app.change_queue.hasPending());
}

pub fn runTask14PersistentApplyShutdownGate() !void {
    const Payload = struct {
        destroyed: *usize,
    };
    const Handler = struct {
        fn preflight(
            _: *Payload,
            _: *resource_key.UiRouter,
            _: std.mem.Allocator,
        ) anyerror!resource_key.ApplyPlan {
            return error.PersistentApplyFailure;
        }
        fn commit(
            _: *Payload,
            _: *resource_key.UiRouter,
            _: *resource_key.ApplyPlan,
        ) void {
            unreachable;
        }
        fn deinit(payload: *Payload, _: std.mem.Allocator) void {
            payload.destroyed.* += 1;
        }
        const handler = resource_key.PayloadHandler(Payload){
            .preflight = preflight,
            .commit = commit,
            .deinit = deinit,
        };
    };

    const allocator = std.testing.allocator;
    var app = try App.init(allocator, .{});
    defer app.deinit();
    var destroyed: usize = 0;
    const payload = try allocator.create(Payload);
    payload.* = .{ .destroyed = &destroyed };
    var envelope = resource_key.erasePayload(
        Payload,
        allocator,
        .lifecycle,
        payload,
        &Handler.handler,
        0,
        0,
        0,
        @sizeOf(Payload),
        null,
    ) catch |err| {
        allocator.destroy(payload);
        return err;
    };
    app.change_queue.tryPushControl(envelope) catch |err| {
        envelope.deinit(allocator);
        return err;
    };
    app.drainChangeQueue();
    try std.testing.expect(app.change_queue.hasPending());
    try std.testing.expectEqual(@as(usize, 0), destroyed);

    app.finishLifecycle();
    try std.testing.expectEqual(@as(usize, 1), destroyed);
    try std.testing.expect(!app.change_queue.hasPending());
    try std.testing.expectEqual(@as(usize, 1), app.lifecycle_root_await_count);
}

pub fn runTask14ShutdownDrainAllocationOrdinalsGate() !void {
    const Payload = struct {
        committed: *bool,
        destroyed: *usize,
    };
    const Scratch = struct {
        bytes: []u8,
    };
    const Handler = struct {
        fn preflight(
            _: *Payload,
            _: *resource_key.UiRouter,
            allocator: std.mem.Allocator,
        ) anyerror!resource_key.ApplyPlan {
            const scratch = try allocator.create(Scratch);
            errdefer allocator.destroy(scratch);
            scratch.* = .{ .bytes = try allocator.alloc(u8, 32) };
            return .{
                .scratch = scratch,
                .scratch_alignment = .of(Scratch),
                .deinitFn = destroyPlan,
            };
        }
        fn destroyPlan(
            raw: ?*anyopaque,
            _: std.mem.Alignment,
            allocator: std.mem.Allocator,
        ) void {
            const scratch: *Scratch = @ptrCast(@alignCast(raw.?));
            allocator.free(scratch.bytes);
            allocator.destroy(scratch);
        }
        fn commit(
            payload: *Payload,
            _: *resource_key.UiRouter,
            _: *resource_key.ApplyPlan,
        ) void {
            payload.committed.* = true;
        }
        fn deinit(payload: *Payload, _: std.mem.Allocator) void {
            payload.destroyed.* += 1;
        }
        const handler = resource_key.PayloadHandler(Payload){
            .preflight = preflight,
            .commit = commit,
            .deinit = deinit,
        };
    };
    const Exercise = struct {
        fn run(failing_allocator: std.mem.Allocator, backing: std.mem.Allocator) !void {
            var app = try App.init(backing, .{});
            defer app.deinit();
            var committed = false;
            var destroyed: usize = 0;
            const payload = try failing_allocator.create(Payload);
            payload.* = .{ .committed = &committed, .destroyed = &destroyed };
            var envelope = resource_key.erasePayload(
                Payload,
                failing_allocator,
                .lifecycle,
                payload,
                &Handler.handler,
                0,
                0,
                0,
                @sizeOf(Payload),
                null,
            ) catch |err| {
                failing_allocator.destroy(payload);
                return err;
            };
            app.change_queue.tryPushControl(envelope) catch |err| {
                envelope.deinit(failing_allocator);
                return err;
            };
            app.task14.drain_allocator = failing_allocator;
            app.finishLifecycle();
            try std.testing.expectEqual(@as(usize, 1), destroyed);
            try std.testing.expect(!app.change_queue.hasPending());
            if (!committed) return error.OutOfMemory;
        }
    };
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        Exercise.run,
        .{std.testing.allocator},
    );
}

pub fn runTask14MalformedProductionGate() !void {
    const allocator = std.testing.allocator;
    const io = runtime.io();
    var fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &.{.{
        .body =
        \\{"apiVersion":"v1","kind":"ServiceList","metadata":{"resourceVersion":"10"},"items":[{"metadata":{"namespace":"default","name":"valid","uid":"valid-uid"},"spec":{"type":"ClusterIP","clusterIP":"10.0.0.1"}},{"metadata":{"namespace":"default","name":"broken"},"spec":{"type":"ClusterIP","clusterIP":"10.0.0.2"}}]}
        ,
    }});
    defer fake.deinit();
    var app = try App.init(allocator, .{});
    defer app.deinit();
    const active_session = try task14PrepareLocalSession(
        undefined,
        allocator,
        io,
        app.shared_event,
        1,
        .{
            .context_name = "malformed",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
    );
    _ = try app.active_session_slot.commit(active_session);
    app.k8s_service.connected = true;
    app.task14 = .{ .transport = fake.transport() };
    const service_index = try task14FamilyIndex(&app, "services");
    try app.startResourceFamilySubscription(service_index);

    var attempts: usize = 0;
    while (app.resource_families.registry.entryAt(service_index).?.active != null and
        attempts < 30_000) : (attempts += 1)
    {
        try task14Pump(&app, io);
    }
    try std.testing.expect(app.resource_families.registry.entryAt(service_index).?.active == null);
    try std.testing.expectEqual(@as(usize, 0), app.resource_families.service_projection.count());
    try std.testing.expectEqual(@as(usize, 0), app.services_view.table.items.items.len);
    try std.testing.expectEqual(@as(usize, 1), fake.requests.items.len);
    try std.testing.expectEqual(@as(usize, 1), app.lifecycle_supervisor.metrics.launched);
    try std.testing.expectEqual(@as(usize, 1), app.lifecycle_supervisor.metrics.reaped);
    try std.testing.expect(!app.change_queue.hasPending());
    app.finishLifecycle();
}

pub fn runTask14MalformedWatchProductionGate() !void {
    const allocator = std.testing.allocator;
    const io = runtime.io();
    const empty_list = "{\"metadata\":{\"resourceVersion\":\"10\"},\"items\":[]}";
    var service_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(
        allocator,
        &.{.{ .body = empty_list }},
    );
    defer service_fake.deinit();
    var node_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(
        allocator,
        &.{.{ .body = empty_list }},
    );
    defer node_fake.deinit();
    var gateway_fake = @import("k8s/FakeTransport.zig").FakeTransport.init(
        allocator,
        &.{.{ .body = empty_list }},
    );
    defer gateway_fake.deinit();
    var app = try App.init(allocator, .{});
    defer app.deinit();
    const active_session = try task14PrepareLocalSession(
        undefined,
        allocator,
        io,
        app.shared_event,
        1,
        .{
            .context_name = "malformed-watch",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
    );
    _ = try app.active_session_slot.commit(active_session);
    app.k8s_service.connected = true;

    var service_script = ServiceSubscription.Task14MalformedWatch{ .allocator = allocator };
    var service_destroyed: std.atomic.Value(usize) = .init(0);
    var service_retry: std.atomic.Value(bool) = .init(false);
    var service_spec = try ServiceSubscription.ownedTaskSpec(allocator, .{
        .context_name = "malformed-watch",
        .namespace = "default",
        .projection = &app.resource_families.service_projection,
        .deinit_counter = &service_destroyed,
        .retry_wait_entered = &service_retry,
        .transport_override = service_fake.transport(),
        .watch_override = service_script.source(),
    });
    const service_key = try app.data_plane.startSubscription(1, &service_spec);
    const service_index = try task14FamilyIndex(&app, "services");
    app.resource_families.registry.entryAt(service_index).?.markStarted(service_key);

    var attempts: usize = 0;
    while (app.resource_families.registry.entryAt(service_index).?.active != null and
        attempts < 30_000) : (attempts += 1)
    {
        try task14Pump(&app, io);
    }
    try std.testing.expect(app.resource_families.registry.entryAt(service_index).?.active == null);
    try std.testing.expectEqual(@as(usize, 0), app.resource_families.service_projection.count());
    try std.testing.expectEqual(@as(usize, 0), app.services_view.table.items.items.len);
    try std.testing.expectEqual(@as(usize, 1), service_script.watch_calls);
    try std.testing.expect(!service_retry.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), service_destroyed.load(.acquire));

    var node_script = NodeSubscription.Task14MalformedWatch{ .allocator = allocator };
    var node_destroyed: std.atomic.Value(usize) = .init(0);
    var node_retry: std.atomic.Value(bool) = .init(false);
    var node_spec = try NodeSubscription.ownedTaskSpec(allocator, .{
        .context_name = "malformed-watch",
        .projection = app.node_projection,
        .deinit_counter = &node_destroyed,
        .retry_wait_entered = &node_retry,
        .transport_override = node_fake.transport(),
        .watch_override = node_script.source(),
    });
    app.active_node_subscription = try app.data_plane.startSubscription(1, &node_spec);
    attempts = 0;
    while (app.active_node_subscription != null and attempts < 30_000) : (attempts += 1) {
        try task14Pump(&app, io);
    }
    try std.testing.expect(app.active_node_subscription == null);
    try std.testing.expectEqual(@as(usize, 0), app.node_projection.count());
    try std.testing.expectEqual(@as(usize, 0), app.nodes_view.table.items.items.len);
    try std.testing.expectEqual(@as(usize, 1), node_script.watch_calls);
    try std.testing.expect(!node_retry.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), node_destroyed.load(.acquire));

    var gateway_script = GatewaySubscription.Task14MalformedWatch{ .allocator = allocator };
    var gateway_destroyed: std.atomic.Value(usize) = .init(0);
    var gateway_retry: std.atomic.Value(bool) = .init(false);
    var gateway_spec = try GatewaySubscription.ownedTaskSpec(allocator, .{
        .context_name = "malformed-watch",
        .namespace = "default",
        .projection = &app.resource_families.gateway_projection,
        .deinit_counter = &gateway_destroyed,
        .retry_wait_entered = &gateway_retry,
        .transport_override = gateway_fake.transport(),
        .watch_override = gateway_script.source(),
    });
    const gateway_key = try app.data_plane.startSubscription(1, &gateway_spec);
    const gateway_index = try task14FamilyIndex(&app, "gateways");
    app.resource_families.registry.entryAt(gateway_index).?.markStarted(gateway_key);
    attempts = 0;
    while (app.resource_families.registry.entryAt(gateway_index).?.active != null and
        attempts < 30_000) : (attempts += 1)
    {
        try task14Pump(&app, io);
    }
    try std.testing.expect(app.resource_families.registry.entryAt(gateway_index).?.active == null);
    try std.testing.expectEqual(@as(usize, 0), app.resource_families.gateway_projection.count());
    try std.testing.expectEqual(@as(usize, 0), app.gateways_view.table.items.items.len);
    try std.testing.expectEqual(@as(usize, 1), gateway_script.watch_calls);
    try std.testing.expect(!gateway_retry.load(.acquire));
    try std.testing.expectEqual(@as(usize, 1), gateway_destroyed.load(.acquire));

    try std.testing.expectEqual(@as(usize, 1), service_fake.requests.items.len);
    try std.testing.expectEqual(@as(usize, 1), node_fake.requests.items.len);
    try std.testing.expectEqual(@as(usize, 1), gateway_fake.requests.items.len);
    try std.testing.expectEqual(@as(usize, 3), app.lifecycle_supervisor.metrics.launched);
    try std.testing.expectEqual(
        app.lifecycle_supervisor.metrics.launched,
        app.lifecycle_supervisor.metrics.reaped,
    );
    try std.testing.expectEqual(@as(usize, 0), app.data_plane.trackedCount());
    try std.testing.expect(!app.change_queue.hasPending());
    app.finishLifecycle();
    try std.testing.expectEqual(@as(usize, 0), app.lifecycle_supervisor.liveChildren());
    try std.testing.expectEqual(@as(usize, 0), active_session.leaseCount());
}

pub fn runTask14HeaderPeriodicGate() !void {
    const allocator = std.testing.allocator;
    const io = runtime.io();
    const scripts = [_]@import("k8s/FakeTransport.zig").ResponseScript{
        .{ .body = "{\"items\":[{\"usage\":{\"cpu\":\"1\",\"memory\":\"2Gi\"}}]}" },
        .{ .body = "{\"items\":[{\"status\":{\"capacity\":{\"cpu\":\"4\",\"memory\":\"8Gi\"}}}]}" },
        .{ .body = "{\"items\":[{\"usage\":{\"cpu\":\"2\",\"memory\":\"4Gi\"}}]}" },
        .{ .body = "{\"items\":[{\"status\":{\"capacity\":{\"cpu\":\"4\",\"memory\":\"8Gi\"}}}]}" },
    };
    var fake = @import("k8s/FakeTransport.zig").FakeTransport.init(allocator, &scripts);
    defer fake.deinit();
    var app = try App.init(allocator, .{});
    defer app.deinit();

    const session = try task14PrepareLocalSession(
        undefined,
        allocator,
        io,
        app.shared_event,
        1,
        .{
            .context_name = "header",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
    );
    _ = try app.active_session_slot.commit(session);
    app.k8s_service.connected = true;
    app.pod_first_paint_emitted = true;

    app.task14.header_transport = fake.transport();
    app.last_header_metrics_ns = 0;
    app.maybeRefreshHeaderMetrics();

    var first_id: ?resource_key.SubscriptionId = null;
    var attempts: usize = 0;
    while (attempts < 30_000) : (attempts += 1) {
        if (app.active_header_metrics_request) |key| first_id = key.subscription_id;
        try task14Pump(&app, io);
        if (first_id != null and app.active_header_metrics_request == null) break;
    }
    const first = first_id orelse return error.MissingFirstHeaderRequest;
    const first_cpu = app.header.cpu_usage;
    try std.testing.expect(first_cpu > 0);

    app.last_header_metrics_ns = 1;
    app.maybeRefreshHeaderMetrics();
    var second_id: ?resource_key.SubscriptionId = null;
    attempts = 0;
    while (attempts < 30_000) : (attempts += 1) {
        if (app.active_header_metrics_request) |key| second_id = key.subscription_id;
        try task14Pump(&app, io);
        if (second_id != null and app.active_header_metrics_request == null) break;
    }
    const second = second_id orelse return error.MissingSecondHeaderRequest;
    try std.testing.expect(second != first);
    try std.testing.expect(app.header.cpu_usage != first_cpu);
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
    var entries = [_]family_registry.Entry{ undefined, undefined };
    for (&entries, 0..) |*entry, index| {
        entry.name = if (index == 0) "first" else "second";
        entry.active = null;
        entry.restart_pending = true;
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
        "gatewayclasses",
        "gateways",
        "httproutes",
        "grpcroutes",
        "referencegrants",
        "tcproutes",
        "tlsroutes",
        "udproutes",
        "backendtlspolicies",
        "listenersets",
        "roles",
        "rolebindings",
        "clusterroles",
        "clusterrolebindings",
        "validatingadmissionpolicies",
        "validatingadmissionpolicybindings",
        "mutatingadmissionpolicies",
        "mutatingadmissionpolicybindings",
        "validatingwebhookconfigurations",
        "mutatingwebhookconfigurations",
        "resourceclaims",
        "deviceclasses",
        "priorityclasses",
        "runtimeclasses",
        "leases",
        "certificatesigningrequests",
        "storageversionmigrations",
        "events",
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

test "gateway core and extension views preserve scope and request exact restarts" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    inline for (.{
        app.gateways_view,
        app.httproutes_view,
        app.grpcroutes_view,
        app.referencegrants_view,
        app.tcproutes_view,
        app.tlsroutes_view,
        app.udproutes_view,
        app.backendtlspolicies_view,
        app.listenersets_view,
    }) |view| {
        try std.testing.expect(@TypeOf(view.*).view_config.is_namespaced);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .{ .char = '0' });
        try std.testing.expect(view.table.show_all_namespaces);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
    try std.testing.expect(!GatewayClassesView.view_config.is_namespaced);
    app.gatewayclasses_view.markSubscriptionStarted();
    _ = try GatewayClassesView.handleKey(app.gatewayclasses_view, .ctrl_r);
    try std.testing.expectEqual(.restart, app.gatewayclasses_view.takeSubscriptionRequest());
}

test "RBAC views preserve scope and request exact restarts" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    inline for (.{ app.roles_view, app.rolebindings_view }) |view| {
        try std.testing.expect(@TypeOf(view.*).view_config.is_namespaced);
        try std.testing.expect(!view.table.show_all_namespaces);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .{ .char = '0' });
        try std.testing.expect(view.table.show_all_namespaces);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
    inline for (.{ app.clusterroles_view, app.clusterrolebindings_view }) |view| {
        try std.testing.expect(!@TypeOf(view.*).view_config.is_namespaced);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
}

test "admission views preserve cluster scope and request exact restarts" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    inline for (.{
        app.validatingadmissionpolicies_view,
        app.validatingadmissionpolicybindings_view,
        app.mutatingadmissionpolicies_view,
        app.mutatingadmissionpolicybindings_view,
        app.validatingwebhookconfigurations_view,
        app.mutatingwebhookconfigurations_view,
    }) |view| {
        try std.testing.expect(!@TypeOf(view.*).view_config.is_namespaced);
        try std.testing.expect(!view.table.show_all_namespaces);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
}

test "DRA and platform views preserve scope and request exact restarts" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();
    inline for (.{ app.resourceclaims_view, app.leases_view, app.events_view }) |view| {
        try std.testing.expect(@TypeOf(view.*).view_config.is_namespaced);
        view.markSubscriptionStarted();
        _ = try @TypeOf(view.*).handleKey(view, .ctrl_r);
        try std.testing.expectEqual(.restart, view.takeSubscriptionRequest());
    }
    try std.testing.expect(app.events_view.table.show_all_namespaces);
    try std.testing.expectEqual(@as(u8, 4), EventsView.view_config.name_column);
    inline for (.{
        app.deviceclasses_view,
        app.priorityclasses_view,
        app.runtimeclasses_view,
        app.certificatesigningrequests_view,
        app.storageversionmigrations_view,
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

    inline for (.{ @as(usize, 26), @as(usize, 31) }, 0..) |entry_index, offset| {
        const gateway_entry = app.resource_families.registry.entryAt(entry_index).?;
        const gateway_identity = resource_key.ResourceIdentity{
            .generation = 8,
            .subscription_id = @intCast(9 + offset),
        };
        gateway_entry.markStarted(.{
            .generation = gateway_identity.generation,
            .subscription_id = gateway_identity.subscription_id,
        });
        defer gateway_entry.markStopped();
        try std.testing.expect(app.resource_families.registry.contains(gateway_identity));
        try std.testing.expect(!matchesIdentity(pod, gateway_identity));
        try std.testing.expectEqual(ResourceDrainEffects{}, decideResourceDrainEffects(
            .{ .resource = gateway_identity },
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

    const rbac_entry = app.resource_families.registry.entryAt(36).?;
    const rbac_identity = resource_key.ResourceIdentity{
        .generation = 8,
        .subscription_id = 11,
    };
    rbac_entry.markStarted(.{
        .generation = rbac_identity.generation,
        .subscription_id = rbac_identity.subscription_id,
    });
    defer rbac_entry.markStopped();
    try std.testing.expect(app.resource_families.registry.contains(rbac_identity));
    try std.testing.expect(!matchesIdentity(pod, rbac_identity));
    try std.testing.expectEqual(ResourceDrainEffects{}, decideResourceDrainEffects(
        .{ .resource = rbac_identity },
        pod,
        .{ .generation = 8, .subscription_id = 4 },
        node,
        namespace,
        .list_complete,
        true,
        2,
        false,
    ));

    const admission_entry = app.resource_families.registry.entryAt(40).?;
    const admission_identity = resource_key.ResourceIdentity{
        .generation = 8,
        .subscription_id = 12,
    };
    admission_entry.markStarted(.{
        .generation = admission_identity.generation,
        .subscription_id = admission_identity.subscription_id,
    });
    defer admission_entry.markStopped();
    try std.testing.expect(app.resource_families.registry.contains(admission_identity));
    try std.testing.expect(!matchesIdentity(pod, admission_identity));
    try std.testing.expectEqual(ResourceDrainEffects{}, decideResourceDrainEffects(
        .{ .resource = admission_identity },
        pod,
        .{ .generation = 8, .subscription_id = 4 },
        node,
        namespace,
        .list_complete,
        true,
        2,
        false,
    ));

    inline for (.{ @as(usize, 46), @as(usize, 48) }, 0..) |entry_index, offset| {
        const family_entry = app.resource_families.registry.entryAt(entry_index).?;
        const family_identity = resource_key.ResourceIdentity{
            .generation = 8,
            .subscription_id = @intCast(13 + offset),
        };
        family_entry.markStarted(.{
            .generation = family_identity.generation,
            .subscription_id = family_identity.subscription_id,
        });
        defer family_entry.markStopped();
        try std.testing.expect(app.resource_families.registry.contains(family_identity));
        try std.testing.expect(!matchesIdentity(pod, family_identity));
        try std.testing.expectEqual(ResourceDrainEffects{}, decideResourceDrainEffects(
            .{ .resource = family_identity },
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

fn task15TerminalMessage(completion: lifecycle.LifecycleCompletion) ?[]const u8 {
    const detail = switch (completion) {
        .subscription_stopped => |stopped| stopped.detail orelse return null,
        else => return null,
    };
    return switch (detail.code) {
        .unauthorized => "Unauthorized: credentials were rejected",
        .forbidden => "Forbidden: access denied for this resource",
        .absent => "Unavailable: API or CRD is not installed",
        .malformed_event, .decode => "Terminal watch error: malformed server event",
        .throttled => "Retry budget exhausted after throttling",
        .server => "Retry budget exhausted after server errors",
        .transport => "Retry budget exhausted after transport errors",
        .expired => "Resource version expired",
        .limit => "Terminal response limit exceeded",
        .canceled => return null,
    };
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

test "poll timeout cannot restart resource subscriptions" {
    var app = try App.init(std.testing.allocator, .{});
    defer app.deinit();

    _ = app.pods_view.takeSubscriptionRequest();
    _ = app.nodes_view.takeSubscriptionRequest();
    _ = app.namespaces_view.takeSubscriptionRequest();
    for (app.resource_families.registry.items()) |*entry| {
        _ = entry.takeRequest();
    }

    app.servicePollTimeout();

    try std.testing.expectEqual(@as(@TypeOf(app.pods_view.takeSubscriptionRequest()), .none), app.pods_view.takeSubscriptionRequest());
    try std.testing.expectEqual(@as(@TypeOf(app.nodes_view.takeSubscriptionRequest()), .none), app.nodes_view.takeSubscriptionRequest());
    try std.testing.expectEqual(@as(@TypeOf(app.namespaces_view.takeSubscriptionRequest()), .none), app.namespaces_view.takeSubscriptionRequest());
    for (app.resource_families.registry.items()) |*entry| {
        try std.testing.expectEqual(family_registry.Request.none, entry.takeRequest());
    }
}

test "palette resource switch starts subscription without another key" {
    const allocator = std.testing.allocator;
    const io = runtime.io();
    var lists = @import("k8s/FakeTransport.zig").PathListTransport.init(
        allocator,
        resource_subscription.task14ListBodyForPath,
    );
    defer lists.deinit();
    var app = try App.init(allocator, .{});
    defer app.deinit();

    const active_session = try task14PrepareLocalSession(
        undefined,
        allocator,
        io,
        app.shared_event,
        1,
        .{
            .context_name = "palette-test",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
    );
    _ = try app.active_session_slot.commit(active_session);
    app.k8s_service.connected = true;
    app.task14 = .{ .transport = lists.transport(), .hold_watch = true };

    try app.executePaletteCommand("deploy", false);

    const deployment_index = try task14FamilyIndex(&app, "deployments");
    try std.testing.expect(app.resource_families.registry.entryAt(deployment_index).?.active != null);
    try std.testing.expect(app.deployments_view.table.loading);

    app.finishLifecycle();
    try std.testing.expectEqual(@as(usize, 0), app.lifecycle_supervisor.liveChildren());
    try std.testing.expectEqual(@as(usize, 0), active_session.leaseCount());
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
