# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The release workflow extracts the section matching the git tag (`vX.Y.Z` →
`## [X.Y.Z]`) and fails if that section is missing. Add the section before tagging.

## [Unreleased]

## [0.2.1] - 2026-09-10

### Changed

- Current Zig 0.17 development builds are supported alongside the Zig 0.16.0
  release baseline, with a non-blocking Zig master CI canary.
- Removed the obsolete root `plan.txt`; maintained design and roadmap documents
  live under `docs/design/`.

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
