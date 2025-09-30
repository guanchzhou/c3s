# Architecture Documentation

## Overview

This document describes the architecture and design decisions for the C3S Kubernetes client TUI application. C3S is a high-performance terminal-based user interface for Kubernetes management, built with a clean MVVM architecture in Zig.

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
│                    MVVM Layer                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ ViewManager │  │  Command    │  │      Views          │  │
│  │             │  │  Registry   │  │  (Pods, Themes,     │  │
│  │             │  │             │  │   Help)             │  │
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

## MVVM Architecture

C3S implements a clean Model-View-ViewModel (MVVM) pattern for better separation of concerns and maintainability.

### 1. Model Layer
- **Data Structures**: Pod, Theme, Config, etc.
- **Business Logic**: Data processing and validation
- **External APIs**: Kubernetes client integration (planned)

### 2. View Layer
- **View Interface**: Polymorphic view trait
- **View Implementations**: PodsView, ThemesView, HelpView
- **Rendering**: UI presentation and layout

### 3. ViewModel Layer
- **ViewManager**: View navigation and lifecycle
- **Command System**: Centralized command processing
- **State Management**: Application state coordination

## Component Architecture

### 1. Application Layer (`app.zig`)
- **Responsibility**: Main application coordinator and event loop
- **Key Functions**:
  - Initialize MVVM components
  - Handle main event loop
  - Coordinate input handling
  - Manage application lifecycle
- **Dependencies**: ViewManager, CommandRegistry, Views

### 2. MVVM Layer

#### ViewManager (`view_manager.zig`)
- **Responsibility**: Manage view stack and navigation
- **Key Functions**:
  - Push/pop views from stack
  - Handle view lifecycle (onShow/onHide)
  - Manage view state transitions
- **Features**:
  - LIFO view stack
  - Automatic cleanup
  - View activation tracking

#### Command System (`command.zig`)
- **Responsibility**: Centralized command processing
- **Key Functions**:
  - Register and execute commands
  - Handle command context
  - Manage command lifecycle
- **Features**:
  - Command registry
  - Context passing
  - Error handling

#### View Trait (`view.zig`)
- **Responsibility**: Define view interface
- **Key Functions**:
  - Render view content
  - Handle key events
  - Manage view lifecycle
- **Features**:
  - Polymorphic interface
  - Key result handling
  - Lifecycle management

### 3. View Implementations

#### PodsView (`views/pods_view.zig`)
- **Responsibility**: Display Kubernetes pods
- **Key Functions**:
  - Render pod table
  - Handle navigation and selection
  - Manage filtering and scrolling
- **Features**:
  - Real-time filtering
  - Row selection
  - Theme integration

#### ThemesView (`views/themes_view.zig`)
- **Responsibility**: Theme selection interface
- **Key Functions**:
  - Display available themes
  - Handle theme selection
  - Live theme preview
- **Features**:
  - Theme discovery
  - Live preview
  - Alphabetical sorting

#### HelpView (`views/help_view.zig`)
- **Responsibility**: Help and documentation
- **Key Functions**:
  - Display help content
  - Handle navigation
  - Show key bindings
- **Features**:
  - Scrollable content
  - Command reference
  - Key binding guide

### 4. Terminal Layer (`terminal.zig`)
- **Responsibility**: Abstract terminal operations
- **Key Functions**:
  - Screen clearing and cursor control
  - Text rendering with colors
  - Input event processing
  - Terminal state management
- **Dependencies**: Zig standard library only

### 5. UI Components

#### Header Component (`header.zig`)
- **Responsibility**: Display system information
- **Key Functions**:
  - Render Kubernetes context
  - Display system metrics
  - Show keyboard shortcuts
  - Compact mode toggle
- **Features**:
  - Dynamic content
  - Theme integration
  - Responsive layout

#### Footer Component (`footer.zig`)
- **Responsibility**: Display context information
- **Key Functions**:
  - Show current resource type
  - Display status messages
  - Context indicators
- **Features**:
  - Status display
  - Theme integration
  - Dynamic content

## Design Principles

### 1. MVVM Pattern
- **Separation of Concerns**: Clear boundaries between layers
- **Testability**: Each layer can be tested independently
- **Maintainability**: Easy to modify and extend
- **Reusability**: Views and commands can be reused

### 2. Polymorphism
- **View Interface**: All views implement the same interface
- **Command Interface**: All commands follow the same pattern
- **Type Safety**: Compile-time type checking
- **Flexibility**: Easy to add new views or commands

### 3. Memory Safety
- **Proper Allocation**: Use of Zig's memory management
- **Cleanup**: Automatic resource cleanup
- **No Leaks**: Comprehensive deallocation
- **Error Handling**: Graceful error recovery

### 4. Performance
- **Efficient Rendering**: Minimal redraws
- **Fast Input**: Responsive key handling
- **Memory Efficient**: Optimized allocations
- **Caching**: Smart data caching

## Data Flow

### 1. Initialization Flow
```
main() → App.init() → ViewManager.init() → CommandRegistry.init() → Views.init()
```

