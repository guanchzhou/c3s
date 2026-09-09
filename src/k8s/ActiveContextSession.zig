const std = @import("std");
const klient = @import("klient");
const task15 = @import("../task15_diagnostics.zig");
const read_transport = @import("ReadTransport.zig");

pub const Generation = u64;

pub const ContextSpec = struct {
    context_name: []const u8,
    kubeconfig_path: ?[]const u8,
    default_namespace: []const u8,
    force_proxy: bool,
    readonly: bool,
};

pub const OwnedContextSpec = struct {
    value: ContextSpec,

    pub fn clone(allocator: std.mem.Allocator, source: ContextSpec) !OwnedContextSpec {
        const context_name = try allocator.dupe(u8, source.context_name);
        errdefer allocator.free(context_name);
        const kubeconfig_path = if (source.kubeconfig_path) |path|
            try allocator.dupe(u8, path)
        else
            null;
        errdefer if (kubeconfig_path) |path| allocator.free(path);
        const default_namespace = try allocator.dupe(u8, source.default_namespace);
        errdefer allocator.free(default_namespace);
        return .{ .value = .{
            .context_name = context_name,
            .kubeconfig_path = kubeconfig_path,
            .default_namespace = default_namespace,
            .force_proxy = source.force_proxy,
            .readonly = source.readonly,
        } };
    }

    pub fn deinit(self: *OwnedContextSpec, allocator: std.mem.Allocator) void {
        allocator.free(self.value.context_name);
        if (self.value.kubeconfig_path) |path| allocator.free(path);
        allocator.free(self.value.default_namespace);
        self.* = undefined;
    }
};

pub const LeasePurpose = enum {
    list_watch,
    metrics,
    header_metrics,
    traffic,
    detail,
    yaml,
    logs,
    authorization,
    command,
};

pub const SessionState = enum(u8) {
    empty,
    preparing,
    active,
    invalidated,
    teardown_ready,
};

pub const TransportMode = enum(u8) {
    klient,
    direct_curl,
    proxy,
};

pub const LifecycleEvent = enum {
    proxy_kill,
    client_deinit,
    credentials_deinit,
    spec_deinit,
    session_deinit,
};

pub const LifecycleObserver = struct {
    context: *anyopaque,
    observe_fn: *const fn (*anyopaque, LifecycleEvent) void,

    pub fn init(
        context: anytype,
        observe_fn: *const fn (*anyopaque, LifecycleEvent) void,
    ) LifecycleObserver {
        return .{ .context = @ptrCast(context), .observe_fn = observe_fn };
    }

    fn emit(self: LifecycleObserver, event: LifecycleEvent) void {
        self.observe_fn(self.context, event);
    }
};

var probe_sentinel: u8 = 0;

pub const ReadinessProbe = struct {
    context: *anyopaque,
    verify_fn: *const fn (*anyopaque, *ActiveContextSession) anyerror!void,

    pub fn init(
        context: anytype,
        verify_fn: *const fn (*anyopaque, *ActiveContextSession) anyerror!void,
    ) ReadinessProbe {
        return .{ .context = @ptrCast(context), .verify_fn = verify_fn };
    }

    pub fn alwaysReady() ReadinessProbe {
        return init(&probe_sentinel, alwaysReadyFn);
    }

    pub fn clientVersion() ReadinessProbe {
        return init(&probe_sentinel, clientVersionFn);
    }

    fn alwaysReadyFn(_: *anyopaque, _: *ActiveContextSession) anyerror!void {}

    fn clientVersionFn(_: *anyopaque, session: *ActiveContextSession) anyerror!void {
        const target = try task15.enforceRequest(.GET, "/version");
        emitRequestAudit(session.spec.context_name, target, null, "start");
        const body = session.client.request(.GET, "/version", null) catch |err| {
            emitRequestAudit(session.spec.context_name, target, null, "terminal");
            return err;
        };
        session.allocator.free(body);
        emitRequestAudit(session.spec.context_name, target, 200, "none");
    }

    fn verify(self: ReadinessProbe, session: *ActiveContextSession) !void {
        try self.verify_fn(self.context, session);
    }
};

fn emitRequestAudit(
    context_name: []const u8,
    target: task15.SanitizedRequest,
    status: ?u16,
    retry_class: []const u8,
) void {
    var writer = task15.Writer.initFromEnv();
    writer.emit(.{
        .event = .request_audit,
        .context = context_name,
        .scope = target.scope,
        .family = task15.familyForResource(target.resource),
        .method = .GET,
        .api_group = target.api_group,
        .resource = target.resource,
        .subresource = target.subresource,
        .endpoint_class = target.endpoint_class,
        .status = status,
        .retry_class = retry_class,
        .identity_fingerprint = target.identity_fingerprint,
        .query_fingerprint = target.query_fingerprint,
    });
}

