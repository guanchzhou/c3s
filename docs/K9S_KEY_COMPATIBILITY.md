# K9s Key Binding Compatibility

This document tracks c3s compatibility with k9s key bindings. Our goal is 100% key binding compatibility.

## Core Navigation (✅ Implemented)

| Key | Action | Status |
|-----|--------|--------|
| `j` / `↓` | Navigate down | ✅ |
| `k` / `↑` | Navigate up | ✅ |
| `h` / `←` | Navigate left | ✅ |
| `l` / `→` | Navigate right | ✅ |
| `g` | Go to top | ✅ |
| `G` (Shift+g) | Go to bottom | ✅ |
| `Ctrl+f` / `PgDn` | Page down | ✅ |
| `Ctrl+b` / `PgUp` | Page up | ✅ |
| `Home` | Go to top | ✅ |
| `End` | Go to bottom | ✅ |

## Command & Filter (✅ Implemented)

| Key | Action | Status |
|-----|--------|--------|
| `:` | Open command mode | ✅ |
| `/` | Open filter mode | ✅ |
| `:q` / `:quit` | Exit application | ✅ |
| `Esc` | Close modal/command (never exits) | ✅ |
| `Enter` | Execute command/filter | ✅ |
| `x` / `Delete` | Clear filter | ✅ (x implemented) |

## View Controls (⚠️ Partial)

| Key | Action | Status |
|-----|--------|--------|
| `?` | Toggle help | ✅ |
| `Ctrl+e` | Toggle header compact mode | ✅ |
| `Ctrl+u` | Clear filter | ⏳ TODO |

## Quick Views (⚠️ Partial)

| Key | Action | Status |
|-----|--------|--------|
| `0` | All namespaces | ⏳ TODO (display only) |
| `1` | Default namespace | ⏳ TODO (display only) |
| `2-9` | Custom views | ⏳ TODO |

## Pod Actions (❌ Not Implemented)

| Key | Action | Status |
|-----|--------|--------|
| `a` | Attach to container | ❌ |
| `s` | Shell into container | ❌ |
| `d` | Describe resource | ❌ |
| `e` | Edit resource | ❌ |
| `l` | View logs | ❌ |
| `Shift+l` | View previous logs | ❌ |
| `y` | View YAML | ❌ |
| `t` | Transfer files | ❌ |
| `z` | Sanitize (restart) | ❌ |
| `i` | Set image | ❌ |
| `o` | Show node | ❌ |
| `Shift+f` | Port forward | ❌ |
| `f` | Show port forwards | ❌ |

## Destructive Actions (❌ Not Implemented)

| Key | Action | Status |
|-----|--------|--------|
| `Ctrl+k` | Kill pod | ❌ |
| `Ctrl+d` | Delete resource | ❌ |
| `Ctrl+f` | Kill finalizers | ❌ (conflicts with page down) |

## Sorting (❌ Not Implemented)

| Key | Action | Status |
|-----|--------|--------|
| `Shift+r` | Sort by ready | ❌ |
| `Shift+s` | Sort by status | ❌ |
| `Shift+t` | Sort by restarts | ❌ |
| `Shift+i` | Sort by IP | ❌ |
| `Shift+o` | Sort by node | ❌ |
| `Shift+n` | Sort by name | ❌ |

## Selection & Marking (❌ Not Implemented)

| Key | Action | Status |
|-----|--------|--------|
| `Space` | Mark/unmark item | ❌ |
| `Ctrl+Space` | Clear marks | ❌ |
| `m` | Mark item | ❌ |

## Clipboard (❌ Not Implemented)

| Key | Action | Status |
|-----|--------|--------|
| `c` | Copy resource name | ❌ |
| `Ctrl+c` | Copy (in certain contexts) | ❌ |
| `n` | Copy namespace | ❌ |

## Special Keys (✅ Disabled)

| Key | Action | Status |
|-----|--------|--------|
| `Ctrl+c` | Does NOT exit | ✅ |
| `Esc` | Does NOT exit (only closes modals) | ✅ |

## Configuration Files

k9s loads key bindings from:
- `$XDG_CONFIG_HOME/k9s/hotkeys.yaml` - Global hotkeys
- `$XDG_DATA_HOME/k9s/clusters/{cluster}/{context}/hotkeys.yaml` - Context-specific

c3s should support the same:
- `$XDG_CONFIG_HOME/c3s/hotkeys.yaml`
- `$XDG_DATA_HOME/c3s/clusters/{cluster}/{context}/hotkeys.yaml`

## Hotkeys Format (k9s)

```yaml
hotKeys:
  shift-0:
    shortCut: Shift-0
    description: View Workloads
    command: wk k8s-app=cilium
    override: false
    keepHistory: false
```

## Implementation Plan

1. Create `hotkeys.zig` module to parse YAML hotkeys
2. Create `key_actions.zig` for action mapping
3. Implement all k9s standard key bindings
4. Support custom hotkeys from config files
5. Add override and keepHistory support
6. Implement context-specific hotkeys

## References

- k9s key definitions: `internal/ui/key.go`
- k9s pod bindings: `internal/view/pod.go`
- k9s hotkeys: `internal/config/hotkey.go`
- k9s app bindings: `internal/ui/app.go`
