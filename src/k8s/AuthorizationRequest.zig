const std = @import("std");

const keys = @import("ResourceKey.zig");
const lifecycle = @import("LifecycleInbox.zig");
const K8sService = @import("../services/K8sService.zig").K8sService;
const AuthorizationView = @import("../view/AuthorizationView.zig").AuthorizationView;
const access = @import("../view/auth_access_tab.zig");
const policy = @import("../view/auth_policy_tab.zig");
const condition = @import("../view/auth_condition_tab.zig");

pub const AuthorizationPayload = struct {
    generation: keys.Generation,
    subscription_id: keys.SubscriptionId,
    serial: u64,
    result: Result,

    pub const AccessResult = struct {
        rows: []access.AccessRow,
        conditional_auth_available: bool,
        transferred: bool = false,
    };
    pub const PolicyResult = struct {
        rows: []policy.PolicyRow,
        cedar_available: bool,
        transferred: bool = false,
    };
    pub const ConditionsResult = struct {
        resource: []u8,
        rows: []condition.ConditionRow,
        transferred: bool = false,
    };
    pub const FailureResult = struct {
        tab: AuthorizationView.Tab,
        message: []u8,
    };
    pub const Result = union(enum) {
        access_review: AccessResult,
        policies: PolicyResult,
        conditions: ConditionsResult,
        failure: FailureResult,
    };
};

pub const UiTarget = struct {
    view: *AuthorizationView,
};

pub const Backend = struct {
    context: *anyopaque,
    isConnectedFn: *const fn (*anyopaque) bool,
    checkAccessFn: *const fn (*anyopaque, []const u8, []const u8, []const u8, []const u8) anyerror!K8sService.AccessCheckResult,
    detectConditionalFn: *const fn (*anyopaque) anyerror!bool,
    listRbacFn: *const fn (*anyopaque) anyerror![]K8sService.PolicyInfo,
    detectCedarFn: *const fn (*anyopaque) anyerror!bool,
    listCedarFn: *const fn (*anyopaque) anyerror![]K8sService.PolicyInfo,
    conditionsFn: *const fn (*anyopaque, []const u8, []const u8, []const u8) anyerror![]K8sService.ConditionInfo,

    pub fn fromService(service: *K8sService) Backend {
        const Adapter = struct {
            fn connected(raw: *anyopaque) bool {
                const value: *K8sService = @ptrCast(@alignCast(raw));
                return value.isConnected();
            }
            fn check(raw: *anyopaque, verb: []const u8, group: []const u8, resource: []const u8, namespace: []const u8) !K8sService.AccessCheckResult {
                const value: *K8sService = @ptrCast(@alignCast(raw));
                return value.checkAccess(verb, group, resource, namespace);
            }
            fn conditional(raw: *anyopaque) !bool {
                const value: *K8sService = @ptrCast(@alignCast(raw));
                return value.detectConditionalAuth();
            }
            fn rbac(raw: *anyopaque) ![]K8sService.PolicyInfo {
                const value: *K8sService = @ptrCast(@alignCast(raw));
                return value.listRBACPolicies();
            }
            fn cedarAvailable(raw: *anyopaque) !bool {
                const value: *K8sService = @ptrCast(@alignCast(raw));
                return value.detectCedarAuth();
            }
            fn cedar(raw: *anyopaque) ![]K8sService.PolicyInfo {
                const value: *K8sService = @ptrCast(@alignCast(raw));
                return value.listCedarPolicies();
            }
            fn conditions(raw: *anyopaque, resource: []const u8, group: []const u8, namespace: []const u8) ![]K8sService.ConditionInfo {
                const value: *K8sService = @ptrCast(@alignCast(raw));
                return value.getAuthorizationConditions(resource, group, namespace);
            }
        };
        return .{
            .context = service,
            .isConnectedFn = Adapter.connected,
            .checkAccessFn = Adapter.check,
            .detectConditionalFn = Adapter.conditional,
            .listRbacFn = Adapter.rbac,
            .detectCedarFn = Adapter.cedarAvailable,
            .listCedarFn = Adapter.cedar,
            .conditionsFn = Adapter.conditions,
        };
    }

    fn isConnected(self: Backend) bool {
        return self.isConnectedFn(self.context);
    }
};

pub const Options = struct {
    serial: u64,
    tab: AuthorizationView.Tab,
    service: *K8sService,
    namespace: []const u8,
    resource: []const u8 = "",
    group: []const u8 = "",
    conditional_auth_available: ?bool = null,
    cedar_available: ?bool = null,
    backend_override: ?Backend = null,
};

