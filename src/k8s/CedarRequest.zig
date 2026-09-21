// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Background work for the Cedar workbench: listing Policy objects and running the
// official `cedar` binary against them.
//
// All of it is off the UI thread for the same reason the detail and log requests are:
// a scan spawns one `cedar` process per policy, and doing that inline would freeze the
// table for as long as it takes.
//
// The CLI wrapper is constructed inside `run` rather than shared with the App. It owns
// a temp directory and a file counter, and handing the same mutable instance to a
// worker thread would be a data race the moment two Cedar actions overlap.

const std = @import("std");

const keys = @import("ResourceKey.zig");
const lifecycle = @import("LifecycleInbox.zig");
const session = @import("ActiveContextSession.zig");
const K8sService = @import("../services/K8sService.zig").K8sService;
const k8s_types = @import("../services/k8s_types.zig");
const cedar_cli = @import("../services/CedarCli.zig");
const CedarCli = cedar_cli.CedarCli;
const cedar_request = @import("../viewmodel/cedar_request.zig");
const workbench = @import("../viewmodel/cedar_workbench.zig");
const CedarView = @import("../view/CedarView.zig").CedarView;
const DetailView = @import("../view/DetailView.zig").DetailView;
const ViewManager = @import("../viewmodel/ViewManager.zig").ViewManager;
const age = @import("../viewmodel/age.zig");

pub const Kind = enum {
    list,
    source,
    check_parse,
    format,
    validate,
    scan,
    can_i,
};

pub const CedarPayload = struct {
    generation: keys.Generation,
    subscription_id: keys.SubscriptionId,
    serial: u64,
    result: Result,

    pub const ListResult = struct {
        rows: []CedarView.Row,
        crd_present: bool,
        cedar_installed: bool,
        transferred: bool = false,
    };
    /// Text destined for a detail pane.
    pub const PaneResult = struct {
        title: []u8,
        body: []u8,
    };
    pub const FailureResult = struct {
        message: []u8,
        /// A failed list leaves the table alone and shows the message on the view; a
        /// failed action has no pane to show, so it goes to the view too.
        kind: Kind,
    };
    pub const Result = union(enum) {
        list: ListResult,
        pane: PaneResult,
        failure: FailureResult,
    };
};

pub const UiTarget = struct {
    view: *CedarView,
    detail: *DetailView,
    view_manager: *ViewManager,
    active_key: keys.RequestKey,
    active_serial: u64,
    dirty: *bool,
};

pub const Options = struct {
    serial: u64,
    kind: Kind,
    service: *K8sService,
    /// Cluster context name, for the report headers.
    context: []const u8 = "",
    /// Selected policy, for the per-policy actions.
    name: []const u8 = "",
    content: []const u8 = "",
    /// Optional file paths the user supplied.
    schema_path: []const u8 = "",
    entities_path: []const u8 = "",
    context_path: []const u8 = "",
    /// can-i inputs.
    principal: []const u8 = "",
    action: []const u8 = "",
    resource: []const u8 = "",
    namespace: []const u8 = "",
    api_group: []const u8 = "",
};

const owned_field_names = [_][]const u8{
    "context",       "name",         "content",   "schema_path",
    "entities_path", "context_path", "principal", "action",
    "resource",      "namespace",    "api_group",
};

