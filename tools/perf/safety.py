"""Hard read-only rules for the c3s vs k9s PTY harness.

The harness must never become a way to mutate a cluster. TUI argv always
includes --readonly. The only byte the PTY may write is optional `0`
(k9s/c3s all-namespaces). kubectl is limited to get/describe/top/auth whoami.
"""

from __future__ import annotations

# Keys that delete, edit, scale, exec, drain, cordon, restart, or shell.
FORBIDDEN_TUI_BYTES = frozenset(
    {
        b"d",
        b"D",
        b"e",
        b"s",
        b"R",
        b"c",  # copy on most views; cordon on nodes
        b"u",  # uncordon on nodes
        b"t",  # trigger cronjob
        b"p",  # suspend
        b"x",  # shell in k9s
        b"\x04",  # ctrl-d delete
        b"\x0c",  # ctrl-l rollback
    }
)

# The only input this harness is allowed to inject.
# Navigation keys are read-only (move cursor/selection); they are safe on a
# --readonly binary and required for key-latency measurement.
NAV_KEYS = frozenset(
    {
        b"\x1b[A",  # up arrow
        b"\x1b[B",  # down arrow
        b"\x1b[5~",  # page up
        b"\x1b[6~",  # page down
    }
)
ALLOWED_TUI_INPUT = frozenset({b"0"}) | NAV_KEYS

FORBIDDEN_TUI_FLAGS = frozenset({"--write", "--force", "--dangerously-allow-write"})

KUBECTL_READ_VERBS = frozenset(
    {
        "get",
        "describe",
        "explain",
        "api-resources",
        "api-versions",
        "version",
        "cluster-info",
        "top",
        "auth",
        "config",
        "wait",
    }
)

KUBECTL_FORBIDDEN_VERBS = frozenset(
    {
        "apply",
        "create",
        "delete",
        "edit",
        "patch",
        "replace",
        "scale",
        "autoscale",
        "expose",
        "run",
        "exec",
        "attach",
        "cp",
        "port-forward",
        "proxy",
        "drain",
        "cordon",
        "uncordon",
        "taint",
        "label",
        "annotate",
        "rollout",
        "certificate",
        "debug",
        "kustomize",
        "set",
    }
)


class SafetyError(ValueError):
    pass


def assert_safe_tui_argv(argv: list[str]) -> None:
    if not argv:
        raise SafetyError("empty TUI argv")
    flags = {a for a in argv if a.startswith("-")}
    if "--readonly" not in argv:
        raise SafetyError("TUI argv must include --readonly")
    bad = flags & FORBIDDEN_TUI_FLAGS
    if bad:
        raise SafetyError(f"refusing mutating TUI flag {sorted(bad)}")
    if "--debug" in argv:
        raise SafetyError("refusing --debug (fixture path, not a cluster measurement)")


def assert_safe_tui_input(data: bytes) -> None:
    if data in ALLOWED_TUI_INPUT:
        return
    if data in FORBIDDEN_TUI_BYTES:
        raise SafetyError(f"refusing mutating TUI input {data!r}")
    raise SafetyError(f"refusing TUI input outside the whitelist {data!r}")


def kubectl_verb(argv: list[str]) -> str:
    if not argv or not argv[0].endswith("kubectl"):
        raise SafetyError(f"not kubectl: {argv[:1]!r}")
    i = 1
    while i < len(argv):
        a = argv[i]
        if a.startswith("-"):
            if a in {
                "--context",
                "--kubeconfig",
                "--namespace",
                "-n",
                "--request-timeout",
                "--cluster",
                "--user",
                "--token",
                "-o",
                "--output",
            } or a.startswith("--request-timeout="):
                if "=" not in a and a not in {"-A", "--all-namespaces", "--no-headers"}:
                    i += 2
                    continue
                i += 1
                continue
            if a in {"-A", "--all-namespaces", "--no-headers", "-R"}:
                i += 1
                continue
            i += 1
            continue
        return a
    raise SafetyError(f"kubectl argv has no verb: {argv!r}")


def assert_safe_kubectl_argv(argv: list[str]) -> None:
    verb = kubectl_verb(argv)
    if verb in KUBECTL_FORBIDDEN_VERBS:
        raise SafetyError(f"refusing mutating kubectl {verb}")
    if verb not in KUBECTL_READ_VERBS:
        raise SafetyError(f"refusing unlisted kubectl {verb}")
    if verb == "auth":
        idx = argv.index("auth")
        sub = next((a for a in argv[idx + 1 :] if not a.startswith("-")), None)
        if sub not in {"whoami", "can-i"}:
            raise SafetyError("kubectl auth is limited to whoami / can-i")
    if verb == "config":
        idx = argv.index("config")
        sub = next((a for a in argv[idx + 1 :] if not a.startswith("-")), None)
        if sub not in {"view", "current-context", "get-contexts"}:
            raise SafetyError("kubectl config is limited to view / current-context / get-contexts")


def tui_argv(
    binary: str,
    *,
    context: str | None,
    kubeconfig: str | None,
    k9s_pods_all: bool = False,
    extra_args: list[str] | None = None,
) -> list[str]:
    argv = [binary, "--readonly"]
    if context:
        argv += ["--context", context]
    if kubeconfig:
        argv += ["--kubeconfig", kubeconfig]
    if k9s_pods_all:
        argv += ["-A", "-c", "po"]
    if extra_args:
        argv += extra_args
    assert_safe_tui_argv(argv)
    return argv
