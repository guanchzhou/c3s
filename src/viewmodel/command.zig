const std = @import("std");
const View = @import("view.zig").View;
const Logger = @import("../core/logger.zig");

/// Command pattern for handling user actions
pub const Command = struct {
    name: []const u8,
    execute: *const fn (ctx: *CommandContext) anyerror!void,

    pub const CommandContext = struct {
        allocator: std.mem.Allocator,
        view_manager: *ViewManager,
        data: ?*anyopaque = null,
    };
};

/// Command registry for managing all available commands
pub const CommandRegistry = struct {
    allocator: std.mem.Allocator,
    commands: std.StringHashMap(Command),

    pub fn init(allocator: std.mem.Allocator) !CommandRegistry {
        return CommandRegistry{
            .allocator = allocator,
            .commands = std.StringHashMap(Command).init(allocator),
        };
    }

    pub fn deinit(self: *CommandRegistry) void {
        self.commands.deinit();
    }

    /// Register a command
    pub fn register(self: *CommandRegistry, name: []const u8, command: Command) !void {
        try self.commands.put(name, command);
        Logger.debug("CommandRegistry: Registered command '{s}'", .{name});
    }

    /// Execute a command by name
    pub fn execute(self: *CommandRegistry, name: []const u8, ctx: *Command.CommandContext) !bool {
        if (self.commands.get(name)) |command| {
            Logger.info("CommandRegistry: Executing command '{s}'", .{name});
            try command.execute(ctx);
            return true;
        }
        Logger.warn("CommandRegistry: Unknown command '{s}'", .{name});
        return false;
    }

    /// Get all available command names
    pub fn getCommandNames(self: *CommandRegistry) ![][]const u8 {
        var names = std.ArrayListUnmanaged([]const u8).empty;
        var iterator = self.commands.iterator();
        while (iterator.next()) |entry| {
            try names.append(self.allocator, entry.key_ptr.*);
        }
        return names.toOwnedSlice(self.allocator);
    }
};

// Import ViewManager here to avoid circular dependency
const ViewManager = @import("ViewManager.zig").ViewManager;

// --- Tests ---

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
    const allocator = std.testing.allocator;

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
    try std.testing.expectEqual(@as(usize, 1), counter);

    try cmd.execute(&ctx);
    try std.testing.expectEqual(@as(usize, 2), counter);
}

test "CommandRegistry - init and deinit" {
    const allocator = std.testing.allocator;

    var registry = try CommandRegistry.init(allocator);
    defer registry.deinit();

    // Registry should be empty initially
    const names = try registry.getCommandNames();
    defer allocator.free(names);
    try std.testing.expectEqual(@as(usize, 0), names.len);
}

test "CommandRegistry - register and execute" {
    const allocator = std.testing.allocator;

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
    try std.testing.expect(executed);
    try std.testing.expectEqual(@as(usize, 1), counter);
}

test "CommandRegistry - execute unknown command" {
    const allocator = std.testing.allocator;

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
    try std.testing.expect(!executed);
    try std.testing.expectEqual(@as(usize, 0), counter); // Counter unchanged
}

test "CommandRegistry - multiple commands" {
    const allocator = std.testing.allocator;

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
    try std.testing.expectEqual(@as(usize, 11), counter);

    _ = try registry.execute("dec", &ctx);
    try std.testing.expectEqual(@as(usize, 10), counter);

    _ = try registry.execute("inc", &ctx);
    _ = try registry.execute("inc", &ctx);
    try std.testing.expectEqual(@as(usize, 12), counter);
}

test "CommandRegistry - getCommandNames" {
    const allocator = std.testing.allocator;

    var registry = try CommandRegistry.init(allocator);
    defer registry.deinit();

    const cmd1 = Command{ .name = "cmd1", .execute = testIncrement };
    const cmd2 = Command{ .name = "cmd2", .execute = testDecrement };

    try registry.register("first", cmd1);
    try registry.register("second", cmd2);

    const names = try registry.getCommandNames();
    defer allocator.free(names);

    try std.testing.expectEqual(@as(usize, 2), names.len);

    // Names should include "first" and "second"
    var found_first = false;
    var found_second = false;
    for (names) |name| {
        if (std.mem.eql(u8, name, "first")) found_first = true;
        if (std.mem.eql(u8, name, "second")) found_second = true;
    }
    try std.testing.expect(found_first);
    try std.testing.expect(found_second);
}

test "CommandRegistry - command aliases" {
    const allocator = std.testing.allocator;

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
    try std.testing.expectEqual(@as(usize, 1), counter);

    _ = try registry.execute("q", &ctx);
    try std.testing.expectEqual(@as(usize, 2), counter);

    _ = try registry.execute("exit", &ctx);
    try std.testing.expectEqual(@as(usize, 3), counter);
}

test "Command - error handling" {
    const allocator = std.testing.allocator;

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
    try std.testing.expectError(error.TestError, result);
}
