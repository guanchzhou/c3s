const std = @import("std");
const posix = std.posix;
const terminal = @import("core/terminal.zig");
const Terminal = terminal.Terminal;
const Key = terminal.Key;
const Header = @import("ui/header.zig").Header;
const Footer = @import("ui/footer.zig").Footer;
const CommandInput = @import("ui/command_input.zig").CommandInput;
const Theme = @import("theme.zig");
const Cli = @import("cli.zig");
const Config = @import("model/config.zig");
const Logger = @import("core/logger.zig");
const version = @import("model/version.zig");
const theme_loader = @import("model/theme_loader.zig");
// MVVM imports
const View = @import("viewmodel/view.zig").View;
const ViewManager = @import("viewmodel/view_manager.zig").ViewManager;
const Command = @import("viewmodel/command.zig").Command;
const CommandRegistry = @import("viewmodel/command.zig").CommandRegistry;

// View imports
const PodsView = @import("view/pods_view.zig").PodsView;
const DeploymentsView = @import("view/deployments_view.zig").DeploymentsView;
const ServicesView = @import("view/services_view.zig").ServicesView;
const NamespacesView = @import("view/namespaces_view.zig").NamespacesView;
const NodesView = @import("view/nodes_view.zig").NodesView;
const StatefulSetsView = @import("view/statefulsets_view.zig").StatefulSetsView;
const DaemonSetsView = @import("view/daemonsets_view.zig").DaemonSetsView;
const ReplicaSetsView = @import("view/replicasets_view.zig").ReplicaSetsView;
const JobsView = @import("view/jobs_view.zig").JobsView;
const CronJobsView = @import("view/cronjobs_view.zig").CronJobsView;
const ConfigMapsView = @import("view/configmaps_view.zig").ConfigMapsView;
const SecretsView = @import("view/secrets_view.zig").SecretsView;
const PersistentVolumesView = @import("view/persistentvolumes_view.zig").PersistentVolumesView;
const PersistentVolumeClaimsView = @import("view/persistentvolumeclaims_view.zig").PersistentVolumeClaimsView;
const IngressesView = @import("view/ingresses_view.zig").IngressesView;
const NetworkPoliciesView = @import("view/networkpolicies_view.zig").NetworkPoliciesView;
const ServiceAccountsView = @import("view/serviceaccounts_view.zig").ServiceAccountsView;
const RolesView = @import("view/roles_view.zig").RolesView;
const RoleBindingsView = @import("view/rolebindings_view.zig").RoleBindingsView;
const ClusterRolesView = @import("view/clusterroles_view.zig").ClusterRolesView;
const ClusterRoleBindingsView = @import("view/clusterrolebindings_view.zig").ClusterRoleBindingsView;
const EventsView = @import("view/events_view.zig").EventsView;
const ResourceQuotasView = @import("view/resourcequotas_view.zig").ResourceQuotasView;
const LimitRangesView = @import("view/limitranges_view.zig").LimitRangesView;
const PodDisruptionBudgetsView = @import("view/poddisruptionbudgets_view.zig").PodDisruptionBudgetsView;
const HPAView = @import("view/hpa_view.zig").HPAView;
const ContextsView = @import("view/contexts_view.zig").ContextsView;
const ThemesView = @import("view/themes_view.zig").ThemesView;
const HelpView = @import("view/help_view.zig").HelpView;
const DetailView = @import("view/detail_view.zig").DetailView;
const LogsView = @import("view/logs_view.zig").LogsView;

