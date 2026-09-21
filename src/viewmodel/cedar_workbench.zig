// SPDX-License-Identifier: Apache-2.0
// Copyright Authors of C3S
//
// Assembles Cedar policy sets and renders the workbench's text panes. Pure: no
// process spawning, no cluster access. The orchestration that runs `cedar` lives in
// the request; everything here can be exercised without either.
//
// The k9s plugin wrote its readable output as an HTML file and opened it beside the
// terminal, because a k9s plugin cannot draw into k9s. c3s draws its own panes, so
// the equivalent output is text laid out for a terminal.

const std = @import("std");
const cedar_cli = @import("../services/CedarCli.zig");
const cedar_request = @import("cedar_request.zig");

/// What happened to one policy while assembling a set or scanning.
pub const PolicyStatus = enum {
    ok,
    parse_fail,
    fetch_error,
    too_large,
    /// Beyond the per-run policy cap.
    over_limit,

    pub fn label(self: PolicyStatus) []const u8 {
        return switch (self) {
            .ok => "OK",
            .parse_fail => "PARSE_FAIL",
            .fetch_error => "FETCH_ERROR",
            .too_large => "SKIP_TOO_LARGE",
            .over_limit => "SKIPPED (over limit)",
        };
    }

    /// Anything that is not a clean parse means the policy is missing from the set,
    /// which is what makes an authorization result untrustworthy.
    pub fn isEvidenceGap(self: PolicyStatus) bool {
        return self != .ok;
    }
};

pub const PolicyResult = struct {
    name: []const u8,
    status: PolicyStatus,
    /// Cedar's diagnostics for a failed parse, empty otherwise. Borrowed.
    detail: []const u8 = "",
};

/// Append one policy to a set, giving it an `@id` when it has none.
///
/// The id is what Cedar prints when it names the determining policies, so without
/// one the answer says "policy3" and the reviewer has to count. Policies that already
/// carry an `@id` annotation are left alone rather than double-annotated, which Cedar
/// rejects.
pub fn appendToPolicySet(
    allocator: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(u8),
    name: []const u8,
    content: []const u8,
) !void {
    if (!hasIdAnnotation(content)) {
        try out.appendSlice(allocator, "@id(");
        try cedar_request.appendJsonString(allocator, out, name);
        try out.appendSlice(allocator, ")\n");
    }
    try out.appendSlice(allocator, content);
    if (!std.mem.endsWith(u8, content, "\n")) try out.append(allocator, '\n');
    try out.append(allocator, '\n');
}

/// True when the source already carries an `@id(` annotation at the start of a
/// statement. A bare substring search would match `@id(` inside a string literal or a
/// comment and then skip an annotation the policy actually needs.
pub fn hasIdAnnotation(content: []const u8) bool {
    var rest = content;
    while (rest.len > 0) {
        const line_end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
        const line = std.mem.trim(u8, rest[0..line_end], " \t\r");
        if (std.mem.startsWith(u8, line, "@id(")) return true;
        // Annotations and comments precede the statement; once the statement itself
        // starts, any later `@id(` belongs to a different policy in the same file --
        // and a multi-statement policy already carries its own ids.
        if (line.len > 0 and !std.mem.startsWith(u8, line, "//") and !std.mem.startsWith(u8, line, "@")) {
            return false;
        }
        if (line_end == rest.len) break;
        rest = rest[line_end + 1 ..];
    }
    return false;
}

pub const ScanSummary = struct {
    results: []const PolicyResult,
    context: []const u8,
    /// True when the run stopped early or could not read every policy.
    truncated: bool = false,
};

