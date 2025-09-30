# Table Column Fitting & Horizontal Scrolling Design

## Overview
Implement k9s-style adaptive table rendering with progressive column fitting and horizontal scrolling for narrow terminals.

## K9s Behavior Analysis

### Column Width Calculation
1. **ComputeMaxColumns()** - Calculate max width for each column
   - Iterate all rows to find widest content per column
   - Add padding (1 char) to each column
   - Sort column gets +2 chars for sort indicator

### Progressive Column Hiding
1. **shouldExcludeColumn()** - Hide columns based on:
   - `h.Hide` flag - explicitly hidden columns
   - `!t.wide && h.Wide` - wide columns hidden in normal mode
   - NAMESPACE column hidden if not cluster-wide
   - Metrics columns (MX) hidden if no metrics available

### Column Rendering Priority
1. **High Priority** (always show if possible):
   - NAME column (primary identifier)
   - STATUS/READY columns (critical state)
   
2. **Medium Priority**:
   - NAMESPACE (if cluster-wide)
   - AGE column
   
3. **Low Priority** (hide first):
   - RESTARTS, IP, NODE (can be hidden on narrow screens)
   - Wide columns (marked with 'W' attribute)

### Horizontal Scrolling
k9s uses `tview.Table` which has built-in horizontal scrolling:
- Uses `cell.SetExpansion(1)` for flexible width
- Table automatically scrolls horizontally when content exceeds width
- Arrow keys (Left/Right) navigate horizontally

## C3S Implementation Plan

### Phase 1: Column Width Calculation
```zig
pub const ColumnInfo = struct {
    name: []const u8,
    width: u16,
    min_width: u16,  // Minimum viable width
    priority: u8,    // 0=highest, 255=lowest
    truncatable: bool,
};

pub fn calculateColumnWidths(
    allocator: Allocator,
    headers: []const []const u8,
    rows: []const []const []const u8,
    available_width: u16,
) ![]u16 {
    // 1. Calculate max width for each column from all rows
    var max_widths = try allocator.alloc(u16, headers.len);
    
    // Initialize with header widths
    for (headers, 0..) |header, i| {
        max_widths[i] = @intCast(header.len + 2); // +2 for padding
    }
    
    // Find max width from data
    for (rows) |row| {
        for (row, 0..) |cell, i| {
            const width = @intCast(cell.len + 2);
            if (width > max_widths[i]) {
                max_widths[i] = width;
            }
        }
    }
    
    return max_widths;
}
```

### Phase 2: Progressive Column Fitting
```zig
pub const FitStrategy = struct {
    pub fn fitColumns(
        max_widths: []u16,
        priorities: []u8,
        available_width: u16,
    ) []bool {
        // Returns array of bools indicating which columns to show
        var visible = allocator.alloc(bool, max_widths.len);
        @memset(visible, true);
        
        var total_width: u16 = 0;
        for (max_widths) |w| total_width += w;
        
        if (total_width <= available_width) {
            return visible; // All columns fit
        }
        
        // Hide columns by priority (lowest first)
        var sorted_indices = sortByPriority(priorities);
        for (sorted_indices) |idx| {
            if (total_width <= available_width) break;
            
            visible[idx] = false;
            total_width -= max_widths[idx];
        }
        
        return visible;
    }
};
```

### Phase 3: Column Truncation Strategy
```zig
pub fn distributeWidth(
    max_widths: []u16,
    visible: []bool,
    available_width: u16,
) []u16 {
    var final_widths = allocator.alloc(u16, max_widths.len);
    
    // Count visible columns
    var visible_count: u16 = 0;
    var total_max: u16 = 0;
    for (visible, max_widths) |vis, max| {
        if (vis) {
            visible_count += 1;
            total_max += max;
        }
    }
    
    if (total_max <= available_width) {
        // All columns fit at max width
        for (max_widths, visible, 0..) |max, vis, i| {
            final_widths[i] = if (vis) max else 0;
        }
    } else {
        // Proportionally reduce widths
        const scale = @as(f32, @floatFromInt(available_width)) / 
                     @as(f32, @floatFromInt(total_max));
        
        for (max_widths, visible, 0..) |max, vis, i| {
            if (vis) {
                final_widths[i] = @intFromFloat(
                    @as(f32, @floatFromInt(max)) * scale
                );
            } else {
                final_widths[i] = 0;
            }
        }
    }
    
    return final_widths;
}
```

