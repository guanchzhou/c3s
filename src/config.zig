const std = @import("std");
const xdg = @import("xdg.zig");

pub const UiConfig = struct {
    compact: bool = false,
};

pub const Config = struct {
    allocator: std.mem.Allocator,
    ui: UiConfig,
    
    pub fn deinit(self: *const Config) void {
        _ = self;
        // No dynamic allocations to free in current implementation
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
    const config_content = std.fs.cwd().readFileAlloc(
        allocator,
        paths.config_file,
        1024 * 1024, // 1MB max
    ) catch {
        // File not found or read error - return defaults
        return Config{
            .allocator = allocator,
            .ui = UiConfig{},
        };
    };
    defer allocator.free(config_content);
    
    // Parse the YAML (simple parser for our use case)
    const ui_config = parseUiConfig(config_content);
    
    return Config{
        .allocator = allocator,
        .ui = ui_config,
    };
}

fn parseUiConfig(content: []const u8) UiConfig {
    var ui_config = UiConfig{};
    
    // Simple line-by-line parser looking for "compact: true" or "compact: false"
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
    }
    
    return ui_config;
}
