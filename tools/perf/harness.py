"""PTY, telemetry, and process metrics for read-only c3s vs k9s runs."""

from __future__ import annotations

import contextlib
import errno
import fcntl
import hashlib
import json
import os
import platform
import pty
import re
import select
import signal
import stat
import struct
import subprocess
import sys
import termios
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from safety import (
    SafetyError,
    assert_safe_kubectl_argv,
    assert_safe_tui_input,
)

PROTOCOL = "c3s-k9s-perf/1.2"
ROWS, COLS = 40, 120
SAMPLE_S = 8.0
MAX_S = 45.0
DEBUG_SIZE_WARN = 10_000_000
MAX_TELEMETRY_RECORD_BYTES = 512
C3S_PERF_FD = "C3S_PERF_FD"
U32_MAX = (1 << 32) - 1
U64_MAX = (1 << 64) - 1
# c3s currently targets 64-bit platforms. Keep usize deterministic on the wire
# instead of deriving acceptance from the Python host running the report.
TELEMETRY_USIZE_MAX = U64_MAX
ALLOWED_LIVE_CONTEXTS = frozenset({"dev4.as", "rc.alpha-sense.org"})
SCREEN_HINT_MARKERS = (
    b"kube-system",
    b"crossplane",
    b"cloud-services",
    b"istio-system",
    b"Pods(all)",
    b"pods(all)",  # c3s title: pods(all)[N]
    b"(all)[",
    b"[all]",
    b"namespace all",
)
TELEMETRY_EVENTS = frozenset(
    {
        "sync_start",
        "first_batch_queued",
        "first_usable_paint",
        "list_complete_received",
        "complete_sync_paint",
        "watch_connected",
        "metrics_ready",
        "reconnect_start",
        "reconnect_complete",
        "summary",
    }
)
TELEMETRY_STRING_FIELDS = ("event", "context", "resource", "scope")
TELEMETRY_INTEGER_FIELDS = (
    "monotonic_ns",
    "generation",
    "subscription_id",
    "applied_revision",
    "object_count",
    "queue_bytes",
)
TELEMETRY_COUNTER_FIELDS = ("dropped_oversize", "dropped_eagain", "write_faults")
TELEMETRY_INTEGER_MAX = {
    "monotonic_ns": U64_MAX,
    "generation": U64_MAX,
    "subscription_id": U32_MAX,
    "applied_revision": U64_MAX,
    "object_count": TELEMETRY_USIZE_MAX,
    "queue_bytes": TELEMETRY_USIZE_MAX,
}
ANSI = re.compile(
    rb"(?:\x1b\[[0-9;?=]*[A-Za-z]"
    rb"|\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)"
    rb"|\x1b[()][0-9AB]"
    rb"|\x1b[NO]"
    rb"|\r)"
)
CAVEATS = [
    "readonly_only",
    "paint_bytes_are_not_a_c3s_win",
    "rss_mb_is_ps_rss_kb_div_1000",
    "c3s_tree_includes_kubectl_proxy",
    "c3s_screen_hint_is_diagnostic_only",
]


def _is_bounded_int(value: object, maximum: int) -> bool:
    return type(value) is int and 0 <= value <= maximum


def assert_live_context(context: str) -> None:
    """Allow live cluster and PTY work only on the two approved contexts."""
    if context not in ALLOWED_LIVE_CONTEXTS:
        raise SafetyError(f"live context is not allowlisted: {context!r}")


def _tui_context(argv: list[str]) -> str:
    contexts: list[str] = []
    for index, arg in enumerate(argv):
        if arg == "--context":
            if index + 1 >= len(argv):
                raise SafetyError("--context requires a value")
            contexts.append(argv[index + 1])
        elif arg.startswith("--context="):
            contexts.append(arg.partition("=")[2])
    if len(contexts) != 1:
        raise SafetyError("live TUI argv must contain exactly one --context")
    return contexts[0]


def _valid_telemetry_record(record: object) -> bool:
    if not isinstance(record, dict):
        return False
    if any(not isinstance(record.get(field), str) for field in TELEMETRY_STRING_FIELDS):
        return False
    if record["event"] not in TELEMETRY_EVENTS:
        return False
    if any(
        not _is_bounded_int(record.get(field), TELEMETRY_INTEGER_MAX[field])
        for field in TELEMETRY_INTEGER_FIELDS
    ):
        return False
    if record["event"] == "summary" and any(
        not _is_bounded_int(record.get(field), U64_MAX) for field in TELEMETRY_COUNTER_FIELDS
    ):
        return False
    return True


