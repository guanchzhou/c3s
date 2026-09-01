#!/usr/bin/env python3
"""Unit tests for the read-only perf harness. No cluster or real TUI."""

from __future__ import annotations

import contextlib
import errno
import json
import os
import select
import sys
import time
import unittest
from unittest import mock
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import harness  # noqa: E402
from harness import homebrew_cellar, median, parse_version_fields, rss_mb, strip_ansi  # noqa: E402
from safety import (  # noqa: E402
    SafetyError,
    assert_safe_kubectl_argv,
    assert_safe_tui_argv,
    assert_safe_tui_input,
    kubectl_verb,
    tui_argv,
)


def telemetry_event(event: str = "sync_start", monotonic_ns: int = 1_000_000_000, **extra: object) -> dict:
    record = {
        "event": event,
        "monotonic_ns": monotonic_ns,
        "context": "dev4.as",
        "resource": "pods",
        "scope": "all_namespaces",
        "generation": 7,
        "subscription_id": 3,
        "applied_revision": 11,
        "object_count": 128,
        "queue_bytes": 4096,
    }
    record.update(extra)
    return record


def telemetry_line(**overrides: object) -> bytes:
    return (json.dumps(telemetry_event(**overrides), separators=(",", ":")) + "\n").encode()


def require_harness_attr(test: unittest.TestCase, name: str):
    value = getattr(harness, name, None)
    test.assertIsNotNone(value, f"harness telemetry support is missing: {name}")
    return value


def read_child_fd(pid: int, fd: int, *, timeout: float = 3.0) -> bytes:
    deadline = time.monotonic() + timeout
    data = bytearray()
    reaped = False
    try:
        while time.monotonic() < deadline:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                try:
                    chunk = os.read(fd, 4096)
                except OSError as exc:
                    if exc.errno in (errno.EAGAIN, errno.EIO):
                        chunk = b""
                    else:
                        raise
                if chunk:
                    data.extend(chunk)
                elif data:
                    break
            waited, _ = os.waitpid(pid, os.WNOHANG)
            if waited == pid:
                reaped = True
                if not ready:
                    break
        return bytes(data)
    finally:
        if not reaped:
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass


class SafetyTui(unittest.TestCase):
    def test_readonly_required(self) -> None:
        with self.assertRaises(SafetyError):
            assert_safe_tui_argv(["c3s", "--context", "x"])

    def test_write_refused(self) -> None:
        with self.assertRaises(SafetyError):
            assert_safe_tui_argv(["c3s", "--readonly", "--write"])

    def test_debug_refused(self) -> None:
        with self.assertRaises(SafetyError):
            assert_safe_tui_argv(["c3s", "--readonly", "--debug"])

    def test_builder_injects_readonly(self) -> None:
        argv = tui_argv("/bin/c3s", context="k8s-dev", kubeconfig=None)
        self.assertEqual(argv[:2], ["/bin/c3s", "--readonly"])
        self.assertIn("--context", argv)

    def test_k9s_pods_all(self) -> None:
        argv = tui_argv("/bin/k9s", context="x", kubeconfig="/tmp/kc", k9s_pods_all=True)
        self.assertIn("-A", argv)
        self.assertEqual(argv[argv.index("-c") + 1], "po")
        assert_safe_tui_argv(argv)

    def test_nav_keys_allowed_mutating_refused(self) -> None:
        # Zero and all four navigation keys must be allowed.
        assert_safe_tui_input(b"0")
        from safety import NAV_KEYS
        for nav in NAV_KEYS:
            assert_safe_tui_input(nav)  # must not raise
        # Mutating keys must be refused.
        for bad in (b"d", b"D", b"e", b"s", b"R", b"\x04", b"x", b"j"):
            with self.assertRaises(SafetyError):
                assert_safe_tui_input(bad)
        # Unlisted non-mutating chars are also refused.
        with self.assertRaises(SafetyError):
            assert_safe_tui_input(b"q")


