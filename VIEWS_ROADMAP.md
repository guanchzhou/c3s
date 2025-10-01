# C3S Views Implementation Roadmap

Based on k9s functionality analysis. Views organized by priority and category.

## Current Status

### ✅ Implemented (7 views)
1. ✅ **Pods** (`pods_view.zig`) - Using fixtures, needs real data
2. ✅ **Deployments** (`deployments_view.zig`) - Ready
3. ✅ **Services** (`services_view.zig`) - Ready
4. ✅ **Namespaces** (`namespaces_view.zig`) - Ready
5. ✅ **Nodes** (`nodes_view.zig`) - Ready
6. ✅ **Themes** (`themes_view.zig`) - Working
7. ✅ **Help** (`help.zig`) - Working

## Priority 1: Core Workload Resources (Next Sprint)

### Essential for MVP
1. **StatefulSets** (`:sts`) - Stateful workloads
   - File: `view/statefulsets_view.zig`
   - Service: `k8s_service.listStatefulSets()`
   - Columns: NAMESPACE, NAME, READY, AGE
   - Actions: describe, logs, delete, scale

2. **DaemonSets** (`:ds`) - Node-level workloads
   - File: `view/daemonsets_view.zig`
   - Service: `k8s_service.listDaemonSets()`
   - Columns: NAMESPACE, NAME, DESIRED, CURRENT, READY, UP-TO-DATE, AGE
   - Actions: describe, logs, delete

3. **ReplicaSets** (`:rs`) - Pod replication
   - File: `view/replicasets_view.zig`
   - Service: `k8s_service.listReplicaSets()`
   - Columns: NAMESPACE, NAME, DESIRED, CURRENT, READY, AGE
   - Actions: describe, delete, scale

4. **Jobs** (`:job`) - Batch workloads
   - File: `view/jobs_view.zig`
   - Service: `k8s_service.listJobs()`
   - Columns: NAMESPACE, NAME, COMPLETIONS, DURATION, AGE
   - Actions: describe, logs, delete

5. **CronJobs** (`:cj`) - Scheduled jobs
   - File: `view/cronjobs_view.zig`
   - Service: `k8s_service.listCronJobs()`
   - Columns: NAMESPACE, NAME, SCHEDULE, SUSPEND, ACTIVE, LAST-SCHEDULE
   - Actions: describe, suspend/resume, delete

## Priority 2: Configuration & Storage

### Configuration Resources
6. **ConfigMaps** (`:cm`) - Configuration data
   - File: `view/configmaps_view.zig`
   - Columns: NAMESPACE, NAME, DATA, AGE
   - Actions: describe, edit, delete

7. **Secrets** (`:sec`) - Sensitive data
   - File: `view/secrets_view.zig`
   - Columns: NAMESPACE, NAME, TYPE, DATA, AGE
   - Actions: describe, decode (base64), delete
   - Security: Mask values by default

### Storage Resources
8. **PersistentVolumes** (`:pv`) - Cluster storage
   - File: `view/pv_view.zig`
   - Columns: NAME, CAPACITY, ACCESS-MODES, RECLAIM-POLICY, STATUS, AGE
   - Actions: describe, delete

9. **PersistentVolumeClaims** (`:pvc`) - Storage requests
   - File: `view/pvc_view.zig`
   - Columns: NAMESPACE, NAME, STATUS, VOLUME, CAPACITY, ACCESS-MODES, AGE
   - Actions: describe, delete

10. **StorageClasses** (`:sc`) - Storage types
    - File: `view/storageclasses_view.zig`
    - Columns: NAME, PROVISIONER, RECLAIM-POLICY, VOLUME-BINDING-MODE, AGE
    - Actions: describe, delete

## Priority 3: Network Resources

11. **Ingresses** (`:ing`) - HTTP routing
    - File: `view/ingresses_view.zig`
    - Columns: NAMESPACE, NAME, CLASS, HOSTS, ADDRESS, PORTS, AGE
    - Actions: describe, edit, delete

12. **Endpoints** (`:ep`) - Service endpoints
    - File: `view/endpoints_view.zig`
    - Columns: NAMESPACE, NAME, ENDPOINTS, AGE
    - Actions: describe

