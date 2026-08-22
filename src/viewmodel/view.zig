const std = @import("std");
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const hints_model = @import("../model/hints.zig");

/// Resource info returned by views for describe/delete/logs operations
pub const ResourceInfo = struct {
    name: []const u8,
    namespace: []const u8,
};

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

        /// Get view name for debugging / identity
        getName: *const fn (ptr: *anyopaque) []const u8,

        /// Optional decorated title for the box header, e.g. "pods(default)[8]"
        /// or "pods(all)[104]". Returns "" by default; callers fall back to
        /// getName() when empty.
        getTitle: *const fn (ptr: *anyopaque) []const u8 = &noopGetTitle,

        /// Get hints configuration for this view
        getHints: *const fn (ptr: *anyopaque) hints_model.HintConfig,

        /// Cleanup view resources
        deinit: *const fn (ptr: *anyopaque) void,

        /// Apply a text filter to the view's content
        applyFilter: *const fn (ptr: *anyopaque, filter: []const u8) anyerror!void = &noopApplyFilter,

        /// Clear filter and return true if a filter was active
        clearFilter: *const fn (ptr: *anyopaque) anyerror!bool = &noopClearFilter,

        /// Refresh view data from its source
        refresh: *const fn (ptr: *anyopaque) anyerror!void = &noopRefresh,

        /// Get selected resource info for describe/delete/logs
        getSelectedResource: *const fn (ptr: *anyopaque) ?ResourceInfo = &noopGetSelectedResource,
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
        // k9s-parity actions
        request_edit,
        request_shell,
        request_attach,
        request_port_forward,
        request_aliases,
        request_show_node,
        request_logs_previous,
        request_set_image,
        request_kill,
        request_sanitize,
        request_transfer,
        request_kill_finalizers,
        /// A cluster context was switched (contexts view, Enter). The app
        /// returns to the view that was active before entering contexts,
        /// refreshed against the new cluster (k9s behavior).
        context_switched,
        /// A namespace was switched (namespaces view, Enter). Handled exactly like
        /// context_switched: the previous view's onShow skips a network refresh when
        /// rows already exist, so without this the OLD namespace's rows stayed on
        /// screen while getTitle -- which reads current_namespace live -- displayed
        /// the NEW one. The title contradicted the rows.
        namespace_switched,
        /// Base64-decode the selected Secret's data (`x` on the secrets view).
        request_decode,
        /// Mark the selected node unschedulable (`c` on the nodes view).
        request_cordon,
        /// Undo a cordon (`u` on the nodes view).
        request_uncordon,
        /// Open the traffic view for the selected resource.
        request_traffic,
    };

    pub fn render(self: View, terminal_inst: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        return self.vtable.render(self.ptr, terminal_inst, x, y, width, height);
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

    pub fn getTitle(self: View) []const u8 {
        return self.vtable.getTitle(self.ptr);
    }

    pub fn getHints(self: View) hints_model.HintConfig {
        return self.vtable.getHints(self.ptr);
    }

    pub fn deinit(self: View) void {
        return self.vtable.deinit(self.ptr);
    }

    pub fn applyFilter(self: View, filter: []const u8) !void {
        return self.vtable.applyFilter(self.ptr, filter);
    }

    pub fn clearFilter(self: View) !bool {
        return self.vtable.clearFilter(self.ptr);
    }

    pub fn refresh(self: View) !void {
        return self.vtable.refresh(self.ptr);
    }

    pub fn getSelectedResource(self: View) ?ResourceInfo {
        return self.vtable.getSelectedResource(self.ptr);
    }

    /// Create a view from a concrete type
    pub fn create(comptime T: type, instance: *T, vtable: *const VTable) View {
        return View{
            .ptr = @ptrCast(instance),
            .vtable = vtable,
        };
    }

    // Default no-op implementations for optional vtable methods
    fn noopGetTitle(_: *anyopaque) []const u8 {
        return "";
    }

    fn noopApplyFilter(_: *anyopaque, _: []const u8) anyerror!void {}
    fn noopClearFilter(_: *anyopaque) anyerror!bool {
        return false;
    }
    fn noopRefresh(_: *anyopaque) anyerror!void {}
    fn noopGetSelectedResource(_: *anyopaque) ?ResourceInfo {
        return null;
    }
};

