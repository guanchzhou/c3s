// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Cedar authorization request model. Pure: no App, no I/O, no process spawning.
//
// Turns "Can P do A on R?" into the three Cedar entity UIDs plus the entities JSON
// that `cedar authorize` needs. Two shapes are supported:
//
//   k8s    the frozen cedar-access-control-for-k8s request model -- k8s::User /
//          k8s::Action / k8s::Resource, RequestInfo attributes, and a resource UID
//          that is the canonical API path (`/api/v1/namespaces/kube-system/pods`).
//   cedar  plain Cedar entities for policies that are not about Kubernetes at all
//          (`User::"alice"`, `Action::"view"`, `Photo::"x"`).
//
// The k8s shape is deliberately frozen against
// cedar-policy/cedar-access-control-for-k8s, which is an unmaintained proof of
// concept. Attributes from other Cedar-for-Kubernetes efforts are NOT mixed in: a
// request that is half one model and half another authorizes against neither.

const std = @import("std");

/// Which entity vocabulary the request is expressed in.
pub const Mode = enum { k8s, cedar };

/// A Cedar entity UID, held unquoted. `format` renders the `Type::"id"` syntax.
pub const EntityUid = struct {
    type: []const u8,
    id: []const u8,

    /// Render as Cedar source text: `k8s::User::"alice"`. The id is JSON-escaped
    /// because Cedar string literals use JSON escaping, and an id can legitimately
    /// contain a quote (`system:serviceaccount:ns:odd"name`).
    pub fn render(self: EntityUid, allocator: std.mem.Allocator) ![]u8 {
        var out = std.ArrayListUnmanaged(u8).empty;
        errdefer out.deinit(allocator);
        try out.appendSlice(allocator, self.type);
        try out.appendSlice(allocator, "::");
        try appendJsonString(allocator, &out, self.id);
        return out.toOwnedSlice(allocator);
    }
};

/// A fully resolved authorization request, owning every string it holds.
pub const Request = struct {
    allocator: std.mem.Allocator,
    mode: Mode,

    principal: EntityUid,
    action: EntityUid,
    resource: EntityUid,

    /// Short display labels, for the status line and the report header.
    principal_label: []const u8,
    action_label: []const u8,
    resource_label: []const u8,

    /// Kubernetes RequestInfo. All empty in `.cedar` mode.
    api_group: []const u8,
    api_version: []const u8,
    namespace: []const u8,
    resource_plural: []const u8,
    object_name: []const u8,
    subresource: []const u8,

    pub fn deinit(self: *Request) void {
        const a = self.allocator;
        a.free(self.principal.type);
        a.free(self.principal.id);
        a.free(self.action.type);
        a.free(self.action.id);
        a.free(self.resource.type);
        a.free(self.resource.id);
        a.free(self.principal_label);
        a.free(self.action_label);
        a.free(self.resource_label);
        a.free(self.api_group);
        a.free(self.api_version);
        a.free(self.namespace);
        a.free(self.resource_plural);
        a.free(self.object_name);
        a.free(self.subresource);
    }
};

/// Raw, untrusted user input straight off the form.
pub const Input = struct {
    principal: []const u8,
    action: []const u8,
    resource: []const u8,
    namespace: []const u8 = "",
    api_group: []const u8 = "",
    api_version: []const u8 = "v1",
};

/// Parse the one-line can-i query into its fields.
///
/// The shape is `principal action resource [-n namespace] [-g apiGroup]`, which is the
/// `kubectl auth can-i` muscle memory a reviewer already has. It is one line rather than
/// a five-step wizard because this is the key people press repeatedly while reading a
/// policy, and five prompts per question is five times the friction.
///
/// Slices point into `line`; the caller owns it for as long as the result is used.
pub fn parseQuery(line: []const u8) Error!Input {
    var input = Input{ .principal = "", .action = "", .resource = "" };
    var positional: usize = 0;

    var fields = std.mem.tokenizeAny(u8, line, " \t");
    while (fields.next()) |field| {
        const flag: ?*[]const u8 =
            if (std.mem.eql(u8, field, "-n") or std.mem.eql(u8, field, "--namespace"))
                &input.namespace
            else if (std.mem.eql(u8, field, "-g") or std.mem.eql(u8, field, "--group"))
                &input.api_group
            else if (std.mem.eql(u8, field, "-v") or std.mem.eql(u8, field, "--api-version"))
                &input.api_version
            else
                null;
        if (flag) |slot| {
            slot.* = fields.next() orelse return Error.InvalidSegment;
            continue;
        }
        switch (positional) {
            0 => input.principal = field,
            1 => input.action = field,
            2 => input.resource = field,
            // A fourth bare word is a typo, not an extra field. Taking it silently
            // would authorize a question the user did not ask.
            else => return Error.InvalidSegment,
        }
        positional += 1;
    }

    if (input.principal.len == 0) return Error.EmptyPrincipal;
    if (input.action.len == 0) return Error.EmptyAction;
    if (input.resource.len == 0) return Error.EmptyResource;
    return input;
}