const Spec = struct {
    serial: u64,
    tab: AuthorizationView.Tab,
    service: *K8sService,
    namespace: []u8,
    resource: []u8,
    group: []u8,
    conditional_auth_available: ?bool,
    cedar_available: ?bool,
    backend: Backend,
    generation: keys.Generation = 0,
    subscription_id: keys.SubscriptionId = 0,

    fn bind(raw: ?*anyopaque, generation: keys.Generation, subscription_id: keys.SubscriptionId) void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        self.generation = generation;
        self.subscription_id = subscription_id;
    }

    fn run(raw: ?*anyopaque, control: *lifecycle.ChildControl, _: std.Io) anyerror!void {
        const self: *Spec = @ptrCast(@alignCast(raw.?));
        const lease = control.lease orelse return error.MissingLease;
        if (lease.purpose != .authorization) return error.InvalidLeasePurpose;

        const payload = try control.allocator.create(AuthorizationPayload);
        var payload_initialized = false;
        var payload_owned = true;
        errdefer {
            if (payload_owned) {
                if (payload_initialized) payloadDeinit(payload, control.allocator);
                control.allocator.destroy(payload);
            }
        }
        const result = self.build(control.allocator) catch |err|
            AuthorizationPayload.Result{ .failure = .{
                .tab = self.tab,
                .message = try failureMessage(control.allocator, err),
            } };
        payload.* = .{
            .generation = self.generation,
            .subscription_id = self.subscription_id,
            .serial = self.serial,
            .result = result,
        };
        payload_initialized = true;
        const key = keys.RequestKey{
            .generation = self.generation,
            .subscription_id = self.subscription_id,
        };
        var envelope = try keys.erasePayload(
            AuthorizationPayload,
            control.allocator,
            .{ .authorization = key },
            payload,
            &payload_handler,
            self.generation,
            self.subscription_id,
            self.serial,
            payloadBytes(payload),
            null,
        );
        payload_initialized = false;
        payload_owned = false;
        const outcome = try control.publishDelivery(envelope);
        if (outcome == .abandoned) return;
        envelope = undefined;
        control.finish(.{ .request_finished = .{ .key = key } });
    }

    fn build(self: *Spec, allocator: std.mem.Allocator) !AuthorizationPayload.Result {
        if (!self.backend.isConnected()) return error.NotConnected;
        return switch (self.tab) {
            .access_review => .{ .access_review = try buildAccess(
                allocator,
                self.backend,
                self.namespace,
                self.conditional_auth_available,
            ) },
            .policy_browser => .{ .policies = try buildPolicies(
                allocator,
                self.service,
                self.backend,
                self.cedar_available,
            ) },
            .condition_inspector => .{ .conditions = try buildConditions(
                allocator,
                self.service,
                self.backend,
                self.resource,
                self.group,
                self.namespace,
                self.conditional_auth_available,
            ) },
        };
    }

    fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
        const self: *Spec = @ptrCast(@alignCast(raw orelse return));
        allocator.free(self.namespace);
        allocator.free(self.resource);
        allocator.free(self.group);
        allocator.destroy(self);
    }
};

pub fn ownedTaskSpec(allocator: std.mem.Allocator, options: Options) !lifecycle.OwnedTaskSpec {
    const spec = try allocator.create(Spec);
    errdefer allocator.destroy(spec);
    spec.* = .{
        .serial = options.serial,
        .tab = options.tab,
        .service = options.service,
        .namespace = try allocator.dupe(u8, options.namespace),
        .resource = undefined,
        .group = undefined,
        .conditional_auth_available = options.conditional_auth_available,
        .cedar_available = options.cedar_available,
        .backend = options.backend_override orelse Backend.fromService(options.service),
    };
    errdefer allocator.free(spec.namespace);
    spec.resource = try allocator.dupe(u8, options.resource);
    errdefer allocator.free(spec.resource);
    spec.group = try allocator.dupe(u8, options.group);
    return .{
        .ptr = spec,
        .alignment = .of(Spec),
        .owned_bytes = @sizeOf(Spec) + spec.namespace.len + spec.resource.len + spec.group.len,
        .lease_purpose = .authorization,
        .bindFn = Spec.bind,
        .runFn = Spec.run,
        .deinitFn = Spec.deinit,
    };
}

const verbs = [_][]const u8{ "get", "list", "create", "update", "delete", "watch" };

