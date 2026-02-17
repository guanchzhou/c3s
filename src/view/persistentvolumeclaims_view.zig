/// PersistentVolumeClaimsView - View for Kubernetes PersistentVolumeClaims
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
const universal_filter = @import("../viewmodel/filter.zig");
const sort_util = @import("../viewmodel/sort.zig");
const Logger = @import("../core/logger.zig");

pub const PersistentVolumeClaimsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    k8s_service: *K8sService,

    items: std.ArrayListUnmanaged(PVCInfo),
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
    const COL_STATUS: u8 = 2;

    const PVCInfo = struct {
        name: []const u8,
        namespace: []const u8,
        status: []const u8,
        volume: []const u8,
        capacity: []const u8,
        access_modes: []const u8,
        age: []const u8,

        pub fn deinit(self: *PVCInfo, allocator: std.mem.Allocator) void {
            allocator.free(self.name);
            allocator.free(self.namespace);
            allocator.free(self.status);
            allocator.free(self.volume);
            allocator.free(self.capacity);
            allocator.free(self.access_modes);
            allocator.free(self.age);
        }

        fn getName(self: *const PVCInfo) []const u8 { return self.name; }
        fn getAge(self: *const PVCInfo) []const u8 { return self.age; }
        fn getStatus(self: *const PVCInfo) []const u8 { return self.status; }
    };

    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors, k8s_service: *K8sService) !PersistentVolumeClaimsView {
        return PersistentVolumeClaimsView{
            .allocator = allocator,
            .theme = theme,
            .k8s_service = k8s_service,
            .items = .{},
            .filtered_indices = std.ArrayListUnmanaged(usize){},
            .selected_row = 0,
            .scroll_offset = 0,
            .visible_rows = 0,
            .loading = false,
            .error_message = null,
            .filter_text = "",
            .show_all_namespaces = true,
        };
    }

    pub fn deinit(self: *PersistentVolumeClaimsView) void {
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.deinit(self.allocator);
        self.filtered_indices.deinit(self.allocator);
        if (self.error_message) |msg| {
            self.allocator.free(msg);
        }
    }

    pub fn refresh(self: *PersistentVolumeClaimsView) !void {
        self.loading = true;
        if (self.error_message) |msg| {
            self.allocator.free(msg);
            self.error_message = null;
        }
        for (self.items.items) |*item| {
            item.deinit(self.allocator);
        }
        self.items.clearRetainingCapacity();

        if (!self.k8s_service.isConnected()) {
            self.error_message = try self.allocator.dupe(u8, "Not connected to Kubernetes cluster");
            return;
        }

        const pvcs = if (self.show_all_namespaces)
            self.k8s_service.listAllPersistentVolumeClaims() catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list PVCs: {}", .{err});
                return;
            }
        else
            self.k8s_service.listPersistentVolumeClaims(null) catch |err| {
                self.error_message = try std.fmt.allocPrint(self.allocator, "Failed to list PVCs: {}", .{err});
                return;
            };
        defer self.allocator.free(pvcs);

        for (pvcs) |pvc| {
            const name = try self.allocator.dupe(u8, pvc.metadata.name);
            const namespace = try self.allocator.dupe(u8, pvc.metadata.namespace orelse "default");
            const status = try self.allocator.dupe(u8, "Bound");
            const volume = try self.allocator.dupe(u8, "pv-001");
            const capacity = try self.allocator.dupe(u8, "10Gi");
            const access_modes = try self.allocator.dupe(u8, "RWO");
            const age = try self.allocator.dupe(u8, "1d");

            try self.items.append(self.allocator, PVCInfo{
                .name = name,
                .namespace = namespace,
                .status = status,
                .volume = volume,
                .capacity = capacity,
                .access_modes = access_modes,
                .age = age,
            });
        }

        self.loading = false;
        try self.applyFilter(self.filter_text);
    }

    pub fn getSelectedResourceInfo(self: *PersistentVolumeClaimsView) ?ResourceInfo {
        if (self.filtered_indices.items.len == 0) return null;
        if (self.selected_row >= self.filtered_indices.items.len) return null;
        const idx = self.filtered_indices.items[self.selected_row];
        const item = self.items.items[idx];
        return ResourceInfo{
            .name = item.name,
            .namespace = item.namespace,
        };
    }

    pub fn applyFilter(self: *PersistentVolumeClaimsView, filter: []const u8) !void {
        self.filter_text = filter;
        try universal_filter.applyFilter(
            PVCInfo,
            self.allocator,
            self.items.items,
            &self.filtered_indices,
            filter,
            &self.selected_row,
            &self.scroll_offset,
            self.visible_rows,
            pvcMatchFn,
        );
        self.applySorting();
    }

    fn applySorting(self: *PersistentVolumeClaimsView) void {
        if (self.sort_column) |col| {
            switch (col) {
                COL_NAME => sort_util.sortFilteredIndices(PVCInfo, self.items.items, &self.filtered_indices, PVCInfo.getName, self.sort_ascending),
                COL_AGE => sort_util.sortFilteredIndices(PVCInfo, self.items.items, &self.filtered_indices, PVCInfo.getAge, self.sort_ascending),
                COL_STATUS => sort_util.sortFilteredIndices(PVCInfo, self.items.items, &self.filtered_indices, PVCInfo.getStatus, self.sort_ascending),
                else => {},
            }
        }
    }

    fn pvcMatchFn(item: *const PVCInfo, filter: []const u8) bool {
        return std.mem.indexOf(u8, item.name, filter) != null or
            std.mem.indexOf(u8, item.namespace, filter) != null;
    }

    pub fn createView(self: *PersistentVolumeClaimsView) View {
        return View.create(PersistentVolumeClaimsView, self, &vtable);
    }

    fn render(ptr: *anyopaque, term: *Terminal, x: u16, y: u16, width: u16, height: u16) !void {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        _ = width;
        self.visible_rows = if (height > 1) height - 1 else 0;

        if (self.loading) {
            try Theme.writeStringWithTheme(term, x, y, "Loading persistent volume claims...", self.theme.main_fg, self.theme.main_bg);
            return;
        }
        if (self.error_message) |msg| {
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.status_failed, self.theme.main_bg);
            return;
        }
        if (self.filtered_indices.items.len == 0) {
            const msg = if (self.show_all_namespaces) "No PVCs found in cluster" else "No PVCs in current namespace";
            try Theme.writeStringWithTheme(term, x, y, msg, self.theme.main_fg, self.theme.main_bg);
            return;
        }

        const name_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_NAME);
        const age_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_AGE);
        const status_ind = sort_util.sortIndicator(self.sort_column, self.sort_ascending, COL_STATUS);
        var name_hdr_buf: [32]u8 = undefined;
        var age_hdr_buf: [16]u8 = undefined;
        var status_hdr_buf: [16]u8 = undefined;
        const name_hdr = std.fmt.bufPrint(&name_hdr_buf, "NAME{s}", .{name_ind}) catch "NAME";
        const age_hdr = std.fmt.bufPrint(&age_hdr_buf, "AGE{s}", .{age_ind}) catch "AGE";
        const status_hdr = std.fmt.bufPrint(&status_hdr_buf, "STATUS{s}", .{status_ind}) catch "STATUS";
        var hdr_buf: [128]u8 = undefined;
        const header = std.fmt.bufPrint(&hdr_buf, "  NAMESPACE             {s: <22}{s: <9}VOLUME   CAPACITY   ACCESS   {s}", .{ name_hdr, status_hdr, age_hdr }) catch "  NAMESPACE             NAME                  STATUS   VOLUME   CAPACITY   ACCESS   AGE";
        try Theme.writeStringWithTheme(term, x, y, header, self.theme.title, self.theme.main_bg);

        const start_idx = self.scroll_offset;
        const end_idx = @min(start_idx + self.visible_rows, self.filtered_indices.items.len);
        var row: u16 = 0;

        for (start_idx..end_idx) |fi| {
            const item_idx = self.filtered_indices.items[fi];
            const item = &self.items.items[item_idx];
            const is_selected = (fi == self.selected_row);
            const fg_color = if (is_selected) self.theme.selected_fg else self.theme.main_fg;
            const bg_color = if (is_selected) self.theme.selected_bg else self.theme.main_bg;

            const line = try std.fmt.allocPrint(
                self.allocator,
                "  {s: <20} {s: <20} {s: <8} {s: <8} {s: <10} {s: <8} {s}",
                .{
                    if (item.namespace.len > 20) item.namespace[0..20] else item.namespace,
                    if (item.name.len > 20) item.name[0..20] else item.name,
                    item.status,
                    item.volume,
                    item.capacity,
                    item.access_modes,
                    item.age,
                },
            );
            defer self.allocator.free(line);
            try Theme.writeStringWithTheme(term, x, y + 1 + row, line, fg_color, bg_color);
            row += 1;
        }
    }

    fn handleKey(ptr: *anyopaque, key: Key) !KeyResult {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        switch (key) {
            .down => {
                if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len - 1) {
                    self.selected_row += 1;
                    if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                        self.scroll_offset = self.selected_row - self.visible_rows + 1;
                    }
                }
                return .handled;
            },
            .up => {
                if (self.selected_row > 0) {
                    self.selected_row -= 1;
                    if (self.selected_row < self.scroll_offset) self.scroll_offset = self.selected_row;
                }
                return .handled;
            },
            .char => |c| switch (c) {
                'j' => {
                    if (self.filtered_indices.items.len > 0 and self.selected_row < self.filtered_indices.items.len - 1) {
                        self.selected_row += 1;
                        if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                            self.scroll_offset = self.selected_row - self.visible_rows + 1;
                        }
                    }
                    return .handled;
                },
                'k' => {
                    if (self.selected_row > 0) {
                        self.selected_row -= 1;
                        if (self.selected_row < self.scroll_offset) self.scroll_offset = self.selected_row;
                    }
                    return .handled;
                },
                'g' => {
                    self.selected_row = 0;
                    self.scroll_offset = 0;
                    return .handled;
                },
                'G' => {
                    if (self.filtered_indices.items.len > 0) {
                        self.selected_row = @intCast(self.filtered_indices.items.len - 1);
                        if (self.selected_row >= self.visible_rows) {
                            self.scroll_offset = self.selected_row - self.visible_rows + 1;
                        }
                    }
                    return .handled;
                },
                'N' => {
                    sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_NAME);
                    self.applySorting();
                    return .handled;
                },
                'A' => {
                    sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_AGE);
                    self.applySorting();
                    return .handled;
                },
                'S' => {
                    sort_util.toggleSort(&self.sort_column, &self.sort_ascending, COL_STATUS);
                    self.applySorting();
                    return .handled;
                },
                'd' => return .request_describe,
                'y' => return .request_yaml,
                '/' => return .request_filter,
                'r' => {
                    try self.refresh();
                    return .handled;
                },
                '0' => {
                    self.show_all_namespaces = !self.show_all_namespaces;
                    try self.refresh();
                    return .handled;
                },
                else => return .not_handled,
            },
            else => return .not_handled,
        }
    }

    fn onShow(ptr: *anyopaque) void {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        self.refresh() catch |err| {
            Logger.err("Failed to refresh PVCs: {}", .{err});
        };
    }

    fn onHide(ptr: *anyopaque) void {
        _ = ptr;
    }

    fn getName(ptr: *anyopaque) []const u8 {
        _ = ptr;
        return "persistentvolumeclaims";
    }

    fn getHints(ptr: *anyopaque) hints_model.HintConfig {
        _ = ptr;
        return hints_model.resourceHints();
    }

    fn deinitView(ptr: *anyopaque) void {
        const self: *PersistentVolumeClaimsView = @ptrCast(@alignCast(ptr));
        self.deinit();
    }

    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        .onShow = onShow,
        .onHide = onHide,
        .getName = getName,
        .getHints = getHints,
        .deinit = deinitView,
    };
};
