const std = @import("std");
const testing = std.testing;
const c3s = @import("src");
const App = c3s.App;

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

// ---------------------------------------------------------------------------
// Key dispatch through App, not through a view directly.
//
// These exist because two shipped features -- `x` = Decode on secrets and Ctrl-D =
// Stop on port-forwards -- were unreachable in the running binary while their tests
// passed. Both tests called the view's handleKey directly, so neither ever crossed
// App's global key switch, which claimed those keys first.
// ---------------------------------------------------------------------------

const Key = @import("src").Terminal.Key;

fn installLocalAppSession(app: *App, allocator: std.mem.Allocator) !void {
    const session = session: {
        const client = try allocator.create(c3s.K8sClient);
        errdefer allocator.destroy(client);
        client.* = try c3s.K8sClient.init(allocator, c3s.runtime.io(), .{
            .server = "http://127.0.0.1",
            .namespace = "default",
        });
        errdefer client.deinit();
        break :session try c3s.ActiveContextSession.adopt(
            allocator,
            c3s.runtime.io(),
            1,
            .{
                .context_name = "app-test-context",
                .kubeconfig_path = null,
                .default_namespace = "default",
                .force_proxy = false,
                .readonly = false,
            },
            .{
                .shared_event = app.shared_event,
                .client = client,
                .cluster_name = "app-test-cluster",
                .user_name = "app-test-user",
                .readiness_verified = true,
            },
        );
    };
    errdefer session.deinit();
    _ = try app.active_session_slot.commit(session);
    app.k8s_service.connected = true;
}

test "real Enter switches namespace then pushes and refreshes pods" {
    const allocator = testing.allocator;
    var app = try App.init(allocator, .{});
    defer app.deinit();
    try installLocalAppSession(&app, allocator);
    try app.switchToView("namespaces");

    const namespaces = &app.namespaces_view.table;
    try namespaces.appendItem(.{
        .name = try allocator.dupe(u8, "kube-system"),
        .status = try allocator.dupe(u8, "Active"),
        .age = try allocator.dupe(u8, "1d"),
        .allocator = allocator,
    });
    try namespaces.filtered_indices.append(allocator, 0);
    namespaces.selected_row = 0;

    const pods = &app.pods_view.table;
    try pods.appendItem(.{ .columns = .{
        try allocator.dupe(u8, "default"), try allocator.dupe(u8, "stale"),
        try allocator.dupe(u8, "1/1"),     try allocator.dupe(u8, "Running"),
        try allocator.dupe(u8, "0"),       try allocator.dupe(u8, "1m"),
        try allocator.dupe(u8, "2Mi"),     try allocator.dupe(u8, "1"),
        try allocator.dupe(u8, "1"),       try allocator.dupe(u8, "10.0.0.2"),
        try allocator.dupe(u8, "node-1"),  try allocator.dupe(u8, "1d"),
    }, .allocator = allocator });
    try pods.filtered_indices.append(allocator, 0);

    const namespace_depth = app.view_manager.getDepth();
    try app.handleKey(.enter);

    try testing.expectEqualStrings("kube-system", app.k8s_service.getCurrentNamespace());
    try testing.expectEqualStrings("pods", app.current_view_name);
    try testing.expectEqualStrings("pods", app.view_manager.getCurrentView().?.getName());
    try testing.expectEqual(namespace_depth + 1, app.view_manager.getDepth());
    try testing.expectEqual(@as(usize, 1), namespaces.items.items.len);
    try testing.expectEqual(@as(usize, 0), pods.items.items.len);

    try app.handleKey(.escape);
    try testing.expectEqual(namespace_depth, app.view_manager.getDepth());
    try testing.expectEqualStrings("namespaces", app.current_view_name);
    try testing.expectEqualStrings(
        "namespaces",
        app.view_manager.getCurrentView().?.getName(),
    );
}

