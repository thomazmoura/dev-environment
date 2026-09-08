"""The one-sampler-many-readers cache, shared by every radar.

A "radar" here is any tool that answers a question about the whole machine by
sampling something expensive -- agent-radar reads every agent's screen,
git-radar runs `git status` in every session's directory -- and then shows the
answer in several places at once: a status-bar segment, a picker, a watcher pane
per session.

Sampling once per consumer does not work, for two reasons that agent-radar found
the hard way (see modules/agent-radar/scripts/agent_feed.py):

  cost      the work multiplies by the number of consumers rather than by the
            number of things being watched. A feed pane open in every session is
            the case that motivates this file.

  state     any smoothing across samples (agent-radar's working->idle debounce)
            is a read-modify-write against the previous sample, so it is only
            correct when one process takes all the samples.

So: exactly one process samples, on one timer, and publishes; everyone else
reads the published snapshot, which costs a file read however many readers there
are. Nobody starts the sampler by hand -- the first consumer that finds the lock
free spawns it (`ensure_daemon`), and it exits on its own once nothing has read
from it for a while. A read that comes back stale falls back to sampling live,
which is what makes the daemon an optimisation rather than a dependency.

This module owns only the generic half of that: the cache directory, the atomic
publish, the flock liveness check, the heartbeat and the staleness rules. What a
row *is*, how it is sampled and any cross-sample smoothing stay with each radar.

    RadarCache("git-radar", daemon, encode, decode)   bind a radar to a cache
    cache.publish(rows, status)                        what the daemon writes
    cache.read() / cache.sample_cached(sample)         what consumers call

It lives under modules/tmux/scripts rather than inside either radar because it
belongs to neither. Both radars are tmux consumers and both already reach into
this directory (Select-Agent.sh sources tmux-helpers.sh from here), so the
relative path holds in Docker and on the host alike.
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

# Defaults are agent-radar's, because it is the radar these numbers were tuned
# against. A radar whose sample costs more passes its own -- see git_feed.py,
# where a `git status` per session buys a slower tick and a looser staleness
# bound in the same ratio.
DEFAULT_INTERVAL = 1.0
DEFAULT_STALE_AFTER = 5.0
DEFAULT_IDLE_EXIT_SECONDS = 90.0


def cache_root(name: str) -> Path:
    """Where a radar's runtime state lives: $XDG_CACHE_HOME/<name>.

    A free function as well as a method, because a detector may need the
    directory (agent-radar keeps its hook markers there) without being able to
    import the cache -- the cache imports the detector, not the other way round.
    """
    root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return Path(root) / name


def write_atomic(path: Path, text: str) -> None:
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


@dataclass
class Snapshot:
    rows: list
    status: str
    generated: float

    @property
    def age(self) -> float:
        return max(0.0, time.time() - self.generated)


class RadarCache:
    """One radar's cache: its directory, its daemon and its row codec.

    `encode` turns a row into a JSON-safe dict; `decode` turns one back into a
    row and is allowed to raise KeyError or TypeError on a payload written by an
    older version of the radar -- see `read`, which treats that as an unusable
    snapshot rather than showing half a list.
    """

    def __init__(
        self,
        name: str,
        daemon_script: Path | str,
        encode,
        decode,
        *,
        interval: float = DEFAULT_INTERVAL,
        stale_after: float = DEFAULT_STALE_AFTER,
        idle_exit: float = DEFAULT_IDLE_EXIT_SECONDS,
    ) -> None:
        self.name = name
        self.daemon_script = Path(daemon_script)
        self.encode = encode
        self.decode = decode
        self.interval = interval
        self.stale_after = stale_after
        self.idle_exit = idle_exit

    # --- Paths ---------------------------------------------------------------

    def cache_dir(self) -> Path:
        return cache_root(self.name)

    def state_path(self) -> Path:
        return self.cache_dir() / "state.json"

    def status_path(self) -> Path:
        """The tmux status-bar string, published as plain text beside the JSON.

        Its own file so a status-bar script stays a `cat` on the hot path. That
        script runs on every status refresh, of which there are far more than
        the status-interval timer suggests, and starting a Python interpreter
        there to pull one field out of the JSON would cost more than the
        sampling does.
        """
        return self.cache_dir() / "status.txt"

    def lock_path(self) -> Path:
        return self.cache_dir() / "daemon.lock"

    def heartbeat_path(self) -> Path:
        return self.cache_dir() / "heartbeat"

    def log_path(self) -> Path:
        return self.cache_dir() / "daemon.log"

    # --- Publishing ----------------------------------------------------------

    def publish(self, rows: list, status: str) -> None:
        """Write the snapshot every consumer reads. Called only by the daemon."""
        payload = {
            "generated": time.time(),
            "status": status,
            "rows": [self.encode(row) for row in rows],
        }
        write_atomic(self.state_path(), json.dumps(payload))
        write_atomic(self.status_path(), status)

    # --- Reading -------------------------------------------------------------

    def touch_heartbeat(self) -> None:
        """Tell the daemon somebody is still reading, so it knows not to exit."""
        path = self.heartbeat_path()
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        except OSError:
            pass

    def last_read_age(self) -> float:
        """How long since a consumer last read the snapshot.

        Missing counts as infinitely old, not as brand new. The daemon stamps
        this file once at startup precisely so that "missing" means something
        has removed it -- and a sampler whose cache directory has been wiped
        should exit and let the next consumer respawn it, not keep publishing
        into nowhere. Reading it as fresh would instead make the idle exit
        unreachable for a daemon nobody ever reads from.
        """
        try:
            return max(0.0, time.time() - self.heartbeat_path().stat().st_mtime)
        except OSError:
            return float("inf")

    def read(self, max_age: float | None = None) -> Snapshot | None:
        """The published snapshot, or None if there is not a usable one.

        The file's mtime is the clock, not the `generated` field inside it: both
        are written by the same machine, and mtime cannot disagree with the file
        it is attached to.
        """
        if max_age is None:
            max_age = self.stale_after
        self.touch_heartbeat()
        path = self.state_path()
        try:
            generated = path.stat().st_mtime
            if time.time() - generated > max_age:
                return None
            payload = json.loads(path.read_text())
        except (OSError, ValueError):
            return None

        # `rows` is required, not defaulted: a payload without it was written by
        # a version of the radar that predates this cache, and reading it as an
        # empty list would render as "nothing is running" -- a confident wrong
        # answer, where None means "sample live" and is merely slower.
        try:
            entries = payload["rows"]
        except (KeyError, TypeError):
            return None

        rows = []
        for entry in entries:
            try:
                rows.append(self.decode(entry))
            except (KeyError, TypeError):
                # A snapshot written by an older version of the radar. Treat the
                # whole thing as unusable rather than showing half a list.
                return None
        return Snapshot(rows, payload.get("status", ""), generated)

    # --- The daemon ----------------------------------------------------------

    def daemon_running(self) -> bool:
        """Whether a sampler holds the lock.

        The lock *is* the liveness check: it is held for as long as the daemon's
        process exists and released by the kernel when it dies, however it dies.
        A pidfile would need a separate "is that pid still the daemon" test and
        would go stale on a crash.
        """
        try:
            fd = os.open(self.lock_path(), os.O_CREAT | os.O_RDWR, 0o644)
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

    def ensure_daemon(self, interval: float | None = None) -> None:
        """Start the sampler if nothing is sampling. Safe to call on every tick.

        Two consumers can both find the lock free and both spawn; the loser exits
        the moment it fails to take the lock, so the race costs one wasted
        process start and cannot produce two samplers.
        """
        if interval is None:
            interval = self.interval
        try:
            self.cache_dir().mkdir(parents=True, exist_ok=True)
        except OSError:
            return
        if self.daemon_running():
            return
        try:
            log = open(self.log_path(), "a")
        except OSError:
            log = subprocess.DEVNULL
        try:
            subprocess.Popen(
                [sys.executable, str(self.daemon_script), "--interval", str(interval)],
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

    def take_lock(self):
        """Claim the right to be the sampler, or None if someone else has it.

        The caller holds the returned descriptor open for its whole life and
        never releases it explicitly: the kernel drops it when the process ends,
        by any route, which is what makes `daemon_running()` truthful even after
        a crash.
        """
        self.cache_dir().mkdir(parents=True, exist_ok=True)
        fd = os.open(self.lock_path(), os.O_CREAT | os.O_RDWR, 0o644)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            return None
        return fd

    def sample_cached(self, sample, interval: float | None = None) -> list:
        """What consumers call: the shared snapshot, or a live sample if there is none.

        The fallback is what makes the daemon an optimisation rather than a
        dependency -- every consumer still works, at the old cost, if it is not
        running yet or has just died.
        """
        self.ensure_daemon(interval)
        snapshot = self.read()
        if snapshot is not None:
            return snapshot.rows
        return sample()
