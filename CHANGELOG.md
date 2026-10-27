---
type: note
title: Changelog
---

# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The release workflow extracts the section matching the git tag (`vX.Y.Z` →
`## [X.Y.Z]`) and fails if that section is missing. Add the section before tagging.

## [Unreleased]

## [0.5.0] - 2026-10-27

### Changed

- Resource lists stream over one reused HTTP/2 connection per context, through zig-klient's list client. The 47 built-in resource types are read as Protobuf; custom resources and Gateway API types are read as JSON. When the client can't connect, c3s falls back to the previous transports.
- A throttled list shows `API server busy, retrying in N s` in the table status while it waits.
- The system curl transport now asks for HTTP/2.

## [0.4.4] - 2026-10-25

### Security

- Control characters and terminal escape sequences in cluster data (logs, YAML, describe output, table cells) are shown as `?` instead of reaching the terminal.
- `kubectl proxy` now binds its own port instead of taking one c3s reserved, and is stopped if c3s panics.
- Saved resources are written as new owner-only files in an owner-only directory; the log file is owner-only.
- `--token` and `--insecure-skip-tls-verify` are refused at startup.

### Fixed

- `--cluster`, `--user`, `--as`, `--as-group` (repeatable), `--certificate-authority`, `--client-certificate`, `--client-key`, and `--request-timeout` are passed to every kubectl call; they were parsed and ignored. `--logFile` now sets the log path.
- `--headless`, `--logoless`, `--splashless`, and `--write` fail with an "unsupported flag" error instead of being silently ignored.
- Delete asks `Delete <kind>/<name>? (y/N)` in its own prompt, and its outcome is no longer overwritten by the connection status.
- Sanitize only removes completed/failed pods visible under the current filter and shows how many in the confirmation.
- A kubectl killed by a signal is reported as a failure.
- A failed kubectl request no longer re-runs the exec credential plugin.
- Triggered job names never end in `-` or `.` when shortened.
- Theme colors such as `seashell` are no longer rejected.
- Long log lines are truncated on a character boundary.
- `--help` shows the log path for the current user.
- Live diagnostics read eligible contexts from `C3S_DIAGNOSTIC_CONTEXTS`.

## [0.4.3] - 2026-10-20

### Added

- Pressing `o` on a pod in `PodsView` jumps to `NodesView` filtered to the selected pod's node.
- Packaged `skins/` alongside the `c3s` binary in release archives.

### Fixed

- Fixed free-before-alloc ordering in `Header.updateK8sVersion` and `ThemesView.setCurrentTheme`.
- Rolled back `view_ptrs` push if `stack.append` fails in `ViewManager.pushView`.
- Prevented `zig build test` from writing test namespaces to `~/.config/c3s/config.yaml` and cleaned up test-only memory leaks in `xdg` and `logger`.

## [0.4.2] - 2026-10-19

### Changed

- Zig 0.17.0 is now required to build from source. Zig 0.16 is no longer
  supported: 0.17 `zig fmt` rewrites `@intFromEnum` and `@enumFromInt` to
  builtins that 0.16 rejects. CI and release binaries are built with Zig 0.17.0.

## [0.4.1] - 2026-10-06

### Fixed

- Startup abort (`panic: integer overflow` in `activeIdentityCount`) once a
  second pod, node, namespace, or metrics subscription became active.

## [0.4.0] - 2026-09-21

### Added

- Cedar policy workbench at `:cedar`: lists `cedar.k8s.aws` Policy objects and
  runs the official `cedar` CLI for check-parse, format, validate, a
  cluster-wide scan, and a can-i evaluation with a verb matrix. Read-only, off
  the UI thread, and fail-closed — an incomplete policy set answers
  `INDETERMINATE` rather than `ALLOW` or `DENY`.
- Typed status, CPU, memory, restart, and age filters, configurable metric
  thresholds, and faults-mode titles.
- Sentence-style palette targeting, kind cycling, full-column copy picker, and
  permission-aware discovery suggestions.
- Bounded session timelines and deterministic unhealthy-workload reports with
  rollout, container, condition, and Warning-event findings.
- Kubernetes-native Argo CD Application refresh and truthful sync-details
  reporting without Argo credentials or an `argocd` binary.
- Port-forwards can be started directly from `:pf`; failed/exited forwards stay
  visible with their exit code.

### Changed

- Namespace selection preserves the active resource kind instead of always
  returning to pods.

## [0.3.2] - 2026-09-21

### Added

- Namespace Enter scopes the pods view to that namespace instead of
  `pods(all)`.
- Recent namespaces persist as numbered `1`–`9` shortcuts (`0` remains
  all-namespaces), matching k9s-style hopping.
- Enter on a node opens that node's pods via a projection `node=` filter.
- `--command` / `-c` runs after connect through the palette resolver.
- Discovered cluster resources and their short names appear in the command
  palette dropdown, so `nodepool` suggests `nodepools` while typing.
- The header lists the numbered namespaces between the cluster stats and the
  key hints, k9s-style: `<0>` all-namespaces followed by each recent namespace
  by name, with the active one highlighted.

### Changed

- The header's `<0> all` / `<1-9> recent namespaces` placeholders are gone; the
  namespace column names the destination behind every digit instead.

### Fixed

- Replacing an already-active root view no longer retires the LIST before
  paint, so startup commands such as `-c pods` show rows.
