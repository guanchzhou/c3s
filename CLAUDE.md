# c3s

Kubernetes TUI client in Zig 0.16.x, inspired by k9s + btop. Fast, lightweight, k9s-compatible skins.

Brain: `brain/Projects/c3s/`.

## Build & run

```bash
zig build
zig build clean && zig build       # after patching stdlib or updating deps
zig build test

zig-out/bin/c3s --debug            # dummy data
zig-out/bin/c3s                    # n/a values (no real k8s client yet)
```

## Architecture (MVVM)

```
src/
├── core/       # terminal, logger, xdg
├── model/      # config, theme, version
├── view/       # pods, themes, help
├── viewmodel/  # commands, filters, view manager
├── ui/         # header, footer, box drawing
└── fixtures/   # k8s_data, pods_data
```

Key components:
- **Terminal** (`core/terminal.zig`) — custom raw-mode terminal (replaced vaxis), ANSI escape codes, key input incl. Shift/Ctrl.
- **View system** — View trait + vtables, ViewManager (stack nav), CommandRegistry (Shift+: or `/`).
- **Theme loader** — k9s skin files, real-time preview, hex/named → ANSI, validated against command injection (100KB cap).
- **Header** — 12-level progressive compression for narrow terminals (full → values only → minimum `context | 2%::27%`).

## Zig 0.16 API gotchas (migrated from 0.15)

0.16 routes file/subprocess/socket I/O through `std.Io`. c3s owns one io and
publishes it via `core/runtime.zig` (`runtime.io()`, lazily initialized so unit
tests work without `main`); `main(init: std.process.Init)` calls `runtime.set(init.io)`.

- `std.ArrayList(T)` is now **unmanaged**; empty value is `.empty` (not `(T){}`);
  `append`/`deinit` take the allocator. `std.array_list.Managed(T)` is the old managed one.
- `std.fs.cwd()` removed → `std.Io.Dir.cwd()`; `openFile`/`openDir`/`createDirPath`
  (was `makePath`)/`createFile`/`writeFile`/`readFileAlloc`/`close` all take `runtime.io()`.
  `std.fs.selfExeDirPath` → `std.process.executableDirPath(io, buf)` (returns len).
- `std.posix` is trimmed (no `write`/`close`/`dup2`/`open`/`isatty`); use `core/sys.zig`
  (libc-backed) for raw fd ops on the render/log/crash paths (kept io-free).
- `std.time.{timestamp,milliTimestamp,nanoTimestamp}` removed → `core/clock.zig` (libc clock_gettime).
- `std.process.getEnvVarOwned` removed → `core/env.zig` (libc getenv). `std.io.getStd*` →
  `std.fs.File.std{out,in,err}()`. `std.mem.trimRight/Left` → `trimEnd/trimStart`.
- `std.process.Child.init/.run` removed → `std.process.spawn(io,…)` / `std.process.run(gpa,io,…)`;
  `Term.Exited` → `.exited`. Sigaction handler takes `posix.SIG`, not `c_int`.
- zig-klient v0.3.2: `K8sClient.init`/`connectWithFallback`/`KubeconfigParser.init`/
  `executeCredentialPlugin` take `io`; `ConnectionPool` removed; `ServiceSpec.type_` → `@"type"`;
  many spec fields (selector/template/ports) are now `std.json.Value`.

## Conventions

- `camelCase` functions, `PascalCase` types, `snake_case` fields/locals (Zig std / ghostty style). GoDoc-style comments on public fns. `zig fmt` enforced (`zig build fmt`).
- Allocators explicit; `defer deinit()` always. ArenaAllocator for temporary data.
- Tests mirror src tree (`tests/ui/header_test.zig` ↔ `src/ui/header.zig`); use `@import("c3s")`.
- Fixtures in `src/fixtures/`: `fixtures.k8s_data.getData(debug)` picks dummy vs n/a.
- Target 60 FPS. Dirty-flag rendering, minimal allocations in hot paths.

## Config (XDG)

- Config: `~/.config/c3s/config.yml`
- Themes: `~/.config/c3s/skins/`
- State + logs: `~/.local/state/c3s/` (`c3s.log`)

## Adding things

- **View**: create `src/view/x.zig` implementing View trait (render/handleKey/onShow/onHide/getName/deinit), register in ViewManager, add command + test.
- **Fixture**: `src/fixtures/x.zig`, export in `src/fixtures/index.zig`.
- **Command**: register in `src/app.zig` CommandRegistry, bind key, update help.

## Patterns

```zig
pub fn init(allocator: std.mem.Allocator) !MyStruct {
    const data = try allocator.alloc(u8, 100);
    errdefer allocator.free(data);
    return MyStruct{ .allocator = allocator, .data = data };
}

pub fn deinit(self: *MyStruct) void {
    self.allocator.free(self.data);
}
```

## Future

Real K8s client lands in `src/k8s/`; keep `--debug` for offline testing; reuse fixture data shapes. Planned: pod listing/filter, resources, logs, port-forward, shell, YAML edit.

## Build system

- `build.zig` + `build.zig.zon`. Tests use anonymous import to `src/index.zig`.
- Version auto-generated: `v0.YYYY.MM.DD.HH.MM`.

## References

- Zig 0.16.0 docs · k9scli.io · btop (aristocratos) · XDG Base Directory spec.
