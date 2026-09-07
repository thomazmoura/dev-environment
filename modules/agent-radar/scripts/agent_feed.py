"""The shared sampling backend: one detector run per tick, however many readers.

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
reads the published snapshot. Reading is a file read, so a consumer costs the
same whether there is one of it or ten, and the debounce has a single writer
again.

    Start-AgentRadar.py    the sampler; the only caller of detect() in normal use
    publish()              what it writes, atomically
    read()/sample_cached() what every consumer calls instead of detecting

The daemon is nobody's responsibility to start: the first consumer that finds
the lock free spawns it (`ensure_daemon`), and it exits on its own once tmux is
gone or nothing has read from it in a while. A consumer whose read comes back
stale falls back to sampling live, so a dead or slow daemon degrades to the old
behaviour rather than showing an empty list.
"""

from __future__ import annotations

import fcntl
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import agent_radar as radar  # noqa: E402

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


def cache_dir() -> Path:
    root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return Path(root) / "agent-radar"


def state_path() -> Path:
    return cache_dir() / "state.json"


def status_path() -> Path:
    """The tmux status-bar string, published as plain text alongside the JSON.

    Its own file so `Get-AgentSummary.sh` stays a `cat` on the hot path. That
    script runs on every status refresh, of which there are far more than the
    status-interval timer suggests, and starting a Python interpreter there to
    pull one field out of the JSON would cost more than the sampling does.
    """
    return cache_dir() / "status.txt"


def lock_path() -> Path:
    return cache_dir() / "daemon.lock"


def heartbeat_path() -> Path:
    return cache_dir() / "heartbeat"


def log_path() -> Path:
    return cache_dir() / "daemon.log"


def debounce_path() -> Path:
    return cache_dir() / "debounce.json"


def daemon_script() -> Path:
    return HERE / "Start-AgentRadar.py"


@dataclass
class Snapshot:
    panes: list
    status: str
    generated: float

    @property
    def age(self) -> float:
        return max(0.0, time.time() - self.generated)


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
    _write_atomic(path, json.dumps(current))


def sample() -> list[radar.Pane]:
    """One live reading of the world, smoothed. The expensive path."""
    panes = radar.detect()
    debounce(panes)
    return panes


def _write_atomic(path: Path, text: str) -> None:
    """Temp-file-then-rename, so a reader never sees a half-written file.

    Two writers racing is harmless -- the loser's sample is simply lost -- which
    matters for the fallback paths, not the daemon: the daemon is a singleton.
    """
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix(f"{path.suffix}.{os.getpid()}.tmp")
        temp.write_text(text)
        temp.replace(path)
    except OSError:
        pass


def publish(panes: list[radar.Pane], status: str) -> None:
    """Write the snapshot every consumer reads. Called only by the daemon."""
    payload = {
        "generated": time.time(),
        "status": status,
        "panes": [{field: getattr(pane, field) for field in FIELDS} for pane in panes],
    }
    _write_atomic(state_path(), json.dumps(payload))
    _write_atomic(status_path(), status)


def touch_heartbeat() -> None:
    """Tell the daemon somebody is still reading, so it knows not to exit."""
    path = heartbeat_path()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.touch()
    except OSError:
        pass


def last_read_age() -> float:
    """How long since a consumer last read the snapshot.

    Missing counts as infinitely old, not as brand new. The daemon stamps this
    file once at startup precisely so that "missing" means something has removed
    it -- and a sampler whose cache directory has been wiped should exit and let
    the next consumer respawn it, not keep publishing into nowhere. Reading it as
    fresh would instead make the idle exit unreachable for a daemon nobody ever
    reads from.
    """
    try:
        return max(0.0, time.time() - heartbeat_path().stat().st_mtime)
    except OSError:
        return float("inf")


def read(max_age: float = STALE_AFTER) -> Snapshot | None:
    """The published snapshot, or None if there is not a usable one.

    The file's mtime is the clock, not the `generated` field inside it: both are
    written by the same machine, and mtime cannot disagree with the file it is
    attached to.
    """
    touch_heartbeat()
    path = state_path()
    try:
        generated = path.stat().st_mtime
        if time.time() - generated > max_age:
            return None
        payload = json.loads(path.read_text())
    except (OSError, ValueError):
        return None

    panes = []
    for entry in payload.get("panes", []):
        try:
            panes.append(radar.Pane(**{f: entry[f] for f in FIELDS}))
        except (KeyError, TypeError):
            # A snapshot written by an older version of this file. Treat the
            # whole thing as unusable rather than showing half a list.
            return None
    return Snapshot(panes, payload.get("status", ""), generated)


def daemon_running() -> bool:
    """Whether a sampler holds the lock.

    The lock *is* the liveness check: it is held for as long as the daemon's
    process exists and released by the kernel when it dies, however it dies. A
    pidfile would need a separate "is that pid still the daemon" test and would
    go stale on a crash.
    """
    try:
        fd = os.open(lock_path(), os.O_CREAT | os.O_RDWR, 0o644)
    except OSError:
        # Cannot tell; assume one is running rather than spawning blindly.
        return True
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return True
    else:
        fcntl.flock(fd, fcntl.LOCK_UN)
        return False
    finally:
        os.close(fd)


def ensure_daemon(interval: float = DEFAULT_INTERVAL) -> None:
    """Start the sampler if nothing is sampling. Safe to call on every tick.

    Two consumers can both find the lock free and both spawn; the loser exits
    the moment it fails to take the lock, so the race costs one wasted process
    start and cannot produce two samplers.
    """
    try:
        cache_dir().mkdir(parents=True, exist_ok=True)
    except OSError:
        return
    if daemon_running():
        return
    try:
        log = open(log_path(), "a")
    except OSError:
        log = subprocess.DEVNULL
    try:
        subprocess.Popen(
            [sys.executable, str(daemon_script()), "--interval", str(interval)],
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=log,
            # Its own session: the daemon must outlive the popup, pane or
            # status-bar shell that happened to notice it was missing.
            start_new_session=True,
        )
    except OSError:
        pass
    finally:
        if log is not subprocess.DEVNULL:
            log.close()


def sample_cached(interval: float = DEFAULT_INTERVAL) -> list[radar.Pane]:
    """What consumers call: the shared snapshot, or a live sample if there is none.

    The fallback is what makes the daemon an optimisation rather than a
    dependency -- every consumer still works, at the old cost, if it is not
    running yet or has just died.
    """
    ensure_daemon(interval)
    snapshot = read()
    if snapshot is not None:
        return snapshot.panes
    return sample()
