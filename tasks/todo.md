# Pods column parity with k9s

User: "where are rest of columns?" — pods view shows only NAME READY STATUS MEM IP NODE AGE.
Two defects: (1) CPU column silently dropped by a layout bug; (2) RESTARTS / %CPU/R / %MEM/R missing entirely.

Target k9s default pods columns: NAMESPACE NAME READY STATUS RESTARTS CPU MEM %CPU/R %MEM/R IP NODE AGE.

## Tasks
- [x] Fix layout budget bug: NAMESPACE column counted in visibility budget even when hidden in single-ns scope, forcing a VERY_LOW column (CPU) to be eliminated. Added a `force_hidden` mask (`calculateColumnWidthsHidden`) so hidden columns cost nothing.
- [x] Add numeric `cpu_milli`/`mem_bytes` to `PodMetric` (already computed in buildMetricsMap; just store them).
- [x] Extend `metrics_columns` config with optional `cpu_pct`/`mem_pct` column indices; metrics hook computes usage/request %.
- [x] transformPod: add RESTARTS (sum restartCount), %CPU/R + %MEM/R cells carrying summed request totals for the hook to convert.
- [x] Rewire pods config to the 12-column k9s layout.
- [x] Also fixed: deterministic column-drop order (unstable sort kept %MEM/R while dropping CPU/MEM — now drops rightmost-of-tier first, k9s-style).
- [x] Verify: `zig build`, `zig build test` (381 pass), `zig fmt --check`, live PTY check against cloud-core-dev.

## Review
Two root causes behind "where are rest of columns?":
1. **CPU silently dropped (all views):** the column-visibility budget counted the
   NAMESPACE column's width even when single-ns scope was about to hide it, so a
   phantom ~24-col reservation forced the lowest-priority column out. CPU lost the
   tie-break vs MEM (equal VERY_LOW priority + unstable sort). Fix: exclude
   force-hidden columns from the budget; freed space flows to NAME.
2. **Missing k9s columns:** added RESTARTS + %CPU/R + %MEM/R (real data: restartCount
   sum; usage/request % from summed container requests). PodMetric gained numeric
   cpu_milli/mem_bytes; the metrics hook converts the request integers the transform
   stashes in the pct cells.
Bonus: made narrow-width degradation deterministic (drop rightmost metric first).

Verified live (cloud-core-dev, single-ns default):
- 200/160 cols → all 12 columns, real CPU (1m/2m), RESTARTS, %CPU/R (9,18), %MEM/R (78,89).
- 140 cols → drops %MEM/R, %CPU/R, MEM; **CPU now survives** (was the bug).
- 130 cols → drops metrics + NODE, keeps RESTARTS/IP.
Files: table_layout.zig, resource_view.zig, resource_configs.zig, k8s_types.zig, K8sService.zig.
Changes left uncommitted (no commit/push requested).
