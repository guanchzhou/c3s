# C3S - Claude Development Guide

This document provides context and guidelines for AI assistants (like Claude) working on the c3s project.

## Project Overview

**c3s** is a Kubernetes TUI (Terminal User Interface) client written in Zig, inspired by k9s and btop.

- **Language**: Zig 0.15.1
- **Target**: Terminal-based Kubernetes cluster management
- **Philosophy**: Fast, lightweight, beautiful UI with k9s compatibility

## Architecture

### MVVM Pattern

The project follows **Model-View-ViewModel** architecture:

```
src/
├── core/          # Core utilities (terminal, logger, xdg)
├── model/         # Data models (config, theme, version)
├── view/          # UI views (pods, themes, help)
├── viewmodel/     # View logic (commands, filters, view manager)
├── ui/            # UI components (header, footer, box drawing)
└── fixtures/      # Test data (k8s_data, pods_data)
```

### Key Components

1. **Terminal** (`core/terminal.zig`)
   - Custom terminal implementation (replaced vaxis due to instability)
   - Raw mode, ANSI escape codes, key input parsing
   - Handles Shift, Ctrl modifiers

2. **View System** (`viewmodel/`)
   - View trait with vtables for polymorphism
   - ViewManager with stack-based navigation
   - CommandRegistry for application-level commands

3. **Theme System** (`model/theme_loader.zig`)
   - Supports k9s skin files
   - Dynamic theme switching with real-time preview
   - Hex/named colors → ANSI conversion

4. **Header** (`ui/header.zig`)
   - Progressive compression (12 levels) for narrow terminals
   - Debug mode: dummy data vs. n/a values
   - Uses fixtures module for test data

## Development Workflow

### Building & Testing

```bash
# Build
zig build

# Clean build (required after patching Zig stdlib or updating deps)
zig build clean && zig build

# Run tests
zig build test

# Run with debug data
zig-out/bin/c3s --debug

# Run normally (n/a values)
zig-out/bin/c3s
```

### Code Style

- **Naming**: `snake_case` for functions, `PascalCase` for types
- **Error handling**: Always handle errors explicitly, use `try` or `catch`
- **Memory**: Use allocators properly, always `defer deinit()`
- **Comments**: GoDoc-style for public functions

### Zig Specifics (0.15.1)

Important API changes in Zig 0.15:
- `ArrayList.init()` → `ArrayList.initCapacity()` (returns error union)
- `ArrayList.deinit()` → `ArrayList.deinit(allocator)` (needs allocator)
- `ArrayList.append()` → `ArrayList.append(allocator, item)` (needs allocator)
- `std.fs.Dir.iterate()` method instead of `iterate` function
- `std.fs.File.Kind.file` instead of `.File`

## Project Conventions

### Testing

- Test files mirror source structure: `tests/ui/header_test.zig` → `src/ui/header.zig`
- Use `@import("c3s")` in tests for main exports
- All public functions should have tests
- Use fixtures for consistent test data

### Fixtures (`src/fixtures/`)

Centralized test data:
- `k8s_data.zig` - Kubernetes cluster info (default, minimal, production, high_load, etc.)
- `pods_data.zig` - Pod information (default_pods, mixed_status_pods, etc.)
- Use `fixtures.k8s_data.getData(debug)` to get appropriate data

### Configuration

- XDG Base Directory spec compliant
- Config: `~/.config/c3s/config.yml`
- Themes: `~/.config/c3s/skins/`
- State: `~/.local/state/c3s/`
- Logs: `~/.local/state/c3s/c3s.log`

## Key Features

### Progressive Header Compression

12 levels of compression for narrow terminals:
- Level 0: Full with version
- Level 1: Drop version
- Level 2: Drop k8s prefix
- Level 3: Compact CPU/MEM (2%::27%)
- Level 4: Short labels (ctx:, c:, u:)
- Level 5: Drop [RW]
- Level 6: Drop c3s
- Level 7: Values only
- Level 8: Drop k8s version
- Level 9: Truncate user
- Level 10: Truncate cluster
- Level 11: Minimum (context | 2%::27%)

### Theme System

