// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// k9s-style filter prefixes and command-palette extras. Pure: no App, no I/O.
//
// Filter bar (the `/` prompt, without the slash):
//   term     substring on searchable columns (existing behaviour)
//   !term    inverse substring
//   -l sel   label selector (AND of comma-separated k=v pairs against stored labels)
//   -f term  subsequence (fuzzy) match on searchable columns
//
// Palette extras after the alias (`:po kube-system /fred app=x @ctx`):
//   /foo     apply filter `foo` after switching
//   k=v      apply as a `-l` label filter
//   @name    switch kube context first
//   other    treat as a namespace

const std = @import("std");

pub const FilterKind = enum { substring, inverse, label, fuzzy };

pub const ParsedFilter = struct {
    kind: FilterKind,
    query: []const u8,
};

/// Split a filter-bar payload into kind + query. Empty query means "match all"
/// regardless of kind (so `/!` with nothing typed does not blank the table).
pub fn parseFilter(raw: []const u8) ParsedFilter {
    const s = std.mem.trim(u8, raw, " \t");
    if (s.len >= 1 and s[0] == '!') {
        return .{ .kind = .inverse, .query = std.mem.trim(u8, s[1..], " \t") };
    }
    if (std.mem.startsWith(u8, s, "-l")) {
        return .{ .kind = .label, .query = std.mem.trim(u8, s[2..], " \t") };
    }
    if (std.mem.startsWith(u8, s, "-f")) {
        return .{ .kind = .fuzzy, .query = std.mem.trim(u8, s[2..], " \t") };
    }
    return .{ .kind = .substring, .query = s };
}

pub const CommandExtras = struct {
    name: []const u8,
    namespace: ?[]const u8 = null,
    filter: ?[]const u8 = null,
    labels: ?[]const u8 = null,
    context: ?[]const u8 = null,
};

/// First token is the command/alias; remaining tokens are extras.
pub fn parseCommand(raw: []const u8) CommandExtras {
    const trimmed = std.mem.trim(u8, raw, " \t");
    if (trimmed.len == 0) return .{ .name = trimmed };

    var it = std.mem.tokenizeScalar(u8, trimmed, ' ');
    const name = it.next() orelse return .{ .name = trimmed };
    var extras = CommandExtras{ .name = name };
    while (it.next()) |tok| {
        if (tok.len == 0) continue;
        if (tok[0] == '/') {
            extras.filter = tok[1..];
        } else if (tok[0] == '@') {
            extras.context = tok[1..];
        } else if (std.mem.indexOfScalar(u8, tok, '=')) |_| {
            extras.labels = tok;
        } else {
            extras.namespace = tok;
        }
    }
    return extras;
}

/// Flatten a metadata.labels JSON object to `k=v,k=v`. Empty / non-object → "".
/// Caller owns a non-empty result.
pub fn formatLabels(allocator: std.mem.Allocator, value: std.json.Value) ![]const u8 {
    if (value != .object) return &.{};
    if (value.object.count() == 0) return &.{};

    var buf: std.ArrayListUnmanaged(u8) = .empty;
    errdefer buf.deinit(allocator);
    var first = true;
    var iter = value.object.iterator();
    while (iter.next()) |entry| {
        if (!first) try buf.append(allocator, ',');
        first = false;
        try buf.appendSlice(allocator, entry.key_ptr.*);
        try buf.append(allocator, '=');
        if (entry.value_ptr.* == .string) {
            try buf.appendSlice(allocator, entry.value_ptr.string);
        }
    }
    return buf.toOwnedSlice(allocator);
}

/// AND of comma-separated `k=v` pairs: each pair must appear in `labels`.
pub fn labelsMatch(labels: []const u8, selector: []const u8) bool {
    const sel = std.mem.trim(u8, selector, " \t");
    if (sel.len == 0) return true;
    var it = std.mem.splitScalar(u8, sel, ',');
    while (it.next()) |pair| {
        const p = std.mem.trim(u8, pair, " \t");
        if (p.len == 0) continue;
        if (std.mem.indexOf(u8, labels, p) == null) return false;
    }
    return true;
}

fn isSubsequence(query: []const u8, candidate: []const u8) bool {
    if (query.len == 0) return true;
    var qi: usize = 0;
    for (candidate) |ch| {
        if (std.ascii.toLower(ch) == std.ascii.toLower(query[qi])) {
            qi += 1;
            if (qi == query.len) return true;
        }
    }
    return false;
}

fn columnsHit(columns: []const []const u8, query: []const u8, fuzzy: bool) bool {
    if (query.len == 0) return true;
    for (columns) |col| {
        if (fuzzy) {
            if (isSubsequence(query, col)) return true;
        } else if (std.mem.indexOf(u8, col, query) != null) {
            return true;
        }
    }
    return false;
}