// Service imports
const k8s_service_mod = @import("services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const ResourceType = k8s_service_mod.ResourceType;
const ResourceInfo = k8s_service_mod.ResourceInfo;

// Global flag for terminal resize signal
var terminal_resized: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

pub const App = struct {
    allocator: std.mem.Allocator,
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
    last_render_time: i128 = 0,
    min_frame_time_ns: i128 = 16_666_667, // ~60 FPS (16.67ms)
    current_theme_name: []const u8,

    // MVVM components
    view_manager: ViewManager,
    command_registry: CommandRegistry,
    theme: *theme_loader.ThemeColors,

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
    contexts_view: *ContextsView,

    // UI views
    themes_view: *ThemesView,
    help_view: *HelpView,
    detail_view: *DetailView,
    logs_view: *LogsView,

    // Delete confirmation state
    delete_pending: bool = false,
    delete_resource_name: ?[]u8 = null,
    delete_resource_namespace: ?[]u8 = null,
    delete_resource_type: ?ResourceType = null,

    // Track which primary view is active (for view switching, not pushing)
    current_primary_view: enum { pods, deployments, services, namespaces, nodes, statefulsets, daemonsets, replicasets, jobs, cronjobs, configmaps, secrets, persistentvolumes, persistentvolumeclaims, ingresses, networkpolicies, serviceaccounts, roles, rolebindings, clusterroles, clusterrolebindings, events, resourcequotas, limitranges, poddisruptionbudgets, hpa, contexts, themes } = .pods,

    pub fn init(allocator: std.mem.Allocator, config: Cli.Config) !App {
        // Initialize terminal
        const term = try Terminal.init(allocator);

        // Load UI config from file
        const ui_config = Config.load(allocator) catch Config.Config{
            .allocator = allocator,
            .ui = Config.UiConfig{},
            .theme_owned = null,
        };
        defer ui_config.deinit();

        // Load theme
        const theme = try allocator.create(theme_loader.ThemeColors);
        theme.* = try theme_loader.loadTheme(allocator, ui_config.ui.theme);

        // Initialize Kubernetes service (heap-allocated so views get a stable pointer)
        const k8s_service = try allocator.create(K8sService);
        k8s_service.* = try K8sService.init(allocator);
        errdefer {
            k8s_service.deinit();
            allocator.destroy(k8s_service);
        }

        // Try to connect to K8s cluster (non-fatal if it fails)
        k8s_service.connect(config.context) catch |err| {
            Logger.warn("Failed to connect to Kubernetes: {}. Continuing without cluster connection.", .{err});
        };

        // Initialize MVVM components
        const view_manager = try ViewManager.init(allocator);
        const command_registry = try CommandRegistry.init(allocator);

        // Allocate view pointers (will initialize after App struct is created)
        const deployments_view = try allocator.create(DeploymentsView);
        const services_view = try allocator.create(ServicesView);
        const namespaces_view = try allocator.create(NamespacesView);
        const nodes_view = try allocator.create(NodesView);
        const statefulsets_view = try allocator.create(StatefulSetsView);
        const daemonsets_view = try allocator.create(DaemonSetsView);
        const replicasets_view = try allocator.create(ReplicaSetsView);
        const jobs_view = try allocator.create(JobsView);
        const cronjobs_view = try allocator.create(CronJobsView);
        const configmaps_view = try allocator.create(ConfigMapsView);
        const secrets_view = try allocator.create(SecretsView);
        const persistentvolumes_view = try allocator.create(PersistentVolumesView);
        const persistentvolumeclaims_view = try allocator.create(PersistentVolumeClaimsView);
        const ingresses_view = try allocator.create(IngressesView);
        const networkpolicies_view = try allocator.create(NetworkPoliciesView);
        const serviceaccounts_view = try allocator.create(ServiceAccountsView);
        const roles_view = try allocator.create(RolesView);
        const rolebindings_view = try allocator.create(RoleBindingsView);
        const clusterroles_view = try allocator.create(ClusterRolesView);
        const clusterrolebindings_view = try allocator.create(ClusterRoleBindingsView);
        const events_view = try allocator.create(EventsView);
        const resourcequotas_view = try allocator.create(ResourceQuotasView);
        const limitranges_view = try allocator.create(LimitRangesView);
        const poddisruptionbudgets_view = try allocator.create(PodDisruptionBudgetsView);
        const hpa_view = try allocator.create(HPAView);
        const contexts_view = try allocator.create(ContextsView);
        const pods_view = try allocator.create(PodsView);

        // Initialize UI views (these don't need k8s_service)

        const themes_view = try allocator.create(ThemesView);
        themes_view.* = try ThemesView.init(allocator, ui_config.ui.theme, theme);
        errdefer themes_view.cleanup();

        const help_view = try allocator.create(HelpView);
        help_view.* = try HelpView.init(allocator, theme);
        errdefer help_view.cleanup();

        const detail_view = try allocator.create(DetailView);
        detail_view.* = try DetailView.init(allocator, theme);
        errdefer detail_view.cleanup();

        const logs_view = try allocator.create(LogsView);
        logs_view.* = try LogsView.init(allocator, theme);
        errdefer logs_view.cleanup();

        // Initialize header with cluster info
        const cluster_info = k8s_service.getClusterInfo();
        var header = if (cluster_info.connected) blk: {
            // Use real cluster data
            const real_data = struct {
                context: []const u8,
                cluster: []const u8,
                user: []const u8,
                k8s_version: []const u8,
                cpu_usage: u8,
                mem_usage: u8,
            }{
                .context = cluster_info.context,
                .cluster = cluster_info.cluster,
                .user = "system:admin", // TODO: Get from kubeconfig
                .k8s_version = "v1.34.1+k3s1", // TODO: Get from cluster
                .cpu_usage = 0,
                .mem_usage = 0,
            };
            Logger.info("Connected to cluster: {s}, context: {s}", .{ cluster_info.cluster, cluster_info.context });
            break :blk try Header.initWithData(allocator, theme, real_data);
        } else blk: {
            // Use fixtures when not connected
            break :blk try Header.init(allocator, theme, config.debug);
        };

        const footer = try Footer.init(allocator, theme);
        const command_input = try CommandInput.init(allocator, theme);

        // Apply UI config
        Logger.info("UI Config - compact: {}, footer: {}", .{ ui_config.ui.compact, ui_config.ui.footer });
        header.setCompact(ui_config.ui.compact);

        // Create app
        var app = App{
            .allocator = allocator,
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
            .pods_view = pods_view,
            .deployments_view = deployments_view,
            .services_view = services_view,
            .namespaces_view = namespaces_view,
            .nodes_view = nodes_view,
            .statefulsets_view = statefulsets_view,
            .daemonsets_view = daemonsets_view,
            .replicasets_view = replicasets_view,
            .jobs_view = jobs_view,
            .cronjobs_view = cronjobs_view,
            .configmaps_view = configmaps_view,
            .secrets_view = secrets_view,
            .persistentvolumes_view = persistentvolumes_view,
            .persistentvolumeclaims_view = persistentvolumeclaims_view,
            .ingresses_view = ingresses_view,
            .networkpolicies_view = networkpolicies_view,
            .serviceaccounts_view = serviceaccounts_view,
            .roles_view = roles_view,
            .rolebindings_view = rolebindings_view,
            .clusterroles_view = clusterroles_view,
            .clusterrolebindings_view = clusterrolebindings_view,
            .events_view = events_view,
            .resourcequotas_view = resourcequotas_view,
            .limitranges_view = limitranges_view,
            .poddisruptionbudgets_view = poddisruptionbudgets_view,
            .hpa_view = hpa_view,
            .contexts_view = contexts_view,
            .themes_view = themes_view,
            .help_view = help_view,
            .detail_view = detail_view,
            .logs_view = logs_view,
        };

        // NOW initialize resource views with stable pointer to app.k8s_service
        // (This must happen AFTER k8s_service is moved into the App struct)
        pods_view.* = try PodsView.init(allocator, theme, app.k8s_service);
        errdefer pods_view.cleanup();

        deployments_view.* = try DeploymentsView.init(allocator, theme, app.k8s_service);
        errdefer deployments_view.deinit();

        services_view.* = try ServicesView.init(allocator, theme, app.k8s_service);
        errdefer services_view.deinit();

        namespaces_view.* = try NamespacesView.init(allocator, theme, app.k8s_service);
        errdefer namespaces_view.deinit();

        nodes_view.* = try NodesView.init(allocator, theme, app.k8s_service);
        errdefer nodes_view.deinit();

        statefulsets_view.* = try StatefulSetsView.init(allocator, theme, app.k8s_service);
        errdefer statefulsets_view.deinit();

        daemonsets_view.* = try DaemonSetsView.init(allocator, theme, app.k8s_service);
        errdefer daemonsets_view.deinit();

        replicasets_view.* = try ReplicaSetsView.init(allocator, theme, app.k8s_service);
        errdefer replicasets_view.deinit();

        jobs_view.* = try JobsView.init(allocator, theme, app.k8s_service);
        errdefer jobs_view.deinit();

        cronjobs_view.* = try CronJobsView.init(allocator, theme, app.k8s_service);
        errdefer cronjobs_view.deinit();

        configmaps_view.* = try ConfigMapsView.init(allocator, theme, app.k8s_service);
        errdefer configmaps_view.deinit();

        secrets_view.* = try SecretsView.init(allocator, theme, app.k8s_service);
        errdefer secrets_view.deinit();

        persistentvolumes_view.* = try PersistentVolumesView.init(allocator, theme, app.k8s_service);
        errdefer persistentvolumes_view.deinit();

        persistentvolumeclaims_view.* = try PersistentVolumeClaimsView.init(allocator, theme, app.k8s_service);
        errdefer persistentvolumeclaims_view.deinit();

        ingresses_view.* = try IngressesView.init(allocator, theme, app.k8s_service);
        errdefer ingresses_view.deinit();

        networkpolicies_view.* = try NetworkPoliciesView.init(allocator, theme, app.k8s_service);
        errdefer networkpolicies_view.deinit();

        serviceaccounts_view.* = try ServiceAccountsView.init(allocator, theme, app.k8s_service);
        errdefer serviceaccounts_view.deinit();

        roles_view.* = try RolesView.init(allocator, theme, app.k8s_service);
        errdefer roles_view.deinit();

        rolebindings_view.* = try RoleBindingsView.init(allocator, theme, app.k8s_service);
        errdefer rolebindings_view.deinit();

        clusterroles_view.* = try ClusterRolesView.init(allocator, theme, app.k8s_service);
        errdefer clusterroles_view.deinit();

        clusterrolebindings_view.* = try ClusterRoleBindingsView.init(allocator, theme, app.k8s_service);
        errdefer clusterrolebindings_view.deinit();

        events_view.* = try EventsView.init(allocator, theme, app.k8s_service);
        errdefer events_view.deinit();

        resourcequotas_view.* = try ResourceQuotasView.init(allocator, theme, app.k8s_service);
        errdefer resourcequotas_view.deinit();

        limitranges_view.* = try LimitRangesView.init(allocator, theme, app.k8s_service);
        errdefer limitranges_view.deinit();

        poddisruptionbudgets_view.* = try PodDisruptionBudgetsView.init(allocator, theme, app.k8s_service);
        errdefer poddisruptionbudgets_view.deinit();

        hpa_view.* = try HPAView.init(allocator, theme, app.k8s_service);
        errdefer hpa_view.deinit();

        contexts_view.* = try ContextsView.init(allocator, theme, app.k8s_service);
        errdefer contexts_view.deinit();

        // Register commands
        try app.registerCommands();

        // Push initial view (PodsView is the reference implementation with all features working)
        try app.view_manager.pushView(app.pods_view.createView());

        return app;
    }

    pub fn deinit(self: *App) void {
        // Clean up resource views
        self.poddisruptionbudgets_view.deinit();
        self.allocator.destroy(self.poddisruptionbudgets_view);
        self.hpa_view.deinit();
        self.allocator.destroy(self.hpa_view);
        self.contexts_view.deinit();
        self.allocator.destroy(self.contexts_view);

        self.limitranges_view.deinit();
        self.allocator.destroy(self.limitranges_view);

        self.resourcequotas_view.deinit();
        self.allocator.destroy(self.resourcequotas_view);

        self.events_view.deinit();
        self.allocator.destroy(self.events_view);

        self.clusterrolebindings_view.deinit();
        self.allocator.destroy(self.clusterrolebindings_view);

        self.clusterroles_view.deinit();
        self.allocator.destroy(self.clusterroles_view);

        self.rolebindings_view.deinit();
        self.allocator.destroy(self.rolebindings_view);

        self.roles_view.deinit();
        self.allocator.destroy(self.roles_view);

        self.serviceaccounts_view.deinit();
        self.allocator.destroy(self.serviceaccounts_view);

        self.networkpolicies_view.deinit();
        self.allocator.destroy(self.networkpolicies_view);

        self.ingresses_view.deinit();
        self.allocator.destroy(self.ingresses_view);

        self.persistentvolumeclaims_view.deinit();
        self.allocator.destroy(self.persistentvolumeclaims_view);

        self.persistentvolumes_view.deinit();
        self.allocator.destroy(self.persistentvolumes_view);

        self.secrets_view.deinit();
        self.allocator.destroy(self.secrets_view);

        self.configmaps_view.deinit();
        self.allocator.destroy(self.configmaps_view);

        self.cronjobs_view.deinit();
        self.allocator.destroy(self.cronjobs_view);

        self.jobs_view.deinit();
        self.allocator.destroy(self.jobs_view);

        self.replicasets_view.deinit();
        self.allocator.destroy(self.replicasets_view);

        self.daemonsets_view.deinit();
        self.allocator.destroy(self.daemonsets_view);

        self.statefulsets_view.deinit();
        self.allocator.destroy(self.statefulsets_view);

        self.nodes_view.deinit();
        self.allocator.destroy(self.nodes_view);

        self.namespaces_view.deinit();
        self.allocator.destroy(self.namespaces_view);

        self.services_view.deinit();
        self.allocator.destroy(self.services_view);

        self.deployments_view.deinit();
        self.allocator.destroy(self.deployments_view);

        // Clean up UI views
        self.pods_view.cleanup();
        self.allocator.destroy(self.pods_view);

        self.themes_view.cleanup();
        self.allocator.destroy(self.themes_view);

        self.help_view.cleanup();
        self.allocator.destroy(self.help_view);

        self.detail_view.cleanup();
        self.allocator.destroy(self.detail_view);

        self.logs_view.cleanup();
        self.allocator.destroy(self.logs_view);

        // Clean up delete state
        self.clearDeleteState();

        // Clean up MVVM components
        self.view_manager.deinit();
        self.command_registry.deinit();

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
    }

    fn registerCommands(self: *App) !void {
        // === QUIT COMMANDS ===
        try self.command_registry.register("q", Command{ .name = "q", .execute = quitCommand });
        try self.command_registry.register("q!", Command{ .name = "q!", .execute = quitCommand });
        try self.command_registry.register("qa", Command{ .name = "qa", .execute = quitCommand });
        try self.command_registry.register("Q", Command{ .name = "Q", .execute = quitCommand });
        try self.command_registry.register("quit", Command{ .name = "quit", .execute = quitCommand });
        try self.command_registry.register("exit", Command{ .name = "exit", .execute = quitCommand });

        // === HELP COMMANDS ===
        try self.command_registry.register("?", Command{ .name = "?", .execute = helpCommand });
        try self.command_registry.register("h", Command{ .name = "h", .execute = helpCommand });
        try self.command_registry.register("help", Command{ .name = "help", .execute = helpCommand });

        // === CONTEXT COMMANDS ===
        try self.command_registry.register("ctx", Command{ .name = "ctx", .execute = contextsCommand });
        try self.command_registry.register("context", Command{ .name = "context", .execute = contextsCommand });
        try self.command_registry.register("contexts", Command{ .name = "contexts", .execute = contextsCommand });

        // === NAMESPACE COMMANDS ===
        try self.command_registry.register("ns", Command{ .name = "ns", .execute = namespacesCommand });
        try self.command_registry.register("namespace", Command{ .name = "namespace", .execute = namespacesCommand });
        try self.command_registry.register("namespaces", Command{ .name = "namespaces", .execute = namespacesCommand });

        // === PODS COMMANDS ===
        try self.command_registry.register("pods", Command{ .name = "pods", .execute = podsCommand });
        try self.command_registry.register("po", Command{ .name = "po", .execute = podsCommand });

        // === DEPLOYMENTS ===
        try self.command_registry.register("deployments", Command{ .name = "deployments", .execute = deploymentsCommand });
        try self.command_registry.register("deploy", Command{ .name = "deploy", .execute = deploymentsCommand });
        try self.command_registry.register("dp", Command{ .name = "dp", .execute = deploymentsCommand });

        // === SERVICES ===
        try self.command_registry.register("services", Command{ .name = "services", .execute = servicesCommand });
        try self.command_registry.register("svc", Command{ .name = "svc", .execute = servicesCommand });

        // === NODES ===
        try self.command_registry.register("nodes", Command{ .name = "nodes", .execute = nodesCommand });
        try self.command_registry.register("no", Command{ .name = "no", .execute = nodesCommand });

        // === STATEFULSETS ===
        try self.command_registry.register("statefulsets", Command{ .name = "statefulsets", .execute = statefulsetsCommand });
        try self.command_registry.register("sts", Command{ .name = "sts", .execute = statefulsetsCommand });

        // === DAEMONSETS ===
        try self.command_registry.register("daemonsets", Command{ .name = "daemonsets", .execute = daemonsetsCommand });
        try self.command_registry.register("ds", Command{ .name = "ds", .execute = daemonsetsCommand });

        // === REPLICASETS ===
        try self.command_registry.register("replicasets", Command{ .name = "replicasets", .execute = replicasetsCommand });
        try self.command_registry.register("rs", Command{ .name = "rs", .execute = replicasetsCommand });

        // === CONFIGMAPS ===
        try self.command_registry.register("configmaps", Command{ .name = "configmaps", .execute = notImplementedCommand });
        try self.command_registry.register("cm", Command{ .name = "cm", .execute = notImplementedCommand });

        // === SECRETS ===
        try self.command_registry.register("secrets", Command{ .name = "secrets", .execute = notImplementedCommand });
        try self.command_registry.register("sec", Command{ .name = "sec", .execute = notImplementedCommand });

        // === INGRESS ===
        try self.command_registry.register("ingresses", Command{ .name = "ingresses", .execute = notImplementedCommand });
        try self.command_registry.register("ing", Command{ .name = "ing", .execute = notImplementedCommand });

        // === JOBS ===
        try self.command_registry.register("jobs", Command{ .name = "jobs", .execute = jobsCommand });
        try self.command_registry.register("jo", Command{ .name = "jo", .execute = jobsCommand });
        try self.command_registry.register("job", Command{ .name = "job", .execute = jobsCommand });

        // === CRONJOBS ===
        try self.command_registry.register("cronjobs", Command{ .name = "cronjobs", .execute = cronjobsCommand });
        try self.command_registry.register("cj", Command{ .name = "cj", .execute = cronjobsCommand });

        // === CONFIGMAPS ===
        try self.command_registry.register("configmaps", Command{ .name = "configmaps", .execute = configmapsCommand });
        try self.command_registry.register("cm", Command{ .name = "cm", .execute = configmapsCommand });

        // === SECRETS ===
        try self.command_registry.register("secrets", Command{ .name = "secrets", .execute = secretsCommand });
        try self.command_registry.register("secret", Command{ .name = "secret", .execute = secretsCommand });

        // === PERSISTENTVOLUMES ===
        try self.command_registry.register("persistentvolumes", Command{ .name = "persistentvolumes", .execute = persistentvolumesCommand });
        try self.command_registry.register("pv", Command{ .name = "pv", .execute = persistentvolumesCommand });

        // === PERSISTENTVOLUMECLAIMS ===
        try self.command_registry.register("persistentvolumeclaims", Command{ .name = "persistentvolumeclaims", .execute = persistentvolumeclaimsCommand });
        try self.command_registry.register("pvc", Command{ .name = "pvc", .execute = persistentvolumeclaimsCommand });

        // === INGRESSES ===
        try self.command_registry.register("ingresses", Command{ .name = "ingresses", .execute = ingressesCommand });
        try self.command_registry.register("ing", Command{ .name = "ing", .execute = ingressesCommand });

        // === NETWORKPOLICIES ===
        try self.command_registry.register("networkpolicies", Command{ .name = "networkpolicies", .execute = networkpoliciesCommand });
        try self.command_registry.register("netpol", Command{ .name = "netpol", .execute = networkpoliciesCommand });

        // === SERVICEACCOUNTS ===
        try self.command_registry.register("serviceaccounts", Command{ .name = "serviceaccounts", .execute = serviceaccountsCommand });
        try self.command_registry.register("sa", Command{ .name = "sa", .execute = serviceaccountsCommand });

        // === ROLES ===
        try self.command_registry.register("roles", Command{ .name = "roles", .execute = rolesCommand });

        // === ROLEBINDINGS ===
        try self.command_registry.register("rolebindings", Command{ .name = "rolebindings", .execute = rolebindingsCommand });

        // === CLUSTERROLES ===
        try self.command_registry.register("clusterroles", Command{ .name = "clusterroles", .execute = clusterrolesCommand });

        // === CLUSTERROLEBINDINGS ===
        try self.command_registry.register("clusterrolebindings", Command{ .name = "clusterrolebindings", .execute = clusterrolebindingsCommand });

        // === EVENTS ===
        try self.command_registry.register("events", Command{ .name = "events", .execute = eventsCommand });
        try self.command_registry.register("ev", Command{ .name = "ev", .execute = eventsCommand });

        // === RESOURCEQUOTAS ===
        try self.command_registry.register("resourcequotas", Command{ .name = "resourcequotas", .execute = resourcequotasCommand });
        try self.command_registry.register("quota", Command{ .name = "quota", .execute = resourcequotasCommand });

        // === LIMITRANGES ===
        try self.command_registry.register("limitranges", Command{ .name = "limitranges", .execute = limitrangesCommand });
        try self.command_registry.register("limits", Command{ .name = "limits", .execute = limitrangesCommand });

        // === PODDISRUPTIONBUDGETS ===
        try self.command_registry.register("poddisruptionbudgets", Command{ .name = "poddisruptionbudgets", .execute = poddisruptionbudgetsCommand });
        try self.command_registry.register("pdb", Command{ .name = "pdb", .execute = poddisruptionbudgetsCommand });

        // === HORIZONTALPODAUTOSCALERS ===
        try self.command_registry.register("horizontalpodautoscalers", Command{ .name = "horizontalpodautoscalers", .execute = hpaCommand });
        try self.command_registry.register("hpa", Command{ .name = "hpa", .execute = hpaCommand });

        // === NODES ===
        try self.command_registry.register("nodes", Command{ .name = "nodes", .execute = notImplementedCommand });
        try self.command_registry.register("no", Command{ .name = "no", .execute = notImplementedCommand });

        // === PVC ===
        try self.command_registry.register("persistentvolumeclaims", Command{ .name = "persistentvolumeclaims", .execute = notImplementedCommand });
        try self.command_registry.register("pvc", Command{ .name = "pvc", .execute = notImplementedCommand });

        // === PV ===
        try self.command_registry.register("persistentvolumes", Command{ .name = "persistentvolumes", .execute = notImplementedCommand });
        try self.command_registry.register("pv", Command{ .name = "pv", .execute = notImplementedCommand });

        // === STORAGE CLASSES ===
        try self.command_registry.register("storageclasses", Command{ .name = "storageclasses", .execute = notImplementedCommand });
        try self.command_registry.register("sc", Command{ .name = "sc", .execute = notImplementedCommand });

        // === SERVICE ACCOUNTS ===
        try self.command_registry.register("serviceaccounts", Command{ .name = "serviceaccounts", .execute = notImplementedCommand });
        try self.command_registry.register("sa", Command{ .name = "sa", .execute = notImplementedCommand });

        // === RBAC ===
        try self.command_registry.register("clusterroles", Command{ .name = "clusterroles", .execute = notImplementedCommand });
        try self.command_registry.register("cr", Command{ .name = "cr", .execute = notImplementedCommand });
        try self.command_registry.register("clusterrolebindings", Command{ .name = "clusterrolebindings", .execute = notImplementedCommand });
        try self.command_registry.register("crb", Command{ .name = "crb", .execute = notImplementedCommand });
        try self.command_registry.register("roles", Command{ .name = "roles", .execute = notImplementedCommand });
        try self.command_registry.register("ro", Command{ .name = "ro", .execute = notImplementedCommand });
        try self.command_registry.register("rolebindings", Command{ .name = "rolebindings", .execute = notImplementedCommand });
        try self.command_registry.register("rb", Command{ .name = "rb", .execute = notImplementedCommand });

        // === NETWORK ===
        try self.command_registry.register("networkpolicies", Command{ .name = "networkpolicies", .execute = notImplementedCommand });
        try self.command_registry.register("np", Command{ .name = "np", .execute = notImplementedCommand });
        try self.command_registry.register("endpoints", Command{ .name = "endpoints", .execute = notImplementedCommand });
        try self.command_registry.register("ep", Command{ .name = "ep", .execute = notImplementedCommand });

        // === AUTOSCALING ===
        try self.command_registry.register("horizontalpodautoscalers", Command{ .name = "horizontalpodautoscalers", .execute = notImplementedCommand });
        try self.command_registry.register("hpa", Command{ .name = "hpa", .execute = notImplementedCommand });

        // === POLICY ===
        try self.command_registry.register("poddisruptionbudgets", Command{ .name = "poddisruptionbudgets", .execute = notImplementedCommand });
        try self.command_registry.register("pdb", Command{ .name = "pdb", .execute = notImplementedCommand });

        // === EVENTS ===
        try self.command_registry.register("events", Command{ .name = "events", .execute = notImplementedCommand });
        try self.command_registry.register("ev", Command{ .name = "ev", .execute = notImplementedCommand });

        // === CRD ===
        try self.command_registry.register("customresourcedefinitions", Command{ .name = "customresourcedefinitions", .execute = notImplementedCommand });
        try self.command_registry.register("crd", Command{ .name = "crd", .execute = notImplementedCommand });

        // === K9S SPECIFIC COMMANDS ===
        try self.command_registry.register("aliases", Command{ .name = "aliases", .execute = notImplementedCommand });
        try self.command_registry.register("a", Command{ .name = "a", .execute = notImplementedCommand });
        try self.command_registry.register("xray", Command{ .name = "xray", .execute = notImplementedCommand });
        try self.command_registry.register("xr", Command{ .name = "xr", .execute = notImplementedCommand });
        try self.command_registry.register("x", Command{ .name = "x", .execute = notImplementedCommand });
        try self.command_registry.register("portforwards", Command{ .name = "portforwards", .execute = notImplementedCommand });
        try self.command_registry.register("pf", Command{ .name = "pf", .execute = notImplementedCommand });
        try self.command_registry.register("benchmarks", Command{ .name = "benchmarks", .execute = notImplementedCommand });
        try self.command_registry.register("containers", Command{ .name = "containers", .execute = notImplementedCommand });
        try self.command_registry.register("co", Command{ .name = "co", .execute = notImplementedCommand });

        // === DIRECTORY/LS ===
        try self.command_registry.register("dir", Command{ .name = "dir", .execute = notImplementedCommand });
        try self.command_registry.register("dirs", Command{ .name = "dirs", .execute = notImplementedCommand });
        try self.command_registry.register("d", Command{ .name = "d", .execute = notImplementedCommand });
        try self.command_registry.register("ls", Command{ .name = "ls", .execute = notImplementedCommand });

        // === THEMES/SKINS ===
        try self.command_registry.register("themes", Command{ .name = "themes", .execute = themesCommand });
        try self.command_registry.register("skins", Command{ .name = "skins", .execute = themesCommand });

        // === INTERNAL COMMANDS ===
        try self.command_registry.register("select_theme", Command{ .name = "select_theme", .execute = selectThemeCommand });
    }

    pub fn run(self: *App) !void {
        try self.terminal.enterAlternateScreen();
        defer _ = self.terminal.exitAlternateScreen() catch {};

        try self.terminal.hideCursor();
        defer _ = self.terminal.showCursor() catch {};

        try self.terminal.enableRawMode();
        defer self.terminal.disableRawMode();

        // Setup SIGWINCH handler for terminal resize
        setupResizeHandler() catch |err| {
            Logger.warn("Failed to setup SIGWINCH handler: {}", .{err});
        };

        self.dirty = true;
        self.prev_width = 0;
        self.prev_height = 0;

        while (self.running) {
            self.renderIfNeeded() catch |err| {
                Logger.err("Render error: {any}", .{err});
            };

            // Check if terminal was resized
            if (terminal_resized.load(.acquire)) {
                terminal_resized.store(false, .release);
                self.dirty = true;
            }

            var pollfds = [_]posix.pollfd{
                posix.pollfd{ .fd = self.terminal.stdin.handle, .events = posix.POLL.IN, .revents = 0 },
            };

            // Poll with timeout to catch resize events via signal
            const poll_result = posix.poll(&pollfds, 100) catch |err| { // 100ms timeout
                return err;
            };

            if (poll_result == 0) {
                // Timeout - check if terminal size changed (fallback)
                continue;
            }

            const events = pollfds[0].revents;
            if ((events & posix.POLL.IN) != 0) {
                if (self.terminal.readKey() catch |err| {
                    Logger.err("readKey error: {any}", .{err});
                    continue;
                }) |key| {
                    self.handleKey(key) catch |err| {
                        Logger.err("handleKey error: {any}", .{err});
                    };
                }
            }

            if ((events & (posix.POLL.ERR | posix.POLL.HUP | posix.POLL.NVAL)) != 0) {
                self.running = false;
            }
        }
    }

    fn renderIfNeeded(self: *App) !void {
        const size = try self.terminal.getSize();
        const size_changed = self.prev_width != size.width or self.prev_height != size.height;
        if (!size_changed and !self.dirty) return;

        // Rate limit rendering to prevent excessive updates (60 FPS max)
        const now = std.time.nanoTimestamp();
        const elapsed = now - self.last_render_time;
        if (!size_changed and elapsed < self.min_frame_time_ns) {
            return;
        }
        self.last_render_time = now;

        // Start DEC synchronized output mode
        try self.terminal.beginSyncOutput();
        defer self.terminal.endSyncOutput() catch {};

        const new_header_height = self.header.height();
        const header_height_changed = self.header_height != new_header_height;
        self.header_height = new_header_height;
        const footer_height: u16 = if (self.footer_visible) 1 else 0;
        const command_height: u16 = if (self.command_input.visible) 1 else 0;

        // Clear on resize OR header size change (compact toggle)
        if (size_changed or header_height_changed) {
            try self.terminal.clear();
        }

        // Update header and footer themes if we're previewing a theme
        const effective_theme = if (self.themes_view.preview_theme) |preview| preview else self.theme;
        self.header.setTheme(effective_theme);
        self.footer.setTheme(effective_theme);

        // Render header with hints from current view
        if (size.height >= self.header_height) {
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

        // Render current view
        if (body_height > 0) {
            if (self.view_manager.getCurrentView()) |current_view| {
                try current_view.render(&self.terminal, 0, body_start, size.width, body_height);
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
                if (self.k8s_service.isConnected()) {
                    self.footer.setStatus(null);
                } else {
                    self.footer.setStatus("Not connected to Kubernetes cluster");
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
        self.prev_width = size.width;
        self.prev_height = size.height;
        self.dirty = false;
    }

    fn handleKey(self: *App, key: Key) !void {
        // Handle command input first
        if (self.command_input.visible) {
            switch (key) {
                .char => |c| {
                    if (c >= 32 and c <= 126) {
                        try self.command_input.addChar(c);
                        self.dirty = true;
                    }
                },
                .backspace => {
                    self.command_input.backspace();
                    self.dirty = true;
                },
                .enter => {
                    // Process command
                    const cmd_text = self.command_input.getCommand();
                    const prompt = self.command_input.prompt;

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
                        // Execute command
                        var ctx = Command.CommandContext{
                            .allocator = self.allocator,
                            .view_manager = &self.view_manager,
                            .data = self,
                        };
                        _ = try self.command_registry.execute(cmd_text, &ctx);
                    }

                    self.command_input.hide();
                    self.dirty = true;
                },
                .escape => {
                    self.command_input.hide();
                    self.dirty = true;
                },
                else => {},
            }
            return;
        }

        // Handle global keys
        switch (key) {
            .char => |c| switch (c) {
                'h' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'j' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'k' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'l' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'g' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
                'G' => {
                    // Pass to current view
                    if (self.view_manager.getCurrentView()) |current_view| {
                        const result = try current_view.handleKey(key);
                        if (result == .handled) self.dirty = true;
                    }
                },
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
                    self.dirty = true;
                }
            },
            .ctrl_c => {
                // Ctrl+C doesn't exit in k9s, use :q command instead
            },
            .ctrl_d => {
                // Ctrl+D: delete resource (k9s compat)
                if (self.view_manager.getCurrentView()) |_| {
                    self.handleDeleteRequest() catch |err| {
                        Logger.err("Delete request failed: {any}", .{err});
                    };
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
                // Pass to current view
                if (self.view_manager.getCurrentView()) |current_view| {
                    const result = try current_view.handleKey(key);
                    if (result == .handled) self.dirty = true;
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
                    try self.view_manager.pushView(self.help_view.createView());
                }
                self.dirty = true;
            },
            .colon => {
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
        }
    }

    /// Central handler for view KeyResult values
    fn handleViewResult(self: *App, result: View.KeyResult, current_view: View, key: Key) !void {
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
                self.showLogsView() catch |err| {
                    Logger.err("Failed to show logs view: {any}", .{err});
                };
            },
            .request_delete => {
                self.handleDeleteRequest() catch |err| {
                    Logger.err("Delete request failed: {any}", .{err});
                };
            },
        }
    }

    /// Map current_primary_view to ResourceType
    fn currentResourceType(self: *App) ?ResourceType {
        return switch (self.current_primary_view) {
            .pods => .pods,
            .deployments => .deployments,
            .services => .services,
            .namespaces => .namespaces,
            .nodes => .nodes,
            .statefulsets => .statefulsets,
            .daemonsets => .daemonsets,
            .replicasets => .replicasets,
            .jobs => .jobs,
            .cronjobs => .cronjobs,
            .configmaps => .configmaps,
            .secrets => .secrets,
            .persistentvolumes => .persistentvolumes,
            .persistentvolumeclaims => .persistentvolumeclaims,
            .ingresses => .ingresses,
            .networkpolicies => .networkpolicies,
            .serviceaccounts => .serviceaccounts,
            .roles => .roles,
            .rolebindings => .rolebindings,
            .clusterroles => .clusterroles,
            .clusterrolebindings => .clusterrolebindings,
            .events => .events,
            .resourcequotas => .resourcequotas,
            .limitranges => .limitranges,
            .poddisruptionbudgets => .poddisruptionbudgets,
            .hpa => .hpa,
            .contexts => .contexts,
            .themes => null,
        };
    }

    /// Get selected resource info from the current primary view
    fn getSelectedResourceFromCurrentView(self: *App) ?ResourceInfo {
        return switch (self.current_primary_view) {
            .pods => self.pods_view.getSelectedResourceInfo(),
            .deployments => self.deployments_view.getSelectedResourceInfo(),
            .services => self.services_view.getSelectedResourceInfo(),
            .namespaces => self.namespaces_view.getSelectedResourceInfo(),
            .nodes => self.nodes_view.getSelectedResourceInfo(),
            .statefulsets => self.statefulsets_view.getSelectedResourceInfo(),
            .daemonsets => self.daemonsets_view.getSelectedResourceInfo(),
            .replicasets => self.replicasets_view.getSelectedResourceInfo(),
            .jobs => self.jobs_view.getSelectedResourceInfo(),
            .cronjobs => self.cronjobs_view.getSelectedResourceInfo(),
            .configmaps => self.configmaps_view.getSelectedResourceInfo(),
            .secrets => self.secrets_view.getSelectedResourceInfo(),
            .persistentvolumes => self.persistentvolumes_view.getSelectedResourceInfo(),
            .persistentvolumeclaims => self.persistentvolumeclaims_view.getSelectedResourceInfo(),
            .ingresses => self.ingresses_view.getSelectedResourceInfo(),
            .networkpolicies => self.networkpolicies_view.getSelectedResourceInfo(),
            .serviceaccounts => self.serviceaccounts_view.getSelectedResourceInfo(),
            .roles => self.roles_view.getSelectedResourceInfo(),
            .rolebindings => self.rolebindings_view.getSelectedResourceInfo(),
            .clusterroles => self.clusterroles_view.getSelectedResourceInfo(),
            .clusterrolebindings => self.clusterrolebindings_view.getSelectedResourceInfo(),
            .events => self.events_view.getSelectedResourceInfo(),
            .resourcequotas => self.resourcequotas_view.getSelectedResourceInfo(),
            .limitranges => self.limitranges_view.getSelectedResourceInfo(),
            .poddisruptionbudgets => self.poddisruptionbudgets_view.getSelectedResourceInfo(),
            .hpa => self.hpa_view.getSelectedResourceInfo(),
            .contexts => null,
            .themes => null,
        };
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

        // Set content on detail view
        const title = if (describe)
            try std.fmt.allocPrint(self.allocator, "Describe {s}/{s}", .{ resource_type.resourceName(), info.name })
        else
            try std.fmt.allocPrint(self.allocator, "YAML {s}/{s}", .{ resource_type.resourceName(), info.name });
        defer self.allocator.free(title);

        if (describe) {
            try self.detail_view.setContentDescribe(json_data, title);
        } else {
            try self.detail_view.setContentJson(json_data, title);
        }

        // Push detail view as sub-view
        try self.view_manager.pushView(self.detail_view.createView());
        self.dirty = true;
    }

    /// Show logs view for selected pod
    fn showLogsView(self: *App) !void {
        if (self.current_primary_view != .pods) return;

        const info = self.pods_view.getSelectedResourceInfo() orelse return;

        // Fetch logs from K8s API
        const log_data = self.k8s_service.getPodLogs(info.name, info.namespace) catch |err| {
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
    fn handleDeleteRequest(self: *App) !void {
        const resource_type = self.currentResourceType() orelse return;
        const info = self.getSelectedResourceFromCurrentView() orelse return;

        // Store delete state
        self.clearDeleteState();
        self.delete_pending = true;
        self.delete_resource_name = try self.allocator.dupe(u8, info.name);
        self.delete_resource_namespace = try self.allocator.dupe(u8, info.namespace);
        self.delete_resource_type = resource_type;

        // Show confirmation prompt
        const prompt_text = try std.fmt.allocPrint(self.allocator, "Delete {s}/{s}? [y/n]: ", .{ resource_type.resourceName(), info.name });
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

        self.k8s_service.deleteResource(resource_type, name, namespace) catch |err| {
            Logger.err("Failed to delete {s}/{s}: {any}", .{ resource_type.resourceName(), name, err });
            self.footer.setStatus("Delete failed");
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
        if (self.delete_resource_name) |n| self.allocator.free(n);
        if (self.delete_resource_namespace) |n| self.allocator.free(n);
        self.delete_resource_name = null;
        self.delete_resource_namespace = null;
        self.delete_resource_type = null;
    }

    /// Apply filter to the current view
    fn applyFilterToCurrentView(self: *App, filter: []const u8) !void {
        switch (self.current_primary_view) {
            .pods => try self.pods_view.applyFilter(filter),
            .themes => try self.themes_view.applyFilter(filter),
            .deployments => try self.deployments_view.applyFilter(filter),
            .services => try self.services_view.applyFilter(filter),
            .namespaces => try self.namespaces_view.applyFilter(filter),
            .nodes => try self.nodes_view.applyFilter(filter),
            .statefulsets => try self.statefulsets_view.applyFilter(filter),
            .daemonsets => try self.daemonsets_view.applyFilter(filter),
            .replicasets => try self.replicasets_view.applyFilter(filter),
            .jobs => try self.jobs_view.applyFilter(filter),
            .cronjobs => try self.cronjobs_view.applyFilter(filter),
            .configmaps => try self.configmaps_view.applyFilter(filter),
            .secrets => try self.secrets_view.applyFilter(filter),
            .persistentvolumes => try self.persistentvolumes_view.applyFilter(filter),
            .persistentvolumeclaims => try self.persistentvolumeclaims_view.applyFilter(filter),
            .ingresses => try self.ingresses_view.applyFilter(filter),
            .networkpolicies => try self.networkpolicies_view.applyFilter(filter),
            .serviceaccounts => try self.serviceaccounts_view.applyFilter(filter),
            .roles => try self.roles_view.applyFilter(filter),
            .rolebindings => try self.rolebindings_view.applyFilter(filter),
            .clusterroles => try self.clusterroles_view.applyFilter(filter),
            .clusterrolebindings => try self.clusterrolebindings_view.applyFilter(filter),
            .events => try self.events_view.applyFilter(filter),
            .resourcequotas => try self.resourcequotas_view.applyFilter(filter),
            .limitranges => try self.limitranges_view.applyFilter(filter),
            .poddisruptionbudgets => try self.poddisruptionbudgets_view.applyFilter(filter),
            .hpa => try self.hpa_view.applyFilter(filter),
            .contexts => {},
        }
        self.dirty = true;
    }

    /// Check if current view has an active filter and clear it
    fn clearCurrentViewFilter(self: *App) !bool {
        return switch (self.current_primary_view) {
            .pods => if (self.pods_view.filter_text.len > 0) {
                try self.pods_view.applyFilter("");
                return true;
            } else false,
            .themes => if (self.themes_view.filter_text.len > 0) {
                try self.themes_view.applyFilter("");
                return true;
            } else false,
            .deployments => if (self.deployments_view.filter_text.len > 0) {
                try self.deployments_view.applyFilter("");
                return true;
            } else false,
            .services => if (self.services_view.filter_text.len > 0) {
                try self.services_view.applyFilter("");
                return true;
            } else false,
            .namespaces => if (self.namespaces_view.filter_text.len > 0) {
                try self.namespaces_view.applyFilter("");
                return true;
            } else false,
            .nodes => if (self.nodes_view.filter_text.len > 0) {
                try self.nodes_view.applyFilter("");
                return true;
            } else false,
            .statefulsets => if (self.statefulsets_view.filter_text.len > 0) {
                try self.statefulsets_view.applyFilter("");
                return true;
            } else false,
            .daemonsets => if (self.daemonsets_view.filter_text.len > 0) {
                try self.daemonsets_view.applyFilter("");
                return true;
            } else false,
            .replicasets => if (self.replicasets_view.filter_text.len > 0) {
                try self.replicasets_view.applyFilter("");
                return true;
            } else false,
            .jobs => if (self.jobs_view.filter_text.len > 0) {
                try self.jobs_view.applyFilter("");
                return true;
            } else false,
            .cronjobs => if (self.cronjobs_view.filter_text.len > 0) {
                try self.cronjobs_view.applyFilter("");
                return true;
            } else false,
            .configmaps => if (self.configmaps_view.filter_text.len > 0) {
                try self.configmaps_view.applyFilter("");
                return true;
            } else false,
            .secrets => if (self.secrets_view.filter_text.len > 0) {
                try self.secrets_view.applyFilter("");
                return true;
            } else false,
            .persistentvolumes => if (self.persistentvolumes_view.filter_text.len > 0) {
                try self.persistentvolumes_view.applyFilter("");
                return true;
            } else false,
            .persistentvolumeclaims => if (self.persistentvolumeclaims_view.filter_text.len > 0) {
                try self.persistentvolumeclaims_view.applyFilter("");
                return true;
            } else false,
            .ingresses => if (self.ingresses_view.filter_text.len > 0) {
                try self.ingresses_view.applyFilter("");
                return true;
            } else false,
            .networkpolicies => if (self.networkpolicies_view.filter_text.len > 0) {
                try self.networkpolicies_view.applyFilter("");
                return true;
            } else false,
            .serviceaccounts => if (self.serviceaccounts_view.filter_text.len > 0) {
                try self.serviceaccounts_view.applyFilter("");
                return true;
            } else false,
            .roles => if (self.roles_view.filter_text.len > 0) {
                try self.roles_view.applyFilter("");
                return true;
            } else false,
            .rolebindings => if (self.rolebindings_view.filter_text.len > 0) {
                try self.rolebindings_view.applyFilter("");
                return true;
            } else false,
            .clusterroles => if (self.clusterroles_view.filter_text.len > 0) {
                try self.clusterroles_view.applyFilter("");
                return true;
            } else false,
            .clusterrolebindings => if (self.clusterrolebindings_view.filter_text.len > 0) {
                try self.clusterrolebindings_view.applyFilter("");
                return true;
            } else false,
            .events => if (self.events_view.filter_text.len > 0) {
                try self.events_view.applyFilter("");
                return true;
            } else false,
            .resourcequotas => if (self.resourcequotas_view.filter_text.len > 0) {
                try self.resourcequotas_view.applyFilter("");
                return true;
            } else false,
            .limitranges => if (self.limitranges_view.filter_text.len > 0) {
                try self.limitranges_view.applyFilter("");
                return true;
            } else false,
            .poddisruptionbudgets => if (self.poddisruptionbudgets_view.filter_text.len > 0) {
                try self.poddisruptionbudgets_view.applyFilter("");
                return true;
            } else false,
            .hpa => if (self.hpa_view.filter_text.len > 0) {
                try self.hpa_view.applyFilter("");
                return true;
            } else false,
            .contexts => false,
        };
    }

    /// Refresh the current view
    fn refreshCurrentView(self: *App) void {
        switch (self.current_primary_view) {
            .pods => self.pods_view.refresh() catch |err| {
                Logger.err("Failed to refresh pods: {any}", .{err});
            },
            .deployments => self.deployments_view.refresh() catch |err| {
                Logger.err("Failed to refresh deployments: {any}", .{err});
            },
            .services => self.services_view.refresh() catch |err| {
                Logger.err("Failed to refresh services: {any}", .{err});
            },
            .namespaces => self.namespaces_view.refresh() catch |err| {
                Logger.err("Failed to refresh namespaces: {any}", .{err});
            },
            .nodes => self.nodes_view.refresh() catch |err| {
                Logger.err("Failed to refresh nodes: {any}", .{err});
            },
            .statefulsets => self.statefulsets_view.refresh() catch |err| {
                Logger.err("Failed to refresh statefulsets: {any}", .{err});
            },
            .daemonsets => self.daemonsets_view.refresh() catch |err| {
                Logger.err("Failed to refresh daemonsets: {any}", .{err});
            },
            .replicasets => self.replicasets_view.refresh() catch |err| {
                Logger.err("Failed to refresh replicasets: {any}", .{err});
            },
            .jobs => self.jobs_view.refresh() catch |err| {
                Logger.err("Failed to refresh jobs: {any}", .{err});
            },
            .cronjobs => self.cronjobs_view.refresh() catch |err| {
                Logger.err("Failed to refresh cronjobs: {any}", .{err});
            },
            .configmaps => self.configmaps_view.refresh() catch |err| {
                Logger.err("Failed to refresh configmaps: {any}", .{err});
            },
            .secrets => self.secrets_view.refresh() catch |err| {
                Logger.err("Failed to refresh secrets: {any}", .{err});
            },
            .persistentvolumes => self.persistentvolumes_view.refresh() catch |err| {
                Logger.err("Failed to refresh persistentvolumes: {any}", .{err});
            },
            .persistentvolumeclaims => self.persistentvolumeclaims_view.refresh() catch |err| {
                Logger.err("Failed to refresh persistentvolumeclaims: {any}", .{err});
            },
            .ingresses => self.ingresses_view.refresh() catch |err| {
                Logger.err("Failed to refresh ingresses: {any}", .{err});
            },
            .networkpolicies => self.networkpolicies_view.refresh() catch |err| {
                Logger.err("Failed to refresh networkpolicies: {any}", .{err});
            },
            .serviceaccounts => self.serviceaccounts_view.refresh() catch |err| {
                Logger.err("Failed to refresh serviceaccounts: {any}", .{err});
            },
            .roles => self.roles_view.refresh() catch |err| {
                Logger.err("Failed to refresh roles: {any}", .{err});
            },
            .rolebindings => self.rolebindings_view.refresh() catch |err| {
                Logger.err("Failed to refresh rolebindings: {any}", .{err});
            },
            .clusterroles => self.clusterroles_view.refresh() catch |err| {
                Logger.err("Failed to refresh clusterroles: {any}", .{err});
            },
            .clusterrolebindings => self.clusterrolebindings_view.refresh() catch |err| {
                Logger.err("Failed to refresh clusterrolebindings: {any}", .{err});
            },
            .events => self.events_view.refresh() catch |err| {
                Logger.err("Failed to refresh events: {any}", .{err});
            },
            .resourcequotas => self.resourcequotas_view.refresh() catch |err| {
                Logger.err("Failed to refresh resourcequotas: {any}", .{err});
            },
            .limitranges => self.limitranges_view.refresh() catch |err| {
                Logger.err("Failed to refresh limitranges: {any}", .{err});
            },
            .poddisruptionbudgets => self.poddisruptionbudgets_view.refresh() catch |err| {
                Logger.err("Failed to refresh poddisruptionbudgets: {any}", .{err});
            },
            .hpa => self.hpa_view.refresh() catch |err| {
                Logger.err("Failed to refresh hpa: {any}", .{err});
            },
            .contexts => self.contexts_view.refresh() catch |err| {
                Logger.err("Failed to refresh contexts: {any}", .{err});
            },
            .themes => {},
        }
        self.dirty = true;
    }

    fn saveThemeToConfig(self: *App, theme_name: []const u8) !void {
        Logger.info("Changing theme to: {s}", .{theme_name});

        const xdg = @import("core/xdg.zig");
        const paths = try xdg.ensurePaths();

        // Read existing config or create new one
        const existing_content = std.fs.cwd().readFileAlloc(
            self.allocator,
            paths.config_file,
            1024 * 1024,
        ) catch "";
        defer if (existing_content.len > 0) self.allocator.free(existing_content);

        // Build new config with updated theme
        var new_config = try std.ArrayList(u8).initCapacity(self.allocator, 1024);
        defer new_config.deinit(self.allocator);

        var found_theme_line = false;
        var in_ui_section = false;

        var lines = std.mem.splitScalar(u8, existing_content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Check for ui section
            if (std.mem.indexOf(u8, trimmed, "ui:")) |_| {
                in_ui_section = true;
                try new_config.appendSlice(self.allocator, line);
                try new_config.append(self.allocator, '\n');
                continue;
            }

            // Update theme line if in ui section
            if (in_ui_section) {
                if (std.mem.indexOf(u8, trimmed, "theme:")) |_| {
                    const theme_line = try std.fmt.allocPrint(self.allocator, "    theme: {s}\n", .{theme_name});
                    defer self.allocator.free(theme_line);
                    try new_config.appendSlice(self.allocator, theme_line);
                    found_theme_line = true;
                    continue;
                }
            }

            // Check if we left ui section
            if (in_ui_section and trimmed.len > 0 and trimmed[0] != ' ') {
                // Add theme line if not found yet
                if (!found_theme_line) {
                    const theme_line = try std.fmt.allocPrint(self.allocator, "    theme: {s}\n", .{theme_name});
                    defer self.allocator.free(theme_line);
                    try new_config.appendSlice(self.allocator, theme_line);
                    found_theme_line = true;
                }
                in_ui_section = false;
            }

            try new_config.appendSlice(self.allocator, line);
            try new_config.append(self.allocator, '\n');
        }

        // If no config existed, create minimal one
        if (existing_content.len == 0) {
            const default_config = try std.fmt.allocPrint(self.allocator, "c3s:\n  ui:\n    compact: false\n    theme: {s}\n", .{theme_name});
            defer self.allocator.free(default_config);
            try new_config.appendSlice(self.allocator, default_config);
        } else if (!found_theme_line) {
            // Config exists but no theme line, append it
            const theme_line = try std.fmt.allocPrint(self.allocator, "    theme: {s}\n", .{theme_name});
            defer self.allocator.free(theme_line);
            try new_config.appendSlice(self.allocator, theme_line);
        }

        // Write config file
        try std.fs.cwd().writeFile(.{
            .sub_path = paths.config_file,
            .data = new_config.items,
        });

        Logger.info("Theme saved to config successfully: {s}", .{theme_name});

        // Update current theme name
        self.allocator.free(self.current_theme_name);
        self.current_theme_name = try self.allocator.dupe(u8, theme_name);

        Logger.info("Current theme updated in memory: {s}", .{self.current_theme_name});
    }
};

// Command implementations
fn quitCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    app.running = false;
    Logger.info("Quit command executed", .{});
}

fn themesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    // Don't push - replace the root view with themes view
    if (ctx.view_manager.getDepth() == 1) {
        // We're at root level, switch primary view
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.themes_view.createView());
        app.current_primary_view = .themes;
    }
    Logger.info("Themes command executed", .{});
}

fn podsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    // Switch to pods view
    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.pods_view.createView());
        app.current_primary_view = .pods;
    }
    Logger.info("Pods command executed", .{});
}