class TelemetryStreamParser:
    """Incrementally parse bounded complete NDJSON records."""

    def __init__(self) -> None:
        self._buffer = bytearray()
        self._dropping_oversize = False
        self.oversize_records = 0
        self.malformed_records = 0
        self.truncated_records = 0

    @property
    def buffered_bytes(self) -> int:
        return len(self._buffer)

    def feed(self, chunk: bytes) -> list[dict[str, Any]]:
        events: list[dict[str, Any]] = []
        for byte in chunk:
            if self._dropping_oversize:
                if byte == ord("\n"):
                    self._dropping_oversize = False
                continue

            self._buffer.append(byte)
            if byte == ord("\n"):
                raw = bytes(self._buffer)
                self._buffer.clear()
                if len(raw) > MAX_TELEMETRY_RECORD_BYTES:
                    self.oversize_records += 1
                    continue
                try:
                    record = json.loads(raw)
                except (UnicodeDecodeError, json.JSONDecodeError):
                    self.malformed_records += 1
                    continue
                if not _valid_telemetry_record(record):
                    self.malformed_records += 1
                    continue
                events.append(record)
            elif len(self._buffer) >= MAX_TELEMETRY_RECORD_BYTES:
                self._buffer.clear()
                self._dropping_oversize = True
                self.oversize_records += 1
        return events

    def finish(self) -> list[dict[str, Any]]:
        if self._buffer:
            self.truncated_records += 1
        self._buffer.clear()
        self._dropping_oversize = False
        return []


def summarize_telemetry(
    events: list[dict[str, Any]],
    *,
    process_start_ns: int,
    t_screen_hint_s: float | None,
) -> dict[str, Any]:
    def marker_time(event_name: str) -> float | None:
        if not _is_bounded_int(process_start_ns, U64_MAX):
            return None
        for event in events:
            if not _valid_telemetry_record(event):
                continue
            if event.get("event") != event_name:
                continue
            timestamp = event.get("monotonic_ns")
            if not _is_bounded_int(timestamp, U64_MAX) or timestamp < process_start_ns:
                return None
            return round((timestamp - process_start_ns) / 1_000_000_000, 6)
        return None

    first = marker_time("first_usable_paint")
    complete = marker_time("complete_sync_paint")
    counters = None
    for event in reversed(events):
        if _valid_telemetry_record(event) and event.get("event") == "summary":
            counters = {field: event[field] for field in TELEMETRY_COUNTER_FIELDS}
            break
    return {
        "t_screen_hint_s": t_screen_hint_s,
        "t_first_usable_paint_s": first,
        "t_complete_sync_paint_s": complete,
        "authoritative_markers_ok": first is not None and complete is not None,
        "telemetry_counters": counters,
    }


@dataclass
class PtyChild:
    pid: int
    master_fd: int
    telemetry_read_fd: int | None
    process_start_ns: int
    telemetry_parser: TelemetryStreamParser | None = None
    telemetry_events: list[dict[str, Any]] | None = None
    _master_owned: bool = True
    _process_owned: bool = True
    _cleaned: bool = False

    def __enter__(self) -> PtyChild:
        return self

    def attach_telemetry(
        self,
        parser: TelemetryStreamParser,
        events: list[dict[str, Any]] | None = None,
    ) -> None:
        self.telemetry_parser = parser
        self.telemetry_events = events

    def cleanup(
        self,
        active_type: type[BaseException] | None,
        active: BaseException | None,
        active_traceback: object,
    ) -> None:
        """Drain and release once; first cleanup failure wins only without a body failure."""
        _ = active_type
        _ = active_traceback
        if self._cleaned:
            return
        self._cleaned = True
        failures: list[tuple[str, BaseException]] = []

        def attempt(label: str, operation: Callable[[], object]) -> None:
            try:
                operation()
            except BaseException as exc:
                failures.append((label, exc))

        parser = self.telemetry_parser
        telemetry_fd = self.telemetry_read_fd
        if parser is not None and telemetry_fd is not None:
            def drain() -> None:
                while True:
                    try:
                        chunk = os.read(telemetry_fd, 4096)
                    except OSError as exc:
                        if exc.errno == errno.EAGAIN:
                            return
                        raise
                    if not chunk:
                        return
                    parsed = parser.feed(chunk)
                    if self.telemetry_events is not None:
                        self.telemetry_events.extend(parsed)

            attempt("telemetry drain", drain)
        if parser is not None:
            attempt("telemetry parser finish", parser.finish)

        if telemetry_fd is not None:
            self.telemetry_read_fd = None
            attempt("telemetry reader close", lambda: os.close(telemetry_fd))
        if self._master_owned:
            self._master_owned = False
            attempt("PTY master close", lambda: os.close(self.master_fd))
        if self._process_owned:
            self._process_owned = False
            attempt("child termination/reap", lambda: kill_tree(self.pid))

        if not failures:
            return
        if active is not None:
            for label, failure in failures:
                with contextlib.suppress(BaseException):
                    active.add_note(f"{label} failed during cleanup: {failure!r}")
            return
        raise failures[0][1]

    def cleanup_preserving(
        self,
        active_type: type[BaseException] | None,
        active: BaseException | None,
        active_traceback: object,
    ) -> None:
        try:
            self.cleanup(active_type, active, active_traceback)
        except BaseException as cleanup_failure:
            if active is None:
                raise
            with contextlib.suppress(BaseException):
                active.add_note(f"unexpected cleanup failure: {cleanup_failure!r}")

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc: BaseException | None,
        traceback: object,
    ) -> bool:
        self.cleanup_preserving(exc_type, exc, traceback)
        return False


