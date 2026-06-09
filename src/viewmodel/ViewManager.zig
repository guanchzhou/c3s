const std = @import("std");
const View = @import("view.zig").View;
const Logger = @import("../core/logger.zig");

/// Manages a stack of views, handling navigation between them
pub const ViewManager = struct {
    allocator: std.mem.Allocator,
    view_ptrs: std.ArrayList(usize),
    view_vtables: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator) !ViewManager {
        return ViewManager{
            .allocator = allocator,
            .view_ptrs = try std.ArrayList(usize).initCapacity(allocator, 10),
            .view_vtables = try std.ArrayList(usize).initCapacity(allocator, 10),
        };
    }

    pub fn deinit(self: *ViewManager) void {
        // Clean up all views in stack
        while (self.view_ptrs.items.len > 0) {
            _ = self.popView();
        }
        self.view_ptrs.deinit(self.allocator);
        self.view_vtables.deinit(self.allocator);
    }

    /// Push a new view onto the stack and activate it
    pub fn pushView(self: *ViewManager, view: View) !void {
        // Hide current view if one exists
        if (self.getCurrentView()) |current| {
            current.onHide();
        }

        Logger.info("ViewManager: Pushing view '{s}' onto stack (depth: {d})", .{ view.getName(), self.view_ptrs.items.len + 1 });

        try self.view_ptrs.append(self.allocator, @intFromPtr(view.ptr));
        try self.view_vtables.append(self.allocator, @intFromPtr(view.vtable));
        view.onShow();
    }

    /// Pop the current view and return to previous
    pub fn popView(self: *ViewManager) ?View {
        if (self.view_ptrs.items.len == 0) return null;

        const popped_ptr = self.view_ptrs.pop();
        const popped_vtable = self.view_vtables.pop();
        const popped = View{ .ptr = @ptrFromInt(popped_ptr.?), .vtable = @ptrFromInt(popped_vtable.?) };
        popped.onHide();

        Logger.info("ViewManager: Popped view '{s}' from stack (depth: {d})", .{ popped.getName(), self.view_ptrs.items.len });

        // Show previous view if one exists
        if (self.getCurrentView()) |current| {
            current.onShow();
        }

        return popped;
    }

    /// Get the current (top) view without removing it
    pub fn getCurrentView(self: *ViewManager) ?View {
        if (self.view_ptrs.items.len == 0) return null;
        const ptr = self.view_ptrs.items[self.view_ptrs.items.len - 1];
        const vtable = self.view_vtables.items[self.view_vtables.items.len - 1];
        return View{ .ptr = @ptrFromInt(ptr), .vtable = @ptrFromInt(vtable) };
    }

    /// Check if a specific view type is currently active
    pub fn isViewActive(self: *ViewManager, view_name: []const u8) bool {
        if (self.getCurrentView()) |current| {
            return std.mem.eql(u8, current.getName(), view_name);
        }
        return false;
    }

    /// Get stack depth (for debugging)
    pub fn getDepth(self: *ViewManager) usize {
        return self.view_ptrs.items.len;
    }

    /// Clear all views and reset to empty stack
    pub fn clear(self: *ViewManager) void {
        while (self.view_ptrs.items.len > 0) {
            _ = self.popView();
        }
    }
};
