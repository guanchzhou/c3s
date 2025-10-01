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

    // TLS certificate data (decoded from base64) - needs cleanup
    tls_ca_data: ?[]const u8 = null,
    tls_cert_data: ?[]const u8 = null,
    tls_key_data: ?[]const u8 = null,

    /// Initialize the K8s service
    pub fn init(allocator: std.mem.Allocator) !K8sService {
        return K8sService{
            .allocator = allocator,
            .client = null,
            .connected = false,
            .current_namespace = try allocator.dupe(u8, "default"),
            .context_name = try allocator.dupe(u8, "unknown"),
            .cluster_name = try allocator.dupe(u8, "unknown"),
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

        // Update context and cluster names
        self.allocator.free(self.context_name);
        self.allocator.free(self.cluster_name);
        self.context_name = try self.allocator.dupe(u8, context.name);
        self.cluster_name = try self.allocator.dupe(u8, cluster.name);

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

        // Skip TLS config for localhost - Rancher Desktop uses system-trusted certs
        const is_localhost = std.mem.indexOf(u8, cluster.server, "127.0.0.1") != null or
            std.mem.indexOf(u8, cluster.server, "localhost") != null;

        Logger.info("DEBUG: cluster.server={s}, is_localhost={}", .{ cluster.server, is_localhost });

        if (!is_localhost) {
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
            if (is_localhost) {
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

                client.* = try klient.K8sClient.init(self.allocator, .{
                    .server = cluster.server,
                    .token = token,
                    .namespace = self.current_namespace,
                    .retry_config = klient.defaultConfig,
                    .tls_config = tls_config,
                });
            }
        } else if (user.client_certificate_data != null or user.client_certificate != null) {
            Logger.info("DEBUG: Entered mTLS auth branch", .{});

            // For localhost, use connectWithFallback (falls back to kubectl proxy)
            if (is_localhost) {
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

                client.* = try klient.K8sClient.init(self.allocator, .{
                    .server = cluster.server,
                    .token = null,
                    .namespace = self.current_namespace,
                    .retry_config = klient.defaultConfig,
                    .tls_config = tls_config,
                });
            }
        } else {
            // No auth credentials - just use CA cert if available
            // TODO: Add exec credential plugin support
            Logger.warn("No token or client certificate found, creating client without auth", .{});

            if (self.tls_ca_data) |ca| {
                tls_config = klient.tls.TlsConfig{
                    .ca_cert_data = ca,
                };
            }

            client.* = try klient.K8sClient.init(self.allocator, .{
                .server = cluster.server,
                .token = null,
                .namespace = self.current_namespace,
                .retry_config = klient.defaultConfig,
                .tls_config = tls_config,
            });
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
        if (self.client) |client| {
            client.namespace = self.current_namespace;
        }
    }

    /// Get cluster information
    pub fn getClusterInfo(self: *const K8sService) ClusterInfo {
        return ClusterInfo{
            .context = self.context_name,
            .cluster = self.cluster_name,
            .namespace = self.current_namespace,
            .connected = self.connected,
        };
    }

    // ===== Pod Operations =====

    /// List all pods across all namespaces
    pub fn listAllPods(self: *K8sService) ![]klient.Pod {
        if (!self.isConnected()) return error.NotConnected;

        const pods_client = klient.resources.Pods.init(self.client.?);
        const pod_list = try pods_client.client.listAll();
        defer pod_list.deinit();

        return pod_list.value.items;
    }

    /// List pods in a specific namespace
    pub fn listPods(self: *K8sService, namespace: ?[]const u8) ![]klient.Pod {
        if (!self.isConnected()) return error.NotConnected;

        const pods_client = klient.resources.Pods.init(self.client.?);
        const ns = namespace orelse self.current_namespace;
        const pod_list = try pods_client.client.list(ns);
        defer pod_list.deinit();

        return pod_list.value.items;
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
        const list = try client.list();
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

        // Reconnect with new context
        try self.connect(context_name);
    }
};

/// Cluster information structure
pub const ClusterInfo = struct {
    context: []const u8,
    cluster: []const u8,
    namespace: []const u8,
    connected: bool,
};
