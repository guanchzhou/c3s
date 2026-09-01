/// Kubernetes Service Layer
///
/// Wraps zig-klient to provide a clean interface for c3s views.
/// Handles client initialization, authentication, and resource operations.
const std = @import("std");
const klient = @import("klient");
const Logger = @import("../core/logger.zig");
const k8s_types = @import("k8s_types.zig");
const runtime = @import("../core/runtime.zig");
const env = @import("../core/env.zig");
const xdg = @import("../core/xdg.zig");
const clock = @import("../core/clock.zig");
const active_context = @import("../k8s/ActiveContextSession.zig");
const active_slot = @import("../k8s/ActiveSessionSlot.zig");
const ActiveContextSession = active_context.ActiveContextSession;
const ActiveSessionSlot = active_slot.ActiveSessionSlot;

// Re-export shared types so existing `@import("services/K8sService.zig").ClusterInfo` etc. keep working.
pub const ClusterInfo = k8s_types.ClusterInfo;
pub const ResourceType = k8s_types.ResourceType;
pub const ResourceInfo = k8s_types.ResourceInfo;

/// Kubernetes service for managing cluster connections and resource operations
pub const K8sService = struct {
    const FacadeSnapshot = struct {
        context_name: []u8,
        cluster_name: []u8,
        user_name: []u8,
        current_namespace: []u8,

        fn clone(
            allocator: std.mem.Allocator,
            session: *const ActiveContextSession,
        ) !FacadeSnapshot {
            const context_name = try allocator.dupe(u8, session.spec.context_name);
            errdefer allocator.free(context_name);
            const cluster_name = try allocator.dupe(u8, session.cluster_name);
            errdefer allocator.free(cluster_name);
            const user_name = try allocator.dupe(u8, session.user_name);
            errdefer allocator.free(user_name);
            const current_namespace = try allocator.dupe(
                u8,
                session.spec.default_namespace,
            );
            return .{
                .context_name = context_name,
                .cluster_name = cluster_name,
                .user_name = user_name,
                .current_namespace = current_namespace,
            };
        }

        fn deinit(self: *FacadeSnapshot, allocator: std.mem.Allocator) void {
            allocator.free(self.context_name);
            allocator.free(self.cluster_name);
            allocator.free(self.user_name);
            allocator.free(self.current_namespace);
            self.* = undefined;
        }
    };

    const ResolvedRequest = struct {
        lease: ?active_context.RequestLease,
        client: ?*klient.K8sClient,
        use_kubectl: bool,
        proxy_port: ?u16,
        context_name: []const u8,
        kubeconfig_path: ?[]const u8,
        credentials: ?*active_context.CredentialProvider,

        fn deinit(self: *ResolvedRequest) void {
            if (self.lease) |*lease| lease.release();
            self.lease = null;
        }
    };

    allocator: std.mem.Allocator,
    connected: bool,
    current_namespace: []const u8,
    context_name: []const u8,
    cluster_name: []const u8,
    user_name: []const u8,
    session_slot: ?*ActiveSessionSlot = null,
    session_factory: active_context.SessionFactory = active_context.SessionFactory.production(),
    kubeconfig_path: ?[]const u8 = null,
    kubeconfig_parser_allocator: ?std.mem.Allocator = null,

    // Cached server version (fetched once from /version endpoint)
    cached_k8s_version: ?[]const u8 = null,
    // Set to true after first version fetch failure to avoid repeated attempts that may panic
    version_fetch_failed: bool = false,
    // Set to true after connect() has been called at least once
    connect_attempted: bool = false,
    // When true, use `kubectl get --raw` for API calls instead of klient's HTTP client
    use_kubectl: bool = false,
    /// When true, every cluster-mutating method fails with error.ReadOnlyMode.
    ///
    /// Set from `--readonly`. Enforced HERE rather than in the UI: the flag was
    /// previously parsed, advertised in --help, and consulted nowhere, so
    /// `c3s --readonly` permitted deletion. Guarding at the service boundary means
    /// a new caller cannot forget it, and Phase 4's mutations inherit it for free.
    readonly: bool = false,

    /// Wrapper around parsed pod lists so callers can keep JSON alive while consuming
    const PodList = std.json.Parsed(klient.types.List(klient.types.Pod));

    /// Initialize the K8s service
    pub fn init(allocator: std.mem.Allocator) !K8sService {
        const current_namespace = try allocator.dupe(u8, "default");
        errdefer allocator.free(current_namespace);
        const context_name = try allocator.dupe(u8, "unknown");
        errdefer allocator.free(context_name);
        const cluster_name = try allocator.dupe(u8, "unknown");
        errdefer allocator.free(cluster_name);
        const user_name = try allocator.dupe(u8, "unknown");
        return K8sService{
            .allocator = allocator,
            .connected = false,
            .current_namespace = current_namespace,
            .context_name = context_name,
            .cluster_name = cluster_name,
            .user_name = user_name,
        };
    }

    /// Bind this non-owning facade to App's active slot.
    pub fn bindSessionSlot(self: *K8sService, slot: *ActiveSessionSlot) void {
        self.session_slot = slot;
    }

    /// Preserve the CLI kubeconfig override in each copied ContextSpec.
    pub fn setKubeconfigPath(self: *K8sService, path: ?[]const u8) void {
        self.kubeconfig_path = path;
    }

    /// Return the exact active slot shared with the future DataPlane facade.
    pub fn sessionSlot(self: *K8sService) ?*ActiveSessionSlot {
        return self.session_slot;
    }

    /// Resolve the session-owned proxy endpoint.
    pub fn proxyPort(self: *K8sService) ?u16 {
        var lease = (self.acquireRequest(.command) catch return null) orelse return null;
        defer lease.release();
        return lease.session.requestView().proxy_port;
    }

    /// Acquire a caller-owned request lease from the active generation.
    pub fn acquireRequest(
        self: *K8sService,
        purpose: active_context.LeasePurpose,
    ) !?active_context.RequestLease {
        const slot = self.session_slot orelse return null;
        return try slot.acquire(null, purpose);
    }

    fn resolveRequest(
        self: *K8sService,
        purpose: active_context.LeasePurpose,
    ) !ResolvedRequest {
        if (self.session_slot) |slot| {
            if (try slot.acquire(null, purpose)) |acquired| {
                var lease = acquired;
                const session = lease.session;
                const view = session.requestView();
                const client = lease.client() catch |err| {
                    lease.release();
                    return err;
                };
                return .{
                    .lease = lease,
                    .client = client,
                    .use_kubectl = view.use_kubectl,
                    .proxy_port = view.proxy_port,
                    .context_name = view.context_name,
                    .kubeconfig_path = view.kubeconfig_path,
                    .credentials = view.credentials,
                };
            }
        }
        return error.NotConnected;
    }

    fn publishSession(
        self: *K8sService,
        session: *ActiveContextSession,
        snapshot: *FacadeSnapshot,
    ) void {
        self.allocator.free(self.context_name);
        self.allocator.free(self.cluster_name);
        self.allocator.free(self.user_name);
        self.allocator.free(self.current_namespace);
        if (self.cached_k8s_version) |version| self.allocator.free(version);
        self.cached_k8s_version = null;
        self.version_fetch_failed = false;
        self.context_name = snapshot.context_name;
        self.cluster_name = snapshot.cluster_name;
        self.user_name = snapshot.user_name;
        self.current_namespace = snapshot.current_namespace;
        snapshot.* = undefined;
        self.connected = true;
        self.use_kubectl = session.requestView().use_kubectl;
    }

    /// Detach facade aliases before App destroys the invalidated session.
    pub fn detachSession(self: *K8sService) void {
        self.connected = false;
        self.use_kubectl = false;
    }

    /// Clean up resources
    pub fn deinit(self: *K8sService) void {
        self.connected = false;
        self.allocator.free(self.current_namespace);
        self.allocator.free(self.context_name);
        self.allocator.free(self.cluster_name);
        self.allocator.free(self.user_name);

        // Free cached server version if allocated
        if (self.cached_k8s_version) |v| self.allocator.free(v);
    }

    fn refreshCredentialProvider(
        self: *K8sService,
        provider: *active_context.CredentialProvider,
    ) void {
        const cmd = provider.exec_command orelse return;
        const cfg = klient.exec_credential.ExecConfig{
            .command = cmd,
            .args = provider.exec_args,
            .apiVersion = provider.exec_api_version orelse "client.authentication.k8s.io/v1beta1",
        };
        const cred = klient.exec_credential.executeCredentialPlugin(self.allocator, runtime.io(), cfg) catch return;
        // The Parsed arena owns all credential strings — without this deinit the
        // token-bearing buffer leaked on every refresh.
        defer cred.deinit();
        if (cred.value.status) |s| {
            if (s.token) |tok| {
                provider.replaceToken(tok) catch return;
                std.crypto.secureZero(u8, @constCast(tok));
                Logger.info("Refreshed exec-auth token", .{});
            }
        }
    }

    /// Connect to Kubernetes cluster using kubeconfig
    pub fn hasAttemptedConnect(self: *const K8sService) bool {
        return self.connect_attempted;
    }

    pub fn connect(self: *K8sService, context_override: ?[]const u8) !void {
        self.connect_attempted = true;
        const slot = self.session_slot orelse return error.SessionSlotUnbound;
        const force_proxy = if (env.getOwned(self.allocator, "C3S_FORCE_PROXY")) |value| blk: {
            defer self.allocator.free(value);
            break :blk std.ascii.eqlIgnoreCase(value, "1") or
                std.ascii.eqlIgnoreCase(value, "true");
        } else |_| false;
        const generation = try slot.reserveGeneration();
        const session = try self.session_factory.prepare(
            self.allocator,
            runtime.io(),
            slot.shared_event,
            generation,
            .{
                .context_name = context_override orelse "",
                .kubeconfig_path = self.kubeconfig_path,
                .default_namespace = self.current_namespace,
                .force_proxy = force_proxy,
                .readonly = self.readonly,
            },
        );
        var session_owned = true;
        defer if (session_owned) session.deinit();
        try session.ensureReady();

        var snapshot = try FacadeSnapshot.clone(self.allocator, session);
        var snapshot_owned = true;
        defer if (snapshot_owned) snapshot.deinit(self.allocator);

        const previous = try slot.commit(session);
        self.publishSession(session, &snapshot);
        snapshot_owned = false;
        session_owned = false;

        if (previous) |old| {
            try old.checkTeardownReady();
            old.deinit();
        }
    }

    // ── Transport hint cache ────────────────────────────────────────────────
    // State file `transport-hints`: one "<unix-ts> <server>" line per cluster
    // whose direct-TLS probe failed. Best-effort — any I/O failure simply
    // means the probe runs as before.

    const transport_hint_ttl: i64 = 24 * 60 * 60;

    fn transportHintsPath(self: *K8sService) ?[]u8 {
        const paths = xdg.ensurePaths() catch return null;
        return std.fs.path.join(self.allocator, &.{ paths.state_dir, "transport-hints" }) catch null;
    }

    fn readTransportHints(self: *K8sService, path: []const u8) ?[]u8 {
        return std.Io.Dir.cwd().readFileAlloc(runtime.io(), path, self.allocator, .limited(64 * 1024)) catch null;
    }

    /// True when `server` failed its direct-TLS probe within the TTL.
    fn directTlsKnownBad(self: *K8sService, server: []const u8) bool {
        const path = self.transportHintsPath() orelse return false;
        defer self.allocator.free(path);
        const content = self.readTransportHints(path) orelse return false;
        defer self.allocator.free(content);
        return hintsContainFresh(content, server, clock.timestamp(), transport_hint_ttl);
    }

    /// Record (`bad = true`) or clear (`bad = false`) the failure hint for `server`.
    fn setTransportHint(self: *K8sService, server: []const u8, bad: bool) void {
        if (std.mem.indexOfAny(u8, server, " \n") != null) return; // keep the line format unambiguous
        const path = self.transportHintsPath() orelse return;
        defer self.allocator.free(path);

        var out: std.ArrayList(u8) = .empty;
        defer out.deinit(self.allocator);

        // Keep other servers' entries; drop any existing entry for this one.
        var had_entry = false;
        if (self.readTransportHints(path)) |content| {
            defer self.allocator.free(content);
            var lines = std.mem.splitScalar(u8, content, '\n');
            while (lines.next()) |line| {
                if (line.len == 0) continue;
                const sp = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
                if (std.mem.eql(u8, line[sp + 1 ..], server)) {
                    had_entry = true;
                    continue;
                }
                out.appendSlice(self.allocator, line) catch return;
                out.append(self.allocator, '\n') catch return;
            }
        }
        if (!bad and !had_entry) return; // nothing to change — skip the write

        if (bad) {
            const entry = std.fmt.allocPrint(self.allocator, "{d} {s}\n", .{ clock.timestamp(), server }) catch return;
            defer self.allocator.free(entry);
            out.appendSlice(self.allocator, entry) catch return;
        }
        std.Io.Dir.cwd().writeFile(runtime.io(), .{ .sub_path = path, .data = out.items }) catch |err| {
            Logger.warn("transport-hints write failed: {any}", .{err});
        };
    }

    /// Pure scan of hint-file content: does `server` have an entry newer than `ttl`?
    fn hintsContainFresh(content: []const u8, server: []const u8, now: i64, ttl: i64) bool {
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const sp = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
            if (!std.mem.eql(u8, line[sp + 1 ..], server)) continue;
            const ts = std.fmt.parseInt(i64, line[0..sp], 10) catch continue;
            return now - ts < ttl;
        }
        return false;
    }

    /// Like kubectlRequest but uses `a` for the response body allocation instead
    /// of self.allocator. Safe to call from a worker thread — the response buffer
    /// is owned by `a`, never by the shared App GPA. URL/argv scratch allocations
    /// internally still use self.allocator for buildKubectlArgv, BUT those are
    /// allocated and freed entirely within the call (no cross-thread sharing window
    /// since the main thread never allocates concurrently with the worker on the
    /// same GPA — the worker only calls this from workerMain where the main thread
    /// is in poll/render with no allocations in flight). The response buffer (the
    /// only long-lived result) uses `a`.
    pub fn kubectlRequestAlloc(self: *K8sService, a: std.mem.Allocator, path: []const u8) ![]u8 {
        var request = try self.resolveRequest(.traffic);
        defer request.deinit();
        return self.kubectlRequestAllocResolved(a, &request, path);
    }

    fn kubectlRequestAllocResolved(
        self: *K8sService,
        a: std.mem.Allocator,
        request: *ResolvedRequest,
        path: []const u8,
    ) ![]u8 {
        // Fast path: proxy (curl subprocess) with caller's allocator for the result.
        if (request.proxy_port) |port| {
            if (self.proxyRequestAlloc(a, port, path)) |body| {
                return body;
            } else |_| {
                // Proxy died — fall through.
            }
        }
        return self.kubectlRequestOnceAlloc(a, request, path) catch |err| {
            if (request.credentials) |provider| {
                if (provider.exec_command == null) return err;
                self.refreshCredentialProvider(provider);
                return self.kubectlRequestOnceAlloc(a, request, path);
            }
            return err;
        };
    }

    fn proxyRequestAlloc(self: *K8sService, a: std.mem.Allocator, port: u16, path: []const u8) ![]u8 {
        const url = try std.fmt.allocPrint(self.allocator, "http://127.0.0.1:{d}{s}", .{ port, path });
        defer self.allocator.free(url);
        const result = std.process.run(a, runtime.io(), .{
            .argv = &.{ "curl", "-sf", "--max-time", "8", url },
            .stdout_limit = .limited(128 * 1024 * 1024),
        }) catch return error.KubectlFailed;
        defer a.free(result.stderr);
        if (result.term.exited != 0) {
            a.free(result.stdout);
            return error.KubectlFailed;
        }
        return result.stdout;
    }

    /// POST a JSON body through the local `kubectl proxy` via curl.
    ///
    /// The kubectl transport has no POST path -- `kubectl get --raw` is read-only --
    /// so SelfSubjectAccessReview could not be issued at all in kubectl mode. Going
    /// through the proxy keeps it a single fast localhost call and preserves full
    /// response fidelity (including the KEP-5681 condition chain), which
    /// `kubectl auth can-i` would discard. It is also the only option that does not
    /// cost a ~1.5s subprocess per cell: the access grid issues 48 checks.
    fn proxyPostResolved(
        self: *K8sService,
        request: *const ResolvedRequest,
        path: []const u8,
        body: []const u8,
    ) ![]u8 {
        const port = request.proxy_port orelse return error.ProxyUnavailable;
        const url = try std.fmt.allocPrint(self.allocator, "http://127.0.0.1:{d}{s}", .{ port, path });
        defer self.allocator.free(url);

        const result = std.process.run(self.allocator, runtime.io(), .{
            .argv = &.{
                "curl",          "-sf",
                "--max-time",    "8",
                "-X",            "POST",
                "-H",            "Content-Type: application/json",
                "--data-binary", body,
                url,
            },
            .stdout_limit = .limited(1024 * 1024),
        }) catch return error.KubectlFailed;
        defer self.allocator.free(result.stderr);

        if (result.term != .exited or result.term.exited != 0) {
            self.allocator.free(result.stdout);
            return error.KubectlFailed;
        }
        return result.stdout;
    }

    fn kubectlRequestOnceAlloc(
        self: *K8sService,
        a: std.mem.Allocator,
        request: *const ResolvedRequest,
        path: []const u8,
    ) ![]u8 {
        const argv = try self.buildKubectlArgvResolved(request, &.{ "get", "--raw", path });
        defer self.allocator.free(argv);
        const result = std.process.run(a, runtime.io(), .{
            .argv = argv,
            .stdout_limit = .limited(128 * 1024 * 1024),
        });
        const output = result catch |err| {
            Logger.warn("kubectl request failed for path '{s}': {}", .{ path, err });
            return error.KubectlFailed;
        };
        defer a.free(output.stderr);
        if (output.term.exited != 0) {
            defer a.free(output.stdout);
            const reason = std.mem.trim(u8, output.stderr, " \r\n\t");
            Logger.warn("kubectl exited with code {} for path '{s}': {s}", .{
                output.term.exited, path, reason[0..@min(reason.len, 300)],
            });
            if (std.mem.indexOf(u8, reason, "Forbidden") != null) return error.Forbidden;
            return error.KubectlFailed;
        }
        return output.stdout;
    }

    /// Execute a raw kubectl request and return the JSON response.
    /// Uses `kubectl get --raw <path> --context <context>` which handles
    /// TLS, auth, and exec credentials via Go's standard library.
    pub fn kubectlRequest(self: *K8sService, path: []const u8) ![]u8 {
        var request = try self.resolveRequest(.detail);
        defer request.deinit();
        return self.kubectlRequestResolved(&request, path);
    }

    fn kubectlRequestResolved(
        self: *K8sService,
        request: *ResolvedRequest,
        path: []const u8,
    ) ![]u8 {
        // Fast path: the persistent kubectl proxy over localhost.
        if (request.proxy_port) |port| {
            if (self.proxyRequest(port, path)) |body| {
                return body;
            } else |_| {
                // Proxy died/unreachable — fall through to per-call kubectl.
            }
        }
        return self.kubectlRequestOnce(request, path) catch |err| {
            // A failure may be an expired token. If we have an exec plugin,
            // refresh once and retry — transparently handles token expiry.
            if (request.credentials) |provider| {
                if (provider.exec_command == null) return err;
                self.refreshCredentialProvider(provider);
                return self.kubectlRequestOnce(request, path);
            }
            return err;
        };
    }

    fn kubectlRequestOnce(
        self: *K8sService,
        request: *const ResolvedRequest,
        path: []const u8,
    ) ![]u8 {
        const argv = try self.buildKubectlArgvResolved(request, &.{ "get", "--raw", path });
        defer self.allocator.free(argv);
        const result = std.process.run(self.allocator, runtime.io(), .{
            .argv = argv,
            .stdout_limit = .limited(128 * 1024 * 1024), // 128MB max
        });

        const output = result catch |err| {
            Logger.warn("kubectl request failed for path '{s}': {}", .{ path, err });
            return error.KubectlFailed;
        };
        defer self.allocator.free(output.stderr);

        if (output.term.exited != 0) {
            defer self.allocator.free(output.stdout);
            // Surface kubectl's own reason (RBAC denials, expired creds, …) —
            // a bare exit code hides e.g. `pods is forbidden: User "x" cannot
            // list …` and sends debugging down the wrong path entirely.
            const reason = std.mem.trim(u8, output.stderr, " \r\n\t");
            Logger.warn("kubectl exited with code {} for path '{s}': {s}", .{
                output.term.exited, path, reason[0..@min(reason.len, 300)],
            });
            if (std.mem.indexOf(u8, reason, "Forbidden") != null) return error.Forbidden;
            return error.KubectlFailed;
        }

        return output.stdout;
    }

    /// Run `kubectl api-resources` and return its raw, column-aligned output
    /// (NAME / SHORTNAMES / APIVERSION / NAMESPACED / KIND). Caller frees.
    pub fn listApiResources(self: *K8sService) ![]u8 {
        var request = try self.resolveRequest(.detail);
        defer request.deinit();
        const argv = try self.buildKubectlArgvResolved(&request, &.{"api-resources"});
        defer self.allocator.free(argv);
        const result = std.process.run(self.allocator, runtime.io(), .{
            .argv = argv,
            .stdout_limit = .limited(8 * 1024 * 1024),
        });
        const output = result catch return error.KubectlFailed;
        defer self.allocator.free(output.stderr);
        if (output.term.exited != 0) {
            defer self.allocator.free(output.stdout);
            return error.KubectlFailed;
        }
        return output.stdout;
    }

    /// Build `kubectl [--context <ctx>] <args...>` into an owned argv.
    ///
    /// --context pins kubectl to the cluster c3s is connected to: after an
    /// in-app context switch, kubectl's own current-context (the shell
    /// kubeconfig) may point at a DIFFERENT cluster — presenting the new
    /// context's token to the old server yields Forbidden for everything.
    /// Credentials are intentionally not placed in argv. Kubectl resolves the
    /// selected context's credential provider itself.
    fn buildKubectlArgv(self: *K8sService, args: []const []const u8) ![]const []const u8 {
        const request = ResolvedRequest{
            .lease = null,
            .client = null,
            .use_kubectl = self.use_kubectl,
            .proxy_port = self.proxyPort(),
            .context_name = self.context_name,
            .kubeconfig_path = self.kubeconfig_path,
            .credentials = null,
        };
        return self.buildKubectlArgvResolved(&request, args);
    }

    fn buildKubectlArgvResolved(
        self: *K8sService,
        request: *const ResolvedRequest,
        args: []const []const u8,
    ) ![]const []const u8 {
        var argv = std.ArrayListUnmanaged([]const u8).empty;
        errdefer argv.deinit(self.allocator);
        try argv.append(self.allocator, "kubectl");
        if (request.kubeconfig_path) |path| {
            try argv.append(self.allocator, "--kubeconfig");
            try argv.append(self.allocator, path);
        }
        if (!std.mem.eql(u8, request.context_name, "unknown")) {
            try argv.append(self.allocator, "--context");
            try argv.append(self.allocator, request.context_name);
        }
        for (args) |a| try argv.append(self.allocator, a);
        return argv.toOwnedSlice(self.allocator);
    }

    /// Start the active session's OS-port-selected proxy. The facade never owns it.
    pub fn startProxy(self: *K8sService) void {
        var lease = (self.acquireRequest(.command) catch return) orelse return;
        defer lease.release();
        const session = lease.session;
        session.startProxy() catch |err| {
            Logger.warn("kubectl proxy startup failed: {any}; using per-call kubectl", .{err});
            return;
        };
        self.use_kubectl = session.requestView().use_kubectl;
    }

    /// GET a raw API path through the local kubectl proxy (no per-call TLS/auth).
    fn proxyRequest(self: *K8sService, port: u16, path: []const u8) ![]u8 {
        const url = try std.fmt.allocPrint(self.allocator, "http://127.0.0.1:{d}{s}", .{ port, path });
        defer self.allocator.free(url);
        const result = std.process.run(self.allocator, runtime.io(), .{
            .argv = &.{ "curl", "-sf", "--max-time", "8", url },
            .stdout_limit = .limited(128 * 1024 * 1024),
        }) catch return error.KubectlFailed;
        defer self.allocator.free(result.stderr);
        if (result.term.exited != 0) {
            self.allocator.free(result.stdout);
            return error.KubectlFailed;
        }
        return result.stdout;
    }

    /// Run a one-shot kubectl command (e.g. `set image`, `cp`, `delete`).
    /// Returns error.KubectlFailed on non-zero exit.
    ///
    /// Every caller is a mutation (`set image`, `patch` finalizers, `cp`). The
    /// guard lives here so a new caller cannot forget `--readonly` the way the
    /// original delete path did.
    pub fn runKubectl(self: *K8sService, args: []const []const u8) !void {
        try self.assertMutable();
        var request = try self.resolveRequest(.command);
        defer request.deinit();
        const argv = try self.buildKubectlArgvResolved(&request, args);
        defer self.allocator.free(argv);
        const result = std.process.run(self.allocator, runtime.io(), .{
            .argv = argv,
            .stdout_limit = .limited(1024 * 1024),
        }) catch return error.KubectlFailed;
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        if (result.term.exited != 0) return error.KubectlFailed;
    }

    /// Spawn a long-running kubectl command detached from the TUI terminal
    /// (stdio → /dev/null), e.g. `port-forward`. Caller owns the returned Child
    /// and must kill/wait it.
    ///
    /// Port-forward is a local tunnel into the cluster, so `--readonly` refuses
    /// it the same way it refuses mutations. The only current caller is
    /// port-forward; if a read-only spawn is ever needed, give it a separate
    /// method that does not call assertMutable.
    pub fn spawnKubectl(self: *K8sService, args: []const []const u8) !std.process.Child {
        try self.assertMutable();
        var request = try self.resolveRequest(.command);
        defer request.deinit();
        const argv = try self.buildKubectlArgvResolved(&request, args);
        defer self.allocator.free(argv);
        return std.process.spawn(runtime.io(), .{
            .argv = argv,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        });
    }

    // NOTE: a former updateNamesFromKubectl() helper (read the SHELL's
    // current-context via `kubectl config current-context`) was deleted: it
    // had no callers, and after an in-app context switch it would overwrite
    // context_name with the shell's context — breaking the --context pinning
    // that keeps kubectl pointed at the cluster c3s is actually connected to.
    // connect() derives all names from the parsed kubeconfig instead.

    /// Parse /version JSON response and cache the gitVersion string.
    fn cacheVersionFromResponse(self: *K8sService, response: []const u8) void {
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch return;
        defer parsed.deinit();

        // A non-object body -- an HTML error page from a proxy, or a metav1.Status --
        // used to panic here rather than degrade to "unknown version".
        if (parsed.value != .object) return;
        const git_version = if (parsed.value.object.get("gitVersion")) |v|
            if (v == .string) v.string else null
        else
            null;

        const version_str = git_version orelse return;
        if (self.cached_k8s_version) |old| self.allocator.free(old);
        self.cached_k8s_version = self.allocator.dupe(u8, version_str) catch null;
    }

    /// Check if connected to a cluster
    pub fn isConnected(self: *const K8sService) bool {
        const slot = self.session_slot orelse return false;
        return self.connected and slot.view().state == .active;
    }

    /// Get the current namespace
    pub fn getCurrentNamespace(self: *const K8sService) []const u8 {
        return self.current_namespace;
    }

    /// Set the current namespace
    pub fn setCurrentNamespace(self: *K8sService, namespace: []const u8) !void {
        var lease = (try self.acquireRequest(.command)) orelse
            return error.NotConnected;
        defer lease.release();
        const client = try lease.client();

        const replacement = try self.allocator.dupe(u8, namespace);
        errdefer self.allocator.free(replacement);
        const client_namespace = try client.allocator.dupe(u8, namespace);
        errdefer client.allocator.free(client_namespace);

        self.allocator.free(self.current_namespace);
        self.current_namespace = replacement;

        // Give the client its own copy since K8sClient.deinit() frees client.namespace
        client.allocator.free(client.namespace);
        client.namespace = client_namespace;
    }

    /// Get cluster information
    pub fn getClusterInfo(self: *const K8sService) ClusterInfo {
        return ClusterInfo{
            .context = self.context_name,
            .cluster = self.cluster_name,
            .user = self.user_name,
            .namespace = self.current_namespace,
            .connected = self.isConnected(),
        };
    }

    /// Fetch the Kubernetes server version from the /version endpoint.
    /// The result is cached so subsequent calls do not make additional HTTP requests.
    /// Returns the gitVersion string (e.g. "v1.30.2+k3s1") or "unknown" on failure.
    pub fn getServerVersion(self: *K8sService) []const u8 {
        if (!self.isConnected()) return "n/a";

        var request = self.resolveRequest(.header_metrics) catch return "n/a";
        defer request.deinit();

        // A cached value belongs to the currently published active session only.
        if (self.cached_k8s_version) |v| return v;

        // Don't retry after failure — repeated attempts can trigger std lib panics
        if (self.version_fetch_failed) return "unknown";

        const response = if (request.use_kubectl)
            self.kubectlRequestResolved(&request, "/version") catch |err| {
                Logger.warn("Failed to fetch /version via kubectl: {}", .{err});
                self.version_fetch_failed = true;
                return "unknown";
            }
        else
            (request.client orelse return "n/a").request(.GET, "/version", null) catch |err| {
                Logger.warn("Failed to fetch /version: {}", .{err});
                self.version_fetch_failed = true;
                return "unknown";
            };
        defer self.allocator.free(response);

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
            Logger.warn("Failed to parse /version response: {}", .{err});
            return "unknown";
        };
        defer parsed.deinit();

        if (parsed.value != .object) return "unknown";
        const git_version = if (parsed.value.object.get("gitVersion")) |v|
            if (v == .string) v.string else null
        else
            null;

        const version_str = git_version orelse "unknown";
        self.cached_k8s_version = self.allocator.dupe(u8, version_str) catch {
            return "unknown";
        };

        Logger.info("Fetched server version: {s}", .{self.cached_k8s_version.?});
        return self.cached_k8s_version.?;
    }

    // ===== Generic Resource Helpers =====

    /// Parse a kubectl JSON response into a typed list and return copied items.
    /// Wrapper that owns parsed K8s list data. Items are valid until deinit().
    pub fn ParsedList(comptime T: type) type {
        return struct {
            _parsed: std.json.Parsed(klient.types.List(T)),

            pub fn items(self: @This()) []T {
                return self._parsed.value.items;
            }

            pub fn deinit(self: *@This()) void {
                self._parsed.deinit();
            }
        };
    }

    /// List all instances of a resource across all namespaces.
    /// Caller must call .deinit() on the result when done with .items().
    pub fn listAllGenericPub(self: *K8sService, comptime T: type, comptime ClientType: type) !ParsedList(T) {
        if (!self.isConnected()) return error.NotConnected;
        var request = try self.resolveRequest(.list_watch);
        defer request.deinit();
        const active_client = request.client orelse return error.NotConnected;

        if (request.use_kubectl) {
            const dummy = ClientType.init(active_client);
            const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dummy.client.api_path, dummy.client.resource });
            defer self.allocator.free(path);

            const body = try self.kubectlRequestResolved(&request, path);
            defer self.allocator.free(body);
            return .{ ._parsed = try std.json.parseFromSlice(
                klient.types.List(T),
                self.allocator,
                body,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            ) };
        }

        const client = ClientType.init(active_client);
        return .{ ._parsed = try client.client.listAll() };
    }

    /// List instances of a resource in a specific namespace.
    /// Caller must call .deinit() on the result when done with .items().
    pub fn listInNsGenericPub(self: *K8sService, comptime T: type, comptime ClientType: type, namespace: ?[]const u8) !ParsedList(T) {
        if (!self.isConnected()) return error.NotConnected;
        const ns = namespace orelse self.current_namespace;
        var request = try self.resolveRequest(.list_watch);
        defer request.deinit();
        const active_client = request.client orelse return error.NotConnected;

        if (request.use_kubectl) {
            const dummy = ClientType.init(active_client);
            const path = try std.fmt.allocPrint(self.allocator, "{s}/namespaces/{s}/{s}", .{ dummy.client.api_path, ns, dummy.client.resource });
            defer self.allocator.free(path);

            const body = try self.kubectlRequestResolved(&request, path);
            defer self.allocator.free(body);
            return .{ ._parsed = try std.json.parseFromSlice(
                klient.types.List(T),
                self.allocator,
                body,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            ) };
        }

        const client = ClientType.init(active_client);
        return .{ ._parsed = try client.client.list(ns) };
    }

    /// Legacy list methods for backward compatibility (shallow copy, OK for simple types)
    fn listAllGeneric(self: *K8sService, comptime T: type, comptime ClientType: type) ![]T {
        var parsed = try self.listAllGenericPub(T, ClientType);
        defer parsed.deinit();
        const items = try self.allocator.alloc(T, parsed.items().len);
        @memcpy(items, parsed.items());
        return items;
    }

    fn listInNsGeneric(self: *K8sService, comptime T: type, comptime ClientType: type, namespace: ?[]const u8) ![]T {
        var parsed = try self.listInNsGenericPub(T, ClientType, namespace);
        defer parsed.deinit();
        const items = try self.allocator.alloc(T, parsed.items().len);
        @memcpy(items, parsed.items());
        return items;
    }

    // ===== Pod Operations =====

    /// List all pods across all namespaces
    pub fn listAllPods(self: *K8sService) !PodList {
        if (!self.isConnected()) return error.NotConnected;
        var request = try self.resolveRequest(.list_watch);
        defer request.deinit();
        const active_client = request.client orelse return error.NotConnected;

        if (request.use_kubectl) {
            const body = try self.kubectlRequestResolved(&request, "/api/v1/pods");
            defer self.allocator.free(body);
            return std.json.parseFromSlice(
                klient.types.List(klient.types.Pod),
                self.allocator,
                body,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            );
        }

        const pods_client = klient.resources.Pods.init(active_client);
        return try pods_client.client.listAll();
    }

    /// List pods in a specific namespace
    pub fn listPods(self: *K8sService, namespace: ?[]const u8) !PodList {
        if (!self.isConnected()) return error.NotConnected;
        const ns = namespace orelse self.current_namespace;
        var request = try self.resolveRequest(.list_watch);
        defer request.deinit();
        const active_client = request.client orelse return error.NotConnected;

        if (request.use_kubectl) {
            const path = try std.fmt.allocPrint(self.allocator, "/api/v1/namespaces/{s}/pods", .{ns});
            defer self.allocator.free(path);
            const body = try self.kubectlRequestResolved(&request, path);
            defer self.allocator.free(body);
            return std.json.parseFromSlice(
                klient.types.List(klient.types.Pod),
                self.allocator,
                body,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            );
        }

        const pods_client = klient.resources.Pods.init(active_client);
        return try pods_client.client.list(ns);
    }

    /// Delete a pod
    /// Reject a cluster mutation when running with --readonly.
    ///
    /// Called by every mutating method. Read paths deliberately do not call this.
    fn assertMutable(self: *K8sService) !void {
        if (self.readonly) return error.ReadOnlyMode;
    }

    pub fn deletePod(self: *K8sService, name: []const u8, namespace: ?[]const u8) !void {
        try self.assertMutable();
        if (!self.isConnected()) return error.NotConnected;
        var request = try self.resolveRequest(.command);
        defer request.deinit();
        const active_client = request.client orelse return error.NotConnected;

        const pods_client = klient.Pods.init(active_client);
        const ns = namespace orelse self.current_namespace;
        // klient.Pods wraps a ResourceClient in `.client`; delete takes (name, ns).
        // This body never compiled -- Zig analyses a function only when it is
        // referenced, and nothing referenced it, so the arity error stayed hidden.
        try pods_client.client.delete(name, ns);
    }

    // ===== Deployment Operations =====

    /// List all deployments
    pub fn listAllDeployments(self: *K8sService) ![]klient.types.Deployment {
        return self.listAllGeneric(klient.types.Deployment, klient.resources.Deployments);
    }

    /// List deployments in a namespace
    pub fn listDeployments(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Deployment {
        return self.listInNsGeneric(klient.types.Deployment, klient.resources.Deployments, namespace);
    }

    /// Cordon or uncordon a node (mark it unschedulable, or undo that).
    ///
    /// Goes through kubectl on BOTH transports, deliberately. There is no klient
    /// helper for this -- it is a PATCH of node.spec.unschedulable -- and the
    /// direct-HTTP path is exactly where the former scale* helpers went wrong:
    /// A missing transport branch means silent failure on every TLS-intercepted
    /// cluster. One path that
    /// works everywhere beats two where one is broken, and cordon is infrequent
    /// enough that a ~1.5s subprocess is irrelevant.
    ///
    /// buildKubectlArgv pins --context, so this cannot cordon a node in the cluster
    /// the user is NOT looking at -- the same hazard that made deleteResource
    /// dangerous.
    pub fn setNodeSchedulable(self: *K8sService, node_name: []const u8, schedulable: bool) !void {
        try self.assertMutable();
        if (!self.isConnected()) return error.NotConnected;

        const verb = if (schedulable) "uncordon" else "cordon";
        var request = try self.resolveRequest(.command);
        defer request.deinit();
        const argv = try self.buildKubectlArgvResolved(&request, &.{ verb, node_name });
        defer self.allocator.free(argv);

        const result = std.process.run(self.allocator, runtime.io(), .{
            .argv = argv,
            .stdout_limit = .limited(64 * 1024),
        }) catch return error.KubectlFailed;
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.term != .exited or result.term.exited != 0) {
            Logger.warn("kubectl {s} {s} failed: {s}", .{ verb, node_name, result.stderr });
            return error.KubectlFailed;
        }
    }

    // ===== Service Operations =====

    /// List all services
    pub fn listAllServices(self: *K8sService) ![]klient.types.Service {
        return self.listAllGeneric(klient.types.Service, klient.resources.Services);
    }

    /// List services in a namespace
    pub fn listServices(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Service {
        return self.listInNsGeneric(klient.types.Service, klient.resources.Services, namespace);
    }

    // ===== Namespace Operations =====

    /// List all namespaces
    /// Caller owns the result and MUST call `.deinit()` when done — the items'
    /// `status` (json.Value) and string fields reference the parsed arena. (The
    /// legacy shallow-copy `listAllGeneric` freed that arena and returned
    /// dangling json.Value fields → use-after-free in `.object.get`.)
    pub fn listNamespaces(self: *K8sService) !ParsedList(klient.types.Namespace) {
        return self.listAllGenericPub(klient.types.Namespace, klient.resources.Namespaces);
    }

    // ===== Node Operations =====

    /// List all nodes
    pub fn listNodes(self: *K8sService) ![]klient.types.Node {
        return self.listAllGeneric(klient.types.Node, klient.resources.Nodes);
    }

    // ===== ConfigMap Operations =====

    /// List all configmaps across all namespaces
    pub fn listAllConfigMaps(self: *K8sService) ![]klient.types.ConfigMap {
        return self.listAllGeneric(klient.types.ConfigMap, klient.resources.ConfigMaps);
    }

    /// List configmaps in a namespace
    pub fn listConfigMaps(self: *K8sService, namespace: ?[]const u8) ![]klient.types.ConfigMap {
        return self.listInNsGeneric(klient.types.ConfigMap, klient.resources.ConfigMaps, namespace);
    }

    // ===== Secret Operations =====

    /// List all secrets across all namespaces
    pub fn listAllSecrets(self: *K8sService) ![]klient.types.Secret {
        return self.listAllGeneric(klient.types.Secret, klient.resources.Secrets);
    }

    /// List secrets in a namespace
    pub fn listSecrets(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Secret {
        return self.listInNsGeneric(klient.types.Secret, klient.resources.Secrets, namespace);
    }

    // ===== StatefulSet Operations =====

    /// List all statefulsets
    pub fn listAllStatefulSets(self: *K8sService) ![]klient.types.StatefulSet {
        return self.listAllGeneric(klient.types.StatefulSet, klient.resources.StatefulSets);
    }

    // ===== DaemonSet Operations =====

    /// List all daemonsets
    pub fn listAllDaemonSets(self: *K8sService) ![]klient.types.DaemonSet {
        return self.listAllGeneric(klient.types.DaemonSet, klient.resources.DaemonSets);
    }

    // ===== ReplicaSet Operations =====

    /// List all replicasets
    pub fn listAllReplicaSets(self: *K8sService) ![]klient.types.ReplicaSet {
        return self.listAllGeneric(klient.types.ReplicaSet, klient.resources.ReplicaSets);
    }

    // ===== Job Operations =====

    /// List all jobs
    pub fn listAllJobs(self: *K8sService) ![]klient.types.Job {
        return self.listAllGeneric(klient.types.Job, klient.resources.Jobs);
    }

    // ===== CronJob Operations =====

    /// List all cronjobs
    pub fn listAllCronJobs(self: *K8sService) ![]klient.types.CronJob {
        return self.listAllGeneric(klient.types.CronJob, klient.resources.CronJobs);
    }

    // ===== PersistentVolume Operations =====

    /// List all persistent volumes (cluster-scoped)
    pub fn listAllPersistentVolumes(self: *K8sService) ![]klient.types.PersistentVolume {
        return self.listAllGeneric(klient.types.PersistentVolume, klient.resources.PersistentVolumes);
    }

    // ===== PersistentVolumeClaim Operations =====

    /// List all persistent volume claims
    pub fn listAllPersistentVolumeClaims(self: *K8sService) ![]klient.types.PersistentVolumeClaim {
        return self.listAllGeneric(klient.types.PersistentVolumeClaim, klient.resources.PersistentVolumeClaims);
    }

    // ===== Ingress Operations =====

    /// List all ingresses across all namespaces
    pub fn listAllIngresses(self: *K8sService) ![]klient.types.Ingress {
        return self.listAllGeneric(klient.types.Ingress, klient.resources.Ingresses);
    }

    // ===== NetworkPolicy Operations =====

    /// List all network policies across all namespaces
    pub fn listAllNetworkPolicies(self: *K8sService) ![]klient.types.NetworkPolicy {
        return self.listAllGeneric(klient.types.NetworkPolicy, klient.resources.NetworkPolicies);
    }

    // ===== ServiceAccount Operations =====

    /// List all service accounts across all namespaces
    pub fn listAllServiceAccounts(self: *K8sService) ![]klient.types.ServiceAccount {
        return self.listAllGeneric(klient.types.ServiceAccount, klient.resources.ServiceAccounts);
    }

    // ===== Role Operations =====

    /// List all roles across all namespaces
    pub fn listAllRoles(self: *K8sService) ![]klient.types.Role {
        return self.listAllGeneric(klient.types.Role, klient.resources.Roles);
    }

    // ===== RoleBinding Operations =====

    /// List all role bindings across all namespaces
    pub fn listAllRoleBindings(self: *K8sService) ![]klient.types.RoleBinding {
        return self.listAllGeneric(klient.types.RoleBinding, klient.resources.RoleBindings);
    }

    // ===== ClusterRole Operations =====

    /// List all cluster roles (cluster-scoped)
    pub fn listAllClusterRoles(self: *K8sService) ![]klient.types.ClusterRole {
        return self.listAllGeneric(klient.types.ClusterRole, klient.resources.ClusterRoles);
    }

    // ===== ClusterRoleBinding Operations =====

    /// List all cluster role bindings (cluster-scoped)
    pub fn listAllClusterRoleBindings(self: *K8sService) ![]klient.types.ClusterRoleBinding {
        return self.listAllGeneric(klient.types.ClusterRoleBinding, klient.resources.ClusterRoleBindings);
    }

    // ===== Event Operations =====

    /// List all events across all namespaces
    pub fn listAllEvents(self: *K8sService) ![]klient.types.Event {
        return self.listAllGeneric(klient.types.Event, klient.resources.Events);
    }

    // ===== ResourceQuota Operations =====

    /// List all resource quotas across all namespaces
    pub fn listAllResourceQuotas(self: *K8sService) ![]klient.types.ResourceQuota {
        return self.listAllGeneric(klient.types.ResourceQuota, klient.resources.ResourceQuotas);
    }

    // ===== LimitRange Operations =====

    /// List all limit ranges across all namespaces
    pub fn listAllLimitRanges(self: *K8sService) ![]klient.types.LimitRange {
        return self.listAllGeneric(klient.types.LimitRange, klient.resources.LimitRanges);
    }

    // ===== PodDisruptionBudget Operations =====

    /// List all pod disruption budgets across all namespaces
    pub fn listAllPodDisruptionBudgets(self: *K8sService) ![]klient.types.PodDisruptionBudget {
        return self.listAllGeneric(klient.types.PodDisruptionBudget, klient.resources.PodDisruptionBudgets);
    }

    // ===== HorizontalPodAutoscaler Operations =====

    /// List all horizontal pod autoscalers across all namespaces
    pub fn listAllHPAs(self: *K8sService) ![]klient.types.HorizontalPodAutoscaler {
        return self.listAllGeneric(klient.types.HorizontalPodAutoscaler, klient.resources.HorizontalPodAutoscalers);
    }

    // ===== Endpoints Operations =====

    /// List all endpoints across all namespaces
    pub fn listAllEndpoints(self: *K8sService) ![]klient.types.Endpoints {
        return self.listAllGeneric(klient.types.Endpoints, klient.resources.EndpointsClient);
    }

    // ===== StorageClass Operations =====

    /// List all storage classes (cluster-scoped)
    pub fn listAllStorageClasses(self: *K8sService) ![]klient.types.StorageClass {
        return self.listAllGeneric(klient.types.StorageClass, klient.resources.StorageClasses);
    }

    // ===== Pod Metrics Operations =====

    pub const PodMetric = k8s_types.PodMetric;

    /// Fetch pod metrics from the Kubernetes Metrics Server.
    /// Returns a map of "namespace/name" -> PodMetric.
    /// If the metrics server is not available, returns null (graceful degradation).
    pub fn getPodMetrics(self: *K8sService, all_namespaces: bool) !?std.StringHashMap(PodMetric) {
        if (!self.isConnected()) return null;
        var request = try self.resolveRequest(.metrics);
        defer request.deinit();
        const active_client = request.client orelse return null;

        if (request.use_kubectl) {
            // Use kubectl to fetch metrics API
            const path = if (all_namespaces)
                "/apis/metrics.k8s.io/v1beta1/pods"
            else
                try std.fmt.allocPrint(self.allocator, "/apis/metrics.k8s.io/v1beta1/namespaces/{s}/pods", .{self.current_namespace});
            defer if (!all_namespaces) self.allocator.free(path);

            const body = self.kubectlRequestResolved(&request, path) catch |err| {
                Logger.warn("Metrics server unavailable via kubectl: {any}", .{err});
                return null;
            };
            defer self.allocator.free(body);

            const KubectlMetricsList = struct { items: []klient.PodMetrics };
            var parsed = std.json.parseFromSlice(KubectlMetricsList, self.allocator, body, .{
                .ignore_unknown_fields = true,
                .allocate = .alloc_always,
            }) catch |err| {
                Logger.warn("Failed to parse metrics response: {any}", .{err});
                return null;
            };
            defer parsed.deinit();
            return try self.buildMetricsMap(parsed.value.items);
        }

        const metrics_client = klient.MetricsClient.init(active_client);
        var parsed = if (all_namespaces)
            metrics_client.getAllPodMetrics() catch |err| {
                Logger.warn("Metrics server unavailable (all namespaces): {any}", .{err});
                return null;
            }
        else blk: {
            break :blk metrics_client.getPodMetrics(self.current_namespace) catch |err| {
                Logger.warn("Metrics server unavailable (namespace {s}): {any}", .{ self.current_namespace, err });
                return null;
            };
        };
        defer parsed.deinit();
        return try self.buildMetricsMap(parsed.value.items);
    }

    /// Build a metrics map from a slice of PodMetrics items.
    fn buildMetricsMap(self: *K8sService, items: []klient.PodMetrics) !std.StringHashMap(PodMetric) {
        var result = std.StringHashMap(PodMetric).init(self.allocator);
        errdefer {
            var it = result.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.cpu);
                self.allocator.free(entry.value_ptr.mem);
            }
            result.deinit();
        }

        for (items) |pod_metric| {
            var total_cpu_millicores: u64 = 0;
            var total_mem_bytes: u64 = 0;

            if (pod_metric.containers) |containers| {
                for (containers) |container| {
                    if (container.usage.cpu) |cpu_str| {
                        if (klient.MetricsClient.parseCpuMillicores(cpu_str)) |mc| {
                            total_cpu_millicores += mc;
                        }
                    }
                    if (container.usage.memory) |mem_str| {
                        if (klient.MetricsClient.parseMemoryBytes(mem_str)) |bytes| {
                            total_mem_bytes += bytes;
                        }
                    }
                }
            }

            const cpu_display = if (total_cpu_millicores >= 1000 and total_cpu_millicores % 1000 == 0)
                try std.fmt.allocPrint(self.allocator, "{d}", .{total_cpu_millicores / 1000})
            else
                try std.fmt.allocPrint(self.allocator, "{d}m", .{total_cpu_millicores});
            errdefer self.allocator.free(cpu_display);

            const mem_display = if (total_mem_bytes >= 1024 * 1024 * 1024 and total_mem_bytes % (1024 * 1024 * 1024) == 0)
                try std.fmt.allocPrint(self.allocator, "{d}Gi", .{total_mem_bytes / (1024 * 1024 * 1024)})
            else if (total_mem_bytes >= 1024 * 1024)
                try std.fmt.allocPrint(self.allocator, "{d}Mi", .{total_mem_bytes / (1024 * 1024)})
            else if (total_mem_bytes >= 1024)
                try std.fmt.allocPrint(self.allocator, "{d}Ki", .{total_mem_bytes / 1024})
            else
                try std.fmt.allocPrint(self.allocator, "{d}", .{total_mem_bytes});
            errdefer self.allocator.free(mem_display);

            const ns = pod_metric.metadata.namespace orelse "default";
            const key = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ ns, pod_metric.metadata.name });
            errdefer self.allocator.free(key);

            try result.put(key, PodMetric{
                .cpu = cpu_display,
                .mem = mem_display,
                .cpu_milli = total_cpu_millicores,
                .mem_bytes = total_mem_bytes,
            });
        }

        Logger.info("Fetched metrics for {d} pods", .{result.count()});
        return result;
    }

    /// Free a PodMetric map returned by getPodMetrics
    pub fn freePodMetrics(self: *K8sService, metrics_map: *std.StringHashMap(PodMetric)) void {
        var it = metrics_map.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.cpu);
            self.allocator.free(entry.value_ptr.mem);
        }
        metrics_map.deinit();
    }

    // ===== Context Operations =====

    pub const ContextInfo = k8s_types.ContextInfo;

    /// List all available contexts from kubeconfig
    pub fn listContexts(self: *K8sService) ![]ContextInfo {
        const parser_allocator = self.kubeconfig_parser_allocator orelse self.allocator;
        var parser = klient.KubeconfigParser.init(parser_allocator, runtime.io());
        var kubeconfig = if (self.kubeconfig_path) |path|
            try parser.loadFromPath(path)
        else
            try parser.load();
        defer kubeconfig.deinit(parser_allocator);

        const contexts = try self.allocator.alloc(ContextInfo, kubeconfig.contexts.len);
        errdefer self.allocator.free(contexts);
        var initialized: usize = 0;
        errdefer for (contexts[0..initialized]) |context| {
            self.allocator.free(context.name);
            self.allocator.free(context.cluster);
            self.allocator.free(context.user);
            if (context.namespace) |namespace| self.allocator.free(namespace);
        };
        for (kubeconfig.contexts, 0..) |ctx, i| {
            const is_current = std.mem.eql(u8, ctx.name, self.context_name);
            const name = try self.allocator.dupe(u8, ctx.name);
            errdefer self.allocator.free(name);
            const cluster = try self.allocator.dupe(u8, ctx.cluster);
            errdefer self.allocator.free(cluster);
            const user = try self.allocator.dupe(u8, ctx.user);
            errdefer self.allocator.free(user);
            const namespace = if (ctx.namespace) |ns|
                try self.allocator.dupe(u8, ns)
            else
                null;
            contexts[i] = ContextInfo{
                .name = name,
                .cluster = cluster,
                .user = user,
                .namespace = namespace,
                .is_current = is_current,
            };
            initialized += 1;
        }
        return contexts;
    }

    // ===== Generic Resource Operations =====

    /// Get raw JSON for any resource (for describe/yaml views)
    pub fn getRawJson(self: *K8sService, resource_type: ResourceType, name: []const u8, namespace: []const u8) ![]u8 {
        if (!self.isConnected()) return error.NotConnected;
        var request = try self.resolveRequest(.detail);
        defer request.deinit();
        const active_client = request.client orelse return error.NotConnected;

        const path = if (resource_type.isClusterScoped())
            try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{ resource_type.apiPath(), resource_type.resourceName(), name })
        else
            try std.fmt.allocPrint(self.allocator, "{s}/namespaces/{s}/{s}/{s}", .{ resource_type.apiPath(), namespace, resource_type.resourceName(), name });
        defer self.allocator.free(path);

        if (request.use_kubectl) return try self.kubectlRequestResolved(&request, path);
        return try active_client.request(.GET, path, null);
    }

    /// Delete any resource by type, name, namespace
    pub fn deleteResource(self: *K8sService, resource_type: ResourceType, name: []const u8, namespace: []const u8, force: bool) !void {
        try self.assertMutable();
        if (!self.isConnected()) return error.NotConnected;
        var request = try self.resolveRequest(.command);
        defer request.deinit();
        const active_client = request.client orelse return error.NotConnected;

        const path = if (resource_type.isClusterScoped())
            try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{ resource_type.apiPath(), resource_type.resourceName(), name })
        else
            try std.fmt.allocPrint(self.allocator, "{s}/namespaces/{s}/{s}/{s}", .{ resource_type.apiPath(), namespace, resource_type.resourceName(), name });
        defer self.allocator.free(path);

        if (request.use_kubectl) {
            // Use kubectl delete for kubectl mode. Zig 0.16: std.process.run
            // spawns + waits + collects output in one call (output discarded).
            // force adds --grace-period=0 --force (Ctrl-K kill vs Ctrl-D delete).
            // MUST go through buildKubectlArgv: it pins --context to the cluster
            // c3s is connected to. A hand-built argv inherits kubectl's own
            // current-context, so after an in-app context switch this deleted from
            // the PREVIOUS cluster. Every other kubectl call in this file already
            // routed through it; this one did not.
            const sub = [_][]const u8{ "delete", resource_type.resourceName(), name, "-n", namespace };
            const sub_forced = sub ++ [_][]const u8{ "--grace-period=0", "--force" };
            const argv = try self.buildKubectlArgvResolved(&request, if (force) &sub_forced else &sub);
            defer self.allocator.free(argv);

            const result = std.process.run(self.allocator, runtime.io(), .{
                .argv = argv,
                .stdout_limit = .limited(64 * 1024),
            }) catch return error.KubectlFailed;
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
            if (result.term.exited != 0) return error.KubectlFailed;
            return;
        }

        const body = try active_client.request(.DELETE, path, null);
        self.allocator.free(body);
    }

    /// Get pod logs
    pub fn getPodLogs(self: *K8sService, name: []const u8, namespace: ?[]const u8, previous: bool) ![]u8 {
        return self.getPodLogsForContainer(name, namespace, previous, null);
    }

    /// Fetch pod logs, optionally for a named container.
    ///
    /// `container == null` asks the API server to choose, which it only does for
    /// single-container pods; for anything with a sidecar (Istio, log shippers,
    /// init-heavy workloads) it answers 400 "a container name must be specified".
    /// That is why logs simply failed on those pods.
    ///
    /// Rather than guess, the null case falls back to reading the pod and using its
    /// first container. The extra GET is only paid when the first attempt fails, and
    /// only on pods that would otherwise show nothing at all. A container picker is
    /// Phase 4 work; this makes the default case work in the meantime.
    pub fn getPodLogsForContainer(
        self: *K8sService,
        name: []const u8,
        namespace: ?[]const u8,
        previous: bool,
        container: ?[]const u8,
    ) ![]u8 {
        if (!self.isConnected()) return error.NotConnected;

        const ns = namespace orelse "default";

        if (self.logRequest(name, ns, previous, container)) |body| return body else |err| {
            // Only the ambiguous-container case is worth a retry; a real failure
            // (missing pod, forbidden, transport down) must surface as itself.
            if (container != null) return err;

            const first = self.firstContainerName(name, ns) catch return err;
            defer self.allocator.free(first);
            Logger.info("pod {s} has multiple containers; showing logs for '{s}'", .{ name, first });
            return self.logRequest(name, ns, previous, first);
        }
    }

    /// Build the query string for a pod-log request. Caller owns the result.
    ///
    /// Pulled out of logRequest so it can be tested: a mutation deleting
    /// `timestamps=true` survived the whole suite, and losing that parameter silently
    /// turns the `t` toggle in LogsView into a no-op -- there would be no timestamps
    /// to reveal, and nothing anywhere would fail.
    pub fn logQuery(allocator: std.mem.Allocator, previous: bool, container: ?[]const u8) ![]u8 {
        var query: std.ArrayListUnmanaged(u8) = .empty;
        errdefer query.deinit(allocator);
        try query.appendSlice(allocator, "tailLines=1000");
        // Always ask for timestamps, and let the view strip them for display.
        //
        // The alternative -- refetching when the user toggles `t` -- means a round trip
        // per keypress and a window where the toggle is on but the buffer predates it,
        // so the first screen after toggling shows the wrong thing. Fetching once costs
        // ~31 bytes per line and makes the toggle instant. The view strips by default,
        // so output is unchanged until the user asks for timestamps.
        try query.appendSlice(allocator, "&timestamps=true");
        if (previous) try query.appendSlice(allocator, "&previous=true");
        if (container) |c| {
            try query.appendSlice(allocator, "&container=");
            try query.appendSlice(allocator, c);
        }
        return query.toOwnedSlice(allocator);
    }

    fn logRequest(self: *K8sService, name: []const u8, ns: []const u8, previous: bool, container: ?[]const u8) ![]u8 {
        var request = try self.resolveRequest(.logs);
        defer request.deinit();
        const query = try logQuery(self.allocator, previous, container);
        defer self.allocator.free(query);

        const path = try std.fmt.allocPrint(
            self.allocator,
            "/api/v1/namespaces/{s}/pods/{s}/log?{s}",
            .{ ns, name, query },
        );
        defer self.allocator.free(path);

        if (request.use_kubectl) return try self.kubectlRequestResolved(&request, path);
        if (request.client) |client| return try client.request(.GET, path, null);
        return error.NotConnected;
    }

    /// Name of the pod's first container. Caller owns the result.
    fn firstContainerName(self: *K8sService, name: []const u8, ns: []const u8) ![]u8 {
        const raw = try self.getRawJson(.pods, name, ns);
        defer self.allocator.free(raw);

        var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, raw, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        if (parsed.value != .object) return error.UnexpectedResponse;
        const spec = parsed.value.object.get("spec") orelse return error.UnexpectedResponse;
        if (spec != .object) return error.UnexpectedResponse;
        const containers = spec.object.get("containers") orelse return error.UnexpectedResponse;
        if (containers != .array or containers.array.items.len == 0) return error.UnexpectedResponse;

        const first = containers.array.items[0];
        if (first != .object) return error.UnexpectedResponse;
        const cname = first.object.get("name") orelse return error.UnexpectedResponse;
        if (cname != .string) return error.UnexpectedResponse;

        return self.allocator.dupe(u8, cname.string);
    }

    // ===== Authorization Methods =====

    pub const AccessCheckResult = k8s_types.AccessCheckResult;
    pub const PolicyInfo = k8s_types.PolicyInfo;
    pub const ConditionInfo = k8s_types.ConditionInfo;

    /// Check access for a specific verb on a resource (SelfSubjectAccessReview)
    pub fn checkAccess(self: *K8sService, verb: []const u8, group: []const u8, resource: []const u8, namespace: []const u8) !AccessCheckResult {
        if (!self.isConnected()) return error.NotConnected;
        var request = try self.resolveRequest(.authorization);
        defer request.deinit();

        // Build SelfSubjectAccessReview JSON body
        var body_buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(&body_buf,
            \\{{"apiVersion":"authorization.k8s.io/v1","kind":"SelfSubjectAccessReview","spec":{{"resourceAttributes":{{"namespace":"{s}","verb":"{s}","group":"{s}","resource":"{s}"}}}}}}
        , .{ namespace, verb, group, resource });

        const ssar_path = "/apis/authorization.k8s.io/v1/selfsubjectaccessreviews";

        // The kubectl transport is the standard path on clusters where direct TLS
        // failed (EKS, TLS interception). Without this branch every check errored,
        // and because the caller swallowed the error the grid rendered as
        // "denied everywhere" -- an answer the app had not earned.
        // The HTTP path is used only while the resolved request lease is live.
        const response = if (request.use_kubectl)
            self.proxyPostResolved(&request, ssar_path, body) catch |err| {
                Logger.warn("checkAccess via proxy failed for {s}/{s}: {t}", .{ resource, verb, err });
                return error.RequestFailed;
            }
        else if (request.client) |client|
            client.requestWithContentType(.POST, ssar_path, body, "application/json") catch |err| {
                Logger.warn("checkAccess failed for {s}/{s}: {}", .{ resource, verb, err });
                return error.RequestFailed;
            }
        else
            return error.NotConnected;
        defer self.allocator.free(response);

        // Parse response
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
            Logger.warn("checkAccess: failed to parse response: {}", .{err});
            return error.ParseFailed;
        };
        defer parsed.deinit();

        const denied = AccessCheckResult{ .allowed = false, .conditional = false, .condition_count = 0 };

        const root = parsed.value;
        if (root != .object) return error.UnexpectedResponse;
        const status = root.object.get("status") orelse return denied;

        // On an error the API server answers with a metav1.Status, whose own `status`
        // field is the STRING "Failure" -- so `status.object` panicked on exactly the
        // response most in need of handling. Surface it as an error rather than
        // reporting "denied", which is the distinction Phase 0 established.
        if (status != .object) return error.UnexpectedResponse;

        const allowed = if (status.object.get("allowed")) |v| v == .bool and v.bool else false;

        // Check for conditionSetChain (KEP 5681)
        var conditional = false;
        var condition_count: u32 = 0;
        if (status.object.get("conditionSetChain")) |chain| {
            if (chain == .array) {
                condition_count = @intCast(chain.array.items.len);
                if (condition_count > 0) conditional = true;
            }
        }

        return AccessCheckResult{
            .allowed = allowed,
            .conditional = conditional,
            .condition_count = condition_count,
        };
    }

    /// Detect if ConditionalAuthorization (KEP 5681) is available
    pub fn detectConditionalAuth(self: *K8sService) !bool {
        if (!self.isConnected()) return false;

        // Issue a probe SAR and check if conditionSetChain field exists
        const result = self.checkAccess("get", "", "pods", "default") catch return false;
        // If we got a response at all and conditional flag is set, it's available
        // Otherwise, check if the field was present (even if empty)
        _ = result;

        var request = try self.resolveRequest(.authorization);
        defer request.deinit();
        const active_client = request.client orelse return false;
        // Try a direct API discovery for the alpha feature
        const response = active_client.request(.GET, "/apis/authorization.k8s.io/v1alpha1", null) catch {
            return false;
        };
        defer self.allocator.free(response);

        // If we get a valid response (not 404), the alpha API group exists
        return std.mem.indexOf(u8, response, "authorizationconditionsreviews") != null or
            std.mem.indexOf(u8, response, "conditionSetChain") != null;
    }

    /// Get authorization conditions for a resource (v1alpha1 API)
    pub fn getAuthorizationConditions(self: *K8sService, resource: []const u8, group: []const u8, namespace: []const u8) ![]ConditionInfo {
        if (!self.isConnected()) return error.NotConnected;
        var request = try self.resolveRequest(.authorization);
        defer request.deinit();
        const active_client = request.client orelse return error.NotConnected;

        // Build AuthorizationConditionsReview body
        var body_buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(&body_buf,
            \\{{"apiVersion":"authorization.k8s.io/v1alpha1","kind":"SubjectAccessReview","spec":{{"resourceAttributes":{{"namespace":"{s}","verb":"*","group":"{s}","resource":"{s}"}}}}}}
        , .{ namespace, group, resource });

        const response = active_client.requestWithContentType(.POST, "/apis/authorization.k8s.io/v1alpha1/subjectaccessreviews", body, "application/json") catch |err| {
            Logger.warn("getAuthorizationConditions failed: {}", .{err});
            return error.RequestFailed;
        };
        defer self.allocator.free(response);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch {
            return error.ParseFailed;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return &.{};
        const status = root.object.get("status") orelse return &.{};
        if (status != .object) return &.{}; // metav1.Status: `status` is a string
        const chain = status.object.get("conditionSetChain") orelse return &.{};

        if (chain != .array) return &.{};

        var results = std.ArrayListUnmanaged(ConditionInfo).empty;
        errdefer {
            for (results.items) |*c| c.deinit();
            results.deinit(self.allocator);
        }

        for (chain.array.items) |condition_set| {
            if (condition_set != .object) continue;

            const effect = if (condition_set.object.get("effect")) |v|
                if (v == .string) v.string else "Unknown"
            else
                "Unknown";

            const authorizer = if (condition_set.object.get("authorizer")) |v|
                if (v == .string) v.string else "unknown"
            else
                "unknown";

            // Each conditionSet may have multiple conditions
            const conditions = condition_set.object.get("conditions") orelse continue;
            if (conditions != .array) continue;

            for (conditions.array.items) |cond| {
                if (cond != .object) continue;

                const expr = if (cond.object.get("expression")) |v|
                    if (v == .string) v.string else ""
                else
                    "";

                const desc = if (cond.object.get("message")) |v|
                    if (v == .string) v.string else ""
                else if (cond.object.get("description")) |v|
                    if (v == .string) v.string else ""
                else
                    "";

                try results.append(self.allocator, ConditionInfo{
                    .effect = try self.allocator.dupe(u8, effect),
                    .authorizer = try self.allocator.dupe(u8, authorizer),
                    .expression = try self.allocator.dupe(u8, expr),
                    .description = try self.allocator.dupe(u8, desc),
                    .allocator = self.allocator,
                });
            }
        }

        return results.toOwnedSlice(self.allocator);
    }

    /// Cedar's Kubernetes API group.
    ///
    /// The group NAME is the API's identity, so naming it is unavoidable -- but the
    /// version and plural are asked of the server rather than assumed. The previous
    /// code hardcoded all three and got two of them wrong
    /// (`cedar.k8s.io/v1alpha1/cedarpolicies` instead of
    /// `cedar.k8s.aws/<served>/policies`), and because the failure was swallowed the
    /// Cedar rows silently never appeared. Verified against
    /// cedar-policy/cedar-access-control-for-k8s (+groupName=cedar.k8s.aws).
    const cedar_group = "cedar.k8s.aws";

    /// Detect if Cedar authorization CRDs are available.
    ///
    /// Discovery-driven: present in the cluster means supported, absent means there is
    /// nothing to show. No version or plural is compiled in.
    pub fn detectCedarAuth(self: *K8sService) !bool {
        if (!self.isConnected()) return false;
        var request = try self.resolveRequest(.authorization);
        defer request.deinit();
        const active_client = request.client orelse return false;
        return klient.Discovery.init(active_client).hasGroup(cedar_group);
    }

    /// List Cedar policies from CRDs
    pub fn listCedarPolicies(self: *K8sService) ![]PolicyInfo {
        if (!self.isConnected()) return error.NotConnected;
        var request = try self.resolveRequest(.authorization);
        defer request.deinit();
        const active_client = request.client orelse return error.NotConnected;

        // Ask the server where Cedar policies live instead of assuming.
        const disco = klient.Discovery.init(active_client);
        const info = (disco.findResource(cedar_group, "Policy") catch |err| {
            Logger.warn("Cedar discovery failed: {}", .{err});
            return error.RequestFailed;
        }) orelse return &.{};
        defer disco.freeResource(info);

        // Policy is cluster-scoped, which discovery reports via info.namespaced.
        const path = try info.resourcePath(self.allocator, null, null);
        defer self.allocator.free(path);

        const response = active_client.request(.GET, path, null) catch |err| {
            Logger.warn("listCedarPolicies failed for {s}: {}", .{ path, err });
            return error.RequestFailed;
        };
        defer self.allocator.free(response);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch {
            return error.ParseFailed;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return &.{};
        const items = root.object.get("items") orelse return &.{};
        if (items != .array) return &.{};

        var results = std.ArrayListUnmanaged(PolicyInfo).empty;
        errdefer {
            for (results.items) |*p| p.deinit();
            results.deinit(self.allocator);
        }

        for (items.array.items) |item| {
            if (item != .object) continue;

            const metadata = item.object.get("metadata") orelse continue;
            const name = if (metadata == .object)
                if (metadata.object.get("name")) |v| if (v == .string) v.string else "unknown" else "unknown"
            else
                "unknown";

            // Extract policy spec
            const spec = item.object.get("spec") orelse continue;
            if (spec != .object) continue;

            // The Cedar Policy CRD has `spec.content` (the policy text) and
            // `spec.validation`. It has no resource/actions/principal fields -- the
            // previous code read those and so every row rendered "*", which in an RBAC
            // table reads as "all resources". That is not a cosmetic defect: it
            // overstates the reach of every Cedar policy in a security view.
            //
            // Cedar policy text does not decompose into RBAC's resource/verbs/subjects
            // without a Cedar parser, so show what is actually known and mark the rest
            // not-applicable rather than inventing a wildcard.
            const content = if (spec.object.get("content")) |v|
                if (v == .string) v.string else ""
            else
                "";

            // Effect is the leading keyword of a Cedar policy and is genuinely the
            // action semantics, so it belongs in the verbs column.
            const trimmed = std.mem.trim(u8, content, " \t\r\n");
            const verbs_str = if (std.mem.startsWith(u8, trimmed, "permit"))
                "permit"
            else if (std.mem.startsWith(u8, trimmed, "forbid"))
                "forbid"
            else
                "—";

            // First line of the policy, truncated -- the most informative single field.
            const first_line = blk: {
                const line_end = std.mem.indexOfScalar(u8, trimmed, '\n') orelse trimmed.len;
                const line = trimmed[0..line_end];
                break :blk if (line.len > 60) line[0..60] else line;
            };
            const resource_str = if (first_line.len > 0) first_line else "(empty policy)";

            const subjects_str = "—";

            try results.append(self.allocator, PolicyInfo{
                .source = try self.allocator.dupe(u8, name),
                .resource = try self.allocator.dupe(u8, resource_str),
                .verbs = try self.allocator.dupe(u8, verbs_str),
                .subjects = try self.allocator.dupe(u8, subjects_str),
                .allocator = self.allocator,
            });
        }

        return results.toOwnedSlice(self.allocator);
    }

    /// List RBAC policies (ClusterRoles + Bindings aggregated)
    pub fn listRBACPolicies(self: *K8sService) ![]PolicyInfo {
        if (!self.isConnected()) return error.NotConnected;
        var request = try self.resolveRequest(.authorization);
        defer request.deinit();
        const active_client = request.client orelse return error.NotConnected;

        var results = std.ArrayListUnmanaged(PolicyInfo).empty;
        errdefer {
            for (results.items) |*p| p.deinit();
            results.deinit(self.allocator);
        }

        // Fetch ClusterRoles
        const cr_response = active_client.request(.GET, "/apis/rbac.authorization.k8s.io/v1/clusterroles", null) catch |err| {
            Logger.warn("listRBACPolicies: failed to list clusterroles: {}", .{err});
            return results.toOwnedSlice(self.allocator);
        };
        defer self.allocator.free(cr_response);

        var cr_parsed = std.json.parseFromSlice(std.json.Value, self.allocator, cr_response, .{}) catch {
            return results.toOwnedSlice(self.allocator);
        };
        defer cr_parsed.deinit();

        // Fetch ClusterRoleBindings for subject lookup
        const crb_response = active_client.request(.GET, "/apis/rbac.authorization.k8s.io/v1/clusterrolebindings", null) catch {
            return results.toOwnedSlice(self.allocator);
        };
        defer self.allocator.free(crb_response);

        var crb_parsed = std.json.parseFromSlice(std.json.Value, self.allocator, crb_response, .{}) catch {
            return results.toOwnedSlice(self.allocator);
        };
        defer crb_parsed.deinit();

        // Build binding map: role name -> subjects string
        var binding_map = std.StringHashMap([]const u8).init(self.allocator);
        defer {
            var it = binding_map.iterator();
            while (it.next()) |entry| {
                self.allocator.free(entry.value_ptr.*);
            }
            binding_map.deinit();
        }

        // A metav1.Status body has no "items"; .object on it would panic, so the
        // lookup is guarded into an optional rather than nesting another block.
        const crb_items_opt = if (crb_parsed.value == .object)
            crb_parsed.value.object.get("items")
        else
            null;
        if (crb_items_opt) |crb_items| {
            if (crb_items == .array) {
                for (crb_items.array.items) |binding| {
                    if (binding != .object) continue;
                    const role_ref = binding.object.get("roleRef") orelse continue;
                    if (role_ref != .object) continue;
                    const role_name = if (role_ref.object.get("name")) |v|
                        if (v == .string) v.string else continue
                    else
                        continue;

                    const subjects_arr = binding.object.get("subjects") orelse continue;
                    if (subjects_arr != .array) continue;

                    var subj_list = std.ArrayListUnmanaged(u8).empty;
                    defer subj_list.deinit(self.allocator);

                    for (subjects_arr.array.items, 0..) |subj, si| {
                        if (subj != .object) continue;
                        if (si > 0) try subj_list.appendSlice(self.allocator, ",");
                        const subj_name = if (subj.object.get("name")) |v|
                            if (v == .string) v.string else "?"
                        else
                            "?";
                        try subj_list.appendSlice(self.allocator, subj_name);
                    }

                    const subj_str = try self.allocator.dupe(u8, subj_list.items);
                    try binding_map.put(role_name, subj_str);
                }
            }
        }

        // Process ClusterRoles
        const cr_items_opt = if (cr_parsed.value == .object)
            cr_parsed.value.object.get("items")
        else
            null;
        if (cr_items_opt) |cr_items| {
            if (cr_items == .array) {
                for (cr_items.array.items) |role| {
                    if (role != .object) continue;
                    const metadata = role.object.get("metadata") orelse continue;
                    if (metadata != .object) continue;
                    const name = if (metadata.object.get("name")) |v|
                        if (v == .string) v.string else continue
                    else
                        continue;

                    const rules = role.object.get("rules") orelse continue;
                    if (rules != .array) continue;

                    for (rules.array.items) |rule| {
                        if (rule != .object) continue;

                        // Extract resources
                        var res_buf: [128]u8 = undefined;
                        var res_len: usize = 0;
                        if (rule.object.get("resources")) |resources| {
                            if (resources == .array) {
                                for (resources.array.items, 0..) |r, ri| {
                                    if (r != .string) continue;
                                    if (ri > 0 and res_len < res_buf.len - 1) {
                                        res_buf[res_len] = ',';
                                        res_len += 1;
                                    }
                                    const to_copy = @min(r.string.len, res_buf.len - res_len);
                                    @memcpy(res_buf[res_len..][0..to_copy], r.string[0..to_copy]);
                                    res_len += to_copy;
                                }
                            }
                        }

                        // Extract verbs
                        var verb_buf: [128]u8 = undefined;
                        var verb_len: usize = 0;
                        if (rule.object.get("verbs")) |verbs| {
                            if (verbs == .array) {
                                for (verbs.array.items, 0..) |v, vi| {
                                    if (v != .string) continue;
                                    if (vi > 0 and verb_len < verb_buf.len - 1) {
                                        verb_buf[verb_len] = ',';
                                        verb_len += 1;
                                    }
                                    const to_copy = @min(v.string.len, verb_buf.len - verb_len);
                                    @memcpy(verb_buf[verb_len..][0..to_copy], v.string[0..to_copy]);
                                    verb_len += to_copy;
                                }
                            }
                        }

                        const subjects_str = binding_map.get(name) orelse "-";

                        try results.append(self.allocator, PolicyInfo{
                            .source = try self.allocator.dupe(u8, name),
                            .resource = try self.allocator.dupe(u8, res_buf[0..res_len]),
                            .verbs = try self.allocator.dupe(u8, verb_buf[0..verb_len]),
                            .subjects = try self.allocator.dupe(u8, subjects_str),
                            .allocator = self.allocator,
                        });
                    }
                }
            }
        }

        return results.toOwnedSlice(self.allocator);
    }

    /// Switch to a different context
    pub fn switchContext(self: *K8sService, context_name: []const u8) !void {
        Logger.info("Switching to context: {s}", .{context_name});

        try self.connect(context_name);
        if (self.cached_k8s_version) |version| self.allocator.free(version);
        self.cached_k8s_version = null;
        self.version_fetch_failed = false;
    }
};

const testing = std.testing;

test "hintsContainFresh matches only fresh entries for the exact server" {
    const ttl = K8sService.transport_hint_ttl;
    const content =
        "1000 https://eks.example.com\n" ++
        "5000 https://other.example.com\n";

    // Fresh entry (now - ts < ttl).
    try testing.expect(K8sService.hintsContainFresh(content, "https://eks.example.com", 1000 + ttl - 1, ttl));
    // Expired entry.
    try testing.expect(!K8sService.hintsContainFresh(content, "https://eks.example.com", 1000 + ttl, ttl));
    // Unknown server / prefix must not match.
    try testing.expect(!K8sService.hintsContainFresh(content, "https://eks.example.co", 1001, ttl));
    try testing.expect(!K8sService.hintsContainFresh(content, "https://missing.example.com", 1001, ttl));
    // Malformed lines are skipped.
    try testing.expect(!K8sService.hintsContainFresh("garbage\nx y\n", "y", 0, ttl));
}

test "buildKubectlArgv pins --context so mutations cannot hit the wrong cluster" {
    // deleteResource used to hand-build {"kubectl","delete",...} with no --context,
    // so after an in-app context switch it deleted from whatever cluster the SHELL's
    // kubeconfig pointed at. It now routes through this builder; this pins the
    // builder's contract.
    const allocator = std.testing.allocator;
    var svc = try K8sService.init(allocator);
    defer svc.deinit();

    svc.allocator.free(svc.context_name);
    svc.context_name = try allocator.dupe(u8, "prod-cluster");

    const argv = try svc.buildKubectlArgv(&.{ "delete", "pods", "doomed", "-n", "default" });
    defer allocator.free(argv);

    try std.testing.expectEqualStrings("kubectl", argv[0]);

    var saw_context = false;
    for (argv, 0..) |a, i| {
        if (std.mem.eql(u8, a, "--context")) {
            saw_context = true;
            try std.testing.expectEqualStrings("prod-cluster", argv[i + 1]);
        }
    }
    try std.testing.expect(saw_context);

    // and the subcommand survives intact after the injected flags
    try std.testing.expectEqualStrings("delete", argv[argv.len - 5]);
    try std.testing.expectEqualStrings("doomed", argv[argv.len - 3]);
}

test "buildKubectlArgv omits --context when the context is unknown" {
    // Guards the other direction: an "unknown" context must not be passed to kubectl
    // as a literal, which would fail every call.
    const allocator = std.testing.allocator;
    var svc = try K8sService.init(allocator);
    defer svc.deinit();

    const argv = try svc.buildKubectlArgv(&.{"version"});
    defer allocator.free(argv);

    for (argv) |a| try std.testing.expect(!std.mem.eql(u8, a, "--context"));
}

test "cacheVersionFromResponse tolerates a non-object body" {
    // An HTML error page from an intercepting proxy, or a bare JSON scalar, reached
    // parsed.value.object unguarded and panicked instead of degrading to "unknown".
    // In-file because cacheVersionFromResponse is private: testability is not a
    // reason to widen the API.
    var svc = try K8sService.init(std.testing.allocator);
    defer svc.deinit();

    svc.cacheVersionFromResponse("[]");
    svc.cacheVersionFromResponse("\"just a string\"");
    svc.cacheVersionFromResponse("null");
    svc.cacheVersionFromResponse("<html>503 Service Unavailable</html>");
    try std.testing.expect(svc.cached_k8s_version == null);

    // A well-formed body still works.
    svc.cacheVersionFromResponse("{\"gitVersion\":\"v1.36.4\"}");
    try std.testing.expectEqualStrings("v1.36.4", svc.cached_k8s_version.?);
}

test "readonly is a promise about the cluster, not about which API verbs we call" {
    // Documents the invariant that the App-level gates exist to uphold.
    //
    // The service guard added in Phase 0 only sees calls that go THROUGH the service.
    // c3s also spawns kubectl directly for edit / shell / attach (App.runInteractive),
    // which bypasses it entirely -- so `--readonly` still permitted `kubectl edit`
    // until those call sites were gated too. A guard at one layer is not a guard.
    //
    // This test pins the flag's meaning; the App-side refusals are asserted where
    // they live. Kept here because this is where the flag is owned.
    const allocator = std.testing.allocator;
    var svc = try K8sService.init(allocator);
    defer svc.deinit();

    try std.testing.expect(!svc.readonly);
    svc.readonly = true;

    // Everything that mutates through the service is refused...
    svc.connected = true;
    try std.testing.expectError(error.ReadOnlyMode, svc.deleteResource(.pods, "p", "default", false));

    // ...while reads are not, so the flag cannot be satisfied by simply failing.
    svc.connected = false;
    try std.testing.expectError(error.NotConnected, svc.getPodLogs("p", "default", false));
}
