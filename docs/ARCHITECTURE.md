# Architecture Documentation

## Overview

This document describes the architecture and design decisions for the C3S Kubernetes client TUI application. C3S is a terminal-based user interface for Kubernetes management, inspired by k9s but built from scratch in Zig.

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        C3S TUI App                         │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │   Header    │  │    Body     │  │       Footer        │  │
│  │ Component   │  │ Component   │  │    Component        │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                    Terminal Layer                          │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │              Custom Terminal Implementation             │ │
│  │              (ANSI escape codes, input handling)       │ │
│  └─────────────────────────────────────────────────────────┘ │
├─────────────────────────────────────────────────────────────┤
│                    Zig Standard Library                    │
└─────────────────────────────────────────────────────────────┘
```

### Component Architecture

#### 1. Application Layer (`app.zig`)
- **Responsibility**: Main application coordinator and event loop
- **Key Functions**:
  - Initialize and manage all components
  - Handle main event loop
  - Coordinate input handling
  - Manage application lifecycle
- **Dependencies**: All other components

#### 2. Terminal Layer (`terminal.zig`)
- **Responsibility**: Abstract terminal operations and input handling
- **Key Functions**:
  - Screen clearing and cursor control
  - Text rendering with colors
  - Input event processing
  - Terminal state management
- **Dependencies**: Zig standard library only

#### 3. UI Components

##### Header Component (`header.zig`)
- **Responsibility**: Display system information and keyboard shortcuts
- **Key Functions**:
  - Render Kubernetes context information
  - Display system metrics (CPU, memory)
  - Show keyboard shortcuts
  - macOS-style window controls
- **Data**: Static system information (configurable)

##### Body Component (`body.zig`)
- **Responsibility**: Main content area with Kubernetes resources table
- **Key Functions**:
  - Render resource tables (pods, services, etc.)
  - Handle navigation and selection
  - Manage scrolling and viewport
  - Display resource status and metrics
- **Data**: Kubernetes resource data (currently mock data)

##### Footer Component (`footer.zig`)
- **Responsibility**: Display context and status information
- **Key Functions**:
  - Show current resource type
  - Display status messages
  - Context indicators
- **Data**: Current application state

## Design Principles

### 1. Modularity
- Each component is self-contained with clear interfaces
- Components communicate through well-defined APIs
- Easy to add new components or modify existing ones

### 2. Separation of Concerns
- **UI Layer**: Pure presentation logic
- **Data Layer**: Resource management and state
- **Input Layer**: Event handling and user interaction
- **Terminal Layer**: Low-level terminal operations

### 3. Memory Safety
- Proper allocation and deallocation patterns
- No memory leaks or dangling pointers
- Use of Zig's memory management features

### 4. Error Handling
- Comprehensive error handling throughout
- Graceful degradation on errors
- Clear error messages and recovery

### 5. Performance
- Efficient rendering with minimal redraws
- Fast input response
- Optimized memory usage

## Data Flow

### 1. Initialization Flow
```
main() → App.init() → Component.init() → Terminal.init()
```

### 2. Event Loop Flow
```
Input Event → App.handleInput() → Component.update() → Terminal.render()
```

### 3. Rendering Flow
```
App.run() → Component.render() → Terminal.writeString() → Screen Update
```

## Component Interfaces

### Terminal Interface
```zig
pub const Terminal = struct {
    pub fn init(allocator: Allocator) !Terminal
    pub fn deinit(self: *Terminal) void
    pub fn clear(self: *Terminal) !void
    pub fn writeString(self: *Terminal, x: u16, y: u16, text: []const u8) !void
    pub fn writeStringWithColor(self: *Terminal, x: u16, y: u16, text: []const u8, fg: Color, bg: Color) !void
    pub fn readKey(self: *Terminal) !?Key
    // ... other methods
};
```

### Component Interface
```zig
pub const Component = struct {
    pub fn init(allocator: Allocator) !Component
    pub fn deinit(self: *Component) void
    pub fn render(self: *Component, terminal: *Terminal, x: u16, y: u16, width: u16, height: u16) !void
    // ... component-specific methods
};
```

## State Management

### Application State
- **Current View**: Which resource type is being displayed
- **Selected Item**: Currently highlighted row/item
- **Scroll Position**: Viewport position in large lists
- **Input Mode**: Current input context

### Component State
- **Header**: Static system information
- **Body**: Resource data, selection, scroll position
- **Footer**: Current context and status

## Error Handling Strategy

### 1. Terminal Errors
- Handle terminal initialization failures
- Graceful fallback for unsupported terminal features
- Proper cleanup on exit

### 2. Component Errors
- Validate input parameters
- Handle rendering failures
- Recover from data corruption

### 3. Application Errors
- Log errors appropriately
- Provide user feedback
- Maintain application stability

## Testing Strategy

### Unit Tests
- **Terminal Layer**: Test individual terminal operations
- **Components**: Test rendering and state management
- **Utilities**: Test helper functions and data structures

### Integration Tests
- **Component Interaction**: Test how components work together
- **Input Handling**: Test complete input-to-output flow
- **Rendering Pipeline**: Test full rendering cycle

### Performance Tests
- **Rendering Performance**: Measure frame rendering time
- **Memory Usage**: Monitor memory allocation patterns
- **Input Responsiveness**: Measure input-to-display latency

## Future Architecture Considerations

### 1. Plugin System
- Allow external components to be loaded
- Define plugin interfaces and APIs
- Support for custom resource types

### 2. Configuration Management
- User preferences and settings
- Key binding customization
- Theme and appearance options

### 3. Kubernetes Integration
- Real-time API client
- Resource caching and synchronization
- Event streaming and updates

### 4. Advanced UI Features
- Multiple tabs/views
- Split-screen layouts
- Modal dialogs and popups

## Build System

The project uses Zig's built-in build system with the following features:

- **Multiple Build Targets**: Support for different platforms and architectures
- **Optimization Levels**: Debug, ReleaseFast, ReleaseSafe, ReleaseSmall
- **Test Execution**: Automated unit and integration test running
- **Benchmarking Support**: Performance measurement tools
- **Dependency Management**: Package management with build.zig.zon

## Development Guidelines

### Code Organization
- One component per file
- Clear separation of public and private interfaces
- Consistent naming conventions
- Comprehensive documentation

### Testing Requirements
- All public functions must have tests
- Integration tests for component interactions
- Performance benchmarks for critical paths
- Error condition testing

### Documentation Standards
- Inline documentation for all public APIs
- Architecture decisions documented
- Usage examples for complex features
- Regular documentation updates