// --- Tests ---

// MockView: tracks call counts and provides controllable return values
const MockView = struct {
    render_count: usize = 0,
    handle_key_count: usize = 0,
    on_show_count: usize = 0,
    on_hide_count: usize = 0,
    get_name_count: usize = 0,
    get_hints_count: usize = 0,
    deinit_count: usize = 0,
    apply_filter_count: usize = 0,
    clear_filter_count: usize = 0,
    refresh_count: usize = 0,
    get_selected_resource_count: usize = 0,

    last_filter: []const u8 = "",
    clear_filter_return: bool = false,
    selected_resource: ?ResourceInfo = null,

    const vtable_with_defaults = View.VTable{
        .render = mockRender,
        .handleKey = mockHandleKey,
        .onShow = mockOnShow,
        .onHide = mockOnHide,
        .getName = mockGetName,
        .getHints = mockGetHints,
        .deinit = mockDeinit,
        // applyFilter, clearFilter, refresh, getSelectedResource use defaults
    };

    const vtable_with_custom = View.VTable{
        .render = mockRender,
        .handleKey = mockHandleKey,
        .onShow = mockOnShow,
        .onHide = mockOnHide,
        .getName = mockGetName,
        .getHints = mockGetHints,
        .deinit = mockDeinit,
        .applyFilter = mockApplyFilter,
        .clearFilter = mockClearFilter,
        .refresh = mockRefresh,
        .getSelectedResource = mockGetSelectedResource,
    };

    fn self(ptr: *anyopaque) *MockView {
        return @ptrCast(@alignCast(ptr));
    }

    fn mockRender(ptr: *anyopaque, _: *Terminal, _: u16, _: u16, _: u16, _: u16) anyerror!void {
        self(ptr).render_count += 1;
    }

    fn mockHandleKey(ptr: *anyopaque, _: Key) anyerror!View.KeyResult {
        self(ptr).handle_key_count += 1;
        return .handled;
    }

    fn mockOnShow(ptr: *anyopaque) void {
        self(ptr).on_show_count += 1;
    }

    fn mockOnHide(ptr: *anyopaque) void {
        self(ptr).on_hide_count += 1;
    }

    fn mockGetName(ptr: *anyopaque) []const u8 {
        self(ptr).get_name_count += 1;
        return "mock-view";
    }

    fn mockGetHints(ptr: *anyopaque) hints_model.HintConfig {
        self(ptr).get_hints_count += 1;
        return .{};
    }

    fn mockDeinit(ptr: *anyopaque) void {
        self(ptr).deinit_count += 1;
    }

    fn mockApplyFilter(ptr: *anyopaque, filter: []const u8) anyerror!void {
        const s = self(ptr);
        s.apply_filter_count += 1;
        s.last_filter = filter;
    }

    fn mockClearFilter(ptr: *anyopaque) anyerror!bool {
        const s = self(ptr);
        s.clear_filter_count += 1;
        return s.clear_filter_return;
    }

    fn mockRefresh(ptr: *anyopaque) anyerror!void {
        self(ptr).refresh_count += 1;
    }

    fn mockGetSelectedResource(ptr: *anyopaque) ?ResourceInfo {
        const s = self(ptr);
        s.get_selected_resource_count += 1;
        return s.selected_resource;
    }

    fn createView(s: *MockView, vtable: *const View.VTable) View {
        return View.create(MockView, s, vtable);
    }
};

test "View.create produces valid view with correct vtable pointer" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_defaults);

    // The vtable should be the one we passed in
    try std.testing.expect(view.vtable == &MockView.vtable_with_defaults);

    // The ptr should point to our mock (via @ptrCast round-trip)
    const recovered: *MockView = @ptrCast(@alignCast(view.ptr));
    try std.testing.expect(recovered == &mock);
}

