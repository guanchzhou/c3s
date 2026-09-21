const std = @import("std");
const klient = @import("klient");

pub const table_accept = "application/json;as=Table;v=v1;g=meta.k8s.io";

pub const Descriptor = struct {
    group: []u8,
    version: []u8,
    plural: []u8,
    kind: []u8,
    namespaced: bool,

    pub fn deinit(self: *Descriptor, allocator: std.mem.Allocator) void {
        allocator.free(self.group);
        allocator.free(self.version);
        allocator.free(self.plural);
        allocator.free(self.kind);
        self.* = undefined;
    }

    pub fn listPath(
        self: Descriptor,
        allocator: std.mem.Allocator,
        namespace: ?[]const u8,
        all_namespaces: bool,
    ) ![]u8 {
        if (self.namespaced and !all_namespaces) {
            return std.fmt.allocPrint(
                allocator,
                "/apis/{s}/{s}/namespaces/{s}/{s}",
                .{ self.group, self.version, namespace orelse "default", self.plural },
            );
        }
        return std.fmt.allocPrint(
            allocator,
            "/apis/{s}/{s}/{s}",
            .{ self.group, self.version, self.plural },
        );
    }
};

pub fn resolve(
    allocator: std.mem.Allocator,
    discovery: klient.Discovery,
    query: []const u8,
) !?Descriptor {
    const groups = try discovery.groups();
    defer groups.deinit();

    var suffix_match: ?Descriptor = null;
    errdefer if (suffix_match) |*descriptor| descriptor.deinit(allocator);

    for (groups.value.groups) |group| {
        const version = preferredVersion(group) orelse continue;
        const resources = discovery.resources(group.name, version) catch continue;
        defer resources.deinit();

        for (resources.value.resources) |resource| {
            if (std.mem.indexOfScalar(u8, resource.name, '/') != null) continue;
            if (!hasVerb(resource.verbs, "list")) continue;

            if (matchesExact(query, group.name, resource)) {
                const exact = try cloneDescriptor(allocator, group.name, version, resource);
                if (suffix_match) |*descriptor| descriptor.deinit(allocator);
                suffix_match = null;
                return exact;
            }
            if (!matchesUniqueSuffix(query, resource)) continue;

            if (suffix_match != null) {
                suffix_match.?.deinit(allocator);
                suffix_match = null;
                return error.AmbiguousResource;
            }
            suffix_match = try cloneDescriptor(allocator, group.name, version, resource);
        }
    }
    return suffix_match;
}

/// Resolve from `kubectl api-resources`' preferred-resource catalog. This avoids
/// issuing one HTTP request per API group on the UI thread while preserving the
/// same server-discovery semantics.
pub fn resolveApiResources(
    allocator: std.mem.Allocator,
    output: []const u8,
    query: []const u8,
) !?Descriptor {
    var lines = std.mem.splitScalar(u8, output, '\n');
    const header = lines.next() orelse return null;
    const offsets = apiResourceOffsets(header) orelse return error.InvalidDiscoveryOutput;
    var suffix_match: ?Descriptor = null;
    errdefer if (suffix_match) |*descriptor| descriptor.deinit(allocator);

    while (lines.next()) |line| {
        if (std.mem.trim(u8, line, " \t\r").len == 0) continue;
        const cells = apiResourceCells(line, offsets);
        const slash = std.mem.lastIndexOfScalar(u8, cells[2], '/') orelse continue;
        const group = cells[2][0..slash];
        const version = cells[2][slash + 1 ..];
        if (group.len == 0 or version.len == 0) continue;

        const exact = eqlIgnoreCase(query, cells[0]) or
            eqlIgnoreCase(query, cells[4]) or
            commaListContains(cells[1], query) or
            qualifiedMatches(query, cells[0], group);
        if (exact) {
            const exact_match = try cloneRawDescriptor(
                allocator,
                group,
                version,
                cells[0],
                cells[4],
                std.mem.eql(u8, cells[3], "true"),
            );
            if (suffix_match) |*descriptor| descriptor.deinit(allocator);
            suffix_match = null;
            return exact_match;
        }
        if (query.len < 8 or cells[0].len <= query.len or
            !std.ascii.eqlIgnoreCase(cells[0][cells[0].len - query.len ..], query))
            continue;
        if (suffix_match != null) {
            suffix_match.?.deinit(allocator);
            suffix_match = null;
            return error.AmbiguousResource;
        }
        suffix_match = try cloneRawDescriptor(
            allocator,
            group,
            version,
            cells[0],
            cells[4],
            std.mem.eql(u8, cells[3], "true"),
        );
    }
    return suffix_match;
}