pub const CredentialProvider = struct {
    allocator: std.mem.Allocator,
    auth_token: ?[]const u8 = null,
    exec_command: ?[]const u8 = null,
    exec_args: ?[][]const u8 = null,
    exec_api_version: ?[]const u8 = null,
    tls_ca_data: ?[]const u8 = null,
    tls_cert_data: ?[]const u8 = null,
    tls_key_data: ?[]const u8 = null,

    pub fn empty(allocator: std.mem.Allocator) CredentialProvider {
        return .{ .allocator = allocator };
    }

    fn secureFree(self: *CredentialProvider, bytes: []const u8) void {
        std.crypto.secureZero(u8, @constCast(bytes));
        self.allocator.free(bytes);
    }

    pub fn replaceToken(self: *CredentialProvider, token: []const u8) !void {
        const replacement = try self.allocator.dupe(u8, token);
        if (self.auth_token) |old| self.secureFree(old);
        self.auth_token = replacement;
    }

    pub fn setExecConfig(
        self: *CredentialProvider,
        command: []const u8,
        args: ?[]const []const u8,
        api_version: []const u8,
    ) !void {
        const command_copy = try self.allocator.dupe(u8, command);
        errdefer self.allocator.free(command_copy);
        const version_copy = try self.allocator.dupe(u8, api_version);
        errdefer self.allocator.free(version_copy);

        var args_copy: ?[][]const u8 = null;
        if (args) |source| {
            const owned = try self.allocator.alloc([]const u8, source.len);
            errdefer self.allocator.free(owned);
            var initialized: usize = 0;
            errdefer for (owned[0..initialized]) |arg| self.allocator.free(arg);
            for (source, owned) |arg, *destination| {
                destination.* = try self.allocator.dupe(u8, arg);
                initialized += 1;
            }
            args_copy = owned;
        }

        self.exec_command = command_copy;
        self.exec_api_version = version_copy;
        self.exec_args = args_copy;
    }

    pub fn deinit(self: *CredentialProvider) void {
        if (self.auth_token) |token| self.secureFree(token);
        if (self.exec_command) |command| self.allocator.free(command);
        if (self.exec_api_version) |version| self.allocator.free(version);
        if (self.exec_args) |args| {
            for (args) |arg| self.allocator.free(arg);
            self.allocator.free(args);
        }
        if (self.tls_ca_data) |ca| self.allocator.free(ca);
        if (self.tls_cert_data) |cert| self.secureFree(cert);
        if (self.tls_key_data) |key| self.secureFree(key);
        self.* = empty(self.allocator);
    }
};

pub const ProxyOwner = struct {
    context: *anyopaque,
    port: u16,
    kill_fn: *const fn (*anyopaque, std.Io) void,
    deinit_fn: *const fn (*anyopaque, std.mem.Allocator) void,
    killed: bool = false,

    pub fn init(
        context: anytype,
        port: u16,
        kill_fn: *const fn (*anyopaque, std.Io) void,
        deinit_fn: *const fn (*anyopaque, std.mem.Allocator) void,
    ) ProxyOwner {
        return .{
            .context = @ptrCast(context),
            .port = port,
            .kill_fn = kill_fn,
            .deinit_fn = deinit_fn,
        };
    }

    pub fn fromChild(
        allocator: std.mem.Allocator,
        child: std.process.Child,
        port: u16,
    ) !ProxyOwner {
        const state = try allocator.create(ChildState);
        state.* = .{ .child = child };
        return init(state, port, killChild, deinitChild);
    }

    pub fn kill(self: *ProxyOwner, io: std.Io) void {
        if (self.killed) return;
        self.killed = true;
        self.kill_fn(self.context, io);
    }

    pub fn deinit(self: *ProxyOwner, allocator: std.mem.Allocator) void {
        self.deinit_fn(self.context, allocator);
        self.* = undefined;
    }

    const ChildState = struct {
        child: std.process.Child,
    };

    fn killChild(context: *anyopaque, io: std.Io) void {
        const state: *ChildState = @ptrCast(@alignCast(context));
        state.child.kill(io);
    }

    fn deinitChild(context: *anyopaque, allocator: std.mem.Allocator) void {
        const state: *ChildState = @ptrCast(@alignCast(context));
        allocator.destroy(state);
    }
};

pub const ProxyStarter = struct {
    context: *anyopaque,
    start_fn: *const fn (*anyopaque, *ActiveContextSession) anyerror!ProxyOwner,

    pub fn init(
        context: anytype,
        start_fn: *const fn (*anyopaque, *ActiveContextSession) anyerror!ProxyOwner,
    ) ProxyStarter {
        return .{ .context = @ptrCast(context), .start_fn = start_fn };
    }

    pub fn start(self: ProxyStarter, session: *ActiveContextSession) !ProxyOwner {
        return self.start_fn(self.context, session);
    }
};

pub const DirectCurlProbe = struct {
    context: *anyopaque,
    verify_fn: *const fn (*anyopaque, *ActiveContextSession) anyerror!void,

    pub fn init(
        context: anytype,
        verify_fn: *const fn (*anyopaque, *ActiveContextSession) anyerror!void,
    ) DirectCurlProbe {
        return .{ .context = @ptrCast(context), .verify_fn = verify_fn };
    }

    pub fn production() DirectCurlProbe {
        return init(&probe_sentinel, productionVerify);
    }

    fn productionVerify(_: *anyopaque, session: *ActiveContextSession) anyerror!void {
        try session.verifyDirectCurl();
    }

    fn verify(self: DirectCurlProbe, session: *ActiveContextSession) !void {
        try self.verify_fn(self.context, session);
    }
};

