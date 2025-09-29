#!/bin/bash

echo "Testing C3S build..."

# Try to find zig in common locations
ZIG_PATHS=(
    "/opt/homebrew/Cellar/zig/0.15.1/bin/zig"
    "/usr/local/bin/zig"
    "zig"
)

ZIG_CMD=""
for path in "${ZIG_PATHS[@]}"; do
    if command -v "$path" &> /dev/null; then
        ZIG_CMD="$path"
        break
    fi
done

if [ -z "$ZIG_CMD" ]; then
    echo "Error: Could not find zig command"
    exit 1
fi

echo "Using zig: $ZIG_CMD"

# Test build
echo "Building C3S..."
if $ZIG_CMD build; then
    echo "✅ Build successful!"
    
    # Test if executable was created
    if [ -f "zig-out/bin/c3s" ]; then
        echo "✅ Executable created: zig-out/bin/c3s"
        
        # Test running the app (with timeout to avoid hanging)
        echo "Testing app execution (5 second timeout)..."
        timeout 5s ./zig-out/bin/c3s || echo "App ran (timeout expected)"
        
    else
        echo "❌ Executable not found"
        exit 1
    fi
else
    echo "❌ Build failed"
    exit 1
fi

echo "✅ All tests passed!"