fn deploymentsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.deployments_view.createView());
        app.current_primary_view = .deployments;
    }
    Logger.info("Deployments command executed", .{});
}

fn servicesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.services_view.createView());
        app.current_primary_view = .services;
    }
    Logger.info("Services command executed", .{});
}

fn namespacesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.namespaces_view.createView());
        app.current_primary_view = .namespaces;
    }
    Logger.info("Namespaces command executed", .{});
}

fn nodesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.nodes_view.createView());
        app.current_primary_view = .nodes;
    }
    Logger.info("Nodes command executed", .{});
}

fn helpCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    // Toggle help view - don't stack it!
    if (ctx.view_manager.isViewActive("help")) {
        Logger.info("Help command: closing help view", .{});
        _ = ctx.view_manager.popView();
    } else {
        Logger.info("Help command: opening help view", .{});
        try ctx.view_manager.pushView(app.help_view.createView());
    }
}

fn selectThemeCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    const selected_theme = app.themes_view.getSelectedThemeName();
    try app.saveThemeToConfig(selected_theme);
    try app.themes_view.setCurrentTheme(selected_theme);
    Logger.info("Theme selected: {s}", .{selected_theme});
}

fn statefulsetsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.statefulsets_view.createView());
        app.current_primary_view = .statefulsets;
    }
    Logger.info("StatefulSets command executed", .{});
}