fn buildAccess(
    allocator: std.mem.Allocator,
    backend: Backend,
    namespace: []const u8,
    known_conditional: ?bool,
) !AuthorizationPayload.AccessResult {
    const conditional_available = known_conditional orelse
        (backend.detectConditionalFn(backend.context) catch false);
    var rows = std.ArrayListUnmanaged(access.AccessRow).empty;
    errdefer {
        for (rows.items) |*row| row.deinit();
        rows.deinit(allocator);
    }
    try rows.ensureTotalCapacity(allocator, access.core_resources.len);
    for (access.core_resources) |resource| {
        var row = access.AccessRow{
            .resource = try allocator.dupe(u8, resource.resource),
            .group = try allocator.dupe(u8, resource.group),
            .allocator = allocator,
        };
        errdefer row.deinit();
        for (verbs, 0..) |verb, index| {
            const checked = backend.checkAccessFn(backend.context, verb, resource.group, resource.resource, namespace) catch
                continue;
            const status: access.AccessStatus = if (checked.conditional)
                .conditional
            else if (checked.allowed)
                .allowed
            else
                .denied;
            switch (index) {
                0 => row.get = status,
                1 => row.list = status,
                2 => row.create = status,
                3 => row.update = status,
                4 => row.delete = status,
                5 => row.watch = status,
                else => unreachable,
            }
            if (checked.condition_count > 0) {
                row.condition_count = (row.condition_count orelse 0) + checked.condition_count;
            }
        }
        if (!conditional_available) row.condition_count = null;
        rows.appendAssumeCapacity(row);
    }
    return .{
        .rows = try rows.toOwnedSlice(allocator),
        .conditional_auth_available = conditional_available,
    };
}

fn buildPolicies(
    allocator: std.mem.Allocator,
    service: *K8sService,
    backend: Backend,
    known_cedar: ?bool,
) !AuthorizationPayload.PolicyResult {
    const rbac = try backend.listRbacFn(backend.context);
    defer {
        for (rbac) |*item| item.deinit();
        service.allocator.free(rbac);
    }
    const cedar_available = known_cedar orelse (backend.detectCedarFn(backend.context) catch false);
    const cedar: []K8sService.PolicyInfo = if (cedar_available)
        try backend.listCedarFn(backend.context)
    else
        @constCast(&.{});
    defer if (cedar_available) {
        for (cedar) |*item| item.deinit();
        service.allocator.free(cedar);
    };

    var rows = std.ArrayListUnmanaged(policy.PolicyRow).empty;
    errdefer {
        for (rows.items) |*row| row.deinit();
        rows.deinit(allocator);
    }
    try rows.ensureTotalCapacity(allocator, rbac.len + cedar.len);
    for (rbac) |item| try appendPolicy(allocator, &rows, item, .rbac);
    for (cedar) |item| try appendPolicy(allocator, &rows, item, .cedar);
    return .{
        .rows = try rows.toOwnedSlice(allocator),
        .cedar_available = cedar_available,
    };
}

fn appendPolicy(
    allocator: std.mem.Allocator,
    rows: *std.ArrayListUnmanaged(policy.PolicyRow),
    item: K8sService.PolicyInfo,
    kind: policy.PolicyRow.PolicyType,
) !void {
    var row = policy.PolicyRow{
        .source = try allocator.dupe(u8, item.source),
        .policy_type = kind,
        .resource = undefined,
        .verbs = undefined,
        .subjects = undefined,
        .allocator = allocator,
    };
    errdefer allocator.free(row.source);
    row.resource = try allocator.dupe(u8, item.resource);
    errdefer allocator.free(row.resource);
    row.verbs = try allocator.dupe(u8, item.verbs);
    errdefer allocator.free(row.verbs);
    row.subjects = try allocator.dupe(u8, item.subjects);
    rows.appendAssumeCapacity(row);
}

fn buildConditions(
    allocator: std.mem.Allocator,
    service: *K8sService,
    backend: Backend,
    resource: []const u8,
    group: []const u8,
    namespace: []const u8,
    conditional_available: ?bool,
) !AuthorizationPayload.ConditionsResult {
    if (conditional_available != null and !conditional_available.?)
        return error.ConditionalAuthorizationUnavailable;
    const source = try backend.conditionsFn(backend.context, resource, group, namespace);
    defer {
        for (source) |*item| item.deinit();
        service.allocator.free(source);
    }
    var rows = std.ArrayListUnmanaged(condition.ConditionRow).empty;
    errdefer {
        for (rows.items) |*row| row.deinit();
        rows.deinit(allocator);
    }
    try rows.ensureTotalCapacity(allocator, source.len);
    for (source, 0..) |item, index| {
        var row = condition.ConditionRow{
            .index = @intCast(index + 1),
            .effect = try allocator.dupe(u8, item.effect),
            .authorizer = undefined,
            .expression = undefined,
            .description = undefined,
            .allocator = allocator,
        };
        errdefer allocator.free(row.effect);
        row.authorizer = try allocator.dupe(u8, item.authorizer);
        errdefer allocator.free(row.authorizer);
        row.expression = try allocator.dupe(u8, item.expression);
        errdefer allocator.free(row.expression);
        row.description = try allocator.dupe(u8, item.description);
        rows.appendAssumeCapacity(row);
    }
    return .{
        .resource = try allocator.dupe(u8, resource),
        .rows = try rows.toOwnedSlice(allocator),
    };
}

