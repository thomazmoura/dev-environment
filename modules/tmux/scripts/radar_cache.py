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
free spawns it (`ensure_daemon`), it replaces itself when its own code changes
(`restart_daemon`), and it exits on its own once nothing has read from it for a
while. A read that comes back stale falls back to sampling live,
which is what makes the daemon an optimisation rather than a dependency.

This module owns only the generic half of that: the cache directory, the atomic
publish, the flock liveness check, the heartbeat and the staleness rules. What a
row *is*, how it is sampled and any cross-sample smoothing stay with each radar.

    RadarCache("git-radar", daemon, encode, decode)   bind a radar to a cache
    cache.publish(rows, status)                        what the daemon writes
    cache.read() / cache.sample_cached(sample)         what consumers call
    cache.source_baseline() / source_changed()         has the code been edited?
    cache.restart_daemon(lock, interval)               hand over to that code

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

# How often a sampler stats its "sample now" flag while it would otherwise be
# asleep. Shared rather than scaled to the tick: this is the latency a person
# waits, and a slower tick says a sample costs more, not that a dead row should
# linger longer.
NUDGE_POLL = 0.05


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


def source_root(daemon_script: Path) -> Path | None:
    """The tree a radar's code lives in, given its daemon: `modules/`.

    Every radar sits at `modules/<radar>/scripts/Start-*.py`, so the daemon
    script is three levels down from the root shared with `modules/tmux/scripts`
    -- which is where this file lives, and so is part of every radar's code.
    """
    try:
        parents = daemon_script.resolve().parents
    except OSError:
        return None
    return parents[2] if len(parents) > 2 else None


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

    def nudge_path(self) -> Path:
        """The "sample now" flag: a file whose mtime is the whole message.

        The interval is what a sampler falls back on when nothing tells it
        anything, and a pane closing is instant on screen, so its row is a lie
        for whatever is left of the tick. Anything that knows such a moment
        happened touches this file and the sampler wakes on it.

        A file rather than a signal, because a signal needs a pid: the daemon
        deliberately keeps no pidfile -- the flock *is* the liveness check --
        and a pid read from a file can belong to whatever inherited the number.
        Nobody has to be listening either; with no daemon up this is just a
        file, whose mtime the next daemon adopts as its baseline.
        """
        return self.cache_dir() / "resample"

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

    def nudge_stamp(self) -> float:
        """The mtime of the "sample now" flag, or 0.0 if nothing has ever asked.

        Compared against the previous check rather than against the clock:
        "has anyone asked since I last looked" needs no threshold for how
        recent counts, and every value of such a threshold is either a missed
        nudge or a repeated one.
        """
        try:
            return self.nudge_path().stat().st_mtime
        except OSError:
            return 0.0

    def request_sample(self) -> None:
        """Ask the sampler to publish now instead of at the end of its tick."""
        path = self.nudge_path()
        try:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.touch()
        except OSError:
            pass

    def generation(self) -> float:
        """The mtime of the published snapshot, or 0.0 if there is none.

        For consumers that redraw when the snapshot *changes* rather than when
        their own timer comes round, so the two timers do not stack. A stat is
        cheap enough for a keypress loop where a read and decode is not; 0.0
        can only compare unequal to a real mtime, so a daemon appearing or
        dying also reads as a change.
        """
        try:
            return self.state_path().stat().st_mtime
        except OSError:
            return 0.0

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

    # --- Reloading its own code ---------------------------------------------
    # A sampler imports its code once and then runs for days. An edit reaches
    # every consumer at once, because consumers are short-lived -- and never
    # reaches the daemon, whose snapshot those consumers read in preference to
    # sampling for themselves (`sample_cached`). So a change tests correct by
    # hand and is wrong everywhere it is actually shown, with nothing on screen
    # saying why. Worse, the self-recycling below cannot save it: `idle_exit`
    # needs nobody to be reading, and a status bar reads every tick, so on a
    # machine in use the daemon that is holding stale code is exactly the one
    # that never ages out.
    #
    # The source is discovered rather than listed: whatever this process has
    # already imported from under `modules/`, which is precisely the set it
    # could be holding stale. A hand-maintained list would be one more thing to
    # forget to update, and forgetting is the whole bug.
    #
    # Rules files are deliberately not included. agent_radar.detect() re-reads
    # its TOML every tick, so those already deploy live and watching them would
    # buy nothing but restarts.

    def source_files(self) -> list[Path]:
        """Every already-imported module file under this radar's tree."""
        root = source_root(self.daemon_script)
        if root is None:
            return []
        found = set()
        # A copy: importing during iteration is possible and mutating
        # sys.modules under a live view of it raises.
        for module in list(sys.modules.values()):
            path = getattr(module, "__file__", None)
            if not path:
                continue
            try:
                resolved = Path(path).resolve()
                resolved.relative_to(root)
                real = resolved.is_file()
            except (OSError, ValueError):
                # ValueError is the common case and means "outside the tree":
                # the stdlib, and anything pip put in site-packages.
                continue
            if not real:
                # `__file__` is not always a file: a module exec'd from stdin or
                # a string carries something like "<stdin>", which resolves to a
                # plausible path under the tree that has never existed. Watching
                # it would be harmless but permanent noise in the baseline.
                continue
            found.add(resolved)
        return sorted(found)

    def source_baseline(self) -> dict[str, tuple[int, int]]:
        """What this sampler's code looked like when it started.

        Taken once, and re-stat'd against the same keys afterwards, so a module
        imported lazily later reads as what it is -- a new file, not a changed
        one -- and cannot trigger a restart on its own.
        """
        return self._stat_sources(self.source_files())

    @staticmethod
    def _stat_sources(paths) -> dict[str, tuple[int, int]]:
        marks: dict[str, tuple[int, int]] = {}
        for path in paths:
            try:
                info = Path(path).stat()
            except OSError:
                # Deleted, or caught mid-rename. Recorded as a value of its own
                # rather than skipped, so a file going missing reads as a change
                # instead of silently shrinking the set being compared.
                marks[str(path)] = (-1, -1)
            else:
                marks[str(path)] = (info.st_mtime_ns, info.st_size)
        return marks

    def source_changed(self, baseline: dict[str, tuple[int, int]]) -> bool:
        """Whether any of that code has been edited since.

        Size as well as mtime, because `git checkout` between two branches can
        land a file with the mtime it had before.
        """
        return self._stat_sources(baseline) != baseline

    def restart_daemon(self, lock: int | None, interval: float) -> None:
        """Replace this sampler with one running the current code. Never returns.

        exec, rather than exiting and letting a consumer respawn us, because
        there may be no consumer: agent-radar keeps sampling with everybody
        detached while notifications are on, and git-radar keeps sampling for
        remote clients on a machine with no tmux of its own. Both are precisely
        the cases where nothing would call `ensure_daemon`, so an exit there is
        not a restart, it is a stop.

        exec also keeps the daemon's stdout and stderr, which are the log file
        `ensure_daemon` opened, so the replacement goes on writing where this
        one left off.
        """
        if lock is not None:
            # Dropped deliberately, and only here: the replacement claims it
            # back microseconds later. A consumer ticking inside that window can
            # spawn a second sampler, which is the race `ensure_daemon` already
            # documents and already survives -- the loser exits the moment
            # `take_lock` fails.
            try:
                os.close(lock)
            except OSError:
                pass
        try:
            os.execv(
                sys.executable,
                [sys.executable, str(self.daemon_script), "--interval", str(interval)],
            )
        except OSError as error:
            # The interpreter or the script is unreadable -- a tree mid-checkout,
            # say. The lock is already gone, so exit and let the next consumer
            # tick spawn a replacement; sampling on with half the code reloaded
            # is not an option, since exec is all-or-nothing and this is the
            # branch where it was nothing.
            print(f"{self.name}: restart failed: {error!r}", file=sys.stderr, flush=True)
            os._exit(0)

    def wait_for_tick(self, remaining: float, seen: float, also=None) -> float:
        """Sleep out the rest of a tick, unless somebody asks for a sample sooner.

        `seen` is the flag's mtime as of the last check and comes back updated,
        so one touch wakes exactly one tick. See `nudge_path`.

        `also` is an optional threading.Event that ends the wait too -- for a
        sampler with news arriving from its own threads (git-radar hears from
        remote hosts that way). It is cleared on the way out, and `seen` comes
        back unchanged, so the caller can tell it apart from a nudge.
        """
        deadline = time.monotonic() + remaining
        while True:
            left = deadline - time.monotonic()
            if left <= 0:
                return seen
            time.sleep(min(NUDGE_POLL, left))
            stamp = self.nudge_stamp()
            if stamp != seen:
                return stamp
            if also is not None and also.is_set():
                also.clear()
                return seen

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
