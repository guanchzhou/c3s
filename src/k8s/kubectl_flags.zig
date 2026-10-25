//! kubectl global flags from the c3s command line, passed to every kubectl
//! process c3s starts. Strings are borrowed from argv and live for the process.
const std = @import("std");

pub const max_as_groups = 16;

pub const Overrides = struct {
    cluster: ?[]const u8 = null,
    user: ?[]const u8 = null,
    as: ?[]const u8 = null,
    as_groups: []const []const u8 = &.{},
    certificate_authority: ?[]const u8 = null,
    client_certificate: ?[]const u8 = null,
    client_key: ?[]const u8 = null,
    request_timeout: ?[]const u8 = null,

    /// Whether these change which server c3s talks to or who it is. The
    /// in-process client is built from the kubeconfig alone, so any of them
    /// routes all traffic through kubectl.
    pub fn changesIdentity(self: Overrides) bool {
        return self.cluster != null or self.user != null or self.as != null or
            self.as_groups.len > 0 or self.certificate_authority != null or
            self.client_certificate != null or self.client_key != null;
    }

    /// Flags for `kubectl proxy`. `--request-timeout` is left out: on the proxy it
    /// would cut every watch stream at that deadline.
    pub fn appendIdentity(
        self: Overrides,
        allocator: std.mem.Allocator,
        argv: *std.ArrayListUnmanaged([]const u8),
    ) !void {
        const pairs = [_]struct { []const u8, ?[]const u8 }{
            .{ "--cluster", self.cluster },
            .{ "--user", self.user },
            .{ "--as", self.as },
            .{ "--certificate-authority", self.certificate_authority },
            .{ "--client-certificate", self.client_certificate },
            .{ "--client-key", self.client_key },
        };
        for (pairs) |pair| {
            if (pair[1]) |value| try argv.appendSlice(allocator, &.{ pair[0], value });
        }
        for (self.as_groups) |group| try argv.appendSlice(allocator, &.{ "--as-group", group });
    }

    /// Flags for one-shot kubectl requests.
    pub fn appendRequest(
        self: Overrides,
        allocator: std.mem.Allocator,
        argv: *std.ArrayListUnmanaged([]const u8),
    ) !void {
        try self.appendIdentity(allocator, argv);
        if (self.request_timeout) |value| try argv.appendSlice(allocator, &.{ "--request-timeout", value });
    }
};

test "identity flags omit the request timeout, request flags keep it" {
    const allocator = std.testing.allocator;
    const overrides = Overrides{
        .cluster = "staging",
        .as = "jane",
        .as_groups = &.{ "devs", "oncall" },
        .request_timeout = "10s",
    };
    try std.testing.expect(overrides.changesIdentity());

    var identity: std.ArrayListUnmanaged([]const u8) = .empty;
    defer identity.deinit(allocator);
    try overrides.appendIdentity(allocator, &identity);
    const expected_identity = [_][]const u8{
        "--cluster", "staging", "--as", "jane", "--as-group", "devs", "--as-group", "oncall",
    };
    try std.testing.expectEqual(expected_identity.len, identity.items.len);
    for (expected_identity, identity.items) |want, got| try std.testing.expectEqualStrings(want, got);

    var request: std.ArrayListUnmanaged([]const u8) = .empty;
    defer request.deinit(allocator);
    try overrides.appendRequest(allocator, &request);
    try std.testing.expectEqualStrings("--request-timeout", request.items[request.items.len - 2]);
    try std.testing.expectEqualStrings("10s", request.items[request.items.len - 1]);
}

test "a request timeout alone keeps the in-process client" {
    try std.testing.expect(!(Overrides{ .request_timeout = "5s" }).changesIdentity());
    try std.testing.expect(!(Overrides{}).changesIdentity());
}