### Phase 4: Horizontal Scroll Implementation
```zig
pub const TableScroll = struct {
    scroll_offset: u16 = 0,
    visible_width: u16,
    total_width: u16,
    
    pub fn canScrollLeft(self: *const TableScroll) bool {
        return self.scroll_offset > 0;
    }
    
    pub fn canScrollRight(self: *const TableScroll) bool {
        return self.scroll_offset + self.visible_width < self.total_width;
    }
    
    pub fn scrollLeft(self: *TableScroll, amount: u16) void {
        if (self.scroll_offset >= amount) {
            self.scroll_offset -= amount;
        } else {
            self.scroll_offset = 0;
        }
    }
    
    pub fn scrollRight(self: *TableScroll, amount: u16) void {
        const max_offset = if (self.total_width > self.visible_width)
            self.total_width - self.visible_width
        else
            0;
        
        self.scroll_offset = @min(
            self.scroll_offset + amount,
            max_offset
        );
    }
    
    pub fn getVisibleRange(self: *const TableScroll) struct { start: u16, end: u16 } {
        return .{
            .start = self.scroll_offset,
            .end = self.scroll_offset + self.visible_width,
        };
    }
};
```

### Phase 5: Table Rendering with Scroll
```zig
pub fn renderTable(
    self: *PodsView,
    terminal: *Terminal,
    x: u16,
    y: u16,
    width: u16,
    height: u16,
) !void {
    // Calculate column widths
    const max_widths = try calculateColumnWidths(...);
    const visible_cols = fitColumns(max_widths, priorities, width - 2);
    const final_widths = distributeWidth(max_widths, visible_cols, width - 2);
    
    // Render headers with scroll offset
    const scroll_range = self.scroll.getVisibleRange();
    var col_x: u16 = x + 1;
    var accumulated_width: u16 = 0;
    
    for (headers, final_widths, visible_cols, 0..) |header, w, vis, i| {
        if (!vis) continue;
        
        // Check if column is in visible scroll range
        if (accumulated_width + w < scroll_range.start) {
            accumulated_width += w;
            continue;
        }
        if (accumulated_width > scroll_range.end) break;
        
        // Render column (possibly partial if at scroll edge)
        const visible_start = if (accumulated_width < scroll_range.start)
            scroll_range.start - accumulated_width
        else
            0;
        
        const visible_width = @min(
            w - visible_start,
            scroll_range.end - (accumulated_width + visible_start)
        );
        
        try renderColumnHeader(
            terminal,
            col_x,
            y,
            header[visible_start..],
            visible_width
        );
        
        col_x += visible_width;
        accumulated_width += w;
    }
}
```

## Column Priority Configuration

```zig
pub const ColumnPriority = struct {
    pub const HIGH: u8 = 0;
    pub const MEDIUM: u8 = 50;
    pub const LOW: u8 = 100;
    pub const VERY_LOW: u8 = 200;
    
    pub fn getPodColumnPriorities() []u8 {
        return &[_]u8{
            HIGH,       // NAME (always show)
            MEDIUM,     // READY
            MEDIUM,     // STATUS
            LOW,        // RESTARTS
            VERY_LOW,   // AGE
            VERY_LOW,   // IP
            VERY_LOW,   // NODE
        };
    }
};
```

## Progressive Hiding Order (Pods Example)

1. **Width >= 120**: All columns visible
   - NAME | NAMESPACE | READY | STATUS | RESTARTS | AGE | IP | NODE

2. **Width >= 100**: Hide NODE
   - NAME | NAMESPACE | READY | STATUS | RESTARTS | AGE | IP

3. **Width >= 80**: Hide IP
   - NAME | NAMESPACE | READY | STATUS | RESTARTS | AGE

4. **Width >= 60**: Hide RESTARTS
   - NAME | NAMESPACE | READY | STATUS | AGE

5. **Width >= 40**: Hide AGE
   - NAME | NAMESPACE | READY | STATUS

6. **Width < 40**: Enable horizontal scrolling
   - Show NAME + one status column, allow scrolling

## Key Bindings

- `Left Arrow` / `h`: Scroll table left
- `Right Arrow` / `l`: Scroll table right
- `0` / `Home`: Jump to leftmost column
- `$` / `End`: Jump to rightmost column
- `Shift-H`: Toggle wide mode (show all columns, enable scroll)

## Benefits

✅ Adaptive to terminal width
✅ Progressive degradation (hide least important first)
✅ Horizontal scrolling when needed
✅ Maintains NAME column visibility (primary key)
✅ Smooth UX matching k9s behavior
✅ Proportional width distribution
