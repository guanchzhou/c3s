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