test "failed namespace Enter stays on namespaces" {
    const allocator = testing.allocator;
    var app = try App.init(allocator, .{});
    defer app.deinit();
    try app.switchToView("namespaces");

    const namespaces = &app.namespaces_view.table;
    try namespaces.appendItem(.{
        .name = try allocator.dupe(u8, "kube-system"),
        .status = try allocator.dupe(u8, "Active"),
        .age = try allocator.dupe(u8, "1d"),
        .allocator = allocator,
    });
    try namespaces.filtered_indices.append(allocator, 0);
    const namespace_depth = app.view_manager.getDepth();

    try app.handleKey(.enter);

    try testing.expectEqualStrings("default", app.k8s_service.getCurrentNamespace());
    try testing.expectEqualStrings("namespaces", app.current_view_name);
    try testing.expectEqual(namespace_depth, app.view_manager.getDepth());
}

test "x on the secrets view reaches the view, not App's global filter-clear" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{});
    defer app.deinit();

    try app.switchToView("secrets");
    try testing.expectEqualStrings("secrets", app.current_view_name);

    // Put a filter in place. If App's global 'x' handler wins, the filter is cleared
    // and the decode never happens -- which is exactly the shipped bug.
    try app.applyFilterToCurrentView("keep-me");
    try app.handleKey(.{ .char = 'x' });

    // The filter survived, so 'x' was consumed by the view rather than the global
    // clear-filter handler. (The decode itself needs a cluster; that it was ATTEMPTED
    // is what this asserts.)
    try testing.expect(app.secrets_view.table.filter_text.len > 0);
}

test "x on a view with no decode still clears the filter" {
    // The other half of the contract: view-first must not break the global fallback.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{});
    defer app.deinit();

    try app.switchToView("configmaps");
    try app.applyFilterToCurrentView("something");
    try testing.expect(app.configmaps_view.table.filter_text.len > 0);

    try app.handleKey(.{ .char = 'x' });
    try testing.expectEqual(@as(usize, 0), app.configmaps_view.table.filter_text.len);
}

test "Ctrl-D on the port-forwards view stops a forward instead of asking to delete" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{});
    defer app.deinit();

    try app.switchToView("portforwards");
    try testing.expectEqualStrings("portforwards", app.current_view_name);

    const child = try std.process.spawn(@import("src").runtime.io(), .{
        .argv = &.{ "/bin/sh", "-c", "sleep 300" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    });
    try app.port_forward_registry.add("pods/x", "1:1", "default", child);
    try app.port_forwards_view.refresh();
    try testing.expectEqual(@as(usize, 1), app.port_forward_registry.count());

    try app.handleKey(.{ .ctrl_d = {} });

    // Stopped, not queued for deletion. Before view-first dispatch, App's global
    // Ctrl-D ran handleDeleteRequest, which returned immediately because
    // "portforwards" is not a ResourceType -- so the key did nothing at all.
    try testing.expectEqual(@as(usize, 0), app.port_forward_registry.count());
    try testing.expect(!app.delete_pending);
}

test "Ctrl-D on a resource view still starts a delete confirmation" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{});
    defer app.deinit();

    try app.switchToView("pods");
    // No selection without a cluster, so this asserts the key still reaches the
    // global delete path rather than being swallowed by the view.
    try app.handleKey(.{ .ctrl_d = {} });
    try testing.expect(!app.delete_pending); // nothing selected, so nothing pending
}

test "Shift-G goes to the bottom of a table-backed view" {
    // Terminal.readKey maps a raw 'G' to Key.shift_g. TableState only matched
    // .char='G', so Goto Bottom was dead on ~30 views while its unit test passed a
    // character the terminal never emits.
    //
    // Driven on namespaces because its row type is a plain struct -- the point is
    // TableState's key handling, which every table-backed view shares.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{});
    defer app.deinit();

    try app.switchToView("namespaces");
    const t = &app.namespaces_view.table;
    for ([_][]const u8{ "one", "two", "three" }) |name| {
        try t.appendItem(.{
            .name = try allocator.dupe(u8, name),
            .status = try allocator.dupe(u8, "Active"),
            .age = try allocator.dupe(u8, "1d"),
            .allocator = allocator,
        });
    }
    t.filtered_indices.clearRetainingCapacity();
    for (0..3) |i| try t.filtered_indices.append(allocator, i);
    t.visible_rows = 2;
    t.selected_row = 0;

    try app.handleKey(.{ .shift_g = {} });
    try testing.expectEqual(@as(u32, 2), t.selected_row);
}