def _close_fd_quietly(fd: int | None) -> None:
    if fd is None:
        return
    with contextlib.suppress(BaseException):
        os.close(fd)


def _cleanup_child(pid: int, master_fd: int, telemetry_read_fd: int | None) -> None:
    _close_fd_quietly(telemetry_read_fd)
    _close_fd_quietly(master_fd)
    with contextlib.suppress(BaseException):
        kill_tree(pid)


def _fork_exec_pty(
    argv: list[str],
    env: dict[str, str],
    *,
    c3s_telemetry: bool,
) -> PtyChild:
    """Fork a PTY and expose a c3s-only nonblocking telemetry reader."""
    child_env = env.copy()
    child_env.pop(C3S_PERF_FD, None)
    read_fd: int | None = None
    write_fd: int | None = None
    try:
        if c3s_telemetry:
            read_fd, write_fd = os.pipe()
            os.set_blocking(read_fd, False)
            os.set_blocking(write_fd, False)
            os.set_inheritable(read_fd, False)
            os.set_inheritable(write_fd, True)

        process_start_ns = time.monotonic_ns()
        pid, master = pty.fork()
    except BaseException:
        _close_fd_quietly(read_fd)
        _close_fd_quietly(write_fd)
        raise

    if pid == 0:
        try:
            if read_fd is not None:
                os.close(read_fd)
            if write_fd is not None:
                child_env[C3S_PERF_FD] = str(write_fd)
            os.execvpe(argv[0], argv, child_env)
        except BaseException as exc:
            with contextlib.suppress(BaseException):
                os.write(2, f"exec failed: {exc}\n".encode())
            os._exit(127)

    try:
        if write_fd is not None:
            os.close(write_fd)
            write_fd = None
    except BaseException:
        _close_fd_quietly(write_fd)
        _cleanup_child(pid, master, read_fd)
        raise
    try:
        return PtyChild(
            pid=pid,
            master_fd=master,
            telemetry_read_fd=read_fd,
            process_start_ns=process_start_ns,
        )
    except BaseException:
        _cleanup_child(pid, master, read_fd)
        raise


def strip_ansi(buf: bytes) -> bytes:
    return ANSI.sub(b"", buf)


def rss_mb(kb: int) -> float:
    return round(kb / 1000.0, 1)


def median(values: list[float]) -> float | None:
    if not values:
        return None
    s = sorted(values)
    n = len(s)
    mid = n // 2
    if n % 2:
        return s[mid]
    return (s[mid - 1] + s[mid]) / 2.0


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent.parent


def default_c3s() -> Path:
    return repo_root() / "zig-out" / "bin" / "c3s"


def which(name: str) -> str | None:
    for d in os.environ.get("PATH", "").split(os.pathsep):
        p = Path(d) / name
        if p.is_file() and os.access(p, os.X_OK):
            return str(p)
    return None