fn failureMessage(allocator: std.mem.Allocator, err: anyerror) ![]u8 {
    return allocator.dupe(u8, switch (err) {
        error.NotConnected => "Not connected to Kubernetes cluster",
        error.ConditionalAuthorizationUnavailable => "Conditional Authorization (KEP 5681) is not available on this cluster.",
        else => @errorName(err),
    });
}

const Prepared = struct {
    error_message: ?[]u8 = null,
};

fn payloadPreflight(
    payload: *AuthorizationPayload,
    router: *keys.UiRouter,
    allocator: std.mem.Allocator,
) anyerror!keys.ApplyPlan {
    const key = keys.RequestKey{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    };
    const raw = router.target(.{ .authorization = key }) orelse return error.StaleAuthorizationTarget;
    const target: *UiTarget = @ptrCast(@alignCast(raw));
    const tab = resultTab(payload.result);
    const active = target.view.activeKey(tab).* orelse return error.StaleAuthorizationTarget;
    if (!active.eql(key) or target.view.activeSerial(tab) != payload.serial)
        return error.StaleAuthorizationTarget;

    switch (payload.result) {
        .access_review => |value| {
            try target.view.access_tab.table.items.ensureTotalCapacity(allocator, value.rows.len);
            try target.view.access_tab.table.filtered_indices.ensureTotalCapacity(allocator, value.rows.len);
        },
        .policies => |value| {
            try target.view.policy_tab.table.items.ensureTotalCapacity(allocator, value.rows.len);
            try target.view.policy_tab.table.filtered_indices.ensureTotalCapacity(allocator, value.rows.len);
        },
        .conditions => |value| {
            try target.view.condition_tab.table.items.ensureTotalCapacity(allocator, value.rows.len);
            try target.view.condition_tab.table.filtered_indices.ensureTotalCapacity(allocator, value.rows.len);
        },
        .failure => |value| {
            const prepared = try allocator.create(Prepared);
            errdefer allocator.destroy(prepared);
            prepared.* = .{ .error_message = try allocator.dupe(u8, value.message) };
            return .{
                .scratch = prepared,
                .scratch_alignment = .of(Prepared),
                .deinitFn = preparedDeinit,
            };
        },
    }
    return .{};
}

fn payloadCommit(
    payload: *AuthorizationPayload,
    router: *keys.UiRouter,
    plan: *keys.ApplyPlan,
) void {
    const key = keys.RequestKey{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    };
    const raw = router.target(.{ .authorization = key }) orelse return;
    const target: *UiTarget = @ptrCast(@alignCast(raw));
    const tab = resultTab(payload.result);
    const active = target.view.activeKey(tab).* orelse return;
    if (!active.eql(key) or target.view.activeSerial(tab) != payload.serial) return;

    if (target.view.error_message) |message| target.view.allocator.free(message);
    target.view.error_message = null;
    switch (payload.result) {
        .access_review => |*value| {
            replaceAccessRows(target.view, value.rows);
            value.transferred = true;
            target.view.access_tab.conditional_auth_available = value.conditional_auth_available;
        },
        .policies => |*value| {
            replacePolicyRows(target.view, value.rows);
            value.transferred = true;
            target.view.policy_tab.cedar_available = value.cedar_available;
        },
        .conditions => |*value| {
            replaceConditionRows(target.view, value.resource, value.rows);
            value.transferred = true;
        },
        .failure => {
            const prepared: *Prepared = @ptrCast(@alignCast(plan.scratch.?));
            target.view.error_message = prepared.error_message;
            prepared.error_message = null;
            clearTab(target.view, tab);
        },
    }
    target.view.loading = target.view.hasActiveRequestExcept(tab);
}

fn replaceAccessRows(view: *AuthorizationView, rows: []access.AccessRow) void {
    const selected = view.access_tab.table.selected_row;
    view.access_tab.table.clearItems();
    for (rows) |row| view.access_tab.table.items.appendAssumeCapacity(row);
    for (view.access_tab.table.items.items, 0..) |*row, index| {
        if (access.AccessReviewTab.accessMatchFn(row, view.access_tab.table.filter_text))
            view.access_tab.table.filtered_indices.appendAssumeCapacity(index);
    }
    clampSelection(&view.access_tab.table.selected_row, selected, view.access_tab.table.filtered_indices.items.len);
}

