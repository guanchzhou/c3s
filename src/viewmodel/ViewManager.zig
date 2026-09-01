const std = @import("std");
const View = @import("view.zig").View;
const Logger = @import("../core/logger.zig");
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const hints = @import("../model/hints.zig");

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
        // The view objects are owned by App; this manager only holds
        // (ptr, vtable) handles. Do NOT popView() here: popView fires onHide/
        // onShow lifecycle callbacks, and during teardown App may have already
        // destroyed the underlying view objects — invoking their methods on
        // freed memory is a use-after-free (e.g. quitting from a pushed detail
        // view popped back to a destroyed PodsView, whose onShow derefs self).
        // Just release the handle arrays.
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

    /// Write `pods > logs` into `buf`. Empty when the stack is empty.
    pub fn writeCrumbs(self: *const ViewManager, buf: []u8) []const u8 {
        var n: usize = 0;
        for (self.view_ptrs.items, 0..) |ptr, i| {
            const view = View{
                .ptr = @ptrFromInt(ptr),
                .vtable = @ptrFromInt(self.view_vtables.items[i]),
            };
            const name = view.getName();
            if (i > 0) {
                if (n + 3 > buf.len) break;
                @memcpy(buf[n .. n + 3], " > ");
                n += 3;
            }
            const take = @min(name.len, buf.len - n);
            @memcpy(buf[n .. n + take], name[0..take]);
            n += take;
        }
        return buf[0..n];
    }

    /// Clear all views and reset to empty stack
    pub fn clear(self: *ViewManager) void {
        while (self.view_ptrs.items.len > 0) {
            _ = self.popView();
        }
    }
};

// --- Tests ---

// Mock view for testing
const MockView = struct {
    name: []const u8,
    show_count: *usize,
    hide_count: *usize,

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinit,
    };

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, w: u16, h: u16) !void {
        _ = ptr;
        _ = term;
        _ = x;
        _ = y;
        _ = w;
        _ = h;
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        _ = ptr;
        _ = key;
        return .not_handled;
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *MockView = @ptrCast(@alignCast(ptr));
        self.show_count.* += 1;
    }

    fn onHide(ptr: *anyopaque) void {
        const self: *MockView = @ptrCast(@alignCast(ptr));
        self.hide_count.* += 1;
    }

    fn getName(ptr: *anyopaque) []const u8 {
        const self: *MockView = @ptrCast(@alignCast(ptr));
        return self.name;
    }

    fn getHints(ptr: *anyopaque) hints.HintConfig {
        _ = ptr;
        return .{ .quick_commands = &[_]hints.QuickCommand{}, .hints = &[_]hints.Hint{} };
    }

    fn deinit(ptr: *anyopaque) void {
        _ = ptr;
    }

    fn createView(self: *MockView) View {
        return View.create(MockView, self, &vtable);
    }
};

test "ViewManager - init and deinit" {
    const allocator = std.testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    try std.testing.expectEqual(@as(usize, 0), vm.getDepth());
}

test "ViewManager - push and get current view" {
    const allocator = std.testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    var show_count: usize = 0;
    var hide_count: usize = 0;

    var mock_view = MockView{
        .name = "test-view",
        .show_count = &show_count,
        .hide_count = &hide_count,
    };
    const view = mock_view.createView();

    try vm.pushView(view);

    try std.testing.expectEqual(@as(usize, 1), vm.getDepth());
    try std.testing.expectEqual(@as(usize, 1), show_count); // onShow called once

    if (vm.getCurrentView()) |current| {
        try std.testing.expectEqualStrings("test-view", current.getName());
    } else {
        try std.testing.expect(false); // Should have a current view
    }
}

test "ViewManager - pop view" {
    const allocator = std.testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    var show_count: usize = 0;
    var hide_count: usize = 0;

    var mock_view = MockView{
        .name = "test-view",
        .show_count = &show_count,
        .hide_count = &hide_count,
    };
    const view = mock_view.createView();

    try vm.pushView(view);
    try std.testing.expectEqual(@as(usize, 1), vm.getDepth());

    const popped = vm.popView();
    try std.testing.expect(popped != null);
    try std.testing.expectEqual(@as(usize, 0), vm.getDepth());
    try std.testing.expectEqual(@as(usize, 1), hide_count); // onHide called once
}

test "ViewManager - multiple views" {
    const allocator = std.testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    var show1: usize = 0;
    var hide1: usize = 0;
    var show2: usize = 0;
    var hide2: usize = 0;

    var view1 = MockView{ .name = "view-1", .show_count = &show1, .hide_count = &hide1 };
    var view2 = MockView{ .name = "view-2", .show_count = &show2, .hide_count = &hide2 };

    try vm.pushView(view1.createView());
    try std.testing.expectEqual(@as(usize, 1), vm.getDepth());
    try std.testing.expectEqual(@as(usize, 1), show1);
    try std.testing.expectEqual(@as(usize, 0), hide1);

    try vm.pushView(view2.createView());
    try std.testing.expectEqual(@as(usize, 2), vm.getDepth());
    try std.testing.expectEqual(@as(usize, 1), hide1); // view1 hidden
    try std.testing.expectEqual(@as(usize, 1), show2); // view2 shown

    // Current view should be view2
    if (vm.getCurrentView()) |current| {
        try std.testing.expectEqualStrings("view-2", current.getName());
    }

    _ = vm.popView();
    try std.testing.expectEqual(@as(usize, 1), vm.getDepth());
    try std.testing.expectEqual(@as(usize, 2), show1); // view1 shown again
    try std.testing.expectEqual(@as(usize, 1), hide2); // view2 hidden

    // Current view should be view1
    if (vm.getCurrentView()) |current| {
        try std.testing.expectEqualStrings("view-1", current.getName());
    }
}

test "ViewManager - isViewActive" {
    const allocator = std.testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    try std.testing.expect(!vm.isViewActive("any-view")); // No views

    var show_count: usize = 0;
    var hide_count: usize = 0;

    var mock_view = MockView{
        .name = "pods-view",
        .show_count = &show_count,
        .hide_count = &hide_count,
    };

    try vm.pushView(mock_view.createView());
    try std.testing.expect(vm.isViewActive("pods-view"));
    try std.testing.expect(!vm.isViewActive("themes-view"));
}

test "ViewManager - clear" {
    const allocator = std.testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    var show1: usize = 0;
    var hide1: usize = 0;
    var show2: usize = 0;
    var hide2: usize = 0;

    var view1 = MockView{ .name = "view-1", .show_count = &show1, .hide_count = &hide1 };
    var view2 = MockView{ .name = "view-2", .show_count = &show2, .hide_count = &hide2 };

    try vm.pushView(view1.createView());
    try vm.pushView(view2.createView());
    try std.testing.expectEqual(@as(usize, 2), vm.getDepth());

    vm.clear();
    try std.testing.expectEqual(@as(usize, 0), vm.getDepth());
    try std.testing.expectEqual(@as(usize, 1), hide2);
    try std.testing.expectEqual(@as(usize, 2), show1); // view1 shown when view2 popped, then hidden when cleared
}

test "ViewManager - pop from empty stack" {
    const allocator = std.testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    const popped = vm.popView();
    try std.testing.expect(popped == null);
}

test "ViewManager - getCurrentView from empty stack" {
    const allocator = std.testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    const current = vm.getCurrentView();
    try std.testing.expect(current == null);
}
