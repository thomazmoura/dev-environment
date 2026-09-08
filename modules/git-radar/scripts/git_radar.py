"""Reads one git status per tmux session. The collector behind git-radar.

The question this answers is the one you ask by walking your sessions: which of
these repositories has work I have not committed, and which is out of step with
origin. agent-radar answers "who is waiting on me"; this answers "where did I
leave things".

Two deliberate constraints shape everything below.

  No fetching.  Ahead/behind is computed from the origin refs already in the
                repository. A tick therefore costs no network, cannot hang on a
                remote that is down and cannot prompt for credentials -- which
                matters a great deal for something a daemon runs every few
                seconds across every session you have open. The cost is that
                "behind" is only as fresh as your last fetch, so Watch-GitFeed.py
                offers `f` to fetch the selected repository on demand.

  One status.  `git status --porcelain=v2 --branch` returns the branch, the
                upstream *and* the ahead/behind pair in its header lines, so a
                repository costs one `status` rather than a `status` plus a
                `rev-list`. Halving the git calls is the difference between a
                tick you never notice and one you do.

Structure mirrors agent_radar.py: list the things (list_sessions), inspect each
one (inspect), and assemble (detect). Nothing here prints -- presentation lives
in Get-GitState.py, so the CLI and the curses feed cannot disagree about how a
row reads.
"""

from __future__ import annotations

import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

MODULE_ROOT = Path(__file__).resolve().parent.parent

# See agent_radar.SHARED_SCRIPTS: the generic cache machinery is shared between
# the radars and lives with the other tmux helpers.
SHARED_SCRIPTS = MODULE_ROOT.parent / "tmux" / "scripts"

# --- States ------------------------------------------------------------------
# One state per row, so the feed has exactly one thing to colour. A repository
# can of course be several of these at once (dirty *and* ahead); the order in
# STATE_ORDER is the order in which they are worth interrupting you, and the
# counts are all on the row anyway for the cases where you want the detail.
CONFLICTED = "conflicted"
DIVERGED = "diverged"
DIRTY = "dirty"
SYNCED = "synced"
CLEAN = "clean"
NOREPO = "norepo"

STATES = (CONFLICTED, DIVERGED, DIRTY, SYNCED, CLEAN, NOREPO)

# Only used for the optional attention-first ordering; detect() sorts by session
# name, because this list doubles as your session list and a row that moves while
# you are reaching for Enter is worse than one you have to scan for.
STATE_ORDER = {state: index for index, state in enumerate(STATES)}

# The literal git prints for `# branch.head` when HEAD is not on a branch.
DETACHED = "(detached)"


@dataclass
class Repo:
    session: str
    path: str
    root: str = ""
    branch: str = ""
    upstream: str = ""
    ahead: int = 0
    behind: int = 0
    added: int = 0
    modified: int = 0
    deleted: int = 0
    untracked: int = 0
    conflicted: int = 0
    state: str = NOREPO
    detail: str = ""

    @property
    def tracked_changes(self) -> int:
        return self.added + self.modified + self.deleted + self.conflicted

    @property
    def dirty(self) -> bool:
        return self.tracked_changes + self.untracked > 0


def _run(argv: list[str]) -> tuple[int, str]:
    """Run a command; return (returncode, stdout), or (-1, "") if it never ran.

    Fails open the same way agent_radar._run does, and for the same reason: this
    is on a daemon's hot path, and a repository being deleted or `git gc` holding
    a lock mid-tick must degrade one row rather than take the sampler down. The
    return code is kept here -- unlike in agent_radar -- because "not a git
    repository" is a normal, meaningful answer rather than a failure.
    """
    try:
        result = subprocess.run(
            argv, capture_output=True, text=True, check=False, timeout=5
        )
    except (OSError, subprocess.SubprocessError):
        return -1, ""
    return result.returncode, result.stdout


def git(path: str, *args: str) -> tuple[int, str]:
    """A git invocation that cannot disturb the repository it is reading.

    --no-optional-locks stops `status` from opportunistically refreshing the
    index, which would otherwise have the daemon taking index.lock every few
    seconds in every repository you have open -- and losing that race against
    your own interactive git is exactly the kind of intermittent "unable to
    create index.lock" that is miserable to trace back to a background process.
    """
    return _run(["git", "--no-optional-locks", "-C", path, *args])


def list_sessions() -> list[tuple[str, str]]:
    """Every session as (name, directory), in one tmux call.

    session_path is where the session was created, which is the right answer for
    the New-CodeSession.sh workflow: one session per project directory. It is
    preferred over pane_current_path precisely because it does not follow a `cd`
    inside some pane -- the session's identity is the project, not wherever the
    shell in pane 2 happens to be sitting. pane_current_path is the fallback for
    sessions created without an explicit -c.
    """
    fmt = "\t".join(["#{session_name}", "#{session_path}", "#{pane_current_path}"])
    code, out = _run(["tmux", "list-sessions", "-F", fmt])
    if code != 0:
        return []

    sessions = []
    for line in out.splitlines():
        fields = line.split("\t")
        if len(fields) != 3:
            continue
        name, session_path, pane_path = fields
        path = session_path or pane_path
        if not name or not path:
            continue
        sessions.append((name, os.path.normpath(path)))
    return sessions


