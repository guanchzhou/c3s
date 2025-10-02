# End-to-End (E2E) Tests

This directory contains end-to-end tests that simulate complete user workflows in c3s.

## Overview

E2E tests verify that entire user scenarios work correctly from start to finish, testing the integration of all components: UI, commands, views, and services.

## What E2E Tests Cover

Unlike unit tests (testing individual components) or integration tests (testing API interactions), E2E tests focus on **user journeys**:

1. **Application Launch** - Starting c3s and loading initial view
2. **Navigation** - Moving between views using commands
3. **Resource Viewing** - Viewing different Kubernetes resources
4. **Filtering** - Applying and clearing filters
5. **Context Switching** - Changing between different clusters
6. **Theme Switching** - Changing application themes
7. **Error Handling** - How the app behaves with no cluster

## Test Scenarios

###  1. Basic Navigation Flow

```
User Journey:
1. Launch c3s
2. View pods (default view)
3. Press :deployments
4. Navigate to deployments view
5. Press :services
6. Navigate to services view
7. Press q to quit

Expected: Smooth navigation, no crashes, proper cleanup
```

### 2. Filtering Workflow

```
User Journey:
1. Launch c3s on pods view
2. Press / to start filter
3. Type "nginx"
4. See filtered results
5. Press Esc to clear filter
6. See all pods again

Expected: Filter applies correctly, clears correctly
```

### 3. Namespace Toggle

```
User Journey:
1. Launch c3s on pods view
2. See pods in current namespace
3. Press 0 to toggle all namespaces
4. See pods from all namespaces
5. Press 0 again to toggle back

Expected: Namespace switching works, pod counts change
```

### 4. Context Switching

```
User Journey:
1. Launch c3s
2. Press :contexts
3. Navigate to another context
4. Press Enter to switch
5. Verify data loads from new cluster

Expected: Context switches, views refresh with new data
```

### 5. Theme Switching

```
User Journey:
1. Launch c3s
2. Press :themes
3. Navigate to different theme
4. Press Enter to apply
5. See colors change throughout UI

Expected: Theme applies immediately, all colors update
```

### 6. Multi-View Navigation

```
User Journey:
1. Launch c3s on pods view
2. Press :nodes
3. Navigate with j/k
4. Press :events
5. View recent events
6. Press Esc to go back
7. Return to pods view

Expected: View stack works correctly, navigation smooth
```

### 7. Error Handling - No Cluster

```
User Journey:
1. Configure invalid/unreachable cluster
2. Launch c3s --debug
3. See appropriate error message or dummy data
4. Navigate normally with debug data
5. Quit cleanly

Expected: Graceful degradation, no crashes
```

### 8. Rapid Command Execution

```
User Journey:
1. Launch c3s
2. Rapidly execute: :deploy, :svc, :pods, :ns, :nodes
3. Each view loads correctly
4. No memory leaks
5. Quit cleanly

Expected: Handles rapid view switching, stable performance
```

### 9. Resource Refresh

```
User Journey:
1. Launch c3s on pods view
2. Note current pod count
3. Press r to refresh
4. See updated data
5. Press r multiple times rapidly
6. No crashes or duplication

Expected: Refresh works correctly, handles rapid refresh
```

### 10. Complete Session

```
User Journey:
1. Launch c3s
2. View multiple resource types (5+)
3. Apply filters on 2-3 views
4. Switch contexts once
5. Change theme once
6. Navigate extensively (100+ key presses)
7. Quit normally

Expected: Entire session works smoothly, no memory leaks
```

## Running E2E Tests

### Prerequisites

- Built c3s binary: `zig build`
- Optional: Kubernetes cluster for full testing
- Alternative: Use `--debug` flag for offline testing

### Run All E2E Tests

```bash
# With real cluster
zig build test-e2e

# With debug data (no cluster required)
zig build test-e2e-debug
```

### Run Specific Scenario

```bash
# Test only navigation
zig test tests/e2e/navigation_test.zig

# Test only filtering
zig test tests/e2e/filtering_test.zig
```

## Test Implementation

E2E tests use a **simulated terminal** approach:

```zig
// Example E2E test structure
test "complete navigation workflow" {
    var app = try App.init(allocator);
    defer app.deinit();

    // Simulate user pressing :deployments
    try app.handleCommand(":deployments");
    
    // Verify we're on deployments view
    try testing.expect(app.current_view == .deployments);
    
    // Simulate navigation
    try app.handleKey(.{ .char = 'j' });
    try app.handleKey(.{ .char = 'j' });
    
    // Verify selection changed
    try testing.expect(app.deployments_view.selected_index == 2);
}
```

## Test Organization

```
tests/e2e/
├── README.md                    # This file
├── navigation_test.zig          # Navigation scenarios
├── filtering_test.zig           # Filtering scenarios
├── context_switch_test.zig      # Context switching
├── theme_switch_test.zig        # Theme switching
├── resource_viewing_test.zig    # Resource viewing workflows
├── error_handling_test.zig      # Error scenarios
└── full_session_test.zig        # Complete user sessions
```

## Metrics & Success Criteria

### Performance Metrics

