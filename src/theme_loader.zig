const std = @import("std");

pub const ThemeColors = struct {
    main_bg: []const u8,
    main_fg: []const u8,
    title: []const u8,
    hi_fg: []const u8,
    selected_bg: []const u8,
    selected_fg: []const u8,
    inactive_fg: []const u8,
    proc_box: []const u8,
    div_line: []const u8,
    status_running: []const u8,
    status_pending: []const u8,
    status_failed: []const u8,
    status_succeeded: []const u8,
    key_highlight: []const u8,
    title_highlight: []const u8,
    app_name: []const u8,
    
    // Cached ANSI escape sequences
    allocator: std.mem.Allocator,
};

pub fn loadTheme(allocator: std.mem.Allocator, theme_name: []const u8) !ThemeColors {
    // Try to load from bundled themes directory
    const theme_file_name = try std.fmt.allocPrint(allocator, "themes/{s}.theme", .{theme_name});
    defer allocator.free(theme_file_name);
    
    const content = std.fs.cwd().readFileAlloc(allocator, theme_file_name, 1024 * 1024) catch |err| {
        // If file not found, return default tokyo-night
        if (err == error.FileNotFound) {
            return defaultTheme(allocator);
        }
        return err;
    };
    defer allocator.free(content);
    
    return parseThemeFile(allocator, content);
}

pub fn defaultTheme(allocator: std.mem.Allocator) !ThemeColors {
    // Tokyo Night theme as default
    return ThemeColors{
        .allocator = allocator,
        .main_bg = try allocator.dupe(u8, "\x1b[49m"),
        .main_fg = try hexToAnsi(allocator, "#cfc9c2"),
        .title = try hexToAnsi(allocator, "#cfc9c2"),
        .hi_fg = try hexToAnsi(allocator, "#7dcfff"),
        .selected_bg = try hexToBgAnsi(allocator, "#414868"),
        .selected_fg = try hexToAnsi(allocator, "#cfc9c2"),
        .inactive_fg = try hexToAnsi(allocator, "#565f89"),
        .proc_box = try hexToAnsi(allocator, "#565f89"),
        .div_line = try hexToAnsi(allocator, "#565f89"),
        .status_running = try hexToAnsi(allocator, "#50fa7b"),
        .status_pending = try hexToAnsi(allocator, "#e0af68"),
        .status_failed = try hexToAnsi(allocator, "#f7768e"),
        .status_succeeded = try hexToAnsi(allocator, "#7dcfff"),
        .key_highlight = try hexToAnsi(allocator, "#f7768e"),
        .title_highlight = try hexToAnsi(allocator, "#e0af68"),
        .app_name = try allocator.dupe(u8, "\x1b[1;97m"),
    };
}

fn parseThemeFile(allocator: std.mem.Allocator, content: []const u8) !ThemeColors {
    var theme_map = std.StringHashMap([]const u8).init(allocator);
    defer theme_map.deinit();
    
    // Parse line by line
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        
        // Skip comments and empty lines
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        
        // Parse theme[key]="value"
        if (std.mem.indexOf(u8, trimmed, "theme[")) |start| {
            if (std.mem.indexOf(u8, trimmed[start..], "]=\"")) |bracket_end| {
                const key_start = start + 6; // "theme[" length
                const key_end = start + bracket_end;
                const key = trimmed[key_start..key_end];
                
                const value_start = key_end + 3; // "]=\"" length
                if (std.mem.indexOfScalar(u8, trimmed[value_start..], '"')) |quote_end| {
                    const value = trimmed[value_start..value_start + quote_end];
                    try theme_map.put(try allocator.dupe(u8, key), try allocator.dupe(u8, value));
                }
            }
        }
    }
    
    // Build ThemeColors from map
    const main_bg = if (theme_map.get("main_bg")) |bg|
        if (bg.len == 0 or std.mem.eql(u8, bg, "#00")) try allocator.dupe(u8, "\x1b[49m") else try hexToAnsi(allocator, bg)
    else
        try allocator.dupe(u8, "\x1b[49m");
    
    return ThemeColors{
        .allocator = allocator,
        .main_bg = main_bg,
        .main_fg = try getThemeColor(allocator, &theme_map, "main_fg", "#cfc9c2"),
        .title = try getThemeColor(allocator, &theme_map, "title", "#cfc9c2"),
        .hi_fg = try getThemeColor(allocator, &theme_map, "hi_fg", "#7dcfff"),
        .selected_bg = try getThemeColorBg(allocator, &theme_map, "selected_bg", "#414868"),
        .selected_fg = try getThemeColor(allocator, &theme_map, "selected_fg", "#cfc9c2"),
        .inactive_fg = try getThemeColor(allocator, &theme_map, "inactive_fg", "#565f89"),
        .proc_box = try getThemeColor(allocator, &theme_map, "proc_box", "#565f89"),
        .div_line = try getThemeColor(allocator, &theme_map, "div_line", "#565f89"),
        .status_running = try hexToAnsi(allocator, "#50fa7b"),
        .status_pending = try getThemeColor(allocator, &theme_map, "cpu_mid", "#e0af68"),
        .status_failed = try getThemeColor(allocator, &theme_map, "temp_end", "#f7768e"),
        .status_succeeded = try getThemeColor(allocator, &theme_map, "hi_fg", "#7dcfff"),
        .key_highlight = try getThemeColor(allocator, &theme_map, "hi_fg", "#f7768e"),
        .title_highlight = try getThemeColor(allocator, &theme_map, "cpu_mid", "#e0af68"),
        .app_name = try allocator.dupe(u8, "\x1b[1;97m"),
    };
}

