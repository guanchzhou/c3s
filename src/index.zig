// Main module exports for testing
pub const Terminal = @import("core/Terminal.zig").Terminal;
pub const Key = @import("core/Terminal.zig").Key;
pub const Color = @import("core/Terminal.zig").Color;
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
pub const PortForwardsView = @import("view/PortForwardsView.zig").PortForwardsView;
pub const log_text = @import("view/log_text.zig");
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
pub const EventsView = rc.EventsView;
pub const ResourceQuotasView = rc.ResourceQuotasView;
pub const LimitRangesView = rc.LimitRangesView;
pub const PodDisruptionBudgetsView = rc.PodDisruptionBudgetsView;
pub const HPAView = rc.HPAView;
pub const EndpointsView = rc.EndpointsView;
pub const StorageClassesView = rc.StorageClassesView;
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
pub const App = @import("App.zig").App;
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

// Services
pub const K8sService = @import("services/K8sService.zig").K8sService;
pub const ClusterInfo = @import("services/K8sService.zig").ClusterInfo;
pub const PortForwardRegistry = @import("services/PortForwardRegistry.zig").PortForwardRegistry;
pub const K9sMigration = @import("services/K9sMigration.zig");
pub const k8s_service_types = @import("services/k8s_types.zig");
pub const secret_decode = @import("viewmodel/secret_decode.zig");

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

// Test discovery root. Zig analyzes decls lazily, so the pub imports above do
// NOT by themselves pull co-located `test{}` blocks into the test binary —
// without this block `zig build test` compiles an EMPTY test runner and
// reports success. refAllDecls references every pub decl, forcing analysis of
// each imported module and collecting its tests.
test {
    @import("std").testing.refAllDecls(@This());
}