pub const Error = error{
    EmptyPrincipal,
    EmptyAction,
    EmptyResource,
    EmptyApiVersion,
    InvalidSegment,
    InvalidEntityUid,
    DuplicateEntityUid,
    MalformedEntities,
};

/// Kubernetes verbs, per the frozen PoC's Action vocabulary. A bare word from this
/// list is what tips an otherwise ambiguous request into `.k8s` mode.
const k8s_verbs = [_][]const u8{
    "get",    "list",     "watch",            "create",      "update", "patch",
    "delete", "proxy",    "deletecollection", "impersonate", "sign",   "approve",
    "bind",   "escalate", "attest",           "use",
};

/// The verbs the decision matrix evaluates alongside the asked-for one. Read verbs
/// first, then writes, which is the order a reviewer scans for escalation.
pub const matrix_verbs = [_][]const u8{
    "get", "list", "watch", "create", "update", "patch", "delete",
};

pub fn isK8sVerb(verb: []const u8) bool {
    for (k8s_verbs) |candidate| {
        if (std.mem.eql(u8, candidate, verb)) return true;
    }
    return false;
}

/// Path and name segments are interpolated into a URL-shaped resource UID and into
/// Cedar source, so they are restricted rather than escaped. Empty is allowed; the
/// caller decides which segments are mandatory.
pub fn validSegment(value: []const u8) bool {
    for (value) |c| {
        const ok = std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or c == '-' or c == ':';
        if (!ok) return false;
    }
    return true;
}

/// `pods`, `pods/mypod`, or `pods/mypod/log`.
pub const ResourceParts = struct {
    plural: []const u8,
    object_name: []const u8,
    subresource: []const u8,
};

pub fn splitResource(raw: []const u8) ResourceParts {
    const trimmed = trim(raw);
    const first = std.mem.indexOfScalar(u8, trimmed, '/') orelse
        return .{ .plural = trimmed, .object_name = "", .subresource = "" };
    const rest = trimmed[first + 1 ..];
    const second = std.mem.indexOfScalar(u8, rest, '/') orelse
        return .{ .plural = trimmed[0..first], .object_name = rest, .subresource = "" };
    return .{
        .plural = trimmed[0..first],
        .object_name = rest[0..second],
        .subresource = rest[second + 1 ..],
    };
}

/// The canonical API path the frozen PoC uses as the Resource entity id.
pub fn canonicalPath(
    allocator: std.mem.Allocator,
    api_group: []const u8,
    api_version: []const u8,
    namespace: []const u8,
    parts: ResourceParts,
) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);

    if (api_group.len > 0) {
        try out.appendSlice(allocator, "/apis/");
        try out.appendSlice(allocator, api_group);
        try out.append(allocator, '/');
    } else {
        try out.appendSlice(allocator, "/api/");
    }
    try out.appendSlice(allocator, api_version);

    if (namespace.len > 0) {
        try out.appendSlice(allocator, "/namespaces/");
        try out.appendSlice(allocator, namespace);
    }
    try out.append(allocator, '/');
    try out.appendSlice(allocator, parts.plural);
    if (parts.object_name.len > 0) {
        try out.append(allocator, '/');
        try out.appendSlice(allocator, parts.object_name);
    }
    if (parts.subresource.len > 0) {
        try out.append(allocator, '/');
        try out.appendSlice(allocator, parts.subresource);
    }
    return out.toOwnedSlice(allocator);
}

/// Decide which vocabulary the user meant. An explicit `Type::"id"` action or a
/// Kubernetes verb, namespace, or API group means Kubernetes; anything else is
/// plain Cedar.
pub fn detectMode(action_raw: []const u8, namespace: []const u8, api_group: []const u8) Mode {
    const action = trim(action_raw);
    if (std.mem.startsWith(u8, action, "k8s::Action::")) return .k8s;
    if (std.mem.indexOf(u8, action, "::") != null) return .cedar;
    if (isK8sVerb(action)) return .k8s;
    if (trim(namespace).len > 0 or trim(api_group).len > 0) return .k8s;
    return .cedar;
}

