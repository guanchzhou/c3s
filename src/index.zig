// Main module exports for testing
pub const Terminal = @import("core/Terminal.zig").Terminal;
pub const Key = @import("core/Terminal.zig").Key;
pub const Color = @import("core/Terminal.zig").Color;
pub const Wakeup = @import("core/Wakeup.zig").Wakeup;
pub const Header = @import("ui/Header.zig").Header;
pub const Footer = @import("ui/Footer.zig").Footer;

// UI module exports
pub const ui = struct {
    pub const table_layout = @import("ui/table_layout.zig");
    pub const table_state = @import("ui/TableState.zig");
};

// View exports - all resource views (including pods) come from resource_configs
const rc = @import("view/resource_configs.zig");
pub const PodsView = rc.PodsView;
pub const DeploymentsView = rc.DeploymentsView;
pub const ServicesView = rc.ServicesView;
pub const NamespacesView = @import("view/NamespacesView.zig").NamespacesView;
pub const namespaces_view = @import("view/NamespacesView.zig");
pub const PortForwardsView = @import("view/PortForwardsView.zig").PortForwardsView;
pub const log_text = @import("view/log_text.zig");
pub const views_config = @import("model/views_config.zig");
pub const NodesView = rc.NodesView;
pub const StatefulSetsView = rc.StatefulSetsView;
pub const DaemonSetsView = rc.DaemonSetsView;
pub const ReplicaSetsView = rc.ReplicaSetsView;
pub const JobsView = rc.JobsView;
pub const CronJobsView = rc.CronJobsView;
pub const ConfigMapsView = rc.ConfigMapsView;
pub const SecretsView = rc.SecretsView;
pub const PersistentVolumesView = rc.PersistentVolumesView;
pub const PersistentVolumeClaimsView = rc.PersistentVolumeClaimsView;
pub const IngressesView = rc.IngressesView;
pub const NetworkPoliciesView = rc.NetworkPoliciesView;
pub const ServiceAccountsView = rc.ServiceAccountsView;
pub const RolesView = rc.RolesView;
pub const RoleBindingsView = rc.RoleBindingsView;
pub const ClusterRolesView = rc.ClusterRolesView;
pub const ClusterRoleBindingsView = rc.ClusterRoleBindingsView;
pub const ValidatingAdmissionPoliciesView = rc.ValidatingAdmissionPoliciesView;
pub const ValidatingAdmissionPolicyBindingsView = rc.ValidatingAdmissionPolicyBindingsView;
pub const MutatingAdmissionPoliciesView = rc.MutatingAdmissionPoliciesView;
pub const MutatingAdmissionPolicyBindingsView = rc.MutatingAdmissionPolicyBindingsView;
pub const ValidatingWebhookConfigurationsView = rc.ValidatingWebhookConfigurationsView;
pub const MutatingWebhookConfigurationsView = rc.MutatingWebhookConfigurationsView;
pub const EventsView = rc.EventsView;
pub const ResourceQuotasView = rc.ResourceQuotasView;
pub const LimitRangesView = rc.LimitRangesView;
pub const PodDisruptionBudgetsView = rc.PodDisruptionBudgetsView;
pub const HPAView = rc.HPAView;
pub const EndpointsView = rc.EndpointsView;
pub const StorageClassesView = rc.StorageClassesView;
pub const HTTPRoutesView = rc.HTTPRoutesView;
pub const GatewaysView = rc.GatewaysView;
pub const ContextsView = @import("view/ContextsView.zig").ContextsView;
pub const ThemesView = @import("view/ThemesView.zig").ThemesView;
pub const HelpView = @import("view/HelpView.zig").HelpView;
pub const DetailView = @import("view/DetailView.zig").DetailView;
pub const LogsView = @import("view/LogsView.zig").LogsView;
pub const AuthorizationView = @import("view/AuthorizationView.zig").AuthorizationView;
pub const TrafficView = @import("view/TrafficView.zig").TrafficView;
pub const resource_view = @import("view/resource_view.zig");
pub const resource_configs = @import("view/resource_configs.zig");
pub const TableState = @import("ui/TableState.zig").TableState;
pub const View = @import("viewmodel/view.zig").View;
pub const ResourceInfo = @import("viewmodel/view.zig").ResourceInfo;
pub const sort = @import("viewmodel/sort.zig");
pub const filter = @import("viewmodel/filter.zig");
pub const k9s_query = @import("viewmodel/k9s_query.zig");
pub const clipboard = @import("core/clipboard.zig");
pub const App = @import("App.zig").App;
pub const runTask14ComposedOrderingGate = @import("App.zig").runTask14ComposedOrderingGate;
pub const runTask14IdentityGate = @import("App.zig").runTask14IdentityGate;
pub const runTask14ContextSwitchGate = @import("App.zig").runTask14ContextSwitchGate;
pub const runTask14AllocationOrdinalsGate = @import("App.zig").runTask14AllocationOrdinalsGate;
pub const runTask14ShutdownGate = @import("App.zig").runTask14ShutdownGate;
pub const runTask14RollbackIsolationGate = @import("App.zig").runTask14RollbackIsolationGate;
pub const runTask14PersistentApplyShutdownGate = @import("App.zig").runTask14PersistentApplyShutdownGate;
pub const runTask14ShutdownDrainAllocationOrdinalsGate = @import("App.zig").runTask14ShutdownDrainAllocationOrdinalsGate;
pub const runTask14MalformedProductionGate = @import("App.zig").runTask14MalformedProductionGate;
pub const runTask14MalformedWatchProductionGate = @import("App.zig").runTask14MalformedWatchProductionGate;
pub const runTask14HeaderPeriodicGate = @import("App.zig").runTask14HeaderPeriodicGate;
pub const Config = @import("model/config.zig");
pub const Logger = @import("core/logger.zig");
pub const version = @import("model/version.zig");
pub const theme_loader = @import("model/theme_loader.zig");
pub const color256 = @import("model/color256.zig");
pub const hints = @import("model/hints.zig");
pub const fixtures = @import("fixtures/index.zig");