const ApiResourceOffsets = [5]usize;

fn apiResourceOffsets(header: []const u8) ?ApiResourceOffsets {
    const labels = [_][]const u8{ "NAME", "SHORTNAMES", "APIVERSION", "NAMESPACED", "KIND" };
    var offsets: ApiResourceOffsets = undefined;
    var from: usize = 0;
    for (labels, 0..) |label, index| {
        offsets[index] = std.mem.indexOfPos(u8, header, from, label) orelse return null;
        from = offsets[index] + label.len;
    }
    return offsets;
}

fn apiResourceCells(line: []const u8, offsets: ApiResourceOffsets) [5][]const u8 {
    var cells: [5][]const u8 = undefined;
    for (&cells, 0..) |*cell, index| {
        const start = @min(offsets[index], line.len);
        const end = if (index + 1 < offsets.len)
            @min(offsets[index + 1], line.len)
        else
            line.len;
        cell.* = std.mem.trim(u8, line[start..end], " \t\r");
    }
    return cells;
}

fn commaListContains(list: []const u8, query: []const u8) bool {
    var names = std.mem.splitScalar(u8, list, ',');
    while (names.next()) |name| {
        if (eqlIgnoreCase(name, query)) return true;
    }
    return false;
}

fn qualifiedMatches(
    query: []const u8,
    plural: []const u8,
    group: []const u8,
) bool {
    var buffer: [512]u8 = undefined;
    const qualified = std.fmt.bufPrint(&buffer, "{s}.{s}", .{ plural, group }) catch
        return false;
    return eqlIgnoreCase(query, qualified);
}

fn cloneRawDescriptor(
    allocator: std.mem.Allocator,
    group: []const u8,
    version: []const u8,
    plural: []const u8,
    kind: []const u8,
    namespaced: bool,
) !Descriptor {
    const owned_group = try allocator.dupe(u8, group);
    errdefer allocator.free(owned_group);
    const owned_version = try allocator.dupe(u8, version);
    errdefer allocator.free(owned_version);
    const owned_plural = try allocator.dupe(u8, plural);
    errdefer allocator.free(owned_plural);
    const owned_kind = try allocator.dupe(u8, kind);
    return .{
        .group = owned_group,
        .version = owned_version,
        .plural = owned_plural,
        .kind = owned_kind,
        .namespaced = namespaced,
    };
}

fn preferredVersion(group: klient.discovery.APIGroup) ?[]const u8 {
    if (group.preferredVersion) |preferred| {
        if (preferred.version.len > 0) return preferred.version;
    }
    if (group.versions.len > 0 and group.versions[0].version.len > 0)
        return group.versions[0].version;
    return null;
}

fn hasVerb(verbs: []const []const u8, expected: []const u8) bool {
    for (verbs) |verb| {
        if (std.mem.eql(u8, verb, expected)) return true;
    }
    return false;
}

fn matchesExact(
    query: []const u8,
    group: []const u8,
    resource: klient.discovery.APIResource,
) bool {
    if (eqlIgnoreCase(query, resource.name) or eqlIgnoreCase(query, resource.kind))
        return true;
    if (resource.singularName) |singular| {
        if (eqlIgnoreCase(query, singular)) return true;
    }
    for (resource.shortNames) |short_name| {
        if (eqlIgnoreCase(query, short_name)) return true;
    }
    var qualified_buffer: [512]u8 = undefined;
    const qualified = std.fmt.bufPrint(
        &qualified_buffer,
        "{s}.{s}",
        .{ resource.name, group },
    ) catch return false;
    return eqlIgnoreCase(query, qualified);
}

