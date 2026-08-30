# c3s - Kubernetes TUI in Zig

> A blazing-fast Kubernetes Terminal User Interface (TUI) written in Zig, inspired by k9s and btop.

[![CI](https://github.com/guanchzhou/c3s/actions/workflows/ci.yml/badge.svg)](https://github.com/guanchzhou/c3s/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-Apache%202.0-blue)]()
[![Zig](https://img.shields.io/badge/zig-0.16.0-orange)]()

---

## 🚀 **Features**

### **One Generic Table Engine**
Every resource view — pods, deployments, services, daemonsets, PDBs, and the rest — is rendered by a single comptime `ResourceView` engine (`src/view/resource_view.zig`). Adding a resource is a declarative config in `src/view/resource_configs.zig`, not a bespoke renderer. Rendering, sorting, marking, filtering, and namespace scoping behave identically everywhere.

### **Tables That Feel Right**
- ✅ **Full-width layout:** tables fill the terminal; the NAME column stretches to absorb slack.
- ✅ **Full namespace names** and a full-width selection highlight bar.
- ✅ **UTF-8-safe truncation:** long values are clipped on glyph boundaries — no broken multi-byte characters.
- ✅ **Per-column sorting:** `Shift-<letter>` toggles the sort key with a ▲/▼ indicator (e.g. pods: `Shift-N` name, `Shift-R` ready, `Shift-S` status, `Shift-C` cpu, `Shift-M` mem, `Shift-I` ip, `Shift-A` age).
- ✅ **Row marking:** `Space` toggles a k9s-style mark on the current row; marks persist by row identity across cursor moves and refreshes.
- ✅ **Live filtering:** `/` filters the table; the title shows a `</term>` indicator. Clear with `x` or `Esc`.
- ✅ **Namespace scoping:** `0` toggles all-namespaces. The box title reflects scope and count k9s-style — `pods(default)[8]` or `pods(all)[104]` — and the redundant NAMESPACE column is hidden when scoped to a single namespace.

### **Fuzzy Command Palette**
Press `:` or `Ctrl-P` to open a live, fuzzy-ranked command dropdown (bordered popup). Type to filter, `Tab`/`↑`/`↓` to navigate, `Enter` to run. Every resource view and `:aliases` is a command.

### **Aliases View**
`Ctrl-A` (or `:aliases`) opens a real table of API resources — NAME / SHORTNAMES / APIVERSION / NAMESPACED / KIND — with working filter. `Ctrl-A` again toggles it off.

### **Embedded Istio Traffic View**
Press `t` on a deployment to open a live traffic topology:
- Inbound/outbound graph plus a per-peer table (req/s, success %, p50/p99 latency).
- Sourced from Istio's Prometheus metrics via the API-server service proxy.
- Fetched on a **background thread** — the UI never blocks — with ~5s auto-refresh.
- `q`/`Esc` back, `r` refresh, `j`/`k` scroll.

Powered by the `kubectl_traffic` sibling package.

### **50+ Kubernetes Resource Views**
- ✅ **Workloads:** Pods, Deployments, StatefulSets, DaemonSets, ReplicaSets, Jobs, CronJobs
- ✅ **Config & Storage:** ConfigMaps, Secrets, PersistentVolumes, PersistentVolumeClaims, StorageClasses, VolumeAttributesClasses, CSIDrivers
- ✅ **Networking:** Services, Endpoints, EndpointSlices, Ingresses, IngressClasses, NetworkPolicies, IPAddresses, ServiceCIDRs
- ✅ **Gateway API:** GatewayClasses, Gateways, HTTPRoutes, GRPCRoutes, TCP/TLS/UDPRoutes, ReferenceGrants, BackendTLSPolicies, ListenerSets
- ✅ **RBAC:** ServiceAccounts, Roles, RoleBindings, ClusterRoles, ClusterRoleBindings
- ✅ **Admission:** Validating/Mutating AdmissionPolicies and Bindings, Validating/Mutating WebhookConfigurations
- ✅ **Cluster:** Namespaces, Nodes, Events, ResourceQuotas, LimitRanges, PodDisruptionBudgets, PriorityClasses, RuntimeClasses, Leases, CSRs, StorageVersionMigrations
- ✅ **Autoscaling / DRA:** HorizontalPodAutoscalers, ResourceClaims, DeviceClasses

### **Pod Actions**
Describe (`d`), YAML (`y`), logs (`l`), edit (`e` — any resource), shell (`s`), attach (`a`), port-forward (`Shift-F` on pods and services), delete (`Ctrl-D`).

### **Context & Themes**
- Context management: list kubeconfig contexts, interactive switching, multi-cluster support.
- 35+ built-in themes plus k9s-compatible custom skins.

### **Performance**
- ⚡ **Fast:** native Zig, no runtime/GC.
- 🪶 **Lightweight:** low memory footprint.
- 🎯 **Non-blocking:** network work (traffic metrics, refreshes) runs off the UI thread.

---

## 📦 **Installation**

### **Homebrew**

```bash
brew install guanchzhou/tap/c3s
```

The tap is updated by the tag-triggered release workflow. GitHub Release assets
must be public for `brew install` to fetch them; a private repo 404s those URLs.

### **Prerequisites**
- Zig 0.16.0
- kubectl configured with a valid kubeconfig
- Kubernetes cluster access (optional: use `--debug` for demo data)

### **Build from Source**

```bash
git clone https://github.com/guanchzhou/c3s.git
cd c3s
zig build
```

> c3s depends on two sibling packages via relative paths in `build.zig.zon`:
> `../zig-klient` (the Kubernetes client) and `../kubectl-traffic` (the traffic
> view). Check them out next to the c3s directory before building.

### **Run**

```bash
# Connect to current kubectl context
./zig-out/bin/c3s

# Use a specific context
./zig-out/bin/c3s --context my-cluster

# Debug mode (no cluster required)
./zig-out/bin/c3s --debug
```

---

## 🎯 **Quick Start**

### **Navigation & Global Keys**

| Key | Action |
|-----|--------|
| `j` / `k` or `↑` / `↓` | Move cursor |
| `g` / `Shift-G` | Top / bottom |
| `Space` | Mark / unmark current row |
| `Shift-<letter>` | Sort by that column (▲/▼) |
| `/` | Filter |
| `x` | Clear filter |
| `0` | Toggle all namespaces |
| `r` | Refresh |
| `:` or `Ctrl-P` | Fuzzy command palette |
| `Ctrl-A` | Aliases (API resources) view |
| `?` | Help |
| `Esc` | Clear filter / back |
| `q` | Quit (or `:q`) |

### **Pod Actions** (on a selected pod)

| Key | Action |
|-----|--------|
| `d` | Describe |
| `y` | View YAML |
| `l` | Logs |
| `e` | Edit (`kubectl edit`; any resource) |
| `s` | Shell into container |
| `a` | Attach |
| `Shift-F` | Port-forward (pods and services) |
| `Ctrl-D` | Delete |

### **Deployment Actions**

| Key | Action |
|-----|--------|
| `t` | Open live Istio traffic view |

### **Essential Commands**

```
:pods               # View pods
:deployments        # View deployments
:services           # View services
:gateways           # Gateway API
:httproutes         # HTTPRoutes (`:htr`)
:aliases            # API-resources table
:contexts           # Manage contexts
:events             # View cluster events
:hpa                # View HorizontalPodAutoscalers
```

---

## 🎨 **Screenshots**

### Main Interface
```
┌─ pods(default)[8] ─────────────────────────────────────────────────┐
│ Context: my-cluster │ Namespace: default │ CPU: 45% │ MEM: 67%      │
└────────────────────────────────────────────────────────────────────┘

NAME                       READY  STATUS   CPU   MEM    IP           AGE ▲
nginx-7c6d9d7d4-abc12      1/1    Running  12m   34Mi   10.0.1.4     3d
redis-5f6c8b8d-xyz89       1/1    Running  3m    18Mi   10.0.1.9     2d
coredns-6d4b75cb-12345     1/1    Running  5m    22Mi   10.0.0.3     30d

┌────────────────────────────────────────────────────────────────────┐
│ j/k:Nav │ Space:Mark │ Shift-N:Sort │ /:Filter │ 0:All NS │ ::Cmd   │
└────────────────────────────────────────────────────────────────────┘
```

---

## 🏗️ **Architecture**

c3s follows **MVVM (Model-View-ViewModel)**:

```
┌─────────────────────────────────────────────────┐
│                   View Layer                     │
│  Generic ResourceView engine + dedicated views   │
│  (traffic, aliases, contexts, themes, help, …)   │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│                ViewModel Layer                   │
│  ViewManager, CommandRegistry, fuzzy palette     │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│                Service Layer                     │
│  K8sService — abstraction over the K8s client    │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│                Data Layer                        │
│  zig-klient (K8s API) + kubectl_traffic (Istio)  │
└──────────────────────────────────────────────────┘
```

**Key Components:**
- **ResourceView:** one comptime engine drives every resource table (config in `resource_configs.zig`).
- **ViewManager:** stack-based view navigation.
- **CommandRegistry:** k9s-compatible commands, surfaced through the fuzzy palette.
- **K8sService:** clean abstraction over zig-klient.
- **TrafficView:** background-threaded Istio metrics topology.
- **Theme System:** k9s-compatible theming (35+ themes).

---

## 🧪 **Testing**

```bash
# Build
zig build

# Unit tests + integration suites
zig build test-all
```

Unit tests cover the table engine, resource views, service layer, and memory-leak
detection. `zig build test-all` is what CI runs.

---

## 🤝 **Contributing**

Contributions welcome:

1. Fork the repository
2. Create a feature branch
3. Follow the existing patterns (MVVM; add resources declaratively in `resource_configs.zig`)
4. Add tests for new features
5. Run `zig fmt --check src/ tests/ build.zig build.zig.zon`
6. Submit a pull request

---

## 🗺️ **Roadmap**

### ✅ **Completed**
- [x] 25+ Kubernetes resource views
- [x] Unified generic table engine (pods migrated off its bespoke renderer)
- [x] Full-width layout, glyph-safe UTF-8 truncation, full-width selection bar
- [x] Per-column sorting (`Shift-<letter>` with ▲/▼)
- [x] Row marking (`Space`)
- [x] Live filtering (`/`, clear with `x`)
- [x] Namespace scoping (`0`) with k9s-style scoped titles
- [x] Fuzzy command palette (`:` / `Ctrl-P`)
- [x] Aliases / API-resources view (`Ctrl-A`)
- [x] Embedded Istio traffic view (`t` on a deployment, background-threaded)
- [x] Pod actions: describe / YAML / logs / edit / shell / attach / port-forward / delete
- [x] Context management
- [x] Theme system (35+)
- [x] GitHub Actions CI (build + unit tests on Linux & macOS)

### 🚧 **In Progress**
- [ ] Watch mode (real-time streaming updates)
- [ ] Integration-test suite refresh (re-enable `test-all` in CI)

### 📅 **Planned**
- [ ] Custom resource (CRD) support
- [ ] Plugin system
- [ ] Resource creation wizards
- [ ] Diff/compare views
- [ ] Multi-cluster dashboard
- [ ] Metrics integration beyond pod CPU/MEM

---

## ⚙️ **Configuration**

### **Config File**
Located at: `~/.config/c3s/config.yml`

```yaml
ui:
  theme: dracula    # Theme name
  compact: false    # Compact mode
  footer: true      # Show footer
```

### **Themes**
Place custom k9s skins in: `~/.config/c3s/skins/`

### **Logs**
View logs at: `~/.local/state/c3s/c3s.log`

---

## 🐛 **Troubleshooting**

### Connection Issues
```bash
# Check kubectl context
kubectl config current-context

# Run in debug mode (no cluster required)
./zig-out/bin/c3s --debug
```

### Context Not Found
```bash
# List available contexts
kubectl config get-contexts

# Use a specific context
./zig-out/bin/c3s --context <name>
```

---

## 🏆 **Why c3s?**

### vs kubectl
- ✅ **Visual:** TUI vs command-line
- ✅ **Efficient:** navigate with the keyboard
- ✅ **Intuitive:** see all resources at once

### vs k9s
- ✅ **Performance:** native Zig, no GC
- ✅ **Memory:** lower footprint
- ✅ **Compatible:** familiar commands and themes
- ✅ **Traffic:** built-in Istio topology view

### vs Lens
- ✅ **Lightweight:** TUI vs Electron
- ✅ **Fast:** instant startup
- ✅ **Terminal:** works over SSH

---

## 📜 **License**

Apache License 2.0 — see [LICENSE](LICENSE).

---

## 🙏 **Acknowledgments**

- **[k9s](https://k9scli.io/)** — inspiration for UX and commands
- **[btop](https://github.com/aristocratos/btop)** — UI design inspiration
- **[zig-klient](https://github.com/guanchzhou/zig-klient)** — Kubernetes client library
- **Zig Community** — amazing language and ecosystem

---

**Built with ❤️ in Zig — fast, lightweight, powerful.**