fn daemonsetsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.daemonsets_view.createView());
        app.current_primary_view = .daemonsets;
    }
    Logger.info("DaemonSets command executed", .{});
}

fn replicasetsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.replicasets_view.createView());
        app.current_primary_view = .replicasets;
    }
    Logger.info("ReplicaSets command executed", .{});
}

fn jobsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.jobs_view.createView());
        app.current_primary_view = .jobs;
    }
    Logger.info("Jobs command executed", .{});
}

fn cronjobsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.cronjobs_view.createView());
        app.current_primary_view = .cronjobs;
    }
    Logger.info("CronJobs command executed", .{});
}

fn configmapsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.configmaps_view.createView());
        app.current_primary_view = .configmaps;
    }
    Logger.info("ConfigMaps command executed", .{});
}

fn secretsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.secrets_view.createView());
        app.current_primary_view = .secrets;
    }
    Logger.info("Secrets command executed", .{});
}

fn persistentvolumesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.persistentvolumes_view.createView());
        app.current_primary_view = .persistentvolumes;
    }
    Logger.info("PersistentVolumes command executed", .{});
}

fn persistentvolumeclaimsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.persistentvolumeclaims_view.createView());
        app.current_primary_view = .persistentvolumeclaims;
    }
    Logger.info("PersistentVolumeClaims command executed", .{});
}

