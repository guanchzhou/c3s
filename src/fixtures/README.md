# Test Fixtures

This directory contains realistic test data for c3s view components.

## Purpose

- Provide **realistic** test data for Kubernetes resources
- Enable UI testing without real Kubernetes connection
- Support different testing scenarios (minimal, production-like, high-load, etc.)
- Centralize test data to avoid duplication

## Structure

### `k8s_data.zig`
Kubernetes cluster information fixtures:
- `default_data` - fred context (zorg cluster, v1.15.2)
- `blee_data` - blee context (alternate context)
- `minikube_data` - minikube node (v1.15.2, 4 CPU, 8GB)
- `minimal_data` - Short values for testing compression
- `production_data` - Realistic production cluster names
- `high_load_data` - High CPU/memory usage scenarios
- `multi_cluster_data` - All 3 contexts (fred, blee, duh)
- `empty_data` - N/A values for disconnected state

### `pods_data.zig`
Pod information fixtures:
- `default_pods` - Standard pods: nginx, icx-db, coredns, kube-proxy
- `mixed_status_pods` - Pods with various statuses (Running, Pending, Error, etc.)
- `generateManyPods()` - Generate large sets for performance testing
- `namespaced_pods` - Pods by namespace: default, kube-system, icx

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
