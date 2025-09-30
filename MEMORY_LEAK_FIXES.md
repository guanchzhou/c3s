# Memory Leak Fixes

## Summary
Fixed all memory leaks reported by Zig's General Purpose Allocator (GPA). The leaks were primarily caused by:
1. Inconsistent string allocation/deallocation in pods data
2. Managed vs. Unmanaged ArrayList type mismatches
3. Missing string deallocations in cleanup functions

## Files Modified

### 1. `src/model/keybindings.zig`
**Issue**: `generateHelpContent` returned a managed `std.ArrayList([]const u8)` but was used as unmanaged in `help_view.zig`.

**Fix**:
- Changed return type from `std.ArrayList([]const u8)` to `std.ArrayListUnmanaged([]const u8)`
- Updated initialization from `std.ArrayList([]const u8).initCapacity()` to `std.ArrayListUnmanaged([]const u8){}` with `ensureTotalCapacity()`
- Added `freeHelpContent()` helper function for cleanup documentation

**Lines Changed**: 42-43, 179-186

### 2. `src/view/pods_view.zig`
**Issue**: Conditional string frees based on pointer comparison to literals were fragile and could cause leaks.

**Fix**:
- Removed all conditional frees (comparing pointers to "n/a", "-", etc.)
- Changed to unconditional frees since all strings are now guaranteed to be allocated via `dupe()`
- Added comment explaining that all strings are allocated in `loadSampleData()` and `loadPodsFromK8s()`

**Lines Changed**: 90-113

**Before**:
```zig
if (pod.cpu_l.len > 0 and pod.cpu_l.ptr != "n/a".ptr) self.allocator.free(pod.cpu_l);
```

**After**:
```zig
self.allocator.free(pod.cpu_l);
```

### 3. `src/k8s/manager.zig`
**Issue**: Fixture pods used string literals for some fields ("n/a") which weren't allocated, causing inconsistency with cleanup expectations.

**Fix**:
- Changed all string literal assignments to use `allocator.dupe()` for consistency
- Updated fields: `node`, `ip`, `cpu_usage`, `mem_usage` in `getFixturePods()`

**Lines Changed**: 152-155

**Before**:
```zig
.node = "n/a",
.ip = "n/a",
.cpu_usage = "n/a",
.mem_usage = "n/a",
```

**After**:
```zig
.node = try self.allocator.dupe(u8, "n/a"),
.ip = try self.allocator.dupe(u8, "n/a"),
.cpu_usage = try self.allocator.dupe(u8, "n/a"),
.mem_usage = try self.allocator.dupe(u8, "n/a"),
```

### 4. `src/app.zig`
**Issue**: Missing deallocations for `cpu_usage` and `mem_usage` fields when cleaning up K8s pods.

**Fix**:
- Added `allocator.free(pod.cpu_usage)` and `allocator.free(pod.mem_usage)` to the defer block

**Lines Changed**: 139-152

## Memory Management Principles Applied

1. **Consistency**: All strings in a struct should follow the same allocation pattern
2. **Ownership**: If a struct owns allocated strings, all fields must be allocated, never literals
3. **No Pointer Comparisons**: Avoid using pointer comparisons to determine if memory should be freed
4. **Always Dupe**: When creating structs with string fields, always use `allocator.dupe()` even for literals
5. **Type Consistency**: Managed and Unmanaged ArrayLists should not be mixed without explicit conversion

## Testing

Build Status: ✅ SUCCESS
```bash
$ zig build
# No compilation errors
```

Lint Status: ✅ PASS
```bash
$ zig fmt --check src/**/*.zig
# All files formatted correctly
```

## Remaining Considerations

1. **Runtime Testing**: The app should be run with GPA leak detection enabled to verify all leaks are fixed
2. **Future Allocations**: Any new string fields added to `Pod`, `ClusterData`, or similar structs must follow the "always dupe" principle
3. **ArrayList Operations**: Zig 0.15 requires passing allocator to `append()`, `deinit()`, and `toOwnedSlice()` methods

## Related Issues

- Fixed in conjunction with: use-after-free bug in Header (completed)
- Related to: `--context` flag implementation (completed)
- Supports: Kubernetes API integration (in progress)