/// Build the three UIDs and the RequestInfo from raw input. Every returned string is
/// owned by the Request.
pub fn build(allocator: std.mem.Allocator, input: Input) (Error || std.mem.Allocator.Error)!Request {
    const principal_raw = trim(input.principal);
    const action_raw = trim(input.action);
    const resource_raw = trim(input.resource);
    const namespace = trim(input.namespace);
    const api_group = trim(input.api_group);
    const api_version = trim(input.api_version);

    if (principal_raw.len == 0) return Error.EmptyPrincipal;
    if (action_raw.len == 0) return Error.EmptyAction;
    if (resource_raw.len == 0) return Error.EmptyResource;

    const mode = detectMode(action_raw, namespace, api_group);

    var owner = RequestOwner.init(allocator);
    errdefer owner.deinit();

    if (mode == .k8s) {
        if (api_version.len == 0) return Error.EmptyApiVersion;

        const parts = splitResource(resource_raw);
        if (parts.plural.len == 0) return Error.EmptyResource;
        for ([_][]const u8{
            parts.plural, parts.object_name, parts.subresource,
            namespace,    api_group,         api_version,
        }) |segment| {
            if (!validSegment(segment)) return Error.InvalidSegment;
        }

        const path = try canonicalPath(allocator, api_group, api_version, namespace, parts);
        defer allocator.free(path);

        try owner.setPrincipal(try k8sPrincipal(allocator, principal_raw));
        try owner.setAction(try normalizeUid(allocator, "k8s::Action", action_raw));
        try owner.setResource(try dupeUid(allocator, .{ .type = "k8s::Resource", .id = path }));

        try owner.setRequestInfo(.{
            .api_group = api_group,
            .api_version = api_version,
            .namespace = namespace,
            .resource_plural = parts.plural,
            .object_name = parts.object_name,
            .subresource = parts.subresource,
        });
        try owner.setLabels(principal_raw, shortLabel(action_raw), parts.plural);
    } else {
        try owner.setPrincipal(try normalizeUid(allocator, "User", principal_raw));
        try owner.setAction(try normalizeUid(allocator, "Action", action_raw));
        try owner.setResource(try normalizeUid(allocator, "Resource", resource_raw));
        try owner.setRequestInfo(.{});
        try owner.setLabels(shortLabel(principal_raw), shortLabel(action_raw), shortLabel(resource_raw));
    }

    return owner.finish(mode);
}

/// `system:serviceaccount:ns:name` and `system:node:x` are distinct entity types in
/// the PoC model, not decorated user names. Getting this wrong silently authorizes
/// the wrong principal, so it is matched before the User fallback.
fn k8sPrincipal(allocator: std.mem.Allocator, raw: []const u8) !EntityUid {
    if (std.mem.indexOf(u8, raw, "::") != null) {
        return normalizeUid(allocator, "k8s::User", raw);
    }
    if (std.mem.startsWith(u8, raw, "system:serviceaccount:")) {
        // Needs both a namespace and a name after the prefix, or the entity's
        // attributes cannot be derived.
        const rest = raw["system:serviceaccount:".len..];
        const sep = std.mem.indexOfScalar(u8, rest, ':');
        if (sep != null and sep.? > 0 and sep.? + 1 < rest.len) {
            return dupeUid(allocator, .{ .type = "k8s::ServiceAccount", .id = raw });
        }
    }
    if (std.mem.startsWith(u8, raw, "system:node:") and raw.len > "system:node:".len) {
        return dupeUid(allocator, .{ .type = "k8s::Node", .id = raw });
    }
    return dupeUid(allocator, .{ .type = "k8s::User", .id = raw });
}

/// Accept `Type::"id"` verbatim, `Type/id` as a shorthand, and a bare word as an id
/// of the default type.
fn normalizeUid(allocator: std.mem.Allocator, default_type: []const u8, raw: []const u8) !EntityUid {
    if (std.mem.lastIndexOf(u8, raw, "::")) |sep| {
        const type_name = trim(raw[0..sep]);
        const id_text = trim(raw[sep + 2 ..]);
        if (type_name.len == 0 or id_text.len == 0) return Error.InvalidEntityUid;
        const id = if (id_text.len >= 2 and id_text[0] == '"' and id_text[id_text.len - 1] == '"')
            try parseJsonString(allocator, id_text)
        else
            try allocator.dupe(u8, id_text);
        errdefer allocator.free(id);
        return .{ .type = try allocator.dupe(u8, type_name), .id = id };
    }
    if (std.mem.indexOfScalar(u8, raw, '/')) |slash| {
        if (slash > 0 and std.ascii.isUpper(raw[0]) and slash + 1 < raw.len) {
            return dupeUid(allocator, .{ .type = raw[0..slash], .id = raw[slash + 1 ..] });
        }
    }
    return dupeUid(allocator, .{ .type = default_type, .id = raw });
}

fn dupeUid(allocator: std.mem.Allocator, uid: EntityUid) !EntityUid {
    const type_name = try allocator.dupe(u8, uid.type);
    errdefer allocator.free(type_name);
    return .{ .type = type_name, .id = try allocator.dupe(u8, uid.id) };
}

/// Everything after the last `::`, unquoted -- what a human calls the entity.
fn shortLabel(raw: []const u8) []const u8 {
    const trimmed = trim(raw);
    const sep = std.mem.lastIndexOf(u8, trimmed, "::") orelse return trimmed;
    return std.mem.trim(u8, trimmed[sep + 2 ..], "\"");
}

