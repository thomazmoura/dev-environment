#!/usr/bin/env python3
"""The single sampler behind every git-radar consumer.

Runs one `git status` per session per tick and publishes the result; the feed on
prefix + t then R reads what it publishes instead of sampling for itself. See
modules/tmux/scripts/radar_cache.py for why that matters -- the short version is
that sampling cost otherwise multiplies by the number of open consumers rather
than by the number of repositories.

Nobody starts this by hand. Any consumer that finds the lock free spawns it
(radar_cache.ensure_daemon), and it exits by itself when tmux is gone or nothing
has read from it for a while, so it does not outlive the thing it was watching.

It has a second job on a machine you ssh into: the git-radar on the machine you
ssh from asks it about its ssh sessions' directories (git_feed.serve), and it
samples those alongside its own sessions. That job needs no tmux here, so it
keeps the sampler up for as long as somebody is asking.

  Start-GitRadar.py                 sample forever, once every three seconds
  Start-GitRadar.py --interval 10   slower ticks, for a machine with many repos
  Start-GitRadar.py --ensure        start one if none is running, then exit
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import git_feed as feed  # noqa: E402
import git_remote  # noqa: E402

# render_status lives with the other presentation in Get-GitState.py, whose name
# has a hyphen and so cannot be imported by name -- the same load-by-path trick
# Start-AgentRadar.py uses. The daemon renders the summary string rather than
# leaving it to its readers, so that publishing a status-bar segment later stays
# a `cat` on the hot path.
_spec = importlib.util.spec_from_file_location(
    "get_git_state", os.path.join(HERE, "Get-GitState.py")
)
state_cli = importlib.util.module_from_spec(_spec)
# Registered before it is executed, not after: @dataclass resolves a class's
# annotations through sys.modules[cls.__module__], so a module holding one
# cannot be exec'd while it is still invisible there. (Get-AgentState.py has no
# dataclass, which is the only reason its loader gets away without this.)
sys.modules[_spec.name] = state_cli
_spec.loader.exec_module(state_cli)


def tmux_is_running() -> bool:
    try:
        result = subprocess.run(
            ["tmux", "list-sessions"],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


def run(interval: float) -> int:
    """Sample until tmux goes away or the readers do.

    The lock is held open for the whole loop and never explicitly released: the
    kernel drops it when this process ends, by any route, which is what makes
    `daemon_running()` a truthful liveness check even after a crash.
    """
    lock = feed.CACHE.take_lock()
    if lock is None:
        # Another sampler got there first. Two consumers racing to spawn is
        # expected, so this is a normal exit, not an error.
        return 0

    # The baseline for the idle exit: without it a sampler that no consumer ever
    # reads from would have no "last read" to age out of, and would run forever.
    feed.CACHE.touch_heartbeat()

    # Adopt the flag rather than serving it: the touch that woke the *previous*
    # sampler is not this one's to answer, and the loop samples immediately.
    nudged = feed.CACHE.nudge_stamp()

    # The ssh sessions' hosts are asked from threads of their own, so a host
    # that is slow to answer never holds up this loop -- see git_remote.
    poller = git_remote.RemotePoller(interval, feed.STALE_AFTER)

    while True:
        # No tmux is only a reason to stop when no remote client is asking
        # either: a machine you ssh into has no tmux of its own, usually.
        if not tmux_is_running() and not feed.watched_paths():
            return 0
        if feed.CACHE.last_read_age() > feed.IDLE_EXIT_SECONDS:
            # Everyone detached. Leave the last snapshot on disk: it is stale by
            # definition and every reader checks the age, so it cannot be
            # mistaken for live data, and the next consumer respawns us.
            return 0

        started = time.monotonic()
        try:
            repos = feed.sample(poller.lookup)
            # The summary is of this machine's sessions, not of the
            # directories it is only serving.
            sessions = [repo for repo in repos if repo.session]
            feed.CACHE.publish(repos, state_cli.render_status(sessions))
        except Exception as error:  # noqa: BLE001
            # Fail open, like the agent sampler does: one bad tick -- a
            # repository deleted mid-walk, a `git gc` holding a lock -- must not
            # take the sampler down and leave every consumer sampling live
            # forever.
            print(f"git-radar: sample failed: {error!r}", file=sys.stderr, flush=True)

        # Sleep the remainder rather than a flat interval, so a slow sample on a
        # machine full of large repositories does not stretch the tick into two
        # -- and cut even that short if something has asked for a sample in the
        # meantime, a session killed from the feed pane being the usual reason.
        stamp = feed.CACHE.wait_for_tick(
            max(0.0, interval - (time.monotonic() - started)), nudged, poller.updated
        )
        if stamp != nudged:
            # Asked for a sample now -- a fetch has just moved some refs, or a
            # session closed. The remote rows have to hear it too, and their
            # hosts' snapshots may predate it, so they are asked freshly.
            poller.wake()
        nudged = stamp


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interval", type=float, default=feed.DEFAULT_INTERVAL)
    parser.add_argument(
        "--ensure",
        action="store_true",
        help="spawn a detached sampler if none is running, then exit",
    )
    args = parser.parse_args()

    if args.interval <= 0:
        parser.error("--interval must be positive")

    if args.ensure:
        feed.CACHE.ensure_daemon(args.interval)
        return 0

    return run(args.interval)


if __name__ == "__main__":
    raise SystemExit(main())