class SafetyKubectl(unittest.TestCase):
    def test_get_ok(self) -> None:
        assert_safe_kubectl_argv(
            ["kubectl", "--context", "k8s-dev", "--request-timeout=20s", "get", "pods", "-A", "--no-headers"]
        )
        self.assertEqual(
            kubectl_verb(["kubectl", "--context", "x", "get", "nodes"]),
            "get",
        )

    def test_delete_refused(self) -> None:
        with self.assertRaises(SafetyError):
            assert_safe_kubectl_argv(["kubectl", "delete", "pod", "x"])

    def test_apply_refused(self) -> None:
        with self.assertRaises(SafetyError):
            assert_safe_kubectl_argv(["kubectl", "apply", "-f", "x.yaml"])

    def test_exec_refused(self) -> None:
        with self.assertRaises(SafetyError):
            assert_safe_kubectl_argv(["kubectl", "--context", "x", "exec", "-it", "po/x", "--", "sh"])

    def test_auth_whoami_ok(self) -> None:
        assert_safe_kubectl_argv(["kubectl", "--context", "x", "auth", "whoami"])

    def test_auth_unlisted_refused(self) -> None:
        with self.assertRaises(SafetyError):
            assert_safe_kubectl_argv(["kubectl", "auth", "reconcile", "-f", "x"])

    def test_drain_refused(self) -> None:
        with self.assertRaises(SafetyError):
            assert_safe_kubectl_argv(["kubectl", "drain", "node-1"])


class Metrics(unittest.TestCase):
    def test_rss_mb_matches_2026_08_31_unit(self) -> None:
        self.assertEqual(rss_mb(32384), 32.4)
        self.assertEqual(rss_mb(254928), 254.9)

    def test_median_odd_even(self) -> None:
        self.assertEqual(median([3.0, 1.0, 2.0]), 2.0)
        self.assertEqual(median([1.0, 2.0, 3.0, 4.0]), 2.5)
        self.assertIsNone(median([]))

    def test_strip_ansi(self) -> None:
        raw = b"\x1b[31mRunning\x1b[0m"
        self.assertIn(b"Running", strip_ansi(raw))
        self.assertNotIn(b"\x1b", strip_ansi(raw))

    def test_c3s_title_is_only_a_screen_hint(self) -> None:
        screen_hint_markers = require_harness_attr(self, "SCREEN_HINT_MARKERS")
        summarize = require_harness_attr(self, "summarize_telemetry")
        self.assertIn(b"pods(all)", screen_hint_markers)
        result = summarize([], process_start_ns=900_000_000, t_screen_hint_s=0.125)
        self.assertEqual(result["t_screen_hint_s"], 0.125)
        self.assertIsNone(result["t_first_usable_paint_s"])
        self.assertIsNone(result["t_complete_sync_paint_s"])
        self.assertFalse(result["authoritative_markers_ok"])
        report = harness.median_pty([result])
        self.assertEqual(report["t_screen_hint_s"], 0.125)
        self.assertFalse(report["authoritative_markers_ok"])
        self.assertIsNone(report["telemetry_counters"])
        self.assertNotIn("t_allns_s", report)