/// Accumulates the owned strings so a failure halfway through `build` frees exactly
/// what was allocated, rather than leaking the earlier UIDs.
const RequestOwner = struct {
    allocator: std.mem.Allocator,
    principal: ?EntityUid = null,
    action: ?EntityUid = null,
    resource: ?EntityUid = null,
    principal_label: ?[]const u8 = null,
    action_label: ?[]const u8 = null,
    resource_label: ?[]const u8 = null,
    info: ?OwnedInfo = null,

    const RequestInfo = struct {
        api_group: []const u8 = "",
        api_version: []const u8 = "",
        namespace: []const u8 = "",
        resource_plural: []const u8 = "",
        object_name: []const u8 = "",
        subresource: []const u8 = "",
    };

    const OwnedInfo = RequestInfo;

    fn init(allocator: std.mem.Allocator) RequestOwner {
        return .{ .allocator = allocator };
    }

    fn setPrincipal(self: *RequestOwner, uid: EntityUid) !void {
        self.principal = uid;
    }
    fn setAction(self: *RequestOwner, uid: EntityUid) !void {
        self.action = uid;
    }
    fn setResource(self: *RequestOwner, uid: EntityUid) !void {
        self.resource = uid;
    }

    fn setRequestInfo(self: *RequestOwner, info: RequestInfo) !void {
        const a = self.allocator;
        var owned = OwnedInfo{};
        errdefer freeInfo(a, &owned);
        owned.api_group = try a.dupe(u8, info.api_group);
        owned.api_version = try a.dupe(u8, info.api_version);
        owned.namespace = try a.dupe(u8, info.namespace);
        owned.resource_plural = try a.dupe(u8, info.resource_plural);
        owned.object_name = try a.dupe(u8, info.object_name);
        owned.subresource = try a.dupe(u8, info.subresource);
        self.info = owned;
    }

    fn setLabels(self: *RequestOwner, principal: []const u8, action: []const u8, resource: []const u8) !void {
        const a = self.allocator;
        self.principal_label = try a.dupe(u8, principal);
        self.action_label = try a.dupe(u8, action);
        self.resource_label = try a.dupe(u8, resource);
    }

    fn finish(self: *RequestOwner, mode: Mode) Request {
        const info = self.info.?;
        return .{
            .allocator = self.allocator,
            .mode = mode,
            .principal = self.principal.?,
            .action = self.action.?,
            .resource = self.resource.?,
            .principal_label = self.principal_label.?,
            .action_label = self.action_label.?,
            .resource_label = self.resource_label.?,
            .api_group = info.api_group,
            .api_version = info.api_version,
            .namespace = info.namespace,
            .resource_plural = info.resource_plural,
            .object_name = info.object_name,
            .subresource = info.subresource,
        };
    }

    fn deinit(self: *RequestOwner) void {
        const a = self.allocator;
        if (self.principal) |uid| {
            a.free(uid.type);
            a.free(uid.id);
        }
        if (self.action) |uid| {
            a.free(uid.type);
            a.free(uid.id);
        }
        if (self.resource) |uid| {
            a.free(uid.type);
            a.free(uid.id);
        }
        if (self.principal_label) |s| a.free(s);
        if (self.action_label) |s| a.free(s);
        if (self.resource_label) |s| a.free(s);
        if (self.info) |*info| freeInfo(a, info);
    }

    fn freeInfo(a: std.mem.Allocator, info: *OwnedInfo) void {
        a.free(info.api_group);
        a.free(info.api_version);
        a.free(info.namespace);
        a.free(info.resource_plural);
        a.free(info.object_name);
        a.free(info.subresource);
    }
};

/// Build the `--entities` JSON array.
///
/// `base` is an optional caller-supplied entities document, which is where group
/// membership and any other hierarchy comes from. Generated attributes win on
/// collision: the request being authorized is the more specific statement about the
/// principal and resource than a static file is.
///
/// A duplicate UID in `base` is an error rather than a silent last-one-wins, because
/// which of two conflicting definitions applied would decide the answer.
pub fn writeEntities(
    allocator: std.mem.Allocator,
    request: Request,
    base: ?[]const u8,
) (Error || std.mem.Allocator.Error || std.json.ParseError(std.json.Scanner))![]u8 {
    var entities = std.ArrayListUnmanaged(Entity).empty;
    defer {
        for (entities.items) |*entity| entity.deinit(allocator);
        entities.deinit(allocator);
    }

    var parsed: ?std.json.Parsed(std.json.Value) = null;
    defer if (parsed) |*p| p.deinit();

    if (base) |text| {
        parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
        const root = parsed.?.value;
        if (root != .array) return Error.MalformedEntities;
        for (root.array.items) |item| {
            if (item != .object) return Error.MalformedEntities;
            const uid = item.object.get("uid") orelse return Error.MalformedEntities;
            if (uid != .object) return Error.MalformedEntities;
            const type_value = uid.object.get("type") orelse return Error.MalformedEntities;
            const id_value = uid.object.get("id") orelse return Error.MalformedEntities;
            if (type_value != .string or id_value != .string) return Error.MalformedEntities;
            if (findEntity(entities.items, type_value.string, id_value.string) != null) {
                return Error.DuplicateEntityUid;
            }
            var entity = try Entity.fromJson(allocator, item.object, type_value.string, id_value.string);
            errdefer entity.deinit(allocator);
            try entities.append(allocator, entity);
        }
    }

    try mergeGenerated(allocator, &entities, request);

    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);
    try out.append(allocator, '[');
    for (entities.items, 0..) |entity, i| {
        if (i > 0) try out.append(allocator, ',');
        try entity.write(allocator, &out);
    }
    try out.appendSlice(allocator, "]\n");
    return out.toOwnedSlice(allocator);
}