fn ingressesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.ingresses_view.createView());
        app.current_primary_view = .ingresses;
    }
    Logger.info("Ingresses command executed", .{});
}

fn networkpoliciesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.networkpolicies_view.createView());
        app.current_primary_view = .networkpolicies;
    }
    Logger.info("NetworkPolicies command executed", .{});
}

fn serviceaccountsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.serviceaccounts_view.createView());
        app.current_primary_view = .serviceaccounts;
    }
    Logger.info("ServiceAccounts command executed", .{});
}

fn rolesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.roles_view.createView());
        app.current_primary_view = .roles;
    }
    Logger.info("Roles command executed", .{});
}

fn rolebindingsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.rolebindings_view.createView());
        app.current_primary_view = .rolebindings;
    }
    Logger.info("RoleBindings command executed", .{});
}

fn clusterrolesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.clusterroles_view.createView());
        app.current_primary_view = .clusterroles;
    }
    Logger.info("ClusterRoles command executed", .{});
}

fn clusterrolebindingsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.clusterrolebindings_view.createView());
        app.current_primary_view = .clusterrolebindings;
    }
    Logger.info("ClusterRoleBindings command executed", .{});
}

fn eventsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.events_view.createView());
        app.current_primary_view = .events;
    }
    Logger.info("Events command executed", .{});
}

