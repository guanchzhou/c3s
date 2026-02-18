/// Kubernetes Service Layer
///
/// Wraps zig-klient to provide a clean interface for c3s views.
/// Handles client initialization, authentication, and resource operations.
const std = @import("std");
const klient = @import("klient");
const Logger = @import("../core/logger.zig");

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

    // TLS certificate data (decoded from base64) - needs cleanup
    tls_ca_data: ?[]const u8 = null,
    tls_cert_data: ?[]const u8 = null,
    tls_key_data: ?[]const u8 = null,

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

        // Free TLS certificate data if allocated
        if (self.tls_ca_data) |ca| self.allocator.free(ca);
        if (self.tls_cert_data) |cert| self.allocator.free(cert);
        if (self.tls_key_data) |key| self.allocator.free(key);
    }

    /// Connect to Kubernetes cluster using kubeconfig
    pub fn connect(self: *K8sService, context_override: ?[]const u8) !void {
        Logger.info("Connecting to Kubernetes cluster...", .{});

        // Parse kubeconfig using klient's YAML parser
        var parser = klient.KubeconfigParser.init(self.allocator);

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

        // Free old TLS data if reconnecting
        if (self.tls_ca_data) |ca| self.allocator.free(ca);
        if (self.tls_cert_data) |cert| self.allocator.free(cert);
        if (self.tls_key_data) |key| self.allocator.free(key);
        self.tls_ca_data = null;
        self.tls_cert_data = null;
        self.tls_key_data = null;

        // Optional override to force using kubectl proxy (helpful for corp TLS issues)
        var force_proxy: bool = false;
        if (std.process.getEnvVarOwned(self.allocator, "C3S_FORCE_PROXY")) |val| {
            defer self.allocator.free(val);
            force_proxy = std.ascii.eqlIgnoreCase(val, "1") or std.ascii.eqlIgnoreCase(val, "true");
        } else |_| {}

        // Skip TLS config for localhost - Rancher Desktop uses system-trusted certs
        const is_localhost = std.mem.indexOf(u8, cluster.server, "127.0.0.1") != null or
            std.mem.indexOf(u8, cluster.server, "localhost") != null;

        Logger.info("DEBUG: cluster.server={s}, is_localhost={}", .{ cluster.server, is_localhost });

        if (!is_localhost and !force_proxy) {
            // Handle CA certificate (for server verification)
            if (cluster.certificate_authority_data) |base64_ca| {
                // Decode base64 CA certificate and store for cleanup
                self.tls_ca_data = try klient.tls.decodeBase64Cert(self.allocator, base64_ca);
            } else if (cluster.certificate_authority) |ca_path| {
                // Load CA from file and store for cleanup
                const ca_file = try std.fs.cwd().openFile(ca_path, .{});
                defer ca_file.close();
                self.tls_ca_data = try ca_file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
            }
        }

        // Initialize client with appropriate authentication
        Logger.info("DEBUG: user.token exists: {}", .{user.token != null});
        if (user.token) |token| {
            Logger.info("DEBUG: Entered token auth branch", .{});
            // Use connectWithFallback for localhost to handle TLS issues
            if (is_localhost or force_proxy) {
                Logger.info("Using connectWithFallback for localhost", .{});
                client.* = try klient.connectWithFallback(
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
                const direct_or_fb = klient.K8sClient.init(self.allocator, .{
                    .server = cluster.server,
                    .token = token,
                    .namespace = self.current_namespace,
                    .retry_config = klient.defaultConfig,
                    .tls_config = tls_config,
                }) catch |err| blk: {
                    Logger.warn("Direct TLS connect failed: {any}. Falling back via kubectl proxy", .{err});
                    const fb = try klient.connectWithFallback(
                        self.allocator,
                        cluster.server,
                        token,
                        self.current_namespace,
                    );
                    Logger.info("Connected via fallback, api_server: {s}", .{fb.api_server});
                    break :blk fb;
                };
                client.* = direct_or_fb;
            }
        } else if (user.client_certificate_data != null or user.client_certificate != null) {
            Logger.info("DEBUG: Entered mTLS auth branch", .{});

            // For localhost, use connectWithFallback (falls back to kubectl proxy)
            if (is_localhost or force_proxy) {
                Logger.info("Using connectWithFallback for localhost (mTLS would fail)", .{});
                client.* = try klient.connectWithFallback(
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
                    const cert_file = try std.fs.cwd().openFile(cert_path, .{});
                    defer cert_file.close();
                    self.tls_cert_data = try cert_file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
                }

                if (user.client_key_data) |base64_key| {
                    self.tls_key_data = try klient.tls.decodeBase64Cert(self.allocator, base64_key);
                } else if (user.client_key) |key_path| {
                    const key_file = try std.fs.cwd().openFile(key_path, .{});
                    defer key_file.close();
                    self.tls_key_data = try key_file.readToEndAlloc(self.allocator, 10 * 1024 * 1024);
                }

                tls_config = klient.tls.TlsConfig{
                    .client_cert_data = self.tls_cert_data,
                    .client_key_data = self.tls_key_data,
                    .ca_cert_data = self.tls_ca_data,
                };

                // Attempt direct TLS mTLS connection; fall back via kubectl proxy on failure
                const direct_or_fb = klient.K8sClient.init(self.allocator, .{
                    .server = cluster.server,
                    .token = null,
                    .namespace = self.current_namespace,
                    .retry_config = klient.defaultConfig,
                    .tls_config = tls_config,
                }) catch |err| blk: {
                    Logger.warn("mTLS connect failed: {any}. Falling back via kubectl proxy", .{err});
                    const fb = try klient.connectWithFallback(
                        self.allocator,
                        cluster.server,
                        null,
                        self.current_namespace,
                    );
                    Logger.info("Connected via fallback, api_server: {s}", .{fb.api_server});
                    break :blk fb;
                };
                client.* = direct_or_fb;
            }
        } else if (user.exec) |exec_cfg| {
            // Exec credential plugin authentication
            Logger.info("Using exec credential plugin: {s}", .{exec_cfg.command orelse "(null)"});

            const exec_config = klient.exec_credential.ExecConfig{
                .command = exec_cfg.command orelse return error.ExecCommandMissing,
                .args = exec_cfg.args,
                .apiVersion = exec_cfg.api_version orelse "client.authentication.k8s.io/v1beta1",
            };

            const cred = klient.exec_credential.executeCredentialPlugin(self.allocator, exec_config) catch |err| {
                Logger.warn("Exec credential plugin failed: {any}. Falling back via kubectl proxy", .{err});
                client.* = try klient.connectWithFallback(
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

            const exec_token = if (cred.value.status) |s| s.token else null;
            if (exec_token) |token| {
                Logger.info("Got token from exec credential plugin", .{});

                if (self.tls_ca_data) |ca| {
                    tls_config = klient.tls.TlsConfig{
                        .ca_cert_data = ca,
                    };
                }

                const direct_or_fb = klient.K8sClient.init(self.allocator, .{
                    .server = cluster.server,
                    .token = token,
                    .namespace = self.current_namespace,
                    .retry_config = klient.defaultConfig,
                    .tls_config = tls_config,
                }) catch |err| blk: {
                    Logger.warn("Direct TLS with exec token failed: {any}. Falling back via kubectl proxy", .{err});
                    const fb = try klient.connectWithFallback(
                        self.allocator,
                        cluster.server,
                        token,
                        self.current_namespace,
                    );
                    Logger.info("Connected via fallback, api_server: {s}", .{fb.api_server});
                    break :blk fb;
                };
                client.* = direct_or_fb;
            } else {
                Logger.warn("Exec credential plugin returned no token, falling back via kubectl proxy", .{});
                client.* = try klient.connectWithFallback(
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
                client.* = try klient.connectWithFallback(
                    self.allocator,
                    cluster.server,
                    null,
                    self.current_namespace,
                );
                Logger.info("Connected via fallback, api_server: {s}", .{client.api_server});
            } else {
                // Attempt unauthenticated TLS connection; fall back via kubectl proxy on failure
                const direct_or_fb = klient.K8sClient.init(self.allocator, .{
                    .server = cluster.server,
                    .token = null,
                    .namespace = self.current_namespace,
                    .retry_config = klient.defaultConfig,
                    .tls_config = tls_config,
                }) catch |err| blk: {
                    Logger.warn("TLS connect (no auth) failed: {any}. Falling back via kubectl proxy", .{err});
                    const fb = try klient.connectWithFallback(
                        self.allocator,
                        cluster.server,
                        null,
                        self.current_namespace,
                    );
                    Logger.info("Connected via fallback, api_server: {s}", .{fb.api_server});
                    break :blk fb;
                };
                client.* = direct_or_fb;
            }
        }

        self.client = client;
        self.connected = true;

        Logger.info("Successfully connected to cluster '{s}' in context '{s}'", .{
            self.cluster_name,
            self.context_name,
        });
    }

    /// Check if connected to a cluster
    pub fn isConnected(self: *const K8sService) bool {
        return self.connected and self.client != null;
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

        const response = self.client.?.request(.GET, "/version", null) catch |err| {
            Logger.warn("Failed to fetch /version: {}", .{err});
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

    // ===== Pod Operations =====

    /// List all pods across all namespaces
    pub fn listAllPods(self: *K8sService) !PodList {
        if (!self.isConnected()) return error.NotConnected;

        const pods_client = klient.resources.Pods.init(self.client.?);
        return try pods_client.client.listAll();
    }

    /// List pods in a specific namespace
    pub fn listPods(self: *K8sService, namespace: ?[]const u8) !PodList {
        if (!self.isConnected()) return error.NotConnected;

        const pods_client = klient.resources.Pods.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
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
        Logger.info("=== listAllDeployments CALLED ===", .{});

        if (!self.isConnected()) {
            Logger.err("listAllDeployments: NOT CONNECTED", .{});
            return error.NotConnected;
        }

        Logger.info("listAllDeployments: Creating Deployments client", .{});
        const client = klient.resources.Deployments.init(self.client.?);

        Logger.info("listAllDeployments: Calling listAll()", .{});
        const list = client.client.listAll() catch |err| {
            Logger.err("listAllDeployments: listAll() failed with error: {any}", .{err});
            return err;
        };
        defer list.deinit();

        Logger.info("listAllDeployments: Got {} deployments", .{list.value.items.len});

        // Allocate a copy of the items since we defer the parsed result
        const items = try self.allocator.alloc(klient.types.Deployment, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List deployments in a namespace
    pub fn listDeployments(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Deployment {
        Logger.info("=== listDeployments CALLED (namespace = {?s}) ===", .{namespace});

        if (!self.isConnected()) {
            Logger.err("listDeployments: NOT CONNECTED", .{});
            return error.NotConnected;
        }

        Logger.info("listDeployments: Creating Deployments client", .{});
        const client = klient.resources.Deployments.init(self.client.?);
        const ns = namespace orelse self.current_namespace;

        Logger.info("listDeployments: Calling list('{s}')...", .{ns});
        const list = client.client.list(ns) catch |err| {
            Logger.err("listDeployments: list() failed with error: {any}", .{err});
            return err;
        };
        defer list.deinit();

        Logger.info("listDeployments: Got {} deployments", .{list.value.items.len});

        // Allocate a copy of the items since we defer the parsed result
        const items = try self.allocator.alloc(klient.types.Deployment, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
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
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Services.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Service, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List services in a namespace
    pub fn listServices(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Service {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Services.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Service, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== Namespace Operations =====

    /// List all namespaces
    pub fn listNamespaces(self: *K8sService) ![]klient.types.Namespace {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Namespaces.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Namespace, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== Node Operations =====

    /// List all nodes
    pub fn listNodes(self: *K8sService) ![]klient.types.Node {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Nodes.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Node, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== ConfigMap Operations (using new ResourceClient) =====

    /// List all configmaps across all namespaces
    pub fn listAllConfigMaps(self: *K8sService) ![]klient.types.ConfigMap {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ConfigMaps.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.ConfigMap, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List configmaps in a namespace
    pub fn listConfigMaps(self: *K8sService, namespace: ?[]const u8) ![]klient.types.ConfigMap {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ConfigMaps.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.ConfigMap, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== Secret Operations (using new ResourceClient) =====

    /// List all secrets across all namespaces
    pub fn listAllSecrets(self: *K8sService) ![]klient.types.Secret {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Secrets.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Secret, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List secrets in a namespace
    pub fn listSecrets(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Secret {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Secrets.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Secret, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== StatefulSet Operations =====

    /// List all statefulsets
    pub fn listAllStatefulSets(self: *K8sService) ![]klient.types.StatefulSet {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.StatefulSets.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.StatefulSet, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List statefulsets in a namespace
    pub fn listStatefulSets(self: *K8sService, namespace: ?[]const u8) ![]klient.types.StatefulSet {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.StatefulSets.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.StatefulSet, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
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
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.DaemonSets.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.DaemonSet, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List daemonsets in a namespace
    pub fn listDaemonSets(self: *K8sService, namespace: ?[]const u8) ![]klient.types.DaemonSet {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.DaemonSets.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.DaemonSet, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== ReplicaSet Operations =====

    /// List all replicasets
    pub fn listAllReplicaSets(self: *K8sService) ![]klient.types.ReplicaSet {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ReplicaSets.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.ReplicaSet, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List replicasets in a namespace
    pub fn listReplicaSets(self: *K8sService, namespace: ?[]const u8) ![]klient.types.ReplicaSet {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ReplicaSets.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.ReplicaSet, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
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
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Jobs.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Job, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List jobs in a namespace
    pub fn listJobs(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Job {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Jobs.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Job, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== CronJob Operations =====

    /// List all cronjobs
    pub fn listAllCronJobs(self: *K8sService) ![]klient.types.CronJob {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.CronJobs.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.CronJob, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List cronjobs in a namespace
    pub fn listCronJobs(self: *K8sService, namespace: ?[]const u8) ![]klient.types.CronJob {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.CronJobs.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.CronJob, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
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
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.PersistentVolumes.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.PersistentVolume, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== PersistentVolumeClaim Operations =====

    /// List all persistent volume claims
    pub fn listAllPersistentVolumeClaims(self: *K8sService) ![]klient.types.PersistentVolumeClaim {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.PersistentVolumeClaims.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.PersistentVolumeClaim, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List persistent volume claims in a namespace
    pub fn listPersistentVolumeClaims(self: *K8sService, namespace: ?[]const u8) ![]klient.types.PersistentVolumeClaim {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.PersistentVolumeClaims.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.PersistentVolumeClaim, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== Ingress Operations =====

    /// List all ingresses across all namespaces
    pub fn listAllIngresses(self: *K8sService) ![]klient.types.Ingress {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Ingresses.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Ingress, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List ingresses in a namespace
    pub fn listIngresses(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Ingress {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Ingresses.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Ingress, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== NetworkPolicy Operations =====

    /// List all network policies across all namespaces
    pub fn listAllNetworkPolicies(self: *K8sService) ![]klient.types.NetworkPolicy {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.NetworkPolicies.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.NetworkPolicy, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List network policies in a namespace
    pub fn listNetworkPolicies(self: *K8sService, namespace: ?[]const u8) ![]klient.types.NetworkPolicy {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.NetworkPolicies.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.NetworkPolicy, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== ServiceAccount Operations =====

    /// List all service accounts across all namespaces
    pub fn listAllServiceAccounts(self: *K8sService) ![]klient.types.ServiceAccount {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ServiceAccounts.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.ServiceAccount, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List service accounts in a namespace
    pub fn listServiceAccounts(self: *K8sService, namespace: ?[]const u8) ![]klient.types.ServiceAccount {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ServiceAccounts.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.ServiceAccount, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== Role Operations =====

    /// List all roles across all namespaces
    pub fn listAllRoles(self: *K8sService) ![]klient.types.Role {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Roles.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Role, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List roles in a namespace
    pub fn listRoles(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Role {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Roles.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Role, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== RoleBinding Operations =====

    /// List all role bindings across all namespaces
    pub fn listAllRoleBindings(self: *K8sService) ![]klient.types.RoleBinding {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.RoleBindings.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.RoleBinding, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List role bindings in a namespace
    pub fn listRoleBindings(self: *K8sService, namespace: ?[]const u8) ![]klient.types.RoleBinding {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.RoleBindings.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.RoleBinding, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== ClusterRole Operations =====

    /// List all cluster roles (cluster-scoped)
    pub fn listAllClusterRoles(self: *K8sService) ![]klient.types.ClusterRole {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ClusterRoles.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.ClusterRole, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== ClusterRoleBinding Operations =====

    /// List all cluster role bindings (cluster-scoped)
    pub fn listAllClusterRoleBindings(self: *K8sService) ![]klient.types.ClusterRoleBinding {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ClusterRoleBindings.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.ClusterRoleBinding, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== Event Operations =====

    /// List all events across all namespaces
    pub fn listAllEvents(self: *K8sService) ![]klient.types.Event {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Events.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Event, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List events in a namespace
    pub fn listEvents(self: *K8sService, namespace: ?[]const u8) ![]klient.types.Event {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.Events.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.Event, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== ResourceQuota Operations =====

    /// List all resource quotas across all namespaces
    pub fn listAllResourceQuotas(self: *K8sService) ![]klient.types.ResourceQuota {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ResourceQuotas.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.ResourceQuota, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List resource quotas in a namespace
    pub fn listResourceQuotas(self: *K8sService, namespace: ?[]const u8) ![]klient.types.ResourceQuota {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.ResourceQuotas.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.ResourceQuota, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== LimitRange Operations =====

    /// List all limit ranges across all namespaces
    pub fn listAllLimitRanges(self: *K8sService) ![]klient.types.LimitRange {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.LimitRanges.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.LimitRange, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List limit ranges in a namespace
    pub fn listLimitRanges(self: *K8sService, namespace: ?[]const u8) ![]klient.types.LimitRange {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.LimitRanges.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.LimitRange, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== PodDisruptionBudget Operations =====

    /// List all pod disruption budgets across all namespaces
    pub fn listAllPodDisruptionBudgets(self: *K8sService) ![]klient.types.PodDisruptionBudget {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.PodDisruptionBudgets.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.PodDisruptionBudget, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List pod disruption budgets in a namespace
    pub fn listPodDisruptionBudgets(self: *K8sService, namespace: ?[]const u8) ![]klient.types.PodDisruptionBudget {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.PodDisruptionBudgets.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.PodDisruptionBudget, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }
    // ===== HorizontalPodAutoscaler Operations =====

    /// List all horizontal pod autoscalers across all namespaces
    pub fn listAllHPAs(self: *K8sService) ![]klient.types.HorizontalPodAutoscaler {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.HorizontalPodAutoscalers.init(self.client.?);
        const list = try client.client.listAll();
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.HorizontalPodAutoscaler, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    /// List horizontal pod autoscalers in a namespace
    pub fn listHPAs(self: *K8sService, namespace: ?[]const u8) ![]klient.types.HorizontalPodAutoscaler {
        if (!self.isConnected()) return error.NotConnected;

        const client = klient.resources.HorizontalPodAutoscalers.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const list = try client.client.list(ns);
        defer list.deinit();

        const items = try self.allocator.alloc(klient.types.HorizontalPodAutoscaler, list.value.items.len);
        @memcpy(items, list.value.items);

        return items;
    }

    // ===== Pod Metrics Operations =====

    /// Aggregated CPU + memory usage for a single pod (sum of all containers)
    pub const PodMetric = struct {
        cpu: []const u8, // e.g. "100m", "2", "n/a"
        mem: []const u8, // e.g. "45Mi", "1Gi", "n/a"
    };

    /// Fetch pod metrics from the Kubernetes Metrics Server.
    /// Returns a map of "namespace/name" -> PodMetric.
    /// If the metrics server is not available, returns null (graceful degradation).
    pub fn getPodMetrics(self: *K8sService, all_namespaces: bool) !?std.StringHashMap(PodMetric) {
        if (!self.isConnected()) return null;

        const metrics_client = klient.MetricsClient.init(self.client.?);

        // Fetch metrics (all namespaces or current namespace)
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

        for (parsed.value.items) |pod_metric| {
            // Sum CPU (millicores) and memory (bytes) across all containers
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

            // Format CPU: show as millicores (e.g. "100m") or whole cores (e.g. "2")
            const cpu_display = if (total_cpu_millicores >= 1000 and total_cpu_millicores % 1000 == 0)
                try std.fmt.allocPrint(self.allocator, "{d}", .{total_cpu_millicores / 1000})
            else
                try std.fmt.allocPrint(self.allocator, "{d}m", .{total_cpu_millicores});
            errdefer self.allocator.free(cpu_display);

            // Format memory: show in appropriate unit
            const mem_display = if (total_mem_bytes >= 1024 * 1024 * 1024 and total_mem_bytes % (1024 * 1024 * 1024) == 0)
                try std.fmt.allocPrint(self.allocator, "{d}Gi", .{total_mem_bytes / (1024 * 1024 * 1024)})
            else if (total_mem_bytes >= 1024 * 1024)
                try std.fmt.allocPrint(self.allocator, "{d}Mi", .{total_mem_bytes / (1024 * 1024)})
            else if (total_mem_bytes >= 1024)
                try std.fmt.allocPrint(self.allocator, "{d}Ki", .{total_mem_bytes / 1024})
            else
                try std.fmt.allocPrint(self.allocator, "{d}", .{total_mem_bytes});
            errdefer self.allocator.free(mem_display);

            // Build key: "namespace/name"
            const ns = pod_metric.metadata.namespace orelse "default";
            const key = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ ns, pod_metric.metadata.name });
            errdefer self.allocator.free(key);

            try result.put(key, PodMetric{
                .cpu = cpu_display,
                .mem = mem_display,
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

    /// Context information structure
    pub const ContextInfo = struct {
        name: []const u8,
        cluster: []const u8,
        user: []const u8,
        namespace: ?[]const u8,
        is_current: bool,
    };

    /// List all available contexts from kubeconfig
    pub fn listContexts(self: *K8sService) ![]ContextInfo {
        var parser = klient.KubeconfigParser.init(self.allocator);
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

        const body = try self.client.?.request(.GET, path, null);
        return body;
    }

    /// Delete any resource by type, name, namespace
    pub fn deleteResource(self: *K8sService, resource_type: ResourceType, name: []const u8, namespace: []const u8) !void {
        if (!self.isConnected()) return error.NotConnected;

        const path = if (resource_type.isClusterScoped())
            try std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}", .{ resource_type.apiPath(), resource_type.resourceName(), name })
        else
            try std.fmt.allocPrint(self.allocator, "{s}/namespaces/{s}/{s}/{s}", .{ resource_type.apiPath(), namespace, resource_type.resourceName(), name });
        defer self.allocator.free(path);

        const body = try self.client.?.request(.DELETE, path, null);
        self.allocator.free(body);
    }

    /// Get pod logs
    pub fn getPodLogs(self: *K8sService, name: []const u8, namespace: ?[]const u8) ![]u8 {
        if (!self.isConnected()) return error.NotConnected;

        const ns = namespace orelse "default";
        const path = try std.fmt.allocPrint(self.allocator, "/api/v1/namespaces/{s}/pods/{s}/log?tailLines=1000", .{ ns, name });
        defer self.allocator.free(path);

        return try self.client.?.request(.GET, path, null);
    }

    // ===== Authorization Methods =====

    /// Result of an access check (SelfSubjectAccessReview)
    pub const AccessCheckResult = struct {
        allowed: bool,
        conditional: bool,
        condition_count: u32,
    };

    /// Policy info from RBAC aggregation
    pub const PolicyInfo = struct {
        source: []const u8,
        resource: []const u8,
        verbs: []const u8,
        subjects: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *PolicyInfo) void {
            self.allocator.free(self.source);
            self.allocator.free(self.resource);
            self.allocator.free(self.verbs);
            self.allocator.free(self.subjects);
        }
    };

    /// Condition info from AuthorizationConditionsReview
    pub const ConditionInfo = struct {
        effect: []const u8,
        authorizer: []const u8,
        expression: []const u8,
        description: []const u8,
        allocator: std.mem.Allocator,

        pub fn deinit(self: *ConditionInfo) void {
            self.allocator.free(self.effect);
            self.allocator.free(self.authorizer);
            self.allocator.free(self.expression);
            self.allocator.free(self.description);
        }
    };

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

        var results = std.ArrayListUnmanaged(ConditionInfo){};
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

    /// Detect if Cedar authorization CRDs are available
    pub fn detectCedarAuth(self: *K8sService) !bool {
        if (!self.isConnected()) return false;

        const response = self.client.?.request(.GET, "/apis/cedar.k8s.io/v1alpha1", null) catch {
            return false;
        };
        defer self.allocator.free(response);

        // Check for a valid API group response (not a 404 status)
        return std.mem.indexOf(u8, response, "cedar.k8s.io") != null;
    }

    /// List Cedar policies from CRDs
    pub fn listCedarPolicies(self: *K8sService) ![]PolicyInfo {
        if (!self.isConnected()) return error.NotConnected;

        const response = self.client.?.request(.GET, "/apis/cedar.k8s.io/v1alpha1/cedarpolicies", null) catch |err| {
            Logger.warn("listCedarPolicies failed: {}", .{err});
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

        var results = std.ArrayListUnmanaged(PolicyInfo){};
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

            const resource_str = if (spec.object.get("resource")) |v|
                if (v == .string) v.string else "*"
            else
                "*";

            const verbs_str = if (spec.object.get("actions")) |v|
                if (v == .string) v.string else "*"
            else
                "*";

            const subjects_str = if (spec.object.get("principal")) |v|
                if (v == .string) v.string else "*"
            else
                "*";

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

        var results = std.ArrayListUnmanaged(PolicyInfo){};
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

                    var subj_list = std.ArrayListUnmanaged(u8){};
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

        // Clear cached version so it gets re-fetched for the new cluster
        if (self.cached_k8s_version) |v| {
            self.allocator.free(v);
            self.cached_k8s_version = null;
        }

        // Reconnect with new context
        try self.connect(context_name);
    }
};

/// Cluster information structure
pub const ClusterInfo = struct {
    context: []const u8,
    cluster: []const u8,
    user: []const u8,
    namespace: []const u8,
    connected: bool,
};

/// Resource type enum for generic operations (describe, delete, etc.)
pub const ResourceType = enum {
    pods,
    deployments,
    services,
    namespaces,
    nodes,
    statefulsets,
    daemonsets,
    replicasets,
    jobs,
    cronjobs,
    configmaps,
    secrets,
    persistentvolumes,
    persistentvolumeclaims,
    ingresses,
    networkpolicies,
    serviceaccounts,
    roles,
    rolebindings,
    clusterroles,
    clusterrolebindings,
    events,
    resourcequotas,
    limitranges,
    poddisruptionbudgets,
    hpa,
    contexts,

    pub fn apiPath(self: ResourceType) []const u8 {
        return switch (self) {
            .pods, .services, .namespaces, .nodes, .configmaps, .secrets,
            .persistentvolumes, .persistentvolumeclaims, .serviceaccounts,
            .events, .resourcequotas, .limitranges,
            => "/api/v1",
            .deployments, .statefulsets, .daemonsets, .replicasets => "/apis/apps/v1",
            .jobs, .cronjobs => "/apis/batch/v1",
            .ingresses, .networkpolicies => "/apis/networking.k8s.io/v1",
            .roles, .rolebindings, .clusterroles, .clusterrolebindings => "/apis/rbac.authorization.k8s.io/v1",
            .poddisruptionbudgets => "/apis/policy/v1",
            .hpa => "/apis/autoscaling/v2",
            .contexts => "/api/v1", // not a real K8s resource
        };
    }

    pub fn resourceName(self: ResourceType) []const u8 {
        return switch (self) {
            .pods => "pods",
            .deployments => "deployments",
            .services => "services",
            .namespaces => "namespaces",
            .nodes => "nodes",
            .statefulsets => "statefulsets",
            .daemonsets => "daemonsets",
            .replicasets => "replicasets",
            .jobs => "jobs",
            .cronjobs => "cronjobs",
            .configmaps => "configmaps",
            .secrets => "secrets",
            .persistentvolumes => "persistentvolumes",
            .persistentvolumeclaims => "persistentvolumeclaims",
            .ingresses => "ingresses",
            .networkpolicies => "networkpolicies",
            .serviceaccounts => "serviceaccounts",
            .roles => "roles",
            .rolebindings => "rolebindings",
            .clusterroles => "clusterroles",
            .clusterrolebindings => "clusterrolebindings",
            .events => "events",
            .resourcequotas => "resourcequotas",
            .limitranges => "limitranges",
            .poddisruptionbudgets => "poddisruptionbudgets",
            .hpa => "horizontalpodautoscalers",
            .contexts => "contexts",
        };
    }

    pub fn isClusterScoped(self: ResourceType) bool {
        return switch (self) {
            .namespaces, .nodes, .persistentvolumes, .clusterroles, .clusterrolebindings => true,
            else => false,
        };
    }
};

/// Resource info returned by views for generic operations
pub const ResourceInfo = struct {
    name: []const u8,
    namespace: []const u8,
};

// ===== Authorization type tests =====

test "AccessCheckResult struct fields" {
    const result = K8sService.AccessCheckResult{
        .allowed = true,
        .conditional = false,
        .condition_count = 0,
    };
    try std.testing.expectEqual(true, result.allowed);
    try std.testing.expectEqual(false, result.conditional);
    try std.testing.expectEqual(@as(u32, 0), result.condition_count);
}

test "AccessCheckResult conditional" {
    const result = K8sService.AccessCheckResult{
        .allowed = true,
        .conditional = true,
        .condition_count = 3,
    };
    try std.testing.expectEqual(true, result.allowed);
    try std.testing.expectEqual(true, result.conditional);
    try std.testing.expectEqual(@as(u32, 3), result.condition_count);
}

test "PolicyInfo init and deinit" {
    const allocator = std.testing.allocator;

    var policy = K8sService.PolicyInfo{
        .source = try allocator.dupe(u8, "admin-role"),
        .resource = try allocator.dupe(u8, "*.*"),
        .verbs = try allocator.dupe(u8, "get,list,watch"),
        .subjects = try allocator.dupe(u8, "system:masters"),
        .allocator = allocator,
    };

    try std.testing.expectEqualStrings("admin-role", policy.source);
    try std.testing.expectEqualStrings("*.*", policy.resource);
    try std.testing.expectEqualStrings("get,list,watch", policy.verbs);
    try std.testing.expectEqualStrings("system:masters", policy.subjects);

    policy.deinit();
}

test "ConditionInfo init and deinit" {
    const allocator = std.testing.allocator;

    var cond = K8sService.ConditionInfo{
        .effect = try allocator.dupe(u8, "Deny"),
        .authorizer = try allocator.dupe(u8, "cedar-webhook"),
        .expression = try allocator.dupe(u8, "resource.metadata.labels[\"protected\"]"),
        .description = try allocator.dupe(u8, "Block protected pods from deletion"),
        .allocator = allocator,
    };

    try std.testing.expectEqualStrings("Deny", cond.effect);
    try std.testing.expectEqualStrings("cedar-webhook", cond.authorizer);

    cond.deinit();
}

test "checkAccess requires connection" {
    const allocator = std.testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const result = service.checkAccess("get", "", "pods", "default");
    try std.testing.expectError(error.NotConnected, result);
}

test "detectConditionalAuth returns false when not connected" {
    const allocator = std.testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const result = try service.detectConditionalAuth();
    try std.testing.expectEqual(false, result);
}

test "detectCedarAuth returns false when not connected" {
    const allocator = std.testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const result = try service.detectCedarAuth();
    try std.testing.expectEqual(false, result);
}

test "getAuthorizationConditions requires connection" {
    const allocator = std.testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const result = service.getAuthorizationConditions("pods", "", "default");
    try std.testing.expectError(error.NotConnected, result);
}

test "listCedarPolicies requires connection" {
    const allocator = std.testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const result = service.listCedarPolicies();
    try std.testing.expectError(error.NotConnected, result);
}

test "listRBACPolicies requires connection" {
    const allocator = std.testing.allocator;

    var service = try K8sService.init(allocator);
    defer service.deinit();

    const result = service.listRBACPolicies();
    try std.testing.expectError(error.NotConnected, result);
}

test "PolicyInfo multiple init/deinit cycles" {
    const allocator = std.testing.allocator;

    for (0..10) |_| {
        var policy = K8sService.PolicyInfo{
            .source = try allocator.dupe(u8, "test-role"),
            .resource = try allocator.dupe(u8, "pods"),
            .verbs = try allocator.dupe(u8, "get"),
            .subjects = try allocator.dupe(u8, "user1"),
            .allocator = allocator,
        };
        policy.deinit();
    }
}

test "ConditionInfo multiple init/deinit cycles" {
    const allocator = std.testing.allocator;

    for (0..10) |_| {
        var cond = K8sService.ConditionInfo{
            .effect = try allocator.dupe(u8, "Allow"),
            .authorizer = try allocator.dupe(u8, "builtin"),
            .expression = try allocator.dupe(u8, "true"),
            .description = try allocator.dupe(u8, "always allow"),
            .allocator = allocator,
        };
        cond.deinit();
    }
}