pub const SessionFactory = struct {
    context: *anyopaque,
    prepare_fn: *const fn (
        *anyopaque,
        std.mem.Allocator,
        std.Io,
        *std.Io.Event,
        Generation,
        ContextSpec,
    ) anyerror!*ActiveContextSession,

    pub fn init(
        context: anytype,
        prepare_fn: *const fn (
            *anyopaque,
            std.mem.Allocator,
            std.Io,
            *std.Io.Event,
            Generation,
            ContextSpec,
        ) anyerror!*ActiveContextSession,
    ) SessionFactory {
        return .{ .context = @ptrCast(context), .prepare_fn = prepare_fn };
    }

    pub fn production() SessionFactory {
        return init(&probe_sentinel, productionPrepare);
    }

    pub fn prepare(
        self: SessionFactory,
        allocator: std.mem.Allocator,
        io: std.Io,
        shared_event: *std.Io.Event,
        generation: Generation,
        spec: ContextSpec,
    ) !*ActiveContextSession {
        return self.prepare_fn(
            self.context,
            allocator,
            io,
            shared_event,
            generation,
            spec,
        );
    }

    fn productionPrepare(
        _: *anyopaque,
        allocator: std.mem.Allocator,
        io: std.Io,
        shared_event: *std.Io.Event,
        generation: Generation,
        spec: ContextSpec,
    ) anyerror!*ActiveContextSession {
        return ActiveContextSession.prepare(
            allocator,
            io,
            shared_event,
            generation,
            spec,
        );
    }
};

pub const RequestLease = struct {
    session: *ActiveContextSession,
    generation: Generation,
    purpose: LeasePurpose,
    shared_event: *std.Io.Event,
    released: bool = false,

    pub fn client(self: *RequestLease) !*klient.K8sClient {
        if (self.released) return error.LeaseReleased;
        return self.session.requestClient();
    }

    pub fn contextName(self: *RequestLease) ![]const u8 {
        if (self.released) return error.LeaseReleased;
        return self.session.spec.context_name;
    }

    pub fn readTransport(
        self: *RequestLease,
        io: std.Io,
        cancel_requested: *const std.atomic.Value(bool),
    ) !read_transport.TransportAdapter {
        if (self.released) return error.LeaseReleased;
        return self.session.requestTransportAdapter(io, cancel_requested);
    }

    pub fn release(self: *RequestLease) void {
        if (self.released) return;
        self.released = true;
        self.session.releaseLease(self.shared_event);
    }
};

