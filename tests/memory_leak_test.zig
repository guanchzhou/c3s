const std = @import("std");

// Import all major components through the "src" module (Zig 0.16 forbids tests/
// from crossing the module boundary via @import("../src/..")).
const src = @import("src");
const App = src.App;
const CommandInput = src.CommandInput;
const Header = src.Header;
const Footer = src.Footer;
const theme_loader = src.theme_loader;
const config = src.Config;
const HelpView = src.HelpView;
const PodsView = src.PodsView;
const ThemesView = src.ThemesView;
const K8sService = src.K8sService;

test "App init/deinit - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in App!\n", .{});
        }
        std.debug.assert(leaked == .ok);
    }
    const allocator = gpa.allocator();

    // App.init takes a Cli.Config; the default-initialized literal coerces to it.
    var app = try App.init(allocator, .{});
    defer app.deinit();
}

test "Theme loader - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in theme loader!\n", .{});
        }
        std.debug.assert(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);
}

test "CommandInput - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in CommandInput!\n", .{});
        }
        std.debug.assert(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    // Use the command input
    cmd_input.showWithPrompt(":");
    try cmd_input.addChar('t');
    try cmd_input.addChar('e');
    try cmd_input.addChar('s');
    try cmd_input.addChar('t');
    cmd_input.backspace();
    cmd_input.hide();
}

test "Header - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in Header!\n", .{});
        }
        std.debug.assert(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var header = try Header.init(allocator, &theme, false);
    defer header.deinit();
}

test "Footer - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in Footer!\n", .{});
        }
        std.debug.assert(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var footer = try Footer.init(allocator, &theme);
    defer footer.deinit();
}

test "HelpView - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in HelpView!\n", .{});
        }
        std.debug.assert(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var help_view = try HelpView.init(allocator, &theme);
    defer help_view.deinit();
}

test "PodsView - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in PodsView!\n", .{});
        }
        std.debug.assert(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var k8s_service = try K8sService.init(allocator);
    defer k8s_service.deinit();

    var pods_view = try PodsView.init(allocator, &theme, &k8s_service);
    defer pods_view.deinit();

    // Navigation lives on the underlying TableState and must be bounds-safe.
    pods_view.table.navigateDown();
    pods_view.table.navigateUp();
}

test "ThemesView - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in ThemesView!\n", .{});
        }
        std.debug.assert(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(&theme);

    var themes_view = try ThemesView.init(allocator, "tokyo-night", &theme);
    defer themes_view.deinit();
}

test "Config loading - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in config loading!\n", .{});
        }
        std.debug.assert(leaked == .ok);
    }
    const allocator = gpa.allocator();

    // Config.load reads from XDG paths (or returns defaults) and owns any
    // allocated theme name; deinit must free it cleanly.
    const cfg = try config.load(allocator);
    defer cfg.deinit();
}

test "Multiple allocations and deallocations - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in stress test!\n", .{});
        }
        std.debug.assert(leaked == .ok);
    }
    const allocator = gpa.allocator();

    // Create and destroy components multiple times
    for (0..10) |_| {
        var theme = try theme_loader.defaultTheme(allocator);
        defer theme_loader.deinitTheme(&theme);

        var cmd_input = try CommandInput.init(allocator, &theme);
        defer cmd_input.deinit();

        var header = try Header.init(allocator, &theme, false);
        defer header.deinit();

        var footer = try Footer.init(allocator, &theme);
        defer footer.deinit();
    }
}
