# ✅ Context Verification - WORKING

## Current Behavior

c3s **correctly connects to the current kubectl context** automatically.

### Verification

**Your current context**: `research.alpha-sense.org`

**c3s connection log**:
```
[INFO]: Successfully connected to Kubernetes cluster
[INFO]: Context: research.alpha-sense.org, Cluster: research.alpha-sense.org, 
        Server: https://api-research.alpha-sense.org
```

✅ **WORKING AS EXPECTED**

---

## How It Works

### 1. Kubeconfig Loading (`src/k8s/kubeconfig.zig`)

```zig
// Reads ~/.kube/config
pub fn load(self: *KubeconfigParser) !Kubeconfig {
    const home = std.posix.getenv("HOME") orelse return error.HomeNotSet;
    const config_path = try std.fmt.allocPrint(
        self.allocator,
        "{s}/.kube/config",
        .{home}
    );
    // ...
}
```

### 2. Current Context Detection

```zig
// Parses "current-context:" line
if (std.mem.startsWith(u8, trimmed, "current-context:")) {
    const value = std.mem.trim(u8, trimmed[16..], " ");
    current_context = try self.allocator.dupe(u8, value);
}
```

### 3. Context Resolution (`src/k8s/manager.zig`)

```zig
const current_context = kc.getCurrentContext() orelse {
    Logger.warn("No current context in kubeconfig. Using fixtures.", .{});
    return;
};

const cluster = kc.getCluster(current_context.cluster) orelse {
    Logger.warn("Cluster not found in kubeconfig. Using fixtures.", .{});
    return;
};

Logger.info("Context: {s}, Cluster: {s}, Server: {s}", .{
    current_context.name,
    cluster.name,
    cluster.server,
});
```

---

## Context Switching

c3s automatically picks up context changes:

### Method 1: kubectl (recommended)
```bash
# Switch context
kubectl config use-context <context-name>

# Run c3s (will use new context)
./zig-out/bin/c3s
```

### Method 2: c3s flag (if implemented)
```bash
# Use specific context
./zig-out/bin/c3s --context <context-name>
```

---

## Troubleshooting

### If c3s doesn't connect to the right context:

1. **Verify current context**:
   ```bash
   kubectl config current-context
   ```

2. **Check kubeconfig**:
   ```bash
   cat ~/.kube/config | grep current-context
   ```

3. **Run c3s with debug**:
   ```bash
   ./zig-out/bin/c3s --debug
   ```

4. **Check logs**:
   ```
   [INFO]: Connecting to Kubernetes cluster...
   [INFO]: Context: <current-context>, Cluster: <cluster>, Server: <server>
   [INFO]: Successfully connected to Kubernetes cluster
   ```

### Common Issues:

❌ **"No current context"** → kubeconfig missing `current-context:` line
- Fix: `kubectl config use-context <context-name>`

❌ **"Cluster not found"** → Context references non-existent cluster
- Fix: Check `kubectl config view`

❌ **"Using fixtures"** → Can't connect to cluster (credentials, network, etc.)
- Not a c3s issue - cluster is unreachable

---

## ✅ Status

**Current Implementation**: ✅ **WORKING**

- ✅ Reads `~/.kube/config`
- ✅ Detects `current-context`
- ✅ Resolves context → cluster → server
- ✅ Connects to correct API server
- ✅ Falls back to fixtures gracefully

**No changes needed** - context detection is working correctly!
