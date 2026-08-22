# c3s — Lessons

## Debugging
- A fault at `0xaaaaaaaaaaaaab3a` is Zig's `undefined`/freed-memory fill (0xaa). If the printed frames are mutually impossible (render + init + deinit of unrelated subsystems on one stack), the **stack is smashed** — the symbols are garbage. Don't chase the named top frame.
- When the trace is unreliable and you can't reproduce in the agent shell: build a **Python PTY harness** (`pty.fork`, set `TIOCSWINSZ`, write keystrokes) to reproduce the exact user steps, then **instrument** (log markers at each teardown step) to find where it dies. Reproduce → instrument → fix → re-run the repro as the oracle.

## Memory-safety (Zig + json.Value)
- Never `@memcpy` structs that contain `std.json.Value`/slices out of a `Parsed` and then `deinit` the `Parsed` — the copies dangle into the freed arena (crashed in `array_hash_map.getIndexA`). Return the arena-owning wrapper (`ParsedList`) and keep it alive while iterating.
- View teardown must not invoke view lifecycle callbacks (`onShow`/`onHide`) — `App.deinit` had already freed the view objects; `ViewManager.deinit` calling `popView()` (which fires `onShow`) was a use-after-free. Free handle arrays only.

## TUI rendering
- Disable autowrap on the alt screen (`\x1b[?7l` / restore `\x1b[?7h`) or edge writes wrap into the box borders.
- Clear regions with the SAME bg you paint cells with (theme `main_bg`), not the terminal default — else cells show as mismatched blocks.
- Column layout: widths from `calculateColumnWidths` already include +2 padding and sum to the interior — advance `col_x += w` (not `w+1`) and clamp to the right edge.
- A field with both a numeric value and a derived display string: the updater must refresh BOTH (Header CPU/MEM was stuck because `updateCpuMem` only set the `u8`, not `cpu_str`).

## UX / perf
- Re-showing an already-loaded view must NOT block on a network refresh (instant Esc). Guard `onShow` to skip refresh when data exists.
- Every `kubectl` call is a fresh process (~1.3–2s TLS handshake); token reuse (`--token`) trims only the ~0.6s auth. Real speedup needs a persistent connection.
- Make a feature a **depth-1 view** (replace, not push-overlay) when you want `:`-commands to work in it and Esc to not pop it (e.g. the aliases view).

## Test discovery (Zig)
- `pub const x = @import(...)` decls in a test root do NOT pull co-located `test{}` blocks in —
  Zig analyzes decls lazily, so `zig build test` compiled an EMPTY runner ("success, 2ms, 2M RSS")
  while every src test silently never ran. Fix: `test { std.testing.refAllDecls(@This()); }` in
  index.zig. Detection oracle: canary-break one assertion; if the suite still passes, discovery is broken.
- A suspiciously fast/small test run IS the symptom. Verify test discovery whenever wiring changes.

## Process
- Persist the plan to `tasks/todo.md` (checkable) and the brain; work tier by tier; build + `zig build test` + `zig build fmt` green per tier.
- Hints/help must not advertise unimplemented actions — wire every key or remove the hint.

## Review
Session delivered: Zig 0.16 + zig-klient migration (shipped), then 2 crash fixes, UI/border/theme fixes, connect perf (token reuse + pods-first + onShow staleness), and the full k9s keybinding suite. Large batch left UNCOMMITTED on `main` per user choice.
