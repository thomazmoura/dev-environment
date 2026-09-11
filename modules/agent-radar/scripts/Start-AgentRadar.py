#!/usr/bin/env python3
"""The single sampler behind every agent-radar consumer.

Reads every agent pane once per tick and publishes the result; the status bar
(prefix-less, always on), the picker on prefix + t then a, the fzf watcher on
prefix + t then A and the curses feed on prefix + t then r all read what it
publishes instead of detecting for themselves. See agent_feed.py for why that
matters -- the short version is that detection cost used to multiply by the
number of open consumers, and the working->idle debounce was silently broken by
having more than one.

Nobody starts this by hand. Any consumer that finds the lock free spawns it
(agent_feed.ensure_daemon), and it exits by itself when tmux is gone or nothing
has read from it for a while, so it does not outlive the thing it was watching.

The exception is notifications (agent_notify.py): while any notification action
is enabled, nobody reading is not a reason to stop. Detached is exactly when a
"your agent is waiting" message is worth sending, so the sampler then lives as
long as the tmux server does.

  Start-AgentRadar.py                 sample forever, once a second
  Start-AgentRadar.py --interval 0.5  faster ticks
  Start-AgentRadar.py --ensure        start one if none is running, then exit
"""

from __future__ import annotations

import argparse
import fcntl
import importlib.util
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import agent_feed as feed  # noqa: E402
import agent_notify  # noqa: E402

# render_status lives with the other presentation in Get-AgentState.py, whose
# name has a hyphen and so cannot be imported by name. Same load-by-path trick
# Watch-AgentFeed.py uses. The daemon renders the status string rather than
# leaving it to the status bar, so the hot path there stays a `cat`.
_spec = importlib.util.spec_from_file_location(
    "get_agent_state", os.path.join(HERE, "Get-AgentState.py")
)
state_cli = importlib.util.module_from_spec(_spec)
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
    feed.cache_dir().mkdir(parents=True, exist_ok=True)
    lock = os.open(feed.lock_path(), os.O_CREAT | os.O_RDWR, 0o644)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        # Another sampler got there first. Two consumers racing to spawn is
        # expected, so this is a normal exit, not an error.
        os.close(lock)
        return 0

    # The baseline for the idle exit: without it a sampler that no consumer ever
    # reads from would have no "last read" to age out of, and would run forever.
    feed.touch_heartbeat()

    # Adopt the flag rather than serving it: the touch that woke the *previous*
    # sampler is not this one's to answer, and the loop samples immediately.
    nudged = feed.nudge_stamp()

    # Constructed here, after the lock, so a sampler that lost the race never
    # reads the environment or starts worker threads.
    notifier = agent_notify.Notifier()

    while True:
        if not tmux_is_running():
            return 0
        if not notifier.active and feed.last_read_age() > feed.IDLE_EXIT_SECONDS:
            # Everyone detached. Leave the last snapshot on disk: it is stale by
            # definition and every reader checks the age, so it cannot be
            # mistaken for live data, and the next consumer respawns us.
            return 0

        started = time.monotonic()
        try:
            panes = feed.sample()
            feed.publish(panes, state_cli.render_status(panes))
            # After the publish, so the status bar never waits on a notifier.
            notifier.observe(panes)
        except Exception as error:  # noqa: BLE001
            # Fail open, like radar._run does: one bad tick -- tmux restarting
            # mid-capture, a rules file being edited -- must not take the
            # sampler down and leave every consumer falling back to live
            # detection forever.
            print(f"agent-radar: sample failed: {error!r}", file=sys.stderr, flush=True)

        # Sleep the remainder rather than a flat interval, so a slow sample on a
        # busy machine does not stretch the tick into two -- and cut even that
        # short if something has asked for a sample in the meantime.
        nudged = feed.CACHE.wait_for_tick(
            max(0.0, interval - (time.monotonic() - started)), nudged
        )


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
        feed.ensure_daemon(args.interval)
        return 0

    return run(args.interval)


if __name__ == "__main__":
    raise SystemExit(main())
