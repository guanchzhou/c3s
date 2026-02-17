/// PodDisruptionBudgetsView
const std = @import("std");
const klient = @import("klient");
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Key = @import("../core/terminal.zig").Key;
const Terminal = @import("../core/terminal.zig").Terminal;
const Theme = @import("../theme.zig");
const theme_loader = @import("../model/theme_loader.zig");
const hints_model = @import("../model/hints.zig");
const k8s_service_mod = @import("../services/k8s_service.zig");
const K8sService = k8s_service_mod.K8sService;
const ResourceInfo = k8s_service_mod.ResourceInfo;
const Logger = @import("../core/logger.zig");
const universal_filter = @import("../viewmodel/filter.zig");
const sort_util = @import("../viewmodel/sort.zig");

pub const PodDisruptionBudgetsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,
    items: std.ArrayListUnmanaged(PDBInfo),
    filtered_indices: std.ArrayListUnmanaged(usize),
    selected_row: u32,
    scroll_offset: u32,
    visible_rows: u32,
    loading: bool,
    error_message: ?[]const u8,
    filter_text: []const u8,
    show_all_namespaces: bool,
    sort_column: ?u8 = null,
    sort_ascending: bool = true,

    // Sort column indices
    const COL_NAME: u8 = 0;
    const COL_AGE: u8 = 1;

    const PDBInfo = struct {
        namespace: []const u8,
        name: []const u8,
        min_available: []const u8,
        age: []const u8,
        pub fn deinit(self: *PDBInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.namespace);
            allocator.free(self.name);
            allocator.free(self.min_available);
            allocator.free(self.age);
        }
        fn getName(self: *const PDBInfo) []const u8 { return self.name; }
        fn getAge(self: *const PDBInfo) []const u8 { return self.age; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !PodDisruptionBudgetsView {
        return PodDisruptionBudgetsView{ .allocator = allocator, .theme = theme, .k8s_service = k8s_service, .items = .{}, .filtered_indices = .{}, .selected_row = 0, .scroll_offset = 0, .visible_rows = 0, .loading = false, .error_message = null, .filter_text = "", .show_all_namespaces = true, };
    }

    pub fn deinit(self: *PodDisruptionBudgetsView) void {
        for (self.items.items) |*item| item.deinit(self.allocator);
        self.items.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        if (self.error_message) |msg| self.allocator.free(msg);
    }

    pub fn refresh(self: *PodDisruptionBudgetsView) !void {
        self.loading = true;
        if (self.error_message) |msg| { self.allocator.free(msg); self.error_message = null; }
        for (self.items.items) |*item| item.deinit(self.allocator);
        self.items.clearRetainingCapacity();
        if (!self.k8s_service.isConnected()) { self.error_message = try self.allocator.dupe(u8, "Not connected"); return; }
        const pdbs = if (self.show_all_namespaces)
            self.k8s_service.listAllPodDisruptionBudgets() catch |err| { self.error_message = try std.fmt.allocPrint(self.allocator, "Failed: {}", .{err}); return; }
        else
            self.k8s_service.listPodDisruptionBudgets(null) catch |err| { self.error_message = try std.fmt.allocPrint(self.allocator, "Failed: {}", .{err}); return; };
        defer self.allocator.free(pdbs);
        for (pdbs) |pdb| {
            try self.items.append(self.allocator, PDBInfo{
                .namespace = try self.allocator.dupe(u8, pdb.metadata.namespace orelse "default"),
                .name = try self.allocator.dupe(u8, pdb.metadata.name),
                .min_available = try self.allocator.dupe(u8, "1"),
                .age = try self.allocator.dupe(u8, "1d"),
            });
        }
        self.loading = false;
        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *PodDisruptionBudgetsView) ?ResourceInfo {
        if (self.items.items.len == 0) return null;
        const idx = if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len)
            self.filtered_indices.items[self.selected_row]
        else if (self.selected_row < self.items.items.len)
            self.selected_row
        else
            return null;
        const item = self.items.items[idx];
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *PodDisruptionBudgetsView, filter: []const u8) !void {
        self.filter_text = filter;
        try universal_filter.applyFilter(
            PDBInfo,
            self.allocator,
            self.items.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            pdbMatchFn,
        );
        self.applySorting();
    }

    fn applySorting(self: *PodDisruptionBudgetsView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(PDBInfo, self.items.items, &self.filtered_indices, PDBInfo.getName, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(PDBInfo, self.items.items, &self.filtered_indices, PDBInfo.getAge, self.sort_ascending),
                else => {},
            }
        }
    }

    fn pdbMatchFn(item: *const PDBInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *PodDisruptionBudgetsView) View { return View.create(PodDisruptionBudgetsView, self, &vtable); }
    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *PodDisruptionBudgetsView = @ptrCast(@alignCast(ptr)); _ = width;
        self.visible_rows = if (height > 1) height - 1 else 0;
        if (self.loading) { try Theme.writeStringWithTheme(term, x, y, "Loading...", self.theme.main_fg, self.theme.main_bg); return; }
        if (self.error_message) |msg| { try Theme.writeStringWithTheme(term, x, y, msg, self.theme.status_failed, self.theme.main_bg); return; }
        if (self.filtered_indices.items.len == 0) {
            const msg = if (self.show_all_namespaces) "No PDBs found" else "No PDBs in namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg); return;
        }
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        const name_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_AGE);
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             {s: <22}MIN-AVAILABLE  {s}", .{ name_hdr, age_hdr }) catch "  NAMESPACE             NAME                  MIN-AVAILABLE  AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);
        const visible = self.visible_rows; var row: u32 = 0; var fi: u32 = self.scroll_offset;
        while (row < visible and fi < self.filtered_indices.items.len) : ({ row += 1; fi += 1; }) {
            const idx = self.filtered_indices.items[fi];
            const item = &self.items.items[idx]; const is_selected = (fi == self.selected_row);
            const line = try std.fmt.allocPrint(self.allocator, "  {s: <20} {s: <20} {s: <14} {s}", .{
                if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                if (item.name.len > 20) item.name[0..20] else item.name,
                if (item.min_available.len > 14) item.min_available[0..14] else item.min_available, item.age,
            });
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, y + 1 + @as(u16, @intCast(row)), line, if (is_selected) self.theme.selected_fg else self.theme.main_fg, if (is_selected) self.theme.selected_bg else self.theme.main_bg);
        }
    }
    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *PodDisruptionBudgetsView = @ptrCast(@alignCast(ptr));
        switch (key) {
            .down => { if (self.selected_row < self.filtered_indices.items.len -| 1) self.selected_row += 1; return .handled; },
            .up => { if (self.selected_row > 0) self.selected_row -= 1; return .handled; },
            .char => |c| switch (c) {
                'j' => { if (self.selected_row < self.filtered_indices.items.len -| 1) self.selected_row += 1; return .handled; },
                'k' => { if (self.selected_row > 0) self.selected_row -= 1; return .handled; },
                'r' => { try self.refresh(); return .handled; },
                'N' => { sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_NAME); self.applySorting(); return .handled; },
                'A' => { sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_AGE); self.applySorting(); return .handled; },
                'd' => return .request_describe,
                'y' => return .request_yaml,
                '/' => return .request_filter,
                '0' => { self.show_all_namespaces = !self.show_all_namespaces; try self.refresh(); return .handled; },
                else => {},
            },
            else => {},
        }
        return .not_handled;
    }
    fn onShow(ptr: *anyopaque) void { const self: *PodDisruptionBudgetsView = @ptrCast(@alignCast(ptr)); self.refresh() catch |err| { Logger.err("Failed: {}", .{err}); }; }
    fn onHide(ptr: *anyopaque) void { _ = ptr; }
    fn getName(ptr: *anyopaque) []const u8 { _ = ptr; return "poddisruptionbudgets"; }
    fn getHints(ptr: *anyopaque) hints_model.HintConfig { _ = ptr; return hints_model.resourceHints(); }
    fn deinitView(ptr: *anyopaque) void { const self: *PodDisruptionBudgetsView = @ptrCast(@alignCast(ptr)); self.deinit(); }
    const vtable = View.VTable{ .render = render, .handleKey = handleKey, .onShow = onShow, .onHide = onHide, .getName = getName, .getHints = getHints, .deinit = deinitView, };
};
