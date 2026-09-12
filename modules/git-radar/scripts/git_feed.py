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

import hashlib
import os
import sys
import time
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

# How long a directory a remote client asked about stays in this machine's
# snapshot after the last time it asked. Ten ticks: a client polls every tick,
# so this only runs out once it has stopped -- its ssh session closed, or the
# machine it runs on went to sleep.
WATCH_TTL = 30.0

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


def sample(remote=None) -> list[git_radar.Repo]:
    """One live reading of every session, and of every watched directory.

    The expensive path. `remote` is how ssh sessions' hosts are asked -- see
    git_radar.detect; the daemon passes its git_remote.RemotePoller.
    """
    return git_radar.detect(remote, watched_paths())


def sample_cached(interval: float = DEFAULT_INTERVAL) -> list[git_radar.Repo]:
    """What consumers call: the shared snapshot, or a live sample if there is none.

    Session rows only. The snapshot also holds the directories remote clients
    have asked about (see `serve`), which are nobody's session here; this is
    the one place they are kept out of every list of sessions.
    """
    return [
        repo for repo in CACHE.sample_cached(sample, interval) if repo.session
    ]


# --- Serving remote clients ----------------------------------------------------
# A machine you ssh into is asked, by the git-radar of the machine you ssh from,
# where its ssh sessions' directories stand (git_remote.query). The answer comes
# from here: the asked-for directories are registered with this machine's
# sampler, which samples them on its tick alongside its own sessions -- tmux or
# no tmux -- and each question after the first is answered from its snapshot.


def watch_dir() -> Path:
    """One file per watched directory: its content is the path, its mtime the
    last time a client asked. A file per path rather than one list, so two
    clients asking at once never have to merge anything."""
    return CACHE.cache_dir() / "watched"


def watch(paths: list[str]) -> None:
    for path in paths:
        name = hashlib.sha1(path.encode()).hexdigest()
        radar_cache.write_atomic(watch_dir() / name, path)


def watched_paths() -> list[str]:
    """The directories clients have asked about within WATCH_TTL.

    Expired ones are removed on the way, so the list shrinks by itself once a
    client stops asking.
    """
    paths = []
    now = time.time()
    try:
        entries = list(watch_dir().iterdir())
    except OSError:
        return []
    for entry in entries:
        try:
            if now - entry.stat().st_mtime > WATCH_TTL:
                entry.unlink()
                continue
            path = entry.read_text()
        except OSError:
            continue
        if path:
            paths.append(path)
    return sorted(paths)


def serve(paths: list[str], fresh: bool = False) -> list[git_radar.Repo]:
    """One row per asked-for directory, for a remote client. What --serve prints.

    Answered from the snapshot where it can be. A directory not in it yet --
    the first question about it, before the sampler has had a tick -- is
    sampled right here instead, and the sampler asked to pick it up now, so a
    new ssh session shows its branch on its first round trip rather than on its
    second. `fresh` samples every one of them here: the client has just fetched,
    and the snapshot predates it.

    Rows come back with the path exactly as it was asked, which is what the
    client looks them up by.
    """
    watch(paths)
    CACHE.ensure_daemon()

    served: dict[str, git_radar.Repo] = {}
    if not fresh:
        snapshot = CACHE.read()
        if snapshot is not None:
            served = {repo.path: repo for repo in snapshot.rows if not repo.session}

    rows = []
    missing = False
    for path in paths:
        repo = served.get(path)
        if repo is None:
            repo = git_radar.inspect_path(path)
            missing = True
        rows.append(repo)
    if missing and not fresh:
        request_sample()
    return rows


def request_sample() -> None:
    """Ask the sampler to publish now rather than at the end of its three seconds.

    For what a consumer knows before any sample could -- it has just killed a
    session, or a fetch it started has moved the refs. A forced *read* cannot
    help: the published snapshot is exactly the thing that is out of date, so
    the force has to reach the sampler.
    """
    CACHE.request_sample()


def generation() -> float:
    """The mtime of the published snapshot -- a change means a new sample."""
    return CACHE.generation()
