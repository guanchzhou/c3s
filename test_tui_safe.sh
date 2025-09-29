#!/bin/bash

echo "Testing C3S TUI safely..."
echo "Press Ctrl+C to exit, or wait 3 seconds for auto-exit"

# Start the app in background
./zig-out/bin/c3s &
APP_PID=$!

# Wait 3 seconds
sleep 3

# Check if app is still running
if kill -0 $APP_PID 2>/dev/null; then
    echo "App is running, sending Ctrl+C..."
    kill -INT $APP_PID
    wait $APP_PID
    echo "App exited cleanly"
else
    echo "App already exited"
fi