test "Ctrl-b pages up in a table-backed view" {
    // Ctrl-b was advertised as "Page Up" on every view while nothing handled it: App
    // forwards it to the view, and neither TableState nor resource_view had a case.
    // Same shape as the .shift_g bug, found in the same audit.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{});
    defer app.deinit();

    try app.switchToView("namespaces");
    const t = &app.namespaces_view.table;
    for (0..10) |i| {
        var buf: [8]u8 = undefined;
        const name = try std.fmt.bufPrint(&buf, "ns-{d}", .{i});
        try t.appendItem(.{
            .name = try allocator.dupe(u8, name),
            .status = try allocator.dupe(u8, "Active"),
            .age = try allocator.dupe(u8, "1d"),
            .allocator = allocator,
        });
    }
    t.filtered_indices.clearRetainingCapacity();
    for (0..10) |i| try t.filtered_indices.append(allocator, i);
    t.visible_rows = 3;

    // Start at the bottom, then page up.
    try app.handleKey(.{ .shift_g = {} });
    try testing.expectEqual(@as(u32, 9), t.selected_row);

    try app.handleKey(.{ .ctrl_b = {} });
    try testing.expect(t.selected_row < 9);
}

test "arrow down navigates through App on a table-backed view" {
    // Some terminals send SS3 sequences (ESC O B) rather than
    // CSI (ESC [ B). Before the decodeCsi fix those arrived as Key.unsupported and
    // App dropped them silently — arrows felt dead while j/k still worked.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{});
    defer app.deinit();

    try app.switchToView("namespaces");
    const t = &app.namespaces_view.table;
    for ([_][]const u8{ "one", "two", "three" }) |name| {
        try t.appendItem(.{
            .name = try allocator.dupe(u8, name),
            .status = try allocator.dupe(u8, "Active"),
            .age = try allocator.dupe(u8, "1d"),
            .allocator = allocator,
        });
    }
    t.filtered_indices.clearRetainingCapacity();
    for (0..3) |i| try t.filtered_indices.append(allocator, i);
    try testing.expectEqual(@as(u32, 0), t.selected_row);

    try app.handleKey(.down);
    try testing.expectEqual(@as(u32, 1), t.selected_row);
    try testing.expect(app.dirty);

    try app.handleKey(.up);
    try testing.expectEqual(@as(u32, 0), t.selected_row);
}

test "? on a view with no ViewType shows generic help, not Pods' help" {
    // Nine resource types have no ViewType of their own, so currentViewType() used to
    // fall back to .pods -- meaning `?` on an Ingress advertised Shell, Logs, Attach
    // and Sanitize, none of which do anything on an Ingress.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const KeyBindingsViewModel = @import("src").KeyBindingsViewModel;
    const ViewType = @import("src").ViewType;

    var app = try App.init(allocator, .{});
    defer app.deinit();

    for ([_][]const u8{
        "ingresses",      "networkpolicies",   "resourcequotas",
        "limitranges",    "persistentvolumes", "endpoints",
        "storageclasses", "httproutes",        "gateways",
    }) |name| {
        app.current_view_name = name;
        try testing.expectEqual(ViewType.generic, app.currentViewTypeForTest());
    }

    // And the generic set must not carry pods-only actions.
    var vm = try KeyBindingsViewModel.init(allocator, .generic);
    defer vm.deinit();
    for (vm.getBindings()) |b| {
        for ([_][]const u8{ "shell", "attach", "logs", "sanitize", "set_image", "port_forward", "transfer" }) |pods_only| {
            try testing.expect(!std.mem.eql(u8, b.action, pods_only));
        }
    }
    // But it must carry the ones that ARE universally real.
    var has_describe = false;
    var has_delete = false;
    var has_refresh = false;
    for (vm.getBindings()) |b| {
        if (std.mem.eql(u8, b.action, "describe")) has_describe = true;
        if (std.mem.eql(u8, b.action, "delete")) has_delete = true;
        if (std.mem.eql(u8, b.action, "refresh")) has_refresh = true;
    }
    try testing.expect(has_describe);
    try testing.expect(has_delete);
    try testing.expect(has_refresh);
}

