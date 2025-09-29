# C3S - Kubernetes Client TUI

A Kubernetes client TUI application written in Zig, inspired by k9s but with our own implementation. Features a three-part layout (header, body, footer) similar to the k9s interface.

## Project Structure

```
c3s/
├── build.zig              # Build configuration
├── build.zig.zon          # Package dependencies
├── src/
│   ├── main.zig           # Main application entry point
│   ├── app.zig            # Main application logic
│   ├── terminal.zig       # Custom terminal implementation
│   ├── header.zig         # Header component (system info, shortcuts)
│   ├── body.zig           # Body component (Kubernetes resources table)
│   ├── footer.zig         # Footer component (context info)
│   └── benchmark.zig      # Benchmarking utilities
├── tests/
│   └── integration.zig    # Integration tests
├── docs/                  # Documentation
├── .gitignore            # Git ignore rules
├── test_tui.sh           # Test script
└── README.md             # This file
```

## Features

### ✅ Implemented
- **Three-part TUI Layout**: Header, Body, Footer similar to k9s
- **Custom Terminal Implementation**: Built with Zig standard library
- **Header Component**: 
  - System information (context, cluster, user, versions)
  - Keyboard shortcuts display
  - macOS-style window controls
- **Body Component**:
  - Kubernetes pods table view
  - Navigation (j/k for up/down, h/l for left/right)
  - Row highlighting and selection
  - Column-based layout with proper spacing
- **Footer Component**:
  - Current resource type indicator
- **Input Handling**: Basic keyboard navigation and quit functionality

### 🚧 Planned
- **Kubernetes API Integration**: Real-time data from Kubernetes clusters
- **Resource Management**: CRUD operations on Kubernetes resources
- **Advanced Navigation**: Tab switching, filtering, searching
- **Logs and Shell Access**: Pod logs and shell access
- **Configuration**: Customizable key bindings and themes

## Prerequisites

- [Zig](https://ziglang.org/download/) 0.15.1 or later

## Getting Started

### Build the project

```bash
zig build
```

### Run the TUI application

```bash
zig build run
```

### Run tests

```bash
# Run all unit tests
zig build test

# Run specific component tests
zig build test-terminal
zig build test-header
zig build test-body
zig build test-footer
zig build test-app

# Run integration tests
zig build test-integration

# Run all tests (unit + integration)
zig build test-all
```

### Test the application

```bash
# Make the test script executable
chmod +x test_tui.sh

# Run the test script
./test_tui.sh
```

### Controls

- `q` - Quit the application
- `j` - Navigate down (next pod)
- `k` - Navigate up (previous pod)
- `h` - Navigate left (previous column)
- `l` - Navigate right (next column)
- `Esc` - Quit the application
- `Ctrl+C` - Quit the application

## Architecture

### Components

1. **App** (`app.zig`): Main application coordinator
2. **Terminal** (`terminal.zig`): Custom terminal abstraction layer
3. **Header** (`header.zig`): Top section with system info and shortcuts
4. **Body** (`body.zig`): Main content area with Kubernetes resources table
5. **Footer** (`footer.zig`): Bottom section with context information

### Design Principles

- **Modular Design**: Each component is self-contained
- **Clean Architecture**: Separation of concerns between UI and logic
- **Memory Safety**: Proper allocation and deallocation patterns
- **Error Handling**: Comprehensive error handling throughout

## Development

### Build Options

- **Debug**: `zig build` (default)
- **ReleaseFast**: `zig build -Doptimize=ReleaseFast`
- **ReleaseSafe**: `zig build -Doptimize=ReleaseSafe`
- **ReleaseSmall**: `zig build -Doptimize=ReleaseSmall`

### Adding New Features

1. **New Resources**: Add new resource types to `body.zig`
2. **New Commands**: Extend input handling in `app.zig`
3. **UI Components**: Create new components following the existing pattern
4. **Kubernetes Integration**: Add API client functionality

## Testing

The project includes comprehensive testing with unit tests, integration tests, and performance benchmarks:

### Test Coverage
- **Unit Tests**: Individual component testing (terminal, header, body, footer, app)
- **Integration Tests**: Component interaction and full application testing
- **Memory Testing**: Leak detection and allocation pattern verification
- **Performance Testing**: Rendering and input response benchmarks

### Test Documentation
- [Testing Guide](docs/TESTING.md) - Comprehensive testing documentation
- [Architecture Guide](docs/ARCHITECTURE.md) - System architecture and design

## Future Enhancements

- [ ] Real Kubernetes API integration
- [ ] Multiple resource types (services, deployments, etc.)
- [ ] Resource filtering and searching
- [ ] Pod logs viewer
- [ ] Shell access to pods
- [ ] Configuration management
- [ ] Theme support
- [ ] Plugin system

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## License

[Add your license here]