const Spec = struct {
    serial: u64,
    kind: Kind,
    service: *K8sService,
    context: []u8 = &.{},
    name: []u8 = &.{},
    content: []u8 = &.{},
    schema_path: []u8 = &.{},
    entities_path: []u8 = &.{},
    context_path: []u8 = &.{},
    principal: []u8 = &.{},
    action: []u8 = &.{},
    resource: []u8 = &.{},
    namespace: []u8 = &.{},
    api_group: []u8 = &.{},
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
        if (lease.purpose != .cedar) return error.InvalidLeasePurpose;

        const payload = try control.allocator.create(CedarPayload);
        var payload_initialized = false;
        var payload_owned = true;
        errdefer {
            if (payload_owned) {
                if (payload_initialized) payloadDeinit(payload, control.allocator);
                control.allocator.destroy(payload);
            }
        }

        const result = self.build(control.allocator, control) catch |err| blk: {
            if (err == error.Canceled) return err;
            break :blk CedarPayload.Result{ .failure = .{
                .kind = self.kind,
                .message = try failureMessage(control.allocator, err),
            } };
        };

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
            CedarPayload,
            control.allocator,
            .{ .cedar = key },
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

    fn build(
        self: *Spec,
        allocator: std.mem.Allocator,
        control: *lifecycle.ChildControl,
    ) !CedarPayload.Result {
        if (self.kind == .source) return .{ .pane = try self.buildSource(allocator) };

        var cli = CedarCli.init(allocator);
        defer cli.deinit();

        if (self.kind == .list) {
            return .{ .list = try self.buildList(allocator, cli.available()) };
        }
        if (!cli.available()) return error.CedarNotInstalled;

        return switch (self.kind) {
            .check_parse => .{ .pane = try self.buildCheckParse(allocator, &cli) },
            .format => .{ .pane = try self.buildFormat(allocator, &cli) },
            .validate => .{ .pane = try self.buildValidate(allocator, &cli) },
            .scan => .{ .pane = try self.buildScan(allocator, &cli, control) },
            .can_i => .{ .pane = try self.buildCanI(allocator, &cli, control) },
            .list, .source => unreachable,
        };
    }

    fn buildSource(self: *Spec, allocator: std.mem.Allocator) !CedarPayload.PaneResult {
        if (self.name.len == 0) return error.NoPolicySelected;
        const title = try std.fmt.allocPrint(allocator, "cedar: {s}", .{self.name});
        errdefer allocator.free(title);
        return .{ .title = title, .body = try allocator.dupe(u8, self.content) };
    }

    fn buildList(
        self: *Spec,
        allocator: std.mem.Allocator,
        cedar_installed: bool,
    ) !CedarPayload.ListResult {
        const policies = try self.service.listCedarPolicyDocuments();
        defer {
            for (policies) |*policy| policy.deinit();
            self.service.allocator.free(policies);
        }

        // An empty list is ambiguous on its own -- no CRD and no objects look the
        // same -- so ask discovery directly rather than inferring from the count.
        const crd_present = if (policies.len > 0) true else self.service.detectCedarAuth() catch false;

        var rows = std.ArrayListUnmanaged(CedarView.Row).empty;
        errdefer {
            for (rows.items) |*row| row.deinit();
            rows.deinit(allocator);
        }

        const count = @min(policies.len, cedar_cli.max_policies);
        try rows.ensureTotalCapacity(allocator, count);
        for (policies[0..count]) |policy| {
            var row = CedarView.Row{
                .name = try allocator.dupe(u8, policy.name),
                .effect = CedarView.effectOf(policy.content),
                .validation = undefined,
                .age = undefined,
                .summary = undefined,
                .content = undefined,
                .allocator = allocator,
            };
            errdefer allocator.free(row.name);
            row.validation = try allocator.dupe(u8, policy.validation);
            errdefer allocator.free(row.validation);
            row.age = try age.calculateAge(allocator, policy.created_at);
            errdefer allocator.free(row.age);
            row.summary = try allocator.dupe(u8, CedarView.summaryOf(policy.content));
            errdefer allocator.free(row.summary);
            row.content = try allocator.dupe(u8, policy.content);
            rows.appendAssumeCapacity(row);
        }

        return .{
            .rows = try rows.toOwnedSlice(allocator),
            .crd_present = crd_present,
            .cedar_installed = cedar_installed,
        };
    }

    fn buildCheckParse(self: *Spec, allocator: std.mem.Allocator, cli: *CedarCli) !CedarPayload.PaneResult {
        if (self.name.len == 0) return error.NoPolicySelected;
        var outcome = try cli.checkParse(self.content);
        defer outcome.deinit(allocator);

        var body = std.ArrayListUnmanaged(u8).empty;
        errdefer body.deinit(allocator);
        try body.print(allocator, "{s}: {s}\n", .{ self.name, if (outcome.ok) "parsed" else "PARSE_FAIL" });
        if (outcome.diagnostics.len > 0) {
            try body.appendSlice(allocator, "\n");
            try body.appendSlice(allocator, outcome.diagnostics);
        }
        return .{
            .title = try std.fmt.allocPrint(allocator, "cedar check-parse: {s}", .{self.name}),
            .body = try body.toOwnedSlice(allocator),
        };
    }

    fn buildFormat(self: *Spec, allocator: std.mem.Allocator, cli: *CedarCli) !CedarPayload.PaneResult {
        if (self.name.len == 0) return error.NoPolicySelected;
        var outcome = try cli.format(self.content);
        defer outcome.deinit(allocator);

        // On failure the diagnostics are the error text, not formatted source, so the
        // pane must not present them as the policy.
        const body = if (outcome.ok)
            try allocator.dupe(u8, outcome.diagnostics)
        else
            try std.fmt.allocPrint(
                allocator,
                "{s}: FORMAT_FAIL\n\n{s}",
                .{ self.name, outcome.diagnostics },
            );
        errdefer allocator.free(body);
        return .{
            .title = try std.fmt.allocPrint(allocator, "cedar format: {s}", .{self.name}),
            .body = body,
        };
    }

    fn buildValidate(self: *Spec, allocator: std.mem.Allocator, cli: *CedarCli) !CedarPayload.PaneResult {
        if (self.name.len == 0) return error.NoPolicySelected;
        if (self.schema_path.len == 0) return error.NoSchema;
        var outcome = try cli.validate(self.content, self.schema_path);
        defer outcome.deinit(allocator);

        var body = std.ArrayListUnmanaged(u8).empty;
        errdefer body.deinit(allocator);
        try body.print(allocator, "Policy: {s}\nSchema: {s}\n\n", .{ self.name, self.schema_path });
        try body.print(allocator, "{s}\n", .{if (outcome.ok) "valid" else "INVALID"});
        if (outcome.diagnostics.len > 0) {
            try body.appendSlice(allocator, "\n");
            try body.appendSlice(allocator, outcome.diagnostics);
        }
        return .{
            .title = try std.fmt.allocPrint(allocator, "cedar validate: {s}", .{self.name}),
            .body = try body.toOwnedSlice(allocator),
        };
    }

    fn buildScan(
        self: *Spec,
        allocator: std.mem.Allocator,
        cli: *CedarCli,
        control: *lifecycle.ChildControl,
    ) !CedarPayload.PaneResult {
        var collected = try self.collectPolicies(allocator, cli, control, .{ .parse_only = true });
        defer collected.deinit(allocator);

        const text = try workbench.formatScanReport(allocator, .{
            .results = collected.results.items,
            .context = if (self.context.len > 0) self.context else "(current)",
            .truncated = collected.truncated,
        });
        errdefer allocator.free(text);
        return .{ .title = try allocator.dupe(u8, "cedar scan"), .body = text };
    }

    fn buildCanI(
        self: *Spec,
        allocator: std.mem.Allocator,
        cli: *CedarCli,
        control: *lifecycle.ChildControl,
    ) !CedarPayload.PaneResult {
        var request = try cedar_request.build(allocator, .{
            .principal = self.principal,
            .action = self.action,
            .resource = self.resource,
            .namespace = self.namespace,
            .api_group = self.api_group,
        });
        defer request.deinit();

        var collected = try self.collectPolicies(allocator, cli, control, .{ .parse_only = false });
        defer collected.deinit(allocator);

        const entities_base = if (self.entities_path.len > 0)
            try readOptionalFile(allocator, self.entities_path)
        else
            null;
        defer if (entities_base) |text| allocator.free(text);

        const context_json = if (self.context_path.len > 0)
            try readOptionalFile(allocator, self.context_path)
        else
            try allocator.dupe(u8, "{}");
        defer allocator.free(context_json);

        const entities_json = try cedar_request.writeEntities(allocator, request, entities_base);
        defer allocator.free(entities_json);

        const principal_uid = try request.principal.render(allocator);
        defer allocator.free(principal_uid);
        const action_uid = try request.action.render(allocator);
        defer allocator.free(action_uid);
        const resource_uid = try request.resource.render(allocator);
        defer allocator.free(resource_uid);

        const schema: ?[]const u8 = if (self.schema_path.len > 0) self.schema_path else null;
        const base_input = cedar_cli.AuthorizeInput{
            .policies = collected.policy_set.items,
            .entities_json = entities_json,
            .context_json = context_json,
            .principal = principal_uid,
            .action = action_uid,
            .resource = resource_uid,
            .schema_path = schema,
        };

        // Any gap in the policy set makes the answer unknowable, so the evaluation is
        // not even attempted: running it would produce a confident ALLOW or DENY from
        // evidence that is missing a policy which might have said the opposite.
        var decision = cedar_cli.Decision.indeterminate;
        var diagnostics: []u8 = try allocator.dupe(u8, "");
        defer allocator.free(diagnostics);
        var determining: []u8 = try allocator.dupe(u8, "");
        defer allocator.free(determining);

        var matrix = std.ArrayListUnmanaged(workbench.MatrixEntry).empty;
        defer matrix.deinit(allocator);

        if (collected.results.items.len == 0 and collected.included.items.len == 0) {
            // No policies at all: Cedar's answer would be a vacuous DENY. Say so.
            decision = .indeterminate;
        } else if (collected.gaps.items.len == 0) {
            var result = try cli.authorize(base_input);
            defer result.deinit(allocator);
            decision = result.decision;

            allocator.free(diagnostics);
            diagnostics = try allocator.dupe(u8, result.diagnostics);
            allocator.free(determining);
            determining = try allocator.dupe(u8, result.determining);

            if (request.mode == .k8s and decision != .indeterminate) {
                try matrix.ensureTotalCapacity(allocator, cedar_request.matrix_verbs.len);
                for (cedar_request.matrix_verbs) |verb| {
                    if (control.cancel_requested.load(.acquire)) return error.Canceled;
                    const verb_uid = try std.fmt.allocPrint(allocator, "k8s::Action::\"{s}\"", .{verb});
                    defer allocator.free(verb_uid);
                    var per_verb = base_input;
                    per_verb.action = verb_uid;
                    const verb_decision = cli.authorizeDecision(per_verb) catch cedar_cli.Decision.indeterminate;
                    matrix.appendAssumeCapacity(.{ .verb = verb, .decision = verb_decision });
                }
            }
        }

        const text = try workbench.formatCanIReport(allocator, .{
            .decision = decision,
            .request = request,
            .context = if (self.context.len > 0) self.context else "(current)",
            .included = collected.included.items,
            .gaps = collected.gaps.items,
            .determining = determining,
            .matrix = matrix.items,
            .diagnostics = diagnostics,
            .schema_path = schema,
        });
        errdefer allocator.free(text);
        return .{ .title = try allocator.dupe(u8, "cedar can-i"), .body = text };
    }

    const CollectOptions = struct {
        /// Scan only reports; can-i also needs the assembled set.
        parse_only: bool,
    };

    /// Fetch every Policy object and check-parse it, building both the per-policy
    /// verdicts and the combined policy set.
    const Collected = struct {
        results: std.ArrayListUnmanaged(workbench.PolicyResult) = .empty,
        /// Names that parsed, borrowed from `owned_names`.
        included: std.ArrayListUnmanaged([]const u8) = .empty,
        gaps: std.ArrayListUnmanaged(workbench.PolicyResult) = .empty,
        policy_set: std.ArrayListUnmanaged(u8) = .empty,
        owned_names: std.ArrayListUnmanaged([]u8) = .empty,
        owned_details: std.ArrayListUnmanaged([]u8) = .empty,
        truncated: bool = false,

        fn record(
            self: *Collected,
            allocator: std.mem.Allocator,
            name: []const u8,
            status: workbench.PolicyStatus,
            detail: []const u8,
        ) !void {
            const entry = workbench.PolicyResult{ .name = name, .status = status, .detail = detail };
            try self.results.append(allocator, entry);
            if (status == .ok) {
                try self.included.append(allocator, name);
            } else {
                try self.gaps.append(allocator, entry);
            }
        }

        fn deinit(self: *Collected, allocator: std.mem.Allocator) void {
            for (self.owned_names.items) |name| allocator.free(name);
            for (self.owned_details.items) |detail| allocator.free(detail);
            self.owned_names.deinit(allocator);
            self.owned_details.deinit(allocator);
            self.results.deinit(allocator);
            self.included.deinit(allocator);
            self.gaps.deinit(allocator);
            self.policy_set.deinit(allocator);
        }
    };

    fn collectPolicies(
        self: *Spec,
        allocator: std.mem.Allocator,
        cli: *CedarCli,
        control: *lifecycle.ChildControl,
        options: CollectOptions,
    ) !Collected {
        var collected = Collected{};
        errdefer collected.deinit(allocator);

        const policies = try self.service.listCedarPolicyDocuments();
        defer {
            for (policies) |*policy| policy.deinit();
            self.service.allocator.free(policies);
        }

        for (policies, 0..) |policy, index| {
            if (control.cancel_requested.load(.acquire)) return error.Canceled;

            if (index >= cedar_cli.max_policies) {
                collected.truncated = true;
                break;
            }

            const owned_name = try allocator.dupe(u8, policy.name);
            try collected.owned_names.append(allocator, owned_name);

            if (policy.content.len > cedar_cli.max_policy_bytes) {
                try collected.record(allocator, owned_name, .too_large, "");
                continue;
            }

            var outcome = cli.checkParse(policy.content) catch {
                try collected.record(allocator, owned_name, .fetch_error, "");
                continue;
            };
            defer outcome.deinit(allocator);

            if (!outcome.ok) {
                const detail = try allocator.dupe(u8, outcome.diagnostics);
                try collected.owned_details.append(allocator, detail);
                try collected.record(allocator, owned_name, .parse_fail, detail);
                continue;
            }

            try collected.record(allocator, owned_name, .ok, "");
            if (!options.parse_only) {
                try workbench.appendToPolicySet(allocator, &collected.policy_set, owned_name, policy.content);
            }
        }

        if (collected.truncated) {
            try collected.gaps.append(allocator, .{ .name = "(remaining policies)", .status = .over_limit });
        }
        return collected;
    }

    fn deinit(raw: ?*anyopaque, _: std.mem.Alignment, allocator: std.mem.Allocator) void {
        const self: *Spec = @ptrCast(@alignCast(raw orelse return));
        inline for (owned_field_names) |field| allocator.free(@field(self, field));
        allocator.destroy(self);
    }
};