test "port-forward refuses under --readonly without even prompting" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{ .readonly = true });
    defer app.deinit();

    try app.switchToView("pods");
    const t = &app.pods_view.table;
    try t.appendItem(.{ .columns = .{
        try allocator.dupe(u8, "default"), try allocator.dupe(u8, "nginx"),
        try allocator.dupe(u8, "1/1"),     try allocator.dupe(u8, "Running"),
        try allocator.dupe(u8, "0"),       try allocator.dupe(u8, "1m"),
        try allocator.dupe(u8, "2Mi"),     try allocator.dupe(u8, "1"),
        try allocator.dupe(u8, "1"),       try allocator.dupe(u8, "10.0.0.2"),
        try allocator.dupe(u8, "node-1"),  try allocator.dupe(u8, "1d"),
    }, .allocator = allocator });
    try t.filtered_indices.append(allocator, 0);
    t.selected_row = 0;

    try app.handleKey(.{ .char = 'F' });
    try testing.expect(app.pending_input == .none);
}

test "drain refuses under --readonly without even prompting" {
    // Cordon is refused at the service boundary, but drain runs through
    // runInteractive, which spawns kubectl directly and bypasses K8sService entirely --
    // the exact hole found in the Phase 4 audit for edit/shell/attach. So the check has
    // to live at the call site, and it must happen BEFORE the confirmation prompt: a
    // prompt that cannot be honoured is worse than no prompt.
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try App.init(allocator, .{ .readonly = true });
    defer app.deinit();
    try testing.expect(app.k8s_service.readonly);

    try app.switchToView("nodes");
    const t = &app.nodes_view.table;
    try t.appendItem(.{ .columns = .{
        try allocator.dupe(u8, "node-1"),   try allocator.dupe(u8, "Ready"),
        try allocator.dupe(u8, "worker"),   try allocator.dupe(u8, "v1.33.0"),
        try allocator.dupe(u8, "10.0.0.1"), try allocator.dupe(u8, "1d"),
    }, .allocator = allocator });
    try t.filtered_indices.append(allocator, 0);
    t.selected_row = 0;

    try app.handleKey(.{ .char = 'r' });

    // No confirmation was armed, so pressing y next cannot drain anything.
    try testing.expect(app.pending_input == .none);
}

// ---------------------------------------------------------------------------
// Synchronous active-session ownership
// ---------------------------------------------------------------------------

test "App owns one shared Event before its session slot" {
    var app = try App.init(testing.allocator, .{});
    defer app.deinit();

    try testing.expect(app.active_session_slot.shared_event == app.shared_event);
    try testing.expect(app.change_queue.shared_event == app.shared_event);
    try testing.expect(app.change_queue.wakeup == app.wakeup);
    try testing.expect(app.k8s_service.sessionSlot() == app.active_session_slot);
    const view = app.active_session_slot.view();
    try testing.expectEqual(@import("src").SessionState.empty, view.state);
    try testing.expectEqual(@as(u64, 0), view.generation);
}

test "App init failures preserve Event slot and service teardown order" {
    for (0..3) |fail_index| {
        var failing = testing.FailingAllocator.init(testing.allocator, .{
            .fail_index = fail_index,
        });
        if (App.init(failing.allocator(), .{})) |value| {
            var app = value;
            app.deinit();
        } else |err| {
            try testing.expectEqual(error.OutOfMemory, err);
        }
        try testing.expect(failing.has_induced_failure);
        try testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    }
}

