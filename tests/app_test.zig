const std = @import("std");
const testing = std.testing;
const App = @import("src").App;

// App.init takes a Cli.Config; all fields default, so `.{}` is sufficient here.
// Terminal.init does not require a TTY (raw mode is only enabled later), so
// App.init/deinit run cleanly in a headless test environment.

test "app initialization and cleanup" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{});
    defer app.deinit();

    // App was initialized successfully and wired to our allocator.
    try testing.expect(app.allocator.ptr == allocator.ptr);
    try testing.expect(app.running == true);
}

test "app state management" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{});
    defer app.deinit();

    // Initial state.
    try testing.expect(app.running == true);

    // State change.
    app.running = false;
    try testing.expect(app.running == false);
}

test "app memory management" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Multiple init/deinit cycles must not leak; gpa.deinit() in the outer
    // defer asserts no leaks at the end of the test.
    for (0..5) |_| {
        var app = try App.init(allocator, .{});
        app.deinit();
    }
}
