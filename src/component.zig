const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;

// Base component interface for the TUI system
pub const ComponentBounds = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

pub const ComponentType = enum {
    header,
    body,
    footer,
    help_overlay,
};

pub const Component = struct {
    component_type: ComponentType,
    bounds: ComponentBounds,
    visible: bool = true,
    needs_redraw: bool = true,
    z_index: u8 = 0, // For layering (help overlay should be higher)

    pub fn init(component_type: ComponentType, bounds: ComponentBounds) Component {
        const z_index: u8 = switch (component_type) {
            .header => 1,
            .body => 1,
            .footer => 1,
            .help_overlay => 10, // Help overlay should be on top
        };

        return Component{
            .component_type = component_type,
            .bounds = bounds,
            .z_index = z_index,
        };
    }

    pub fn setBounds(self: *Component, bounds: ComponentBounds) void {
        if (self.bounds.x != bounds.x or 
            self.bounds.y != bounds.y or 
            self.bounds.width != bounds.width or 
            self.bounds.height != bounds.height) {
            self.bounds = bounds;
            self.needs_redraw = true;
        }
    }

    pub fn setVisible(self: *Component, visible: bool) void {
        if (self.visible != visible) {
            self.visible = visible;
            self.needs_redraw = true;
        }
    }

    pub fn markDirty(self: *Component) void {
        self.needs_redraw = true;
    }

    pub fn isInBounds(self: *Component, x: u16, y: u16) bool {
        return x >= self.bounds.x and 
               x < self.bounds.x + self.bounds.width and
               y >= self.bounds.y and 
               y < self.bounds.y + self.bounds.height;
    }
};

// Component manager to handle rendering order and overlays
pub const ComponentManager = struct {
    allocator: std.mem.Allocator,
    components: std.ArrayList(Component),
    dirty_regions: std.ArrayList(ComponentBounds),

    pub fn init(allocator: std.mem.Allocator) ComponentManager {
        return ComponentManager{
            .allocator = allocator,
            .components = std.ArrayList(Component).init(allocator),
            .dirty_regions = std.ArrayList(ComponentBounds).init(allocator),
        };
    }

    pub fn deinit(self: *ComponentManager) void {
        self.components.deinit();
        self.dirty_regions.deinit();
    }

    pub fn addComponent(self: *ComponentManager, component: Component) !void {
        try self.components.append(component);
        // Sort by z_index to maintain rendering order
        std.sort.insertion(Component, self.components.items, {}, componentLessThan);
    }

    pub fn getComponent(self: *ComponentManager, component_type: ComponentType) ?*Component {
        for (self.components.items) |*component| {
            if (component.component_type == component_type) {
                return component;
            }
        }
        return null;
    }

    pub fn markRegionDirty(self: *ComponentManager, bounds: ComponentBounds) !void {
        try self.dirty_regions.append(bounds);
    }

    pub fn needsRedraw(self: *ComponentManager) bool {
        for (self.components.items) |component| {
            if (component.visible and component.needs_redraw) {
                return true;
            }
        }
        return self.dirty_regions.items.len > 0;
    }

    pub fn clearDirty(self: *ComponentManager) void {
        for (self.components.items) |*component| {
            component.needs_redraw = false;
        }
        self.dirty_regions.clearRetainingCapacity();
    }

    fn componentLessThan(context: void, a: Component, b: Component) bool {
        _ = context;
        return a.z_index < b.z_index;
    }
};
