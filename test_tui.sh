#!/bin/bash

# Test script for the C3S TUI application
echo "Building C3S TUI application..."

# Try to build the application
if /opt/homebrew/Cellar/zig/0.15.1/bin/zig build; then
    echo "Build successful!"
    echo "Running C3S TUI application..."
    echo "Press 'q' to quit, 'j'/'k' to navigate, 'h'/'l' for left/right"
    echo "Press any key to start..."
    read -n 1
    
    # Run the application
    ./zig-out/bin/c3s
else
    echo "Build failed!"
    exit 1
fi
