# MVVM Architecture Guide

This document describes the Model-View-ViewModel (MVVM) architecture implementation in C3S.

## Overview

C3S uses a clean MVVM pattern to separate concerns and provide a maintainable, testable codebase. The architecture consists of three main layers:

- **Model**: Data structures and business logic
- **View**: UI components and rendering
- **ViewModel**: Mediates between Model and View, handles user interactions

## Architecture Components

### 1. View Trait (`src/view.zig`)

The `View` trait defines the interface that all UI components must implement:

```zig
pub const View = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        render: *const fn (ptr: *anyopaque, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void,
        handleKey: *const fn (ptr: *anyopaque, key: Key) !KeyResult,
        onShow: *const fn (ptr: *anyopaque) void,
        onHide: *const fn (ptr: *anyopaque) void,
        getName: *const fn (ptr: *anyopaque) []const u8,
        deinit: *const fn (ptr: *anyopaque) void,
    };
};
```

#### Key Features
- **Polymorphism**: Uses `anyopaque` and vtables for type-safe polymorphism
- **Lifecycle Management**: `onShow`/`onHide` for view activation/deactivation
- **Key Handling**: Centralized key event processing
- **Rendering**: Standardized rendering interface

#### KeyResult Enum
```zig
pub const KeyResult = enum {
    handled,                    // Key was handled by the view
    not_handled,               // Key was not handled
    request_command_palette,   // Request command palette
    request_filter,            // Request filter input
    request_quit,              // Request application quit
};
```

### 2. ViewManager (`src/view_manager.zig`)

Manages a stack of views and handles navigation:

```zig
pub const ViewManager = struct {
    allocator: std.mem.Allocator,
    view_ptrs: std.ArrayList(usize),
    view_vtables: std.ArrayList(usize),
};
```

#### Key Features
- **View Stack**: LIFO stack for view navigation
- **Lifecycle Management**: Automatically calls `onShow`/`onHide`
- **Memory Management**: Proper cleanup of all views
- **Navigation**: Push/pop views with proper state management

#### Methods
- `pushView(view: View)`: Push a new view onto the stack
- `popView() ?View`: Pop the current view and return to previous
- `getCurrentView() ?View`: Get the current view without removing it
- `getDepth() usize`: Get the current stack depth
- `isViewActive(view_name: []const u8) bool`: Check if a specific view is active

### 3. Command System (`src/command.zig`)

Implements the Command pattern for application actions:

```zig
pub const Command = struct {
    name: []const u8,
    execute: *const fn (ctx: *CommandContext) !void,
};

pub const CommandRegistry = struct {
    allocator: std.mem.Allocator,
    commands: std.StringHashMap(Command),
};
```

#### Key Features
- **Centralized Commands**: All application actions go through the command system
- **Command Context**: Passes necessary data to command execution
- **Registration**: Commands are registered at startup
- **Execution**: Commands are executed by name

#### Command Context
```zig
pub const CommandContext = struct {
    allocator: std.mem.Allocator,
    view_manager: *ViewManager,
    data: ?*anyopaque, // Pointer to the App struct
};
```

## View Implementations

### 1. PodsView (`src/views/pods_view.zig`)

Main view for displaying Kubernetes pods:

```zig
pub const PodsView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    pods: std.ArrayList(Pod),
    filtered_indices: std.ArrayList(usize),
    selected_row: usize,
    scroll_offset: usize,
    visible_rows: u16,
    filter_text: []const u8,
    allocated_title: ?[]u8,
};
```

#### Features
- **Pod Data Management**: Stores and manages pod information
- **Filtering**: Real-time filtering with `applyFilter()`
- **Navigation**: Row selection and scrolling
- **Theming**: Dynamic theme color application

### 2. ThemesView (`src/views/themes_view.zig`)

Theme selection interface:

```zig
pub const ThemesView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    themes: std.ArrayList(ThemeInfo),
    selected_row: usize,
    scroll_offset: usize,
    current_theme_name: []const u8,
    preview_theme: ?*theme_loader.ThemeColors,
};
```

#### Features
- **Theme Discovery**: Scans for available themes
- **Live Preview**: Real-time theme preview when navigating
- **Theme Selection**: Select and apply themes
- **Alphabetical Sorting**: Themes are sorted alphabetically

### 3. HelpView (`src/views/help_view.zig`)

Help and documentation display:

```zig
pub const HelpView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    help_lines: std.ArrayList([]u8),
    selected_row: usize,
    scroll_offset: usize,
    visible_rows: u16,
};
```

#### Features
- **Help Content**: Displays command and key binding help
- **Navigation**: Scrollable help content
- **Theming**: Consistent with application theme

## Data Flow

### 1. User Input Flow
```
User Input → App.handleKey() → ViewManager.getCurrentView() → View.handleKey() → KeyResult
```

### 2. Command Execution Flow
```
Command Input → CommandRegistry.execute() → Command.execute() → ViewManager operations
```

### 3. View Navigation Flow
```
View Action → ViewManager.pushView() → View.onShow() → Rendering
```

### 4. Rendering Flow
```
App.renderIfNeeded() → ViewManager.getCurrentView() → View.render() → Terminal output
```

## Memory Management

### View Lifecycle
1. **Creation**: Views are created in `App.init()`
2. **Activation**: `ViewManager.pushView()` calls `onShow()`
3. **Deactivation**: `ViewManager.popView()` calls `onHide()`
4. **Cleanup**: `View.deinit()` is called when view is removed

### Memory Safety
- All views implement proper `deinit()` methods
- `ViewManager` cleans up all views on destruction
- String allocations are properly managed with `allocator.dupe()` and `allocator.free()`

## Error Handling

### View Errors
- Views return `!void` from `render()` for terminal errors
- Views return `!KeyResult` from `handleKey()` for key processing errors
- Errors are propagated up to the application level

### Command Errors
- Commands return `!void` for execution errors
- Command registry returns `bool` for command existence
- Errors are logged and handled gracefully

## Testing

### View Testing
- Each view can be tested independently
- Mock terminal can be used for rendering tests
- Key handling can be tested with mock keys

### Integration Testing
- ViewManager can be tested with multiple views
- Command system can be tested with mock commands
- Full application flow can be tested end-to-end

## Benefits of MVVM in C3S

### 1. Separation of Concerns
- UI logic is separated from business logic
- Views are focused on presentation
- Commands handle application actions

### 2. Testability
- Views can be tested independently
- Commands can be unit tested
- Mock objects can be easily created

### 3. Maintainability
- Clear boundaries between components
- Easy to add new views or commands
- Consistent patterns across the codebase

### 4. Extensibility
- New views can be added without changing existing code
- New commands can be registered dynamically
- Theme system works consistently across all views

## Future Enhancements

### 1. View State Management
- Add view state persistence
- Implement view-specific configuration
- Add view transition animations

### 2. Command System Enhancements
- Add command aliases
- Implement command history
- Add command completion

### 3. Advanced Navigation
- Add breadcrumb navigation
- Implement view search
- Add navigation shortcuts

## Conclusion

The MVVM architecture in C3S provides a clean, maintainable, and extensible foundation for the TUI application. The separation of concerns makes it easy to add new features, test components, and maintain the codebase as it grows.
