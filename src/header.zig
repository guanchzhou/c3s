const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const BoxDrawing = @import("box_drawing.zig");
const Theme = @import("theme.zig");
const build = @import("c3s_build");

pub const Header = struct {
    allocator: std.mem.Allocator,
    context: []const u8,
    cluster: []const u8,
    user: []const u8,
    k9s_version: []const u8,
    k8s_version: []const u8,
    cpu_usage: u8,
    mem_usage: u8,

    pub fn init(allocator: std.mem.Allocator) !Header {
        return Header{
            .allocator = allocator,
            .context = "rancher-desktop [RW]",
            .cluster = "rancher-desktop",
            .user = "rancher-desktop",
            .k9s_version = initVersion(allocator) catch "0.0.1+dev",
            .k8s_version = "v1.33.3+k3s1",
            .cpu_usage = 2,
            .mem_usage = 27,
        };
    }

    fn initVersion(allocator: std.mem.Allocator) ![]const u8 {
        // Compose version as base_version+build_number from build options
        return try std.fmt.allocPrint(allocator, "{s}+{s}", .{ build.base_version, build.build_number });
    }

    pub fn deinit(self: *Header) void {
        _ = self;
    }

    pub fn render(self: *Header, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        // Create a border around the entire header with btop theme colors and rounded corners
        try BoxDrawing.Box.createBox(terminal, x, y, width, height, Theme.div_line, Theme.main_bg, "c3s", .rounded);

        // System information (left side) - offset by 1 for border
        var line: u16 = y + 1;
        try Theme.writeStringWithTheme(terminal, x + 1, line, "Context: ", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 10, line, self.context, Theme.hi_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "Cluster: ", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 10, line, self.cluster, Theme.hi_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "User: ", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 7, line, self.user, Theme.hi_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "C3S Rev: ", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 10, line, self.k9s_version, Theme.title, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "K8s Rev: ", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, x + 10, line, self.k8s_version, Theme.title, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "CPU: ", Theme.main_fg, Theme.main_bg);
        const cpu_str = try std.fmt.allocPrint(self.allocator, "{}%", .{self.cpu_usage});
        defer self.allocator.free(cpu_str);
        try Theme.writeStringWithTheme(terminal, x + 6, line, cpu_str, Theme.hi_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, x + 1, line, "MEM: ", Theme.main_fg, Theme.main_bg);
        const mem_str = try std.fmt.allocPrint(self.allocator, "{}%", .{self.mem_usage});
        defer self.allocator.free(mem_str);
        try Theme.writeStringWithTheme(terminal, x + 6, line, mem_str, Theme.hi_fg, Theme.main_bg);

        // Keyboard shortcuts (right side) - offset by 1 for border
        const shortcuts_x = @as(u16, @intCast(width / 2)) + 1;
        line = y + 1;
        
        // Left column shortcuts
        try Theme.writeStringWithTheme(terminal, shortcuts_x, line, "<0> all", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, shortcuts_x + 8, line, "<a> Attach", Theme.main_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, shortcuts_x, line, "<1> default", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, shortcuts_x + 8, line, "<ctrl-d> Delete", Theme.main_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, shortcuts_x, line, "<d> Describe", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, shortcuts_x + 8, line, "<e> Edit", Theme.main_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, shortcuts_x, line, "<?> Help", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, shortcuts_x + 8, line, "<l> Logs", Theme.main_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, shortcuts_x, line, "<ctrl-k> Kill", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, shortcuts_x + 8, line, "<p> Logs Previous", Theme.main_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, shortcuts_x, line, "<s> Shell", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, shortcuts_x + 8, line, "<o> Show Node", Theme.main_fg, Theme.main_bg);
        line += 1;

        try Theme.writeStringWithTheme(terminal, shortcuts_x, line, "<y> YAML", Theme.main_fg, Theme.main_bg);
        try Theme.writeStringWithTheme(terminal, shortcuts_x + 8, line, "<f> Show PortForward", Theme.main_bg, Theme.main_bg);
    }
};
