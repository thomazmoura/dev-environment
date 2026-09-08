"""git-radar's binding onto the shared radar cache.

All the machinery -- one sampler, many readers, atomic publish, flock liveness,
heartbeat idle-exit, stale-read fallback -- lives in
modules/tmux/scripts/radar_cache.py and is shared with agent-radar. This file is
only the three things that are specific to this radar: which Repo fields get
published, where the cache lives, and how fast it ticks.

There is no debounce here, unlike agent_feed.py. That exists because an agent
blinks through an idle-looking frame between tool calls; `git status` has no
such flicker, and smoothing it would only delay the answer.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import git_radar  # noqa: E402

sys.path.insert(0, str(git_radar.SHARED_SCRIPTS))

import radar_cache  # noqa: E402

HERE = Path(__file__).resolve().parent

# Three seconds, not agent-radar's one. A tick here is a `rev-parse` plus a
# `git status` per session, which walks the work tree; a tick there is a
# `capture-pane`, which does not. And the latency that matters is different: a
# blocked agent is waiting on you *now*, whereas a file you just saved can show
# up a moment later without anyone noticing.
DEFAULT_INTERVAL = 3.0

# Kept at the same 5x ratio to the tick that agent-radar uses. The point of the
# margin is that a daemon descheduled for a moment under load must not send
# every consumer off sampling in parallel -- which is the stampede the shared
# cache exists to prevent.
STALE_AFTER = 15.0

# Unchanged: this is about how long after the last reader goes away the sampler
# should linger, which has nothing to do with how expensive a tick is.
IDLE_EXIT_SECONDS = 90.0

FIELDS = git_radar.FIELDS


def _encode(repo: git_radar.Repo) -> dict:
    return {field: getattr(repo, field) for field in FIELDS}


def _decode(entry: dict) -> git_radar.Repo:
    return git_radar.Repo(**{field: entry[field] for field in FIELDS})


CACHE = radar_cache.RadarCache(
    "git-radar",
    HERE / "Start-GitRadar.py",
    _encode,
    _decode,
    interval=DEFAULT_INTERVAL,
    stale_after=STALE_AFTER,
    idle_exit=IDLE_EXIT_SECONDS,
)


def sample() -> list[git_radar.Repo]:
    """One live reading of every session. The expensive path."""
    return git_radar.detect()


def sample_cached(interval: float = DEFAULT_INTERVAL) -> list[git_radar.Repo]:
    """What consumers call: the shared snapshot, or a live sample if there is none."""
    return CACHE.sample_cached(sample, interval)
