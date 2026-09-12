"""Asks another machine's git-radar where an ssh session's repository stands.

An ssh session (prefix+N, modules/tmux/scripts/New-SshSession.sh) is a local
tmux session whose panes are all ssh'd into one host, so its repository is on
that host and nothing here can run `git status` on it. What can be done is to
ask the host's own git-radar, which is the same code as this one: `Get-GitState.py
--serve` on the remote takes directories on stdin, registers them with its
sampler so they stay in its snapshot, and prints their rows as JSON.

    query(target, paths)       one round trip, synchronous; the fallback path
    RemotePoller.lookup(...)   the daemon's way: a thread per host does the
                               asking, so a host that is slow to answer never
                               holds up the local rows or the nudge latency
    op_argv(target, root, ...) f / p / P on a remote row, as an ssh command line

Every ssh here is BatchMode with no stdin, for the reasons fetch_env in
Watch-GitFeed.py spells out: this runs from a daemon and from a curses pane,
and neither has anywhere a password prompt could go.
"""

from __future__ import annotations

import json
import os
import shlex
import subprocess
import threading
import time

import git_radar as gitr

# Mirrors SSH_OPTS in modules/tmux/scripts/ssh-helpers.sh, and has to: the
# ControlPath is how these calls find the master connection the session's
# panes already hold open, and a different spelling of it is a different
# socket.
#
# Except ControlMaster=no where the panes say auto. A client that becomes the
# master under ControlPersist forks a background process that keeps the pipe
# it was started with -- and subprocess.run waits for that pipe to close, so a
# query that happened to be first to a host would hang until the master
# expired ten minutes later. `no` still uses a master when there is one; when
# there is not, it connects on its own and leaves nothing behind.
SSH_OPTS = (
    "-o", "ControlMaster=no",
    "-o", f"ControlPath={os.path.expanduser('~')}/.ssh/tmux-%C",
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=5",
)

# The same prefix remote_agent_env in ssh-helpers.sh prints: the host's shared
# agent, when its socket is there, so a fetch on the remote finds the key the
# panes use. An `if` with no else succeeds when its test fails, so a host
# without the agent still runs the command.
REMOTE_AGENT_ENV = (
    'a="$HOME/.ssh/tmux-agent"; '
    'if [ -S "$a/agent.sock" ]; then '
    'export SSH_AUTH_SOCK="$a/agent.sock" SSH_AGENT_PID="$(cat "$a/agent.pid")"; '
    "fi && "
)

# Where the remote's git-radar is. $HOME is left for the remote shell.
SERVE = '"$HOME/.modules/git-radar/scripts/Get-GitState.py" --serve'
REMOTE_NUDGE = '"$HOME/.modules/tmux/scripts/Request-RadarSample.sh" git-radar'

# The reply's format. Bumped whenever what --serve prints changes shape, so an
# older remote says so on its rows instead of being misread.
PROTOCOL = 1

# Generous next to ConnectTimeout: over the master connection an answer takes
# a few tens of milliseconds, and a remote inspecting a directory for the first
# time walks its work tree.
QUERY_TIMEOUT = 10.0


def remote_argv(target: str, script: str) -> list[str]:
    """ssh to `target` and run `script` there under sh.

    Under sh -c rather than handed to the login shell, as remote_directory_matches
    in ssh-helpers.sh does, because the login shell may be anything.
    """
    return ["ssh", *SSH_OPTS, target, "sh -c " + shlex.quote(script)]


def query(target: str, paths: list[str], fresh: bool = False) -> dict | str:
    """One directory's-worth of rows per path, from the host's git-radar.

    {path: Repo} on success, otherwise the phrase an OFFLINE row carries. The
    paths go on stdin, one per line, so no directory name ever has to survive
    two rounds of shell quoting.

    `fresh` asks the remote to sample now rather than answer from its snapshot
    -- for right after a fetch, when the snapshot predates it.
    """
    script = SERVE + (" --fresh" if fresh else "")
    try:
        result = subprocess.run(
            remote_argv(target, script),
            input="".join(f"{path}\n" for path in paths),
            capture_output=True,
            text=True,
            check=False,
            timeout=QUERY_TIMEOUT,
            start_new_session=True,
        )
    except subprocess.TimeoutExpired:
        return gitr.UNREACHABLE
    except OSError:
        return gitr.UNREACHABLE

    if result.returncode == 255:
        # ssh's own failure: no route, no master and no key it may use.
        return gitr.UNREACHABLE
    if result.returncode in (126, 127):
        return gitr.NO_RADAR
    if result.returncode != 0:
        # argparse's 2 is a git-radar that predates --serve.
        return gitr.OUTDATED

    try:
        payload = json.loads(result.stdout)
        if payload.get("version") != PROTOCOL:
            return gitr.OUTDATED
        rows = {}
        for entry in payload["rows"]:
            repo = gitr.Repo(**{field: entry[field] for field in gitr.FIELDS})
            rows[repo.path] = repo
        return rows
    except (ValueError, KeyError, TypeError, AttributeError):
        return gitr.OUTDATED