fn replacePolicyRows(view: *AuthorizationView, rows: []policy.PolicyRow) void {
    const selected = view.policy_tab.table.selected_row;
    view.policy_tab.table.clearItems();
    for (rows) |row| view.policy_tab.table.items.appendAssumeCapacity(row);
    for (view.policy_tab.table.items.items, 0..) |*row, index| {
        if (policy.PolicyBrowserTab.policyMatchFn(row, view.policy_tab.table.filter_text))
            view.policy_tab.table.filtered_indices.appendAssumeCapacity(index);
    }
    clampSelection(&view.policy_tab.table.selected_row, selected, view.policy_tab.table.filtered_indices.items.len);
}

fn replaceConditionRows(view: *AuthorizationView, resource: []u8, rows: []condition.ConditionRow) void {
    const selected = view.condition_tab.table.selected_row;
    view.condition_tab.table.clearItems();
    for (rows) |row| view.condition_tab.table.items.appendAssumeCapacity(row);
    for (view.condition_tab.table.items.items, 0..) |_, index|
        view.condition_tab.table.filtered_indices.appendAssumeCapacity(index);
    clampSelection(&view.condition_tab.table.selected_row, selected, view.condition_tab.table.filtered_indices.items.len);
    if (view.condition_tab.condition_resource) |old| view.allocator.free(old);
    view.condition_tab.condition_resource = resource;
}

fn clampSelection(selected: *u32, previous: u32, count: usize) void {
    selected.* = if (count == 0) 0 else @min(previous, @as(u32, @intCast(count - 1)));
}

fn clearTab(view: *AuthorizationView, tab: AuthorizationView.Tab) void {
    switch (tab) {
        .access_review => view.access_tab.table.clearItems(),
        .policy_browser => view.policy_tab.table.clearItems(),
        .condition_inspector => view.condition_tab.table.clearItems(),
    }
}

fn resultTab(result: AuthorizationPayload.Result) AuthorizationView.Tab {
    return switch (result) {
        .access_review => .access_review,
        .policies => .policy_browser,
        .conditions => .condition_inspector,
        .failure => |value| value.tab,
    };
}

fn preparedDeinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
    const prepared: *Prepared = @ptrCast(@alignCast(raw orelse return));
    if (prepared.error_message) |message| allocator.free(message);
    allocator.destroy(prepared);
}

fn payloadDeinit(payload: *AuthorizationPayload, allocator: std.mem.Allocator) void {
    switch (payload.result) {
        .access_review => |value| {
            if (!value.transferred) for (value.rows) |*row| row.deinit();
            allocator.free(value.rows);
        },
        .policies => |value| {
            if (!value.transferred) for (value.rows) |*row| row.deinit();
            allocator.free(value.rows);
        },
        .conditions => |value| {
            if (!value.transferred) {
                allocator.free(value.resource);
                for (value.rows) |*row| row.deinit();
            }
            allocator.free(value.rows);
        },
        .failure => |value| allocator.free(value.message),
    }
}

fn payloadBytes(payload: *const AuthorizationPayload) usize {
    return @sizeOf(AuthorizationPayload) + switch (payload.result) {
        .access_review => |value| value.rows.len * @sizeOf(access.AccessRow),
        .policies => |value| value.rows.len * @sizeOf(policy.PolicyRow),
        .conditions => |value| value.resource.len + value.rows.len * @sizeOf(condition.ConditionRow),
        .failure => |value| value.message.len,
    };
}

pub const payload_handler = keys.PayloadHandler(AuthorizationPayload){
    .preflight = payloadPreflight,
    .commit = payloadCommit,
    .deinit = payloadDeinit,
};

test "authorization request has no read transport dependency and fixed matrix shape" {
    try std.testing.expectEqual(@as(usize, 8), access.core_resources.len);
    try std.testing.expectEqual(@as(usize, 6), verbs.len);
}

pub fn runTask14AuthorizationUnknownGate() !void {
    const Fake = struct {
        calls: usize = 0,

        fn connected(_: *anyopaque) bool {
            return true;
        }
        fn check(raw: *anyopaque, _: []const u8, _: []const u8, _: []const u8, _: []const u8) !K8sService.AccessCheckResult {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            if (self.calls % 7 == 0) return error.ScriptedFailure;
            return .{ .allowed = true, .conditional = false, .condition_count = 0 };
        }
        fn conditional(_: *anyopaque) !bool {
            return true;
        }
        fn policies(_: *anyopaque) ![]K8sService.PolicyInfo {
            return error.Unused;
        }
        fn cedar(_: *anyopaque) !bool {
            return false;
        }
        fn conditions(_: *anyopaque, _: []const u8, _: []const u8, _: []const u8) ![]K8sService.ConditionInfo {
            return error.Unused;
        }
    };
    var fake = Fake{};
    const backend = Backend{
        .context = &fake,
        .isConnectedFn = Fake.connected,
        .checkAccessFn = Fake.check,
        .detectConditionalFn = Fake.conditional,
        .listRbacFn = Fake.policies,
        .detectCedarFn = Fake.cedar,
        .listCedarFn = Fake.policies,
        .conditionsFn = Fake.conditions,
    };
    const result = try buildAccess(std.testing.allocator, backend, "default", null);
    defer {
        for (result.rows) |*row| row.deinit();
        std.testing.allocator.free(result.rows);
    }
    try std.testing.expectEqual(@as(usize, 48), fake.calls);
    var unknown: usize = 0;
    for (result.rows) |row| {
        inline for (.{ row.get, row.list, row.create, row.update, row.delete, row.watch }) |status| {
            if (status == .unknown) unknown += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 6), unknown);
}

