# Test Fixtures

This directory contains realistic test data for c3s view components, **based on real k9s testdata**.

## Purpose

- Provide **realistic** test data consistent with k9s
- Enable UI testing without real Kubernetes connection
- Support different testing scenarios (minimal, production-like, high-load, etc.)
- Centralize test data to avoid duplication
- Use industry-standard test data from upstream k9s project

## Data Source

All fixture data is derived from **k9s project testdata** located in `testdata/k8s/`:

### Source Files
- 📦 **Pods**: `testdata/k8s/pods/po.json` - nginx pod (Running, 1/1)
- 🚀 **Deployments**: `testdata/k8s/deployments/dp.json` - icx-db (postgres)
- 🖥️  **Nodes**: `testdata/k8s/nodes/no.json` - minikube v1.15.2
- ⚙️  **Kubeconfig**: `testdata/k8s/config/kubeconfig` - fred, blee, duh contexts

This ensures consistency with k9s behavior and provides realistic Kubernetes resource examples.

## Structure

### `k8s_data.zig`
Kubernetes cluster information fixtures (**from k9s testdata**):
- `default_data` - **k9s fred context** (zorg cluster, v1.15.2)
- `blee_data` - **k9s blee context** (alternate context)
- `minikube_data` - **k9s minikube node** (v1.15.2, 4 CPU, 8GB)
- `minimal_data` - Short values for testing compression
- `production_data` - Realistic production cluster names
- `high_load_data` - High CPU/memory usage scenarios
- `multi_cluster_data` - **All 3 k9s contexts** (fred, blee, duh)
- `empty_data` - N/A values for disconnected state

### `pods_data.zig`
Pod information fixtures (**from k9s testdata**):
- `default_pods` - **Real k9s pods**: nginx, icx-db, coredns, kube-proxy
- `mixed_status_pods` - Pods with various statuses (Running, Pending, Error, etc.)
- `generateManyPods()` - Generate large sets for performance testing
- `namespaced_pods` - **k9s pods by namespace**: default, kube-system, icx

## Usage

### In Application Code

```zig
const fixtures = @import("fixtures/index.zig");

// Get K8s data based on debug flag
const k8s_data = fixtures.k8s_data.getData(debug);

// Use in header
header.context = k8s_data.context;
header.cluster = k8s_data.cluster;
```

### In Tests

```zig
const fixtures = @import("c3s").fixtures;

test "header with production data" {
    const data = fixtures.k8s_data.production_data;
    // ... use in test
}

test "pods view with many items" {
    const pods = try fixtures.pods_data.generateManyPods(allocator, 100);
    defer allocator.free(pods);
    // ... test scrolling/performance
}
```

## Adding New Fixtures

When adding new test data:

1. Create a new file in `src/fixtures/` (e.g., `services_data.zig`)
2. Define your data structures and test sets
3. Export the module in `src/fixtures/index.zig`
4. Update this README with documentation

## Integration with Real Data

When integrating real Kubernetes data:

1. Replace fixture calls with real K8s client calls
2. Keep the `--debug` flag to fallback to fixtures when needed
3. Fixtures remain useful for:
   - Testing without K8s connection
   - Reproducible test scenarios
   - UI development and debugging

## Future Enhancement: JSON Parsing

Currently, fixtures use hardcoded values **extracted from** k9s testdata. Future enhancement:

```zig
// Phase 3: Embed and parse JSON at compile time
const pod_json = @embedFile("../../testdata/k8s/pods/po.json");

pub fn parsePodJson(allocator: std.mem.Allocator) !PodInfo {
    const parsed = try std.json.parseFromSlice(..., allocator, pod_json, .{});
    // Extract fields dynamically from JSON
}
```

This would allow:
- Automatic updates when testdata changes
- Dynamic parsing of any k9s resource
- Full JSON schema validation