fn readOptionalFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const runtime = @import("../core/runtime.zig");
    return std.Io.Dir.cwd().readFileAlloc(
        runtime.io(),
        path,
        allocator,
        .limited(cedar_cli.max_policy_bytes),
    ) catch return error.InputFileUnreadable;
}

fn failureMessage(allocator: std.mem.Allocator, err: anyerror) ![]u8 {
    return allocator.dupe(u8, switch (err) {
        error.NotConnected => "Not connected to Kubernetes cluster",
        error.CedarNotInstalled, error.CedarNotFound => CedarCli.missing_hint,
        error.NoPolicySelected => "No Cedar policy is selected",
        error.NoSchema => "Cedar validate needs a schema file. Press Shift-V and enter a path to a .cedarschema.",
        error.InputFileUnreadable => "A file given for the schema, entities or context could not be read",
        error.PolicyTooLarge => "The selected policy is larger than the analysis limit",
        error.EmptyPrincipal => "can-i needs a principal (P)",
        error.EmptyAction => "can-i needs an action (A)",
        error.EmptyResource => "can-i needs a resource (R)",
        error.InvalidSegment => "can-i inputs may only contain letters, digits, '.', '_', '-' and ':'",
        error.InvalidEntityUid => "An entity UID could not be parsed",
        error.DuplicateEntityUid => "The entities file defines the same UID twice",
        error.MalformedEntities => "The entities file is not a Cedar entities array",
        else => @errorName(err),
    });
}