// Additional module re-exports so tests reach src files through the "src"
// module (Zig 0.16 forbids tests/ from @import("../src/..") across the module
// boundary; named-module access via index.zig is the supported path).
pub const xdg = @import("core/xdg.zig");
pub const runtime = @import("core/runtime.zig");
pub const clock = @import("core/clock.zig");
pub const env = @import("core/env.zig");
pub const perf_telemetry = @import("core/perf_telemetry.zig");
pub const sys = @import("core/sys.zig");
pub const age = @import("viewmodel/age.zig");
pub const command = @import("viewmodel/command.zig");
pub const view_manager = @import("viewmodel/ViewManager.zig");
pub const keybindings_vm = @import("viewmodel/keybindings_vm.zig");
pub const keybindings_data = @import("viewmodel/keybindings_data.zig");
pub const keybindings = @import("model/keybindings.zig");
pub const box_drawing = @import("ui/box_drawing.zig");
pub const command_input = @import("ui/CommandInput.zig");
pub const CommandInput = @import("ui/CommandInput.zig").CommandInput;
pub const fuzzy = @import("ui/fuzzy.zig");
pub const panic_hook = @import("panic_hook.zig");
pub const cli = @import("cli.zig");
pub const task15_diagnostics = @import("task15_diagnostics.zig");

// Services
pub const K8sService = @import("services/K8sService.zig").K8sService;
pub const ClusterInfo = @import("services/K8sService.zig").ClusterInfo;
pub const PortForwardRegistry = @import("services/PortForwardRegistry.zig").PortForwardRegistry;
pub const K9sMigration = @import("services/K9sMigration.zig");
pub const k8s_service_types = @import("services/k8s_types.zig");
pub const secret_decode = @import("viewmodel/secret_decode.zig");
pub const KeyBindingsViewModel = @import("viewmodel/keybindings_vm.zig").KeyBindingsViewModel;
pub const ViewType = @import("viewmodel/keybindings_vm.zig").ViewType;

// K8s module exports (from zig-klient library)
pub const klient = @import("klient");
pub const K8sClient = klient.K8sClient;
pub const k8s_types = klient.types;
pub const k8s_resources = klient.resources;
pub const k8s_retry = klient.retry;
pub const k8s_watch = klient.watch;
pub const k8s_exec_credential = klient.exec_credential;
pub const k8s_tls = klient.tls;
// Note: ConnectionPool was removed in zig-klient v0.3.0 (std.http.Client pools internally).
pub const k8s_crd = klient.crd;
pub const KubeconfigParser = klient.KubeconfigParser;