fn matchesUniqueSuffix(query: []const u8, resource: klient.discovery.APIResource) bool {
    if (query.len < 8 or resource.name.len <= query.len) return false;
    const offset = resource.name.len - query.len;
    return std.ascii.eqlIgnoreCase(resource.name[offset..], query);
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

fn cloneDescriptor(
    allocator: std.mem.Allocator,
    group: []const u8,
    version: []const u8,
    resource: klient.discovery.APIResource,
) !Descriptor {
    const owned_group = try allocator.dupe(u8, group);
    errdefer allocator.free(owned_group);
    const owned_version = try allocator.dupe(u8, version);
    errdefer allocator.free(owned_version);
    const owned_plural = try allocator.dupe(u8, resource.name);
    errdefer allocator.free(owned_plural);
    const owned_kind = try allocator.dupe(u8, resource.kind);
    return .{
        .group = owned_group,
        .version = owned_version,
        .plural = owned_plural,
        .kind = owned_kind,
        .namespaced = resource.namespaced,
    };
}

pub const TableData = struct {
    columns: [][]u8,
    rows: []Row,
    allocator: std.mem.Allocator,

    pub const Row = struct {
        cells: [][]u8,
        name: []u8,
        namespace: []u8,
    };

    pub fn deinit(self: *TableData) void {
        for (self.columns) |column| self.allocator.free(column);
        self.allocator.free(self.columns);
        for (self.rows) |row| {
            for (row.cells) |cell| self.allocator.free(cell);
            self.allocator.free(row.cells);
            self.allocator.free(row.name);
            self.allocator.free(row.namespace);
        }
        self.allocator.free(self.rows);
        self.* = undefined;
    }

    pub fn prependNamespaceColumn(self: *TableData) !void {
        const new_columns = try self.allocator.alloc([]u8, self.columns.len + 1);
        errdefer self.allocator.free(new_columns);
        new_columns[0] = try self.allocator.dupe(u8, "Namespace");
        errdefer self.allocator.free(new_columns[0]);
        @memcpy(new_columns[1..], self.columns);

        const replacement_cells = try self.allocator.alloc([][]u8, self.rows.len);
        defer self.allocator.free(replacement_cells);
        var prepared: usize = 0;
        errdefer for (replacement_cells[0..prepared]) |cells| {
            self.allocator.free(cells[0]);
            self.allocator.free(cells);
        };
        for (self.rows, 0..) |row, index| {
            const cells = try self.allocator.alloc([]u8, row.cells.len + 1);
            errdefer self.allocator.free(cells);
            cells[0] = try self.allocator.dupe(u8, row.namespace);
            @memcpy(cells[1..], row.cells);
            replacement_cells[index] = cells;
            prepared += 1;
        }
        for (self.rows, replacement_cells) |*row, cells| {
            self.allocator.free(row.cells);
            row.cells = cells;
        }

        self.allocator.free(self.columns);
        self.columns = new_columns;
    }
};

const WireTable = struct {
    kind: []const u8 = "",
    columnDefinitions: []ColumnDefinition = &.{},
    rows: []WireRow = &.{},

    const ColumnDefinition = struct {
        name: []const u8 = "",
    };

    const WireRow = struct {
        cells: []std.json.Value = &.{},
        object: ?std.json.Value = null,
    };
};

pub fn parseTable(allocator: std.mem.Allocator, body: []const u8) !TableData {
    const parsed = try std.json.parseFromSlice(WireTable, allocator, body, .{
        .ignore_unknown_fields = true,
        .allocate = .alloc_always,
    });
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value.kind, "Table"))
        return error.InvalidTableResponse;

    var columns = try allocator.alloc([]u8, parsed.value.columnDefinitions.len);
    var columns_done: usize = 0;
    errdefer {
        for (columns[0..columns_done]) |column| allocator.free(column);
        allocator.free(columns);
    }
    for (parsed.value.columnDefinitions, 0..) |definition, index| {
        columns[index] = try allocator.dupe(u8, definition.name);
        columns_done += 1;
    }

    var rows = try allocator.alloc(TableData.Row, parsed.value.rows.len);
    var rows_done: usize = 0;
    errdefer {
        for (rows[0..rows_done]) |row| {
            for (row.cells) |cell| allocator.free(cell);
            allocator.free(row.cells);
            allocator.free(row.name);
            allocator.free(row.namespace);
        }
        allocator.free(rows);
    }

    for (parsed.value.rows, 0..) |wire_row, row_index| {
        var cells = try allocator.alloc([]u8, columns.len);
        var cells_done: usize = 0;
        errdefer {
            for (cells[0..cells_done]) |cell| allocator.free(cell);
            allocator.free(cells);
        }
        for (cells, 0..) |*cell, cell_index| {
            cell.* = if (cell_index < wire_row.cells.len)
                try formatCell(allocator, wire_row.cells[cell_index])
            else
                try allocator.dupe(u8, "");
            cells_done += 1;
        }

        const metadata = objectMetadata(wire_row.object);
        const name = try allocator.dupe(u8, metadata.name);
        errdefer allocator.free(name);
        const namespace = try allocator.dupe(u8, metadata.namespace);

        rows[row_index] = .{
            .cells = cells,
            .name = name,
            .namespace = namespace,
        };
        rows_done += 1;
    }

    return .{
        .columns = columns,
        .rows = rows,
        .allocator = allocator,
    };
}

