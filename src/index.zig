// Main module exports for testing
pub const Terminal = @import("core/terminal.zig").Terminal;
pub const Key = @import("core/terminal.zig").Key;
pub const Color = @import("core/terminal.zig").Color;
pub const Header = @import("ui/header.zig").Header;
pub const Footer = @import("ui/footer.zig").Footer;

// UI module exports
pub const ui = struct {
    pub const table_layout = @import("ui/table_layout.zig");
    pub const table_state = @import("ui/table_state.zig");
};

// View exports - pods_view is standalone, all others come from resource_configs
pub const PodsView = @import("view/pods_view.zig").PodsView;
const rc = @import("view/resource_configs.zig");
pub const DeploymentsView = rc.DeploymentsView;
pub const ServicesView = rc.ServicesView;
pub const NamespacesView = @import("view/namespaces_view.zig").NamespacesView;
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
pub const ContextsView = @import("view/contexts_view.zig").ContextsView;
pub const ThemesView = @import("view/themes_view.zig").ThemesView;
pub const HelpView = @import("view/help_view.zig").HelpView;
pub const DetailView = @import("view/detail_view.zig").DetailView;
pub const LogsView = @import("view/logs_view.zig").LogsView;
pub const AuthorizationView = @import("view/authorization_view.zig").AuthorizationView;
pub const resource_view = @import("view/resource_view.zig");
pub const resource_configs = @import("view/resource_configs.zig");
pub const TableState = @import("ui/table_state.zig").TableState;
pub const View = @import("viewmodel/view.zig").View;
pub const ResourceInfo = @import("viewmodel/view.zig").ResourceInfo;
pub const sort = @import("viewmodel/sort.zig");
pub const filter = @import("viewmodel/filter.zig");
pub const App = @import("app.zig").App;
pub const viewNameToPrimaryView = @import("app.zig").viewNameToPrimaryView;
pub const Config = @import("model/config.zig");
pub const Logger = @import("core/logger.zig");
pub const version = @import("model/version.zig");
pub const theme_loader = @import("model/theme_loader.zig");
pub const color256 = @import("model/color256.zig");
pub const hints = @import("model/hints.zig");
pub const fixtures = @import("fixtures/index.zig");

// Services
pub const K8sService = @import("services/k8s_service.zig").K8sService;
pub const ClusterInfo = @import("services/k8s_service.zig").ClusterInfo;
pub const k8s_service_types = @import("services/k8s_types.zig");

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
