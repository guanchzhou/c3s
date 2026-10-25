const std = @import("std");
const Terminal = @import("../core/Terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const clock = @import("../core/clock.zig");
const display_text = @import("../core/display_text.zig");

/// How long an action's status message stays up before the ambient status
/// (connection state, view hint) shows through again.
pub const transient_status_ms: i64 = 5000;

pub const Footer = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    current_resource: []const u8,
    current_view: ?[]const u8 = null, // Additional view status (e.g., "help")
    preview_status: ?[]const u8 = null, // e.g., "previewing snazzy"
    crumbs: []const u8 = "",
    /// Result of the last action ("saved", "Read-only mode: ..."). Copied, because
    /// callers pass stack buffers and allocations they free right after.
    transient: StatusBuffer(256) = .{},
    transient_set_ms: i64 = 0,
    /// Re-derived every frame from connection state or the current view's hint.
    ambient: StatusBuffer(128) = .{},

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !Footer {
        return Footer{
            .allocator = allocator,
            .theme = theme,
            .current_resource = "pod",
        };
    }

    pub fn deinit(self: *Footer) void {
        _ = self;
    }

    // Methods to update footer status
    pub fn setView(self: *Footer, view: ?[]const u8) void {
        self.current_view = view;
    }

    /// Show an action's result until it is replaced, cleared with null, or
    /// `transient_status_ms` passes.
    pub fn setStatus(self: *Footer, status: ?[]const u8) void {
        self.setStatusAt(status, monotonicMs());
    }

    pub fn setStatusAt(self: *Footer, status: ?[]const u8, now_ms: i64) void {
        self.transient.set(status);
        self.transient_set_ms = now_ms;
    }

    /// Per-frame status. Never displaces a live transient message.
    pub fn setAmbientStatus(self: *Footer, status: ?[]const u8) void {
        self.ambient.set(status);
    }

    pub fn statusTextAt(self: *const Footer, now_ms: i64) ?[]const u8 {
        if (self.transient.get()) |text| {
            if (now_ms - self.transient_set_ms < transient_status_ms) return text;
        }
        return self.ambient.get();
    }

    pub fn monotonicMs() i64 {
        return @intCast(@divFloor(clock.monotonicNanoTimestamp(), std.time.ns_per_ms));
    }

    pub fn setPreviewStatus(self: *Footer, theme_name: ?[]const u8) void {
        self.preview_status = theme_name;
    }

    pub fn setCrumbs(self: *Footer, crumbs: []const u8) void {
        self.crumbs = crumbs;
    }

    pub fn setHelpMode(self: *Footer, help_visible: bool) void {
        if (help_visible) {
            self.current_view = "help";
        } else {
            self.current_view = null;
        }
    }

    pub fn setTheme(self: *Footer, theme: *const theme_loader.ThemeColors) void {
        self.theme = theme;
    }

    pub fn render(self: *Footer, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        _ = height; // Fixed height

        // Fill the footer line with theme background
        try terminal.fillRow(x, y, width, self.theme.main_fg, self.theme.main_bg);

        // Display current resource and view status with padding like other components (offset by 1)
        // Use bold text without brackets, like btop: "pods | help" or just "pod"
        var display_len: usize = 0;
        if (self.crumbs.len > 0) {
            try Theme.writeStringWithBold(terminal, x + 1, y, self.crumbs, self.theme.hi_fg, self.theme.main_bg);
            display_len = self.crumbs.len;
        } else if (self.current_view) |view| {
            // Format: "resource | view"
            var status_buffer: [64]u8 = undefined;
            const status_text = try std.fmt.bufPrint(&status_buffer, "{s} | {s}", .{ self.current_resource, view });
            try Theme.writeStringWithBold(terminal, x + 1, y, status_text, self.theme.hi_fg, self.theme.main_bg);
            display_len = status_text.len;
        } else {
            // Just the resource name
            try Theme.writeStringWithBold(terminal, x + 1, y, self.current_resource, self.theme.hi_fg, self.theme.main_bg);
            display_len = self.current_resource.len;
        }

        // Append preview status if present: " | previewing <theme>"
        if (self.preview_status) |theme_name| {
            const start_x: u16 = x + 1 + @as(u16, @intCast(display_len));
            try Theme.writeStringWithTheme(terminal, start_x, y, " | ", self.theme.main_fg, self.theme.main_bg);
            try Theme.writeStringWithTheme(terminal, start_x + 3, y, "previewing ", self.theme.title_highlight, self.theme.main_bg);
            try Theme.writeStringWithTheme(terminal, start_x + 3 + 11, y, theme_name, self.theme.title_highlight, self.theme.main_bg);
            display_len += 3 + 11 + theme_name.len;
        }

        // Append status if present: " | <status>"
        if (self.statusTextAt(monotonicMs())) |status_text2| {
            const start_x: u16 = x + 1 + @as(u16, @intCast(display_len));
            try Theme.writeStringWithTheme(terminal, start_x, y, " | ", self.theme.main_fg, self.theme.main_bg);
            try Theme.writeStringWithTheme(terminal, start_x + 3, y, status_text2, self.theme.status_failed, self.theme.main_bg);
        }
    }
};

