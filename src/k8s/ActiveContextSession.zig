const std = @import("std");
const klient = @import("klient");

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
        const body = try session.client.request(.GET, "/version", null);
        session.allocator.free(body);
    }

    fn verify(self: ReadinessProbe, session: *ActiveContextSession) !void {
        try self.verify_fn(self.context, session);
    }
};

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

pub const FallbackProbe = struct {
    context: *anyopaque,
    verify_fn: *const fn (*anyopaque, *ActiveContextSession) anyerror!void,

    pub fn init(
        context: anytype,
        verify_fn: *const fn (*anyopaque, *ActiveContextSession) anyerror!void,
    ) FallbackProbe {
        return .{ .context = @ptrCast(context), .verify_fn = verify_fn };
    }

    pub fn production() FallbackProbe {
        return init(&probe_sentinel, productionVerify);
    }

    fn productionVerify(_: *anyopaque, session: *ActiveContextSession) anyerror!void {
        try session.verifyKubectlFallback();
    }

    fn verify(self: FallbackProbe, session: *ActiveContextSession) !void {
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
        return self.session.client;
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
        proxy: ?ProxyOwner = null,
        use_kubectl: bool = false,
        readiness: ReadinessProbe = ReadinessProbe.clientVersion(),
        readiness_verified: bool = false,
        observer: ?LifecycleObserver = null,
        proxy_starter: ?ProxyStarter = null,
        fallback_probe: FallbackProbe = FallbackProbe.production(),
    };

    allocator: std.mem.Allocator,
    io: std.Io,
    shared_event: *std.Io.Event,
    generation: Generation,
    spec: ContextSpec,
    cluster_name: []const u8,
    user_name: []const u8,
    client: *klient.K8sClient,
    credential_provider: CredentialProvider,
    proxy: ?ProxyOwner,
    use_kubectl: bool,
    readiness: ReadinessProbe,
    readiness_verified: bool,
    fallback_attempted: bool = false,
    observer: ?LifecycleObserver,
    proxy_starter: ?ProxyStarter,
    fallback_probe: FallbackProbe,
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
            .credential_provider = options.credential_provider orelse CredentialProvider.empty(allocator),
            .proxy = options.proxy,
            .use_kubectl = options.use_kubectl or options.proxy != null,
            .readiness = options.readiness,
            .readiness_verified = options.readiness_verified,
            .observer = options.observer,
            .proxy_starter = options.proxy_starter,
            .fallback_probe = options.fallback_probe,
            .proxy_state = if (options.proxy != null) .ready else .stopped,
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
        if (user.exec) |exec_config| {
            const command = exec_config.command orelse return error.ExecCommandMissing;
            const api_version = exec_config.api_version orelse
                "client.authentication.k8s.io/v1beta1";
            try credentials.setExecConfig(command, exec_config.args, api_version);
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
            .use_kubectl = force_proxy,
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
                self.startProxy() catch return self.verifyFallbackOnce();
                return self.markReady();
            };
            return self.markReady();
        }

        self.startProxy() catch return self.verifyFallbackOnce();
        return self.markReady();
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
            self.use_kubectl = true;
            self.proxy_condition.broadcast(self.io);
            self.mutex.unlock(self.io);
            return err;
        };

        self.mutex.lockUncancelable(self.io);
        if (self.state.load(.acquire) == .invalidated) {
            self.mutex.unlock(self.io);
            proxy.kill(self.io);
            proxy.deinit(self.allocator);
            self.mutex.lockUncancelable(self.io);
            self.proxy_state = .failed;
            self.proxy_condition.broadcast(self.io);
            self.mutex.unlock(self.io);
            return error.SessionInvalidated;
        }
        std.debug.assert(self.proxy == null);
        self.proxy = proxy;
        self.proxy_state = .ready;
        self.use_kubectl = true;
        self.proxy_condition.broadcast(self.io);
        self.mutex.unlock(self.io);
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
        self.proxy = null;
        self.proxy_state = .stopped;
        self.mutex.unlock(self.io);

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

    fn markReady(self: *ActiveContextSession) !void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);
        const current_state = self.state.load(.acquire);
        if (current_state == .invalidated or current_state == .teardown_ready) {
            return error.SessionInvalidated;
        }
        self.readiness_verified = true;
    }

    fn verifyFallbackOnce(self: *ActiveContextSession) !void {
        self.mutex.lockUncancelable(self.io);
        if (self.readiness_verified) {
            self.mutex.unlock(self.io);
            return;
        }
        if (self.fallback_attempted) {
            self.mutex.unlock(self.io);
            return error.ReadinessFailed;
        }
        self.fallback_attempted = true;
        self.use_kubectl = true;
        self.mutex.unlock(self.io);

        try self.fallback_probe.verify(self);
        try self.markReady();
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

    fn verifyKubectlFallback(self: *ActiveContextSession) !void {
        var argv: std.ArrayListUnmanaged([]const u8) = .empty;
        defer argv.deinit(self.allocator);
        try argv.append(self.allocator, "kubectl");
        if (self.spec.kubeconfig_path) |path| {
            try argv.append(self.allocator, "--kubeconfig");
            try argv.append(self.allocator, path);
        }
        try argv.append(self.allocator, "--context");
        try argv.append(self.allocator, self.spec.context_name);
        try argv.append(self.allocator, "get");
        try argv.append(self.allocator, "--raw");
        try argv.append(self.allocator, "/version");
        const result = try std.process.run(self.allocator, self.io, .{
            .argv = argv.items,
            .stdout_limit = .limited(1024 * 1024),
            .stderr_limit = .limited(1024 * 1024),
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        if (result.term != .exited or result.term.exited != 0) {
            return error.ReadinessFailed;
        }
    }

    fn startProxyOwned(self: *ActiveContextSession) !ProxyOwner {
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
        const ready = try std.process.run(self.allocator, self.io, .{
            .argv = &.{
                "curl",
                "-sf",
                "--retry",
                "10",
                "--retry-connrefused",
                "--retry-delay",
                "0",
                "--max-time",
                "5",
                url,
            },
            .stdout_limit = .limited(1024 * 1024),
        });
        defer self.allocator.free(ready.stdout);
        defer self.allocator.free(ready.stderr);
        if (ready.term != .exited or ready.term.exited != 0) {
            return error.ProxyNotReady;
        }

        const proxy = try ProxyOwner.fromChild(self.allocator, child, port);
        child_owned = false;
        return proxy;
    }

    fn emit(self: *ActiveContextSession, event: LifecycleEvent) void {
        if (self.observer) |observer| observer.emit(event);
    }
};