fn payloadPreflight(
    payload: *CedarPayload,
    router: *keys.UiRouter,
    allocator: std.mem.Allocator,
) anyerror!keys.ApplyPlan {
    const key = keys.RequestKey{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    };
    const raw = router.target(.{ .cedar = key }) orelse return error.StaleCedarTarget;
    const target: *UiTarget = @ptrCast(@alignCast(raw));
    if (!target.active_key.eql(key) or target.active_serial != payload.serial)
        return error.StaleCedarTarget;

    switch (payload.result) {
        .list => |value| {
            try target.view.table.items.ensureTotalCapacity(allocator, value.rows.len);
            try target.view.table.filtered_indices.ensureTotalCapacity(allocator, value.rows.len);
        },
        .pane => {
            try target.view_manager.view_ptrs.ensureUnusedCapacity(allocator, 1);
            try target.view_manager.view_vtables.ensureUnusedCapacity(allocator, 1);
        },
        .failure => {},
    }
    return .{};
}

fn payloadCommit(payload: *CedarPayload, router: *keys.UiRouter, _: *keys.ApplyPlan) void {
    const key = keys.RequestKey{
        .generation = payload.generation,
        .subscription_id = payload.subscription_id,
    };
    const raw = router.target(.{ .cedar = key }) orelse return;
    const target: *UiTarget = @ptrCast(@alignCast(raw));
    if (!target.active_key.eql(key) or target.active_serial != payload.serial) return;

    switch (payload.result) {
        .list => |*value| {
            target.view.clearError();
            replaceRows(target.view, value.rows);
            value.transferred = true;
            target.view.crd_present = value.crd_present;
            target.view.cedar_installed = value.cedar_installed;
            target.view.loading = false;
        },
        .pane => |value| {
            target.view.clearError();
            target.view.loading = false;
            target.detail.setContentText(value.body, value.title) catch return;
            target.view_manager.pushView(target.detail.createView()) catch return;
        },
        .failure => |value| {
            target.view.loading = false;
            target.view.setError(value.message) catch {};
        },
    }
    target.dirty.* = true;
}

