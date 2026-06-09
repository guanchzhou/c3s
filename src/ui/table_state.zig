const std = @import("std");
const Key = @import("../core/terminal.zig").Key;
const View = @import("../viewmodel/view.zig").View;
const KeyResult = View.KeyResult;
const Terminal = @import("../core/terminal.zig").Terminal;
const theme_loader = @import("../model/theme_loader.zig");
const Theme = theme_loader;
const universal_filter = @import("../viewmodel/filter.zig");
const sort_util = @import("../viewmodel/sort.zig");

/// Reusable table navigation, filtering, and sorting state.
/// Views compose this instead of reimplementing navigation/filter/sort.
pub fn TableState(comptime ItemType: type) type {
    return struct {
        const Self = @This();

        items: std.ArrayListUnmanaged(ItemType),
        filtered_indices: std.ArrayListUnmanaged(usize),
        selected_row: u32 = 0,
        scroll_offset: u32 = 0,
        visible_rows: u32 = 0,
        filter_text: []const u8 = "",
        sort_column: ?u8 = null,
        sort_ascending: bool = true,
        show_all_namespaces: bool = false,
        loading: bool = false,
        error_message: ?[]u8 = null,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return Self{
                .items = .empty,
                .filtered_indices = .empty,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            if (@hasDecl(ItemType, "deinit")) {
                for (self.items.items) |*item| {
                    item.deinit();
                }
            }
            self.items.deinit(self.allocator);
            self.filtered_indices.deinit(self.allocator);
            if (self.error_message) |msg| {
                self.allocator.free(msg);
            }
        }

        /// Clear all items (calling deinit on each) and reset error state
        pub fn clearItems(self: *Self) void {
            if (@hasDecl(ItemType, "deinit")) {
                for (self.items.items) |*item| {
                    item.deinit();
                }
            }
            self.items.clearRetainingCapacity();
            if (self.error_message) |msg| {
                self.allocator.free(msg);
                self.error_message = null;
            }
        }

        pub fn appendItem(self: *Self, item: ItemType) !void {
            try self.items.append(self.allocator, item);
        }

        pub fn setError(self: *Self, msg: []const u8) !void {
            if (self.error_message) |old| self.allocator.free(old);
            self.error_message = try self.allocator.dupe(u8, msg);
        }

        pub fn setErrorFmt(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            if (self.error_message) |old| self.allocator.free(old);
            self.error_message = try std.fmt.allocPrint(self.allocator, fmt, args);
        }

        /// Set a user-friendly error message for common connection/API errors.
        /// Maps raw Zig errors to actionable messages instead of showing internal error names.
        pub fn setConnectionError(self: *Self, comptime resource: []const u8, err: anyerror) !void {
            const friendly: ?[]const u8 = switch (err) {
                error.TlsInitializationFailed => "TLS connection failed. Try: C3S_FORCE_PROXY=1 c3s",
                error.ConnectionRefused => "Connection refused. Is the cluster reachable?",
                error.ConnectionResetByPeer => "Connection reset. Check cluster status.",
                error.UnexpectedReadFailure => "Connection lost. Check cluster connectivity.",
                else => null,
            };
            if (friendly) |msg| {
                try self.setError(msg);
            } else {
                try self.setErrorFmt("Failed to list " ++ resource ++ ": {}", .{err});
            }
        }

        // ====================================================================
        // Navigation
        // ====================================================================

        pub fn navigateDown(self: *Self) void {
            if (self.selected_row + 1 < self.filtered_indices.items.len) {
                self.selected_row += 1;
                if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                    self.scroll_offset += 1;
                }
            }
        }

        pub fn navigateUp(self: *Self) void {
            if (self.selected_row > 0) {
                self.selected_row -= 1;
                if (self.selected_row < self.scroll_offset) {
                    self.scroll_offset = self.selected_row;
                }
            }
        }

        pub fn gotoTop(self: *Self) void {
            self.selected_row = 0;
            self.scroll_offset = 0;
        }

        pub fn gotoBottom(self: *Self) void {
            if (self.filtered_indices.items.len > 0) {
                self.selected_row = @intCast(self.filtered_indices.items.len - 1);
                if (self.selected_row >= self.visible_rows) {
                    self.scroll_offset = self.selected_row - self.visible_rows + 1;
                }
            }
        }

        pub fn pageDown(self: *Self) void {
            const items_len: u32 = @intCast(self.filtered_indices.items.len);
            const jump = @min(self.visible_rows, items_len -| self.selected_row -| 1);
            self.selected_row += jump;
            if (self.selected_row >= self.scroll_offset + self.visible_rows) {
                self.scroll_offset = self.selected_row - self.visible_rows + 1;
            }
        }

        pub fn pageUp(self: *Self) void {
            const jump = @min(self.visible_rows, self.selected_row);
            self.selected_row -= jump;
            if (self.selected_row < self.scroll_offset) {
                self.scroll_offset = self.selected_row;
            }
        }

        // ====================================================================
        // Key handling — returns KeyResult if handled, null if not
        // ====================================================================

        pub fn handleNavigationKey(self: *Self, key: Key) ?KeyResult {
            switch (key) {
                .char => |c| switch (c) {
                    'j' => {
                        self.navigateDown();
                        return .handled;
                    },
                    'k' => {
                        self.navigateUp();
                        return .handled;
                    },
                    'g' => {
                        self.gotoTop();
                        return .handled;
                    },
                    'G' => {
                        self.gotoBottom();
                        return .handled;
                    },
                    'd' => return .request_describe,
                    'y' => return .request_yaml,
                    ':' => return .request_command_palette,
                    '/' => return .request_filter,
                    else => return null,
                },
                .down => {
                    self.navigateDown();
                    return .handled;
                },
                .up => {
                    self.navigateUp();
                    return .handled;
                },
                .page_down => {
                    self.pageDown();
                    return .handled;
                },
                .page_up => {
                    self.pageUp();
                    return .handled;
                },
                .home => {
                    self.gotoTop();
                    return .handled;
                },
                .end => {
                    self.gotoBottom();
                    return .handled;
                },
                else => return null,
            }
        }

        // ====================================================================
        // Filter & Sort
        // ====================================================================

        pub fn applyFilter(self: *Self, filter: []const u8, comptime matchFn: fn (*const ItemType, []const u8) bool) !void {
            self.filter_text = filter;
            try universal_filter.applyFilter(
                ItemType,
                self.allocator,
                self.items.items,
                &self.filtered_indices,
                filter,
                &self.selected_row,
                &self.scroll_offset,
                self.visible_rows,
                matchFn,
            );
        }

        pub fn toggleSort(self: *Self, col: u8) void {
            sort_util.toggleSort(&self.sort_column, &self.sort_ascending, col);
        }

        pub fn sortBy(self: *Self, comptime getter: fn (*const ItemType) []const u8) void {
            sort_util.sortFilteredIndices(ItemType, self.items.items, &self.filtered_indices, getter, self.sort_ascending);
        }

        // ====================================================================
        // Selection helpers
        // ====================================================================

        pub fn getSelectedItem(self: *const Self) ?*const ItemType {
            if (self.filtered_indices.items.len == 0) return null;
            if (self.selected_row >= self.filtered_indices.items.len) return null;
            const idx = self.filtered_indices.items[self.selected_row];
            return &self.items.items[idx];
        }

        pub fn getVisibleRange(self: *const Self) struct { start: u32, end: u32 } {
            const end = @min(
                self.scroll_offset + self.visible_rows,
                @as(u32, @intCast(self.filtered_indices.items.len)),
            );
            return .{ .start = self.scroll_offset, .end = end };
        }

        pub fn isSelected(self: *const Self, display_offset: usize) bool {
            return (self.scroll_offset + display_offset) == self.selected_row;
        }

        // ====================================================================
        // Rendering helpers
        // ====================================================================

        /// Render loading/error states. Returns true if a state was rendered (caller should return).
        pub fn renderStatus(self: *const Self, terminal_inst: *Terminal, x: u16, y: u16, colors: *const theme_loader.ThemeColors) !bool {
            if (self.loading) {
                try Theme.writeStringWithTheme(terminal_inst, x, y, "Loading...", colors.main_fg, colors.main_bg);
                return true;
            }
            if (self.error_message) |msg| {
                try Theme.writeStringWithTheme(terminal_inst, x, y, msg, colors.status_failed, colors.main_bg);
                return true;
            }
            return false;
        }

        /// Get fg/bg colors for a row based on selection state
        pub fn rowColors(self: *const Self, display_offset: usize, colors: *const theme_loader.ThemeColors) struct { fg: []const u8, bg: []const u8 } {
            if (self.isSelected(display_offset)) {
                return .{ .fg = colors.selected_fg, .bg = colors.selected_bg };
            }
            return .{ .fg = colors.main_fg, .bg = colors.main_bg };
        }
    };
}
