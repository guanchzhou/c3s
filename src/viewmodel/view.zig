const std = @import("std");
const Terminal = @import("../core/terminal.zig").Terminal;
const Key = @import("../core/terminal.zig").Key;
const hints_model = @import("../model/hints.zig");

/// View trait - all views must implement this interface
pub const View = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Render the view to the terminal
        render: *const fn (ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) anyerror!void,
        
        /// Handle a key press
        handleKey: *const fn (ptr: *anyopaque, key: Key) anyerror!KeyResult,
        
        /// Called when view becomes active
        onShow: *const fn (ptr: *anyopaque) void,
        
        /// Called when view becomes inactive
        onHide: *const fn (ptr: *anyopaque) void,
        
        /// Get view name for debugging
        getName: *const fn (ptr: *anyopaque) []const u8,
        
        /// Get hints configuration for this view
        getHints: *const fn (ptr: *anyopaque) hints_model.HintConfig,
        
        /// Cleanup view resources
        deinit: *const fn (ptr: *anyopaque) void,
    };

    pub const KeyResult = enum {
        handled,
        not_handled,
        request_command_palette,
        request_filter,
        request_quit,
        request_describe,
        request_yaml,
        request_logs,
        request_delete,
    };

    pub fn render(self: View, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        return self.vtable.render(self.ptr, terminal, x, y, width, height);
    }

    pub fn handleKey(self: View, key: Key) !KeyResult {
        return self.vtable.handleKey(self.ptr, key);
    }

    pub fn onShow(self: View) void {
        return self.vtable.onShow(self.ptr);
    }

    pub fn onHide(self: View) void {
        return self.vtable.onHide(self.ptr);
    }

    pub fn getName(self: View) []const u8 {
        return self.vtable.getName(self.ptr);
    }

    pub fn getHints(self: View) hints_model.HintConfig {
        return self.vtable.getHints(self.ptr);
    }

    pub fn deinit(self: View) void {
        return self.vtable.deinit(self.ptr);
    }
    
    /// Create a view from a concrete type
    pub fn create(comptime T: type, instance: *T, vtable: *const VTable) View {
        return View{
            .ptr = @ptrCast(instance),
            .vtable = vtable,
        };
    }
};