// Shared active-context ownership and switch coordination.
pub const k8s_active_context = @import("k8s/ActiveContextSession.zig");
pub const ActiveContextSession = k8s_active_context.ActiveContextSession;
pub const ContextSpec = k8s_active_context.ContextSpec;
pub const OwnedContextSpec = k8s_active_context.OwnedContextSpec;
pub const RequestLease = k8s_active_context.RequestLease;
pub const LeasePurpose = k8s_active_context.LeasePurpose;
pub const SessionState = k8s_active_context.SessionState;
pub const k8s_active_session_slot = @import("k8s/ActiveSessionSlot.zig");
pub const ActiveSessionSlot = k8s_active_session_slot.ActiveSessionSlot;
pub const SessionView = k8s_active_session_slot.SessionView;
pub const k8s_resource_key = @import("k8s/ResourceKey.zig");
pub const k8s_change_queue = @import("k8s/ChangeQueue.zig");
pub const ChangeQueue = k8s_change_queue.ChangeQueue;
pub const k8s_lifecycle_inbox = @import("k8s/LifecycleInbox.zig");
pub const k8s_lifecycle_supervisor = @import("k8s/LifecycleSupervisor.zig");
pub const LifecycleSupervisor = k8s_lifecycle_supervisor.LifecycleSupervisor;
pub const k8s_ancillary_requests = @import("k8s/AncillaryRequests.zig");
pub const AncillaryRequests = k8s_ancillary_requests.AncillaryRequests;
pub const k8s_header_metrics_request = @import("k8s/HeaderMetricsRequest.zig");
pub const k8s_traffic_request = @import("k8s/TrafficRequest.zig");
pub const k8s_detail_request = @import("k8s/DetailRequest.zig");
pub const k8s_logs_request = @import("k8s/LogsRequest.zig");
pub const k8s_authorization_request = @import("k8s/AuthorizationRequest.zig");
pub const k8s_read_transport = @import("k8s/ReadTransport.zig");
pub const k8s_fake_transport = @import("k8s/FakeTransport.zig");
pub const k8s_stream_list = @import("k8s/StreamList.zig");
pub const k8s_pod_record = @import("k8s/PodRecord.zig");
pub const PodRecord = k8s_pod_record;
pub const NodeRecord = @import("k8s/NodeRecord.zig");
pub const NamespaceRecord = @import("k8s/NamespaceRecord.zig");
pub const ServiceRecord = @import("k8s/ServiceRecord.zig");
pub const EndpointRecord = @import("k8s/EndpointRecord.zig");
pub const EndpointSliceRecord = @import("k8s/EndpointSliceRecord.zig");
pub const ConfigMapRecord = @import("k8s/ConfigMapRecord.zig");
pub const SecretRecord = @import("k8s/SecretRecord.zig");
pub const ServiceAccountRecord = @import("k8s/ServiceAccountRecord.zig");
pub const ResourceQuotaRecord = @import("k8s/ResourceQuotaRecord.zig");
pub const LimitRangeRecord = @import("k8s/LimitRangeRecord.zig");
pub const DeploymentRecord = @import("k8s/DeploymentRecord.zig");
pub const StatefulSetRecord = @import("k8s/StatefulSetRecord.zig");
pub const DaemonSetRecord = @import("k8s/DaemonSetRecord.zig");
pub const ReplicaSetRecord = @import("k8s/ReplicaSetRecord.zig");
pub const JobRecord = @import("k8s/JobRecord.zig");
pub const CronJobRecord = @import("k8s/CronJobRecord.zig");
pub const HPARecord = @import("k8s/HPARecord.zig");
pub const PDBRecord = @import("k8s/PDBRecord.zig");
pub const IngressRecord = @import("k8s/IngressRecord.zig");
pub const IngressClassRecord = @import("k8s/IngressClassRecord.zig");
pub const NetworkPolicyRecord = @import("k8s/NetworkPolicyRecord.zig");
pub const IPAddressRecord = @import("k8s/IPAddressRecord.zig");
pub const ServiceCIDRRecord = @import("k8s/ServiceCIDRRecord.zig");
pub const PVRecord = @import("k8s/PVRecord.zig");
pub const PVCRecord = @import("k8s/PVCRecord.zig");
pub const StorageClassRecord = @import("k8s/StorageClassRecord.zig");
pub const VolumeAttributesClassRecord = @import("k8s/VolumeAttributesClassRecord.zig");
pub const CSIDriverRecord = @import("k8s/CSIDriverRecord.zig");
pub const GatewayClassRecord = @import("k8s/GatewayClassRecord.zig");
pub const GatewayRecord = @import("k8s/GatewayRecord.zig");
pub const HTTPRouteRecord = @import("k8s/HTTPRouteRecord.zig");
pub const GRPCRouteRecord = @import("k8s/GRPCRouteRecord.zig");
pub const ReferenceGrantRecord = @import("k8s/ReferenceGrantRecord.zig");
pub const TCPRouteRecord = @import("k8s/TCPRouteRecord.zig");
pub const TLSRouteRecord = @import("k8s/TLSRouteRecord.zig");
pub const UDPRouteRecord = @import("k8s/UDPRouteRecord.zig");
pub const BackendTLSPolicyRecord = @import("k8s/BackendTLSPolicyRecord.zig");
pub const ListenerSetRecord = @import("k8s/ListenerSetRecord.zig");
pub const RoleRecord = @import("k8s/RoleRecord.zig");
pub const RoleBindingRecord = @import("k8s/RoleBindingRecord.zig");
pub const ClusterRoleRecord = @import("k8s/ClusterRoleRecord.zig");
pub const ClusterRoleBindingRecord = @import("k8s/ClusterRoleBindingRecord.zig");
pub const ValidatingAdmissionPolicyRecord = @import("k8s/ValidatingAdmissionPolicyRecord.zig");
pub const ValidatingAdmissionPolicyBindingRecord = @import("k8s/ValidatingAdmissionPolicyBindingRecord.zig");
pub const MutatingAdmissionPolicyRecord = @import("k8s/MutatingAdmissionPolicyRecord.zig");
pub const MutatingAdmissionPolicyBindingRecord = @import("k8s/MutatingAdmissionPolicyBindingRecord.zig");
pub const ValidatingWebhookConfigurationRecord = @import("k8s/ValidatingWebhookConfigurationRecord.zig");
pub const MutatingWebhookConfigurationRecord = @import("k8s/MutatingWebhookConfigurationRecord.zig");
pub const ResourceClaimRecord = @import("k8s/ResourceClaimRecord.zig");
pub const DeviceClassRecord = @import("k8s/DeviceClassRecord.zig");
pub const PriorityClassRecord = @import("k8s/PriorityClassRecord.zig");
pub const RuntimeClassRecord = @import("k8s/RuntimeClassRecord.zig");
pub const LeaseRecord = @import("k8s/LeaseRecord.zig");
pub const CSRRecord = @import("k8s/CSRRecord.zig");
pub const StorageVersionMigrationRecord = @import("k8s/StorageVersionMigrationRecord.zig");
pub const EventRecord = @import("k8s/EventRecord.zig");
pub const k8s_load_balancer_address = @import("k8s/LoadBalancerAddress.zig");
pub const k8s_resource_store = @import("k8s/ResourceStore.zig");
pub const k8s_resource_projection = @import("k8s/ResourceProjection.zig");
pub const k8s_resource_subscription = @import("k8s/ResourceSubscription.zig");
pub const k8s_resource_family_registry = @import("k8s/ResourceFamilyRegistry.zig");
pub const k8s_list_watch = @import("k8s/ListWatch.zig");
pub const k8s_data_plane = @import("k8s/DataPlane.zig");
pub const DataPlane = k8s_data_plane.DataPlane;
pub const k8s_metrics_feed = @import("k8s/MetricsFeed.zig");

// Test discovery root. Zig analyzes decls lazily, so the pub imports above do
// NOT by themselves pull co-located `test{}` blocks into the test binary —
// without this block `zig build test` compiles an EMPTY test runner and
// reports success. refAllDecls references every pub decl, forcing analysis of
// each imported module and collecting its tests.
test {
    _ = @import("k8s/batch_records_test.zig");
    _ = @import("k8s/networking_records_test.zig");
    _ = @import("k8s/storage_records_test.zig");
    _ = @import("k8s/gateway_records_test.zig");
    _ = @import("k8s/rbac_records_test.zig");
    _ = @import("k8s/rbac_admission_records_test.zig");
    _ = @import("k8s/dra_platform_records_test.zig");
    @import("std").testing.refAllDecls(@This());
}
