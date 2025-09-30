const std = @import("std");
const testing = std.testing;
const ViewManager = @import("c3s").viewmodel.view_manager.ViewManager;
const View = @import("c3s").viewmodel.view.View;

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

    fn render(ptr: *anyopaque, term: *@import("c3s").core.terminal.Terminal, x: u16, y: u16, w: u16, h: u16) !void {
        _ = ptr;
        _ = term;
        _ = x;
        _ = y;
        _ = w;
        _ = h;
    }

    fn handleKey(ptr: *anyopaque, key: @import("c3s").core.terminal.Key) !View.KeyResult {
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

    fn getHints(ptr: *anyopaque) @import("c3s").model.hints.HintConfig {
        _ = ptr;
        return .{ .quick_commands = &[_]@import("c3s").model.hints.QuickCommand{}, .hints = &[_]@import("c3s").model.hints.Hint{} };
    }

    fn deinit(ptr: *anyopaque) void {
        _ = ptr;
    }

    fn createView(self: *MockView) View {
        return View.create(MockView, self, &vtable);
    }
};

test "ViewManager - init and deinit" {
    const allocator = testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    try testing.expectEqual(@as(usize, 0), vm.getDepth());
}

test "ViewManager - push and get current view" {
    const allocator = testing.allocator;

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

    try testing.expectEqual(@as(usize, 1), vm.getDepth());
    try testing.expectEqual(@as(usize, 1), show_count); // onShow called once

    if (vm.getCurrentView()) |current| {
        try testing.expectEqualStrings("test-view", current.getName());
    } else {
        try testing.expect(false); // Should have a current view
    }
}

test "ViewManager - pop view" {
    const allocator = testing.allocator;

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
    try testing.expectEqual(@as(usize, 1), vm.getDepth());

    const popped = vm.popView();
    try testing.expect(popped != null);
    try testing.expectEqual(@as(usize, 0), vm.getDepth());
    try testing.expectEqual(@as(usize, 1), hide_count); // onHide called once
}

test "ViewManager - multiple views" {
    const allocator = testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    var show1: usize = 0;
    var hide1: usize = 0;
    var show2: usize = 0;
    var hide2: usize = 0;

    var view1 = MockView{ .name = "view-1", .show_count = &show1, .hide_count = &hide1 };
    var view2 = MockView{ .name = "view-2", .show_count = &show2, .hide_count = &hide2 };

    try vm.pushView(view1.createView());
    try testing.expectEqual(@as(usize, 1), vm.getDepth());
    try testing.expectEqual(@as(usize, 1), show1);
    try testing.expectEqual(@as(usize, 0), hide1);

    try vm.pushView(view2.createView());
    try testing.expectEqual(@as(usize, 2), vm.getDepth());
    try testing.expectEqual(@as(usize, 1), hide1); // view1 hidden
    try testing.expectEqual(@as(usize, 1), show2); // view2 shown

    // Current view should be view2
    if (vm.getCurrentView()) |current| {
        try testing.expectEqualStrings("view-2", current.getName());
    }

    _ = vm.popView();
    try testing.expectEqual(@as(usize, 1), vm.getDepth());
    try testing.expectEqual(@as(usize, 2), show1); // view1 shown again
    try testing.expectEqual(@as(usize, 1), hide2); // view2 hidden

    // Current view should be view1
    if (vm.getCurrentView()) |current| {
        try testing.expectEqualStrings("view-1", current.getName());
    }
}

test "ViewManager - isViewActive" {
    const allocator = testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    try testing.expect(!vm.isViewActive("any-view")); // No views

    var show_count: usize = 0;
    var hide_count: usize = 0;

    var mock_view = MockView{
        .name = "pods-view",
        .show_count = &show_count,
        .hide_count = &hide_count,
    };

    try vm.pushView(mock_view.createView());
    try testing.expect(vm.isViewActive("pods-view"));
    try testing.expect(!vm.isViewActive("themes-view"));
}

test "ViewManager - clear" {
    const allocator = testing.allocator;

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
    try testing.expectEqual(@as(usize, 2), vm.getDepth());

    vm.clear();
    try testing.expectEqual(@as(usize, 0), vm.getDepth());
    try testing.expectEqual(@as(usize, 1), hide2);
    try testing.expectEqual(@as(usize, 2), show1); // view1 shown when view2 popped, then hidden when cleared
}

test "ViewManager - pop from empty stack" {
    const allocator = testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    const popped = vm.popView();
    try testing.expect(popped == null);
}

test "ViewManager - getCurrentView from empty stack" {
    const allocator = testing.allocator;

    var vm = try ViewManager.init(allocator);
    defer vm.deinit();

    const current = vm.getCurrentView();
    try testing.expect(current == null);
}