test "access builder performs 48 checks and preserves unknown on error" {
    try runTask14AuthorizationUnknownGate();
}

pub fn runTask14AuthorizationIdentityGate() !void {
    const theme_loader = @import("../model/theme_loader.zig");
    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    var service = try K8sService.init(std.testing.allocator);
    defer service.deinit();
    var view = try AuthorizationView.init(std.testing.allocator, &theme, &service);
    defer view.deinit();
    var target = UiTarget{ .view = &view };
    const Route = struct {
        fn route(raw: *anyopaque, value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *UiTarget = @ptrCast(@alignCast(raw));
            const key = keys.requestKey(value) orelse return null;
            inline for (.{ AuthorizationView.Tab.access_review, .policy_browser, .condition_inspector }) |tab| {
                if (self.view.activeKey(tab).*) |active| {
                    if (active.eql(key)) return raw;
                }
            }
            return null;
        }
    };
    var router = keys.UiRouter{ .context = &target, .targetFn = Route.route };
    const key = keys.RequestKey{ .generation = 7, .subscription_id = 11 };

    view.access_tab.active_key = key;
    view.access_tab.active_serial = 2;
    view.loading = true;
    try view.access_tab.applyFilter("pods");
    const access_rows = try std.testing.allocator.alloc(access.AccessRow, access.core_resources.len);
    for (access_rows, access.core_resources) |*row, resource| {
        row.* = .{
            .resource = try std.testing.allocator.dupe(u8, resource.resource),
            .group = try std.testing.allocator.dupe(u8, resource.group),
            .get = .allowed,
            .list = .denied,
            .create = .conditional,
            .update = .unknown,
            .delete = .allowed,
            .watch = .denied,
            .condition_count = 1,
            .allocator = std.testing.allocator,
        };
    }
    const access_payload = try std.testing.allocator.create(AuthorizationPayload);
    access_payload.* = .{
        .generation = key.generation,
        .subscription_id = key.subscription_id,
        .serial = 2,
        .result = .{ .access_review = .{
            .rows = access_rows,
            .conditional_auth_available = true,
        } },
    };
    var access_envelope = try keys.erasePayload(
        AuthorizationPayload,
        std.testing.allocator,
        .{ .authorization = key },
        access_payload,
        &payload_handler,
        key.generation,
        key.subscription_id,
        2,
        payloadBytes(access_payload),
        null,
    );
    try access_envelope.apply(&router, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 8), view.access_tab.table.items.items.len);
    try std.testing.expectEqual(@as(usize, 1), view.access_tab.table.filtered_indices.items.len);
    for (view.access_tab.table.items.items) |row| {
        try std.testing.expectEqual(access.AccessStatus.allowed, row.get);
        try std.testing.expectEqual(access.AccessStatus.denied, row.list);
        try std.testing.expectEqual(access.AccessStatus.conditional, row.create);
        try std.testing.expectEqual(access.AccessStatus.unknown, row.update);
        try std.testing.expectEqual(access.AccessStatus.allowed, row.delete);
        try std.testing.expectEqual(access.AccessStatus.denied, row.watch);
    }

    view.policy_tab.active_key = key;
    view.policy_tab.active_serial = 3;
    const policy_rows = try std.testing.allocator.alloc(policy.PolicyRow, 1);
    policy_rows[0] = .{
        .source = try std.testing.allocator.dupe(u8, "reader"),
        .policy_type = .rbac,
        .resource = try std.testing.allocator.dupe(u8, "pods"),
        .verbs = try std.testing.allocator.dupe(u8, "get,list"),
        .subjects = try std.testing.allocator.dupe(u8, "team-a"),
        .allocator = std.testing.allocator,
    };
    const policy_payload = try std.testing.allocator.create(AuthorizationPayload);
    policy_payload.* = .{
        .generation = key.generation,
        .subscription_id = key.subscription_id,
        .serial = 3,
        .result = .{ .policies = .{
            .rows = policy_rows,
            .cedar_available = false,
        } },
    };
    var policy_envelope = try keys.erasePayload(
        AuthorizationPayload,
        std.testing.allocator,
        .{ .authorization = key },
        policy_payload,
        &payload_handler,
        key.generation,
        key.subscription_id,
        3,
        payloadBytes(policy_payload),
        null,
    );
    try policy_envelope.apply(&router, std.testing.allocator);
    try std.testing.expectEqualStrings("reader", view.policy_tab.table.items.items[0].source);

    view.condition_tab.active_key = key;
    view.condition_tab.active_serial = 4;
    const condition_rows = try std.testing.allocator.alloc(condition.ConditionRow, 1);
    condition_rows[0] = .{
        .index = 1,
        .effect = try std.testing.allocator.dupe(u8, "Deny"),
        .authorizer = try std.testing.allocator.dupe(u8, "webhook"),
        .expression = try std.testing.allocator.dupe(u8, "request.user == 'bad'"),
        .description = try std.testing.allocator.dupe(u8, "blocked"),
        .allocator = std.testing.allocator,
    };
    const condition_payload = try std.testing.allocator.create(AuthorizationPayload);
    condition_payload.* = .{
        .generation = key.generation,
        .subscription_id = key.subscription_id,
        .serial = 4,
        .result = .{ .conditions = .{
            .resource = try std.testing.allocator.dupe(u8, "pods"),
            .rows = condition_rows,
        } },
    };
    var condition_envelope = try keys.erasePayload(
        AuthorizationPayload,
        std.testing.allocator,
        .{ .authorization = key },
        condition_payload,
        &payload_handler,
        key.generation,
        key.subscription_id,
        4,
        payloadBytes(condition_payload),
        null,
    );
    try condition_envelope.apply(&router, std.testing.allocator);
    try std.testing.expectEqualStrings("pods", view.condition_tab.condition_resource.?);
    try std.testing.expectEqualStrings("blocked", view.condition_tab.table.items.items[0].description);

    const stale = try std.testing.allocator.create(AuthorizationPayload);
    stale.* = .{
        .generation = key.generation,
        .subscription_id = key.subscription_id,
        .serial = 3,
        .result = .{ .failure = .{
            .tab = .condition_inspector,
            .message = try std.testing.allocator.dupe(u8, "stale"),
        } },
    };
    var stale_envelope = try keys.erasePayload(
        AuthorizationPayload,
        std.testing.allocator,
        .{ .authorization = key },
        stale,
        &payload_handler,
        key.generation,
        key.subscription_id,
        3,
        payloadBytes(stale),
        null,
    );
    try std.testing.expectError(
        error.StaleAuthorizationTarget,
        stale_envelope.apply(&router, std.testing.allocator),
    );
    stale_envelope.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("blocked", view.condition_tab.table.items.items[0].description);
}