/// One entity: a UID, an ordered attribute map, and whatever parents the base
/// document supplied.
///
/// Attribute values are held as raw JSON so a base file can carry types c3s has no
/// opinion about (numbers, records, sets) while the generated attributes are plain
/// strings. Keeping them in one ordered map is what makes "generated wins" an actual
/// overwrite; emitting both and trusting the reader to take the last duplicate key
/// produces a document `std.json` rejects outright.
const Entity = struct {
    type: []const u8,
    id: []const u8,
    /// Attribute names and their raw JSON values, in insertion order so the output is
    /// deterministic and diffable.
    attr_names: std.ArrayListUnmanaged([]const u8) = .empty,
    attr_values: std.ArrayListUnmanaged([]const u8) = .empty,
    parents_json: ?[]const u8 = null,

    fn fromJson(
        allocator: std.mem.Allocator,
        object: std.json.ObjectMap,
        type_name: []const u8,
        id: []const u8,
    ) !Entity {
        var entity = Entity{
            .type = try allocator.dupe(u8, type_name),
            .id = try allocator.dupe(u8, id),
        };
        errdefer entity.deinit(allocator);
        if (object.get("attrs")) |attrs| {
            if (attrs != .object) return Error.MalformedEntities;
            var it = attrs.object.iterator();
            while (it.next()) |field| {
                const encoded = try stringifyValue(allocator, field.value_ptr.*);
                defer allocator.free(encoded);
                try entity.setRawAttr(allocator, field.key_ptr.*, encoded);
            }
        }
        if (object.get("parents")) |parents| {
            if (parents != .array) return Error.MalformedEntities;
            entity.parents_json = try stringifyValue(allocator, parents);
        }
        return entity;
    }

    fn setAttr(self: *Entity, allocator: std.mem.Allocator, name: []const u8, value: []const u8) !void {
        var encoded = std.ArrayListUnmanaged(u8).empty;
        defer encoded.deinit(allocator);
        try appendJsonString(allocator, &encoded, value);
        try self.setRawAttr(allocator, name, encoded.items);
    }

    fn setRawAttr(
        self: *Entity,
        allocator: std.mem.Allocator,
        name: []const u8,
        json_value: []const u8,
    ) !void {
        const owned_value = try allocator.dupe(u8, json_value);
        errdefer allocator.free(owned_value);

        for (self.attr_names.items, 0..) |existing, i| {
            if (std.mem.eql(u8, existing, name)) {
                allocator.free(self.attr_values.items[i]);
                self.attr_values.items[i] = owned_value;
                return;
            }
        }

        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);
        try self.attr_names.ensureUnusedCapacity(allocator, 1);
        try self.attr_values.ensureUnusedCapacity(allocator, 1);
        self.attr_names.appendAssumeCapacity(owned_name);
        self.attr_values.appendAssumeCapacity(owned_value);
    }

    fn write(self: Entity, allocator: std.mem.Allocator, out: *std.ArrayListUnmanaged(u8)) !void {
        try out.appendSlice(allocator, "{\"uid\":{\"type\":");
        try appendJsonString(allocator, out, self.type);
        try out.appendSlice(allocator, ",\"id\":");
        try appendJsonString(allocator, out, self.id);
        try out.appendSlice(allocator, "},\"attrs\":{");
        for (self.attr_names.items, self.attr_values.items, 0..) |name, value, i| {
            if (i > 0) try out.append(allocator, ',');
            try appendJsonString(allocator, out, name);
            try out.append(allocator, ':');
            try out.appendSlice(allocator, value);
        }
        try out.appendSlice(allocator, "},\"parents\":");
        try out.appendSlice(allocator, self.parents_json orelse "[]");
        try out.append(allocator, '}');
    }

    fn deinit(self: *Entity, allocator: std.mem.Allocator) void {
        allocator.free(self.type);
        allocator.free(self.id);
        for (self.attr_names.items) |name| allocator.free(name);
        for (self.attr_values.items) |value| allocator.free(value);
        self.attr_names.deinit(allocator);
        self.attr_values.deinit(allocator);
        if (self.parents_json) |json| allocator.free(json);
    }
};

fn findEntity(entities: []Entity, type_name: []const u8, id: []const u8) ?usize {
    for (entities, 0..) |entity, i| {
        if (std.mem.eql(u8, entity.type, type_name) and std.mem.eql(u8, entity.id, id)) return i;
    }
    return null;
}