class TelemetryParser(unittest.TestCase):
    def test_authoritative_markers_come_only_from_telemetry_events(self) -> None:
        summarize = require_harness_attr(self, "summarize_telemetry")
        events = [
            telemetry_event("first_usable_paint", monotonic_ns=1_100_000_000),
            telemetry_event("complete_sync_paint", monotonic_ns=1_750_000_000),
        ]
        result = summarize(events, process_start_ns=1_000_000_000, t_screen_hint_s=0.01)
        self.assertEqual(result["t_first_usable_paint_s"], 0.1)
        self.assertEqual(result["t_complete_sync_paint_s"], 0.75)
        self.assertTrue(result["authoritative_markers_ok"])

    def test_partial_line_is_never_accepted(self) -> None:
        parser_type = require_harness_attr(self, "TelemetryStreamParser")
        parser = parser_type()
        line = telemetry_line()
        self.assertEqual(parser.feed(line[:-1]), [])
        self.assertEqual(parser.finish(), [])
        self.assertEqual(parser.truncated_records, 1)

    def test_parser_bounds_records_including_newline(self) -> None:
        parser_type = require_harness_attr(self, "TelemetryStreamParser")
        max_bytes = require_harness_attr(self, "MAX_TELEMETRY_RECORD_BYTES")
        parser = parser_type()
        base = telemetry_line(context="")
        exact_context = "x" * (max_bytes - len(base))
        accepted = telemetry_line(context=exact_context)
        self.assertEqual(len(accepted), max_bytes)
        self.assertEqual(parser.feed(accepted), [telemetry_event(context=exact_context)])

        oversized = telemetry_line(context=exact_context + "x")
        self.assertEqual(len(oversized), max_bytes + 1)
        self.assertEqual(parser.feed(oversized), [])
        self.assertEqual(parser.oversize_records, 1)

    def test_fragmented_oversize_record_does_not_grow_unbounded(self) -> None:
        parser_type = require_harness_attr(self, "TelemetryStreamParser")
        max_bytes = require_harness_attr(self, "MAX_TELEMETRY_RECORD_BYTES")
        parser = parser_type()
        self.assertEqual(parser.feed(b"{" + b"x" * max_bytes), [])
        self.assertLessEqual(parser.buffered_bytes, max_bytes)
        self.assertEqual(parser.feed(b"x" * max_bytes + b"}\n"), [])
        self.assertEqual(parser.oversize_records, 1)

    def test_summary_counters_are_reported(self) -> None:
        parser_type = require_harness_attr(self, "TelemetryStreamParser")
        summarize = require_harness_attr(self, "summarize_telemetry")
        parser = parser_type()
        events = parser.feed(
            telemetry_line(
                event="summary",
                dropped_oversize=2,
                dropped_eagain=3,
                write_faults=1,
            )
        )
        result = summarize(events, process_start_ns=0, t_screen_hint_s=None)
        self.assertEqual(
            result["telemetry_counters"],
            {"dropped_oversize": 2, "dropped_eagain": 3, "write_faults": 1},
        )

    def test_median_pty_aggregates_only_bounded_counters(self) -> None:
        runs = [
            {
                "telemetry_counters": {
                    "dropped_oversize": 2,
                    "dropped_eagain": 3,
                    "write_faults": 1,
                }
            },
            {
                "telemetry_counters": {
                    "dropped_oversize": 5,
                    "dropped_eagain": 7,
                    "write_faults": 11,
                }
            },
        ]
        aggregated = harness.median_pty(runs)
        self.assertEqual(
            aggregated["telemetry_counters"],
            {"dropped_oversize": 7, "dropped_eagain": 10, "write_faults": 12},
        )

        oversized = [dict(runs[0])]
        oversized[0]["telemetry_counters"] = dict(runs[0]["telemetry_counters"])
        oversized[0]["telemetry_counters"]["dropped_eagain"] = harness.U64_MAX + 1
        self.assertIsNone(harness.median_pty(oversized)["telemetry_counters"])

    def test_integer_fields_match_zig_widths(self) -> None:
        integer_max = require_harness_attr(self, "TELEMETRY_INTEGER_MAX")
        u32_max = require_harness_attr(self, "U32_MAX")
        u64_max = require_harness_attr(self, "U64_MAX")
        usize_max = require_harness_attr(self, "TELEMETRY_USIZE_MAX")
        self.assertEqual(
            integer_max,
            {
                "monotonic_ns": u64_max,
                "generation": u64_max,
                "subscription_id": u32_max,
                "applied_revision": u64_max,
                "object_count": usize_max,
                "queue_bytes": usize_max,
            },
        )
        for field, maximum in integer_max.items():
            at_limit = telemetry_event(**{field: maximum})
            self.assertTrue(harness._valid_telemetry_record(at_limit), field)
            self.assertFalse(harness._valid_telemetry_record(telemetry_event(**{field: maximum + 1})), field)
            self.assertFalse(harness._valid_telemetry_record(telemetry_event(**{field: -1})), field)
            self.assertFalse(harness._valid_telemetry_record(telemetry_event(**{field: True})), field)

        summary = telemetry_event(
            event="summary",
            dropped_oversize=u64_max,
            dropped_eagain=u64_max,
            write_faults=u64_max,
        )
        self.assertTrue(harness._valid_telemetry_record(summary))
        for field in harness.TELEMETRY_COUNTER_FIELDS:
            oversized = dict(summary)
            oversized[field] = u64_max + 1
            self.assertFalse(harness._valid_telemetry_record(oversized), field)

    def test_oversized_integer_marker_is_rejected_before_summarizing(self) -> None:
        u64_max = require_harness_attr(self, "U64_MAX")
        parser_type = require_harness_attr(self, "TelemetryStreamParser")
        parser = parser_type()
        events = parser.feed(
            telemetry_line(event="first_usable_paint", generation=u64_max + 1)
            + telemetry_line(event="complete_sync_paint", monotonic_ns=1_500_000_000)
        )
        self.assertEqual([event["event"] for event in events], ["complete_sync_paint"])
        self.assertEqual(parser.malformed_records, 1)
        result = harness.summarize_telemetry(events, process_start_ns=1_000_000_000, t_screen_hint_s=0.01)
        self.assertIsNone(result["t_first_usable_paint_s"])
        self.assertFalse(result["authoritative_markers_ok"])

    def test_huge_integer_cannot_overflow_or_satisfy_markers(self) -> None:
        huge = int("9" * 300)
        invalid = telemetry_event("first_usable_paint", monotonic_ns=huge)
        self.assertFalse(harness._valid_telemetry_record(invalid))
        result = harness.summarize_telemetry(
            [invalid, telemetry_event("complete_sync_paint", monotonic_ns=1_500_000_000)],
            process_start_ns=1_000_000_000,
            t_screen_hint_s=0.01,
        )
        self.assertIsNone(result["t_first_usable_paint_s"])
        self.assertFalse(result["authoritative_markers_ok"])


