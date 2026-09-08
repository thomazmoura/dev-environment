"""agent-radar's half of the shared sampling backend: what a row is, and the debounce.

Every consumer used to sample for itself -- the status bar, the picker, and each
watcher pane called `radar.detect()` on its own timer. Two things break as soon
as you leave more than one of them open:

  cost      detect() is one `ps -eo` plus a `capture-pane` per agent pane, so
            the work multiplies by the number of consumers, not by the number of
            agents. A feed pane open in every session is the case that motivated
            this file.

  debounce  worse, and silent. The working->idle smoothing is a read-modify-
            write over one cache file. Two pollers on different timers each read
            the *other's* sample as their own previous one, so the confirmation
            counter never accumulates and the smoothing stops working -- with no
            symptom except the flicker it was supposed to remove.

So: exactly one process samples, on one timer, and publishes. Everyone else
reads the published snapshot, so a consumer costs the same whether there is one
of it or ten, and the debounce has a single writer again.

    Start-AgentRadar.py    the sampler; the only caller of detect() in normal use
    publish()              what it writes, atomically
    read()/sample_cached() what every consumer calls instead of detecting

The machinery behind all of that -- the cache directory, the atomic publish, the
flock liveness check, the heartbeat and the staleness rules -- is generic and
lives in modules/tmux/scripts/radar_cache.py, shared with git-radar. What stays
here is what is specific to agents: which Pane fields get published (FIELDS) and
the working->idle debounce, which is stateful and therefore has to sit with the
single sampler. The module-level functions below are thin aliases onto the
shared cache so every existing caller reads the same as it always did.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import agent_radar as radar  # noqa: E402

sys.path.insert(0, str(radar.SHARED_SCRIPTS))

import radar_cache  # noqa: E402

HERE = Path(__file__).resolve().parent

# One second, because the point of the feed is noticing a blocked agent promptly
# and a second is roughly the floor of "did not notice a delay". It is now one
# cost for the whole machine rather than one per consumer, which is what makes
# a rate this high affordable at all.
DEFAULT_INTERVAL = 1.0

# How old a published snapshot may be before a reader stops trusting it and
# samples live. Generous relative to the tick: a daemon descheduled for a moment
# under load should not make every consumer start detecting in parallel, which
# is the exact stampede this file exists to prevent.
STALE_AFTER = 5.0

# The daemon exits when nothing has read from it for this long. tmux's status
# bar reads every few seconds whenever a client is attached, so in practice this
# fires only after the last client detaches -- and the next consumer respawns it.
IDLE_EXIT_SECONDS = 90.0

# Everything a consumer needs off a Pane. `snapshot` is deliberately absent: it
# is the whole screen text, several KB per agent, and it has already served its
# purpose by the time the state is decided.
FIELDS = (
    "pane_id",
    "session",
    "window",
    "label",
    "tty",
    "title",
    "current_command",
    "agent",
    "state",
    "detail",
    "rule_id",
)

# Agents blink through an idle-looking frame between tool calls, so a consumer
# polling once a second sees a working agent flicker to idle and back. Hold a
# working -> idle transition until it has been confirmed, which is where the
# smoothing belongs -- not in the UI, and not in the rules.
#
# Constants from herdr S3.6, which arrived at them the same way anyone will.
PENDING_IDLE_CONFIRMATIONS = 3
PENDING_IDLE_CAP_SECONDS = 0.7


def _encode(pane: radar.Pane) -> dict:
    return {field: getattr(pane, field) for field in FIELDS}


def _decode(entry: dict) -> radar.Pane:
    return radar.Pane(**{field: entry[field] for field in FIELDS})


CACHE = radar_cache.RadarCache(
    "agent-radar",
    HERE / "Start-AgentRadar.py",
    _encode,
    _decode,
    interval=DEFAULT_INTERVAL,
    stale_after=STALE_AFTER,
    idle_exit=IDLE_EXIT_SECONDS,
)

Snapshot = radar_cache.Snapshot


# --- Paths -------------------------------------------------------------------
# Kept as module-level functions so every caller here still reads naturally.


def cache_dir() -> Path:
    """The definition lives in agent_radar: the detector needs the same
    directory to find the hook markers, and it cannot import this module
    without a cycle."""
    return radar.cache_dir()


def state_path() -> Path:
    return CACHE.state_path()


def status_path() -> Path:
    return CACHE.status_path()


def lock_path() -> Path:
    return CACHE.lock_path()


def heartbeat_path() -> Path:
    return CACHE.heartbeat_path()


def log_path() -> Path:
    return CACHE.log_path()


def debounce_path() -> Path:
    return cache_dir() / "debounce.json"


def daemon_script() -> Path:
    return HERE / "Start-AgentRadar.py"


# --- Sampling ----------------------------------------------------------------


def debounce(panes: list[radar.Pane]) -> None:
    """Smooth working -> idle transitions, in place.

    Only that one transition is held. Positive evidence needs no confirmation:
    a matched blocked rule publishes immediately, because the entire point of
    the tool is to tell you about it now.

    This lives in the backend rather than in a consumer because it is stateful:
    it compares against the previous sample, so it is only correct when one
    process takes all the samples. The daemon is that process.
    """
    path = debounce_path()
    try:
        previous = json.loads(path.read_text())
    except (OSError, ValueError):
        previous = {}

    now = time.time()
    current = {}
    for pane in panes:
        entry = previous.get(pane.pane_id, {})
        published = entry.get("published")
        raw = pane.state

        if published == radar.WORKING and raw == radar.IDLE:
            count = entry.get("count", 0) + 1
            first = entry.get("first", now)
            if count >= PENDING_IDLE_CONFIRMATIONS or now - first >= PENDING_IDLE_CAP_SECONDS:
                published = raw
                count, first = 0, now
            else:
                # Keep reporting working, and keep the detail that came with it
                # so the row does not half-update.
                pane.state = radar.WORKING
                pane.detail = entry.get("detail", pane.detail)
        else:
            published = raw
            count, first = 0, now

        current[pane.pane_id] = {
            "published": published,
            "count": count,
            "first": first,
            "detail": pane.detail,
        }

    # Panes that vanished drop out of the file rather than accumulating.
    radar_cache.write_atomic(path, json.dumps(current))


def sample() -> list[radar.Pane]:
    """One live reading of the world, smoothed. The expensive path."""
    panes = radar.detect()
    debounce(panes)
    return panes


# --- The shared cache, under the names this module has always used ------------


def publish(panes: list[radar.Pane], status: str) -> None:
    """Write the snapshot every consumer reads. Called only by the daemon."""
    CACHE.publish(panes, status)


def touch_heartbeat() -> None:
    CACHE.touch_heartbeat()


def last_read_age() -> float:
    return CACHE.last_read_age()


def read(max_age: float = STALE_AFTER) -> Snapshot | None:
    return CACHE.read(max_age)


def daemon_running() -> bool:
    return CACHE.daemon_running()


def ensure_daemon(interval: float = DEFAULT_INTERVAL) -> None:
    CACHE.ensure_daemon(interval)


def sample_cached(interval: float = DEFAULT_INTERVAL) -> list[radar.Pane]:
    """What consumers call: the shared snapshot, or a live sample if there is none.

    The fallback is what makes the daemon an optimisation rather than a
    dependency -- every consumer still works, at the old cost, if it is not
    running yet or has just died.
    """
    return CACHE.sample_cached(sample, interval)