13. **NetworkPolicies** (`:np`) - Network rules
    - File: `view/networkpolicies_view.zig`
    - Columns: NAMESPACE, NAME, POD-SELECTOR, AGE
    - Actions: describe, edit, delete

## Priority 4: RBAC & Security

14. **ServiceAccounts** (`:sa`) - Pod identities
    - File: `view/serviceaccounts_view.zig`
    - Columns: NAMESPACE, NAME, SECRETS, AGE
    - Actions: describe, delete

15. **Roles** (`:ro`) - Namespace permissions
    - File: `view/roles_view.zig`
    - Columns: NAMESPACE, NAME, AGE
    - Actions: describe, delete

16. **RoleBindings** (`:rb`) - Role assignments
    - File: `view/rolebindings_view.zig`
    - Columns: NAMESPACE, NAME, ROLE, AGE
    - Actions: describe, delete

17. **ClusterRoles** (`:cr`) - Cluster permissions
    - File: `view/clusterroles_view.zig`
    - Columns: NAME, AGE
    - Actions: describe, delete

18. **ClusterRoleBindings** (`:crb`) - Cluster role assignments
    - File: `view/clusterrolebindings_view.zig`
    - Columns: NAME, ROLE, AGE
    - Actions: describe, delete

## Priority 5: Cluster Management

19. **Events** (`:ev`) - Cluster events
    - File: `view/events_view.zig`
    - Columns: NAMESPACE, LAST-SEEN, TYPE, REASON, OBJECT, MESSAGE
    - Actions: describe, filter by type
    - Special: Real-time updates, auto-scroll

20. **ResourceQuotas** (`:rq`) - Resource limits
    - File: `view/resourcequotas_view.zig`
    - Columns: NAMESPACE, NAME, AGE
    - Actions: describe, edit

21. **LimitRanges** (`:lr`) - Default limits
    - File: `view/limitranges_view.zig`
    - Columns: NAMESPACE, NAME, AGE
    - Actions: describe, edit

22. **PodDisruptionBudgets** (`:pdb`) - Disruption policies
    - File: `view/pdb_view.zig`
    - Columns: NAMESPACE, NAME, MIN-AVAILABLE, MAX-UNAVAILABLE, ALLOWED-DISRUPTIONS
    - Actions: describe, delete

## Priority 6: Advanced Features

23. **HorizontalPodAutoscalers** (`:hpa`) - Auto-scaling
    - File: `view/hpa_view.zig`
    - Columns: NAMESPACE, NAME, REFERENCE, TARGETS, MINPODS, MAXPODS, REPLICAS, AGE
    - Actions: describe, edit, delete

24. **VerticalPodAutoscalers** (`:vpa`) - Vertical auto-scaling
    - File: `view/vpa_view.zig`
    - Columns: NAMESPACE, NAME, MODE, AGE
    - Actions: describe, edit, delete

25. **CustomResourceDefinitions** (`:crd`) - Custom resources
    - File: `view/crd_view.zig`
    - Columns: NAME, GROUP, VERSION, SCOPE, AGE
    - Actions: describe, view instances

26. **Custom Resources** (`:cr`) - CRD instances (dynamic)
    - File: `view/custom_resource_view.zig`
    - Dynamic columns based on CRD spec
    - Actions: describe, edit, delete

## Priority 7: Special Views

27. **Contexts** (`:ctx`) - Cluster contexts
    - File: `view/contexts_view.zig`
    - Columns: NAME, CLUSTER, AUTHINFO, NAMESPACE
    - Actions: switch context
    - Special: Show current context

28. **Port-Forwards** (`:pf`) - Active port forwards
    - File: `view/portforwards_view.zig`
    - Columns: NAMESPACE, POD, PORTS, AGE
    - Actions: stop, create new

29. **Logs** (`:logs`) - Container logs viewer
    - File: `view/logs_view.zig`
    - Features: tail, follow, previous, timestamps, since
    - Actions: search, export, clear