def file_info(path: str | Path) -> dict[str, Any]:
    p = Path(path)
    st = p.stat()
    real = p.resolve()
    digest = hashlib.sha256()
    with p.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return {
        "path": str(p),
        "realpath": str(real),
        "symlink": str(p) != str(real),
        "bytes": st.st_size,
        "sha256": digest.hexdigest(),
        "mtime": int(st.st_mtime),
        "mtime_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z", time.localtime(st.st_mtime)),
        "mode": stat.filemode(st.st_mode),
        "likely_debug": st.st_size >= DEBUG_SIZE_WARN,
    }


def capture_cmd_text(argv: list[str], *, cap: int = 4000) -> dict[str, Any]:
    p = subprocess.run(argv, capture_output=True, timeout=15)
    raw = p.stdout + p.stderr
    text = strip_ansi(raw).decode("utf-8", "replace")
    text = "".join(ch if (ch == "\n" or 32 <= ord(ch) < 127) else " " for ch in text)
    if len(text) > cap:
        text = text[:cap] + "\n…"
    return {
        "argv": argv,
        "exit": p.returncode,
        "text": text.strip(),
    }


def parse_version_fields(text: str) -> dict[str, str | None]:
    """Pull Version/Commit/Date from c3s --version or k9s version output."""
    fields: dict[str, str | None] = {"version": None, "commit": None, "date": None}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        key = key.strip().lower()
        val = val.strip()
        if not val:
            continue
        if key == "version":
            fields["version"] = val
        elif key == "commit":
            fields["commit"] = None if val.lower() in {"n/a", "none", "-"} else val
        elif key == "date":
            fields["date"] = None if val.lower() in {"n/a", "none", "-"} else val
    return fields


def file_type(path: str | Path) -> str | None:
    try:
        p = subprocess.run(["file", "-b", str(path)], capture_output=True, text=True, timeout=5)
    except OSError:
        return None
    if p.returncode != 0:
        return None
    return p.stdout.strip() or None


def git_tree(root: Path) -> dict[str, Any] | None:
    def git(*args: str) -> str | None:
        p = subprocess.run(["git", "-C", str(root), *args], capture_output=True, text=True)
        if p.returncode != 0:
            return None
        return p.stdout.strip()

    head = git("rev-parse", "HEAD")
    if not head:
        return None
    porcelain = git("status", "--porcelain") or ""
    return {
        "head": head,
        "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
        "describe": git("describe", "--always", "--dirty", "--tags"),
        "subject": git("log", "-1", "--format=%h %cI %s"),
        "dirty": bool(porcelain),
    }


def homebrew_cellar(realpath: str) -> dict[str, str] | None:
    # /opt/homebrew/Cellar/k9s/0.51.0/bin/k9s
    parts = Path(realpath).parts
    if "Cellar" not in parts:
        return None
    i = parts.index("Cellar")
    if i + 2 >= len(parts):
        return None
    return {"formula": parts[i + 1], "version": parts[i + 2], "cellar": str(Path(*parts[: i + 3]))}


def binary_identity(path: str | Path, *, version_argv: list[str]) -> dict[str, Any]:
    info = file_info(path)
    ident: dict[str, Any] = {**info, "file": file_type(info["realpath"] or info["path"])}
    captured = capture_cmd_text([str(path), *version_argv])
    ident["version_cmd"] = captured
    ident.update(parse_version_fields(captured["text"]))
    hb = homebrew_cellar(info["realpath"])
    if hb:
        ident["homebrew"] = hb
    try:
        Path(info["realpath"]).relative_to(repo_root())
        ident["under_repo"] = True
    except ValueError:
        ident["under_repo"] = False
    if ident["under_repo"]:
        tree = git_tree(repo_root())
        if tree:
            ident["git_tree"] = tree
            ident["binary_commit_missing"] = ident.get("commit") is None
        zig = which("zig")
        if zig:
            zcap = capture_cmd_text([zig, "version"])
            ident["zig"] = {"path": zig, "version": zcap["text"].split()[0] if zcap["text"] else None}
    return ident


def set_winsize(fd: int, rows: int = ROWS, cols: int = COLS) -> None:
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))


def rss_kb(pid: int) -> int:
    try:
        out = subprocess.check_output(["ps", "-o", "rss=", "-p", str(pid)], text=True).strip()
    except subprocess.CalledProcessError:
        return 0
    if not out:
        return 0
    return int(out.split()[0])