fn replaceRows(view: *CedarView, rows: []CedarView.Row) void {
    const selected = view.table.selected_row;
    view.table.clearItems();
    for (rows) |row| view.table.items.appendAssumeCapacity(row);
    for (view.table.items.items, 0..) |*row, index| {
        if (CedarView.matchFn(row, view.table.filter_text))
            view.table.filtered_indices.appendAssumeCapacity(index);
    }
    const count = view.table.filtered_indices.items.len;
    view.table.selected_row = if (count == 0) 0 else @min(selected, @as(u32, @intCast(count - 1)));
    view.applySorting();
}

fn payloadDeinit(payload: *CedarPayload, allocator: std.mem.Allocator) void {
    switch (payload.result) {
        .list => |value| {
            if (!value.transferred) for (value.rows) |*row| row.deinit();
            allocator.free(value.rows);
        },
        .pane => |value| {
            allocator.free(value.title);
            allocator.free(value.body);
        },
        .failure => |value| allocator.free(value.message),
    }
}

fn payloadBytes(payload: *const CedarPayload) usize {
    return @sizeOf(CedarPayload) + switch (payload.result) {
        .list => |value| value.rows.len * @sizeOf(CedarView.Row),
        .pane => |value| value.title.len + value.body.len,
        .failure => |value| value.message.len,
    };
}

