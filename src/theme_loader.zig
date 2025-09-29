const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const mem = std.mem;

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
    
    allocator: std.mem.Allocator,
};

pub fn loadTheme(allocator: std.mem.Allocator, theme_name: []const u8) !ThemeColors {
    const skin_file_name = try fmt.allocPrint(allocator, "skins/{s}.yaml", .{theme_name});
    defer allocator.free(skin_file_name);
    
    const content = std.fs.cwd().readFileAlloc(allocator, skin_file_name, 1024 * 1024) catch |err| {
        if (err == error.FileNotFound) {
            return defaultTheme(allocator);
        }
        return err;
    };
    defer allocator.free(content);
    
    return parseSkinFile(allocator, content);
}

pub fn defaultTheme(allocator: std.mem.Allocator) !ThemeColors {
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

// A simpler, more direct method of getting values from a YAML-like structure
// This will not fully parse YAML spec with anchors, but will handle direct keys
// It will also resolve anchors if they are simple (e.g. &blue "#0070f3" or &fg "white")
fn getYamlValue(allocator: mem.Allocator, content: []const u8, key_path: []const u8) !?[]const u8 {
    var lines = mem.splitScalar(u8, content, '\n');
    
    // First pass to resolve anchors
    var anchors = std.StringHashMap([]const u8).init(allocator);
    defer {
        var iter = anchors.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        anchors.deinit();
    }
    
    // Parse anchors first
    var anchor_lines = mem.splitScalar(u8, content, '\n');
    while (anchor_lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (mem.startsWith(u8, trimmed, "&")) {
            if (mem.indexOfScalar(u8, trimmed, ':')) |colon_pos| {
                const anchor_name_start = 1; // After '&'
                const anchor_name_end = colon_pos;
                const anchor_name = trimmed[anchor_name_start..anchor_name_end];

                const value_start = colon_pos + 1; // After ':'
                const value_trimmed = mem.trim(u8, trimmed[value_start..], " \t");

                // Handle quoted values
                if (value_trimmed.len > 0 and value_trimmed[0] == '"' and value_trimmed[value_trimmed.len - 1] == '"') {
                    try anchors.put(try allocator.dupe(u8, anchor_name), try allocator.dupe(u8, value_trimmed[1..value_trimmed.len - 1]));
                } else {
                    try anchors.put(try allocator.dupe(u8, anchor_name), try allocator.dupe(u8, value_trimmed));
                }
            }
        }
    }

    // Second pass to find the key_path and resolve aliases
    lines = mem.splitScalar(u8, content, '\n'); // Reset lines iterator
    
    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Look for the key
        if (mem.startsWith(u8, trimmed, key_path) and trimmed.len > key_path.len and trimmed[key_path.len] == ':') {
            const value_start = key_path.len + 1; // After key and colon
            var value_str = mem.trim(u8, trimmed[value_start..], " \t");

            // Resolve aliases (e.g., *blue)
            if (mem.startsWith(u8, value_str, "*")) {
                const alias_name = value_str[1..];
                if (anchors.get(alias_name)) |aliased_value| {
                    return aliased_value;
                } else {
                    // If alias not found, fallback to the alias name itself or default
                    return value_str; 
                }
            }
            
            // Remove quotes if present
            if (value_str.len > 0 and value_str[0] == '"' and value_str[value_str.len - 1] == '"') {
                return value_str[1..value_str.len - 1];
            }
            return value_str;
        }
    }
    return null;
}

// Placeholder for original getIndent, no longer strictly needed in this simplified parser
// fn getIndent(line: []const u8) usize {
//     var indent: usize = 0;
//     while (indent < line.len and (line[indent] == ' ' or line[indent] == '\t')) : (indent += 1) {}
//     return indent;
// }

