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
const k8s = @import("k8s/index.zig");

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

// Service imports
const K8sService = @import("services/k8s_service.zig").K8sService;

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
    k8s_service: K8sService,

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

        // Initialize Kubernetes service
        var k8s_service = try K8sService.init(allocator);
        errdefer k8s_service.deinit();

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
        };

        // NOW initialize resource views with stable pointer to app.k8s_service
        // (This must happen AFTER k8s_service is moved into the App struct)
        pods_view.* = try PodsView.init(allocator, theme, &app.k8s_service);
        errdefer pods_view.cleanup();

        deployments_view.* = try DeploymentsView.init(allocator, theme, &app.k8s_service);
        errdefer deployments_view.deinit();

        services_view.* = try ServicesView.init(allocator, theme, &app.k8s_service);
        errdefer services_view.deinit();

        namespaces_view.* = try NamespacesView.init(allocator, theme, &app.k8s_service);
        errdefer namespaces_view.deinit();

        nodes_view.* = try NodesView.init(allocator, theme, &app.k8s_service);
        errdefer nodes_view.deinit();

        statefulsets_view.* = try StatefulSetsView.init(allocator, theme, &app.k8s_service);
        errdefer statefulsets_view.deinit();

        daemonsets_view.* = try DaemonSetsView.init(allocator, theme, &app.k8s_service);
        errdefer daemonsets_view.deinit();

        replicasets_view.* = try ReplicaSetsView.init(allocator, theme, &app.k8s_service);
        errdefer replicasets_view.deinit();

        jobs_view.* = try JobsView.init(allocator, theme, &app.k8s_service);
        errdefer jobs_view.deinit();

        cronjobs_view.* = try CronJobsView.init(allocator, theme, &app.k8s_service);
        errdefer cronjobs_view.deinit();

        configmaps_view.* = try ConfigMapsView.init(allocator, theme, &app.k8s_service);
        errdefer configmaps_view.deinit();

        secrets_view.* = try SecretsView.init(allocator, theme, &app.k8s_service);
        errdefer secrets_view.deinit();

        persistentvolumes_view.* = try PersistentVolumesView.init(allocator, theme, &app.k8s_service);
        errdefer persistentvolumes_view.deinit();

        persistentvolumeclaims_view.* = try PersistentVolumeClaimsView.init(allocator, theme, &app.k8s_service);
        errdefer persistentvolumeclaims_view.deinit();

        ingresses_view.* = try IngressesView.init(allocator, theme, &app.k8s_service);
        errdefer ingresses_view.deinit();

        networkpolicies_view.* = try NetworkPoliciesView.init(allocator, theme, &app.k8s_service);
        errdefer networkpolicies_view.deinit();

        serviceaccounts_view.* = try ServiceAccountsView.init(allocator, theme, &app.k8s_service);
        errdefer serviceaccounts_view.deinit();

        roles_view.* = try RolesView.init(allocator, theme, &app.k8s_service);
        errdefer roles_view.deinit();

        rolebindings_view.* = try RoleBindingsView.init(allocator, theme, &app.k8s_service);
        errdefer rolebindings_view.deinit();

        clusterroles_view.* = try ClusterRolesView.init(allocator, theme, &app.k8s_service);
        errdefer clusterroles_view.deinit();

        clusterrolebindings_view.* = try ClusterRoleBindingsView.init(allocator, theme, &app.k8s_service);
        errdefer clusterrolebindings_view.deinit();

        events_view.* = try EventsView.init(allocator, theme, &app.k8s_service);
        errdefer events_view.deinit();

        resourcequotas_view.* = try ResourceQuotasView.init(allocator, theme, &app.k8s_service);
        errdefer resourcequotas_view.deinit();

        limitranges_view.* = try LimitRangesView.init(allocator, theme, &app.k8s_service);
        errdefer limitranges_view.deinit();

        poddisruptionbudgets_view.* = try PodDisruptionBudgetsView.init(allocator, theme, &app.k8s_service);
        errdefer poddisruptionbudgets_view.deinit();

        hpa_view.* = try HPAView.init(allocator, theme, &app.k8s_service);
        errdefer hpa_view.deinit();

        contexts_view.* = try ContextsView.init(allocator, theme, &app.k8s_service);
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

        // Clean up MVVM components
        self.view_manager.deinit();
        self.command_registry.deinit();

        // Clean up Kubernetes service
        self.k8s_service.deinit();

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
            try self.renderIfNeeded();

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
                if (try self.terminal.readKey()) |key| {
                    try self.handleKey(key);
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
            const current_view = self.view_manager.getCurrentView() orelse unreachable;
            const hints = current_view.getHints();
            try self.header.render(&self.terminal, 0, 0, size.width, self.header_height, hints);
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
                        if (self.view_manager.getCurrentView()) |current_view| {
                            if (std.mem.eql(u8, current_view.getName(), "pods")) {
                                try self.pods_view.applyFilter(cmd_text);
                            } else if (std.mem.eql(u8, current_view.getName(), "themes")) {
                                try self.themes_view.applyFilter(cmd_text);
                            }
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
                    if (self.view_manager.getCurrentView()) |current_view| {
                        if (std.mem.eql(u8, current_view.getName(), "pods")) {
                            try self.pods_view.applyFilter("");
                            self.dirty = true;
                        } else if (std.mem.eql(u8, current_view.getName(), "themes")) {
                            try self.themes_view.applyFilter("");
                            self.dirty = true;
                        }
                    }
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
                        switch (result) {
                            .handled => self.dirty = true,
                            .not_handled => {},
                            .request_command_palette => {
                                // Check if we're in themes view and Enter was pressed
                                if (std.mem.eql(u8, current_view.getName(), "themes") and key == .enter) {
                                    // Execute theme selection directly
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
                        }
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
                // First, check if there's an active filter to clear
                var filter_cleared = false;
                if (self.view_manager.getCurrentView()) |current_view| {
                    if (std.mem.eql(u8, current_view.getName(), "pods")) {
                        if (self.pods_view.filter_text.len > 0) {
                            try self.pods_view.applyFilter("");
                            self.dirty = true;
                            filter_cleared = true;
                        }
                    } else if (std.mem.eql(u8, current_view.getName(), "themes")) {
                        if (self.themes_view.filter_text.len > 0) {
                            try self.themes_view.applyFilter("");
                            self.dirty = true;
                            filter_cleared = true;
                        }
                    }
                }

                // Only pop if:
                // 1. No filter was cleared AND
                // 2. We're in a pushed sub-view (depth > 1, like help view)
                // Primary views (pods, themes) are at depth 1, so they don't get popped
                if (!filter_cleared and self.view_manager.getDepth() > 1) {
                    _ = self.view_manager.popView();
                    self.dirty = true;
                }
            },
            .ctrl_c => {
                // Ctrl+C doesn't exit in k9s, use :q command instead
            },
            .ctrl_d => {
                // Ctrl+D reserved for delete action (k9s compat)
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
                    switch (result) {
                        .handled => self.dirty = true,
                        .not_handled => {},
                        .request_command_palette => {
                            // Check if we're in themes view and Enter was pressed
                            if (std.mem.eql(u8, current_view.getName(), "themes")) {
                                // Execute theme selection directly
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
                    }
                }
            },
            .unsupported => {},
            .ctrl_e => {
                self.header.toggleCompact();
                self.dirty = true;
            },
        }
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
