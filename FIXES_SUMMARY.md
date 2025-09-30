# C3S Kubernetes Integration - Fixes & Status

## 🐛 Issues Identified & Fixed

### 1. ✅ FIXED: Use-After-Free Bug (Garbled Symbols)

**Problem**: The header was showing `◆◆◆◆◆◆◆◆` symbols instead of real context/cluster/user names.

**Root Cause**: 
```zig
// In app.zig
var cluster_data = try k8s_manager.getClusterInfo();
defer cluster_data.deinit(allocator);  // ❌ Frees strings HERE

var header = try Header.initWithData(allocator, theme, cluster_data);
// ❌ Header references freed memory!
```

**Fix Applied** (`src/ui/header.zig`):
```zig
pub fn initWithData(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, cluster_data: anytype) !Header {
    // ...
    return Header{
        // ✅ Now duplicates all strings
        .context = try allocator.dupe(u8, cluster_data.context),
        .cluster = try allocator.dupe(u8, cluster_data.cluster),
        .user = try allocator.dupe(u8, cluster_data.user),
        .k8s_version = try allocator.dupe(u8, cluster_data.k8s_version),
        // ...
    };
}

pub fn deinit(self: *Header) void {
    // ✅ Properly frees duplicated strings
    self.allocator.free(self.context);
    self.allocator.free(self.cluster);
    self.allocator.free(self.user);
    self.allocator.free(self.k8s_version);
    // ...
}
```

**Status**: ✅ **FIXED** - Header now shows correct cluster information

---

### 2. 🟡 PARTIAL: Kubernetes API Client

**Problem**: Zig 0.15's HTTP API changed significantly, making the original implementation incomplete.

**What Works**:
- ✅ Module architecture (client, kubeconfig, manager)
- ✅ Kubeconfig parser
- ✅ Graceful fallback to fixtures
- ✅ ClusterData abstraction
- ✅ Memory management

**What Doesn't Work Yet**:
- ❌ HTTP response body reading (Zig 0.15's `fetch()` API limitation)
- ❌ Bearer token authentication headers
- ❌ TLS/SSL connections to real clusters

**Current Behavior**:
```
[WARN] K8s HTTP client not yet fully implemented in Zig 0.15
[INFO] Using fixtures for cluster data
```

**Files**:
- `src/k8s/client.zig` - HTTP client (partial)
- `src/k8s/manager.zig` - Manager with fallback
- `src/k8s/kubeconfig.zig` - Config parser (working)

---

### 3. ❌ TODO: Real-Time CPU/MEM Metrics

**Problem**: CPU and MEM are showing static values from fixtures, not live cluster metrics.

**How k9s Does It**:

From `k9s-patched/internal/client/metrics.go`:
```go
// Calls Kubernetes Metrics Server API
func (m *MetricsServer) FetchNodesMetrics(ctx context.Context) (*mv1beta1.NodeMetricsList, error) {
    return m.mx.MetricsV1beta1().NodeMetricses().List(ctx, metav1.ListOptions{})
}
```

**API Endpoints**:
- Node Metrics: `GET /apis/metrics.k8s.io/v1beta1/nodes`
- Pod Metrics: `GET /apis/metrics.k8s.io/v1beta1/namespaces/{ns}/pods`

**Example Response**:
```json
{
  "items": [{
    "metadata": {"name": "node-1"},
    "usage": {
      "cpu": "250m",      // 0.25 cores
      "memory": "1500Mi"  // 1.5GB
    }
  }]
}
```

**What Needs to Be Done**:
1. Implement Metrics Server API client
2. Parse CPU/memory from response
3. Calculate percentages (usage / allocatable * 100)
4. Update Header with real-time data periodically

---

## 📋 Solution Options

### Option A: Quick Fix - kubectl proxy (Recommended for Testing)

**Steps**:
1. User runs: `kubectl proxy`
2. c3s connects to `http://localhost:8001` (no auth needed!)
3. Works with current Zig 0.15 HTTP client

**Pros**: ✅ Works immediately, no complex auth

**Cons**: ❌ Requires manual proxy step

**Implementation**: 5 minutes

---

### Option B: Use Official Kubernetes C Library (Best Long-Term)

**Available at**: `/Users/andreymaltsev/Development/alphasense/c/`

**Library**: https://github.com/kubernetes-client/c

**Pros**:
- ✅ Official, battle-tested
- ✅ Full API coverage
- ✅ Proper authentication
- ✅ Metrics API support
- ✅ Used in production

**Cons**:
- ❌ Requires building C library
- ❌ Adds C dependency

**Steps**:
1. Build C library (`cmake && make && make install`)
2. Create Zig bindings (`@cImport`)
3. Link in build.zig
4. Implement client wrapper

**Implementation**: 2-4 hours

**See**: `K8S_CLIENT_OPTIONS.md` for full guide

---

### Option C: Wait for Zig 0.15 HTTP API Updates

**Wait for**: Zig stdlib to expose response body in `fetch()` API

**Timeline**: Unknown (weeks/months?)

---

## 🎯 Recommended Next Steps

### Immediate (Testing):

```bash
# Terminal 1: Start proxy
kubectl proxy

# Terminal 2: Test c3s with real cluster
cd c3s
zig build
./zig-out/bin/c3s

# Should show real cluster data (once implemented)
```

### Short-Term (This Week):

1. ✅ **DONE**: Fix use-after-free bug
2. 🔲 **TODO**: Implement kubectl proxy support
3. 🔲 **TODO**: Add Metrics API client
4. 🔲 **TODO**: Real-time metrics refresh

### Long-Term (Production):

1. 🔲 Build Kubernetes C library
2. 🔲 Create Zig bindings
3. 🔲 Full kubeconfig support (all auth methods)
4. 🔲 Watch/streaming API
5. 🔲 All Kubernetes resources

---

## 🧪 Testing

### Verify Fix for Garbled Symbols:

```bash
cd c3s
zig build
./zig-out/bin/c3s
```

**Expected**: Should show fixture data correctly (e.g., "fred [RW]", "zorg", "fred")  
**Not**: ◆◆◆◆◆◆◆◆

### Test with Real Cluster (once implemented):

```bash
# Ensure you have a kubeconfig
kubectl config current-context

# Start proxy
kubectl proxy &

# Run c3s
./zig-out/bin/c3s

# Should show:
# - Real context name
# - Real cluster name  
# - Real user name
# - Live CPU/MEM metrics
```

---

## 📊 Current State

| Component | Status | Notes |
|-----------|--------|-------|
| Use-after-free bug | ✅ Fixed | Header now duplicates strings |
| Module architecture | ✅ Done | Clean separation of concerns |
| Kubeconfig parser | ✅ Done | Parses ~/.kube/config |
| HTTP client | 🟡 Partial | Zig 0.15 API limitation |
| Metrics API | ❌ Not impl | Needs HTTP client first |
| Real-time data | ❌ Not impl | Shows static fixtures |
| Build status | ✅ Working | No compilation errors |
| Linter | ✅ Clean | No linter errors |

---

## 🚀 How to Proceed

**Option 1**: Quick test with kubectl proxy (1 hour)
- Modify client to use `localhost:8001`
- Implement simple HTTP GET
- Parse JSON responses

**Option 2**: Full C library integration (4 hours)
- Build Kubernetes C library
- Create comprehensive Zig bindings
- Production-ready solution

**Your choice!** Both are viable. Option 1 is faster for testing, Option 2 is better for production.