30. **YAML/Describe** (`:yaml`) - Resource YAML viewer
    - File: `view/yaml_view.zig`
    - Features: syntax highlighting, edit, apply
    - Actions: save, copy, diff

## Implementation Guidelines

### View Structure (Standard Pattern)
```zig
pub const XxxView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    
    // State
    items: std.ArrayListUnmanaged(XxxInfo),
    selected_row: usize,
    scroll_offset: usize,
    loading: bool,
    error_message: ?[]const u8,
    
    // Filtering
    filter_text: []const u8,
    show_all_namespaces: bool,
    
    pub fn init(...) !XxxView { }
    pub fn deinit(self: *XxxView) void { }
    pub fn refresh(self: *XxxView) !void { }
    pub fn createView(self: *XxxView) View { }
    
    // View trait implementation
    fn render(ptr: *anyopaque, ...) !void { }
    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult { }
    fn onShow(ptr: *anyopaque) !void { }
    fn onHide(ptr: *anyopaque) void { }
    fn getName(ptr: *anyopaque) []const u8 { }
    fn getHints(ptr: *anyopaque) hints_model.HintConfig { }
};
```

### K8s Service Methods Needed
Add to `services/k8s_service.zig`:
```zig
// Workloads
pub fn listStatefulSets(self: *K8sService, namespace: ?[]const u8) ![]types.StatefulSet
pub fn listDaemonSets(self: *K8sService, namespace: ?[]const u8) ![]types.DaemonSet
pub fn listReplicaSets(self: *K8sService, namespace: ?[]const u8) ![]types.ReplicaSet
pub fn listJobs(self: *K8sService, namespace: ?[]const u8) ![]types.Job
pub fn listCronJobs(self: *K8sService, namespace: ?[]const u8) ![]types.CronJob

// Config & Storage
pub fn listConfigMaps(self: *K8sService, namespace: ?[]const u8) ![]types.ConfigMap
pub fn listSecrets(self: *K8sService, namespace: ?[]const u8) ![]types.Secret
pub fn listPersistentVolumes(self: *K8sService) ![]types.PersistentVolume
pub fn listPersistentVolumeClaims(self: *K8sService, namespace: ?[]const u8) ![]types.PVC
pub fn listStorageClasses(self: *K8sService) ![]types.StorageClass

// Network
pub fn listIngresses(self: *K8sService, namespace: ?[]const u8) ![]types.Ingress
pub fn listEndpoints(self: *K8sService, namespace: ?[]const u8) ![]types.Endpoints
pub fn listNetworkPolicies(self: *K8sService, namespace: ?[]const u8) ![]types.NetworkPolicy

// RBAC
pub fn listServiceAccounts(self: *K8sService, namespace: ?[]const u8) ![]types.ServiceAccount
pub fn listRoles(self: *K8sService, namespace: ?[]const u8) ![]types.Role
pub fn listRoleBindings(self: *K8sService, namespace: ?[]const u8) ![]types.RoleBinding
pub fn listClusterRoles(self: *K8sService) ![]types.ClusterRole
pub fn listClusterRoleBindings(self: *K8sService) ![]types.ClusterRoleBinding

// Cluster
pub fn listEvents(self: *K8sService, namespace: ?[]const u8) ![]types.Event
pub fn listResourceQuotas(self: *K8sService, namespace: ?[]const u8) ![]types.ResourceQuota
pub fn listLimitRanges(self: *K8sService, namespace: ?[]const u8) ![]types.LimitRange
pub fn listPodDisruptionBudgets(self: *K8sService, namespace: ?[]const u8) ![]types.PDB

// Advanced
pub fn listHPAs(self: *K8sService, namespace: ?[]const u8) ![]types.HPA
pub fn listVPAs(self: *K8sService, namespace: ?[]const u8) ![]types.VPA
pub fn listCRDs(self: *K8sService) ![]types.CustomResourceDefinition
pub fn listCustomResources(self: *K8sService, crd: []const u8, namespace: ?[]const u8) ![]types.CustomResource
```