fn formatCell(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    return switch (value) {
        .null => allocator.dupe(u8, ""),
        .bool => |boolean| allocator.dupe(u8, if (boolean) "true" else "false"),
        .integer => |integer| std.fmt.allocPrint(allocator, "{d}", .{integer}),
        .float => |float| std.fmt.allocPrint(allocator, "{d}", .{float}),
        .number_string => |number| allocator.dupe(u8, number),
        .string => |string| allocator.dupe(u8, string),
        .array, .object => std.json.Stringify.valueAlloc(allocator, value, .{}),
    };
}

fn objectMetadata(object: ?std.json.Value) struct {
    name: []const u8,
    namespace: []const u8,
} {
    const value = object orelse return .{ .name = "", .namespace = "" };
    if (value != .object) return .{ .name = "", .namespace = "" };
    const metadata = value.object.get("metadata") orelse
        return .{ .name = "", .namespace = "" };
    if (metadata != .object) return .{ .name = "", .namespace = "" };
    return .{
        .name = jsonString(metadata.object.get("name")),
        .namespace = jsonString(metadata.object.get("namespace")),
    };
}

fn jsonString(value: ?std.json.Value) []const u8 {
    const present = value orelse return "";
    return if (present == .string) present.string else "";
}

test "Table response preserves runtime columns, scalar cells, and identity" {
    const body =
        \\{"kind":"Table","columnDefinitions":[{"name":"Name"},{"name":"Ready"},{"name":"Nodes"}],
        \\"rows":[{"cells":["general",true,4],"object":{"metadata":{"name":"general"}}},
        \\{"cells":["gpu",false,0],"object":{"metadata":{"name":"gpu","namespace":"ops"}}}]}
    ;
    var table = try parseTable(std.testing.allocator, body);
    defer table.deinit();

    try std.testing.expectEqual(@as(usize, 3), table.columns.len);
    try std.testing.expectEqualStrings("Ready", table.columns[1]);
    try std.testing.expectEqualStrings("true", table.rows[0].cells[1]);
    try std.testing.expectEqualStrings("4", table.rows[0].cells[2]);
    try std.testing.expectEqualStrings("general", table.rows[0].name);
    try std.testing.expectEqualStrings("ops", table.rows[1].namespace);
}

test "Descriptor builds all-namespace and scoped CR paths" {
    var descriptor = Descriptor{
        .group = try std.testing.allocator.dupe(u8, "karpenter.sh"),
        .version = try std.testing.allocator.dupe(u8, "v1"),
        .plural = try std.testing.allocator.dupe(u8, "nodeclaims"),
        .kind = try std.testing.allocator.dupe(u8, "NodeClaim"),
        .namespaced = true,
    };
    defer descriptor.deinit(std.testing.allocator);

    const all = try descriptor.listPath(std.testing.allocator, "default", true);
    defer std.testing.allocator.free(all);
    try std.testing.expectEqualStrings("/apis/karpenter.sh/v1/nodeclaims", all);

    const scoped = try descriptor.listPath(std.testing.allocator, "ops", false);
    defer std.testing.allocator.free(scoped);
    try std.testing.expectEqualStrings(
        "/apis/karpenter.sh/v1/namespaces/ops/nodeclaims",
        scoped,
    );
}