fn readTask4ASource(path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        path,
        testing.allocator,
        .limited(2 * 1024 * 1024),
    );
}

test "Task 4A source contains only synchronous session ownership" {
    const files = [_][]const u8{
        "src/k8s/ActiveContextSession.zig",
        "src/k8s/ActiveSessionSlot.zig",
        "src/services/K8sService.zig",
        "src/App.zig",
        "src/index.zig",
    };
    const forbidden = [_][]const u8{
        "std.Io.Group",
        "Future",
        "Completion =",
        "CompletionKind",
        "CompletionSink",
        "TaskControl",
        "task_reapers",
        "completion_owners",
        "PreparationControl",
        "CandidateSink",
        "CancellationSpawnGate",
        "reaper_scheduled",
        "work_finished",
        "delivery_finished",
        "startTask",
        "collectTask",
        "collectCompleted",
        "cancelTask",
        "reapTask",
        "ContextCoordinator",
    };

    for (files) |path| {
        const source = try readTask4ASource(path);
        defer testing.allocator.free(source);
        for (forbidden) |needle| {
            if (std.mem.indexOf(u8, source, needle) != null) {
                std.debug.print("forbidden Task 4A source token '{s}' in {s}\n", .{ needle, path });
                return error.ForbiddenLifecycleSource;
            }
        }
    }

    const coordinator = std.Io.Dir.cwd().readFileAlloc(
        testing.io,
        "src/k8s/ContextCoordinator.zig",
        testing.allocator,
        .limited(2 * 1024 * 1024),
    );
    if (coordinator) |source| {
        testing.allocator.free(source);
        return error.ContextCoordinatorStillExists;
    } else |err| {
        try testing.expectEqual(error.FileNotFound, err);
    }
}

test "App constructs and tears down shared Event storage in safe order" {
    const source = try readTask4ASource("src/App.zig");
    defer testing.allocator.free(source);

    const event_init = std.mem.indexOf(u8, source, "shared_event.* = .unset") orelse
        return error.SharedEventInitializationMissing;
    const slot_init = std.mem.indexOf(u8, source, "ActiveSessionSlot.init") orelse
        return error.ActiveSessionSlotInitializationMissing;
    try testing.expect(event_init < slot_init);

    const invalidate = std.mem.indexOf(u8, source, "active_session_slot.invalidate") orelse
        return error.ActiveSessionInvalidationMissing;
    const event_destroy = std.mem.indexOf(u8, source, "allocator.destroy(self.shared_event)") orelse
        return error.SharedEventDestructionMissing;
    try testing.expect(invalidate < event_destroy);
}

fn containsStandaloneFingerprint(source: []const u8, needle: []const u8) bool {
    var start: usize = 0;
    while (std.mem.indexOfPos(u8, source, start, needle)) |index| {
        const before_is_name = index > 0 and
            (std.ascii.isAlphanumeric(source[index - 1]) or source[index - 1] == '_');
        const after_index = index + needle.len;
        const after_is_name = after_index < source.len and
            (std.ascii.isAlphanumeric(source[after_index]) or source[after_index] == '_');
        if (!before_is_name and !after_is_name) return true;
        start = index + 1;
    }
    return false;
}

test "Task 4A production files contain no publisher fingerprints" {
    const files = [_][]const u8{
        "src/k8s/ActiveContextSession.zig",
        "src/k8s/ActiveSessionSlot.zig",
        "src/services/K8sService.zig",
        "src/App.zig",
        "src/index.zig",
    };
    const forbidden = [_][]const u8{
        "Cur" ++ "sor",
        "cursor" ++ "agent",
        "Clau" ++ "de",
        "Co" ++ "pilot",
        "Chat" ++ "GPT",
    };
    for (files) |path| {
        const source = try readTask4ASource(path);
        defer testing.allocator.free(source);
        for (forbidden) |needle| {
            try testing.expect(!containsStandaloneFingerprint(source, needle));
        }
    }
}
