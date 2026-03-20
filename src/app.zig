const std = @import("std");
const posix = std.posix;
const terminal = @import("core/terminal.zig");
const Terminal = terminal.Terminal;
const Key = terminal.Key;
const Header = @import("ui/header.zig").Header;
const Footer = @import("ui/footer.zig").Footer;
const CommandInput = @import("ui/command_input.zig").CommandInput;
const Theme = theme_loader;
const BoxDrawing = @import("ui/box_drawing.zig");
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

// View imports - generic resource views from single config file
const rc = @import("view/resource_configs.zig");
const PodsView = @import("view/pods_view.zig").PodsView;
const DeploymentsView = rc.DeploymentsView;
const ServicesView = rc.ServicesView;
const NamespacesView = @import("view/namespaces_view.zig").NamespacesView;
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
const ContextsView = @import("view/contexts_view.zig").ContextsView;
const ThemesView = @import("view/themes_view.zig").ThemesView;
const HelpView = @import("view/help_view.zig").HelpView;
const ViewType = @import("viewmodel/keybindings_vm.zig").ViewType;
const DetailView = @import("view/detail_view.zig").DetailView;
const LogsView = @import("view/logs_view.zig").LogsView;
const AuthorizationView = @import("view/authorization_view.zig").AuthorizationView;

