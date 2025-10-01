# zig-klient Issues and Workarounds

This document tracks issues found in the zig-klient library and the workarounds implemented in c3s.

## Current Issues

### 1. TLS Configuration Not Applied (RESOLVED with workaround)

**Issue**: zig-klient's HTTP client doesn't properly apply TLS configuration when making HTTPS requests to Kubernetes API servers with self-signed certificates.

**Error**: `error.TlsInitializationFailed`

**Workaround**: Use `connectWithFallback()` function which:
1. Attempts direct HTTPS connection
2. On TLS failure, automatically falls back to `kubectl proxy` at `http://127.0.0.1:8001`
3. Works seamlessly for localhost clusters (Rancher Desktop, Minikube, etc.)

**Location**: `src/services/k8s_service.zig:144-152`

**Status**: ✅ Implemented - Works for localhost clusters via proxy fallback

**Affected Resources**:
- ✅ Deployments - Works via proxy
- ✅ Services - Works via proxy  
- ✅ Namespaces - Works via proxy
- ✅ Nodes - Works via proxy

### 2. Integer Overflow in std.http.Client (UNRESOLVED)

**Issue**: Zig 0.15.1's `std.http.Client` has buffer size calculation issues causing integer overflow on large response bodies.

**Error**: `integer overflow at src/k8s/client.zig:206:13`

**Affected Operations**:
- ❌ Large namespace listings
- ⚠️ Large pod listings (sometimes)
- ⚠️ Node listings with many nodes

**Potential Solutions**:
1. Upgrade to Zig 0.16+ when available (std.http fixes expected)
2. Implement custom HTTP client with proper buffer management
3. Use chunked response handling
4. Limit response buffer sizes with pagination

**Status**: ⏳ Blocked - Waiting for Zig stdlib fixes or custom HTTP client implementation

### 3. kubectl proxy Requirement (LIMITATION)

**Issue**: For the workaround to function, users must run `kubectl proxy` manually before starting c3s.

**Impact**: Not a true "zero-configuration" experience

**Status**: ⚠️ Documented limitation

**User Instructions**:
```bash
# Terminal 1: Start proxy
kubectl proxy --port=8001 &

# Terminal 2: Run c3s
./zig-out/bin/c3s
```

## Resolved Issues

### 1. ✅ Memory Leaks (RESOLVED)

**Issue**: Multiple memory leaks in string handling and ArrayLists

**Fixed in**: Various files (see MEMORY_STATUS.md)

**Status**: ✅ Resolved

### 2. ✅ Context Flag Ignored (RESOLVED)

**Issue**: `--context` flag was parsed but not used

**Fix**: Pass context override to K8sManager.connect()

**Location**: `src/app.zig:98`, `src/k8s/manager.zig`

**Status**: ✅ Resolved

## Testing Results

### With kubectl proxy running:

| Resource Type | List All | List Namespace | Get | Delete | Update |
|---------------|----------|----------------|-----|--------|--------|
| Pods          | ⏳       | ⏳             | ⏳  | ⏳     | ⏳     |
| Deployments   | ✅       | ✅             | ⏳  | ⏳     | ⏳     |
| Services      | ✅       | ✅             | ⏳  | ⏳     | ⏳     |
| Namespaces    | ✅       | N/A            | ⏳  | ⏳     | N/A    |
| Nodes         | ✅       | N/A            | ⏳  | ⏳     | N/A    |

**Legend**:
- ✅ Working
- ⏳ Not tested yet
- ❌ Fails
- N/A: Not applicable

## Recommendations

### Short-term (Current):
1. ✅ Use `connectWithFallback()` for localhost clusters
2. ✅ Document kubectl proxy requirement
3. ⏳ Implement graceful error messages for users

### Medium-term (Next sprint):
1. ⏳ Add pagination to API calls to avoid large responses
2. ⏳ Implement connection pool to reduce HTTP overhead
3. ⏳ Add retry logic with exponential backoff

### Long-term (Future):
1. ⏳ Wait for Zig 0.16+ std.http fixes
2. ⏳ Consider custom HTTP/2 client implementation
3. ⏳ Add native TLS support without kubectl proxy dependency

## Last Updated

October 1, 2025

## Related Documentation

- HONEST_STATUS.md - Truthful project status
- UPDATED_STATUS.md - Post-fix status
- KLIENT_INTEGRATION.md - Integration guide
- SESSION_SUMMARY.md - Implementation session notes