def threads_of(pid: int) -> int:
    try:
        out = subprocess.check_output(["ps", "-M", "-p", str(pid)], text=True)
    except subprocess.CalledProcessError:
        return 0
    return max(0, len(out.splitlines()) - 1)


def proc_table() -> list[tuple[int, int, int]]:
    out = subprocess.check_output(["ps", "-ax", "-o", "pid=,ppid=,rss="], text=True)
    rows: list[tuple[int, int, int]] = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            rows.append((int(parts[0]), int(parts[1]), int(parts[2])))
        except ValueError:
            continue
    return rows


def tree_detail(root: int) -> tuple[int, int, list[dict[str, Any]]]:
    rows = proc_table()
    by_ppid: dict[int, list[int]] = {}
    rss_map: dict[int, int] = {}
    for pid, ppid, rss in rows:
        rss_map[pid] = rss
        by_ppid.setdefault(ppid, []).append(pid)
    seen: set[int] = set()
    stack = [root]
    members: list[int] = []
    while stack:
        pid = stack.pop()
        if pid in seen:
            continue
        seen.add(pid)
        members.append(pid)
        stack.extend(by_ppid.get(pid, []))
    cmds: list[dict[str, Any]] = []
    total = 0
    for pid in members:
        total += rss_map.get(pid, 0)
        try:
            comm = subprocess.check_output(["ps", "-o", "rss=,comm=", "-p", str(pid)], text=True).strip()
        except subprocess.CalledProcessError:
            continue
        parts = comm.split(None, 1)
        if len(parts) == 2:
            cmds.append({"pid": pid, "rss_kb": int(parts[0]), "comm": parts[1][:80]})
        elif parts:
            cmds.append({"pid": pid, "rss_kb": rss_map.get(pid, 0), "comm": parts[0][:80]})
    cmds.sort(key=lambda x: -x["rss_kb"])
    return total, len(members), cmds


def kill_tree(pid: int) -> None:
    try:
        os.killpg(pid, signal.SIGTERM)
    except OSError:
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError:
            return
    deadline = time.time() + 1.5
    while time.time() < deadline:
        try:
            waited, _ = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                return
        except OSError:
            return
        time.sleep(0.05)
    try:
        os.killpg(pid, signal.SIGKILL)
    except OSError:
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass
    try:
        os.waitpid(pid, 0)
    except OSError:
        pass


def run_timed(argv: list[str], *, env: dict[str, str] | None = None) -> float:
    t0 = time.perf_counter()
    subprocess.run(argv, check=False, capture_output=True, env=env)
    return time.perf_counter() - t0


def measure_cli(binary: str, args: list[str], *, warmup: int, runs: int) -> dict[str, Any]:
    argv = [binary, *args]
    for _ in range(warmup):
        run_timed(argv)
    samples = [run_timed(argv) * 1000.0 for _ in range(runs)]
    return {
        "argv": argv,
        "warmup": warmup,
        "n": runs,
        "ms": [round(x, 3) for x in samples],
        "median_ms": round(median(samples) or 0.0, 3),
    }


def run_kubectl(
    argv: list[str],
    *,
    timeout: int,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    assert_safe_kubectl_argv(argv)
    return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, env=env)


def count_lines(argv: list[str], *, timeout: int, env: dict[str, str] | None = None) -> int:
    p = run_kubectl(argv, timeout=timeout, env=env)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.strip() or f"kubectl failed: {argv}")
    return sum(1 for ln in p.stdout.splitlines() if ln.strip())


def probe_cluster(context: str, kubeconfig: str | None, *, timeout: int = 45) -> dict[str, Any]:
    assert_live_context(context)
    env = os.environ.copy()
    if kubeconfig:
        env["KUBECONFIG"] = kubeconfig
    else:
        env.pop("KUBECONFIG", None)
    prefix = ["kubectl"]
    if kubeconfig:
        prefix += ["--kubeconfig", kubeconfig]
    prefix += ["--context", context, f"--request-timeout={timeout}s"]
    t0 = time.perf_counter()
    pods = count_lines(prefix + ["get", "pods", "-A", "--no-headers"], timeout=timeout, env=env)
    pods_s = round(time.perf_counter() - t0, 3)
    return {
        "context": context,
        "nodes": count_lines(prefix + ["get", "nodes", "--no-headers"], timeout=timeout, env=env),
        "namespaces": count_lines(prefix + ["get", "ns", "--no-headers"], timeout=timeout, env=env),
        "pods": pods,
        "deployments": count_lines(prefix + ["get", "deploy", "-A", "--no-headers"], timeout=timeout, env=env),
        "kubectl_pods_a_s": pods_s,
    }