// Service imports
const klient = @import("klient");
const k8s_service_mod = @import("services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const ResourceType = k8s_service_mod.ResourceType;
const view_mod = @import("viewmodel/view.zig");
const ResourceInfo = view_mod.ResourceInfo;

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
    needs_connect: bool = true, // deferred K8s connection on first render
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
    endpoints_view: *EndpointsView,
    storageclasses_view: *StorageClassesView,
    contexts_view: *ContextsView,

    // UI views
    themes_view: *ThemesView,
    help_view: *HelpView,
    detail_view: *DetailView,
    logs_view: *LogsView,
    authorization_view: *AuthorizationView,

    // Delete confirmation state
    delete_pending: bool = false,
    delete_resource_name: ?[]u8 = null,
    delete_resource_namespace: ?[]u8 = null,
    delete_resource_type: ?ResourceType = null,

    // Track which primary view is active (matches view getName() return value)
    current_view_name: []const u8 = "pods",

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
            contexts_view: *ContextsView = undefined,
            authorization_view: *AuthorizationView = undefined,
        } = .{};
        inline for (k8s_view_types) |entry| {
            @field(app_views, entry[0]) = try allocator.create(entry[1]);
        }
        const pods_view = try allocator.create(PodsView);

        // Initialize UI views (these don't need k8s_service)

        const themes_view = try allocator.create(ThemesView);
        themes_view.* = try ThemesView.init(allocator, ui_config.ui.theme, theme);
        errdefer themes_view.deinit();

        const help_view = try allocator.create(HelpView);
        help_view.* = try HelpView.init(allocator, theme);
        errdefer help_view.deinit();

        const detail_view = try allocator.create(DetailView);
        detail_view.* = try DetailView.init(allocator, theme);
        errdefer detail_view.deinit();

        const logs_view = try allocator.create(LogsView);
        logs_view.* = try LogsView.init(allocator, theme);
        errdefer logs_view.deinit();

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
            .contexts_view = app_views.contexts_view,
            .themes_view = themes_view,
            .help_view = help_view,
            .detail_view = detail_view,
            .logs_view = logs_view,
            .authorization_view = app_views.authorization_view,
        };

        // Initialize all K8s resource views (comptime-generated loop)
        // Must happen AFTER k8s_service is moved into the App struct for stable pointer
        pods_view.* = try PodsView.init(allocator, theme, app.k8s_service);
        inline for (k8s_view_types) |entry| {
            @field(app, entry[0]).* = try entry[1].init(allocator, theme, app.k8s_service);
        }

        // Register commands
        try app.registerCommands();

        // Push initial view (PodsView is the reference implementation with all features working)
        try app.view_manager.pushView(app.pods_view.createView());

        return app;
    }

    pub fn deinit(self: *App) void {
        // Clean up all K8s views (comptime-generated loop)
        inline for (k8s_view_types) |entry| {
            @field(self, entry[0]).deinit();
            self.allocator.destroy(@field(self, entry[0]));
        }

        // Clean up special views
        self.pods_view.deinit();
        self.allocator.destroy(self.pods_view);
        self.themes_view.deinit();
        self.allocator.destroy(self.themes_view);
        self.help_view.deinit();
        self.allocator.destroy(self.help_view);
        self.detail_view.deinit();
        self.allocator.destroy(self.detail_view);
        self.logs_view.deinit();
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

        // Internal commands
        try self.command_registry.register("select_theme", Command{ .name = "select_theme", .execute = selectThemeCommand });
    }

    pub fn run(self: *App) !void {
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
            self.terminal.stdout,
        );
        defer if (palette_applied) {
            color256.resetPalette(self.terminal.stdout, 16, 256) catch {};
        };

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

            // Deferred K8s connection — runs after first render so UI appears instantly
            if (self.needs_connect) {
                self.needs_connect = false;
                self.k8s_service.connect(self.config.context) catch |err| {
                    Logger.warn("Failed to connect to Kubernetes: {}. Continuing without cluster connection.", .{err});
                };
                // Update header with connection info
                const cluster_info = self.k8s_service.getClusterInfo();
                self.header.updateClusterInfo(cluster_info.context, cluster_info.cluster, cluster_info.user) catch {};
                self.header.updateK8sVersion(self.k8s_service.getServerVersion()) catch {};
                // Fetch node metrics for header CPU/MEM
                self.updateHeaderMetrics();
                // Refresh the active view to load data
                if (self.view_manager.getCurrentView()) |current_view| {
                    current_view.refresh() catch {};
                }
                self.dirty = true;
            }

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

        // Update header with current cluster info and server version
        // Only update header with cluster info after connection has been attempted
        if (self.k8s_service.hasAttemptedConnect()) {
            const cluster_info = self.k8s_service.getClusterInfo();
            self.header.updateClusterInfo(cluster_info.context, cluster_info.cluster, cluster_info.user) catch {};
            self.header.updateK8sVersion(self.k8s_service.getServerVersion()) catch {};
        }

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

        // Render current view inside a box border
        if (body_height > 0) {
            if (self.view_manager.getCurrentView()) |current_view| {
                // Draw box border at framework level
                const view_name = current_view.getName();
                self.footer.current_resource = view_name;
                try BoxDrawing.Box.createBox(&self.terminal, 0, body_start, size.width, body_height, effective_theme.proc_box, effective_theme.main_bg, view_name, .rounded, effective_theme.main_fg, effective_theme.title_highlight);
                // Render view inside the box (inner coordinates)
                if (body_height > 2 and size.width > 4) {
                    const inner_x: u16 = 2; // 1 for border + 1 padding
                    const inner_y = body_start + 1;
                    const inner_w = size.width - 4; // 2 for borders + 2 padding
                    const inner_h = body_height - 2;

                    // Views that work without a cluster connection
                    const offline_ok = std.mem.eql(u8, view_name, "contexts") or
                        std.mem.eql(u8, view_name, "themes") or
                        std.mem.eql(u8, view_name, "help");

                    // Clear full box interior (including padding) to prevent artifacts
                    try self.terminal.clearRegion(1, inner_y, size.width - 2, inner_h);

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
                if (self.k8s_service.isConnected()) {
                    self.footer.setStatus(null);
                } else if (!self.k8s_service.hasAttemptedConnect()) {
                    self.footer.setStatus("Connecting...");
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
                // Ctrl+C doesn't exit, use :q command instead
            },
            .ctrl_d => {
                // Ctrl+D: delete resource
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
                    try self.help_view.setViewType(self.currentViewType());
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

                    // After selecting a namespace, push pods view on top
                    // Esc will pop back to namespaces view
                    if (result == .handled and std.mem.eql(u8, self.current_view_name, "namespaces")) {
                        try self.view_manager.pushView(self.pods_view.createView());
                        self.current_view_name = "pods";
                        self.dirty = true;
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

    /// Map current view name to ViewType for context-aware help
    fn currentViewType(self: *App) ViewType {
        return std.meta.stringToEnum(ViewType, self.current_view_name) orelse .pods;
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
        if (!std.mem.eql(u8, self.current_view_name, "pods")) return;

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

    /// Refresh the current view
    fn refreshCurrentView(self: *App) void {
        if (self.view_manager.getCurrentView()) |current| {
            current.refresh() catch |err| {
                Logger.err("Failed to refresh view: {any}", .{err});
            };
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

// ============================================================================
// Comptime-generated view command handlers
// ============================================================================
/// Comptime table mapping App field names to view types.
/// Used by init/deinit loops and command generation.
/// All views in this table take (allocator, theme, k8s_service) for init.
const k8s_view_types = .{
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
    .{ .field = "roles_view", .view_name = "roles", .aliases = &.{"roles"} },
    .{ .field = "rolebindings_view", .view_name = "rolebindings", .aliases = &.{"rolebindings"} },
    .{ .field = "clusterroles_view", .view_name = "clusterroles", .aliases = &.{"clusterroles"} },
    .{ .field = "clusterrolebindings_view", .view_name = "clusterrolebindings", .aliases = &.{"clusterrolebindings"} },
    .{ .field = "events_view", .view_name = "events", .aliases = &.{ "events", "ev" } },
    .{ .field = "resourcequotas_view", .view_name = "resourcequotas", .aliases = &.{"resourcequotas"} },
    .{ .field = "limitranges_view", .view_name = "limitranges", .aliases = &.{"limitranges"} },
    .{ .field = "poddisruptionbudgets_view", .view_name = "poddisruptionbudgets", .aliases = &.{ "poddisruptionbudgets", "pdb" } },
    .{ .field = "hpa_view", .view_name = "hpa", .aliases = &.{ "horizontalpodautoscalers", "hpa" } },
    .{ .field = "endpoints_view", .view_name = "endpoints", .aliases = &.{ "endpoints", "ep" } },
    .{ .field = "storageclasses_view", .view_name = "storageclasses", .aliases = &.{ "storageclasses", "sc" } },
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

fn selectThemeCommand(ctx: *Command.CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    const selected_theme = app.themes_view.getSelectedThemeName();
    try app.saveThemeToConfig(selected_theme);
    try app.themes_view.setCurrentTheme(selected_theme);
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