def op_argv(target: str, root: str, git_args: list[str]) -> list[str]:
    """A fetch, pull or push run in `root` on `target`, as a local command line.

    On the remote it gets the same no-prompt environment fetch_env gives a local
    one, plus the host's shared agent. Afterwards the remote's own sampler is
    nudged, so its snapshot -- and any feed open on the remote itself -- moves
    with the refs; the local side asks with --fresh anyway (RemotePoller.wake).
    The exit status is git's.
    """
    git = " ".join(shlex.quote(arg) for arg in ["git", "-C", root, *git_args])
    script = (
        REMOTE_AGENT_ENV
        + "GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' "
        + f"SSH_ASKPASS_REQUIRE=never {git}; status=$?; "
        + f"{REMOTE_NUDGE} >/dev/null 2>&1; exit $status"
    )
    return remote_argv(target, script)


class _Host:
    """One host's poller thread and the last thing it heard."""

    def __init__(self, target: str, paths: list[str], interval: float,
                 updated: threading.Event) -> None:
        self.target = target
        self.updated = updated
        self.interval = interval
        self.lock = threading.Lock()
        self.paths = paths
        self.wanted = time.monotonic()
        self.answer: dict | str = gitr.CONNECTING
        self.answered = 0.0
        self.fresh = False
        self.woken = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)

    def want(self, paths: list[str]) -> None:
        with self.lock:
            changed = paths != self.paths
            self.paths = paths
            self.wanted = time.monotonic()
        if changed:
            # A new ssh session on this host: ask about it now, not a tick on.
            self.woken.set()

    def wake(self, fresh: bool) -> None:
        with self.lock:
            self.fresh = self.fresh or fresh
        self.woken.set()

    def run(self) -> None:
        while True:
            with self.lock:
                paths = list(self.paths)
                fresh, self.fresh = self.fresh, False
                if time.monotonic() - self.wanted > RemotePoller.IDLE_TICKS * self.interval:
                    return
            answer = query(self.target, paths, fresh)
            with self.lock:
                changed = answer != self.answer
                self.answer = answer
                self.answered = time.monotonic()
            if changed:
                # Published now rather than on the sampler's next tick: a
                # fetch you just made on this host should not sit unseen for
                # the rest of three seconds.
                self.updated.set()
            self.woken.wait(self.interval)
            self.woken.clear()


class RemotePoller:
    """What the daemon hands detect() in place of `query`.

    lookup() never waits on the network: it records which directories are
    wanted of a host and returns whatever that host's thread last heard. So a
    host that has gone away costs the local rows nothing -- they keep their
    three seconds, and a q in the feed keeps its tenth of one -- and its own
    rows turn OFFLINE once its last answer is older than `stale_after`.
    """

    # A host nobody has asked about for this many ticks -- its last ssh session
    # closed -- has its thread stop. Started again by the next lookup.
    IDLE_TICKS = 10

    def __init__(self, interval: float, stale_after: float) -> None:
        self.interval = interval
        self.stale_after = stale_after
        self.lock = threading.Lock()
        self.hosts: dict[str, _Host] = {}
        # Set when any host's answer changes, for the sampler to wait on
        # alongside its nudge flag (radar_cache.wait_for_tick's `also`).
        self.updated = threading.Event()

    def lookup(self, target: str, paths: list[str]) -> dict | str:
        with self.lock:
            host = self.hosts.get(target)
            if host is None or not host.thread.is_alive():
                host = _Host(target, paths, self.interval, self.updated)
                self.hosts[target] = host
                host.thread.start()
            else:
                host.want(paths)
        with host.lock:
            answer, answered = host.answer, host.answered
        if answered and time.monotonic() - answered > self.stale_after:
            return gitr.UNREACHABLE
        return answer

    def wake(self) -> None:
        """Something has asked for a sample now: ask every host now, freshly."""
        with self.lock:
            hosts = list(self.hosts.values())
        for host in hosts:
            host.wake(fresh=True)