### Command Aliases (k9s compatible)
Add to `app.zig` command registry:
```zig
// Workloads
":sts", ":statefulsets" -> StatefulSetsView
":ds", ":daemonsets" -> DaemonSetsView
":rs", ":replicasets" -> ReplicaSetsView
":job", ":jobs" -> JobsView
":cj", ":cronjobs" -> CronJobsView

// Config & Storage
":cm", ":configmaps" -> ConfigMapsView
":sec", ":secrets" -> SecretsView
":pv", ":persistentvolumes" -> PersistentVolumesView
":pvc", ":persistentvolumeclaims" -> PVCView
":sc", ":storageclasses" -> StorageClassesView

// Network
":ing", ":ingresses" -> IngressesView
":ep", ":endpoints" -> EndpointsView
":np", ":networkpolicies" -> NetworkPoliciesView

// RBAC
":sa", ":serviceaccounts" -> ServiceAccountsView
":ro", ":roles" -> RolesView
":rb", ":rolebindings" -> RoleBindingsView
":cr", ":clusterroles" -> ClusterRolesView
":crb", ":clusterrolebindings" -> ClusterRoleBindingsView

// Cluster
":ev", ":events" -> EventsView
":rq", ":resourcequotas" -> ResourceQuotasView
":lr", ":limitranges" -> LimitRangesView
":pdb", ":poddisruptionbudgets" -> PDBView

// Advanced
":hpa", ":horizontalpodautoscalers" -> HPAView
":vpa", ":verticalpodautoscalers" -> VPAView
":crd", ":customresourcedefinitions" -> CRDView

// Special
":ctx", ":contexts" -> ContextsView
":pf", ":portforwards" -> PortForwardsView
":logs" -> LogsView (requires pod/container selection)
":yaml" -> YAMLView (requires resource selection)
```

## Testing Strategy

### Per View Testing
1. Unit tests for filtering, sorting, display logic
2. Integration tests with mock K8s API
3. Real cluster validation with `rancher-desktop`

### Common Test Cases
- Empty list handling
- Error display
- Pagination/scrolling
- Filtering (by name, namespace)
- Multi-namespace toggle
- Theme compatibility
- Keyboard navigation
- Action execution

## Dependencies

### Immediate Blockers
1. ✅ TLS fix in zig-klient (other agent working on it)
2. ✅ All K8s resource types in zig-klient

### Nice to Have
- Watch API for real-time updates
- WebSocket support for logs/exec
- Metrics integration
- Custom resource schema validation

## Milestones

### M1: Core Workloads (Sprint 1)
- StatefulSets, DaemonSets, ReplicaSets, Jobs, CronJobs
- **Goal**: Feature parity with basic kubectl for workloads

### M2: Config & Storage (Sprint 2)
- ConfigMaps, Secrets, PV, PVC, StorageClasses
- **Goal**: Full configuration management

### M3: Network & RBAC (Sprint 3)
- Ingress, Endpoints, NetworkPolicies, RBAC resources
- **Goal**: Complete cluster security view

### M4: Advanced Features (Sprint 4)
- Events, Quotas, Autoscaling, CRDs
- **Goal**: Enterprise-ready cluster management

### M5: Power User Features (Sprint 5)
- Port-forwards, Logs, YAML editor, Custom resources
- **Goal**: k9s feature parity

## Success Criteria

- [ ] All 30 views implemented
- [ ] 100% k9s command alias compatibility
- [ ] Sub-second view switching
- [ ] Real-time updates for Events/Logs
- [ ] Comprehensive keyboard shortcuts
- [ ] Zero crashes on any cluster state
- [ ] Beautiful, consistent UI across all views
- [ ] Detailed logs for troubleshooting

## Current Sprint: Priority 1 (Week 1-2)

**Focus**: Get 5 core workload views working with real data

**Dependencies**: 
- ✅ Wait for zig-klient TLS fix
- ✅ Ensure zig-klient has all resource types

**Deliverables**:
1. StatefulSetsView - Complete
2. DaemonSetsView - Complete  
3. ReplicaSetsView - Complete
4. JobsView - Complete
5. CronJobsView - Complete

**Next Session**: Start with StatefulSetsView once zig-klient TLS is fixed!