- Node drill-down uses the pod projection predicate, not formatted-row text.
- Namespace switches clear stale rows so the previous namespace cannot paint
  under the new title.

## [0.3.1] - 2026-09-18

### Fixed

- Nodes slash-filter matches the VERSION column, so queries such as `1.33`
  hit kubelet strings like `v1.33.x`. INTERNAL-IP, AGE, STATUS, and ROLES stay
  out of the search.
- Pod CPU/MEM metrics start on the first watch upsert after an empty initial
  list, instead of remaining `n/a` for that subscription.

## [0.3.0] - 2026-09-18

### Added

- Generic discovery-driven custom-resource views with server-side Kubernetes
  Table columns, including Karpenter NodeClaims, NodePools, and EC2NodeClasses.
- Semantic Kubernetes-version sorting in the Nodes view with `Shift-V`.
- A synthetic projection benchmark for large resource lists.

### Changed

- Large pod lists use indexed projection updates, progressive merging, and
  coalesced UI synchronization to avoid repeated full table rebuilds.
- Interactive terminal output is damage-aware and paced up to 120 Hz, with
  synchronized presentation for Metal-backed terminals.
- Palette view commands replace the root view from any navigation depth.

### Fixed

- Dynamic-resource views no longer crash while rendering their first header.
- Command-palette selection text uses the selected foreground theme color.
- Numeric and time-based pod sorting remains correct with projected rows.
- Metrics startup cannot leak across pod-subscription restarts, and time-derived
  cells refresh without defeating row reuse.

## [0.2.1] - 2026-09-10

### Changed

- Current Zig 0.17 development builds are supported alongside the Zig 0.16.0
  release baseline, with a non-blocking Zig master CI canary.
- Removed the obsolete root `plan.txt`; maintained design and roadmap documents
  live under `docs/design/`.

### Fixed

- Synchronized the fake read transport used by concurrent lifecycle tests so
  request recording and scripted responses cannot race.
- Kept the Zig 0.17 allocation gate deterministic despite threaded-I/O
  allocator activity.

## [0.2.0] - 2026-09-09

### Added

- A supervised Kubernetes data plane streams LIST and WATCH updates for pods,
  namespaces, nodes, and every resource-family view through exact identities.
- Direct HTTPS readonly transport with bounded proxy fallback, pagination guards,
  request auditing, cancellation, and redacted Task 15 diagnostics.
- Projected metadata labels and k9s-compatible substring, inverse, fuzzy, label,
  and faults-only filtering across resource views.
- Monotonic performance telemetry and deterministic integration gates for
  lifecycle, ordering, allocation, restart, rollback, shutdown, and ancillary
  request behavior.

### Changed

- Resource views now subscribe to the shared data plane instead of issuing
  independent timer-driven Kubernetes LIST requests.
- Incremental projections preserve rows during relists, retain selection in the
  visible viewport, and render pod metrics and sorting from projected records.
- Readonly live startup uses paginated LIST requests and cached exec credentials
  to meet the validated first-paint and complete-sync latency budgets.

### Security

- Active contexts are matched to their resolved cluster identity before live
  readonly validation.
- Interactive kubectl commands pin both kubeconfig and context and remain fenced
  by the service-layer readonly guard.
- Lifecycle shutdown drains owned envelopes and cannot silently drop identities
  when control or delivery queues are saturated.

## [0.1.0] - 2026-08-30

First tagged release.

### Added

- Gateway API views: GatewayClass, Gateway, HTTPRoute, GRPCRoute, ReferenceGrant,
  TCPRoute, TLSRoute, UDPRoute, BackendTLSPolicy, ListenerSet (`:gw`, `:htr`, …).
- Kubernetes 1.33–1.37 daily-driver views: EndpointSlice, IngressClass, IPAddress,
  ServiceCIDR, VolumeAttributesClass, CSIDriver, ValidatingAdmissionPolicy and
  Binding, MutatingAdmissionPolicy and Binding, Validating/MutatingWebhookConfiguration,
  ResourceClaim, DeviceClass, PriorityClass, RuntimeClass, Lease, CSR,
  StorageVersionMigration.
- Tag-triggered release pipeline: cross-compiled linux/macOS binaries, CHANGELOG
  notes, GitHub Release, Homebrew formula, SLSA provenance.
- Short command aliases matching k9s: `role`, `rb`, `cr`, `crb`, `quota`, `limits`.
- `F` port-forward on Services, not only Pods.

### Changed

- CI: least-privilege `contents: read`, concurrency cancellation, checkout@v6,
  macos job only on `main` (PRs stay on Ubuntu to conserve Actions minutes).
- `kubectl` mutations (`set image`, `patch` finalizers, `cp`) go through the
  `--readonly` guard at `K8sService.runKubectl`.
- `e` (edit) works on every resource view, not only Pods.

### Security

- YAML/describe of Secrets redacts `data` and `stringData` values. Use `x` to decode.
- Port-forward specs accept only `digits[:digits]` (or a named remote port). Shell
  metacharacters are rejected before kubectl sees them.
- Port-forward, set-image, transfer, and kill-finalizers refuse under `--readonly`
  before prompting.

[Unreleased]: https://github.com/guanchzhou/c3s/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/guanchzhou/c3s/releases/tag/v0.2.0
[0.1.0]: https://github.com/guanchzhou/c3s/releases/tag/v0.1.0
