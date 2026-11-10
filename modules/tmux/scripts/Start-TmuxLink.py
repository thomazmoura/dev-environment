#!/usr/bin/env python3
"""The sampler behind linked tmux servers: asks each linked machine what it
holds and publishes the answers (see tmux_link.py).

One per machine, like the radars' samplers and on the same cache
(radar_cache.py): prefix+/ and prefix+? read what this publishes, so they open
without waiting on another machine. Started when the tmux config loads and by
any consumer that finds it missing.

It lives as long as there is something to ask and somebody to ask for: it exits
when the last link is removed or tmux is gone, and -- unlike the radars' -- not
for want of readers, since its readers are popups that are closed most of the
time and a cold start would be the wait this exists to avoid.

  Start-TmuxLink.py            sample forever, once every five seconds
  Start-TmuxLink.py --ensure   start one if none is running, then exit
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import tmux_link as link  # noqa: E402


def tmux_is_running() -> bool:
    try:
        result = subprocess.run(
            ["tmux", "list-sessions"], capture_output=True, text=True, check=False, timeout=5
        )
    except (OSError, subprocess.SubprocessError):
        return False
    return result.returncode == 0


def run(interval: float) -> int:
    lock = link.CACHE.take_lock()
    if lock is None:
        return 0

    nudged = link.CACHE.nudge_stamp()
    source = link.CACHE.source_baseline()
    poller = link.poller(interval)

    while True:
        if not link.read_peers() or not tmux_is_running():
            return 0
        if link.CACHE.source_changed(source):
            print("tmux-link: code changed, restarting", file=sys.stderr, flush=True)
            link.CACHE.restart_daemon(lock, interval)

        started = time.monotonic()
        try:
            machines = link.sample(poller.lookup)
            online = sum(1 for machine in machines[1:] if machine.online)
            link.CACHE.publish(machines, f"{online}/{len(machines) - 1}")
        except Exception as error:  # noqa: BLE001
            # Fail open, as the radars' samplers do: one bad tick must not
            # leave every picker sampling live.
            print(f"tmux-link: sample failed: {error!r}", file=sys.stderr, flush=True)

        stamp = link.CACHE.wait_for_tick(
            max(0.0, interval - (time.monotonic() - started)), nudged, poller.updated
        )
        if stamp != nudged:
            # A link was made or removed, or a session opened on a peer.
            poller.wake()
        nudged = stamp


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--interval", type=float, default=link.DEFAULT_INTERVAL)
    parser.add_argument("--ensure", action="store_true",
                        help="spawn a detached sampler if none is running, then exit")
    args = parser.parse_args()
    if args.interval <= 0:
        parser.error("--interval must be positive")
    if args.ensure:
        if link.read_peers():
            link.CACHE.ensure_daemon(args.interval)
        return 0
    return run(args.interval)


if __name__ == "__main__":
    raise SystemExit(main())
