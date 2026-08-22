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

/// Zig 0.16: klient.connectWithFallback gained an `io` parameter. Wrap it once
/// to inject the global io, so the many call sites below stay unchanged.
fn connectWithFallback(
    allocator: std.mem.Allocator,
    server: []const u8,
    token: ?[]const u8,
    namespace: ?[]const u8,
) !klient.K8sClient {
    return klient.connectWithFallback(allocator, runtime.io(), server, token, namespace);
}

// Re-export shared types so existing `@import("services/K8sService.zig").ClusterInfo` etc. keep working.
pub const ClusterInfo = k8s_types.ClusterInfo;
pub const ResourceType = k8s_types.ResourceType;
pub const ResourceInfo = k8s_types.ResourceInfo;

/// Kubernetes service for managing cluster connections and resource operations
pub const K8sService = struct {
    allocator: std.mem.Allocator,
    client: ?*klient.K8sClient,
    connected: bool,
    current_namespace: []const u8,
    context_name: []const u8,
    cluster_name: []const u8,
    user_name: []const u8,

    // Cached server version (fetched once from /version endpoint)
    cached_k8s_version: ?[]const u8 = null,
    // Set to true after first version fetch failure to avoid repeated attempts that may panic
    version_fetch_failed: bool = false,
    // Set to true after connect() has been called at least once
    connect_attempted: bool = false,
    // When true, use `kubectl get --raw` for API calls instead of klient's HTTP client
    use_kubectl: bool = false,

    // TLS certificate data (decoded from base64) - needs cleanup
    tls_ca_data: ?[]const u8 = null,
    tls_cert_data: ?[]const u8 = null,
    tls_key_data: ?[]const u8 = null,

    // Cached bearer token from the exec credential plugin, passed to kubectl via
    // --token so kubectl doesn't re-run the (~0.6s) auth plugin on every call.
    // The exec config is duped so the token can be refreshed on expiry/failure.
    auth_token: ?[]const u8 = null,
    exec_command: ?[]const u8 = null,
    exec_args: ?[][]const u8 = null,
    exec_api_version: ?[]const u8 = null,

    // Persistent `kubectl proxy` (one long-lived authenticated connection to the
    // API server). When up, raw requests hit it over localhost HTTP (~0.1s)
    // instead of spawning a fresh ~2s kubectl per call. Killed on deinit.
    proxy_child: ?std.process.Child = null,
    proxy_port: ?u16 = null,

    /// Wrapper around parsed pod lists so callers can keep JSON alive while consuming
    const PodList = std.json.Parsed(klient.types.List(klient.types.Pod));

    /// Initialize the K8s service
    pub fn init(allocator: std.mem.Allocator) !K8sService {
        return K8sService{
            .allocator = allocator,
            .client = null,
            .connected = false,
            .current_namespace = try allocator.dupe(u8, "default"),
            .context_name = try allocator.dupe(u8, "unknown"),
            .cluster_name = try allocator.dupe(u8, "unknown"),
            .user_name = try allocator.dupe(u8, "unknown"),
        };
    }

    /// Zero sensitive bytes before returning them to the allocator so bearer
    /// tokens and private key material don't linger in freed heap pages
    /// (readable via core dumps, swap, or later allocations).
    fn secureFree(self: *K8sService, data: []const u8) void {
        std.crypto.secureZero(u8, @constCast(data));
        self.allocator.free(data);
    }

    /// Clean up resources
    pub fn deinit(self: *K8sService) void {
        if (self.client) |client| {
            client.deinit();
            self.allocator.destroy(client);
            self.client = null;
        }
        self.connected = false;
        self.allocator.free(self.current_namespace);
        self.allocator.free(self.context_name);
        self.allocator.free(self.cluster_name);
        self.allocator.free(self.user_name);

        // Free cached server version if allocated
        if (self.cached_k8s_version) |v| self.allocator.free(v);

        // Free TLS certificate data. The CA cert is public; the client cert and
        // especially the private key are credentials — zero them before free.
        if (self.tls_ca_data) |ca| self.allocator.free(ca);
        if (self.tls_cert_data) |cert| self.secureFree(cert);
        if (self.tls_key_data) |key| self.secureFree(key);

        // Stop the persistent kubectl proxy.
        if (self.proxy_child) |*child| child.kill(runtime.io());

        // Free cached exec-auth token + config
        if (self.auth_token) |t| self.secureFree(t);
        if (self.exec_command) |c| self.allocator.free(c);
        if (self.exec_api_version) |v| self.allocator.free(v);
        if (self.exec_args) |args| {
            for (args) |a| self.allocator.free(a);
            self.allocator.free(args);
        }
    }

    /// Cache the exec-auth token and a private copy of the exec config (the
    /// kubeconfig is freed after connect()). Lets kubectl skip its own auth via
    /// --token, and lets us refresh the token on expiry without re-parsing.
    fn cacheExecAuth(self: *K8sService, exec_cfg: anytype, token: []const u8) void {
        // Token (replace any prior).
        if (self.auth_token) |old| self.secureFree(old);
        self.auth_token = self.allocator.dupe(u8, token) catch null;

        // Exec config is stable across refreshes — store once.
        if (self.exec_command == null) {
            if (exec_cfg.command) |cmd| self.exec_command = self.allocator.dupe(u8, cmd) catch null;
            self.exec_api_version = self.allocator.dupe(u8, exec_cfg.api_version orelse "client.authentication.k8s.io/v1beta1") catch null;
            if (exec_cfg.args) |args| {
                const owned = self.allocator.alloc([]const u8, args.len) catch return;
                var n: usize = 0;
                for (args) |a| {
                    owned[n] = self.allocator.dupe(u8, a) catch break;
                    n += 1;
                }
                self.exec_args = owned[0..n];
            }
        }
    }

    /// Re-run the exec credential plugin to obtain a fresh bearer token.
    /// Best-effort: on any failure the existing token is left in place.
    fn refreshAuthToken(self: *K8sService) void {
        const cmd = self.exec_command orelse return;
        const cfg = klient.exec_credential.ExecConfig{
            .command = cmd,
            .args = self.exec_args,
            .apiVersion = self.exec_api_version orelse "client.authentication.k8s.io/v1beta1",
        };
        const cred = klient.exec_credential.executeCredentialPlugin(self.allocator, runtime.io(), cfg) catch return;
        // The Parsed arena owns all credential strings — without this deinit the
        // token-bearing buffer leaked on every refresh.
        defer cred.deinit();
        if (cred.value.status) |s| {
            if (s.token) |tok| {
                const dup = self.allocator.dupe(u8, tok) catch return;
                // Scrub the arena's copy; the arena free below won't zero it.
                std.crypto.secureZero(u8, @constCast(tok));
                if (self.auth_token) |old| self.secureFree(old);
                self.auth_token = dup;
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
        Logger.info("Connecting to Kubernetes cluster...", .{});

        // Parse kubeconfig using klient's YAML parser
        var parser = klient.KubeconfigParser.init(self.allocator, runtime.io());

        var kubeconfig = parser.load() catch |err| {
            Logger.warn("Failed to load kubeconfig: {}", .{err});
            return err;
        };
        defer kubeconfig.deinit(self.allocator);

        // Determine which context to use
        const context_name = context_override orelse kubeconfig.current_context;
        if (context_name.len == 0) {
            Logger.warn("No context specified and no current-context in kubeconfig", .{});
            return error.NoContext;
        }

        // Find the context
        const context = kubeconfig.getContextByName(context_name) orelse {
            Logger.warn("Context '{s}' not found in kubeconfig", .{context_name});
            return error.ContextNotFound;
        };

        // Find the cluster
        const cluster = kubeconfig.getClusterByName(context.cluster) orelse {
            Logger.warn("Cluster '{s}' not found in kubeconfig", .{context.cluster});
            return error.ClusterNotFound;
        };

        // Find the user
        const user = kubeconfig.getUserByName(context.user) orelse {
            Logger.warn("User '{s}' not found in kubeconfig", .{context.user});
            return error.UserNotFound;
        };

        // Update context, cluster, and user names
        self.allocator.free(self.context_name);
        self.allocator.free(self.cluster_name);
        self.allocator.free(self.user_name);
        self.context_name = try self.allocator.dupe(u8, context.name);
        self.cluster_name = try self.allocator.dupe(u8, cluster.name);
        self.user_name = try self.allocator.dupe(u8, user.name);

        // Update namespace if specified in context
        if (context.namespace) |ns| {
            if (ns.len > 0) {
                self.allocator.free(self.current_namespace);
                self.current_namespace = try self.allocator.dupe(u8, ns);
            }
        }

        // Create K8s client
        const client = try self.allocator.create(klient.K8sClient);
        errdefer self.allocator.destroy(client);

        // Build TLS config from kubeconfig (handles both file paths and base64 data)
        var tls_config: ?klient.tls.TlsConfig = null;

        // Free old TLS data if reconnecting (zero credentials, see secureFree)
        if (self.tls_ca_data) |ca| self.allocator.free(ca);
        if (self.tls_cert_data) |cert| self.secureFree(cert);
        if (self.tls_key_data) |key| self.secureFree(key);
        self.tls_ca_data = null;
        self.tls_cert_data = null;
        self.tls_key_data = null;

        // Optional override to force using kubectl proxy (helpful for corp TLS issues)
        var force_proxy: bool = false;
        if (env.getOwned(self.allocator, "C3S_FORCE_PROXY")) |val| {
            defer self.allocator.free(val);
            force_proxy = std.ascii.eqlIgnoreCase(val, "1") or std.ascii.eqlIgnoreCase(val, "true");
        } else |_| {}

        // Skip TLS config for localhost - Rancher Desktop uses system-trusted certs
        const is_localhost = std.mem.indexOf(u8, cluster.server, "127.0.0.1") != null or
            std.mem.indexOf(u8, cluster.server, "localhost") != null;

        Logger.debug("cluster.server={s}, is_localhost={}", .{ cluster.server, is_localhost });

        if (!is_localhost and !force_proxy) {
            // Handle CA certificate (for server verification)
            if (cluster.certificate_authority_data) |base64_ca| {
                Logger.debug("Found certificate-authority-data ({d} bytes base64)", .{base64_ca.len});
                // Decode base64 CA certificate and store for cleanup
                self.tls_ca_data = try klient.tls.decodeBase64Cert(self.allocator, base64_ca);
                Logger.debug("Decoded CA cert: {d} bytes PEM", .{self.tls_ca_data.?.len});
            } else if (cluster.certificate_authority) |ca_path| {
                // Load CA from file and store for cleanup
                self.tls_ca_data = try std.Io.Dir.cwd().readFileAlloc(runtime.io(), ca_path, self.allocator, .limited(10 * 1024 * 1024));
            }
        }

        // Initialize client with appropriate authentication
        Logger.debug("user.token exists: {}", .{user.token != null});
        if (user.token) |token| {
            Logger.debug("Using token auth branch", .{});
            // Use connectWithFallback for localhost to handle TLS issues
            if (is_localhost or force_proxy) {
                Logger.info("Using connectWithFallback for localhost", .{});
                client.* = try connectWithFallback(
                    self.allocator,
                    cluster.server,
                    token,
                    self.current_namespace,
                );
                Logger.info("Connected via fallback, api_server: {s}", .{client.api_server});
            } else {
                // Production clusters: use direct connection with TLS config
                if (self.tls_ca_data) |ca| {
                    tls_config = klient.tls.TlsConfig{
                        .ca_cert_data = ca,
                    };
                }

                // Attempt direct TLS connection first; if it fails (e.g., TLS init), fall back via kubectl proxy
                const direct_or_fb = klient.K8sClient.init(self.allocator, runtime.io(), .{
                    .server = cluster.server,
                    .token = token,
                    .namespace = self.current_namespace,
                    .retry_config = klient.defaultConfig,
                    .tls_config = tls_config,
                }) catch |err| blk: {
                    Logger.warn("Direct TLS connect failed: {any}. Falling back via kubectl proxy", .{err});
                    const fb = try connectWithFallback(
                        self.allocator,
                        cluster.server,
                        token,
                        self.current_namespace,
                    );
                    Logger.info("Connected via fallback, api_server: {s}", .{fb.api_server});
                    break :blk fb;
                };
                client.* = direct_or_fb;
                // Verify connection works (TLS handshake is lazy, init may succeed but requests fail)
                try self.verifyOrFallback(client, cluster.server, token);
            }
        } else if (user.client_certificate_data != null or user.client_certificate != null) {
            Logger.debug("Using mTLS auth branch", .{});

            // For localhost, use connectWithFallback (falls back to kubectl proxy)
            if (is_localhost or force_proxy) {
                Logger.info("Using connectWithFallback for localhost (mTLS would fail)", .{});
                client.* = try connectWithFallback(
                    self.allocator,
                    cluster.server,
                    null, // no token for mTLS
                    self.current_namespace,
                );
                Logger.info("Connected via fallback, api_server: {s}", .{client.api_server});
            } else {
                // Production: Load client certificates for mTLS
                if (user.client_certificate_data) |base64_cert| {
                    self.tls_cert_data = try klient.tls.decodeBase64Cert(self.allocator, base64_cert);
                } else if (user.client_certificate) |cert_path| {
                    self.tls_cert_data = try std.Io.Dir.cwd().readFileAlloc(runtime.io(), cert_path, self.allocator, .limited(10 * 1024 * 1024));
                }

                if (user.client_key_data) |base64_key| {
                    self.tls_key_data = try klient.tls.decodeBase64Cert(self.allocator, base64_key);
                } else if (user.client_key) |key_path| {
                    self.tls_key_data = try std.Io.Dir.cwd().readFileAlloc(runtime.io(), key_path, self.allocator, .limited(10 * 1024 * 1024));
                }

                tls_config = klient.tls.TlsConfig{
                    .client_cert_data = self.tls_cert_data,
                    .client_key_data = self.tls_key_data,
                    .ca_cert_data = self.tls_ca_data,
                };

                // Attempt direct TLS mTLS connection; fall back via kubectl proxy on failure
                const direct_or_fb = klient.K8sClient.init(self.allocator, runtime.io(), .{
                    .server = cluster.server,
                    .token = null,
                    .namespace = self.current_namespace,
                    .retry_config = klient.defaultConfig,
                    .tls_config = tls_config,
                }) catch |err| blk: {
                    Logger.warn("mTLS connect failed: {any}. Falling back via kubectl proxy", .{err});
                    const fb = try connectWithFallback(
                        self.allocator,
                        cluster.server,
                        null,
                        self.current_namespace,
                    );
                    Logger.info("Connected via fallback, api_server: {s}", .{fb.api_server});
                    break :blk fb;
                };
                client.* = direct_or_fb;
                // Verify connection works (TLS handshake is lazy, init may succeed but requests fail)
                try self.verifyOrFallback(client, cluster.server, null);
            }
        } else if (user.exec) |exec_cfg| {
            // Exec credential plugin authentication
            Logger.info("Using exec credential plugin: {s}", .{exec_cfg.command orelse "(null)"});

            const exec_config = klient.exec_credential.ExecConfig{
                .command = exec_cfg.command orelse return error.ExecCommandMissing,
                .args = exec_cfg.args,
                .apiVersion = exec_cfg.api_version orelse "client.authentication.k8s.io/v1beta1",
            };

            const cred = klient.exec_credential.executeCredentialPlugin(self.allocator, runtime.io(), exec_config) catch |err| {
                Logger.warn("Exec credential plugin failed: {any}. Falling back via kubectl proxy", .{err});
                client.* = try connectWithFallback(
                    self.allocator,
                    cluster.server,
                    null,
                    self.current_namespace,
                );
                Logger.info("Connected via fallback, api_server: {s}", .{client.api_server});
                self.client = client;
                self.connected = true;
                return;
            };
            // Everything below dupes what it keeps (K8sClient dupes the token,
            // cacheExecAuth dupes token + config), so the Parsed arena can be
            // released — and the arena's token copy scrubbed — when connect()
            // returns. Without this the credential JSON leaked for the
            // process lifetime.
            defer {
                if (cred.value.status) |s| {
                    if (s.token) |tok| std.crypto.secureZero(u8, @constCast(tok));
                }
                cred.deinit();
            }

            const exec_token = if (cred.value.status) |s| s.token else null;
            if (exec_token) |token| {
                Logger.info("Got token from exec credential plugin", .{});
                // Cache for kubectl --token (skips kubectl's own ~0.6s re-auth).
                self.cacheExecAuth(exec_cfg, token);

                if (self.tls_ca_data) |ca| {
                    Logger.debug("Setting TLS config with CA cert ({d} bytes)", .{ca.len});
                    tls_config = klient.tls.TlsConfig{
                        .ca_cert_data = ca,
                    };
                } else {
                    Logger.debug("No CA cert data available - TLS config is null", .{});
                }

                Logger.debug("Creating K8sClient with tls_config={}", .{tls_config != null});
                const direct_or_fb = klient.K8sClient.init(self.allocator, runtime.io(), .{
                    .server = cluster.server,
                    .token = token,
                    .namespace = self.current_namespace,
                    .retry_config = klient.defaultConfig,
                    .tls_config = tls_config,
                }) catch |err| blk: {
                    Logger.warn("Direct TLS with exec token failed: {any}. Falling back via kubectl proxy", .{err});
                    const fb = try connectWithFallback(
                        self.allocator,
                        cluster.server,
                        token,
                        self.current_namespace,
                    );
                    Logger.info("Connected via fallback, api_server: {s}", .{fb.api_server});
                    break :blk fb;
                };
                client.* = direct_or_fb;
                // Verify connection works (TLS handshake is lazy, init may succeed but requests fail)
                try self.verifyOrFallback(client, cluster.server, token);
            } else {
                Logger.warn("Exec credential plugin returned no token, falling back via kubectl proxy", .{});
                client.* = try connectWithFallback(
                    self.allocator,
                    cluster.server,
                    null,
                    self.current_namespace,
                );
            }
        } else {
            // No auth credentials - just use CA cert if available
            Logger.warn("No token or client certificate found, creating client without auth", .{});

            if (!force_proxy) {
                if (self.tls_ca_data) |ca| {
                    tls_config = klient.tls.TlsConfig{
                        .ca_cert_data = ca,
                    };
                }
            }

            if (force_proxy or is_localhost) {
                client.* = try connectWithFallback(
                    self.allocator,
                    cluster.server,
                    null,
                    self.current_namespace,
                );
                Logger.info("Connected via fallback, api_server: {s}", .{client.api_server});
            } else {
                // Attempt unauthenticated TLS connection; fall back via kubectl proxy on failure
                const direct_or_fb = klient.K8sClient.init(self.allocator, runtime.io(), .{
                    .server = cluster.server,
                    .token = null,
                    .namespace = self.current_namespace,
                    .retry_config = klient.defaultConfig,
                    .tls_config = tls_config,
                }) catch |err| blk: {
                    Logger.warn("TLS connect (no auth) failed: {any}. Falling back via kubectl proxy", .{err});
                    const fb = try connectWithFallback(
                        self.allocator,
                        cluster.server,
                        null,
                        self.current_namespace,
                    );
                    Logger.info("Connected via fallback, api_server: {s}", .{fb.api_server});
                    break :blk fb;
                };
                client.* = direct_or_fb;
                // Verify connection works (TLS handshake is lazy, init may succeed but requests fail)
                try self.verifyOrFallback(client, cluster.server, null);
            }
        }

        self.client = client;
        self.connected = true;

        Logger.info("Successfully connected to cluster '{s}' in context '{s}'", .{
            self.cluster_name,
            self.context_name,
        });
    }

    /// Verify that a client can actually reach the cluster by making a lightweight
    /// request (forces TLS handshake). If verification fails, fall back to using
    /// `kubectl get --raw` for API calls (handles TLS via Go's net/http).
    ///
    /// The probe outcome is remembered per server in the state dir: clusters
    /// whose direct TLS always fails (e.g. EKS behind TLS interception) would
    /// otherwise pay the same doomed ~3s probe on every launch before the
    /// identical fallback engaged. Entries expire so direct is re-probed daily.
    fn verifyOrFallback(self: *K8sService, client: *klient.K8sClient, server: []const u8, _: ?[]const u8) !void {
        if (self.directTlsKnownBad(server)) {
            Logger.info("Direct TLS to {s} failed within 24h; kubectl transport (probe skipped)", .{server});
            self.use_kubectl = true;
            return;
        }

        const response = client.request(.GET, "/version", null) catch |err| {
            Logger.warn("Direct connection failed: {any}. Will use kubectl transport.", .{err});
            // Switch to kubectl mode immediately — no verification needed.
            // The first actual API call will validate kubectl works.
            self.use_kubectl = true;
            self.setTransportHint(server, true);
            return;
        };

        self.setTransportHint(server, false);
        self.cacheVersionFromResponse(response);
        self.allocator.free(response);
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
        // Fast path: proxy (curl subprocess) with caller's allocator for the result.
        if (self.proxy_port != null) {
            if (self.proxyRequestAlloc(a, path)) |body| {
                return body;
            } else |_| {
                // Proxy died — fall through.
            }
        }
        return self.kubectlRequestOnceAlloc(a, path) catch |err| {
            if (self.exec_command != null) {
                self.refreshAuthToken();
                return self.kubectlRequestOnceAlloc(a, path);
            }
            return err;
        };
    }

    fn proxyRequestAlloc(self: *K8sService, a: std.mem.Allocator, path: []const u8) ![]u8 {
        const url = try std.fmt.allocPrint(self.allocator, "http://127.0.0.1:18217{s}", .{path});
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

    fn kubectlRequestOnceAlloc(self: *K8sService, a: std.mem.Allocator, path: []const u8) ![]u8 {
        const argv = try self.buildKubectlArgv(&.{ "get", "--raw", path });
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
        // Fast path: the persistent kubectl proxy over localhost.
        if (self.proxy_port != null) {
            if (self.proxyRequest(path)) |body| {
                return body;
            } else |_| {
                // Proxy died/unreachable — fall through to per-call kubectl.
            }
        }
        return self.kubectlRequestOnce(path) catch |err| {
            // A failure may be an expired token. If we have an exec plugin,
            // refresh once and retry — transparently handles token expiry.
            if (self.exec_command != null) {
                self.refreshAuthToken();
                return self.kubectlRequestOnce(path);
            }
            return err;
        };
    }

    fn kubectlRequestOnce(self: *K8sService, path: []const u8) ![]u8 {
        const argv = try self.buildKubectlArgv(&.{ "get", "--raw", path });
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
    /// Uses the cached exec token (--token) when available.
    pub fn listApiResources(self: *K8sService) ![]u8 {
        const argv = try self.buildKubectlArgv(&.{"api-resources"});
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

    /// Build `kubectl [--context <ctx>] [--token <tok>] <args...>` into an
    /// owned argv. Caller frees.
    ///
    /// --context pins kubectl to the cluster c3s is connected to: after an
    /// in-app context switch, kubectl's own current-context (the shell
    /// kubeconfig) may point at a DIFFERENT cluster — presenting the new
    /// context's token to the old server yields Forbidden for everything.
    /// --token is the cached exec token so kubectl skips its ~0.6s auth plugin.
    fn buildKubectlArgv(self: *K8sService, args: []const []const u8) ![]const []const u8 {
        var argv = std.ArrayListUnmanaged([]const u8).empty;
        errdefer argv.deinit(self.allocator);
        try argv.append(self.allocator, "kubectl");
        if (!std.mem.eql(u8, self.context_name, "unknown")) {
            try argv.append(self.allocator, "--context");
            try argv.append(self.allocator, self.context_name);
        }
        if (self.auth_token) |tok| {
            try argv.append(self.allocator, "--token");
            try argv.append(self.allocator, tok);
        }
        for (args) |a| try argv.append(self.allocator, a);
        return argv.toOwnedSlice(self.allocator);
    }

    /// Start a long-lived `kubectl proxy` on a fixed localhost port. It holds ONE
    /// authenticated connection to the API server; c3s then makes fast localhost
    /// HTTP calls instead of spawning a ~2s kubectl per request. Best-effort:
    /// on any failure `proxy_port` stays null and we fall back to per-call kubectl.
    pub fn startProxy(self: *K8sService) void {
        if (self.proxy_child != null) return;
        // --context/--token via buildKubectlArgv: the proxy must serve the
        // cluster c3s is connected to, not the shell's current-context.
        const argv = self.buildKubectlArgv(&.{ "proxy", "--port=18217", "--address=127.0.0.1" }) catch return;
        defer self.allocator.free(argv);
        var child = std.process.spawn(runtime.io(), .{
            .argv = argv,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch {
            Logger.warn("kubectl proxy spawn failed; using per-call kubectl", .{});
            return;
        };
        // Wait for it to bind (curl retries on connection-refused, returns once up).
        const ready = std.process.run(self.allocator, runtime.io(), .{
            .argv = &.{ "curl", "-sf", "-o", "/dev/null", "--retry", "10", "--retry-connrefused", "--retry-delay", "0", "--max-time", "5", "http://127.0.0.1:18217/livez" },
            .stdout_limit = .limited(256),
        }) catch {
            child.kill(runtime.io());
            Logger.warn("kubectl proxy readiness check failed; per-call kubectl", .{});
            return;
        };
        self.allocator.free(ready.stdout);
        self.allocator.free(ready.stderr);
        if (ready.term.exited != 0) {
            child.kill(runtime.io());
            Logger.warn("kubectl proxy not ready (port busy?); per-call kubectl", .{});
            return;
        }
        self.proxy_child = child;
        self.proxy_port = 18217;
        Logger.info("kubectl proxy ready on 127.0.0.1:18217 (fast localhost requests)", .{});
    }

    /// GET a raw API path through the local kubectl proxy (no per-call TLS/auth).
    fn proxyRequest(self: *K8sService, path: []const u8) ![]u8 {
        const url = try std.fmt.allocPrint(self.allocator, "http://127.0.0.1:18217{s}", .{path});
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
    pub fn runKubectl(self: *K8sService, args: []const []const u8) !void {
        const argv = try self.buildKubectlArgv(args);
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
    pub fn spawnKubectl(self: *K8sService, args: []const []const u8) !std.process.Child {
        const argv = try self.buildKubectlArgv(args);
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
        return self.connected and (self.client != null or self.use_kubectl);
    }

    /// Get the current namespace
    pub fn getCurrentNamespace(self: *const K8sService) []const u8 {
        return self.current_namespace;
    }

    /// Set the current namespace
    pub fn setCurrentNamespace(self: *K8sService, namespace: []const u8) !void {
        self.allocator.free(self.current_namespace);
        self.current_namespace = try self.allocator.dupe(u8, namespace);

        // Update client's default namespace if connected
        // Give the client its own copy since K8sClient.deinit() frees client.namespace
        if (self.client) |client| {
            self.allocator.free(client.namespace);
            client.namespace = try self.allocator.dupe(u8, namespace);
        }
    }

    /// Get cluster information
    pub fn getClusterInfo(self: *const K8sService) ClusterInfo {
        return ClusterInfo{
            .context = self.context_name,
            .cluster = self.cluster_name,
            .user = self.user_name,
            .namespace = self.current_namespace,
            .connected = self.connected,
        };
    }

    /// Fetch the Kubernetes server version from the /version endpoint.
    /// The result is cached so subsequent calls do not make additional HTTP requests.
    /// Returns the gitVersion string (e.g. "v1.30.2+k3s1") or "unknown" on failure.
    pub fn getServerVersion(self: *K8sService) []const u8 {
        // Return cached value if available
        if (self.cached_k8s_version) |v| return v;

        if (!self.isConnected()) return "n/a";

        // Don't retry after failure — repeated attempts can trigger std lib panics
        if (self.version_fetch_failed) return "unknown";

        const response = if (self.use_kubectl)
            self.kubectlRequest("/version") catch |err| {
                Logger.warn("Failed to fetch /version via kubectl: {}", .{err});
                self.version_fetch_failed = true;
                return "unknown";
            }
        else
            self.client.?.request(.GET, "/version", null) catch |err| {
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

        if (self.use_kubectl) {
            const dummy = ClientType.init(self.client orelse return error.NotConnected);
            const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dummy.client.api_path, dummy.client.resource });
            defer self.allocator.free(path);

            const body = try self.kubectlRequest(path);
            defer self.allocator.free(body);
            return .{ ._parsed = try std.json.parseFromSlice(
                klient.types.List(T),
                self.allocator,
                body,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            ) };
        }

        const client = ClientType.init(self.client.?);
        return .{ ._parsed = try client.client.listAll() };
    }

    /// List instances of a resource in a specific namespace.
    /// Caller must call .deinit() on the result when done with .items().
    pub fn listInNsGenericPub(self: *K8sService, comptime T: type, comptime ClientType: type, namespace: ?[]const u8) !ParsedList(T) {
        if (!self.isConnected()) return error.NotConnected;
        const ns = namespace orelse self.current_namespace;

        if (self.use_kubectl) {
            const dummy = ClientType.init(self.client orelse return error.NotConnected);
            const path = try std.fmt.allocPrint(self.allocator, "{s}/namespaces/{s}/{s}", .{ dummy.client.api_path, ns, dummy.client.resource });
            defer self.allocator.free(path);

            const body = try self.kubectlRequest(path);
            defer self.allocator.free(body);
            return .{ ._parsed = try std.json.parseFromSlice(
                klient.types.List(T),
                self.allocator,
                body,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            ) };
        }

        const client = ClientType.init(self.client.?);
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

        if (self.use_kubectl) {
            const body = try self.kubectlRequest("/api/v1/pods");
            defer self.allocator.free(body);
            return std.json.parseFromSlice(
                klient.types.List(klient.types.Pod),
                self.allocator,
                body,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            );
        }

        const pods_client = klient.resources.Pods.init(self.client.?);
        return try pods_client.client.listAll();
    }

    /// List pods in a specific namespace
    pub fn listPods(self: *K8sService, namespace: ?[]const u8) !PodList {
        if (!self.isConnected()) return error.NotConnected;
        const ns = namespace orelse self.current_namespace;

        if (self.use_kubectl) {
            const path = try std.fmt.allocPrint(self.allocator, "/api/v1/namespaces/{s}/pods", .{ns});
            defer self.allocator.free(path);
            const body = try self.kubectlRequest(path);
            defer self.allocator.free(body);
            return std.json.parseFromSlice(
                klient.types.List(klient.types.Pod),
                self.allocator,
                body,
                .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
            );
        }

        const pods_client = klient.resources.Pods.init(self.client.?);
        return try pods_client.client.list(ns);
    }

    /// Get a specific pod
    pub fn getPod(self: *K8sService, name: []const u8, namespace: ?[]const u8) !klient.Pod {
        if (!self.isConnected()) return error.NotConnected;

        const pods_client = klient.Pods.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        return try pods_client.get(name, ns);
    }

    /// Delete a pod
    pub fn deletePod(self: *K8sService, name: []const u8, namespace: ?[]const u8) !void {
        if (!self.isConnected()) return error.NotConnected;

        const pods_client = klient.Pods.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        try pods_client.delete(name, ns, null);
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

    /// Scale a deployment
    pub fn scaleDeployment(self: *K8sService, name: []const u8, replicas: i32, namespace: ?[]const u8) !void {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.Deployments.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        try client.scale(name, replicas, ns);
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

    /// List statefulsets in a namespace
    pub fn listStatefulSets(self: *K8sService, namespace: ?[]const u8) ![]klient.types.StatefulSet {
        return self.listInNsGeneric(klient.types.StatefulSet, klient.resources.StatefulSets, namespace);
    }

    /// Scale a statefulset
    pub fn scaleStatefulSet(self: *K8sService, name: []const u8, replicas: i32, namespace: ?[]const u8) !void {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.StatefulSets.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        try client.scale(name, replicas, ns);
    }

    // ===== DaemonSet Operations =====

    /// List all daemonsets
    pub fn listAllDaemonSets(self: *K8sService) ![]klient.types.DaemonSet {
        return self.listAllGeneric(klient.types.DaemonSet, klient.resources.DaemonSets);
    }

    /// List daemonsets in a namespace
    pub fn listDaemonSets(self: *K8sService, namespace: ?[]const u8) ![]klient.types.DaemonSet {
        return self.listInNsGeneric(klient.types.DaemonSet, klient.resources.DaemonSets, namespace);
    }

    // ===== ReplicaSet Operations =====

    /// List all replicasets
    pub fn listAllReplicaSets(self: *K8sService) ![]klient.types.ReplicaSet {
        return self.listAllGeneric(klient.types.ReplicaSet, klient.resources.ReplicaSets);
    }

    /// List replicasets in a namespace
    pub fn listReplicaSets(self: *K8sService, namespace: ?[]const u8) ![]klient.types.ReplicaSet {
        return self.listInNsGeneric(klient.types.ReplicaSet, klient.resources.ReplicaSets, namespace);
    }

    /// Scale a replicaset
    pub fn scaleReplicaSet(self: *K8sService, name: []const u8, replicas: i32, namespace: ?[]const u8) !void {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ReplicaSets.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        try client.scale(name, replicas, ns);
    }

    // ===== Job Operations =====

    /// List all jobs
    pub fn listAllJobs(self: *K8sService) ![]klient.types.Job {
        return self.listAllGeneric(klient.types.Job, klient.resources.Jobs);
    }

    /// List jobs in a namespace
    pub fn listJobs(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Job {
        return self.listInNsGeneric(klient.types.Job, klient.resources.Jobs, namespace);
    }

    // ===== CronJob Operations =====

    /// List all cronjobs
    pub fn listAllCronJobs(self: *K8sService) ![]klient.types.CronJob {
        return self.listAllGeneric(klient.types.CronJob, klient.resources.CronJobs);
    }

    /// List cronjobs in a namespace
    pub fn listCronJobs(self: *K8sService, namespace: ?[]const u8) ![]klient.types.CronJob {
        return self.listInNsGeneric(klient.types.CronJob, klient.resources.CronJobs, namespace);
    }

    /// Suspend/resume a cronjob
    pub fn setCronJobSuspend(self: *K8sService, name: []const u8, should_suspend: bool, namespace: ?[]const u8) !void {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.CronJobs.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        try client.setSuspend(name, should_suspend, ns);
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

    /// List persistent volume claims in a namespace
    pub fn listPersistentVolumeClaims(self: *K8sService, namespace: ?[]const u8) ![]klient.types.PersistentVolumeClaim {
        return self.listInNsGeneric(klient.types.PersistentVolumeClaim, klient.resources.PersistentVolumeClaims, namespace);
    }

    // ===== Ingress Operations =====

    /// List all ingresses across all namespaces
    pub fn listAllIngresses(self: *K8sService) ![]klient.types.Ingress {
        return self.listAllGeneric(klient.types.Ingress, klient.resources.Ingresses);
    }

    /// List ingresses in a namespace
    pub fn listIngresses(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Ingress {
        return self.listInNsGeneric(klient.types.Ingress, klient.resources.Ingresses, namespace);
    }

    // ===== NetworkPolicy Operations =====

    /// List all network policies across all namespaces
    pub fn listAllNetworkPolicies(self: *K8sService) ![]klient.types.NetworkPolicy {
        return self.listAllGeneric(klient.types.NetworkPolicy, klient.resources.NetworkPolicies);
    }

    /// List network policies in a namespace
    pub fn listNetworkPolicies(self: *K8sService, namespace: ?[]const u8) ![]klient.types.NetworkPolicy {
        return self.listInNsGeneric(klient.types.NetworkPolicy, klient.resources.NetworkPolicies, namespace);
    }

    // ===== ServiceAccount Operations =====

    /// List all service accounts across all namespaces
    pub fn listAllServiceAccounts(self: *K8sService) ![]klient.types.ServiceAccount {
        return self.listAllGeneric(klient.types.ServiceAccount, klient.resources.ServiceAccounts);
    }

    /// List service accounts in a namespace
    pub fn listServiceAccounts(self: *K8sService, namespace: ?[]const u8) ![]klient.types.ServiceAccount {
        return self.listInNsGeneric(klient.types.ServiceAccount, klient.resources.ServiceAccounts, namespace);
    }

    // ===== Role Operations =====

    /// List all roles across all namespaces
    pub fn listAllRoles(self: *K8sService) ![]klient.types.Role {
        return self.listAllGeneric(klient.types.Role, klient.resources.Roles);
    }

    /// List roles in a namespace
    pub fn listRoles(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Role {
        return self.listInNsGeneric(klient.types.Role, klient.resources.Roles, namespace);
    }

    // ===== RoleBinding Operations =====

    /// List all role bindings across all namespaces
    pub fn listAllRoleBindings(self: *K8sService) ![]klient.types.RoleBinding {
        return self.listAllGeneric(klient.types.RoleBinding, klient.resources.RoleBindings);
    }

    /// List role bindings in a namespace
    pub fn listRoleBindings(self: *K8sService, namespace: ?[]const u8) ![]klient.types.RoleBinding {
        return self.listInNsGeneric(klient.types.RoleBinding, klient.resources.RoleBindings, namespace);
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

    /// List events in a namespace
    pub fn listEvents(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Event {
        return self.listInNsGeneric(klient.types.Event, klient.resources.Events, namespace);
    }

    // ===== ResourceQuota Operations =====

    /// List all resource quotas across all namespaces
    pub fn listAllResourceQuotas(self: *K8sService) ![]klient.types.ResourceQuota {
        return self.listAllGeneric(klient.types.ResourceQuota, klient.resources.ResourceQuotas);
    }

    /// List resource quotas in a namespace
    pub fn listResourceQuotas(self: *K8sService, namespace: ?[]const u8) ![]klient.types.ResourceQuota {
        return self.listInNsGeneric(klient.types.ResourceQuota, klient.resources.ResourceQuotas, namespace);
    }

    // ===== LimitRange Operations =====

    /// List all limit ranges across all namespaces
    pub fn listAllLimitRanges(self: *K8sService) ![]klient.types.LimitRange {
        return self.listAllGeneric(klient.types.LimitRange, klient.resources.LimitRanges);
    }

    /// List limit ranges in a namespace
    pub fn listLimitRanges(self: *K8sService, namespace: ?[]const u8) ![]klient.types.LimitRange {
        return self.listInNsGeneric(klient.types.LimitRange, klient.resources.LimitRanges, namespace);
    }

    // ===== PodDisruptionBudget Operations =====

    /// List all pod disruption budgets across all namespaces
    pub fn listAllPodDisruptionBudgets(self: *K8sService) ![]klient.types.PodDisruptionBudget {
        return self.listAllGeneric(klient.types.PodDisruptionBudget, klient.resources.PodDisruptionBudgets);
    }

    /// List pod disruption budgets in a namespace
    pub fn listPodDisruptionBudgets(self: *K8sService, namespace: ?[]const u8) ![]klient.types.PodDisruptionBudget {
        return self.listInNsGeneric(klient.types.PodDisruptionBudget, klient.resources.PodDisruptionBudgets, namespace);
    }
    // ===== HorizontalPodAutoscaler Operations =====

    /// List all horizontal pod autoscalers across all namespaces
    pub fn listAllHPAs(self: *K8sService) ![]klient.types.HorizontalPodAutoscaler {
        return self.listAllGeneric(klient.types.HorizontalPodAutoscaler, klient.resources.HorizontalPodAutoscalers);
    }

    /// List horizontal pod autoscalers in a namespace
    pub fn listHPAs(self: *K8sService, namespace: ?[]const u8) ![]klient.types.HorizontalPodAutoscaler {
        return self.listInNsGeneric(klient.types.HorizontalPodAutoscaler, klient.resources.HorizontalPodAutoscalers, namespace);
    }

    // ===== Endpoints Operations =====

    /// List all endpoints across all namespaces
    pub fn listAllEndpoints(self: *K8sService) ![]klient.types.Endpoints {
        return self.listAllGeneric(klient.types.Endpoints, klient.resources.EndpointsClient);
    }

    /// List endpoints in a namespace
    pub fn listEndpoints(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Endpoints {
        return self.listInNsGeneric(klient.types.Endpoints, klient.resources.EndpointsClient, namespace);
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

        if (self.use_kubectl) {
            // Use kubectl to fetch metrics API
            const path = if (all_namespaces)
                "/apis/metrics.k8s.io/v1beta1/pods"
            else
                try std.fmt.allocPrint(self.allocator, "/apis/metrics.k8s.io/v1beta1/namespaces/{s}/pods", .{self.current_namespace});
            defer if (!all_namespaces) self.allocator.free(path);

            const body = self.kubectlRequest(path) catch |err| {
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

        const metrics_client = klient.MetricsClient.init(self.client.?);
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

            try result.put(key, PodMetric{ .cpu = cpu_display, .mem = mem_display });
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
        var parser = klient.KubeconfigParser.init(self.allocator, runtime.io());
        var kubeconfig = try parser.load();
        defer kubeconfig.deinit(self.allocator);

        const contexts = try self.allocator.alloc(ContextInfo, kubeconfig.contexts.len);
        for (kubeconfig.contexts, 0..) |ctx, i| {
            const is_current = std.mem.eql(u8, ctx.name, self.context_name);
            contexts[i] = ContextInfo{
                .name = try self.allocator.dupe(u8, ctx.name),
                .cluster = try self.allocator.dupe(u8, ctx.cluster),
                .user = try self.allocator.dupe(u8, ctx.user),
                .namespace = if (ctx.namespace) |ns| try self.allocator.dupe(u8, ns) else null,
                .is_current = is_current,
            };
        }
        return contexts;
    }

    // ===== Generic Resource Operations =====

    /// Get raw JSON for any resource (for describe/yaml views)
    pub fn getRawJson(self: *K8sService, resource_type: ResourceType, name: []const u8, namespace: []const u8) ![]u8 {
        if (!self.isConnected()) return error.NotConnected;

        const path = if (resource_type.isClusterScoped())
            try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{ resource_type.apiPath(), resource_type.resourceName(), name })
        else
            try std.fmt.allocPrint(self.allocator, "{s}/namespaces/{s}/{s}/{s}", .{ resource_type.apiPath(), namespace, resource_type.resourceName(), name });
        defer self.allocator.free(path);

        if (self.use_kubectl) return try self.kubectlRequest(path);
        return try self.client.?.request(.GET, path, null);
    }

    /// Delete any resource by type, name, namespace
    pub fn deleteResource(self: *K8sService, resource_type: ResourceType, name: []const u8, namespace: []const u8, force: bool) !void {
        if (!self.isConnected()) return error.NotConnected;

        const path = if (resource_type.isClusterScoped())
            try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{ resource_type.apiPath(), resource_type.resourceName(), name })
        else
            try std.fmt.allocPrint(self.allocator, "{s}/namespaces/{s}/{s}/{s}", .{ resource_type.apiPath(), namespace, resource_type.resourceName(), name });
        defer self.allocator.free(path);

        if (self.use_kubectl) {
            // Use kubectl delete for kubectl mode. Zig 0.16: std.process.run
            // spawns + waits + collects output in one call (output discarded).
            // force adds --grace-period=0 --force (Ctrl-K kill vs Ctrl-D delete).
            const base = [_][]const u8{ "kubectl", "delete", resource_type.resourceName(), name, "-n", namespace };
            const forced = base ++ [_][]const u8{ "--grace-period=0", "--force" };
            const result = std.process.run(self.allocator, runtime.io(), .{
                .argv = if (force) &forced else &base,
                .stdout_limit = .limited(64 * 1024),
            }) catch return error.KubectlFailed;
            self.allocator.free(result.stdout);
            self.allocator.free(result.stderr);
            if (result.term.exited != 0) return error.KubectlFailed;
            return;
        }

        const body = try self.client.?.request(.DELETE, path, null);
        self.allocator.free(body);
    }

    /// Get pod logs
    pub fn getPodLogs(self: *K8sService, name: []const u8, namespace: ?[]const u8, previous: bool) ![]u8 {
        if (!self.isConnected()) return error.NotConnected;

        const ns = namespace orelse "default";
        const path = if (previous)
            try std.fmt.allocPrint(self.allocator, "/api/v1/namespaces/{s}/pods/{s}/log?tailLines=1000&previous=true", .{ ns, name })
        else
            try std.fmt.allocPrint(self.allocator, "/api/v1/namespaces/{s}/pods/{s}/log?tailLines=1000", .{ ns, name });
        defer self.allocator.free(path);

        if (self.use_kubectl) return try self.kubectlRequest(path);
        return try self.client.?.request(.GET, path, null);
    }

    // ===== Authorization Methods =====

    pub const AccessCheckResult = k8s_types.AccessCheckResult;
    pub const PolicyInfo = k8s_types.PolicyInfo;
    pub const ConditionInfo = k8s_types.ConditionInfo;

    /// Check access for a specific verb on a resource (SelfSubjectAccessReview)
    pub fn checkAccess(self: *K8sService, verb: []const u8, group: []const u8, resource: []const u8, namespace: []const u8) !AccessCheckResult {
        if (!self.isConnected()) return error.NotConnected;

        // Build SelfSubjectAccessReview JSON body
        var body_buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(&body_buf,
            \\{{"apiVersion":"authorization.k8s.io/v1","kind":"SelfSubjectAccessReview","spec":{{"resourceAttributes":{{"namespace":"{s}","verb":"{s}","group":"{s}","resource":"{s}"}}}}}}
        , .{ namespace, verb, group, resource });

        const response = self.client.?.requestWithContentType(.POST, "/apis/authorization.k8s.io/v1/selfsubjectaccessreviews", body, "application/json") catch |err| {
            Logger.warn("checkAccess failed for {s}/{s}: {}", .{ resource, verb, err });
            return error.RequestFailed;
        };
        defer self.allocator.free(response);

        // Parse response
        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch |err| {
            Logger.warn("checkAccess: failed to parse response: {}", .{err});
            return error.ParseFailed;
        };
        defer parsed.deinit();

        const root = parsed.value;
        const status = root.object.get("status") orelse return AccessCheckResult{ .allowed = false, .conditional = false, .condition_count = 0 };

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

        // Try a direct API discovery for the alpha feature
        const response = self.client.?.request(.GET, "/apis/authorization.k8s.io/v1alpha1", null) catch {
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

        // Build AuthorizationConditionsReview body
        var body_buf: [512]u8 = undefined;
        const body = try std.fmt.bufPrint(&body_buf,
            \\{{"apiVersion":"authorization.k8s.io/v1alpha1","kind":"SubjectAccessReview","spec":{{"resourceAttributes":{{"namespace":"{s}","verb":"*","group":"{s}","resource":"{s}"}}}}}}
        , .{ namespace, group, resource });

        const response = self.client.?.requestWithContentType(.POST, "/apis/authorization.k8s.io/v1alpha1/subjectaccessreviews", body, "application/json") catch |err| {
            Logger.warn("getAuthorizationConditions failed: {}", .{err});
            return error.RequestFailed;
        };
        defer self.allocator.free(response);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch {
            return error.ParseFailed;
        };
        defer parsed.deinit();

        const root = parsed.value;
        const status = root.object.get("status") orelse return &.{};
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
        return klient.Discovery.init(self.client.?).hasGroup(cedar_group);
    }

    /// List Cedar policies from CRDs
    pub fn listCedarPolicies(self: *K8sService) ![]PolicyInfo {
        if (!self.isConnected()) return error.NotConnected;

        // Ask the server where Cedar policies live instead of assuming.
        const disco = klient.Discovery.init(self.client.?);
        const info = (disco.findResource(cedar_group, "Policy") catch |err| {
            Logger.warn("Cedar discovery failed: {}", .{err});
            return error.RequestFailed;
        }) orelse return &.{};
        defer disco.freeResource(info);

        // Policy is cluster-scoped, which discovery reports via info.namespaced.
        const path = try info.resourcePath(self.allocator, null, null);
        defer self.allocator.free(path);

        const response = self.client.?.request(.GET, path, null) catch |err| {
            Logger.warn("listCedarPolicies failed for {s}: {}", .{ path, err });
            return error.RequestFailed;
        };
        defer self.allocator.free(response);

        var parsed = std.json.parseFromSlice(std.json.Value, self.allocator, response, .{}) catch {
            return error.ParseFailed;
        };
        defer parsed.deinit();

        const root = parsed.value;
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

        var results = std.ArrayListUnmanaged(PolicyInfo).empty;
        errdefer {
            for (results.items) |*p| p.deinit();
            results.deinit(self.allocator);
        }

        // Fetch ClusterRoles
        const cr_response = self.client.?.request(.GET, "/apis/rbac.authorization.k8s.io/v1/clusterroles", null) catch |err| {
            Logger.warn("listRBACPolicies: failed to list clusterroles: {}", .{err});
            return results.toOwnedSlice(self.allocator);
        };
        defer self.allocator.free(cr_response);

        var cr_parsed = std.json.parseFromSlice(std.json.Value, self.allocator, cr_response, .{}) catch {
            return results.toOwnedSlice(self.allocator);
        };
        defer cr_parsed.deinit();

        // Fetch ClusterRoleBindings for subject lookup
        const crb_response = self.client.?.request(.GET, "/apis/rbac.authorization.k8s.io/v1/clusterrolebindings", null) catch {
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

        if (crb_parsed.value.object.get("items")) |crb_items| {
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
        if (cr_parsed.value.object.get("items")) |cr_items| {
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

        // Disconnect from current cluster
        if (self.client) |client| {
            client.deinit();
            self.allocator.destroy(client);
            self.client = null;
        }
        self.connected = false;

        // The persistent proxy is bound to the OLD context's cluster — kill it.
        // The next render's startProxy() respawns it against the new context.
        if (self.proxy_child) |*child| {
            child.kill(runtime.io());
            self.proxy_child = null;
            self.proxy_port = null;
        }
        // Let connect() re-decide the transport for the new cluster instead of
        // inheriting the previous cluster's kubectl fallback.
        self.use_kubectl = false;

        // Drop the cached exec-auth config: cacheExecAuth stores it once, so a
        // stale copy would make token refresh re-run the OLD context's auth
        // plugin and fetch a token for the wrong cluster.
        if (self.auth_token) |t| self.secureFree(t);
        if (self.exec_command) |c| self.allocator.free(c);
        if (self.exec_api_version) |v| self.allocator.free(v);
        if (self.exec_args) |args| {
            for (args) |a| self.allocator.free(a);
            self.allocator.free(args);
        }
        self.auth_token = null;
        self.exec_command = null;
        self.exec_api_version = null;
        self.exec_args = null;

        // Clear cached version so it gets re-fetched for the new cluster
        if (self.cached_k8s_version) |v| {
            self.allocator.free(v);
            self.cached_k8s_version = null;
        }

        // Reconnect with new context
        try self.connect(context_name);
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