def pty_run(
    name: str,
    argv: list[str],
    *,
    kubeconfig: str | None,
    send_all_ns: bool,
    sample_s: float = SAMPLE_S,
    max_s: float = MAX_S,
    idle: bool = False,
    inject_keys: bool = False,
    n_key_samples: int = 5,
    key_settle_s: float = 10.0,
    c3s_telemetry: bool,
) -> dict[str, Any]:
    from safety import assert_safe_tui_argv

    assert_live_context(_tui_context(argv))
    assert_safe_tui_argv(argv)
    env = os.environ.copy()
    if kubeconfig:
        env["KUBECONFIG"] = kubeconfig
    else:
        env.pop("KUBECONFIG", None)
    env["TERM"] = "xterm-256color"
    env["COLORTERM"] = "truecolor"
    env["LC_ALL"] = env.get("LC_ALL") or "en_US.UTF-8"
    env.pop("C3S_DEBUG", None)

    with _fork_exec_pty(argv, env, c3s_telemetry=c3s_telemetry) as child:
        return _pty_run_child(
            name,
            argv,
            child,
            send_all_ns=send_all_ns,
            sample_s=sample_s,
            max_s=max_s,
            idle=idle,
            inject_keys=inject_keys,
            n_key_samples=n_key_samples,
            key_settle_s=key_settle_s,
        )