fn mergeGenerated(
    allocator: std.mem.Allocator,
    entities: *std.ArrayListUnmanaged(Entity),
    request: Request,
) !void {
    // Indices, not pointers: every upsert can append and move the backing array, and
    // a stale `*Entity` would write attributes into freed memory.
    const principal_index = try upsert(allocator, entities, request.principal);
    const action_index = try upsert(allocator, entities, request.action);
    const resource_index = try upsert(allocator, entities, request.resource);
    _ = action_index;

    if (request.mode != .k8s) return;

    const principal = &entities.items[principal_index];
    if (std.mem.eql(u8, principal.type, "k8s::User")) {
        try principal.setAttr(allocator, "name", principal.id);
    } else if (std.mem.eql(u8, principal.type, "k8s::ServiceAccount")) {
        const rest = principal.id["system:serviceaccount:".len..];
        const sep = std.mem.indexOfScalar(u8, rest, ':').?;
        try principal.setAttr(allocator, "namespace", rest[0..sep]);
        try principal.setAttr(allocator, "name", rest[sep + 1 ..]);
    } else if (std.mem.eql(u8, principal.type, "k8s::Node")) {
        try principal.setAttr(allocator, "name", principal.id["system:node:".len..]);
    }

    const resource = &entities.items[resource_index];
    try resource.setAttr(allocator, "apiGroup", request.api_group);
    try resource.setAttr(allocator, "resource", request.resource_plural);
    if (request.namespace.len > 0) try resource.setAttr(allocator, "namespace", request.namespace);
    if (request.object_name.len > 0) try resource.setAttr(allocator, "name", request.object_name);
    if (request.subresource.len > 0) try resource.setAttr(allocator, "subresource", request.subresource);
}

fn upsert(
    allocator: std.mem.Allocator,
    entities: *std.ArrayListUnmanaged(Entity),
    uid: EntityUid,
) !usize {
    if (findEntity(entities.items, uid.type, uid.id)) |existing| return existing;
    var entity = Entity{
        .type = try allocator.dupe(u8, uid.type),
        .id = try allocator.dupe(u8, uid.id),
    };
    errdefer entity.deinit(allocator);
    try entities.append(allocator, entity);
    return entities.items.len - 1;
}

fn stringifyValue(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, value, .{});
}

pub fn appendJsonString(
    allocator: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(u8),
    text: []const u8,
) !void {
    try out.append(allocator, '"');
    for (text) |c| {
        switch (c) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => {
                if (c < 0x20) {
                    try out.print(allocator, "\\u{x:0>4}", .{c});
                } else {
                    try out.append(allocator, c);
                }
            },
        }
    }
    try out.append(allocator, '"');
}

fn parseJsonString(allocator: std.mem.Allocator, quoted: []const u8) ![]u8 {
    const parsed = std.json.parseFromSlice([]const u8, allocator, quoted, .{}) catch
        return Error.InvalidEntityUid;
    defer parsed.deinit();
    return allocator.dupe(u8, parsed.value);
}

fn trim(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r\n");
}

// --- Tests ---

const testing = std.testing;

test "the can-i line parses into positional fields and flags" {
    const query = try parseQuery("  alice  list pods -n kube-system -g apps  ");
    try std.testing.expectEqualStrings("alice", query.principal);
    try std.testing.expectEqualStrings("list", query.action);
    try std.testing.expectEqualStrings("pods", query.resource);
    try std.testing.expectEqualStrings("kube-system", query.namespace);
    try std.testing.expectEqualStrings("apps", query.api_group);
    try std.testing.expectEqualStrings("v1", query.api_version);
}

test "a flag without a value, or a stray fourth word, is refused rather than guessed" {
    try std.testing.expectError(Error.InvalidSegment, parseQuery("alice list pods -n"));
    try std.testing.expectError(Error.InvalidSegment, parseQuery("alice list pods extra"));
}

test "a can-i line missing a field names the field" {
    try std.testing.expectError(Error.EmptyPrincipal, parseQuery("   "));
    try std.testing.expectError(Error.EmptyAction, parseQuery("alice"));
    try std.testing.expectError(Error.EmptyResource, parseQuery("alice list"));
}

test "a parsed can-i line builds the request it describes" {
    const query = try parseQuery("system:serviceaccount:team:ci create deployments -n team -g apps");
    var request = try build(std.testing.allocator, query);
    defer request.deinit();
    try std.testing.expectEqual(Mode.k8s, request.mode);
    try std.testing.expectEqualStrings("k8s::ServiceAccount", request.principal.type);
    try std.testing.expectEqualStrings("/apis/apps/v1/namespaces/team/deployments", request.resource.id);
}

test "a bare Kubernetes verb selects the k8s vocabulary" {
    try testing.expectEqual(Mode.k8s, detectMode("get", "", ""));
    try testing.expectEqual(Mode.k8s, detectMode("k8s::Action::\"get\"", "", ""));
    // A namespace or API group is Kubernetes even when the verb is not a known one.
    try testing.expectEqual(Mode.k8s, detectMode("frobnicate", "kube-system", ""));
    try testing.expectEqual(Mode.k8s, detectMode("frobnicate", "", "apps"));
}

test "a plain Cedar action stays in the Cedar vocabulary" {
    try testing.expectEqual(Mode.cedar, detectMode("view", "", ""));
    try testing.expectEqual(Mode.cedar, detectMode("Action::\"view\"", "", ""));
}

test "resource splits into plural, object and subresource" {
    const bare = splitResource("pods");
    try testing.expectEqualStrings("pods", bare.plural);
    try testing.expectEqualStrings("", bare.object_name);
    try testing.expectEqualStrings("", bare.subresource);

    const named = splitResource("pods/mypod");
    try testing.expectEqualStrings("pods", named.plural);
    try testing.expectEqualStrings("mypod", named.object_name);
    try testing.expectEqualStrings("", named.subresource);

    const sub = splitResource("pods/mypod/log");
    try testing.expectEqualStrings("pods", sub.plural);
    try testing.expectEqualStrings("mypod", sub.object_name);
    try testing.expectEqualStrings("log", sub.subresource);
}

