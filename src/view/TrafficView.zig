/// TrafficView — live Istio/Prometheus traffic topology for a workload.
///
/// Pressing 't' on any resource (scoped to deployments in resource_view.zig)
/// opens this full-screen view. It queries Prometheus via the kubectl API-server
/// proxy in a BACKGROUND THREAD (k9s-style), builds a TrafficModel, renders
/// the graph + table from kubectl_traffic's render modules, and caches the
/// result. The main thread (render) only reads cached bytes under a mutex — the
/// UI never freezes waiting for network.
///
/// Keys:
///   q / Esc  — pop view (return to caller)
///   r        — force background re-query
///   j / k / ↑ / ↓ — scroll the output
const std = @import("std");
const View = @import("../viewmodel/view.zig").View;
const Terminal = @import("../core/Terminal.zig").Terminal;
const Key = @import("../core/Terminal.zig").Key;
const Logger = @import("../core/logger.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const K8sService = @import("../services/K8sService.zig").K8sService;
const runtime = @import("../core/runtime.zig");
const kt = @import("kubectl_traffic");

pub const TrafficView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,

    /// Target workload name and namespace (set before pushing the view).
    workload: []const u8 = "",
    namespace: []const u8 = "",

    // --- Background worker state ---
    // Zig 0.16: std.Thread.Mutex is gone; use std.Io.Mutex with
    // lockUncancelable(io)/unlock(io) from runtime.io().
    mutex: std.Io.Mutex = std.Io.Mutex.init,
    worker: ?std.Thread = null,
    should_stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    force_refresh: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    /// Pointer to App.redraw_request — set via setWake() before onShow.
    wake: ?*std.atomic.Value(bool) = null,

    // --- Cached render output (owned by cached_arena) ---
    cached_arena: ?std.heap.ArenaAllocator = null,
    cached_lines: ?[]kt.line.StyledLine = null,
    state: enum { loading, ready, err } = .loading,

    scroll_offset: u32 = 0,
    visible_rows: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) TrafficView {
        return .{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
        };
    }

    pub fn deinit(self: *TrafficView) void {
        self.stopWorker();
        if (self.cached_arena) |*ar| {
            ar.deinit();
            self.cached_arena = null;
        }
        self.cached_lines = null;
    }

    fn stopWorker(self: *TrafficView) void {
        self.should_stop.store(true, .release);
        if (self.worker) |w| {
            w.join();
            self.worker = null;
        }
    }

    /// Set the wake pointer (App.redraw_request). Call before onShow/pushView.
    pub fn setWake(self: *TrafficView, w: *std.atomic.Value(bool)) void {
        self.wake = w;
    }

    /// Set the target workload before pushing this view. Strings are NOT owned
    /// by TrafficView — caller (App) must keep them alive for the view's lifetime.
    pub fn setTarget(self: *TrafficView, workload: []const u8, namespace: []const u8) void {
        // Worker must be stopped before touching cached state.
        // setTarget is always called before onShow (worker not running), so this is safe.
        self.workload = workload;
        self.namespace = namespace;
        self.scroll_offset = 0;
        // Drop any stale cached data.
        if (self.cached_arena) |*ar| {
            ar.deinit();
            self.cached_arena = null;
        }
        self.cached_lines = null;
        self.state = .loading;
    }

    // =========================================================================
    // Background worker
    // =========================================================================

    /// Worker entry point. Loops: fetch → publish → sleep 5 s → repeat.
    /// Wakes App's run loop via the `wake` atomic after each fetch.
    ///
    /// Sleep uses std.c.nanosleep (via libc) because std.Thread.sleep was
    /// removed in Zig 0.16.
    fn workerMain(self: *TrafficView) void {
        // 5-second refresh interval broken into 100ms steps so we can wake
        // early on force_refresh or should_stop.
        const step_ns: c_long = 100 * std.time.ns_per_ms;
        const steps_per_refresh: u32 = 50; // 50 × 100ms = 5s

        while (!self.should_stop.load(.acquire)) {
            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            const a = arena.allocator();

            const result = self.fetchFrame(a);

            self.mutex.lockUncancelable(runtime.io());
            if (self.cached_arena) |*old| old.deinit();
            if (result) |lines| {
                self.cached_arena = arena;
                self.cached_lines = lines;
                self.state = .ready;
            } else |_| {
                arena.deinit();
                self.cached_arena = null;
                self.cached_lines = null;
                self.state = .err;
            }
            self.mutex.unlock(runtime.io());

            if (self.wake) |w| w.store(true, .release);

            // Sleep up to 5s, waking early on stop or force_refresh.
            var steps: u32 = 0;
            while (steps < steps_per_refresh and !self.should_stop.load(.acquire)) {
                if (self.force_refresh.swap(false, .acq_rel)) break;
                const req = std.c.timespec{ .sec = 0, .nsec = step_ns };
                _ = std.c.nanosleep(&req, null);
                steps += 1;
            }
        }
    }

    /// Fetch Prometheus data and render into StyledLines, all allocated from `a`.
    /// Uses kubectlRequestAlloc so the worker's arena owns the response bodies;
    /// no App GPA allocation happens on the worker thread for the long-lived data.
    fn fetchFrame(self: *TrafficView, a: std.mem.Allocator) ![]kt.line.StyledLine {
        var model = kt.model.TrafficModel.init(a, 60);
        defer model.deinit();

        const tgt = kt.discovery.default();

        const DirSpec = struct {
            pq: kt.promql.Direction,
            md: kt.model.Direction,
            peer_label: []const u8,
            ns_label: []const u8,
        };
        const dir_specs = [_]DirSpec{
            .{
                .pq = .inbound,
                .md = .inbound,
                .peer_label = "source_workload",
                .ns_label = "source_workload_namespace",
            },
            .{
                .pq = .outbound,
                .md = .outbound,
                .peer_label = "destination_workload",
                .ns_label = "destination_workload_namespace",
            },
        };

        for (dir_specs) |ds| {
            // ---- rate ----
            const q_rate = try kt.promql.rate(a, ds.pq, self.workload, self.namespace);
            const path_rate = try kt.prom_client.proxyQueryPath(a, tgt.namespace, tgt.service, tgt.port, q_rate);
            if (self.k8s_service.kubectlRequestAlloc(a, path_rate)) |body| {
                var vec = kt.prom_client.parseVector(a, body) catch null;
                if (vec) |*v| {
                    defer v.deinit();
                    for (v.samples) |s| {
                        const peer_name = s.labels.get(ds.peer_label) orelse "unknown";
                        const peer_ns = s.labels.get(ds.ns_label) orelse "";
                        try model.setRate(ds.md, peer_name, peer_ns, s.value);
                    }
                }
            } else |_| {}

            // ---- error rate ----
            const q_err = try kt.promql.errorRate(a, ds.pq, self.workload, self.namespace);
            const path_err = try kt.prom_client.proxyQueryPath(a, tgt.namespace, tgt.service, tgt.port, q_err);
            if (self.k8s_service.kubectlRequestAlloc(a, path_err)) |body| {
                var vec = kt.prom_client.parseVector(a, body) catch null;
                if (vec) |*v| {
                    defer v.deinit();
                    for (v.samples) |s| {
                        const peer_name = s.labels.get(ds.peer_label) orelse "unknown";
                        const peer_ns = s.labels.get(ds.ns_label) orelse "";
                        try model.setErrorRate(ds.md, peer_name, peer_ns, s.value);
                    }
                }
            } else |_| {}

            // ---- latency p50 + p99 — query both then pair by peer ----
            const q_p50 = try kt.promql.latency(a, ds.pq, self.workload, self.namespace, 0.5);
            const path_p50 = try kt.prom_client.proxyQueryPath(a, tgt.namespace, tgt.service, tgt.port, q_p50);

            const q_p99 = try kt.promql.latency(a, ds.pq, self.workload, self.namespace, 0.99);
            const path_p99 = try kt.prom_client.proxyQueryPath(a, tgt.namespace, tgt.service, tgt.port, q_p99);

            // Build a temporary map of peer_name -> p50_ms from p50 query.
            // Keys are arena-allocated; arena outlives the map so safe to reference.
            var p50_map = std.StringHashMap(f64).init(a);
            defer p50_map.deinit();

            if (self.k8s_service.kubectlRequestAlloc(a, path_p50)) |body| {
                var vec = kt.prom_client.parseVector(a, body) catch null;
                if (vec) |*v| {
                    defer v.deinit();
                    for (v.samples) |s| {
                        const peer_name = s.labels.get(ds.peer_label) orelse "unknown";
                        try p50_map.put(peer_name, s.value);
                    }
                }
            } else |_| {}

            if (self.k8s_service.kubectlRequestAlloc(a, path_p99)) |body| {
                var vec = kt.prom_client.parseVector(a, body) catch null;
                if (vec) |*v| {
                    defer v.deinit();
                    for (v.samples) |s| {
                        const peer_name = s.labels.get(ds.peer_label) orelse "unknown";
                        const peer_ns = s.labels.get(ds.ns_label) orelse "";
                        const p50 = p50_map.get(peer_name) orelse 0.0;
                        try model.setLatency(ds.md, peer_name, peer_ns, p50, s.value);
                    }
                }
            } else |_| {}
        }

        model.commitTick();

        // Render graph + table, all in `a`.
        const g = try kt.graph.render(a, &model, self.workload, self.namespace, 6);
        const t = try kt.table.render(a, &model);

        // Blank separator line between graph and table.
        const sep_spans = try a.alloc(kt.line.Span, 1);
        sep_spans[0] = .{ .text = try a.dupe(u8, ""), .color = .default };
        const sep_line = kt.line.StyledLine{ .spans = sep_spans };

        const total = g.len + 1 + t.len;
        var all = try a.alloc(kt.line.StyledLine, total);
        @memcpy(all[0..g.len], g);
        all[g.len] = sep_line;
        @memcpy(all[g.len + 1 .. g.len + 1 + t.len], t);

        return all;
    }

    // =========================================================================
    // Rendering helpers
    // =========================================================================

    fn ansiColor(color: kt.line.Color, theme: *const theme_loader.ThemeColors) []const u8 {
        return switch (color) {
            .default => theme.main_fg,
            .dim => theme.inactive_fg,
            .green => theme.status_running,
            .yellow => theme.status_pending,
            .red => theme.status_failed,
            .cyan => theme.title_highlight,
        };
    }

    // =========================================================================
    // View trait
    // =========================================================================

    pub fn createView(self: *TrafficView) View {
        return View.create(TrafficView, self, &vtable);
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinitView,
        .refresh = vtableRefresh,
    };

    fn render(ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));
        self.visible_rows = if (height > 0) height else 0;

        if (!self.k8s_service.isConnected()) {
            const msg = "Not connected — traffic data unavailable";
            try theme_loader.writeStringWithTheme(terminal, x, y, msg, self.theme.inactive_fg, self.theme.main_bg);
            return;
        }

        self.mutex.lockUncancelable(runtime.io());
        defer self.mutex.unlock(runtime.io());

        switch (self.state) {
            .loading => {
                const msg = "Loading traffic data…";
                try theme_loader.writeStringWithTheme(terminal, x, y, msg, self.theme.inactive_fg, self.theme.main_bg);
                return;
            },
            .err => {
                const msg = "Failed to fetch traffic data — check Prometheus connectivity";
                try theme_loader.writeStringWithTheme(terminal, x, y, msg, self.theme.status_failed, self.theme.main_bg);
                return;
            },
            .ready => {},
        }

        const lines = self.cached_lines orelse {
            const msg = "No traffic data";
            try theme_loader.writeStringWithTheme(terminal, x, y, msg, self.theme.inactive_fg, self.theme.main_bg);
            return;
        };

        const total: u32 = @intCast(lines.len);
        if (total == 0) {
            try theme_loader.writeStringWithTheme(terminal, x, y, "No traffic data", self.theme.inactive_fg, self.theme.main_bg);
            return;
        }

        // Clamp scroll.
        if (self.visible_rows > 0 and self.scroll_offset + self.visible_rows > total) {
            self.scroll_offset = if (total > self.visible_rows) total - self.visible_rows else 0;
        }

        const end_row = @min(self.scroll_offset + self.visible_rows, total);
        for (lines[self.scroll_offset..end_row], 0..) |line, display_idx| {
            const row_y = y + @as(u16, @intCast(display_idx));
            try terminal.setCursor(x, row_y);
            var col: u16 = 0;
            for (line.spans) |span| {
                if (col >= width) break;
                const fg = ansiColor(span.color, self.theme);
                try terminal.writeAll(fg);
                try terminal.writeAll(self.theme.main_bg);
                const avail = width - col;
                const text_len = @min(span.text.len, avail);
                try terminal.writeAll(span.text[0..text_len]);
                try terminal.writeAll("\x1b[0m");
                col += @intCast(text_len);
                // Separate adjacent spans with a space so table columns don't run together.
                if (col < width) {
                    try terminal.writeAll(" ");
                    col += 1;
                }
            }
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !View.KeyResult {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));

        switch (key) {
            .char => |c| switch (c) {
                'q' => return .not_handled,
                'r' => {
                    self.force_refresh.store(true, .release);
                    return .handled;
                },
                'j' => {
                    self.mutex.lockUncancelable(runtime.io());
                    const total: u32 = if (self.cached_lines) |l| @intCast(l.len) else 0;
                    self.mutex.unlock(runtime.io());
                    if (self.visible_rows > 0 and self.scroll_offset + self.visible_rows < total) {
                        self.scroll_offset += 1;
                    }
                    return .handled;
                },
                'k' => {
                    if (self.scroll_offset > 0) self.scroll_offset -= 1;
                    return .handled;
                },
                else => return .not_handled,
            },
            .down => {
                self.mutex.lockUncancelable(runtime.io());
                const total: u32 = if (self.cached_lines) |l| @intCast(l.len) else 0;
                self.mutex.unlock(runtime.io());
                if (self.visible_rows > 0 and self.scroll_offset + self.visible_rows < total) {
                    self.scroll_offset += 1;
                }
                return .handled;
            },
            .up => {
                if (self.scroll_offset > 0) self.scroll_offset -= 1;
                return .handled;
            },
            .escape => return .not_handled,
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));
        if (self.worker == null) {
            self.should_stop.store(false, .release);
            self.state = .loading;
            self.worker = std.Thread.spawn(.{}, workerMain, .{self}) catch null;
            Logger.info("TrafficView: worker thread started for {s}/{s}", .{ self.workload, self.namespace });
        }
    }

    fn onHide(ptr: *anyopaque) void {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));
        self.stopWorker();
        Logger.info("TrafficView: worker thread stopped", .{});
    }

    fn getName(_: *anyopaque) []const u8 {
        return "traffic";
    }

    fn getHints(_: *anyopaque) hints_model.HintConfig {
        const hints = comptime [_]hints_model.Hint{
            hints_model.Hint.highlighted("r", "", "efresh", 10),
            hints_model.Hint.plain("<q/Esc> back", 20),
            hints_model.Hint.highlighted("j", "", "/k scroll", 30),
        };
        return hints_model.HintConfig{ .hints = &hints };
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    fn vtableRefresh(ptr: *anyopaque) anyerror!void {
        const self: *TrafficView = @ptrCast(@alignCast(ptr));
        self.force_refresh.store(true, .release);
    }
};