- k9s-compatible skin files
- Real-time preview when navigating themes
- Dynamic theme updates (header, footer, views)
- Secure validation (prevents command injection)

### View Navigation

- Stack-based view management
- Primary views: pods, themes
- Sub-views: help (Shift+?)
- Esc: clear filter → pop sub-view
- Command palette: Shift+: or /

## Common Tasks

### Adding a New View

1. Create `src/view/my_view.zig`
2. Implement View trait (render, handleKey, onShow, onHide, getName, deinit)
3. Register in ViewManager
4. Add command to CommandRegistry
5. Create tests in `tests/view/my_view_test.zig`

### Adding Test Data

1. Create fixture in `src/fixtures/my_data.zig`
2. Export in `src/fixtures/index.zig`
3. Document in `src/fixtures/README.md`
4. Use in views/tests

### Adding a Command

1. Add to CommandRegistry in `src/app.zig`
2. Implement command function
3. Add key binding in handleKey
4. Update help view

## Security Considerations

- Theme files validated for command injection
- File size limits (100KB for themes)
- Color values sanitized
- No arbitrary code execution from config files

## Performance

- Target: 60 FPS (16.67ms frame time)
- Efficient rendering with dirty flags
- Minimal allocations in hot paths
- Use ArenaAllocator for temporary data

## Debugging

- `--debug` flag enables dummy data
- Logs to `~/.local/state/c3s/c3s.log`
- All errors (even crashes) logged via signal handlers
- Use `Logger.debug()`, `Logger.info()`, `Logger.err()`

## Future Integration

### Real Kubernetes Data

When implementing K8s client:
- Replace fixtures with real K8s API calls
- Keep `--debug` flag for testing without K8s
- Use same data structures as fixtures
- Implement in `src/k8s/` directory

### Planned Features

- Real pod listing and filtering
- Resource management (deployments, services, etc.)
- Log viewing
- Port forwarding
- Shell access
- YAML editing

## Common Patterns

### Memory Management

```zig
pub fn init(allocator: std.mem.Allocator) !MyStruct {
    const data = try allocator.alloc(u8, 100);
    errdefer allocator.free(data);
    
    return MyStruct{
        .allocator = allocator,
        .data = data,
    };
}

pub fn deinit(self: *MyStruct) void {
    self.allocator.free(self.data);
}
```

### View Implementation

```zig
pub const MyView = struct {
    allocator: std.mem.Allocator,
    theme: *const theme_loader.ThemeColors,
    
    pub fn init(allocator: std.mem.Allocator, theme: *const theme_loader.ThemeColors) !MyView {
        return MyView{
            .allocator = allocator,
            .theme = theme,
        };
    }
    
    pub fn createView(self: *MyView) View {
        return View.create(MyView, self, &vtable);
    }
    
    const vtable = View.VTable{
        .render = render,
        .handleKey = handleKey,
        // ... other functions
    };
};
```

## Tips for AI Assistants

1. **Always check Zig version** - We use 0.15.1 with specific API changes
2. **Use fixtures** - Don't hardcode test data
3. **Follow MVVM** - Keep concerns separated
4. **Test everything** - Every public function needs tests
5. **Handle memory** - Always pair alloc with free/deinit
6. **Update TODOs** - Track progress with todo_write
7. **Security first** - Validate all external input
8. **Document changes** - Update README/ARCHITECTURE when needed
9. **Progressive enhancement** - Build incrementally, test often
10. **Ask clarifying questions** - User prefers questions over assumptions

## References

- **Zig**: https://ziglang.org/documentation/0.15.1/
- **k9s**: https://k9scli.io/ (UI inspiration, key bindings)
- **btop**: https://github.com/aristocratos/btop (UI style)
- **XDG Base Directory**: https://specifications.freedesktop.org/basedir-spec/

## Build System

- `build.zig` - Main build configuration
- `build.zig.zon` - Dependencies
- Tests compiled with anonymous import to `src/index.zig`
- Version auto-generated from local time: `v0.YYYY.MM.DD.HH.MM`

---

**Note**: This project is under active development. When in doubt, check the latest code and tests for current patterns and best practices.