test "default applyFilter is a no-op" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_defaults);

    // Should not crash or modify anything
    try view.applyFilter("some-filter");

    // The default no-op does not call MockView's applyFilter, so count stays 0
    try std.testing.expectEqual(@as(usize, 0), mock.apply_filter_count);
}

test "default clearFilter returns false" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_defaults);

    const result = try view.clearFilter();
    try std.testing.expect(!result);

    // Default no-op, so mock's clearFilter was not called
    try std.testing.expectEqual(@as(usize, 0), mock.clear_filter_count);
}

test "default refresh is a no-op" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_defaults);

    // Should not crash
    try view.refresh();

    try std.testing.expectEqual(@as(usize, 0), mock.refresh_count);
}

test "default getSelectedResource returns null" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_defaults);

    const result = view.getSelectedResource();
    try std.testing.expect(result == null);

    try std.testing.expectEqual(@as(usize, 0), mock.get_selected_resource_count);
}

test "custom applyFilter implementation is called correctly" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_custom);

    try view.applyFilter("test-filter");

    try std.testing.expectEqual(@as(usize, 1), mock.apply_filter_count);
    try std.testing.expectEqualStrings("test-filter", mock.last_filter);

    // Call again with different filter
    try view.applyFilter("another");
    try std.testing.expectEqual(@as(usize, 2), mock.apply_filter_count);
    try std.testing.expectEqualStrings("another", mock.last_filter);
}

test "custom clearFilter implementation returns expected value" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_custom);

    // Default return is false
    const result1 = try view.clearFilter();
    try std.testing.expect(!result1);
    try std.testing.expectEqual(@as(usize, 1), mock.clear_filter_count);

    // Change return value and call again
    mock.clear_filter_return = true;
    const result2 = try view.clearFilter();
    try std.testing.expect(result2);
    try std.testing.expectEqual(@as(usize, 2), mock.clear_filter_count);
}

test "custom getSelectedResource returns expected ResourceInfo" {
    var mock = MockView{
        .selected_resource = ResourceInfo{
            .name = "my-pod",
            .namespace = "kube-system",
        },
    };
    const view = mock.createView(&MockView.vtable_with_custom);

    const result = view.getSelectedResource();
    try std.testing.expect(result != null);

    const info = result.?;
    try std.testing.expectEqualStrings("my-pod", info.name);
    try std.testing.expectEqualStrings("kube-system", info.namespace);
    try std.testing.expectEqual(@as(usize, 1), mock.get_selected_resource_count);
}

test "KeyResult enum has expected variants" {
    // Verify all expected variants exist and are distinct
    const handled = View.KeyResult.handled;
    const not_handled = View.KeyResult.not_handled;
    const request_command_palette = View.KeyResult.request_command_palette;
    const request_filter = View.KeyResult.request_filter;
    const request_quit = View.KeyResult.request_quit;
    const request_describe = View.KeyResult.request_describe;
    const request_yaml = View.KeyResult.request_yaml;
    const request_logs = View.KeyResult.request_logs;
    const request_delete = View.KeyResult.request_delete;

    // Verify they are all distinct
    try std.testing.expect(handled != not_handled);
    try std.testing.expect(not_handled != request_command_palette);
    try std.testing.expect(request_command_palette != request_filter);
    try std.testing.expect(request_filter != request_quit);
    try std.testing.expect(request_quit != request_describe);
    try std.testing.expect(request_describe != request_yaml);
    try std.testing.expect(request_yaml != request_logs);
    try std.testing.expect(request_logs != request_delete);
}

test "ResourceInfo struct stores name and namespace" {
    const info = ResourceInfo{
        .name = "nginx-deployment",
        .namespace = "production",
    };

    try std.testing.expectEqualStrings("nginx-deployment", info.name);
    try std.testing.expectEqualStrings("production", info.namespace);

    // Test with empty values
    const empty_info = ResourceInfo{
        .name = "",
        .namespace = "",
    };
    try std.testing.expectEqualStrings("", empty_info.name);
    try std.testing.expectEqualStrings("", empty_info.namespace);
}
