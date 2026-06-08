const std = @import("std");
const xdg = @import("../core/xdg.zig");
const runtime = @import("../core/runtime.zig");

pub const UiConfig = struct {
    compact: bool = false,
    footer: bool = true,
    theme: []const u8 = "tokyo-night",
    theme_allocated: ?[]u8 = null,
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    ui: UiConfig,
    theme_owned: ?[]u8 = null,

    pub fn deinit(self: *const Config) void {
        if (self.theme_owned) |theme| {
            self.allocator.free(theme);
        }
    }
};

pub fn load(allocator: std.mem.Allocator) !Config {
    // Get XDG paths
    const paths = xdg.ensurePaths() catch {
        // If XDG paths fail, return defaults
        return Config{
            .allocator = allocator,
            .ui = UiConfig{},
        };
    };

    // Try to read config file
    const config_content = std.Io.Dir.cwd().readFileAlloc(
        runtime.io(),
        paths.config_file,
        allocator,
        .limited(1024 * 1024), // 1MB max
    ) catch {
        // File not found or read error - return defaults
        return Config{
            .allocator = allocator,
            .ui = UiConfig{},
        };
    };
    defer allocator.free(config_content);

    // Parse the YAML (simple parser for our use case)
    const ui_config = try parseUiConfig(allocator, config_content);

    const Logger = @import("../core/logger.zig");
    Logger.info("Config loaded - compact: {}, footer: {}", .{ ui_config.compact, ui_config.footer });

    return Config{
        .allocator = allocator,
        .ui = ui_config,
        .theme_owned = ui_config.theme_allocated,
    };
}

fn parseUiConfig(allocator: std.mem.Allocator, content: []const u8) !UiConfig {
    var ui_config = UiConfig{};

    // Simple line-by-line parser
    var lines = std.mem.splitScalar(u8, content, '\n');

    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");

        // Look for "compact:" line
        if (std.mem.indexOf(u8, trimmed, "compact:")) |_| {
            // Check if it's set to true
            if (std.mem.indexOf(u8, trimmed, "true")) |_| {
                ui_config.compact = true;
            } else if (std.mem.indexOf(u8, trimmed, "false")) |_| {
                ui_config.compact = false;
            }
        }

        // Look for "footer:" line
        if (std.mem.indexOf(u8, trimmed, "footer:")) |_| {
            // Check if it's set to true or false
            if (std.mem.indexOf(u8, trimmed, "true")) |_| {
                ui_config.footer = true;
            } else if (std.mem.indexOf(u8, trimmed, "false")) |_| {
                ui_config.footer = false;
            }
        }

        // Look for "theme:" line
        if (std.mem.indexOf(u8, trimmed, "theme:")) |pos| {
            const after_colon = std.mem.trim(u8, trimmed[pos + 6 ..], " \t");
            if (after_colon.len > 0) {
                // Remove quotes if present
                var theme_name = after_colon;
                if (theme_name.len > 0 and theme_name[0] == '"' and theme_name[theme_name.len - 1] == '"') {
                    theme_name = theme_name[1 .. theme_name.len - 1];
                }
                // Allocate the theme name since it points into content buffer
                const owned = try allocator.dupe(u8, theme_name);
                ui_config.theme = owned;
                ui_config.theme_allocated = owned;
            }
        }
    }

    return ui_config;
}