### 2. User Input Flow
```
User Input → App.handleKey() → ViewManager.getCurrentView() → View.handleKey() → KeyResult
```

### 3. Command Execution Flow
```
Command Input → CommandRegistry.execute() → Command.execute() → ViewManager operations
```

### 4. View Navigation Flow
```
View Action → ViewManager.pushView() → View.onShow() → Rendering
```

### 5. Rendering Flow
```
App.renderIfNeeded() → ViewManager.getCurrentView() → View.render() → Terminal output
```

## State Management

### Application State
- **Current View**: Active view in the stack
- **View Stack**: Navigation history
- **Command State**: Command palette visibility
- **Filter State**: Current filter text
- **Theme State**: Current theme and preview

### View State
- **PodsView**: Selected row, scroll position, filter text
- **ThemesView**: Selected theme, scroll position, preview
- **HelpView**: Scroll position, content state

### Command State
- **Command Registry**: Available commands
- **Command Context**: Execution context
- **Command History**: Command execution history

## Error Handling Strategy

### 1. View Errors
- **Rendering Errors**: Handle terminal output failures
- **Key Handling Errors**: Graceful key processing
- **State Errors**: Recover from invalid state

### 2. Command Errors
- **Execution Errors**: Handle command failures
- **Context Errors**: Validate command context
- **Registry Errors**: Handle command registration

### 3. ViewManager Errors
- **Navigation Errors**: Handle view stack issues
- **Lifecycle Errors**: Manage view lifecycle
- **Memory Errors**: Handle allocation failures

## Testing Strategy

### Unit Tests
- **View Tests**: Test individual view functionality
- **Command Tests**: Test command execution
- **ViewManager Tests**: Test navigation and lifecycle
- **Terminal Tests**: Test terminal operations

### Integration Tests
- **MVVM Integration**: Test view-command interaction
- **Navigation Tests**: Test view transitions
- **Command Tests**: Test command execution flow
- **Rendering Tests**: Test full rendering pipeline

### Performance Tests
- **Rendering Performance**: Measure view rendering time
- **Memory Usage**: Monitor allocation patterns
- **Input Responsiveness**: Measure key handling latency
- **Navigation Performance**: Test view switching speed

## Theme System

### Theme Architecture
- **Theme Loader**: Parse k9s skin files
- **Theme Colors**: Color scheme management
- **Theme Application**: Dynamic theme switching
- **Theme Preview**: Live theme preview

### Theme Features
- **k9s Compatibility**: Full k9s skin support
- **Live Preview**: Real-time theme changes
- **Theme Persistence**: Save selected themes
- **Color Mapping**: ANSI color conversion

## Configuration System

### Configuration Architecture
- **Config Loading**: XDG Base Directory support
- **Theme Configuration**: Theme selection persistence
- **UI Configuration**: UI state persistence
- **Command Configuration**: Command customization

### Configuration Features
- **XDG Compliance**: Standard configuration paths
- **JSON Format**: Human-readable configuration
- **Default Values**: Sensible defaults
- **Validation**: Configuration validation

## Future Architecture Considerations

### 1. Plugin System
- **View Plugins**: Custom view implementations
- **Command Plugins**: Custom command extensions
- **Theme Plugins**: Custom theme support
- **API Plugins**: External service integration

### 2. Advanced Navigation
- **Breadcrumb Navigation**: Navigation history
- **View Search**: Find views by name
- **Navigation Shortcuts**: Quick view switching
- **View Bookmarks**: Save view states

### 3. Kubernetes Integration
- **Real-time API**: Live Kubernetes data
- **Resource Management**: CRUD operations
- **Event Streaming**: Real-time updates
- **Multi-cluster**: Multiple cluster support

### 4. Performance Optimizations
- **View Caching**: Cache rendered views
- **Lazy Loading**: Load views on demand
- **Memory Pooling**: Reuse allocations
- **Async Operations**: Non-blocking operations

## Build System

The project uses Zig's built-in build system with the following features:

- **Multiple Build Targets**: Support for different platforms
- **Optimization Levels**: Debug, ReleaseFast, ReleaseSafe, ReleaseSmall
- **Test Execution**: Automated unit and integration tests
- **Benchmarking Support**: Performance measurement tools
- **Dependency Management**: Package management with build.zig.zon

## Development Guidelines

### Code Organization
- **MVVM Structure**: Clear separation of concerns
- **View Files**: One view per file in `views/` directory
- **Command Files**: Commands in `command.zig`
- **Consistent Naming**: Clear and descriptive names

### Testing Requirements
- **View Tests**: All views must have tests
- **Command Tests**: All commands must have tests
- **Integration Tests**: MVVM integration testing
- **Performance Tests**: Critical path benchmarking

### Documentation Standards
- **API Documentation**: All public APIs documented
- **Architecture Documentation**: System design documented
- **Usage Examples**: Code examples for complex features
- **Regular Updates**: Keep documentation current

## Conclusion

The MVVM architecture in C3S provides a solid foundation for a maintainable, testable, and extensible TUI application. The clear separation of concerns, polymorphic design, and comprehensive error handling make it easy to add new features and maintain the codebase as it grows.