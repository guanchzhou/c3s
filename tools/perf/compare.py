#!/usr/bin/env python3
"""c3s vs k9s read-only performance comparison.

    zig build -Doptimize=ReleaseFast perf -- --context dev4.as
    python3 tools/perf/compare.py --context dev4.as --all-namespaces
    python3 tools/perf/compare.py --cli-only
    python3 tools/perf/compare.py --idle --context k8s-dev

Always --readonly. The only TUI key this tool may send is `0` (all-namespaces).
Every report records binary identity (version, commit, sha256, file(1), git/Homebrew).
Paint bytes are recorded but are not a c3s speed win.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from harness import (  # noqa: E402
    CAVEATS,
    assert_live_context,
    binary_identity,
    default_c3s,
    empty_report,
    measure_cli,
    median_pty,
    probe_cluster,
    pty_run,
    which,
)
from safety import SafetyError, tui_argv  # noqa: E402


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--c3s", default=str(default_c3s()), help="c3s binary (default zig-out/bin/c3s)")
    p.add_argument("--k9s", default=which("k9s") or "k9s", help="k9s binary")
    p.add_argument("--context", help="kube context (required for PTY / cluster probe)")
    p.add_argument("--kubeconfig", help="kubeconfig path (sets KUBECONFIG for children)")
    p.add_argument("--all-namespaces", action="store_true", help="k9s -A -c po; c3s sends 0 after first row")
    p.add_argument("--idle", action="store_true", help="8 s sample only; do not wait for pod rows (API may be down)")
    p.add_argument("--cli-only", action="store_true", help="binaries + version/help timing; no TUI")
    p.add_argument("--binaries-only", action="store_true")
    p.add_argument("--no-cluster-probe", action="store_true")
    p.add_argument("--runs", type=int, default=1, help="PTY repetitions; report median")
    p.add_argument("--sample-s", type=float, default=8.0)
    p.add_argument("--max-wait", type=float, default=45.0)
    p.add_argument("--cli-warmup", type=int, default=2)
    p.add_argument("--cli-runs", type=int, default=9)
    p.add_argument("--json", help="write the report JSON here (stdout still gets the table)")
    p.add_argument("--quiet", action="store_true")
    p.add_argument(
        "--inject-keys",
        action="store_true",
        help="inject up-arrow keys after the screen hint and record diagnostic key-write-to-first-PTY-byte latency (not proven key-to-paint)",
    )
    p.add_argument(
        "--no-refresh-trial",
        action="store_true",
        help="skip the --refresh 0 c3s comparison run (only used with --inject-keys)",
    )
    return p.parse_args(argv)


def fmt_identity(name: str, b: dict) -> str:
    ver = b.get("version") or "?"
    sha = (b.get("sha256") or "")[:12]
    bits = [f"{name:4}  {ver}", f"{b.get('bytes', 0):,} B", f"sha256 {sha}"]
    commit = b.get("commit")
    if commit:
        bits.append(f"commit {commit[:12]}")
    git = b.get("git_tree") or {}
    if git.get("head"):
        dirty = "+dirty" if git.get("dirty") else ""
        bits.append(f"tree {git['head'][:12]}{dirty}")
        if b.get("binary_commit_missing"):
            bits.append("binary commit n/a")
    hb = b.get("homebrew") or {}
    if hb.get("formula"):
        bits.append(f"homebrew {hb['formula']} {hb.get('version')}")
    zig = b.get("zig") or {}
    if zig.get("version"):
        bits.append(f"zig {zig['version']}")
    ftype = b.get("file")
    if ftype:
        bits.append(ftype[:72])
    return "  ".join(bits)


def fmt_table(report: dict) -> str:
    lines = [
        f"protocol {report['protocol']}  {report['when']}",
        f"host     {report['host'].get('machine')} {report['host'].get('system')}",
        "caveats  " + ", ".join(report.get("caveats") or CAVEATS),
    ]
    bins = report.get("binaries") or {}
    if bins:
        c, k = bins.get("c3s") or {}, bins.get("k9s") or {}
        if c:
            lines.append(fmt_identity("c3s", c))
        if k:
            lines.append(fmt_identity("k9s", k))
        cb, kb = c.get("bytes") or 0, k.get("bytes") or 0
        ratio = f"{kb / cb:.1f}×" if cb else "?"
        lines.append(f"disk     c3s {cb:,} B   k9s {kb:,} B   k9s/c3s {ratio}")
        if c.get("likely_debug"):
            lines.append("warning  c3s looks like Debug — rebuild -Doptimize=ReleaseFast")
    cli = report.get("cli") or {}
    if cli:
        cv = (cli.get("c3s_version") or {}).get("median_ms")
        kv = (cli.get("k9s_version") or {}).get("median_ms")
        lines.append(f"cli      c3s --version {cv} ms   k9s version {kv} ms")
    cl = report.get("cluster")
    if cl:
        lines.append(
            f"cluster  {cl.get('context')}  nodes={cl.get('nodes')} ns={cl.get('namespaces')} "
            f"pods={cl.get('pods')} deploy={cl.get('deployments')}  kubectl pods -A {cl.get('kubectl_pods_a_s')} s"
        )
    pty = report.get("pty") or {}
    for name in ("c3s", "k9s"):
        block = pty.get(name) or {}
        med = block.get("median") or {}
        if not med:
            continue
        if name == "c3s":
            marker_status = "pass" if med.get("authoritative_markers_ok") else "missing"
            lines.append(
                f"pty c3s  telemetry {marker_status}  first {med.get('t_first_usable_paint_s')} s  "
                f"complete {med.get('t_complete_sync_paint_s')} s  "
                f"parent {med.get('parent_rss_mb_t8s')} MB  tree {med.get('tree_rss_mb_t8s')} MB  "
                f"thr {med.get('threads_t8s')}  paint {med.get('pty_bytes_t8s')} B @8s"
            )
            counters = med.get("telemetry_counters")
            if counters:
                lines.append(
                    f"         telemetry drops: oversize={counters['dropped_oversize']} "
                    f"eagain={counters['dropped_eagain']} faults={counters['write_faults']}"
                )
            else:
                lines.append("         telemetry summary unavailable")
        else:
            lines.append(
                f"pty k9s   output-observed screen {med.get('t_screen_hint_s')} s  "
                f"parent {med.get('parent_rss_mb_t8s')} MB  tree {med.get('tree_rss_mb_t8s')} MB  "
                f"thr {med.get('threads_t8s')}  paint {med.get('pty_bytes_t8s')} B @8s"
            )
        if name == "c3s" and med.get("t_screen_hint_s") is not None:
            lines.append(f"         diag:screen-hint {med.get('t_screen_hint_s')} s  [not an authoritative c3s marker]")
        if med.get("parent_rss_mb_screen_hint") is not None:
            lines.append(
                f"         screen-hint+2s  parent {med.get('parent_rss_mb_screen_hint')} MB  "
                f"tree {med.get('tree_rss_mb_screen_hint')} MB  "
                f"thr {med.get('threads_screen_hint')}  paint {med.get('pty_bytes_screen_hint')} B"
            )
        if med.get("key_to_next_pty_byte_max_ms") is not None:
            lines.append(
                f"         diag:next-byte↑  median {med.get('key_to_next_pty_byte_median_ms')} ms  "
                f"max {med.get('key_to_next_pty_byte_max_ms')} ms  (n={med.get('n')}×5 keys)"
                f"  [diagnostic: key write → first subsequent PTY byte; not proven key-to-paint]"
            )
    no_ref = (pty.get("c3s_no_refresh") or {}).get("median") or {}
    if no_ref.get("key_to_next_pty_byte_max_ms") is not None:
        lines.append(
            f"pty c3s(--refresh 0) diag:next-byte↑  median {no_ref.get('key_to_next_pty_byte_median_ms')} ms  "
            f"max {no_ref.get('key_to_next_pty_byte_max_ms')} ms"
        )
    return "\n".join(lines) + "\n"


def measure(ns: argparse.Namespace) -> dict:
    if not ns.binaries_only and not ns.cli_only:
        if not ns.context:
            raise SystemExit("--context is required for PTY measurement (or pass --cli-only)")
        assert_live_context(ns.context)

    report = empty_report()
    c3s = Path(ns.c3s)
    k9s = Path(ns.k9s)
    if not c3s.is_file():
        raise SystemExit(f"c3s binary missing: {c3s}  (zig build -Doptimize=ReleaseFast)")
    if not k9s.is_file():
        raise SystemExit(f"k9s binary missing: {k9s}")
    report["binaries"] = {
        "c3s": binary_identity(c3s, version_argv=["--version"]),
        "k9s": binary_identity(k9s, version_argv=["version"]),
    }
    if ns.binaries_only:
        return report

    report["cli"] = {
        "c3s_version": measure_cli(str(c3s), ["--version"], warmup=ns.cli_warmup, runs=ns.cli_runs),
        "c3s_help": measure_cli(str(c3s), ["--help"], warmup=ns.cli_warmup, runs=ns.cli_runs),
        "k9s_version": measure_cli(str(k9s), ["version"], warmup=ns.cli_warmup, runs=ns.cli_runs),
        "k9s_help": measure_cli(str(k9s), ["--help"], warmup=ns.cli_warmup, runs=ns.cli_runs),
    }
    if ns.cli_only:
        return report

    if not ns.no_cluster_probe and not ns.idle:
        report["cluster"] = probe_cluster(ns.context, ns.kubeconfig)

    c3s_argv = tui_argv(str(c3s), context=ns.context, kubeconfig=ns.kubeconfig)
    k9s_argv = tui_argv(
        str(k9s),
        context=ns.context,
        kubeconfig=ns.kubeconfig,
        k9s_pods_all=ns.all_namespaces and not ns.idle,
    )
    # Second c3s argv with auto-refresh disabled: baseline for key-latency comparison.
    c3s_no_refresh_argv = tui_argv(
        str(c3s),
        context=ns.context,
        kubeconfig=ns.kubeconfig,
        extra_args=["--refresh", "0"],
    )
    inject = ns.inject_keys
    c3s_runs = []
    c3s_no_refresh_runs = []
    k9s_runs = []
    for i in range(ns.runs):
        c3s_runs.append(
            pty_run(
                "c3s",
                c3s_argv,
                kubeconfig=ns.kubeconfig,
                send_all_ns=ns.all_namespaces and not ns.idle,
                sample_s=ns.sample_s,
                max_s=ns.max_wait,
                idle=ns.idle,
                inject_keys=inject,
                c3s_telemetry=True,
            )
        )
        time.sleep(1.0)
        # Run --refresh 0 trial when key injection is active (skip if --no-refresh-trial).
        if inject and not ns.no_refresh_trial:
            c3s_no_refresh_runs.append(
                pty_run(
                    "c3s-no-refresh",
                    c3s_no_refresh_argv,
                    kubeconfig=ns.kubeconfig,
                    send_all_ns=ns.all_namespaces and not ns.idle,
                    sample_s=ns.sample_s,
                    max_s=ns.max_wait,
                    idle=ns.idle,
                    inject_keys=True,
                    c3s_telemetry=True,
                )
            )
            time.sleep(1.0)
        k9s_runs.append(
            pty_run(
                "k9s",
                k9s_argv,
                kubeconfig=ns.kubeconfig,
                send_all_ns=False,
                sample_s=ns.sample_s,
                max_s=ns.max_wait,
                idle=ns.idle,
                c3s_telemetry=False,
            )
        )
        if i + 1 < ns.runs:
            time.sleep(1.0)
    c3s_median = median_pty(c3s_runs)
    report["pty"] = {
        "cols": 120,
        "rows": 40,
        "sample_s": ns.sample_s,
        "all_namespaces": ns.all_namespaces,
        "idle": ns.idle,
        "inject_keys": inject,
        "c3s_authoritative_markers_ok": bool(c3s_median and c3s_median["authoritative_markers_ok"]),
        "c3s": {"runs": c3s_runs, "median": c3s_median},
        "c3s_no_refresh": {"runs": c3s_no_refresh_runs, "median": median_pty(c3s_no_refresh_runs)} if c3s_no_refresh_runs else None,
        "k9s": {"runs": k9s_runs, "median": median_pty(k9s_runs)},
    }
    return report


def main() -> None:
    ns = parse_args()
    try:
        report = measure(ns)
    except SafetyError as exc:
        raise SystemExit(f"safety: {exc}") from exc
    payload = json.dumps(report, indent=2)
    if ns.json:
        Path(ns.json).write_text(payload + "\n")
    if not ns.quiet:
        sys.stderr.write(fmt_table(report))
        if not ns.json:
            sys.stdout.write(payload + "\n")
    elif ns.json is None:
        sys.stdout.write(payload + "\n")


if __name__ == "__main__":
    main()
