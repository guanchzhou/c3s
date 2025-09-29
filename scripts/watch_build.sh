#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR"

BUILD_NUM=$(cat .build_number 2>/dev/null || echo 0)
BUILD_FLAG="-Dbuild=${BUILD_NUM}"

build_once() {
  echo "==> Building (version 0.0.1+${BUILD_NUM}) at $(date '+%T')"
  zig build ${BUILD_FLAG} || true
}

if command -v watchexec >/dev/null 2>&1; then
  watchexec -e zig -w src -w build.zig -w build.zig.zon -r -- sh -c "zig build ${BUILD_FLAG}"
elif command -v fswatch >/dev/null 2>&1; then
  fswatch -o src build.zig build.zig.zon | while read -r _; do zig build ${BUILD_FLAG}; done
elif command -v entr >/dev/null 2>&1; then
  fd -e zig src | entr -r zig build ${BUILD_FLAG}
else
  echo "No watcher found (watchexec/fswatch/entr). Polling every 2s..."
  build_once
  while sleep 2; do
    zig build ${BUILD_FLAG} || true
  done
fi