pub const ActiveContextSession = struct {
    pub const ProxyState = enum {
        stopped,
        starting,
        ready,
        failed,
    };

    pub const RequestView = struct {
        use_kubectl: bool,
        proxy_port: ?u16,
        transport_mode: TransportMode,
        context_name: []const u8,
        kubeconfig_path: ?[]const u8,
        credentials: *CredentialProvider,
    };

    pub const AdoptOptions = struct {
        shared_event: *std.Io.Event,
        client: *klient.K8sClient,
        cluster_name: []const u8,
        user_name: []const u8,
        credential_provider: ?CredentialProvider = null,
        direct_curl_allowed: bool = false,
        defer_curl_readiness: bool = false,
        direct_curl_probe: DirectCurlProbe = DirectCurlProbe.production(),
        readiness: ReadinessProbe = ReadinessProbe.clientVersion(),
        readiness_verified: bool = false,
        observer: ?LifecycleObserver = null,
        proxy_starter: ?ProxyStarter = null,
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    shared_event: *std.Io.Event,
    generation: Generation,
    spec: ContextSpec,
    cluster_name: []const u8,
    user_name: []const u8,
    client: *klient.K8sClient,
    proxy_client: ?*klient.K8sClient,
    credential_provider: CredentialProvider,
    proxy: ?ProxyOwner,
    use_kubectl: bool,
    transport_mode: TransportMode,
    direct_curl_allowed: bool,
    defer_curl_readiness: bool,
    direct_curl_probe: DirectCurlProbe,
    readiness: ReadinessProbe,
    readiness_verified: bool,
    observer: ?LifecycleObserver,
    proxy_starter: ?ProxyStarter,
    lease_count: std.atomic.Value(usize) = .init(0),
    lease_epoch: std.atomic.Value(u64) = .init(0),
    state: std.atomic.Value(SessionState) = .init(.preparing),
    proxy_state: ProxyState,
    mutex: std.Io.Mutex = .init,
    proxy_condition: std.Io.Condition = .init,

    pub fn adopt(
        allocator: std.mem.Allocator,
        io: std.Io,
        generation: Generation,
        spec: ContextSpec,
        options: AdoptOptions,
    ) !*ActiveContextSession {
        var owned_spec = try OwnedContextSpec.clone(allocator, spec);
        errdefer owned_spec.deinit(allocator);
        const cluster_name = try allocator.dupe(u8, options.cluster_name);
        errdefer allocator.free(cluster_name);
        const user_name = try allocator.dupe(u8, options.user_name);
        errdefer allocator.free(user_name);
        const session = try allocator.create(ActiveContextSession);
        session.* = .{
            .allocator = allocator,
            .io = io,
            .shared_event = options.shared_event,
            .generation = generation,
            .spec = owned_spec.value,
            .cluster_name = cluster_name,
            .user_name = user_name,
            .client = options.client,
            .proxy_client = null,
            .credential_provider = options.credential_provider orelse CredentialProvider.empty(allocator),
            .proxy = null,
            .use_kubectl = false,
            .transport_mode = .klient,
            .direct_curl_allowed = options.direct_curl_allowed,
            .defer_curl_readiness = options.defer_curl_readiness,
            .direct_curl_probe = options.direct_curl_probe,
            .readiness = options.readiness,
            .readiness_verified = options.readiness_verified,
            .observer = options.observer,
            .proxy_starter = options.proxy_starter,
            .proxy_state = .stopped,
        };
        return session;
    }

    pub fn prepare(
        allocator: std.mem.Allocator,
        io: std.Io,
        shared_event: *std.Io.Event,
        generation: Generation,
        requested_spec: ContextSpec,
    ) !*ActiveContextSession {
        var parser = klient.KubeconfigParser.init(allocator, io);
        var kubeconfig = if (requested_spec.kubeconfig_path) |path|
            try parser.loadFromPath(path)
        else
            try parser.load();
        defer kubeconfig.deinit(allocator);

        const selected_name = if (requested_spec.context_name.len > 0)
            requested_spec.context_name
        else
            kubeconfig.current_context;
        if (selected_name.len == 0) return error.NoContext;
        const context = kubeconfig.getContextByName(selected_name) orelse
            return error.ContextNotFound;
        const cluster = kubeconfig.getClusterByName(context.cluster) orelse
            return error.ClusterNotFound;
        const user = kubeconfig.getUserByName(context.user) orelse
            return error.UserNotFound;
        const namespace = if (context.namespace) |value|
            if (value.len > 0) value else requested_spec.default_namespace
        else
            requested_spec.default_namespace;

        var credentials = CredentialProvider.empty(allocator);
        var credentials_owned = true;
        defer if (credentials_owned) credentials.deinit();

        if (cluster.certificate_authority_data) |encoded| {
            credentials.tls_ca_data = try klient.tls.decodeBase64Cert(allocator, encoded);
        } else if (cluster.certificate_authority) |path| {
            credentials.tls_ca_data = try std.Io.Dir.cwd().readFileAlloc(
                io,
                path,
                allocator,
                .limited(10 * 1024 * 1024),
            );
        }
        if (user.client_certificate_data) |encoded| {
            credentials.tls_cert_data = try klient.tls.decodeBase64Cert(allocator, encoded);
        } else if (user.client_certificate) |path| {
            credentials.tls_cert_data = try std.Io.Dir.cwd().readFileAlloc(
                io,
                path,
                allocator,
                .limited(10 * 1024 * 1024),
            );
        }
        if (user.client_key_data) |encoded| {
            credentials.tls_key_data = try klient.tls.decodeBase64Cert(allocator, encoded);
        } else if (user.client_key) |path| {
            credentials.tls_key_data = try std.Io.Dir.cwd().readFileAlloc(
                io,
                path,
                allocator,
                .limited(10 * 1024 * 1024),
            );
        }

        var token: ?[]const u8 = user.token;
        if (token) |value| {
            try credentials.replaceToken(value);
            token = credentials.auth_token;
        }

        var force_proxy = requested_spec.force_proxy or
            user.client_certificate_data != null or user.client_certificate != null;
        const direct_curl_allowed = task15.isLiveMode();
        if (user.exec) |exec_config| {
            const command = exec_config.command orelse return error.ExecCommandMissing;
            const api_version = exec_config.api_version orelse
                "client.authentication.k8s.io/v1beta1";
            try credentials.setExecConfig(command, exec_config.args, api_version);
            if (!force_proxy or direct_curl_allowed) {
                const parsed_result = klient.exec_credential.executeCredentialPlugin(
                    allocator,
                    io,
                    .{
                        .command = command,
                        .args = exec_config.args,
                        .apiVersion = api_version,
                    },
                );
                if (parsed_result) |parsed| {
                    defer parsed.deinit();
                    if (parsed.value.status) |status| {
                        if (status.token) |value| {
                            try credentials.replaceToken(value);
                            token = credentials.auth_token;
                            std.crypto.secureZero(u8, @constCast(value));
                        }
                    }
                } else |_| {
                    force_proxy = true;
                    token = null;
                }
            }
        }

        const tls_config: ?klient.tls.TlsConfig = if (!force_proxy and credentials.tls_ca_data != null)
            .{ .ca_cert_data = credentials.tls_ca_data }
        else
            null;
        const client = try allocator.create(klient.K8sClient);
        var client_initialized = false;
        var client_transferred = false;
        errdefer if (!client_transferred) {
            if (client_initialized) client.deinit();
            allocator.destroy(client);
        };
        client.* = try klient.K8sClient.init(allocator, io, .{
            .server = cluster.server,
            .token = token,
            .namespace = namespace,
            .retry_config = klient.defaultConfig,
            .tls_config = tls_config,
        });
        client_initialized = true;

        const session = try adopt(allocator, io, generation, .{
            .context_name = context.name,
            .kubeconfig_path = requested_spec.kubeconfig_path,
            .default_namespace = namespace,
            .force_proxy = force_proxy,
            .readonly = requested_spec.readonly,
        }, .{
            .shared_event = shared_event,
            .client = client,
            .cluster_name = cluster.name,
            .user_name = user.name,
            .credential_provider = credentials,
            .direct_curl_allowed = direct_curl_allowed,
            .defer_curl_readiness = direct_curl_allowed,
        });
        client_transferred = true;
        credentials_owned = false;
        return session;
    }

    pub fn verifyReady(self: *ActiveContextSession) !void {
        try self.readiness.verify(self);
    }

    pub fn ensureReady(self: *ActiveContextSession) !void {
        self.mutex.lockUncancelable(self.io);
        if (self.readiness_verified) {
            self.mutex.unlock(self.io);
            return;
        }
        const current_state = self.state.load(.acquire);
        if (current_state == .invalidated or current_state == .teardown_ready) {
            self.mutex.unlock(self.io);
            return error.SessionInvalidated;
        }
        const force_proxy = self.spec.force_proxy;
        self.mutex.unlock(self.io);

        if (!force_proxy) {
            self.verifyReady() catch {
                if (self.direct_curl_allowed) {
                    if (!self.defer_curl_readiness) self.direct_curl_probe.verify(self) catch {
                        self.startProxy() catch return error.ReadinessFailed;
                        return self.markReady(.proxy);
                    };
                    return self.markReady(.direct_curl);
                }
                self.startProxy() catch return error.ReadinessFailed;
                return self.markReady(.proxy);
            };
            return self.markReady(.klient);
        }

        if (self.direct_curl_allowed) {
            if (!self.defer_curl_readiness) self.direct_curl_probe.verify(self) catch {
                self.startProxy() catch return error.ReadinessFailed;
                return self.markReady(.proxy);
            };
            return self.markReady(.direct_curl);
        }
        self.startProxy() catch return error.ReadinessFailed;
        return self.markReady(.proxy);
    }

    pub fn isReady(self: *ActiveContextSession) bool {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.readiness_verified;
    }

    pub fn startProxy(self: *ActiveContextSession) !void {
        self.mutex.lockUncancelable(self.io);
        while (self.proxy_state == .starting) {
            self.proxy_condition.waitUncancelable(self.io, &self.mutex);
        }
        const current_state = self.state.load(.acquire);
        if (current_state == .invalidated or current_state == .teardown_ready) {
            self.mutex.unlock(self.io);
            return error.SessionInvalidated;
        }
        switch (self.proxy_state) {
            .ready => {
                self.mutex.unlock(self.io);
                return;
            },
            .failed => {
                self.mutex.unlock(self.io);
                return error.ProxyNotReady;
            },
            .stopped => self.proxy_state = .starting,
            .starting => unreachable,
        }
        self.mutex.unlock(self.io);

        var proxy = (if (self.proxy_starter) |starter|
            starter.start(self)
        else
            self.startProxyOwned()) catch |err| {
            self.mutex.lockUncancelable(self.io);
            self.proxy_state = .failed;
            self.use_kubectl = false;
            self.proxy_condition.broadcast(self.io);
            self.mutex.unlock(self.io);
            return err;
        };
        var proxy_owned = true;
        errdefer if (proxy_owned) {
            proxy.kill(self.io);
            proxy.deinit(self.allocator);
            self.markProxyFailed();
        };

        const proxy_server = try std.fmt.allocPrint(
            self.allocator,
            "http://127.0.0.1:{d}",
            .{proxy.port},
        );
        defer self.allocator.free(proxy_server);
        var proxy_client_value = try klient.K8sClient.init(self.allocator, self.io, .{
            .server = proxy_server,
            .namespace = self.client.namespace,
            .max_response_size = self.client.max_response_size,
        });
        var proxy_client_owned = true;
        errdefer if (proxy_client_owned) proxy_client_value.deinit();
        const proxy_client = try self.allocator.create(klient.K8sClient);
        proxy_client.* = proxy_client_value;
        proxy_client_owned = false;

        self.mutex.lockUncancelable(self.io);
        if (self.state.load(.acquire) == .invalidated) {
            self.mutex.unlock(self.io);
            proxy_client.deinit();
            self.allocator.destroy(proxy_client);
            return error.SessionInvalidated;
        }
        std.debug.assert(self.proxy == null);
        std.debug.assert(self.proxy_client == null);
        self.proxy = proxy;
        self.proxy_client = proxy_client;
        proxy_owned = false;
        self.proxy_state = .ready;
        self.use_kubectl = true;
        self.transport_mode = .proxy;
        self.proxy_condition.broadcast(self.io);
        self.mutex.unlock(self.io);
    }

    fn markProxyFailed(self: *ActiveContextSession) void {
        self.mutex.lockUncancelable(self.io);
        self.proxy_state = .failed;
        self.use_kubectl = false;
        self.proxy_condition.broadcast(self.io);
        self.mutex.unlock(self.io);
    }

    fn requestClient(self: *ActiveContextSession) *klient.K8sClient {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return self.proxy_client orelse self.client;
    }

    fn requestTransportAdapter(
        self: *ActiveContextSession,
        io: std.Io,
        cancel_requested: *const std.atomic.Value(bool),
    ) read_transport.TransportAdapter {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return switch (self.transport_mode) {
            .klient => .{ .klient = .{
                .client = self.client,
                .io = io,
                .context_name = self.spec.context_name,
                .cancel_requested = cancel_requested,
            } },
            .proxy => .{ .klient = .{
                .client = self.proxy_client.?,
                .io = io,
                .context_name = self.spec.context_name,
                .cancel_requested = cancel_requested,
            } },
            .direct_curl => .{ .fallback = .{
                .context = self,
                .io = io,
                .cancel_requested = cancel_requested,
                .get_fn = fallbackCurlGet,
            } },
        };
    }

    fn fallbackCurlGet(
        raw: *anyopaque,
        io: std.Io,
        cancel_requested: *const std.atomic.Value(bool),
        request: read_transport.ReadRequest,
        callback_context: *anyopaque,
        callback: read_transport.ReadCallback,
    ) anyerror!void {
        const self: *ActiveContextSession = @ptrCast(@alignCast(raw));
        var final_curl_error: ?anyerror = null;
        for (0..2) |attempt| {
            var callback_error: ?anyerror = null;
            var curl = read_transport.CurlTransport{
                .allocator = self.allocator,
                .io = io,
                .config = .{
                    .server = self.client.api_server,
                    .token = self.credential_provider.auth_token,
                    .ca_pem = self.credential_provider.tls_ca_data,
                    .client_cert_pem = self.credential_provider.tls_cert_data,
                    .client_key_pem = self.credential_provider.tls_key_data,
                },
                .context_name = self.spec.context_name,
                .cancel_requested = cancel_requested,
                .callback_error_out = &callback_error,
                .recoverable_transport_errors = true,
            };
            curl.transport().get(request, callback_context, callback) catch |curl_error| {
                if (callback_error) |err| return err;
                if (curl_error == error.Canceled or cancel_requested.load(.acquire))
                    return error.Canceled;
                if (attempt == 0) continue;
                final_curl_error = curl_error;
                break;
            };
            return;
        }

        const curl_error = final_curl_error orelse return error.CurlFailed;
        self.startProxy() catch return curl_error;
        var proxy = read_transport.KlientTransport{
            .client = self.requestClient(),
            .io = io,
            .context_name = self.spec.context_name,
            .cancel_requested = cancel_requested,
        };
        return proxy.transport().get(request, callback_context, callback);
    }

    pub fn acquireLocked(
        self: *ActiveContextSession,
        purpose: LeasePurpose,
        shared_event: *std.Io.Event,
    ) !RequestLease {
        if (self.shared_event != shared_event) return error.SharedEventMismatch;
        if (self.state.load(.acquire) != .active) return error.SessionInvalidated;
        _ = self.lease_count.fetchAdd(1, .acq_rel);
        return .{
            .session = self,
            .generation = self.generation,
            .purpose = purpose,
            .shared_event = shared_event,
        };
    }

    pub fn requestView(self: *ActiveContextSession) RequestView {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        return .{
            .use_kubectl = self.use_kubectl,
            .proxy_port = if (self.proxy) |proxy| proxy.port else null,
            .transport_mode = self.transport_mode,
            .context_name = self.spec.context_name,
            .kubeconfig_path = self.spec.kubeconfig_path,
            .credentials = &self.credential_provider,
        };
    }

    pub fn activateLocked(self: *ActiveContextSession) !void {
        if (!self.readiness_verified) return error.SessionNotReady;
        if (self.state.load(.acquire) != .preparing) return error.InvalidSessionState;
        self.state.store(.active, .release);
    }

    pub fn invalidate(self: *ActiveContextSession) void {
        const current = self.state.load(.acquire);
        if (current == .teardown_ready) return;
        self.state.store(.invalidated, .release);
    }

    pub fn leaseCount(self: *const ActiveContextSession) usize {
        return self.lease_count.load(.acquire);
    }

    pub fn leaseEpoch(self: *const ActiveContextSession) u64 {
        return self.lease_epoch.load(.acquire);
    }

    pub fn logicalState(self: *const ActiveContextSession) SessionState {
        return self.state.load(.acquire);
    }

    pub fn checkTeardownReady(self: *const ActiveContextSession) !void {
        if (self.leaseCount() != 0) return error.LeasesOutstanding;
        if (self.logicalState() == .active) return error.SessionStillActive;
    }

    pub fn deinit(self: *ActiveContextSession) void {
        if (self.logicalState() == .preparing) self.invalidate();
        self.checkTeardownReady() catch |err|
            std.debug.panic("active session teardown rejected: {any}", .{err});

        self.mutex.lockUncancelable(self.io);
        while (self.proxy_state == .starting) {
            self.proxy_condition.waitUncancelable(self.io, &self.mutex);
        }
        var proxy = self.proxy;
        const proxy_client = self.proxy_client;
        self.proxy = null;
        self.proxy_client = null;
        self.proxy_state = .stopped;
        self.mutex.unlock(self.io);

        if (proxy_client) |owned_client| {
            owned_client.deinit();
            self.allocator.destroy(owned_client);
        }
        if (proxy) |*owned_proxy| {
            self.emit(.proxy_kill);
            owned_proxy.kill(self.io);
            owned_proxy.deinit(self.allocator);
        }

        self.emit(.client_deinit);
        self.client.deinit();
        self.allocator.destroy(self.client);
        self.emit(.credentials_deinit);
        self.credential_provider.deinit();

        self.emit(.spec_deinit);
        var owned_spec = OwnedContextSpec{ .value = self.spec };
        owned_spec.deinit(self.allocator);
        self.allocator.free(self.cluster_name);
        self.allocator.free(self.user_name);
        self.state.store(.teardown_ready, .release);
        self.emit(.session_deinit);
        self.allocator.destroy(self);
    }

    fn markReady(self: *ActiveContextSession, mode: TransportMode) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const current_state = self.state.load(.acquire);
        if (current_state == .invalidated or current_state == .teardown_ready) {
            return error.SessionInvalidated;
        }
        if (mode == .proxy and
            (self.proxy_state != .ready or self.proxy_client == null))
        {
            return error.ProxyNotReady;
        }
        self.transport_mode = mode;
        self.readiness_verified = true;
    }

    fn verifyDirectCurl(self: *ActiveContextSession) !void {
        var canceled = std.atomic.Value(bool).init(false);
        var adapter = read_transport.CurlTransport{
            .allocator = self.allocator,
            .io = self.io,
            .config = .{
                .server = self.client.api_server,
                .token = self.credential_provider.auth_token,
                .ca_pem = self.credential_provider.tls_ca_data,
                .client_cert_pem = self.credential_provider.tls_cert_data,
                .client_key_pem = self.credential_provider.tls_key_data,
            },
            .context_name = self.spec.context_name,
            .cancel_requested = &canceled,
        };
        const Probe = struct {
            fn receive(
                _: *anyopaque,
                meta: read_transport.ResponseMeta,
                reader: *std.Io.Reader,
            ) anyerror!void {
                if (meta.status.class() != .success) return error.ReadinessFailed;
                _ = try reader.discardRemaining();
            }
        };
        var callback_context: u8 = 0;
        try adapter.transport().get(
            try read_transport.ReadRequest.init("/version"),
            &callback_context,
            Probe.receive,
        );
    }

    fn releaseLease(
        self: *ActiveContextSession,
        shared_event: *std.Io.Event,
    ) void {
        std.debug.assert(self.shared_event == shared_event);
        const previous = self.lease_count.fetchSub(1, .release);
        std.debug.assert(previous > 0);
        _ = self.lease_epoch.fetchAdd(1, .acq_rel);
        shared_event.set(self.io);
    }

    fn startProxyOwned(self: *ActiveContextSession) !ProxyOwner {
        const target = try task15.enforceRequest(.GET, "/version");
        var address: std.Io.net.IpAddress = .{ .ip4 = .loopback(0) };
        var reservation = try address.listen(self.io, .{});
        const port = reservation.socket.address.getPort();
        reservation.deinit(self.io);

        const port_arg = try std.fmt.allocPrint(self.allocator, "--port={d}", .{port});
        defer self.allocator.free(port_arg);
        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "kubectl");
        if (self.spec.kubeconfig_path) |path| {
            try argv.append(self.allocator, "--kubeconfig");
            try argv.append(self.allocator, path);
        }
        try argv.append(self.allocator, "--context");
        try argv.append(self.allocator, self.spec.context_name);
        try argv.append(self.allocator, "proxy");
        try argv.append(self.allocator, port_arg);
        try argv.append(self.allocator, "--address=127.0.0.1");

        var child = try std.process.spawn(self.io, .{
            .argv = argv.items,
            .stdin = .ignore,
            .stdout = .ignore,
            .stderr = .ignore,
        });
        var child_owned = true;
        errdefer if (child_owned) child.kill(self.io);

        const url = try std.fmt.allocPrint(
            self.allocator,
            "http://127.0.0.1:{d}/version",
            .{port},
        );
        defer self.allocator.free(url);
        emitRequestAudit(self.spec.context_name, target, null, "start");
        var proxy_ready = false;
        for (0..80) |_| {
            const probe = std.process.run(self.allocator, self.io, .{
                .argv = &.{ "curl", "-sf", "--max-time", "0.2", url },
                .stdout_limit = .limited(1024 * 1024),
            }) catch |err| {
                emitRequestAudit(self.spec.context_name, target, null, "terminal");
                return err;
            };
            const succeeded = probe.term == .exited and probe.term.exited == 0;
            self.allocator.free(probe.stdout);
            self.allocator.free(probe.stderr);
            if (succeeded) {
                proxy_ready = true;
                break;
            }
            self.io.sleep(.{ .nanoseconds = 50 * std.time.ns_per_ms }, .awake) catch |err| {
                emitRequestAudit(self.spec.context_name, target, null, "terminal");
                return err;
            };
        }
        if (!proxy_ready) {
            emitRequestAudit(self.spec.context_name, target, null, "terminal");
            return error.ProxyNotReady;
        }
        emitRequestAudit(self.spec.context_name, target, 200, "none");

        const proxy = try ProxyOwner.fromChild(self.allocator, child, port);
        child_owned = false;
        return proxy;
    }

    fn emit(self: *ActiveContextSession, event: LifecycleEvent) void {
        if (self.observer) |observer| observer.emit(event);
    }
};

