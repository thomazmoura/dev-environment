"""Asking another machine's radar about an ssh session, shared by every radar.

An ssh session (prefix+N, modules/tmux/scripts/New-SshSession.sh) is a local
tmux session whose panes are all ssh'd into one host. What its panes are doing
is partly on that host -- git-radar's repository, agent-radar's agent process --
so each radar asks the host's own copy of itself, over ssh, with a `--serve`
flag on its CLI. What is asked and what comes back belongs to each radar
(modules/git-radar/scripts/git_remote.py, agent-radar's agent_remote.py); this
module owns the generic half:

    remote_argv(target, script)   ssh to a host and run a script there
    RemotePoller(query, ...)      the daemon's way of asking: a thread per host,
                                  so a host that is slow to answer never holds
                                  up the local rows or the nudge latency

It lives beside radar_cache.py for the same reason that does: it belongs to
neither radar.

Every ssh here is BatchMode with no stdin: this runs from a daemon and from
curses panes, and neither has anywhere a password prompt could go.
"""

from __future__ import annotations

import os
import shlex
import threading
import time

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


def remote_argv(target: str, script: str) -> list[str]:
    """ssh to `target` and run `script` there under sh.

    Under sh -c rather than handed to the login shell, as remote_directory_matches
    in ssh-helpers.sh does, because the login shell may be anything.
    """
    return ["ssh", *SSH_OPTS, target, "sh -c " + shlex.quote(script)]


class _Host:
    """One host's poller thread and the last thing it heard."""

    def __init__(self, poller: "RemotePoller", target: str, request) -> None:
        self.poller = poller
        self.target = target
        self.lock = threading.Lock()
        self.request = request
        self.wanted = time.monotonic()
        self.answer = poller.connecting
        self.answered = 0.0
        self.fresh = False
        self.woken = threading.Event()
        self.thread = threading.Thread(target=self.run, daemon=True)

    def want(self, request) -> None:
        with self.lock:
            changed = request != self.request
            self.request = request
            self.wanted = time.monotonic()
        if changed:
            # Something new to ask this host -- a new ssh session on it: ask
            # now, not a tick on.
            self.woken.set()

    def wake(self, fresh: bool) -> None:
        with self.lock:
            self.fresh = self.fresh or fresh
        self.woken.set()

    def run(self) -> None:
        poller = self.poller
        while True:
            with self.lock:
                request = self.request
                fresh, self.fresh = self.fresh, False
                if time.monotonic() - self.wanted > poller.IDLE_TICKS * poller.interval:
                    return
            answer = poller.query(self.target, request, fresh)
            with self.lock:
                changed = answer != self.answer
                self.answer = answer
                self.answered = time.monotonic()
            if changed:
                # Published now rather than on the sampler's next tick: a
                # change on this host should not sit unseen for the rest of it.
                poller.updated.set()
            self.woken.wait(poller.interval)
            self.woken.clear()


class RemotePoller:
    """What a daemon hands its detector in place of a synchronous query.

    `query(target, request, fresh)` asks one host one question and returns its
    answer, or a phrase saying why there is none. lookup() never waits on it:
    it records what is wanted of a host and returns whatever that host's thread
    last heard -- `connecting` before the first answer, `unreachable` once the
    last one is older than `stale_after`. So a host that has gone away costs
    the local rows nothing.
    """

    # A host nobody has asked about for this many ticks -- its last ssh session
    # closed -- has its thread stop. Started again by the next lookup.
    IDLE_TICKS = 10

    def __init__(self, query, interval: float, stale_after: float,
                 connecting="connecting", unreachable="unreachable") -> None:
        self.query = query
        self.interval = interval
        self.stale_after = stale_after
        self.connecting = connecting
        self.unreachable = unreachable
        self.lock = threading.Lock()
        self.hosts: dict[str, _Host] = {}
        # Set when any host's answer changes, for the sampler to wait on
        # alongside its nudge flag (radar_cache.wait_for_tick's `also`).
        self.updated = threading.Event()

    def lookup(self, target: str, request=None):
        with self.lock:
            host = self.hosts.get(target)
            if host is None or not host.thread.is_alive():
                host = _Host(self, target, request)
                self.hosts[target] = host
                host.thread.start()
            else:
                host.want(request)
        with host.lock:
            answer, answered = host.answer, host.answered
        if answered and time.monotonic() - answered > self.stale_after:
            return self.unreachable
        return answer

    def wake(self) -> None:
        """Something has asked for a sample now: ask every host now, freshly."""
        with self.lock:
            hosts = list(self.hosts.values())
        for host in hosts:
            host.wake(fresh=True)
