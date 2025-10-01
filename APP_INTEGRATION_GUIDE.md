# App.zig Integration Guide

This guide shows how to integrate the new K8sService and views into app.zig.

## 🎯 Changes Needed

### 1. Add Imports
```zig
const K8sService = @import("services/k8s_service.zig").K8sService;
const DeploymentsView = @import("view/deployments_view.zig").DeploymentsView;
const ServicesView = @import("view/services_view.zig").ServicesView;
const NamespacesView = @import("view/namespaces_view.zig").NamespacesView;
const NodesView = @import("view/nodes_view.zig").NodesView;
```

### 2. Add Fields to App Struct
```zig
pub const App = struct {
    // Existing fields...
    allocator: std.mem.Allocator,
    terminal: Terminal,
    config: Config,
    theme: theme_loader.ThemeColors,
    
    // Add K8s service
    k8s_service: K8sService,
    
    // Add new views
    deployments_view: DeploymentsView,
    services_view: ServicesView,
    namespaces_view: NamespacesView,
    nodes_view: NodesView,
    
    // Existing views...
    pods_view: PodsView,
    themes_view: ThemesView,
    help_view: HelpView,
    
    // ... rest of fields
};
```

### 3. Update init() Method

```zig
pub fn init(allocator: std.mem.Allocator, cli_args: CliArgs) !App {
    // ... existing initialization code ...
    
    // Initialize K8s service
    var k8s_service = try K8sService.init(allocator);
    errdefer k8s_service.deinit();
    
    // Connect to cluster (with error handling)
    k8s_service.connect(cli_args.context) catch |err| {
        Logger.warn("Failed to connect to K8s cluster: {}", .{err});
        Logger.info("Continuing with fixture data", .{});
    };
    
    // Initialize new views with k8s_service
    var deployments_view = try DeploymentsView.init(allocator, &theme, &k8s_service);
    errdefer deployments_view.deinit();
    
    var services_view = try ServicesView.init(allocator, &theme, &k8s_service);
    errdefer services_view.deinit();
    
    var namespaces_view = try NamespacesView.init(allocator, &theme, &k8s_service);
    errdefer namespaces_view.deinit();
    
    var nodes_view = try NodesView.init(allocator, &theme, &k8s_service);
    errdefer nodes_view.deinit();
    
    // Update existing pods_view initialization (when refactored)
    // var pods_view = try PodsView.init(allocator, &theme, &k8s_service);
    
    return App{
        // ... existing fields ...
        .k8s_service = k8s_service,
        .deployments_view = deployments_view,
        .services_view = services_view,
        .namespaces_view = namespaces_view,
        .nodes_view = nodes_view,
        // ... rest of fields ...
    };
}
```

### 4. Update deinit() Method

```zig
pub fn deinit(self: *App) void {
    // Deinit new views
    self.nodes_view.deinit();
    self.namespaces_view.deinit();
    self.services_view.deinit();
    self.deployments_view.deinit();
    
    // Deinit K8s service
    self.k8s_service.deinit();
    
    // ... existing deinit code ...
}
```

### 5. Add Navigation Commands

```zig
fn registerCommands(self: *App) !void {
    var commands = &self.command_registry.commands;
    
    // Existing commands...
    try commands.put("quit", quitCommand);
    try commands.put("q", quitCommand);
    try commands.put("themes", themesCommand);
    try commands.put("skins", themesCommand);
    try commands.put("help", helpCommand);
    
    // Add new resource navigation commands
    try commands.put("deployments", deployCommand);
    try commands.put("deploy", deployCommand);
    try commands.put("services", servicesCommand);
    try commands.put("svc", servicesCommand);
    try commands.put("namespaces", namespacesCommand);
    try commands.put("ns", namespacesCommand);
    try commands.put("nodes", nodesCommand);
    try commands.put("no", nodesCommand);
    try commands.put("pods", podsCommand);
    try commands.put("po", podsCommand);
}

// Command implementations
fn deployCommand(ctx: *CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    try ctx.view_manager.pushView(app.deployments_view.createView());
}

fn servicesCommand(ctx: *CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    try ctx.view_manager.pushView(app.services_view.createView());
}

fn namespacesCommand(ctx: *CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    try ctx.view_manager.pushView(app.namespaces_view.createView());
}

fn nodesCommand(ctx: *CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    try ctx.view_manager.pushView(app.nodes_view.createView());
}

fn podsCommand(ctx: *CommandContext) !void {
    const app: *App = @ptrCast(@alignCast(ctx.data.?));
    try ctx.view_manager.pushView(app.pods_view.createView());
}
```