def _pty_run_child(
    name: str,
    argv: list[str],
    child: PtyChild,
    *,
    send_all_ns: bool,
    sample_s: float,
    max_s: float,
    idle: bool,
    inject_keys: bool,
    n_key_samples: int,
    key_settle_s: float,
) -> dict[str, Any]:
    pid = child.pid
    master = child.master_fd
    telemetry_read_fd = child.telemetry_read_fd
    telemetry_parser = TelemetryStreamParser()
    child.attach_telemetry(telemetry_parser)
    telemetry_events: list[dict[str, Any]] = []
    child.attach_telemetry(telemetry_parser, telemetry_events)

    try:
        set_winsize(master)
        os.kill(pid, signal.SIGWINCH)
    except OSError:
        pass

    fl = fcntl.fcntl(master, fcntl.F_GETFL)
    fcntl.fcntl(master, fcntl.F_SETFL, fl | os.O_NONBLOCK)

    def elapsed() -> float:
        return (time.monotonic_ns() - child.process_start_ns) / 1_000_000_000

    n_bytes = 0
    buf = bytearray()
    t_running: float | None = None
    t_screen_hint: float | None = None
    sent_all_ns = False
    sample_8s: dict[str, Any] | None = None
    sample_screen_hint: dict[str, Any] | None = None
    master_open = True

    # Diagnostic key-timing state: after the view loads, inject up-arrow keys at
    # 1.5 s intervals and record time from key write to first subsequent PTY byte.
    # This is NOT proven key-to-flushed-paint: any PTY output satisfies it,
    # including partial or unrelated output.  Fields are named key_to_next_pty_byte_*
    # to make that limitation explicit.  Authoritative key-to-paint telemetry is
    # a separate future task.
    t_key_inject: float | None = None  # perf_counter() when last key was written
    t_last_key: float | None = None  # elapsed process time at last injection
    key_to_next_pty_byte_ms: list[float] = []  # key write → first subsequent PTY byte (ms)

    def sample(tag: str) -> dict[str, Any]:
        parent = rss_kb(pid)
        tree, nproc, procs = tree_detail(pid)
        return {
            "tag": tag,
            "t": round(elapsed(), 3),
            "parent_rss_kb": parent,
            "parent_rss_mb": rss_mb(parent),
            "tree_rss_kb": tree,
            "tree_rss_mb": rss_mb(tree),
            "nproc": nproc,
            "threads": threads_of(pid),
            "pty_bytes": n_bytes,
            "procs": procs[:8],
        }

    try:
        while elapsed() < max_s:
            now = elapsed()
            read_fds = [master] if master_open else []
            if telemetry_read_fd is not None:
                read_fds.append(telemetry_read_fd)
            if not read_fds:
                break
            ready, _, _ = select.select(read_fds, [], [], 0.05)

            if telemetry_read_fd is not None and telemetry_read_fd in ready:
                try:
                    telemetry_chunk = os.read(telemetry_read_fd, 4096)
                except OSError as exc:
                    if exc.errno == errno.EAGAIN:
                        telemetry_chunk = None
                    else:
                        raise
                if telemetry_chunk:
                    telemetry_events.extend(telemetry_parser.feed(telemetry_chunk))
                elif telemetry_chunk == b"":
                    telemetry_read_fd = None

            if master_open and master in ready:
                try:
                    chunk = os.read(master, 65536)
                except OSError as exc:
                    if exc.errno == errno.EAGAIN:
                        chunk = None
                    elif exc.errno == errno.EIO:
                        chunk = b""
                    else:
                        raise
                if chunk == b"":
                    master_open = False
                elif chunk:
                    n_bytes += len(chunk)
                    # Record key-to-first-byte latency when we get data after a key injection.
                    if inject_keys and t_key_inject is not None:
                        latency = (time.perf_counter() - t_key_inject) * 1000.0
                        key_to_next_pty_byte_ms.append(round(latency, 1))
                        t_key_inject = None
                    buf.extend(chunk)
                    if len(buf) > 2_000_000:
                        del buf[: len(buf) - 1_000_000]
                    plain = strip_ansi(bytes(buf))
                    if t_running is None and b"Running" in plain:
                        t_running = elapsed()
                    if t_screen_hint is None and any(m in plain for m in SCREEN_HINT_MARKERS):
                        t_screen_hint = elapsed()
                    if (
                        send_all_ns
                        and not sent_all_ns
                        and not idle
                        and n_bytes > 0
                        and now >= 1.0
                        and t_screen_hint is None
                    ):
                        # c3s ignores -A; `0` toggles all-namespaces. Do not wait
                        # for Running — default ns is often empty (k8s-dev).
                        payload = b"0"
                        assert_safe_tui_input(payload)
                        os.write(master, payload)
                        sent_all_ns = True

            if sample_8s is None and now >= sample_s:
                sample_8s = sample("t8s")
            if (
                not idle
                and sample_screen_hint is None
                and t_screen_hint is not None
                and now >= t_screen_hint + 2.0
            ):
                sample_screen_hint = sample("screen_hint+2s")

            # Diagnostic: inject navigation keys and measure time from write to
            # first subsequent PTY byte.  key_settle_s (default 10 s) gives the
            # initial all-ns LIST time to complete before sampling begins.
            # Caveat: (all)[ fires on the loading frame (title change), not on
            # data arrival, so the initial LIST may still be running at
            # t_screen_hint+2s. Any sample captured during that window is labelled
            # as an outlier in key_to_next_pty_byte_settle_note.
            if (
                inject_keys
                and sample_screen_hint is not None
                and now >= (t_screen_hint or 0) + key_settle_s
                and t_key_inject is None
                and len(key_to_next_pty_byte_ms) < n_key_samples
            ):
                since_last = (now - t_last_key) if t_last_key is not None else float("inf")
                if since_last >= 1.5:
                    payload = b"\x1b[A"  # up arrow — read-only navigation
                    assert_safe_tui_input(payload)
                    os.write(master, payload)
                    t_key_inject = time.perf_counter()
                    t_last_key = now

            if idle and sample_8s is not None and now >= sample_s + 1.0:
                break
            if sample_8s and (idle or sample_screen_hint) and now >= sample_s + 1.0:
                if idle or (t_screen_hint is not None and now >= t_screen_hint + 3.0):
                    if not inject_keys or len(key_to_next_pty_byte_ms) >= n_key_samples:
                        break
            # Empty-cluster bail: Running appeared, we never asked for all-ns,
            # and no all-ns marker showed up. Do NOT fire this after sending `0`
            # — a 4k-pod cluster (dev4/rc) is still listing well past 22 s.
            if (
                not idle
                and not sent_all_ns
                and t_running is not None
                and t_screen_hint is None
                and now >= 22.0
            ):
                break
        last = sample("end")
    finally:
        child.cleanup_preserving(*sys.exc_info())

    telemetry = summarize_telemetry(
        telemetry_events,
        process_start_ns=child.process_start_ns,
        t_screen_hint_s=round(t_screen_hint, 3) if t_screen_hint is not None else None,
    )
    return {
        "name": name,
        "argv": argv,
        "t_first_running_s": round(t_running, 3) if t_running is not None else None,
        **telemetry,
        "telemetry_events": telemetry_events,
        "telemetry_parser": {
            "oversize_records": telemetry_parser.oversize_records,
            "malformed_records": telemetry_parser.malformed_records,
            "truncated_records": telemetry_parser.truncated_records,
        },
        "sent_all_ns_key": sent_all_ns,
        "pty_bytes": n_bytes,
        "sample_8s": sample_8s,
        "sample_screen_hint_plus_2s": sample_screen_hint,
        "sample_end": last,
        "key_to_next_pty_byte_ms": key_to_next_pty_byte_ms if inject_keys else None,
        "key_to_next_pty_byte_max_ms": round(max(key_to_next_pty_byte_ms), 1) if key_to_next_pty_byte_ms else None,
        "key_to_next_pty_byte_median_ms": round(median(key_to_next_pty_byte_ms), 1) if key_to_next_pty_byte_ms else None,
        # Settle limitation: (all)[ fires on title change (loading frame), not on
        # data arrival. Samples within key_settle_s of t_screen_hint may include the
        # initial all-ns LIST stall and are not steady-state; they are retained
        # rather than discarded so outliers remain visible.
        "key_to_next_pty_byte_settle_note": (
            "settle_based_on_title_marker_not_data_arrival; initial_LIST_outlier_possible"
            if inject_keys else None
        ),
    }