fn StatusBuffer(comptime capacity: usize) type {
    return struct {
        bytes: [capacity]u8 = undefined,
        len: usize = 0,
        present: bool = false,

        const Self = @This();

        fn set(self: *Self, text: ?[]const u8) void {
            const value = text orelse {
                self.present = false;
                self.len = 0;
                return;
            };
            const fitted = display_text.utf8Prefix(value, capacity);
            // The source may alias this buffer (re-setting the current status).
            std.mem.copyForwards(u8, self.bytes[0..fitted.len], fitted);
            self.len = fitted.len;
            self.present = true;
        }

        fn get(self: *const Self) ?[]const u8 {
            return if (self.present) self.bytes[0..self.len] else null;
        }
    };
}

const testing = std.testing;

test "footer status is a copy that survives its source buffer being reused" {
    const theme = try theme_loader.defaultTheme(testing.allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));
    var footer = try Footer.init(testing.allocator, &theme);
    defer footer.deinit();

    var stack_buf: [64]u8 = undefined;
    const msg = try std.fmt.bufPrint(&stack_buf, "Read-only mode: {s} refused", .{"drain"});
    footer.setStatusAt(msg, 1000);
    @memset(&stack_buf, 'X');
    try testing.expectEqualStrings("Read-only mode: drain refused", footer.statusTextAt(1000).?);

    const heap = try testing.allocator.dupe(u8, "Sanitized 3 pods");
    footer.setStatusAt(heap, 1000);
    testing.allocator.free(heap);
    try testing.expectEqualStrings("Sanitized 3 pods", footer.statusTextAt(1001).?);
}

test "per-frame ambient status does not clobber a transient message until it expires" {
    const theme = try theme_loader.defaultTheme(testing.allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));
    var footer = try Footer.init(testing.allocator, &theme);
    defer footer.deinit();

    footer.setStatusAt("saved", 10_000);
    footer.setAmbientStatus("Not connected to Kubernetes cluster");
    try testing.expectEqualStrings("saved", footer.statusTextAt(10_000 + transient_status_ms - 1).?);
    try testing.expectEqualStrings(
        "Not connected to Kubernetes cluster",
        footer.statusTextAt(10_000 + transient_status_ms).?,
    );

    footer.setStatusAt("copied", 20_000);
    footer.setStatusAt(null, 20_001);
    footer.setAmbientStatus(null);
    try testing.expect(footer.statusTextAt(20_002) == null);
}

test "an over-long status is truncated on a character boundary" {
    const theme = try theme_loader.defaultTheme(testing.allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));
    var footer = try Footer.init(testing.allocator, &theme);
    defer footer.deinit();

    var long: [300]u8 = undefined;
    for (0..100) |index| @memcpy(long[index * 3 ..][0..3], "日");
    footer.setStatusAt(&long, 0);
    const shown = footer.statusTextAt(0).?;
    try testing.expect(shown.len <= 256);
    try testing.expect(std.unicode.utf8ValidateSlice(shown));
}

test "footer initialization and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var footer = try Footer.init(allocator, &theme);
    defer footer.deinit();

    // Test that footer was initialized with default values
    try testing.expect(std.mem.eql(u8, footer.current_resource, "pod"));
}

test "footer rendering" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var footer = try Footer.init(allocator, &theme);
    defer footer.deinit();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test that rendering doesn't crash
    try footer.render(&terminal, 0, 0, 80, 1);

    // Test rendering at different positions
    try footer.render(&terminal, 10, 5, 100, 1);

    // Test rendering with different sizes
    try footer.render(&terminal, 0, 0, 120, 1);
}

test "footer data validation" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var footer = try Footer.init(allocator, &theme);
    defer footer.deinit();

    // Test that current_resource is non-empty
    try testing.expect(footer.current_resource.len > 0);
}

test "footer memory management" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    // Test multiple initialization and cleanup cycles
    for (0..10) |_| {
        var footer = try Footer.init(allocator, &theme);
        footer.deinit();
    }

    // No explicit gpa.deinit() here: the deferred gpa.deinit() runs after the
    // theme's defer frees its allocation, and DebugAllocator reports any leak
    // from the footer init/deinit cycles at that point.
}