test "authorization envelopes replace all real tab tables and fence stale serials" {
    try runTask14AuthorizationIdentityGate();
}

pub fn runTask14AuthorizationGate() !void {
    const klient = @import("klient");
    const runtime = @import("../core/runtime.zig");
    const slot_mod = @import("ActiveSessionSlot.zig");
    const session_mod = @import("ActiveContextSession.zig");
    const supervisor_mod = @import("LifecycleSupervisor.zig");
    const queue_mod = @import("ChangeQueue.zig");
    const plane_mod = @import("DataPlane.zig");
    const ancillary_mod = @import("AncillaryRequests.zig");
    const theme_loader = @import("../model/theme_loader.zig");

    const Fake = struct {
        calls: usize = 0,
        fn connected(_: *anyopaque) bool {
            return true;
        }
        fn check(raw: *anyopaque, _: []const u8, _: []const u8, _: []const u8, _: []const u8) !K8sService.AccessCheckResult {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.calls += 1;
            return .{ .allowed = true, .conditional = false, .condition_count = 0 };
        }
        fn conditional(_: *anyopaque) !bool {
            return true;
        }
        fn policies(_: *anyopaque) ![]K8sService.PolicyInfo {
            return error.Unused;
        }
        fn cedar(_: *anyopaque) !bool {
            return false;
        }
        fn conditions(_: *anyopaque, _: []const u8, _: []const u8, _: []const u8) ![]K8sService.ConditionInfo {
            return error.Unused;
        }
    };

    const io = runtime.io();
    var event: std.Io.Event = .unset;
    var inbox = lifecycle.LifecycleInbox.init(io, &event);
    defer inbox.deinit(std.testing.allocator);
    var cancellations = lifecycle.CancellationIntents.init();
    var slot = slot_mod.ActiveSessionSlot.init(io, &event);
    defer slot.deinit();
    var queue = queue_mod.ChangeQueue.init(io, std.testing.allocator, keys.Limits.default, &event, null);
    defer queue.deinit();
    const client = try std.testing.allocator.create(klient.K8sClient);
    client.* = try klient.K8sClient.init(std.testing.allocator, io, .{
        .server = "http://127.0.0.1",
        .namespace = "default",
    });
    const active_session = try session_mod.ActiveContextSession.adopt(
        std.testing.allocator,
        io,
        1,
        .{
            .context_name = "test",
            .kubeconfig_path = null,
            .default_namespace = "default",
            .force_proxy = false,
            .readonly = true,
        },
        .{
            .shared_event = &event,
            .client = client,
            .cluster_name = "cluster",
            .user_name = "user",
            .readiness_verified = true,
        },
    );
    _ = try slot.commit(active_session);
    var supervisor = try supervisor_mod.LifecycleSupervisor.init(
        std.testing.allocator,
        io,
        &event,
        &inbox,
        &cancellations,
        &slot,
        &queue,
        session_mod.SessionFactory.production(),
        active_session,
    );
    var producer = lifecycle.LifecycleProducer.init(&inbox, &cancellations, std.testing.allocator);
    var plane = plane_mod.DataPlane.init(std.testing.allocator, producer, &queue);
    var requests = ancillary_mod.AncillaryRequests.init(std.testing.allocator, producer, &queue);
    defer requests.deinit();
    var service = try K8sService.init(std.testing.allocator);
    defer service.deinit();
    var fake = Fake{};
    const backend = Backend{
        .context = &fake,
        .isConnectedFn = Fake.connected,
        .checkAccessFn = Fake.check,
        .detectConditionalFn = Fake.conditional,
        .listRbacFn = Fake.policies,
        .detectCedarFn = Fake.cedar,
        .listCedarFn = Fake.policies,
        .conditionsFn = Fake.conditions,
    };
    var spec = try ownedTaskSpec(std.testing.allocator, .{
        .serial = 1,
        .tab = .access_review,
        .service = &service,
        .namespace = "default",
        .backend_override = backend,
    });
    defer spec.deinit(std.testing.allocator);
    const key = try requests.startRequest(.authorization, 1, &spec);

    var theme = try theme_loader.defaultTheme(std.testing.allocator);
    defer theme_loader.deinitTheme(&theme);
    var view = try AuthorizationView.init(std.testing.allocator, &theme, &service);
    defer view.deinit();
    view.access_tab.active_key = key;
    view.access_tab.active_serial = 1;
    view.loading = true;
    var target = UiTarget{ .view = &view };
    const Route = struct {
        plane: *plane_mod.DataPlane,
        requests: *ancillary_mod.AncillaryRequests,
        target: *UiTarget,
        fn route(raw: *anyopaque, value: keys.EnvelopeTarget) ?*anyopaque {
            const self: *@This() = @ptrCast(@alignCast(raw));
            return switch (value) {
                .lifecycle => @ptrCast(self.plane),
                .authorization => |request_key| if (self.requests.contains(request_key, .authorization))
                    @ptrCast(self.target)
                else
                    null,
                else => null,
            };
        }
        fn observe(raw: *anyopaque, payload: *anyopaque, _: ?keys.ResourceIdentity) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            const completion: *lifecycle.LifecycleCompletion = @ptrCast(@alignCast(payload));
            _ = self.requests.handleCompletion(completion.*);
        }
    };
    var route = Route{ .plane = &plane, .requests = &requests, .target = &target };
    var router = keys.UiRouter{
        .context = &route,
        .targetFn = Route.route,
        .lifecycleFn = Route.observe,
    };

    try supervisor.startRoot();
    defer {
        producer.enqueueShutdown() catch {};
        _ = supervisor.awaitRoot();
        while (queue.pop()) |value| {
            var envelope = value;
            envelope.deinit(std.testing.allocator);
        }
    }
    for (0..10_000) |_| {
        while (queue.pop()) |value| {
            var envelope = value;
            if (envelope.target != .lifecycle and !requests.acceptsEnvelope(envelope)) {
                envelope.deinit(std.testing.allocator);
                continue;
            }
            try envelope.apply(&router, std.testing.allocator);
        }
        if (requests.trackedCount() == 0) break;
        try io.sleep(.{ .nanoseconds = std.time.ns_per_ms }, .awake);
    }
    try std.testing.expectEqual(@as(usize, 48), fake.calls);
    try std.testing.expectEqual(@as(usize, 8), view.access_tab.table.items.items.len);
    try std.testing.expectEqual(@as(usize, 0), active_session.leaseCount());
}

test "real supervisor applies authorization matrix with one authorization child" {
    try runTask14AuthorizationGate();
}
