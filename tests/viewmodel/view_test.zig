const std = @import("std");
const testing = std.testing;
const c3s = @import("c3s");
const View = c3s.View;
const Key = c3s.Key;
const Terminal = c3s.Terminal;
const ResourceInfo = c3s.ResourceInfo;
const hints_model = c3s.hints;

// --- MockView: tracks call counts and provides controllable return values ---

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

// --- Tests ---

test "View.create produces valid view with correct vtable pointer" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_defaults);

    // The vtable should be the one we passed in
    try testing.expect(view.vtable == &MockView.vtable_with_defaults);

    // The ptr should point to our mock (via @ptrCast round-trip)
    const recovered: *MockView = @ptrCast(@alignCast(view.ptr));
    try testing.expect(recovered == &mock);
}

test "default applyFilter is a no-op" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_defaults);

    // Should not crash or modify anything
    try view.applyFilter("some-filter");

    // The default no-op does not call MockView's applyFilter, so count stays 0
    try testing.expectEqual(@as(usize, 0), mock.apply_filter_count);
}

test "default clearFilter returns false" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_defaults);

    const result = try view.clearFilter();
    try testing.expect(!result);

    // Default no-op, so mock's clearFilter was not called
    try testing.expectEqual(@as(usize, 0), mock.clear_filter_count);
}

test "default refresh is a no-op" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_defaults);

    // Should not crash
    try view.refresh();

    try testing.expectEqual(@as(usize, 0), mock.refresh_count);
}

test "default getSelectedResource returns null" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_defaults);

    const result = view.getSelectedResource();
    try testing.expect(result == null);

    try testing.expectEqual(@as(usize, 0), mock.get_selected_resource_count);
}

test "custom applyFilter implementation is called correctly" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_custom);

    try view.applyFilter("test-filter");

    try testing.expectEqual(@as(usize, 1), mock.apply_filter_count);
    try testing.expectEqualStrings("test-filter", mock.last_filter);

    // Call again with different filter
    try view.applyFilter("another");
    try testing.expectEqual(@as(usize, 2), mock.apply_filter_count);
    try testing.expectEqualStrings("another", mock.last_filter);
}

test "custom clearFilter implementation returns expected value" {
    var mock = MockView{};
    const view = mock.createView(&MockView.vtable_with_custom);

    // Default return is false
    const result1 = try view.clearFilter();
    try testing.expect(!result1);
    try testing.expectEqual(@as(usize, 1), mock.clear_filter_count);

    // Change return value and call again
    mock.clear_filter_return = true;
    const result2 = try view.clearFilter();
    try testing.expect(result2);
    try testing.expectEqual(@as(usize, 2), mock.clear_filter_count);
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
    try testing.expect(result != null);

    const info = result.?;
    try testing.expectEqualStrings("my-pod", info.name);
    try testing.expectEqualStrings("kube-system", info.namespace);
    try testing.expectEqual(@as(usize, 1), mock.get_selected_resource_count);
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
    try testing.expect(handled != not_handled);
    try testing.expect(not_handled != request_command_palette);
    try testing.expect(request_command_palette != request_filter);
    try testing.expect(request_filter != request_quit);
    try testing.expect(request_quit != request_describe);
    try testing.expect(request_describe != request_yaml);
    try testing.expect(request_yaml != request_logs);
    try testing.expect(request_logs != request_delete);
}

test "ResourceInfo struct stores name and namespace" {
    const info = ResourceInfo{
        .name = "nginx-deployment",
        .namespace = "production",
    };

    try testing.expectEqualStrings("nginx-deployment", info.name);
    try testing.expectEqualStrings("production", info.namespace);

    // Test with empty values
    const empty_info = ResourceInfo{
        .name = "",
        .namespace = "",
    };
    try testing.expectEqualStrings("", empty_info.name);
    try testing.expectEqualStrings("", empty_info.namespace);
}