### 6. Update Header to Show Live Cluster Info

```zig
// In render() or wherever header is created
const cluster_info = self.k8s_service.getClusterInfo();

// Update header with real cluster data
var header = try Header.initWithData(
    self.allocator,
    &self.theme,
    .{
        .context = cluster_info.context,
        .cluster = cluster_info.cluster,
        .namespace = cluster_info.namespace,
        .connected = cluster_info.connected,
        // ... other fields ...
    },
);
```

## 🔑 Key Points

### Error Handling
- **Graceful degradation**: If K8s connection fails, continue with fixtures
- **User feedback**: Log warnings but don't crash
- **View-level errors**: Each view handles its own API errors

### Memory Management
- **errdefer**: Use errdefer for cleanup on init failure
- **deinit order**: Deinit views before service
- **Resource ownership**: K8sService owns the klient connection

### State Management
- **Namespace changes**: When user switches namespace in NamespacesView:
  1. K8sService.setCurrentNamespace() updates state
  2. All subsequent API calls use new namespace
  3. Other views automatically use new namespace on refresh

### View Lifecycle
1. Views initialized with k8s_service reference
2. Views load data on init via k8s_service
3. Views refresh data on 'r' key press
4. Views clean up on deinit

## 🧪 Testing Steps

### 1. Build Test
```bash
cd /Users/andreymaltsev/Development/alphasense/c3s
zig build
```

### 2. Connection Test (with kubectl proxy)
```bash
# Terminal 1: Start proxy
kubectl proxy

# Terminal 2: Run c3s
./zig-out/bin/c3s
```

### 3. Connection Test (with kubeconfig)
```bash
# Ensure you have a valid kubeconfig
kubectl config current-context

# Run c3s with context
./zig-out/bin/c3s --context <your-context>
```

### 4. Navigation Test
```
# In c3s:
:deployments   # Should show deployments
:services      # Should show services
:namespaces    # Should show namespaces
:nodes         # Should show nodes
:pods          # Should show pods (when updated)
```

### 5. Namespace Switch Test
```
# In c3s:
:namespaces
# Navigate to a namespace with j/k
<Enter>        # Switch namespace
:deployments   # Should show deployments in new namespace
```

## 🐛 Common Issues

### Issue: "Failed to connect to K8s cluster"
**Solution**: 
- Check kubeconfig exists: `~/.kube/config`
- Verify context: `kubectl config current-context`
- Try kubectl proxy method

### Issue: "Context not found"
**Solution**:
- List contexts: `kubectl config get-contexts`
- Use correct context name with `--context` flag

### Issue: Views show "Failed to list resources"
**Solution**:
- Check cluster connectivity: `kubectl get pods`
- Verify permissions for service account
- Check logs: `~/.local/state/c3s/c3s.log`

### Issue: Empty data in views
**Solution**:
- Ensure resources exist in cluster: `kubectl get <resource>`
- Check current namespace
- Try "0" key to toggle all-namespaces

## 📋 Checklist

Before marking integration complete:

- [ ] K8sService imported and initialized
- [ ] All 4 new views initialized with k8s_service
- [ ] Navigation commands registered for all views
- [ ] Error handling for connection failures
- [ ] Proper deinit order
- [ ] Build succeeds
- [ ] Can navigate between views
- [ ] Can switch namespaces
- [ ] Data displays correctly
- [ ] Refresh works ('r' key)
- [ ] Logs show proper cluster connection

## 🚀 Next Steps After Integration

1. Update PodsView to use K8sService
2. Add more resource types (ConfigMaps, Secrets, etc.)
3. Implement resource actions (delete, scale, etc.)
4. Add filtering across all views
5. Add log viewing for pods
6. Add exec/attach functionality

---

**Ready to integrate?** Follow this guide step by step in app.zig!