test "all-namespace Table adds the namespace column kubectl prints" {
    const body =
        \\{"kind":"Table","columnDefinitions":[{"name":"Name"}],"rows":[
        \\{"cells":["one"],"object":{"metadata":{"name":"one","namespace":"ops"}}}]}
    ;
    var table = try parseTable(std.testing.allocator, body);
    defer table.deinit();
    try table.prependNamespaceColumn();

    try std.testing.expectEqualStrings("Namespace", table.columns[0]);
    try std.testing.expectEqualStrings("Name", table.columns[1]);
    try std.testing.expectEqualStrings("ops", table.rows[0].cells[0]);
    try std.testing.expectEqualStrings("one", table.rows[0].cells[1]);
}

test "resource aliases include Karpenter-friendly unique suffixes" {
    var short_names = [_][]const u8{ "ec2nc", "ec2ncs" };
    var verbs = [_][]const u8{"list"};
    const resource = klient.discovery.APIResource{
        .name = "ec2nodeclasses",
        .singularName = "ec2nodeclass",
        .shortNames = &short_names,
        .kind = "EC2NodeClass",
        .verbs = &verbs,
    };
    try std.testing.expect(matchesExact("ec2nc", "karpenter.k8s.aws", resource));
    try std.testing.expect(matchesExact(
        "ec2nodeclasses.karpenter.k8s.aws",
        "karpenter.k8s.aws",
        resource,
    ));
    try std.testing.expect(matchesUniqueSuffix("nodeclasses", resource));
    try std.testing.expect(!matchesUniqueSuffix("classes", resource));
}

test "api-resources catalog resolves every Karpenter palette entry" {
    const catalog =
        \\NAME                   SHORTNAMES    APIVERSION                 NAMESPACED   KIND
        \\ec2nodeclasses         ec2nc,ec2ncs  karpenter.k8s.aws/v1      false        EC2NodeClass
        \\nodeclaims                           karpenter.sh/v1            false        NodeClaim
        \\nodepools                            karpenter.sh/v1            false        NodePool
    ;
    for ([_][]const u8{
        "nodepool",
        "nodepools",
        "nodeclaims",
        "ec2nodeclasses",
        "ec2nc",
        "nodeclasses",
    }) |query| {
        var descriptor = (try resolveApiResources(
            std.testing.allocator,
            catalog,
            query,
        )).?;
        defer descriptor.deinit(std.testing.allocator);
        if (std.mem.eql(u8, query, "nodepool") or
            std.mem.eql(u8, query, "nodepools"))
        {
            try std.testing.expectEqualStrings("karpenter.sh", descriptor.group);
            try std.testing.expectEqualStrings("NodePool", descriptor.kind);
        } else if (std.mem.eql(u8, query, "nodeclaims")) {
            try std.testing.expectEqualStrings("karpenter.sh", descriptor.group);
            try std.testing.expectEqualStrings("NodeClaim", descriptor.kind);
        } else {
            try std.testing.expectEqualStrings("karpenter.k8s.aws", descriptor.group);
            try std.testing.expectEqualStrings("ec2nodeclasses", descriptor.plural);
        }
        try std.testing.expect(!descriptor.namespaced);
    }
}

test "ambiguous api-resources suffix releases its provisional descriptor once" {
    const catalog =
        \\NAME                   SHORTNAMES    APIVERSION                 NAMESPACED   KIND
        \\ec2nodeclasses                       karpenter.k8s.aws/v1        false        EC2NodeClass
        \\azure-nodeclasses                    karpenter.azure.com/v1      false        AzureNodeClass
    ;
    try std.testing.expectError(
        error.AmbiguousResource,
        resolveApiResources(std.testing.allocator, catalog, "nodeclasses"),
    );
}