fn parseSkinFile(allocator: mem.Allocator, content: []const u8) !ThemeColors {
    var theme = try defaultTheme(allocator);
    theme.allocator = allocator; // Ensure theme owns its allocated colors

    // Helper to replace allocated string
    const replaceColor = struct {
        fn replace(alloc: mem.Allocator, old: *[]const u8, new: []const u8) !void {
            alloc.free(old.*);
            old.* = new;
        }
    }.replace;

    // General colors
    if (try getYamlValue(allocator, content, "k9s.body.fgColor")) |val| try replaceColor(allocator, &theme.main_fg, try hexToAnsi(allocator, val));
    if (try getYamlValue(allocator, content, "k9s.body.bgColor")) |val| try replaceColor(allocator, &theme.main_bg, try hexToBgAnsi(allocator, val));
    if (try getYamlValue(allocator, content, "k9s.frame.title.fgColor")) |val| try replaceColor(allocator, &theme.title, try hexToAnsi(allocator, val));
    if (try getYamlValue(allocator, content, "k9s.frame.menu.keyColor")) |val| try replaceColor(allocator, &theme.hi_fg, try hexToAnsi(allocator, val));
    
    // Selected row
    if (try getYamlValue(allocator, content, "k9s.views.table.cursorBgColor")) |val| try replaceColor(allocator, &theme.selected_bg, try hexToBgAnsi(allocator, val));
    if (try getYamlValue(allocator, content, "k9s.views.table.cursorFgColor")) |val| try replaceColor(allocator, &theme.selected_fg, try hexToAnsi(allocator, val));

    // Inactive/Comment color
    if (try getYamlValue(allocator, content, "k9s.status.completedColor")) |val| try replaceColor(allocator, &theme.inactive_fg, try hexToAnsi(allocator, val));

    // Proc box outline (using general outline color)
    if (try getYamlValue(allocator, content, "k9s.frame.border.fgColor")) |val| try replaceColor(allocator, &theme.proc_box, try hexToAnsi(allocator, val));

    // Divider line
    if (try getYamlValue(allocator, content, "k9s.frame.border.fgColor")) |val| try replaceColor(allocator, &theme.div_line, try hexToAnsi(allocator, val));

    // Status colors (k9s uses named colors, map to our default ANSI codes if not found)
    if (try getYamlValue(allocator, content, "k9s.status.addColor")) |val| try replaceColor(allocator, &theme.status_running, try hexToAnsi(allocator, val));
    if (try getYamlValue(allocator, content, "k9s.status.pendingColor")) |val| try replaceColor(allocator, &theme.status_pending, try hexToAnsi(allocator, val));
    if (try getYamlValue(allocator, content, "k9s.status.errorColor")) |val| try replaceColor(allocator, &theme.status_failed, try hexToAnsi(allocator, val));
    if (try getYamlValue(allocator, content, "k9s.status.completedColor")) |val| try replaceColor(allocator, &theme.status_succeeded, try hexToAnsi(allocator, val));

    // Key highlight for shortcuts
    if (try getYamlValue(allocator, content, "k9s.frame.menu.keyColor")) |val| try replaceColor(allocator, &theme.key_highlight, try hexToAnsi(allocator, val));

    // Title highlight for (all) etc.
    if (try getYamlValue(allocator, content, "k9s.frame.title.highlightColor")) |val| try replaceColor(allocator, &theme.title_highlight, try hexToAnsi(allocator, val));

    return theme;
}

fn hexToAnsi(allocator: mem.Allocator, hex_or_name: []const u8) error{OutOfMemory, InvalidCharacter, Overflow}![]const u8 {
    if (mem.eql(u8, hex_or_name, "default")) return allocator.dupe(u8, "\x1b[39m");
    
    // Check if it's an alias reference like *blue (should have been resolved by getYamlValue)
    if (mem.startsWith(u8, hex_or_name, "*")) return nameToAnsi(allocator, hex_or_name[1..]);
    
    // Handle named colors like "white", "red", etc. (lowercase initial)
    if (hex_or_name.len > 0 and ascii.isLower(hex_or_name[0])) {
        return nameToAnsi(allocator, hex_or_name);
    }

    // Handle short hex format like "#ff" or "#90"
    if (hex_or_name.len == 3 and hex_or_name[0] == '#') {
        const val = try fmt.parseInt(u8, hex_or_name[1..], 16);
        return fmt.allocPrint(allocator, "\x1b[38;5;{d}m", .{val});
    }
    
    // Handle full hex format "#RRGGBB"
    if (hex_or_name.len == 7 and hex_or_name[0] == '#') {
        const r = try fmt.parseInt(u8, hex_or_name[1..3], 16);
        const g = try fmt.parseInt(u8, hex_or_name[3..5], 16);
        const b = try fmt.parseInt(u8, hex_or_name[5..7], 16);
        return fmt.allocPrint(allocator, "\x1b[38;2;{d};{d};{d}m", .{ r, g, b });
    }
    
    // Fallback
    return allocator.dupe(u8, "\x1b[39m");
}