/// Render the `Shift-A` scan pane: one line per policy, then a tally.
pub fn formatScanReport(allocator: std.mem.Allocator, summary: ScanSummary) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);

    var ok: usize = 0;
    var failed: usize = 0;
    var errored: usize = 0;
    for (summary.results) |result| {
        switch (result.status) {
            .ok => ok += 1,
            .parse_fail => failed += 1,
            else => errored += 1,
        }
    }

    try out.print(allocator, "Cedar policy scan (check-parse)  context={s}\n", .{summary.context});
    try out.print(
        allocator,
        "Limits: {d} policies, {d} bytes each\n\n",
        .{ cedar_cli.max_policies, cedar_cli.max_policy_bytes },
    );

    if (summary.results.len == 0) {
        try out.appendSlice(allocator, "No Cedar Policy objects in this cluster.\n");
        return out.toOwnedSlice(allocator);
    }

    for (summary.results) |result| {
        try out.print(allocator, "{s: <40}  {s}\n", .{ result.name, result.status.label() });
        if (result.detail.len > 0) try appendIndented(allocator, &out, result.detail, "    ");
    }

    try out.print(allocator, "\n{d} OK, {d} PARSE_FAIL", .{ ok, failed });
    if (errored > 0) try out.print(allocator, ", {d} ERROR", .{errored});
    try out.append(allocator, '\n');

    // Saying the scan was incomplete matters more than the tally: a clean-looking
    // count over a partial set is the misleading outcome.
    if (errored > 0 or summary.truncated) {
        try out.appendSlice(
            allocator,
            "\nINCOMPLETE: not every Policy object could be read, so this is not a full picture.\n",
        );
    }
    return out.toOwnedSlice(allocator);
}

pub const MatrixEntry = struct {
    verb: []const u8,
    decision: cedar_cli.Decision,
};

pub const CanIReport = struct {
    decision: cedar_cli.Decision,
    request: cedar_request.Request,
    context: []const u8,
    /// Policies that parsed and went into the set.
    included: []const []const u8,
    /// Policies that did not, and why. A non-empty list forces INDETERMINATE.
    gaps: []const PolicyResult,
    determining: []const u8,
    matrix: []const MatrixEntry,
    diagnostics: []const u8,
    /// Set when the user supplied one.
    schema_path: ?[]const u8 = null,
};

/// Render the `Shift-I` result pane: the question, the answer, the evidence it rests
/// on, and the other verbs for the same principal and resource.
pub fn formatCanIReport(allocator: std.mem.Allocator, report: CanIReport) ![]u8 {
    var out = std.ArrayListUnmanaged(u8).empty;
    errdefer out.deinit(allocator);

    const request = report.request;
    try out.print(allocator, "Can {s} {s} {s}?\n\n", .{
        request.principal_label,
        request.action_label,
        request.resource_label,
    });
    try out.print(allocator, "  {s}\n\n", .{report.decision.label()});

    if (report.decision == .indeterminate) {
        try out.appendSlice(
            allocator,
            "INDETERMINATE means the question was not answered, not that access is denied.\n" ++
                "Cedar was given an incomplete policy set or could not finish evaluating.\n\n",
        );
    }

    if (report.determining.len > 0) {
        try out.print(allocator, "Determined by: {s}\n\n", .{report.determining});
    }

    try out.appendSlice(allocator, "Request\n");
    try out.print(allocator, "  principal   {s}::\"{s}\"\n", .{ request.principal.type, request.principal.id });
    try out.print(allocator, "  action      {s}::\"{s}\"\n", .{ request.action.type, request.action.id });
    try out.print(allocator, "  resource    {s}::\"{s}\"\n", .{ request.resource.type, request.resource.id });
    if (request.mode == .k8s) {
        try out.print(allocator, "  apiGroup    {s}\n", .{if (request.api_group.len > 0) request.api_group else "(core)"});
        try out.print(allocator, "  namespace   {s}\n", .{if (request.namespace.len > 0) request.namespace else "(all)"});
        if (request.object_name.len > 0) try out.print(allocator, "  name        {s}\n", .{request.object_name});
        if (request.subresource.len > 0) try out.print(allocator, "  subresource {s}\n", .{request.subresource});
    }
    try out.print(allocator, "  context     {s}\n", .{report.context});
    if (report.schema_path) |schema| try out.print(allocator, "  schema      {s}\n", .{schema});
    try out.append(allocator, '\n');

    if (report.matrix.len > 0) {
        try out.appendSlice(allocator, "Other verbs, same principal and resource\n");
        for (report.matrix) |entry| {
            try out.print(allocator, "  {s: <8}  {s}\n", .{ entry.verb, entry.decision.label() });
        }
        try out.append(allocator, '\n');
    }

    try out.print(allocator, "Evidence: {d} policy object(s) evaluated\n", .{report.included.len});
    for (report.included) |name| try out.print(allocator, "  {s}\n", .{name});

    if (report.gaps.len > 0) {
        try out.print(allocator, "\nNot evaluated: {d}\n", .{report.gaps.len});
        for (report.gaps) |gap| {
            try out.print(allocator, "  {s: <40}  {s}\n", .{ gap.name, gap.status.label() });
        }
    }

    if (report.diagnostics.len > 0) {
        try out.appendSlice(allocator, "\ncedar output\n");
        try appendIndented(allocator, &out, report.diagnostics, "  ");
    }

    try out.appendSlice(
        allocator,
        "\nThis evaluates Cedar Policy objects with the official cedar CLI. " ++
            "It is not Kubernetes RBAC and does not call the admission webhook.\n",
    );
    return out.toOwnedSlice(allocator);
}

