# Integration Tests

This directory contains integration tests that interact with real Kubernetes clusters.

## Overview

Integration tests verify that c3s correctly interacts with actual Kubernetes API servers. Unlike unit tests that use mocks or fixtures, these tests require a real cluster connection.

## Requirements

### Prerequisites

1. **Kubernetes cluster access**
   - Local cluster (minikube, kind, k3s)
   - Remote cluster (GKE, EKS, AKS, etc.)
   - Kubernetes API server accessible

2. **Valid kubeconfig**
   - Default: `~/.kube/config`
   - Contains at least one valid context
   - Proper authentication credentials

3. **RBAC permissions**
   - Read access to core resources (pods, nodes, namespaces)
   - Read access to workload resources (deployments, statefulsets, etc.)
   - Read access to RBAC resources (roles, service accounts, etc.)

### Optional Resources

Some tests verify listing of optional resources:
- PersistentVolumes
- StorageClasses
- NetworkPolicies
- Ingresses
- Custom Resources

If your cluster doesn't have these resources, the tests will pass with 0 items.

## Running Tests

### All Integration Tests

```bash
# Run all integration tests (requires cluster)
zig build test-integration
```

### Specific Test

```bash
# Run a specific integration test
zig test tests/integration/k8s_service_integration_test.zig \
  --dep klient \
  -Mklient=/path/to/zig-klient/src/klient.zig
```

### Without Cluster Access

Integration tests gracefully skip if no cluster is available:

```
Skipping integration test - no cluster available: error.ConnectionRefused
```

This is expected in CI environments or when no cluster is configured.

## Test Structure

### Test Organization

```
tests/integration/
├── README.md                           # This file
├── k8s_service_integration_test.zig    # K8sService integration tests
└── view_integration_test.zig           # View integration tests (future)
```

### Test Categories

1. **Connection Tests**
   - Connect to cluster
   - Disconnect from cluster
   - Connection lifecycle
   - Context switching

2. **Resource Listing Tests**
   - List pods (namespace-scoped)
   - List all pods (cluster-wide)
   - List namespaces
   - List nodes
   - List deployments, services, etc.

3. **Multi-Namespace Tests**
   - Query different namespaces
   - Compare results across namespaces

4. **Context Tests**
   - List all contexts
   - Verify current context
   - Switch contexts (if multiple available)

## Test Patterns

### Graceful Skipping

All integration tests handle missing clusters gracefully:

```zig
test "my integration test" {
    var service = K8sService.init(allocator);
    defer service.deinit();

    service.connect(null) catch |err| {
        std.debug.print("Skipping integration test - no cluster available: {}\n", .{err});
        return error.SkipZigTest;
    };
    defer service.disconnect();

    // Test logic here
}
```

### Resource Cleanup

Always clean up allocated resources:

```zig
const pods = service.listPods(null) catch |err| {
    std.debug.print("Failed to list pods: {}\n", .{err});
    return err;
};
defer allocator.free(pods);
```

### Informative Output

Tests print useful information:

```zig
std.debug.print("Successfully retrieved {} pods\n", .{pods.len});
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Integration Tests

on: [push, pull_request]

jobs:
  integration:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      # Set up local cluster
      - name: Create k3s cluster
        run: |
          curl -sfL https://get.k3s.io | sh -
          sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
          
      # Run tests
      - name: Run integration tests
        run: zig build test-integration
```

### Local CI (without cluster)

Integration tests will skip automatically:

```bash
# Tests will skip gracefully
zig build test-integration

# Output:
# Skipping integration test - no cluster available
```

## Debugging

### Enable Verbose Output

```bash
# See all test output
zig build test-integration --summary all
```

### Test Specific Resources

Modify tests to target specific namespaces:

```zig
const pods = service.listPods("my-namespace") catch |err| {
    return err;
};
```

### Check Cluster State

Before running tests:

```bash
# Verify cluster access
kubectl cluster-info

# List available contexts
kubectl config get-contexts

# Check current namespace
kubectl config view --minify | grep namespace
```

## Test Coverage

### Covered Resources