fn hexToBgAnsi(allocator: mem.Allocator, hex_or_name: []const u8) error{OutOfMemory, InvalidCharacter, Overflow}![]const u8 {
    if (mem.eql(u8, hex_or_name, "default")) return allocator.dupe(u8, "\x1b[49m");

    if (mem.startsWith(u8, hex_or_name, "*")) return nameToBgAnsi(allocator, hex_or_name[1..]);
    
    // Handle named colors
    if (hex_or_name.len > 0 and ascii.isLower(hex_or_name[0])) {
        return nameToBgAnsi(allocator, hex_or_name);
    }

    // Handle short hex format
    if (hex_or_name.len == 3 and hex_or_name[0] == '#') {
        const val = try fmt.parseInt(u8, hex_or_name[1..], 16);
        return fmt.allocPrint(allocator, "\x1b[48;5;{d}m", .{val});
    }
    
    // Handle full hex format
    if (hex_or_name.len == 7 and hex_or_name[0] == '#') {
        const r = try fmt.parseInt(u8, hex_or_name[1..3], 16);
        const g = try fmt.parseInt(u8, hex_or_name[3..5], 16);
        const b = try fmt.parseInt(u8, hex_or_name[5..7], 16);
        return fmt.allocPrint(allocator, "\x1b[48;2;{d};{d};{d}m", .{ r, g, b });
    }
    
    return allocator.dupe(u8, "\x1b[49m");
}

// Basic named color to ANSI mapping (incomplete, expand as needed)
fn nameToAnsi(allocator: mem.Allocator, name: []const u8) error{OutOfMemory, InvalidCharacter, Overflow}![]const u8 {
    if (mem.eql(u8, name, "white")) return allocator.dupe(u8, "\x1b[37m");
    if (mem.eql(u8, name, "black")) return allocator.dupe(u8, "\x1b[30m");
    if (mem.eql(u8, name, "red")) return allocator.dupe(u8, "\x1b[31m");
    if (mem.eql(u8, name, "green")) return allocator.dupe(u8, "\x1b[32m");
    if (mem.eql(u8, name, "yellow")) return allocator.dupe(u8, "\x1b[33m");
    if (mem.eql(u8, name, "blue")) return allocator.dupe(u8, "\x1b[34m");
    if (mem.eql(u8, name, "magenta")) return allocator.dupe(u8, "\x1b[35m");
    if (mem.eql(u8, name, "cyan")) return allocator.dupe(u8, "\x1b[36m");
    // Extended named colors (approximate hex mapping for 256-color or truecolor)
    if (mem.eql(u8, name, "orange")) return hexToAnsi(allocator, "#ff8700"); 
    if (mem.eql(u8, name, "fuchsia")) return hexToAnsi(allocator, "#ff00ff");
    if (mem.eql(u8, name, "lime")) return hexToAnsi(allocator, "#00ff00");
    if (mem.eql(u8, name, "aqua")) return hexToAnsi(allocator, "#00ffff");
    if (mem.eql(u8, name, "gold")) return hexToAnsi(allocator, "#ffd700");
    if (mem.eql(u8, name, "purple")) return hexToAnsi(allocator, "#800080");
    if (mem.eql(u8, name, "slategray")) return hexToAnsi(allocator, "#708090");
    if (mem.eql(u8, name, "darkgoldenrod")) return hexToAnsi(allocator, "#b8860b");
    if (mem.eql(u8, name, "mediumpurple")) return hexToAnsi(allocator, "#9370db");
    if (mem.eql(u8, name, "pink")) return hexToAnsi(allocator, "#ffc0cb");
    if (mem.eql(u8, name, "sandybrown")) return hexToAnsi(allocator, "#f4a460");
    if (mem.eql(u8, name, "dodgerblue")) return hexToAnsi(allocator, "#1e90ff");
    if (mem.eql(u8, name, "lightskyblue")) return hexToAnsi(allocator, "#87cefa");
    if (mem.eql(u8, name, "steelblue")) return hexToAnsi(allocator, "#4682b4");
    if (mem.eql(u8, name, "darkblue")) return hexToAnsi(allocator, "#00008b");
    if (mem.eql(u8, name, "aliceblue")) return hexToAnsi(allocator, "#f0f8ff");
    if (mem.eql(u8, name, "cornflowerblue")) return hexToAnsi(allocator, "#6495ed");
    if (mem.eql(u8, name, "indianred")) return hexToAnsi(allocator, "#cd5c5c");
    if (mem.eql(u8, name, "royalblue")) return hexToAnsi(allocator, "#4169e1");
    if (mem.eql(u8, name, "cadetblue")) return hexToAnsi(allocator, "#5f9ea0");
    if (mem.eql(u8, name, "powderblue")) return hexToAnsi(allocator, "#b0e0e6");
    if (mem.eql(u8, name, "ghostwhite")) return hexToAnsi(allocator, "#f8f8ff");
    if (mem.eql(u8, name, "dimgray")) return hexToAnsi(allocator, "#696969");
    if (mem.eql(u8, name, "navajowhite")) return hexToAnsi(allocator, "#ffdead");
    if (mem.eql(u8, name, "firebrick")) return hexToAnsi(allocator, "#b22222");
    if (mem.eql(u8, name, "gray")) return hexToAnsi(allocator, "#808080");
    if (mem.eql(u8, name, "redred")) return hexToAnsi(allocator, "#ff0000");
    if (mem.eql(u8, name, "linegreen")) return hexToAnsi(allocator, "#32cd32");

    return allocator.dupe(u8, "\x1b[39m"); // Default
}