fn appendIndented(
    allocator: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(u8),
    text: []const u8,
    indent: []const u8,
) !void {
    var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, text, "\n"), '\n');
    while (lines.next()) |line| {
        try out.appendSlice(allocator, indent);
        try out.appendSlice(allocator, line);
        try out.append(allocator, '\n');
    }
}

// --- Tests ---

const testing = std.testing;

test "a policy without an id annotation gets one named after the object" {
    const a = testing.allocator;
    var set = std.ArrayListUnmanaged(u8).empty;
    defer set.deinit(a);

    try appendToPolicySet(a, &set, "permit-all", "permit(principal, action, resource);");
    try testing.expectEqualStrings(
        "@id(\"permit-all\")\npermit(principal, action, resource);\n\n",
        set.items,
    );
}

test "an existing id annotation is not duplicated" {
    const a = testing.allocator;
    var set = std.ArrayListUnmanaged(u8).empty;
    defer set.deinit(a);

    const content = "@id(\"already-named\")\npermit(principal, action, resource);\n";
    try appendToPolicySet(a, &set, "object-name", content);
    try testing.expectEqualStrings("@id(\"already-named\")\npermit(principal, action, resource);\n\n", set.items);
}

test "an id inside the policy body does not count as an annotation" {
    // A substring search finds `@id(` in this string literal and would then skip the
    // annotation, leaving the policy unnamed in Cedar's explanation.
    try testing.expect(!hasIdAnnotation(
        \\permit(principal, action, resource)
        \\when { resource.note == "@id(fake)" };
    ));
    // A comment before the annotation is still fine.
    try testing.expect(hasIdAnnotation("// a note\n@id(\"real\")\npermit(principal, action, resource);"));
    // Another annotation before it too.
    try testing.expect(hasIdAnnotation("@advice(\"x\")\n@id(\"real\")\npermit(principal, action, resource);"));
}

test "a policy name with a quote is escaped into the annotation" {
    const a = testing.allocator;
    var set = std.ArrayListUnmanaged(u8).empty;
    defer set.deinit(a);

    try appendToPolicySet(a, &set, "odd\"name", "permit(principal, action, resource);");
    try testing.expect(std.mem.startsWith(u8, set.items, "@id(\"odd\\\"name\")\n"));
}