✅ **Core Resources:**
- Pods (namespace + all)
- Namespaces
- Nodes
- Events

✅ **Workload Resources:**
- Deployments
- StatefulSets
- DaemonSets
- ReplicaSets
- Jobs
- CronJobs

✅ **Configuration & Storage:**
- ConfigMaps
- Secrets
- PersistentVolumes
- PersistentVolumeClaims

✅ **Networking:**
- Services
- Ingresses
- NetworkPolicies

✅ **RBAC & Security:**
- ServiceAccounts
- Roles
- RoleBindings
- ClusterRoles
- ClusterRoleBindings

✅ **Advanced:**
- HorizontalPodAutoscalers
- ResourceQuotas
- LimitRanges
- PodDisruptionBudgets

✅ **Special:**
- Context listing
- Context switching

### Future Coverage

🚧 **Planned:**
- Resource creation
- Resource updating
- Resource deletion
- Watch operations
- Custom resources
- Pod logs
- Port forwarding

## Best Practices

### 1. Idempotent Tests

Tests should not modify cluster state:
- ✅ List resources
- ✅ Read configurations
- ❌ Create resources (unless cleanup is guaranteed)
- ❌ Delete resources

### 2. Namespace Isolation

Use dedicated test namespaces:

```zig
const test_ns = "c3s-integration-test";
// Create namespace before tests
// Delete namespace after tests
```

### 3. Resource Limits

Don't assume resource counts:

```zig
// ✅ Good - accepts any count
try testing.expect(pods.len >= 0);

// ❌ Bad - assumes specific count
try testing.expect(pods.len == 5);
```

### 4. Error Messages

Provide helpful error context:

```zig
const pods = service.listPods(null) catch |err| {
    std.debug.print("Failed to list pods: {}\n", .{err});
    return err;
};
```

### 5. Timeout Handling

Handle slow clusters:

```zig
// Future: Add timeout support
const timeout = std.time.ns_per_s * 10; // 10 seconds
```

## Troubleshooting

### "Connection refused"

**Problem:** Cluster is not accessible

**Solutions:**
- Check `kubectl cluster-info`
- Verify VPN connection (for remote clusters)
- Check firewall rules
- Ensure API server is running

### "Forbidden" errors

**Problem:** Insufficient RBAC permissions

**Solutions:**
- Check user permissions: `kubectl auth can-i list pods`
- Use admin context if available
- Grant necessary RBAC permissions

### "Context not found"

**Problem:** Invalid kubeconfig

**Solutions:**
- Check `kubectl config get-contexts`
- Verify kubeconfig path: `~/.kube/config`
- Set correct context: `kubectl config use-context <name>`

### Tests hang indefinitely

**Problem:** Network issues or slow API server

**Solutions:**
- Check network connectivity
- Reduce cluster load
- Use local cluster for testing

## Examples

### Run All Tests

```bash
cd /path/to/c3s
zig build test-integration
```

### Expected Output

```
Test [1/15] K8sService - connect to real cluster... OK
Test [2/15] K8sService - list pods integration... 
  Successfully retrieved 12 pods
  OK
Test [3/15] K8sService - list namespaces integration... 
  Successfully retrieved 5 namespaces
  OK
...
All 15 tests passed.
```

### With No Cluster

```
Test [1/15] K8sService - connect to real cluster... 
  Skipping integration test - no cluster available: error.FileNotFound
  SKIP
...
```

## Contributing

When adding new integration tests:

1. Follow existing patterns
2. Handle cluster unavailability gracefully
3. Clean up all allocated resources
4. Provide informative output
5. Document any special requirements
6. Update this README

## References

- [Kubernetes API Documentation](https://kubernetes.io/docs/reference/kubernetes-api/)
- [kubectl Reference](https://kubernetes.io/docs/reference/kubectl/)
- [zig-klient Documentation](https://github.com/guanchzhou/zig-klient)
- [Zig Testing Documentation](https://ziglang.org/documentation/master/#Testing)

---

**Note:** Integration tests complement unit tests but cannot replace them. Both are necessary for comprehensive test coverage.

