const std = @import("std");
const testing = std.testing;
const Command = @import("src").command.Command;
const CommandRegistry = @import("src").command.CommandRegistry;
const ViewManager = @import("src").view_manager.ViewManager;

// Test command that increments a counter
fn testIncrement(ctx: *Command.CommandContext) !void {
    if (ctx.data) |ptr| {
        const counter: *usize = @ptrCast(@alignCast(ptr));
        counter.* += 1;
    }
}

// Test command that decrements a counter
fn testDecrement(ctx: *Command.CommandContext) !void {
    if (ctx.data) |ptr| {
        const counter: *usize = @ptrCast(@alignCast(ptr));
        if (counter.* > 0) {
            counter.* -= 1;
        }
    }
}

// Test command that throws an error
fn testError(ctx: *Command.CommandContext) !void {
    _ = ctx;
    return error.TestError;
}

test "Command - basic execution" {
    const allocator = testing.allocator;

    var counter: usize = 0;
    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    var ctx = Command.CommandContext{
        .allocator = allocator,
        .view_manager = &vm,
        .data = &counter,
    };

    const cmd = Command{
        .name = "increment",
        .execute = testIncrement,
    };

    try cmd.execute(&ctx);
    try testing.expectEqual(@as(usize, 1), counter);

    try cmd.execute(&ctx);
    try testing.expectEqual(@as(usize, 2), counter);
}

test "CommandRegistry - init and deinit" {
    const allocator = testing.allocator;

    var registry = try CommandRegistry.init(allocator);
    defer registry.deinit();

    // Registry should be empty initially
    const names = try registry.getCommandNames();
    defer allocator.free(names);
    try testing.expectEqual(@as(usize, 0), names.len);
}

test "CommandRegistry - register and execute" {
    const allocator = testing.allocator;

    var registry = try CommandRegistry.init(allocator);
    defer registry.deinit();

    var counter: usize = 0;
    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    const cmd = Command{
        .name = "increment",
        .execute = testIncrement,
    };

    try registry.register("inc", cmd);

    var ctx = Command.CommandContext{
        .allocator = allocator,
        .view_manager = &vm,
        .data = &counter,
    };

    const executed = try registry.execute("inc", &ctx);
    try testing.expect(executed);
    try testing.expectEqual(@as(usize, 1), counter);
}

test "CommandRegistry - execute unknown command" {
    const allocator = testing.allocator;

    var registry = try CommandRegistry.init(allocator);
    defer registry.deinit();

    var counter: usize = 0;
    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    var ctx = Command.CommandContext{
        .allocator = allocator,
        .view_manager = &vm,
        .data = &counter,
    };

    const executed = try registry.execute("unknown", &ctx);
    try testing.expect(!executed);
    try testing.expectEqual(@as(usize, 0), counter); // Counter unchanged
}

test "CommandRegistry - multiple commands" {
    const allocator = testing.allocator;

    var registry = try CommandRegistry.init(allocator);
    defer registry.deinit();

    const inc_cmd = Command{ .name = "increment", .execute = testIncrement };
    const dec_cmd = Command{ .name = "decrement", .execute = testDecrement };

    try registry.register("inc", inc_cmd);
    try registry.register("dec", dec_cmd);

    var counter: usize = 10;
    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    var ctx = Command.CommandContext{
        .allocator = allocator,
        .view_manager = &vm,
        .data = &counter,
    };

    _ = try registry.execute("inc", &ctx);
    try testing.expectEqual(@as(usize, 11), counter);

    _ = try registry.execute("dec", &ctx);
    try testing.expectEqual(@as(usize, 10), counter);

    _ = try registry.execute("inc", &ctx);
    _ = try registry.execute("inc", &ctx);
    try testing.expectEqual(@as(usize, 12), counter);
}

test "CommandRegistry - getCommandNames" {
    const allocator = testing.allocator;

    var registry = try CommandRegistry.init(allocator);
    defer registry.deinit();

    const cmd1 = Command{ .name = "cmd1", .execute = testIncrement };
    const cmd2 = Command{ .name = "cmd2", .execute = testDecrement };

    try registry.register("first", cmd1);
    try registry.register("second", cmd2);

    const names = try registry.getCommandNames();
    defer allocator.free(names);

    try testing.expectEqual(@as(usize, 2), names.len);
    
    // Names should include "first" and "second"
    var found_first = false;
    var found_second = false;
    for (names) |name| {
        if (std.mem.eql(u8, name, "first")) found_first = true;
        if (std.mem.eql(u8, name, "second")) found_second = true;
    }
    try testing.expect(found_first);
    try testing.expect(found_second);
}

test "CommandRegistry - command aliases" {
    const allocator = testing.allocator;

    var registry = try CommandRegistry.init(allocator);
    defer registry.deinit();

    const cmd = Command{ .name = "quit", .execute = testIncrement };

    // Register same command under multiple names
    try registry.register("quit", cmd);
    try registry.register("q", cmd);
    try registry.register("exit", cmd);

    var counter: usize = 0;
    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    var ctx = Command.CommandContext{
        .allocator = allocator,
        .view_manager = &vm,
        .data = &counter,
    };

    _ = try registry.execute("quit", &ctx);
    try testing.expectEqual(@as(usize, 1), counter);

    _ = try registry.execute("q", &ctx);
    try testing.expectEqual(@as(usize, 2), counter);

    _ = try registry.execute("exit", &ctx);
    try testing.expectEqual(@as(usize, 3), counter);
}

test "Command - error handling" {
    const allocator = testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    var ctx = Command.CommandContext{
        .allocator = allocator,
        .view_manager = &vm,
        .data = null,
    };

    const cmd = Command{
        .name = "error",
        .execute = testError,
    };

    const result = cmd.execute(&ctx);
    try testing.expectError(error.TestError, result);
}