pub const payload_handler = keys.PayloadHandler(CedarPayload){
    .preflight = payloadPreflight,
    .commit = payloadCommit,
    .deinit = payloadDeinit,
};

pub fn ownedTaskSpec(allocator: std.mem.Allocator, options: Options) !lifecycle.OwnedTaskSpec {
    const spec = try allocator.create(Spec);
    errdefer allocator.destroy(spec);
    spec.* = .{ .serial = options.serial, .kind = options.kind, .service = options.service };

    // Allocate every owned string up front and unwind them together, so a failure
    // partway through does not leak the ones already copied.
    var filled: usize = 0;
    errdefer {
        inline for (owned_field_names, 0..) |field, index| {
            if (index < filled) allocator.free(@field(spec, field));
        }
    }
    inline for (owned_field_names) |field| {
        @field(spec, field) = try allocator.dupe(u8, @field(options, field));
        filled += 1;
    }

    var owned_bytes: usize = @sizeOf(Spec);
    inline for (owned_field_names) |field| owned_bytes += @field(spec, field).len;

    return .{
        .ptr = spec,
        .alignment = .of(Spec),
        .owned_bytes = owned_bytes,
        .lease_purpose = .cedar,
        .bindFn = Spec.bind,
        .runFn = Spec.run,
        .deinitFn = Spec.deinit,
    };
}