def current_session() -> str:
    """The session the caller is running in, or "" outside tmux.

    Resolved from $TMUX_PANE -- the pane this process was started in -- rather
    than from the attached client's session. The two agree whenever you can see
    the pane, and they disagree exactly when you have switched the client
    somewhere else, at which point the row worth marking is still the one this
    pane lives in, not wherever the client wandered off to.

    Deliberately a consumer's question, not the sampler's: the daemon is
    detached and belongs to no session, so this cannot be a published field. Each
    consumer resolves it once at startup -- a pane does not change session.
    """
    pane = os.environ.get("TMUX_PANE")
    if not pane:
        return ""
    code, out = _run(["tmux", "display-message", "-p", "-t", pane, "#{session_name}"])
    if code != 0:
        return ""
    return out.strip()


def repo_root(path: str) -> str:
    """The work tree containing `path`, or "" if there is not one.

    A separate call from `status`, and worth it: rev-parse does not walk the
    work tree, so it is cheap next to a status, and knowing the root lets two
    sessions opened at different depths of the same repository share one status
    call. It is also what the feed's fetch key needs a directory for.
    """
    code, out = git(path, "rev-parse", "--show-toplevel")
    if code != 0:
        return ""
    return out.strip()


def _bucket(x: str, y: str) -> str | None:
    """Which count a changed file belongs to, from its staged/unstaged letters.

    A file is counted once, even when it is staged one way and modified another
    (`AM`, `MD`), because the row is a count of *files* you have touched, not of
    changes. Deletion wins over addition wins over modification: of the two
    letters, the one that says the file is going away is the one you want to see.
    """
    letters = {x, y}
    if "D" in letters:
        return "deleted"
    if "A" in letters:
        return "added"
    if letters & {"M", "R", "C", "T"}:
        return "modified"
    return None


def inspect(repo: Repo) -> Repo:
    """Fill in one repository's branch, divergence and working-tree counts.

    Parses `--porcelain=v2 --branch -z`. The -z is not paranoia: paths may
    contain newlines, and without it a single oddly-named file would silently
    inflate every count on the row. It costs one wrinkle -- a rename record ("2 ")
    is followed by a second NUL-terminated chunk holding the original path, which
    has to be consumed so it is not read as the next record.
    """
    code, out = git(repo.path, "status", "--porcelain=v2", "--branch", "-z")
    if code != 0:
        repo.state = NOREPO
        return repo

    records = out.split("\0")
    index = 0
    while index < len(records):
        record = records[index]
        index += 1
        if not record:
            continue

        if record.startswith("# "):
            key, _, value = record[2:].partition(" ")
            if key == "branch.head":
                repo.branch = value
            elif key == "branch.upstream":
                repo.upstream = value
            elif key == "branch.ab":
                # "+2 -1". Anything else is a git that has changed its mind
                # about the format; leave the zeros rather than guess.
                parts = value.split()
                if len(parts) == 2:
                    try:
                        repo.ahead = int(parts[0])
                        repo.behind = -int(parts[1])
                    except ValueError:
                        pass
            continue

        kind, _, rest = record.partition(" ")
        if kind == "?":
            repo.untracked += 1
        elif kind == "u":
            repo.conflicted += 1
        elif kind in ("1", "2"):
            xy = rest.split(" ", 1)[0]
            if len(xy) == 2:
                bucket = _bucket(xy[0], xy[1])
                if bucket:
                    setattr(repo, bucket, getattr(repo, bucket) + 1)
            if kind == "2":
                # The original path of a rename/copy, as its own field under -z.
                index += 1

    repo.state = _classify(repo)
    return repo


def _classify(repo: Repo) -> str:
    if repo.conflicted:
        return CONFLICTED
    if repo.ahead and repo.behind:
        return DIVERGED
    if repo.dirty:
        return DIRTY
    if repo.ahead or repo.behind:
        return SYNCED
    return CLEAN


def detect() -> list[Repo]:
    """Every session, with its repository's state. The expensive path.

    Sessions sharing a repository share its status call -- the second one is a
    dictionary lookup. Rows come back sorted by session name, which is tmux's own
    order: this list doubles as a session overview, so it should look like one.
    Attention is carried by colour, not by position. (Sorting by STATE_ORDER
    instead is a one-line change; the feed anchors its cursor by session name and
    tolerates re-ordering.)
    """
    by_root: dict[str, Repo] = {}
    repos = []

    for name, path in list_sessions():
        repo = Repo(session=name, path=path)
        root = repo_root(path)
        if not root:
            repo.state = NOREPO
            repos.append(repo)
            continue

        repo.root = root
        seen = by_root.get(root)
        if seen is None:
            by_root[root] = inspect(repo)
        else:
            for field_name in FIELDS:
                if field_name not in ("session", "path"):
                    setattr(repo, field_name, getattr(seen, field_name))
        repos.append(repo)

    return sorted(repos, key=lambda repo: repo.session.lower())


# Everything a consumer needs off a Repo, and the order the CLI prints them in.
FIELDS = (
    "session",
    "path",
    "root",
    "branch",
    "upstream",
    "ahead",
    "behind",
    "added",
    "modified",
    "deleted",
    "untracked",
    "conflicted",
    "state",
    "detail",
)
