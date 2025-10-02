# IMMEDIATE UI FIX NEEDED

## Problem
The application runs but shows NO UI chrome:
- ❌ No header border
- ❌ No title  
- ❌ No footer
- ✅ Error message displays ("Not connected to Kubernetes cluster")

## Root Cause
Based on logs showing "View activated" then immediately "View deactivated", and the fact that only the view's error message renders, there's likely an issue with:

1. **Terminal rendering** - Header/footer not rendering
2. **View management** - View being popped immediately after push
3. **Terminal height check** - Conditional render failing

## Observed Behavior
- App launches and enters main loop
- Pods view pushed and immediately popped (from logs)
- Only raw error text shows - no borders/chrome
- Terminal is in alternate screen mode

## Investigation Steps
1. ✅ Found pods view IS pushed at line 353
2. ✅ Logs confirm view activated then deactivated  
3. ✅ Header render has height check: `if (size.height >= self.header_height)`
4. ⚠️  Need to verify terminal size is being read correctly

## Likely Issues
1. **Terminal size detection failing** - Returns 0 or invalid size
2. **View immediately popping** - Some error path pops view right after push
3. **Header height > terminal height** - Causes header skip

## Quick Fix Needed
Check App.init around line 353 - ensure view stays pushed and terminal size is valid before first render.