test "request leases route streaming clients through an owned proxy" {
    const ProxyHarness = struct {
        kills: usize = 0,
        deinits: usize = 0,

        fn start(context: *anyopaque, _: *ActiveContextSession) anyerror!ProxyOwner {
            const self: *@This() = @ptrCast(@alignCast(context));
            return ProxyOwner.init(self, 43124, kill, deinit);
        }

        fn kill(context: *anyopaque, _: std.Io) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.kills += 1;
        }

        fn deinit(context: *anyopaque, _: std.mem.Allocator) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.deinits += 1;
        }
    };

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var shared_event: std.Io.Event = .unset;
    var proxy_harness = ProxyHarness{};
    const direct_client = try allocator.create(klient.K8sClient);
    errdefer allocator.destroy(direct_client);
    direct_client.* = try klient.K8sClient.init(allocator, io, .{
        .server = "https://cluster.example.test",
        .namespace = "default",
    });
    errdefer direct_client.deinit();

    const session = try ActiveContextSession.adopt(
        allocator,
        io,
        1,
        .{
            .context_name = "readonly",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = true,
            .readonly = true,
        },
        .{
            .shared_event = &shared_event,
            .client = direct_client,
            .cluster_name = "cluster",
            .user_name = "user",
            .readiness_verified = true,
            .proxy_starter = ProxyStarter.init(&proxy_harness, ProxyHarness.start),
        },
    );

    try session.startProxy();
    try session.activateLocked();
    var lease = try session.acquireLocked(.list_watch, &shared_event);
    try std.testing.expectEqualStrings(
        "http://127.0.0.1:43124",
        (try lease.client()).api_server,
    );
    lease.release();
    session.invalidate();
    session.deinit();
    try std.testing.expectEqual(@as(usize, 1), proxy_harness.kills);
    try std.testing.expectEqual(@as(usize, 1), proxy_harness.deinits);
}

