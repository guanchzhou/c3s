# c3s Quick Start Guide

Welcome to **c3s** - A blazing-fast Kubernetes TUI written in Zig! 🚀

---

## 📋 **Prerequisites**

- **Zig 0.15.1** installed
- **kubeconfig** configured (`~/.kube/config`)
- **Kubernetes cluster** accessible (or use `--debug` for demo mode)

---

## 🚀 **Installation**

### Build from Source

```bash
cd /path/to/c3s
zig build
```

### Run

```bash
# Connect to current kubectl context
./zig-out/bin/c3s

# Use specific context
./zig-out/bin/c3s --context my-cluster

# Run in debug mode (with dummy data, no cluster required)
./zig-out/bin/c3s --debug
```

---

## 🎯 **Basic Navigation**

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `j` or `↓` | Move down |
| `k` or `↑` | Move up |
| `0` | Toggle all namespaces |
| `r` | Refresh current view |
| `:` | Open command palette |
| `/` | Filter |
| `Esc` | Clear filter / Go back |
| `q` | Quit |

### View Switching

Press `:` to open the command palette, then type a command:

---

## 📚 **Available Commands**

### Workload Resources

```
:pods or :po                    # View pods
:deployments or :deploy or :dp  # View deployments
:statefulsets or :sts           # View StatefulSets
:daemonsets or :ds              # View DaemonSets
:replicasets or :rs             # View ReplicaSets
:jobs or :job                   # View Jobs
:cronjobs or :cj                # View CronJobs
```

### Configuration & Storage

```
:configmaps or :cm              # View ConfigMaps
:secrets or :secret             # View Secrets
:persistentvolumes or :pv       # View PersistentVolumes
:persistentvolumeclaims or :pvc # View PersistentVolumeClaims
```

### Network Resources

```
:services or :svc               # View Services
:ingresses or :ing              # View Ingresses
:networkpolicies or :netpol     # View NetworkPolicies
```

### RBAC & Security

```
:serviceaccounts or :sa         # View ServiceAccounts
:roles or :role                 # View Roles
:rolebindings or :rb            # View RoleBindings
:clusterroles or :cr            # View ClusterRoles
:clusterrolebindings or :crb    # View ClusterRoleBindings
```

### Cluster Resources

```
:namespaces or :ns              # View Namespaces
:nodes or :no                   # View Nodes
:events or :ev                  # View Events
:resourcequotas or :quota       # View ResourceQuotas
:limitranges or :limits         # View LimitRanges
:poddisruptionbudgets or :pdb   # View PodDisruptionBudgets
```

### Advanced

```
:horizontalpodautoscalers or :hpa  # View HPAs
```

### Special Views

```
:contexts or :ctx or :context   # Manage contexts (press Enter to switch)
:theme                          # Change theme
```

---

## 🎨 **Themes**

c3s supports k9s-compatible themes!

### Change Theme

1. Press `:theme`
2. Navigate with `j`/`k`
3. Press `Enter` to apply

### Available Themes

- `dracula` (default)
- `monokai`
- `nord`
- `tokyo-night`
- And many more!

### Custom Themes

Place your k9s skin files in: `~/.config/c3s/skins/`

---

## 🔧 **Configuration**

### Config File

Located at: `~/.config/c3s/config.yml`

```yaml
ui:
  theme: dracula
  compact: false
  footer: true
```

### Logs

View logs at: `~/.local/state/c3s/c3s.log`

---

## 💡 **Tips & Tricks**

### 1. Quick Context Switching

```bash
# Open c3s
./zig-out/bin/c3s

# Press :contexts
# Navigate to desired context
# Press Enter to switch
```

### 2. Namespace Filtering

- Press `0` in any resource view to toggle between:
  - Current namespace only
  - All namespaces

### 3. Real-time Refresh

- Press `r` to refresh the current view
- Views auto-refresh when switching back to them

### 4. Filtering

- Press `/` to start filtering
- Type to filter by name
- Press `Esc` to clear filter

### 5. Multiple Clusters