def host_info() -> dict[str, str]:
    return {
        "system": platform.system(),
        "release": platform.release(),
        "machine": platform.machine(),
        "python": sys.version.split()[0],
    }


def empty_report() -> dict[str, Any]:
    return {
        "protocol": PROTOCOL,
        "when": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "host": host_info(),
        "caveats": list(CAVEATS),
    }


def median_pty(runs: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not runs:
        return None

    def grab(key: str) -> list[float]:
        out: list[float] = []
        for r in runs:
            v = r.get(key)
            if isinstance(v, (int, float)):
                out.append(float(v))
        return out

    def grab_sample(sample_key: str, field: str) -> list[float]:
        out: list[float] = []
        for r in runs:
            s = r.get(sample_key) or {}
            v = s.get(field)
            if isinstance(v, (int, float)):
                out.append(float(v))
        return out

    def aggregate_counters() -> dict[str, int] | None:
        snapshots: list[dict[str, int]] = []
        for run in runs:
            counters = run.get("telemetry_counters")
            if isinstance(counters, dict) and all(
                _is_bounded_int(counters.get(field), U64_MAX) for field in TELEMETRY_COUNTER_FIELDS
            ):
                snapshots.append(counters)
        if len(snapshots) != len(runs):
            return None
        return {
            field: sum(snapshot[field] for snapshot in snapshots)
            for field in TELEMETRY_COUNTER_FIELDS
        }

    return {
        "n": len(runs),
        "t_first_running_s": median(grab("t_first_running_s")),
        "t_screen_hint_s": median(grab("t_screen_hint_s")),
        "t_first_usable_paint_s": median(grab("t_first_usable_paint_s")),
        "t_complete_sync_paint_s": median(grab("t_complete_sync_paint_s")),
        "authoritative_markers_ok": all(run.get("authoritative_markers_ok") is True for run in runs),
        "telemetry_counters": aggregate_counters(),
        "parent_rss_mb_t8s": median(grab_sample("sample_8s", "parent_rss_mb")),
        "tree_rss_mb_t8s": median(grab_sample("sample_8s", "tree_rss_mb")),
        "threads_t8s": median(grab_sample("sample_8s", "threads")),
        "pty_bytes_t8s": median(grab_sample("sample_8s", "pty_bytes")),
        "parent_rss_mb_screen_hint": median(grab_sample("sample_screen_hint_plus_2s", "parent_rss_mb")),
        "tree_rss_mb_screen_hint": median(grab_sample("sample_screen_hint_plus_2s", "tree_rss_mb")),
        "threads_screen_hint": median(grab_sample("sample_screen_hint_plus_2s", "threads")),
        "pty_bytes_screen_hint": median(grab_sample("sample_screen_hint_plus_2s", "pty_bytes")),
        "key_to_next_pty_byte_max_ms": median(grab("key_to_next_pty_byte_max_ms")),
        "key_to_next_pty_byte_median_ms": median(grab("key_to_next_pty_byte_median_ms")),
    }