class TelemetryFork(unittest.TestCase):
    def test_pipe_configuration_failure_closes_both_descriptors(self) -> None:
        real_pipe = os.pipe
        real_set_blocking = os.set_blocking
        opened: list[int] = []
        blocking_calls = 0

        def tracked_pipe() -> tuple[int, int]:
            pair = real_pipe()
            opened.extend(pair)
            return pair

        def fail_second_set_blocking(fd: int, blocking: bool) -> None:
            nonlocal blocking_calls
            blocking_calls += 1
            if blocking_calls == 2:
                raise OSError("configuration failed")
            real_set_blocking(fd, blocking)

        try:
            with (
                mock.patch.object(harness.os, "pipe", side_effect=tracked_pipe),
                mock.patch.object(harness.os, "set_blocking", side_effect=fail_second_set_blocking),
            ):
                with self.assertRaisesRegex(OSError, "configuration failed"):
                    harness._fork_exec_pty(["/usr/bin/true"], os.environ.copy(), c3s_telemetry=True)
            self.assertEqual(len(opened), 2)
            for fd in opened:
                with self.assertRaises(OSError):
                    os.fstat(fd)
        finally:
            for fd in opened:
                with contextlib.suppress(OSError):
                    os.close(fd)

    def test_post_fork_setup_failure_reaps_child_and_closes_descriptors(self) -> None:
        real_fork_exec = harness._fork_exec_pty
        children = []

        def capture_child(*args, **kwargs):
            child = real_fork_exec(*args, **kwargs)
            children.append(child)
            return child

        argv = [
            sys.executable,
            "-c",
            "import time; time.sleep(30)",
            "--readonly",
            "--context",
            "dev4.as",
        ]
        try:
            with (
                mock.patch.object(harness, "_fork_exec_pty", side_effect=capture_child),
                mock.patch.object(harness.fcntl, "fcntl", side_effect=OSError("post-fork setup failed")),
            ):
                with self.assertRaisesRegex(OSError, "post-fork setup failed"):
                    harness.pty_run(
                        "c3s-test",
                        argv,
                        kubeconfig=None,
                        send_all_ns=False,
                        max_s=0.1,
                        c3s_telemetry=True,
                    )
            self.assertEqual(len(children), 1)
            child = children[0]
            for fd in (child.master_fd, child.telemetry_read_fd):
                if fd is not None:
                    with self.assertRaises(OSError):
                        os.fstat(fd)
            with self.assertRaises(ChildProcessError):
                os.waitpid(child.pid, os.WNOHANG)
        finally:
            for child in children:
                with contextlib.suppress(OSError):
                    os.close(child.master_fd)
                if child.telemetry_read_fd is not None:
                    with contextlib.suppress(OSError):
                        os.close(child.telemetry_read_fd)
                harness.kill_tree(child.pid)

    def test_parser_construction_failure_is_guarded_immediately_after_fork(self) -> None:
        real_fork_exec = harness._fork_exec_pty
        children = []

        def capture_child(*args, **kwargs):
            child = real_fork_exec(*args, **kwargs)
            children.append((child, child.master_fd, child.telemetry_read_fd))
            return child

        argv = [
            sys.executable,
            "-c",
            "import time; time.sleep(30)",
            "--readonly",
            "--context",
            "dev4.as",
        ]
        try:
            with (
                mock.patch.object(harness, "_fork_exec_pty", side_effect=capture_child),
                mock.patch.object(harness, "TelemetryStreamParser", side_effect=RuntimeError("parser construction failed")),
            ):
                with self.assertRaisesRegex(RuntimeError, "parser construction failed"):
                    harness.pty_run(
                        "c3s-test",
                        argv,
                        kubeconfig=None,
                        send_all_ns=False,
                        max_s=0.1,
                        c3s_telemetry=True,
                    )
            self.assertEqual(len(children), 1)
            child, master_fd, telemetry_read_fd = children[0]
            for fd in (master_fd, telemetry_read_fd):
                if fd is not None:
                    with self.assertRaises(OSError):
                        os.fstat(fd)
            with self.assertRaises(ChildProcessError):
                os.waitpid(child.pid, os.WNOHANG)
        finally:
            for child, master_fd, telemetry_read_fd in children:
                with contextlib.suppress(OSError):
                    os.close(master_fd)
                if telemetry_read_fd is not None:
                    with contextlib.suppress(OSError):
                        os.close(telemetry_read_fd)
                harness.kill_tree(child.pid)

    def test_body_failure_wins_over_drain_close_and_reap_failures(self) -> None:
        class BodyFailure(BaseException):
            pass

        class CleanupFailure(RuntimeError):
            pass

        real_fork_exec = harness._fork_exec_pty
        real_close = os.close
        real_kill_tree = harness.kill_tree
        children = []
        owned_fds: set[int] = set()
        close_attempts: list[int] = []
        reap_attempts: list[int] = []

        def capture_child(*args, **kwargs):
            child = real_fork_exec(*args, **kwargs)
            children.append((child, child.master_fd, child.telemetry_read_fd))
            owned_fds.add(child.master_fd)
            if child.telemetry_read_fd is not None:
                owned_fds.add(child.telemetry_read_fd)
            return child

        def fail_owned_close(fd: int) -> None:
            if fd in owned_fds:
                close_attempts.append(fd)
                raise CleanupFailure(f"close cleanup failed for {fd}")
            real_close(fd)

        def fail_owned_reap(pid: int) -> None:
            if children and pid == children[0][0].pid:
                reap_attempts.append(pid)
                raise CleanupFailure("reap cleanup failed")
            real_kill_tree(pid)

        argv = [
            sys.executable,
            "-c",
            "import time; time.sleep(30)",
            "--readonly",
            "--context",
            "dev4.as",
        ]
        try:
            with (
                mock.patch.object(harness, "_fork_exec_pty", side_effect=capture_child),
                mock.patch.object(harness.select, "select", side_effect=BodyFailure("body failed")),
                mock.patch.object(harness.os, "read", side_effect=CleanupFailure("drain cleanup failed")),
                mock.patch.object(harness.os, "close", side_effect=fail_owned_close),
                mock.patch.object(harness, "kill_tree", side_effect=fail_owned_reap),
            ):
                with self.assertRaisesRegex(BodyFailure, "body failed"):
                    harness.pty_run(
                        "c3s-test",
                        argv,
                        kubeconfig=None,
                        send_all_ns=False,
                        max_s=0.1,
                        c3s_telemetry=True,
                    )
            self.assertEqual(len(close_attempts), len(owned_fds))
            self.assertCountEqual(close_attempts, owned_fds)
            self.assertEqual(reap_attempts, [children[0][0].pid])
        finally:
            for child, master_fd, telemetry_read_fd in children:
                with contextlib.suppress(OSError):
                    real_close(master_fd)
                if telemetry_read_fd is not None:
                    with contextlib.suppress(OSError):
                        real_close(telemetry_read_fd)
                real_kill_tree(child.pid)

    def test_successful_pty_body_still_closes_and_reaps(self) -> None:
        real_fork_exec = harness._fork_exec_pty
        children = []

        def capture_child(*args, **kwargs):
            child = real_fork_exec(*args, **kwargs)
            children.append((child, child.master_fd, child.telemetry_read_fd))
            return child

        argv = [
            sys.executable,
            "-c",
            "print('done', flush=True)",
            "--readonly",
            "--context",
            "dev4.as",
        ]
        with mock.patch.object(harness, "_fork_exec_pty", side_effect=capture_child):
            result = harness.pty_run(
                "c3s-test",
                argv,
                kubeconfig=None,
                send_all_ns=False,
                sample_s=0,
                max_s=0.2,
                idle=True,
                c3s_telemetry=True,
            )
        self.assertEqual(result["name"], "c3s-test")
        self.assertEqual(len(children), 1)
        child, master_fd, telemetry_read_fd = children[0]
        for fd in (master_fd, telemetry_read_fd):
            if fd is not None:
                with self.assertRaises(OSError):
                    os.fstat(fd)
        with self.assertRaises(ChildProcessError):
            os.waitpid(child.pid, os.WNOHANG)

    def test_only_nonblocking_writer_survives_c3s_exec(self) -> None:
        fork_exec = require_harness_attr(self, "_fork_exec_pty")
        code = (
            "import fcntl,json,os,stat;"
            "fd=int(os.environ['C3S_PERF_FD']);"
            "pipe_fds=[];"
            "\nfor candidate in range(3,64):\n"
            " try:\n"
            "  fcntl.fcntl(candidate,fcntl.F_GETFD)\n"
            "  if stat.S_ISFIFO(os.fstat(candidate).st_mode): pipe_fds.append(candidate)\n"
            " except OSError: pass\n"
            f"record={telemetry_event()!r};"
            "record.update(perf_fd=fd,pipe_fds=pipe_fds,writer_nonblocking=not os.get_blocking(fd),"
            "writer_inheritable=os.get_inheritable(fd));"
            "os.write(fd,(json.dumps(record,separators=(',',':'))+'\\n').encode())"
        )
        child = fork_exec([sys.executable, "-c", code], os.environ.copy(), c3s_telemetry=True)
        try:
            self.assertIsNotNone(child.telemetry_read_fd)
            self.assertFalse(os.get_blocking(child.telemetry_read_fd))
            raw = read_child_fd(child.pid, child.telemetry_read_fd)
            self.assertEqual(os.read(child.telemetry_read_fd, 1), b"")
            parser_type = require_harness_attr(self, "TelemetryStreamParser")
            events = parser_type().feed(raw)
            self.assertEqual(len(events), 1)
            event = events[0]
            self.assertEqual(event["pipe_fds"], [event["perf_fd"]])
            self.assertTrue(event["writer_nonblocking"])
            self.assertTrue(event["writer_inheritable"])
        finally:
            os.close(child.master_fd)
            if child.telemetry_read_fd is not None:
                os.close(child.telemetry_read_fd)

    def test_k9s_child_never_receives_c3s_perf_fd(self) -> None:
        fork_exec = require_harness_attr(self, "_fork_exec_pty")
        env = os.environ.copy()
        env["C3S_PERF_FD"] = "12345"
        code = "import os; print(os.environ.get('C3S_PERF_FD', 'absent'), flush=True)"
        child = fork_exec([sys.executable, "-c", code], env, c3s_telemetry=False)
        try:
            self.assertIsNone(child.telemetry_read_fd)
            output = read_child_fd(child.pid, child.master_fd)
            self.assertIn(b"absent", output)
            self.assertNotIn(b"12345", output)
        finally:
            os.close(child.master_fd)