test "canonical path distinguishes core from grouped APIs" {
    const a = testing.allocator;

    const core = try canonicalPath(a, "", "v1", "kube-system", splitResource("pods"));
    defer a.free(core);
    try testing.expectEqualStrings("/api/v1/namespaces/kube-system/pods", core);

    const grouped = try canonicalPath(a, "apps", "v1", "", splitResource("deployments/web"));
    defer a.free(grouped);
    try testing.expectEqualStrings("/apis/apps/v1/deployments/web", grouped);

    const sub = try canonicalPath(a, "", "v1", "default", splitResource("pods/web/log"));
    defer a.free(sub);
    try testing.expectEqualStrings("/api/v1/namespaces/default/pods/web/log", sub);
}

test "a service account principal is its own entity type, not a decorated user" {
    const a = testing.allocator;
    var request = try build(a, .{
        .principal = "system:serviceaccount:kube-system:coredns",
        .action = "get",
        .resource = "pods",
    });
    defer request.deinit();

    try testing.expectEqualStrings("k8s::ServiceAccount", request.principal.type);
    try testing.expectEqualStrings("system:serviceaccount:kube-system:coredns", request.principal.id);
}

test "a node principal is recognised, and a lookalike is not" {
    const a = testing.allocator;

    var node = try build(a, .{ .principal = "system:node:ip-10-0-0-1", .action = "get", .resource = "pods" });
    defer node.deinit();
    try testing.expectEqualStrings("k8s::Node", node.principal.type);

    // A truncated prefix has no name to put in the entity, so it is a plain user.
    var truncated = try build(a, .{ .principal = "system:node:", .action = "get", .resource = "pods" });
    defer truncated.deinit();
    try testing.expectEqualStrings("k8s::User", truncated.principal.type);

    // Same for a service account missing the name half.
    var partial = try build(a, .{ .principal = "system:serviceaccount:onlyns", .action = "get", .resource = "pods" });
    defer partial.deinit();
    try testing.expectEqualStrings("k8s::User", partial.principal.type);
}

test "the resource UID is the canonical API path" {
    const a = testing.allocator;
    var request = try build(a, .{
        .principal = "alice",
        .action = "get",
        .resource = "pods/web/log",
        .namespace = "default",
    });
    defer request.deinit();

    try testing.expectEqual(Mode.k8s, request.mode);
    try testing.expectEqualStrings("k8s::Resource", request.resource.type);
    try testing.expectEqualStrings("/api/v1/namespaces/default/pods/web/log", request.resource.id);
    try testing.expectEqualStrings("k8s::Action", request.action.type);
    try testing.expectEqualStrings("get", request.action.id);
    try testing.expectEqualStrings("pods", request.resource_label);
}

test "short Cedar names keep their plain types" {
    const a = testing.allocator;
    var request = try build(a, .{ .principal = "alice", .action = "view", .resource = "Photo/x" });
    defer request.deinit();

    try testing.expectEqual(Mode.cedar, request.mode);
    try testing.expectEqualStrings("User", request.principal.type);
    try testing.expectEqualStrings("alice", request.principal.id);
    try testing.expectEqualStrings("Photo", request.resource.type);
    try testing.expectEqualStrings("x", request.resource.id);
}

test "a fully qualified entity UID is taken as written" {
    const a = testing.allocator;
    var request = try build(a, .{
        .principal = "MyApp::User::\"alice\"",
        .action = "MyApp::Action::\"view\"",
        .resource = "MyApp::Photo::\"vacation.jpg\"",
    });
    defer request.deinit();

    try testing.expectEqualStrings("MyApp::User", request.principal.type);
    try testing.expectEqualStrings("alice", request.principal.id);
    try testing.expectEqualStrings("vacation.jpg", request.resource.id);
    try testing.expectEqualStrings("vacation.jpg", request.resource_label);
}

test "rendering a UID escapes the id" {
    const a = testing.allocator;
    const rendered = try (EntityUid{ .type = "k8s::User", .id = "od\"d" }).render(a);
    defer a.free(rendered);
    try testing.expectEqualStrings("k8s::User::\"od\\\"d\"", rendered);
}

test "a segment that could break out of the path is refused" {
    const a = testing.allocator;
    // A slash-bearing namespace would rewrite the resource path into a different
    // object, so the request is refused rather than sanitized into something the user
    // did not ask about.
    try testing.expectError(Error.InvalidSegment, build(a, .{
        .principal = "alice",
        .action = "get",
        .resource = "pods",
        .namespace = "default/../kube-system",
    }));
    try testing.expectError(Error.InvalidSegment, build(a, .{
        .principal = "alice",
        .action = "get",
        .resource = "pods?x=1",
        .namespace = "default",
    }));
}