test "Task 15 readiness selects direct curl before proxy" {
    const Harness = struct {
        curl_calls: usize = 0,
        proxy_calls: usize = 0,

        fn curlReady(context: *anyopaque, _: *ActiveContextSession) anyerror!void {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.curl_calls += 1;
        }

        fn startProxy(context: *anyopaque, _: *ActiveContextSession) anyerror!ProxyOwner {
            const self: *@This() = @ptrCast(@alignCast(context));
            self.proxy_calls += 1;
            return error.ProxyMustNotStart;
        }
    };

    const allocator = std.testing.allocator;
    const io = std.testing.io;
    var shared_event: std.Io.Event = .unset;
    var harness = Harness{};
    const client = try allocator.create(klient.K8sClient);
    client.* = try klient.K8sClient.init(allocator, io, .{
        .server = "https://cluster.example.test",
        .token = "secret",
        .namespace = "default",
    });
    const session = try ActiveContextSession.adopt(
        allocator,
        io,
        7,
        .{
            .context_name = "dev4.as",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = true,
            .readonly = true,
        },
        .{
            .shared_event = &shared_event,
            .client = client,
            .cluster_name = "cluster",
            .user_name = "user",
            .direct_curl_allowed = true,
            .direct_curl_probe = DirectCurlProbe.init(&harness, Harness.curlReady),
            .proxy_starter = ProxyStarter.init(&harness, Harness.startProxy),
        },
    );
    try session.ensureReady();
    try std.testing.expectEqual(TransportMode.direct_curl, session.requestView().transport_mode);
    try std.testing.expectEqual(@as(usize, 1), harness.curl_calls);
    try std.testing.expectEqual(@as(usize, 0), harness.proxy_calls);

    try session.activateLocked();
    var lease = try session.acquireLocked(.list_watch, &shared_event);
    var canceled = std.atomic.Value(bool).init(false);
    const adapter = try lease.readTransport(io, &canceled);
    try std.testing.expectEqual(
        std.meta.Tag(read_transport.TransportAdapter).fallback,
        std.meta.activeTag(adapter),
    );
    lease.release();
    session.invalidate();
    session.deinit();
}