// --- Tests ---

const testing = std.testing;

test "every option string is copied into the spec and freed once" {
    const a = testing.allocator;
    var service = try K8sService.init(a);
    defer service.deinit();

    var spec = try ownedTaskSpec(a, .{
        .serial = 1,
        .kind = .can_i,
        .service = &service,
        .context = "kind-dev",
        .name = "permit-all",
        .content = "permit(principal, action, resource);",
        .principal = "alice",
        .action = "get",
        .resource = "pods",
        .namespace = "kube-system",
    });
    defer spec.deinit(a);

    const inner: *Spec = @ptrCast(@alignCast(spec.ptr.?));
    try testing.expectEqualStrings("permit-all", inner.name);
    try testing.expectEqualStrings("alice", inner.principal);
    try testing.expectEqualStrings("kube-system", inner.namespace);
    // Unset options still produce owned empty slices, so deinit is uniform.
    try testing.expectEqualStrings("", inner.schema_path);
    try testing.expectEqual(session.LeasePurpose.cedar, spec.lease_purpose);
}

test "failure messages name the fix rather than the error tag" {
    const a = testing.allocator;
    const cases = [_]struct { err: anyerror, needle: []const u8 }{
        .{ .err = error.CedarNotInstalled, .needle = "cargo install" },
        .{ .err = error.NoSchema, .needle = ".cedarschema" },
        .{ .err = error.EmptyPrincipal, .needle = "principal" },
        .{ .err = error.InvalidSegment, .needle = "letters, digits" },
    };
    for (cases) |case| {
        const message = try failureMessage(a, case.err);
        defer a.free(message);
        try testing.expect(std.mem.indexOf(u8, message, case.needle) != null);
    }
}

test "an unmapped error still produces a message instead of nothing" {
    const a = testing.allocator;
    const message = try failureMessage(a, error.SomethingUnexpected);
    defer a.free(message);
    try testing.expectEqualStrings("SomethingUnexpected", message);
}
