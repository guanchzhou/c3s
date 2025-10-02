# URGENT: UI Not Rendering

## Problem
The app runs but shows NO UI:
- ❌ No header border/title
- ❌ No footer
- ✅ View error message shows
- ✅ Alternate screen mode works (dark background)

## For User: Please Run This

```bash
cd /Users/andreymaltsev/Development/alphasense/c3s
zig build
./zig-out/bin/c3s 2>&1 | tee run.log
```

Then in another terminal while it's running:
```bash
cat ~/.local/state/c3s/c3s.log | tail -50
```

Send me both outputs!

## What I Need
1. The full terminal output (run.log)
2. The full log file content
3. Screenshot of what you see
4. Your terminal size: `echo $COLUMNS x $LINES`

## Likely Causes
1. Terminal size detection failing (returns 0 or invalid)
2. Header height > terminal height (causes skip)
3. View rendering before UI chrome
4. Render order issue

## Next Steps
Once I see your logs, I can fix the exact issue!