class LiveContextSafety(unittest.TestCase):
    def test_exact_live_context_allowlist(self) -> None:
        assert_live_context = require_harness_attr(self, "assert_live_context")
        for context in ("dev4.as", "rc.alpha-sense.org"):
            assert_live_context(context)

    def test_other_and_admin_contexts_are_rejected(self) -> None:
        assert_live_context = require_harness_attr(self, "assert_live_context")
        for context in (
            "k8s-dev",
            "dev4.as-admin",
            "dev4.as/admin",
            "admin@dev4.as",
            "rc.alpha-sense.org-admin",
        ):
            with self.subTest(context=context), self.assertRaises(SafetyError):
                assert_live_context(context)

    def test_probe_rejects_context_before_kubectl(self) -> None:
        require_harness_attr(self, "assert_live_context")
        with mock.patch.object(harness, "run_kubectl") as run_kubectl:
            with self.assertRaises(SafetyError):
                harness.probe_cluster("other.example", None)
            run_kubectl.assert_not_called()

    def test_pty_rejects_context_before_spawn(self) -> None:
        require_harness_attr(self, "assert_live_context")
        with mock.patch.object(harness, "_fork_exec_pty") as fork_exec:
            with self.assertRaises(SafetyError):
                harness.pty_run(
                    "c3s",
                    ["/bin/c3s", "--readonly", "--context", "dev4.as-admin"],
                    kubeconfig=None,
                    send_all_ns=False,
                    max_s=0.1,
                    c3s_telemetry=True,
                )
            fork_exec.assert_not_called()


class Identity(unittest.TestCase):
    def test_parse_c3s_version(self) -> None:
        text = "Version:    v0.2026.08.31.11.43+2\nCommit:     n/a\n"
        fields = parse_version_fields(text)
        self.assertEqual(fields["version"], "v0.2026.08.31.11.43+2")
        self.assertIsNone(fields["commit"])
        self.assertIsNone(fields["date"])

    def test_parse_k9s_version(self) -> None:
        text = (
            "Version:    0.51.0\n"
            "Commit:     558caafe7ba067467de46b320cc22ef11fef9c34\n"
            "Date:       n/a\n"
        )
        fields = parse_version_fields(text)
        self.assertEqual(fields["version"], "0.51.0")
        self.assertEqual(fields["commit"], "558caafe7ba067467de46b320cc22ef11fef9c34")
        self.assertIsNone(fields["date"])

    def test_homebrew_cellar(self) -> None:
        hb = homebrew_cellar("/opt/homebrew/Cellar/k9s/0.51.0/bin/k9s")
        self.assertEqual(hb["formula"], "k9s")
        self.assertEqual(hb["version"], "0.51.0")
        self.assertIsNone(homebrew_cellar("/usr/local/bin/k9s"))


if __name__ == "__main__":
    unittest.main()
