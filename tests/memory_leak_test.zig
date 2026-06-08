const std = @import("std");
const testing = std.testing;

// Import all major components
const App = @import("../src/app.zig").App;
const CommandInput = @import("../src/ui/command_input.zig").CommandInput;
const Header = @import("../src/ui/header.zig").Header;
const Footer = @import("../src/ui/footer.zig").Footer;
const theme_loader = @import("../src/model/theme_loader.zig");
const config = @import("../src/model/config.zig");
const HelpView = @import("../src/view/help_view.zig").HelpView;
const PodsView = @import("../src/view/pods_view.zig").PodsView;
const ThemesView = @import("../src/view/themes_view.zig").ThemesView;

test "App init/deinit - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in App!\n", .{});
        }
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var app = try App.init(allocator);
    defer app.deinit();
}

test "Theme loader - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in theme loader!\n", .{});
        }
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    var theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));
}

test "CommandInput - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in CommandInput!\n", .{});
        }
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var cmd_input = try CommandInput.init(allocator, &theme);
    defer cmd_input.deinit();

    // Use the command input
    cmd_input.show(":");
    try cmd_input.insertChar('t');
    try cmd_input.insertChar('e');
    try cmd_input.insertChar('s');
    try cmd_input.insertChar('t');
    cmd_input.clear();
    cmd_input.hide();
}

test "Header - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in Header!\n", .{});
        }
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var header = try Header.init(allocator, &theme);
    defer header.deinit();
}

test "Footer - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in Footer!\n", .{});
        }
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

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
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var help_view = try HelpView.init(allocator, &theme);
    defer help_view.cleanup();
}

test "PodsView - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in PodsView!\n", .{});
        }
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var pods_view = try PodsView.init(allocator, &theme);
    defer pods_view.cleanup();

    // Test navigation
    try pods_view.navigateDown();
    try pods_view.navigateUp();
}

test "ThemesView - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in ThemesView!\n", .{});
        }
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    const theme = try theme_loader.defaultTheme(allocator);
    defer theme_loader.deinitTheme(@constCast(&theme));

    var themes_view = try ThemesView.init(allocator, "tokyo-night", &theme);
    defer themes_view.cleanup();
}

test "Config parsing - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in config parsing!\n", .{});
        }
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    const test_config =
        \\ui:
        \\  compact: false
        \\  theme: tokyo-night
    ;

    var ui_config = try config.parseUiConfig(allocator, test_config);
    defer config.deinitUiConfig(&ui_config);
}

test "Multiple allocations and deallocations - no memory leaks" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        if (leaked == .leak) {
            std.debug.print("Memory leak detected in stress test!\n", .{});
        }
        try testing.expect(leaked == .ok);
    }
    const allocator = gpa.allocator();

    // Create and destroy components multiple times
    for (0..10) |_| {
        const theme = try theme_loader.defaultTheme(allocator);
        defer theme_loader.deinitTheme(@constCast(&theme));

        var cmd_input = try CommandInput.init(allocator, &theme);
        defer cmd_input.deinit();

        var header = try Header.init(allocator, &theme);
        defer header.deinit();

        var footer = try Footer.init(allocator, &theme);
        defer footer.deinit();
    }
}