- **Startup Time:** < 1 second
- **View Switch Time:** < 100ms
- **Filter Response:** < 50ms
- **Memory Usage:** < 100MB for typical session
- **No Memory Leaks:** All allocations freed

### Reliability Metrics

- **Crash Rate:** 0% (no crashes during normal operation)
- **Error Recovery:** 100% (graceful handling of all errors)
- **Data Consistency:** 100% (data always matches K8s API)

### User Experience Metrics

- **Navigation Smoothness:** No lag on key presses
- **Visual Consistency:** Themes apply correctly everywhere
- **Command Accuracy:** All commands work as documented

## CI/CD Integration

### GitHub Actions Workflow

```yaml
name: E2E Tests

on: [push, pull_request]

jobs:
  e2e-debug:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Build c3s
        run: zig build
      - name: Run E2E tests (debug mode)
        run: zig build test-e2e-debug

  e2e-cluster:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Setup k3s
        run: |
          curl -sfL https://get.k3s.io | sh -
          sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
      - name: Build c3s
        run: zig build
      - name: Run E2E tests (with cluster)
        run: zig build test-e2e
```

## Debugging E2E Tests

### Enable Verbose Output

```bash
# See detailed test output
zig build test-e2e --summary all

# Run specific test with verbose
zig test tests/e2e/navigation_test.zig --test-filter "navigation workflow"
```

### Capture Screenshots

E2E tests can capture terminal state for debugging:

```zig
// In test
try app.render();
const screenshot = try app.terminal.captureScreen();
std.debug.print("Screen state:\n{s}\n", .{screenshot});
```

### Test with Real Terminal

For manual E2E testing:

```bash
# Record terminal session
script -q /tmp/c3s-session.txt
./zig-out/bin/c3s --debug
# Perform test actions
exit

# Review recording
cat /tmp/c3s-session.txt
```

## Common Issues & Solutions

### Issue: Tests timeout

**Cause:** Slow K8s API responses

**Solution:**
- Use debug mode for faster tests
- Increase timeout values
- Mock slow API calls

### Issue: Flaky tests

**Cause:** Race conditions or timing issues

**Solution:**
- Add appropriate waits
- Use event-based synchronization
- Avoid time-based assertions

### Issue: Memory leaks in E2E tests

**Cause:** Views not properly cleaned up

**Solution:**
- Ensure all views have `defer view.deinit()`
- Check ViewManager cleanup
- Use `testing.allocator` to detect leaks

### Issue: Tests pass locally but fail in CI

**Cause:** Different terminal environment

**Solution:**
- Mock terminal size/capabilities
- Don't depend on specific terminal features
- Test with minimal terminal emulation

## Best Practices

### 1. Test Real User Workflows

❌ **Bad:** Test each function individually
```zig
test "pods view renders" { ... }
test "deployments view renders" { ... }
```

✅ **Good:** Test complete user journey
```zig
test "user views pods then switches to deployments" {
    // Full workflow from start to finish
}
```

### 2. Use Realistic Scenarios

❌ **Bad:** Test with empty data
```zig
var pods = &[_]Pod{};
```

✅ **Good:** Test with realistic data
```zig
var pods = &[_]Pod{
    // Multiple pods with various states
    running_pod, pending_pod, failed_pod,
};
```

### 3. Test Error Paths

❌ **Bad:** Only test happy path
```zig
test "view pods" {
    // Assume pods load successfully
}
```

✅ **Good:** Test error scenarios too
```zig
test "view pods when API fails" {
    // Test graceful error handling
}
```

### 4. Verify Cleanup

❌ **Bad:** Don't check for leaks
```zig
test "workflow" {
    var app = try App.init(allocator);
    // ... test code ...
}
```

✅ **Good:** Always verify cleanup
```zig
test "workflow" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        try testing.expect(leaked == .ok);
    }
    // ... test code ...
}
```

### 5. Test Performance

✅ **Good:** Include timing checks
```zig
test "view switch is fast" {
    const start = std.time.milliTimestamp();
    try app.switchView(.deployments);
    const elapsed = std.time.milliTimestamp() - start;
    try testing.expect(elapsed < 100); // < 100ms
}
```

## Future Enhancements

### Planned E2E Tests

- [ ] Pod logs viewing
- [ ] Port forwarding workflow
- [ ] YAML editing
- [ ] Resource creation/deletion
- [ ] Multi-cluster workflows
- [ ] Custom resource views
- [ ] Plugin system testing

### Automation

- [ ] Automated E2E test execution on PR
- [ ] Performance regression testing
- [ ] Visual regression testing
- [ ] Load testing (1000+ resources)

## Contributing

When adding new E2E tests:

1. **Identify the user workflow** you want to test
2. **Write a clear test scenario** in this README
3. **Implement the test** following existing patterns
4. **Verify with both debug and real cluster**
5. **Check for memory leaks** using GPA
6. **Update this README** with new test info

## References

- [App Architecture](../../docs/MVVM_ARCHITECTURE.md)
- [Testing Guide](../../docs/TESTING.md)
- [View System](../../docs/ARCHITECTURE.md#view-system)
- [Command System](../../docs/ARCHITECTURE.md#command-system)

---

**Note:** E2E tests are the most important for ensuring c3s works well for end users. Invest time in comprehensive E2E test coverage.