/// Match a row against a filter-bar payload.
pub fn matchSearchable(columns: []const []const u8, labels: []const u8, filter: []const u8) bool {
    const parsed = parseFilter(filter);
    if (parsed.query.len == 0) return true;

    const hit = switch (parsed.kind) {
        .substring, .inverse => columnsHit(columns, parsed.query, false),
        .fuzzy => columnsHit(columns, parsed.query, true),
        .label => labelsMatch(labels, parsed.query),
    };
    return if (parsed.kind == .inverse) !hit else hit;
}

const healthy_status = [_][]const u8{
    "Running",   "Succeeded", "Completed", "Active",    "Bound",
    "Available", "Ready",     "True",      "Scheduled", "Healthy",
};

pub fn isHealthyStatus(status: []const u8) bool {
    for (healthy_status) |ok| {
        if (std.ascii.eqlIgnoreCase(status, ok)) return true;
    }
    return false;
}

/// READY cells like `1/1` are healthy; `0/1` and `0/0` are not. No slash → leave it.
pub fn isHealthyReady(ready: []const u8) bool {
    const slash = std.mem.indexOfScalar(u8, ready, '/') orelse return true;
    const left = ready[0..slash];
    const right = ready[slash + 1 ..];
    if (left.len == 0 or right.len == 0) return true;
    if (std.mem.eql(u8, left, "0")) return false;
    return std.mem.eql(u8, left, right);
}

/// A faults-toggle row: STATUS not healthy, or READY not fully up.
pub fn isFault(status: ?[]const u8, ready: ?[]const u8) bool {
    if (status) |s| {
        if (!isHealthyStatus(s)) return true;
    }
    if (ready) |r| {
        if (!isHealthyReady(r)) return true;
    }
    return false;
}

pub const OwnerRef = struct {
    kind: []const u8,
    name: []const u8,
};

/// First ownerReference, borrowing from the parsed JSON tree.
pub fn firstOwnerRef(root: std.json.Value) ?OwnerRef {
    if (root != .object) return null;
    const meta_v = root.object.get("metadata") orelse return null;
    if (meta_v != .object) return null;
    const refs_v = meta_v.object.get("ownerReferences") orelse return null;
    if (refs_v != .array or refs_v.array.items.len == 0) return null;
    const first = refs_v.array.items[0];
    if (first != .object) return null;
    const kind_v = first.object.get("kind") orelse return null;
    const name_v = first.object.get("name") orelse return null;
    if (kind_v != .string or name_v != .string) return null;
    if (kind_v.string.len == 0 or name_v.string.len == 0) return null;
    return .{ .kind = kind_v.string, .name = name_v.string };
}

pub fn specSuspend(root: std.json.Value) bool {
    if (root != .object) return false;
    const spec = root.object.get("spec") orelse return false;
    if (spec != .object) return false;
    const sus = spec.object.get("suspend") orelse return false;
    return sus == .bool and sus.bool;
}

/// Map a Kubernetes owner kind onto a c3s view name. Closed list: unknown kinds
/// return null rather than guessing a CRD view that does not exist.
pub fn viewForOwnerKind(kind: []const u8) ?[]const u8 {
    const pairs = [_]struct { k: []const u8, v: []const u8 }{
        .{ .k = "Pod", .v = "pods" },
        .{ .k = "ReplicaSet", .v = "replicasets" },
        .{ .k = "Deployment", .v = "deployments" },
        .{ .k = "StatefulSet", .v = "statefulsets" },
        .{ .k = "DaemonSet", .v = "daemonsets" },
        .{ .k = "Job", .v = "jobs" },
        .{ .k = "CronJob", .v = "cronjobs" },
        .{ .k = "Node", .v = "nodes" },
        .{ .k = "Service", .v = "services" },
        .{ .k = "ReplicaSet", .v = "replicasets" },
        .{ .k = "HorizontalPodAutoscaler", .v = "hpa" },
        .{ .k = "PersistentVolumeClaim", .v = "persistentvolumeclaims" },
        .{ .k = "ConfigMap", .v = "configmaps" },
        .{ .k = "Secret", .v = "secrets" },
        .{ .k = "ServiceAccount", .v = "serviceaccounts" },
        .{ .k = "Namespace", .v = "namespaces" },
    };
    for (pairs) |p| {
        if (std.ascii.eqlIgnoreCase(kind, p.k)) return p.v;
    }
    return null;
}

pub fn usedByApplies(view_name: []const u8) bool {
    return std.mem.eql(u8, view_name, "serviceaccounts") or
        std.mem.eql(u8, view_name, "secrets") or
        std.mem.eql(u8, view_name, "configmaps") or
        std.mem.eql(u8, view_name, "persistentvolumeclaims");
}

pub fn restartApplies(view_name: []const u8) bool {
    return std.mem.eql(u8, view_name, "deployments") or
        std.mem.eql(u8, view_name, "statefulsets") or
        std.mem.eql(u8, view_name, "daemonsets");
}