test "a scan that could not read every policy says so" {
    const a = testing.allocator;
    const results = [_]PolicyResult{
        .{ .name = "good", .status = .ok },
        .{ .name = "broken", .status = .parse_fail, .detail = "unexpected token" },
        .{ .name = "huge", .status = .too_large },
    };
    const text = try formatScanReport(a, .{ .results = &results, .context = "kind-dev" });
    defer a.free(text);

    try testing.expect(std.mem.indexOf(u8, text, "1 OK, 1 PARSE_FAIL, 1 ERROR") != null);
    try testing.expect(std.mem.indexOf(u8, text, "INCOMPLETE") != null);
    try testing.expect(std.mem.indexOf(u8, text, "unexpected token") != null);
}

test "a fully readable scan is not labelled incomplete" {
    const a = testing.allocator;
    const results = [_]PolicyResult{
        .{ .name = "good", .status = .ok },
        .{ .name = "broken", .status = .parse_fail },
    };
    const text = try formatScanReport(a, .{ .results = &results, .context = "kind-dev" });
    defer a.free(text);

    // A parse failure is a finding, not a gap: the scan saw the policy and reported on
    // it. Only unreadable policies make the picture partial.
    try testing.expect(std.mem.indexOf(u8, text, "1 OK, 1 PARSE_FAIL\n") != null);
    try testing.expect(std.mem.indexOf(u8, text, "INCOMPLETE") == null);
}

test "an empty cluster scan says there is nothing rather than reporting zeroes" {
    const a = testing.allocator;
    const text = try formatScanReport(a, .{ .results = &.{}, .context = "kind-dev" });
    defer a.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "No Cedar Policy objects") != null);
}

test "the can-i pane states the question, the answer and the evidence" {
    const a = testing.allocator;
    var request = try cedar_request.build(a, .{
        .principal = "alice",
        .action = "get",
        .resource = "pods",
        .namespace = "kube-system",
    });
    defer request.deinit();

    const matrix = [_]MatrixEntry{
        .{ .verb = "get", .decision = .allow },
        .{ .verb = "delete", .decision = .deny },
    };
    const included = [_][]const u8{"permit-viewers"};

    const text = try formatCanIReport(a, .{
        .decision = .allow,
        .request = request,
        .context = "kind-dev",
        .included = &included,
        .gaps = &.{},
        .determining = "permit-viewers",
        .matrix = &matrix,
        .diagnostics = "ALLOW\n",
    });
    defer a.free(text);

    try testing.expect(std.mem.indexOf(u8, text, "Can alice get pods?") != null);
    try testing.expect(std.mem.indexOf(u8, text, "ALLOW") != null);
    try testing.expect(std.mem.indexOf(u8, text, "Determined by: permit-viewers") != null);
    try testing.expect(std.mem.indexOf(u8, text, "/api/v1/namespaces/kube-system/pods") != null);
    try testing.expect(std.mem.indexOf(u8, text, "delete    DENY") != null);
    try testing.expect(std.mem.indexOf(u8, text, "1 policy object(s) evaluated") != null);
    // Says what it is not, so the answer is not mistaken for an RBAC check.
    try testing.expect(std.mem.indexOf(u8, text, "not Kubernetes RBAC") != null);
}

test "an indeterminate pane explains that it is not a denial" {
    // The failure mode this guards: a reviewer reading INDETERMINATE as "denied" and
    // concluding the principal has no access, when nothing was actually decided.
    const a = testing.allocator;
    var request = try cedar_request.build(a, .{ .principal = "alice", .action = "get", .resource = "pods" });
    defer request.deinit();

    const gaps = [_]PolicyResult{.{ .name = "broken", .status = .parse_fail }};
    const text = try formatCanIReport(a, .{
        .decision = .indeterminate,
        .request = request,
        .context = "kind-dev",
        .included = &.{},
        .gaps = &gaps,
        .determining = "",
        .matrix = &.{},
        .diagnostics = "",
    });
    defer a.free(text);

    try testing.expect(std.mem.indexOf(u8, text, "not that access is denied") != null);
    try testing.expect(std.mem.indexOf(u8, text, "Not evaluated: 1") != null);
    try testing.expect(std.mem.indexOf(u8, text, "broken") != null);
}