fn getThemeColor(allocator: std.mem.Allocator, map: *std.StringHashMap([]const u8), key: []const u8, default: []const u8) ![]const u8 {
    if (map.get(key)) |hex| {
        return hexToAnsi(allocator, hex);
    }
    return hexToAnsi(allocator, default);
}

fn getThemeColorBg(allocator: std.mem.Allocator, map: *std.StringHashMap([]const u8), key: []const u8, default: []const u8) ![]const u8 {
    if (map.get(key)) |hex| {
        return hexToBgAnsi(allocator, hex);
    }
    return hexToBgAnsi(allocator, default);
}

fn hexToAnsi(allocator: std.mem.Allocator, hex: []const u8) ![]const u8 {
    if (hex.len == 0) return allocator.dupe(u8, "\x1b[39m");
    
    // Handle short hex format like "#ff" or "#90"
    if (hex.len == 3 and hex[0] == '#') {
        const val = try std.fmt.parseInt(u8, hex[1..], 16);
        return std.fmt.allocPrint(allocator, "\x1b[38;5;{d}m", .{val});
    }
    
    // Handle full hex format "#RRGGBB"
    if (hex.len == 7 and hex[0] == '#') {
        const r = try std.fmt.parseInt(u8, hex[1..3], 16);
        const g = try std.fmt.parseInt(u8, hex[3..5], 16);
        const b = try std.fmt.parseInt(u8, hex[5..7], 16);
        return std.fmt.allocPrint(allocator, "\x1b[38;2;{d};{d};{d}m", .{ r, g, b });
    }
    
    // Fallback
    return allocator.dupe(u8, "\x1b[39m");
}

fn hexToBgAnsi(allocator: std.mem.Allocator, hex: []const u8) ![]const u8 {
    if (hex.len == 0) return allocator.dupe(u8, "\x1b[49m");
    
    // Handle short hex format
    if (hex.len == 3 and hex[0] == '#') {
        const val = try std.fmt.parseInt(u8, hex[1..], 16);
        return std.fmt.allocPrint(allocator, "\x1b[48;5;{d}m", .{val});
    }
    
    // Handle full hex format
    if (hex.len == 7 and hex[0] == '#') {
        const r = try std.fmt.parseInt(u8, hex[1..3], 16);
        const g = try std.fmt.parseInt(u8, hex[3..5], 16);
        const b = try std.fmt.parseInt(u8, hex[5..7], 16);
        return std.fmt.allocPrint(allocator, "\x1b[48;2;{d};{d};{d}m", .{ r, g, b });
    }
    
    return allocator.dupe(u8, "\x1b[49m");
}

pub fn deinitTheme(theme: *ThemeColors) void {
    theme.allocator.free(theme.main_bg);
    theme.allocator.free(theme.main_fg);
    theme.allocator.free(theme.title);
    theme.allocator.free(theme.hi_fg);
    theme.allocator.free(theme.selected_bg);
    theme.allocator.free(theme.selected_fg);
    theme.allocator.free(theme.inactive_fg);
    theme.allocator.free(theme.proc_box);
    theme.allocator.free(theme.div_line);
    theme.allocator.free(theme.status_running);
    theme.allocator.free(theme.status_pending);
    theme.allocator.free(theme.status_failed);
    theme.allocator.free(theme.status_succeeded);
    theme.allocator.free(theme.key_highlight);
    theme.allocator.free(theme.title_highlight);
    theme.allocator.free(theme.app_name);
}