fn nameToBgAnsi(allocator: mem.Allocator, name: []const u8) error{OutOfMemory, InvalidCharacter, Overflow}![]const u8 {
    if (mem.eql(u8, name, "white")) return allocator.dupe(u8, "\x1b[47m");
    if (mem.eql(u8, name, "black")) return allocator.dupe(u8, "\x1b[40m");
    if (mem.eql(u8, name, "red")) return allocator.dupe(u8, "\x1b[41m");
    if (mem.eql(u8, name, "green")) return allocator.dupe(u8, "\x1b[42m");
    if (mem.eql(u8, name, "yellow")) return allocator.dupe(u8, "\x1b[43m");
    if (mem.eql(u8, name, "blue")) return allocator.dupe(u8, "\x1b[44m");
    if (mem.eql(u8, name, "magenta")) return allocator.dupe(u8, "\x1b[45m");
    if (mem.eql(u8, name, "cyan")) return allocator.dupe(u8, "\x1b[46m");
    // Extended named colors (approximate hex mapping for 256-color or truecolor)
    if (mem.eql(u8, name, "orange")) return hexToBgAnsi(allocator, "#ff8700");
    if (mem.eql(u8, name, "fuchsia")) return hexToBgAnsi(allocator, "#ff00ff");
    if (mem.eql(u8, name, "lime")) return hexToBgAnsi(allocator, "#00ff00");
    if (mem.eql(u8, name, "aqua")) return hexToBgAnsi(allocator, "#00ffff");
    if (mem.eql(u8, name, "gold")) return hexToBgAnsi(allocator, "#ffd700");
    if (mem.eql(u8, name, "purple")) return hexToBgAnsi(allocator, "#800080");
    if (mem.eql(u8, name, "slategray")) return hexToBgAnsi(allocator, "#708090");
    if (mem.eql(u8, name, "darkgoldenrod")) return hexToBgAnsi(allocator, "#b8860b");
    if (mem.eql(u8, name, "mediumpurple")) return hexToBgAnsi(allocator, "#9370db");
    if (mem.eql(u8, name, "pink")) return hexToBgAnsi(allocator, "#ffc0cb");
    if (mem.eql(u8, name, "sandybrown")) return hexToBgAnsi(allocator, "#f4a460");
    if (mem.eql(u8, name, "dodgerblue")) return hexToBgAnsi(allocator, "#1e90ff");
    if (mem.eql(u8, name, "lightskyblue")) return hexToBgAnsi(allocator, "#87cefa");
    if (mem.eql(u8, name, "steelblue")) return hexToBgAnsi(allocator, "#4682b4");
    if (mem.eql(u8, name, "darkblue")) return hexToBgAnsi(allocator, "#00008b");
    if (mem.eql(u8, name, "aliceblue")) return hexToBgAnsi(allocator, "#f0f8ff");
    if (mem.eql(u8, name, "cornflowerblue")) return hexToBgAnsi(allocator, "#6495ed");
    if (mem.eql(u8, name, "indianred")) return hexToBgAnsi(allocator, "#cd5c5c");
    if (mem.eql(u8, name, "royalblue")) return hexToBgAnsi(allocator, "#4169e1");
    if (mem.eql(u8, name, "cadetblue")) return hexToBgAnsi(allocator, "#5f9ea0");
    if (mem.eql(u8, name, "powderblue")) return hexToBgAnsi(allocator, "#b0e0e6");
    if (mem.eql(u8, name, "ghostwhite")) return hexToBgAnsi(allocator, "#f8f8ff");
    if (mem.eql(u8, name, "dimgray")) return hexToBgAnsi(allocator, "#696969");
    if (mem.eql(u8, name, "navajowhite")) return hexToBgAnsi(allocator, "#ffdead");
    if (mem.eql(u8, name, "firebrick")) return hexToBgAnsi(allocator, "#b22222");
    if (mem.eql(u8, name, "gray")) return hexToBgAnsi(allocator, "#808080");
    if (mem.eql(u8, name, "redred")) return hexToBgAnsi(allocator, "#ff0000");
    if (mem.eql(u8, name, "linegreen")) return hexToBgAnsi(allocator, "#32cd32");

    return allocator.dupe(u8, "\x1b[49m"); // Default
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