```bash
# Terminal 1
./zig-out/bin/c3s --context cluster-1

# Terminal 2
./zig-out/bin/c3s --context cluster-2
```

---

## 🐛 **Troubleshooting**

### "Failed to connect to Kubernetes"

**Solution:** Check your kubeconfig:
```bash
kubectl config current-context
kubectl cluster-info
```

Or run in debug mode:
```bash
./zig-out/bin/c3s --debug
```

### "Context not found"

**Solution:** List available contexts:
```bash
kubectl config get-contexts
```

Then use:
```bash
./zig-out/bin/c3s --context <context-name>
```

### "No pods found"

**Solutions:**
1. Check if you're in the right namespace
2. Press `0` to toggle all namespaces
3. Verify pods exist: `kubectl get pods --all-namespaces`

### Theme Issues

**Solution:** Ensure theme file exists:
```bash
ls ~/.config/c3s/skins/
```

Or use default theme:
```bash
# Edit ~/.config/c3s/config.yml
ui:
  theme: dracula
```

---

## 📖 **Common Workflows**

### 1. Check Pod Status Across All Namespaces

```
1. Launch c3s
2. Press :pods
3. Press 0 (toggle all namespaces)
4. Navigate with j/k
```

### 2. View Recent Events

```
1. Launch c3s
2. Press :events
3. Events are sorted by timestamp
4. Filter with / if needed
```

### 3. Switch to Another Cluster

```
1. Press :contexts
2. Navigate to desired context
3. Press Enter
4. Views will refresh with new cluster data
```

### 4. Check Resource Quotas

```
1. Press :quota
2. View quota usage per namespace
3. Press 0 for all namespaces
```

### 5. Monitor HPA Scaling

```
1. Press :hpa
2. Watch min/max/current replicas
3. Press r to refresh
```

---

## 🎓 **Learning Resources**

### Documentation

- **PROJECT_COMPLETION_SUMMARY.md** - Complete feature list
- **TESTING_SUMMARY.md** - Testing guide
- **CODE_QUALITY_REPORT.md** - Code quality analysis

### Key Bindings Reference

Similar to k9s for familiar workflow:
- [k9s Documentation](https://k9scli.io/)

### Kubernetes Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)

---

## 🚀 **Advanced Usage**

### Custom Keybindings

Coming soon! Currently uses vim-style defaults.

### Port Forwarding

Coming soon! Will support interactive port forwarding.

### Pod Logs

Coming soon! Will support real-time log viewing.

### YAML Editing

Coming soon! Will support in-TUI YAML editing.

---

## 📊 **Performance**

c3s is built in Zig for maximum performance:

- **Fast startup:** < 1 second
- **Low memory:** ~50-100MB typical usage
- **Efficient rendering:** 60 FPS target
- **Zero overhead:** No garbage collection

---

## 🤝 **Contributing**

Interested in contributing? Check out:

1. **Architecture:** Review MVVM pattern in code
2. **Testing:** Add tests for new features
3. **Documentation:** Improve guides
4. **Features:** Implement advanced features (logs, port-forwarding, etc.)

---

## 📝 **Command Cheat Sheet**

### Quick Reference Card

```
Navigation:           Resources:              Actions:
j/k, ↑/↓ - Navigate  :pods - Pods            0 - All namespaces
:        - Command    :deploy - Deployments  r - Refresh
/        - Filter     :svc - Services        / - Filter
Esc      - Back       :ns - Namespaces       q - Quit
                      :ctx - Contexts
```

---

## 🎯 **Next Steps**

1. **Explore all 28 resource views**
2. **Try different themes**
3. **Manage multiple clusters**
4. **Set up custom configuration**
5. **Join the community** (contribute, report issues)

---

## 💬 **Getting Help**

- **Logs:** Check `~/.local/state/c3s/c3s.log`
- **Issues:** Report on GitHub
- **Documentation:** Read markdown files in project root

---

## 🎉 **You're Ready!**

Start exploring your Kubernetes clusters with c3s:

```bash
./zig-out/bin/c3s
```

**Enjoy the speed and power of c3s!** ⚡

---

*Built with ❤️ in Zig | Inspired by k9s and btop*