pub fn scaleApplies(view_name: []const u8) bool {
    return std.mem.eql(u8, view_name, "deployments") or
        std.mem.eql(u8, view_name, "statefulsets") or
        std.mem.eql(u8, view_name, "replicasets");
}

pub fn rollbackApplies(view_name: []const u8) bool {
    return restartApplies(view_name) or std.mem.eql(u8, view_name, "replicasets");
}

test "parseFilter prefixes" {
    const a = parseFilter("nginx");
    try std.testing.expectEqual(FilterKind.substring, a.kind);
    try std.testing.expectEqualStrings("nginx", a.query);

    const b = parseFilter("!crash");
    try std.testing.expectEqual(FilterKind.inverse, b.kind);
    try std.testing.expectEqualStrings("crash", b.query);

    const c = parseFilter("-l app=web");
    try std.testing.expectEqual(FilterKind.label, c.kind);
    try std.testing.expectEqualStrings("app=web", c.query);

    const d = parseFilter("-f ngnx");
    try std.testing.expectEqual(FilterKind.fuzzy, d.kind);
    try std.testing.expectEqualStrings("ngnx", d.query);

    const e = parseFilter("!");
    try std.testing.expectEqual(FilterKind.inverse, e.kind);
    try std.testing.expectEqualStrings("", e.query);
}

test "parseCommand extras" {
    const a = parseCommand("po");
    try std.testing.expectEqualStrings("po", a.name);
    try std.testing.expect(a.namespace == null);

    const b = parseCommand("po kube-system");
    try std.testing.expectEqualStrings("po", b.name);
    try std.testing.expectEqualStrings("kube-system", b.namespace.?);

    const c = parseCommand("dp /fred");
    try std.testing.expectEqualStrings("dp", c.name);
    try std.testing.expectEqualStrings("fred", c.filter.?);

    const d = parseCommand("po app=web @prod");
    try std.testing.expectEqualStrings("po", d.name);
    try std.testing.expectEqualStrings("app=web", d.labels.?);
    try std.testing.expectEqualStrings("prod", d.context.?);
}

test "matchSearchable substring inverse fuzzy labels" {
    const cols = [_][]const u8{ "default", "nginx-abc" };
    try std.testing.expect(matchSearchable(&cols, "app=web", "nginx"));
    try std.testing.expect(!matchSearchable(&cols, "app=web", "redis"));
    try std.testing.expect(matchSearchable(&cols, "app=web", "!redis"));
    try std.testing.expect(!matchSearchable(&cols, "app=web", "!nginx"));
    try std.testing.expect(matchSearchable(&cols, "app=web", "-f ngx"));
    try std.testing.expect(!matchSearchable(&cols, "app=web", "-f zzz"));
    try std.testing.expect(matchSearchable(&cols, "app=web,env=prod", "-l app=web"));
    try std.testing.expect(!matchSearchable(&cols, "app=web", "-l app=db"));
    try std.testing.expect(matchSearchable(&cols, "app=web", ""));
    try std.testing.expect(matchSearchable(&cols, "app=web", "!"));
}

test "faults STATUS and READY" {
    try std.testing.expect(!isFault("Running", "1/1"));
    try std.testing.expect(isFault("CrashLoopBackOff", "1/1"));
    try std.testing.expect(isFault("Running", "0/1"));
    try std.testing.expect(isFault("Pending", null));
    try std.testing.expect(!isFault("Bound", null));
}

test "firstOwnerRef and viewForOwnerKind" {
    const allocator = std.testing.allocator;
    const json =
        \\{"metadata":{"ownerReferences":[{"kind":"ReplicaSet","name":"web-7d9f"}]}}
    ;
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    const owner = firstOwnerRef(parsed.value) orelse return error.MissingOwner;
    try std.testing.expectEqualStrings("ReplicaSet", owner.kind);
    try std.testing.expectEqualStrings("web-7d9f", owner.name);
    try std.testing.expectEqualStrings("replicasets", viewForOwnerKind(owner.kind).?);
    try std.testing.expect(viewForOwnerKind("SomeCRD") == null);
}

test "formatLabels flattens object" {
    const allocator = std.testing.allocator;
    const json = "{\"app\":\"nginx\",\"env\":\"prod\"}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    const s = try formatLabels(allocator, parsed.value);
    defer if (s.len > 0) allocator.free(s);
    try std.testing.expect(std.mem.indexOf(u8, s, "app=nginx") != null);
    try std.testing.expect(std.mem.indexOf(u8, s, "env=prod") != null);
}

test "specSuspend reads spec.suspend" {
    const allocator = std.testing.allocator;
    const json = "{\"spec\":{\"suspend\":true}}";
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expect(specSuspend(parsed.value));
}
