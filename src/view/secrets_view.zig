/// SecretsView - View for Kubernetes Secrets
const std = @import("std");
const klient = @import("klient");
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = @import("../theme.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const K8sService = @import("../services/k8s_service.zig").K8sService;
const Logger = @import("../core/logger.zig");

pub const SecretsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,

    // State
    items: std.ArrayListUnmanaged(SecretInfo),
    selected_row: usize,
    scroll_offset: usize,
    loading: bool,
    error_message: ?[]const u8,

    // Filtering
    filter_text: []const u8,
    show_all_namespaces: bool,

    const SecretInfo = struct {
        name: []const u8,
        namespace: []const u8,
        secret_type: []const u8,
        keys: usize,
        age: []const u8,

        pub fn deinit(self: *SecretInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.namespace);
            allocator.free(self.secret_type);
            allocator.free(self.age);
        }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !SecretsView {
        return SecretsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = .{},
            .selected_row = 0,
            .scroll_offset = 0,
            .loading = false,
            .error_message = null,
            .filter_text = "",
            .show_all_namespaces = true,
        };
    }

    pub fn deinit(self: *SecretsView) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);

        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    pub fn refresh(self: *SecretsView) !void {
        Logger.info("SecretsView: Refreshing secrets...", .{});
        self.loading = true;

        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }

        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.clearRetainingCapacity();

        if (!self.k8s_service.isConnected()) {
            self.error_message = try self.allocator.dupe(u8, "Not connected to Kubernetes cluster");
            return;
        }

        const secrets = if (self.show_all_namespaces)
            self.k8s_service.listAllSecrets() catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list secrets: {}", .{err});
                return;
            }
        else
            self.k8s_service.listSecrets(null) catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list secrets: {}", .{err});
                return;
            };
        defer self.allocator.free(secrets);

        for (secrets) |secret| {
            const name = try self.allocator.dupe(u8, secret.metadata.name);
            const namespace = try self.allocator.dupe(u8, secret.metadata.namespace orelse "default");
            const secret_type = if (secret.type) |t|
                try self.allocator.dupe(u8, t)
            else
                try self.allocator.dupe(u8, "Opaque");

            const keys: usize = if (secret.data) |data_json| blk: {
                if (data_json == .object) break :blk data_json.object.count();
                break :blk 0;
            } else 0;

            const age = try self.allocator.dupe(u8, "1d");

            try self.items.append(self.allocator, SecretInfo{
                .name = name,
                .namespace = namespace,
                .secret_type = secret_type,
                .keys = keys,
                .age = age,
            });
        }

        self.loading = false;

        if (self.items.items.len == 0) {
            self.selected_row = 0;
        } else if (self.selected_row >= self.items.items.len) {
            self.selected_row = self.items.items.len - 1;
        }
    }

    pub fn createView(self: *SecretsView) View {
        return View.create(SecretsView, self, &vtable);
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *SecretsView = @ptrCast(@alignCast(ptr));
        _ = width;

        if (self.loading) {
            try Theme.writeStringWithTheme(term, x, y, "Loading secrets...", self.theme.main_fg, self.theme.main_bg);
            return;
        }

        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }

        if (self.items.items.len == 0) {
            const msg = if (self.show_all_namespaces) "No secrets found in cluster" else "No secrets in current namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        const header = "  NAMESPACE             NAME                          TYPE             KEYS   AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        const visible_rows = if (height > 1) height - 1 else 0;
        var row: u16 = 0;
        var idx = self.scroll_offset;

        while (row < visible_rows and idx < self.items.items.len) : ({
            row += 1;
            idx += 1;
        }) {
            const item = &self.items.items[idx];
            const is_selected = (idx == self.selected_row);

            const fg_color = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg_color = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            const line = try std.fmt.allocPrint(
                self.allocator,
                "  {s: <20} {s: <28} {s: <15} {d: >6} {s}",
                .{
                    if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                    if (item.name.len > 28) item.name[0..28] else item.name,
                    if (item.secret_type.len > 15) item.secret_type[0..15] else item.secret_type,
                    item.keys,
                    item.age,
                },
            );
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, y + 1 + row, line, fg_color, bg_color);
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *SecretsView = @ptrCast(@alignCast(ptr));
        switch (key) {
            .down => {
                if (self.selected_row < self.items.items.len -| 1) {
                    self.selected_row += 1;
                }
                return .handled;
            },
            .up => {
                if (self.selected_row > 0) {
                    self.selected_row -= 1;
                }
                return .handled;
            },
            .char => |c| switch (c) {
                'j' => {
                    if (self.selected_row < self.items.items.len -| 1) {
                        self.selected_row += 1;
                    }
                    return .handled;
                },
                'k' => {
                    if (self.selected_row > 0) {
                        self.selected_row -= 1;
                    }
                    return .handled;
                },
                'r' => {
                    try self.refresh();
                    return .handled;
                },
                '0' => {
                    self.show_all_namespaces = !self.show_all_namespaces;
                    try self.refresh();
                    return .handled;
                },
                else => {},
            },
            else => {},
        }
        return .not_handled;
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *SecretsView = @ptrCast(@alignCast(ptr));
        Logger.info("SecretsView shown", .{});
        self.refresh() catch |err| {
            Logger.err("Failed to refresh Secrets on show: {}", .{err});
        };
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "secrets";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        const hint_items = comptime [_]hints_model.Hint{
            hints_model.Hint.plain("↑↓ Navigate", 1),
            hints_model.Hint.plain("r Refresh", 2),
            hints_model.Hint.plain("0 All Namespaces", 3),
        };
        return hints_model.HintConfig{
            .hints = &hint_items,
        };
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *SecretsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinitView,
    };
};