test "empty input is refused field by field" {
    const a = testing.allocator;
    try testing.expectError(Error.EmptyPrincipal, build(a, .{ .principal = "  ", .action = "get", .resource = "pods" }));
    try testing.expectError(Error.EmptyAction, build(a, .{ .principal = "alice", .action = "", .resource = "pods" }));
    try testing.expectError(Error.EmptyResource, build(a, .{ .principal = "alice", .action = "get", .resource = "" }));
    try testing.expectError(Error.EmptyApiVersion, build(a, .{
        .principal = "alice",
        .action = "get",
        .resource = "pods",
        .api_version = "",
    }));
}

test "generated entities carry the RequestInfo attributes" {
    const a = testing.allocator;
    var request = try build(a, .{
        .principal = "alice",
        .action = "get",
        .resource = "pods/web/log",
        .namespace = "default",
    });
    defer request.deinit();

    const json = try writeEntities(a, request, null);
    defer a.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, a, json, .{});
    defer parsed.deinit();
    try testing.expectEqual(@as(usize, 3), parsed.value.array.items.len);

    const resource = parsed.value.array.items[2].object;
    const attrs = resource.get("attrs").?.object;
    try testing.expectEqualStrings("pods", attrs.get("resource").?.string);
    try testing.expectEqualStrings("default", attrs.get("namespace").?.string);
    try testing.expectEqualStrings("web", attrs.get("name").?.string);
    try testing.expectEqualStrings("log", attrs.get("subresource").?.string);
    try testing.expectEqualStrings("", attrs.get("apiGroup").?.string);

    const principal = parsed.value.array.items[0].object;
    try testing.expectEqualStrings("alice", principal.get("attrs").?.object.get("name").?.string);
}

test "a base entities file supplies parents, and generated attributes win" {
    const a = testing.allocator;
    var request = try build(a, .{ .principal = "alice", .action = "get", .resource = "pods" });
    defer request.deinit();

    const base =
        \\[{"uid":{"type":"k8s::User","id":"alice"},
        \\  "attrs":{"name":"stale","extra":"kept"},
        \\  "parents":[{"type":"k8s::Group","id":"viewers"}]}]
    ;
    const json = try writeEntities(a, request, base);
    defer a.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, a, json, .{});
    defer parsed.deinit();

    const principal = parsed.value.array.items[0].object;
    const attrs = principal.get("attrs").?.object;
    // The request says who the principal is; the file only decorated it.
    try testing.expectEqualStrings("alice", attrs.get("name").?.string);
    try testing.expectEqualStrings("kept", attrs.get("extra").?.string);
    // Hierarchy is the reason to supply a file at all, so it must survive.
    const parents = principal.get("parents").?.array;
    try testing.expectEqual(@as(usize, 1), parents.items.len);
    try testing.expectEqualStrings("viewers", parents.items[0].object.get("id").?.string);
}

test "non-string attributes from the entities file survive the merge" {
    // c3s only generates string attributes, but a real entities file carries numbers,
    // records and sets. Re-encoding those as strings would change what the policy sees.
    const a = testing.allocator;
    var request = try build(a, .{ .principal = "alice", .action = "get", .resource = "pods" });
    defer request.deinit();

    const base =
        \\[{"uid":{"type":"k8s::User","id":"alice"},
        \\  "attrs":{"level":3,"tags":["a","b"],"meta":{"k":true}},
        \\  "parents":[]}]
    ;
    const json = try writeEntities(a, request, base);
    defer a.free(json);

    const parsed = try std.json.parseFromSlice(std.json.Value, a, json, .{});
    defer parsed.deinit();

    const attrs = parsed.value.array.items[0].object.get("attrs").?.object;
    try testing.expectEqual(@as(i64, 3), attrs.get("level").?.integer);
    try testing.expectEqual(@as(usize, 2), attrs.get("tags").?.array.items.len);
    try testing.expect(attrs.get("meta").?.object.get("k").?.bool);
    try testing.expectEqualStrings("alice", attrs.get("name").?.string);
}

test "a duplicate UID in the entities file is an error, not last-one-wins" {
    const a = testing.allocator;
    var request = try build(a, .{ .principal = "alice", .action = "view", .resource = "Photo/x" });
    defer request.deinit();

    const base =
        \\[{"uid":{"type":"User","id":"alice"},"attrs":{},"parents":[]},
        \\ {"uid":{"type":"User","id":"alice"},"attrs":{},"parents":[]}]
    ;
    try testing.expectError(Error.DuplicateEntityUid, writeEntities(a, request, base));
}

test "a malformed entities file is an error rather than a partial document" {
    const a = testing.allocator;
    var request = try build(a, .{ .principal = "alice", .action = "view", .resource = "Photo/x" });
    defer request.deinit();

    try testing.expectError(Error.MalformedEntities, writeEntities(a, request, "{}"));
    try testing.expectError(Error.MalformedEntities, writeEntities(a, request, "[{\"uid\":\"nope\"}]"));
    try testing.expectError(Error.MalformedEntities, writeEntities(a, request, "[{\"uid\":{\"type\":1,\"id\":\"x\"}}]"));
}