fn resourcequotasCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.resourcequotas_view.createView());
        app.current_primary_view = .resourcequotas;
    }
    Logger.info("ResourceQuotas command executed", .{});
}

fn limitrangesCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.limitranges_view.createView());
        app.current_primary_view = .limitranges;
    }
    Logger.info("LimitRanges command executed", .{});
}

fn poddisruptionbudgetsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.poddisruptionbudgets_view.createView());
        app.current_primary_view = .poddisruptionbudgets;
    }
    Logger.info("PodDisruptionBudgets command executed", .{});
}

fn hpaCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.hpa_view.createView());
        app.current_primary_view = .hpa;
    }
    Logger.info("HorizontalPodAutoscalers command executed", .{});
}

fn contextsCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));

    if (ctx.view_manager.getDepth() == 1) {
        _ = ctx.view_manager.popView();
        try ctx.view_manager.pushView(app.contexts_view.createView());
        app.current_primary_view = .contexts;
    }
    Logger.info("Contexts command executed", .{});
}

fn notImplementedCommand(ctx: *Command.CommandContext) !void {
    _ = ctx;
    Logger.warn("Command not implemented yet", .{});
    // TODO: Show "Not implemented" message to user
}

// SIGWINCH signal handler for terminal resize
fn handleResize(_: c_int) callconv(.c) void {
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
