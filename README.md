# C3S - Kubernetes Client TUI

A high-performance Kubernetes client TUI application written in Zig, inspired by k9s and btop. Features a modern MVVM architecture with clean separation of concerns and comprehensive theming support.

## 🚀 Features

### ✅ Core Features
- **MVVM Architecture**: Clean separation with View, ViewManager, and Command pattern
- **Custom Terminal Implementation**: Built with Zig standard library for maximum performance
- **Three-part TUI Layout**: Header, Body, Footer similar to k9s
- **Theme System**: Full k9s skin compatibility with live preview
- **Command System**: Centralized command processing with `:q`, `:themes`, `:help`
- **Navigation Stack**: Proper back/forward navigation with `Esc`
- **Filtering**: Real-time filtering with `/` command
- **Help System**: Comprehensive help with `?` or `:help`

### 🎨 UI Components
- **Header Component**: 
  - System information (context, cluster, user, K8s version)
  - CPU/Memory usage display
  - Keyboard shortcuts with color coding
  - Compact mode toggle (`Ctrl+E`)
- **Body Component**:
  - Kubernetes pods table view with proper theming
  - Navigation (hjkl, arrows, g/G, Home/End, PgUp/PgDn)
  - Row highlighting and selection
  - Real-time filtering and search
- **Footer Component**:
  - Current resource type indicator
  - Command input display
- **Theme Selector**:
  - 35+ k9s-compatible skins
  - Live theme preview
  - Alphabetical sorting
  - Current theme indicator

### ⌨️ Key Bindings
- **Navigation**: `hjkl`, arrow keys, `g`/`G`, `Home`/`End`, `PgUp`/`PgDn`
- **Commands**: `:` for command palette, `/` for filtering, `?` for help
- **Filtering**: `/` to filter, `x` or `Esc` to clear filter
- **Themes**: `:themes` or `:skins` to open theme selector
- **Quit**: `:q` or `:quit` to exit
- **Compact Header**: `Ctrl+E` to toggle compact mode

## 🏗️ Architecture

### MVVM Pattern
The application uses a clean MVVM (Model-View-ViewModel) architecture:

- **Views**: Self-contained UI components (`PodsView`, `ThemesView`, `HelpView`)
- **ViewManager**: Manages view stack and navigation
- **Commands**: Centralized command processing system
- **Models**: Data structures for pods, themes, etc.

### Project Structure
```
c3s/
├── build.zig              # Build configuration
├── build.zig.zon          # Package dependencies
├── src/
│   ├── main.zig           # Application entry point
│   ├── app.zig            # Main application coordinator
│   ├── terminal.zig       # Custom terminal implementation
│   ├── header.zig         # Header component
│   ├── footer.zig         # Footer component
│   ├── command_input.zig  # Command line input
│   ├── view.zig           # View trait definition
│   ├── view_manager.zig   # View navigation manager
│   ├── command.zig        # Command pattern implementation
│   ├── theme.zig          # Theme system
│   ├── theme_loader.zig   # k9s skin parser
│   ├── config.zig         # Configuration management
│   ├── logger.zig         # Logging system
│   ├── version.zig        # Version management
│   ├── xdg.zig           # XDG Base Directory support
│   └── views/             # View implementations
│       ├── pods_view.zig      # Pods display view
│       ├── themes_view.zig    # Theme selection view
│       └── help_view.zig      # Help display view
├── skins/                 # k9s-compatible theme files
├── tests/                 # Test suite
├── docs/                  # Documentation
└── README.md             # This file
```

## 🚀 Getting Started

### Prerequisites
- [Zig](https://ziglang.org/download/) 0.15.1 or later

### Build the project
```bash
zig build
```

### Run the application
```bash
./zig-out/bin/c3s
```

### Run tests
```bash
# Run all tests
zig build test

# Run specific tests
zig build test-terminal
zig build test-theme-loader
```

## 🎨 Theming

C3S supports k9s-compatible skin files with live preview:

### Available Themes
- 35+ themes included (tokyo-night, stock, transparent, etc.)
- Full k9s skin compatibility
- Live preview when navigating themes
- Automatic theme persistence

### Theme Locations
- **Bundled**: `skins/` directory
- **User**: `$XDG_CONFIG_HOME/c3s/skins/` directory

### Using Themes
1. Press `:themes` or `:skins` to open theme selector
2. Navigate with `j`/`k` or arrow keys
3. Press `Enter` to select a theme
4. Theme is automatically saved and applied

## 📖 Documentation

- [Architecture Guide](docs/ARCHITECTURE.md) - System architecture and design patterns
- [MVVM Guide](docs/MVVM_ARCHITECTURE.md) - MVVM implementation details
- [Theming Guide](docs/THEMES.md) - Theme system and skin development
- [Configuration Guide](docs/CONFIG.md) - Configuration options
- [Performance Guide](docs/PERFORMANCE.md) - Performance optimizations

## 🧪 Testing

The project includes comprehensive testing:

### Test Coverage
- **Unit Tests**: Individual component testing
- **Integration Tests**: Component interaction testing
- **Memory Testing**: Leak detection and allocation verification
- **Theme Testing**: Skin parsing and color conversion
- **Command Testing**: Command system functionality

### Running Tests
```bash
# All tests
zig build test

# Specific test suites
zig build test-terminal
zig build test-theme-loader
zig build test-views
```

## 🚧 Roadmap

### Phase 1: Core Features ✅
- [x] MVVM architecture implementation
- [x] Custom terminal implementation
- [x] Theme system with k9s compatibility
- [x] Command system
- [x] Navigation stack
- [x] Filtering and search

### Phase 2: Kubernetes Integration 🚧
- [ ] Real Kubernetes API integration
- [ ] Live pod data fetching
- [ ] Resource management (CRUD operations)
- [ ] Pod logs viewer
- [ ] Shell access to pods

### Phase 3: Advanced Features 📋
- [ ] Multiple resource types (services, deployments, etc.)
- [ ] Advanced filtering and sorting
- [ ] Configuration management
- [ ] Plugin system
- [ ] Performance optimizations

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite: `zig build test`
6. Submit a pull request

## 📄 License

[Add your license here]

## 🙏 Acknowledgments

- Inspired by [k9s](https://k9scli.io/) - Kubernetes CLI
- Inspired by [btop](https://github.com/aristocratos/btop) - System monitor
- Built with [Zig](https://ziglang.org/) - General-purpose programming language