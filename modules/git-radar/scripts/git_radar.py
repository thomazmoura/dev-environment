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
# An ssh session's repository that could not be asked about: the host did not
# answer, has no git-radar, or has one too old to serve. Its own state rather
# than NOREPO, because "not a repo" would be a confident wrong answer about a
# directory nobody looked at. The reason is in `detail`.
OFFLINE = "offline"

STATES = (CONFLICTED, DIVERGED, DIRTY, SYNCED, CLEAN, NOREPO, OFFLINE)

# The reasons an OFFLINE row gives, in `detail`.
UNREACHABLE = "unreachable"
NO_RADAR = "no git-radar"
OUTDATED = "git-radar outdated"
# Not a failure: the host has not answered about this directory yet -- the first
# moments of a new ssh session, before the poller's first round trip is back.
CONNECTING = "connecting\u2026"

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
    # The @ssh_target of an ssh session's row -- whose repository, and whose
    # `root`, are on that host. Empty for a local row.
    remote: str = ""

    @property
    def has_repo(self) -> bool:
        """Whether there is a repository behind the row to show a branch for."""
        return self.state not in (NOREPO, OFFLINE)

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


@dataclass
class Session:
    name: str
    path: str
    # For an ssh session (prefix+N): its @ssh_target, and whether the host has
    # this dev-environment -- and so a git-radar to ask. Empty for a local one.
    remote: str = ""
    devenv: bool = False


def list_sessions() -> list[Session]:
    """Every session with the directory its repository is in, in one tmux call.

    session_path is where the session was created, which is the right answer for
    the New-CodeSession.sh workflow: one session per project directory. It is
    preferred over pane_current_path precisely because it does not follow a `cd`
    inside some pane -- the session's identity is the project, not wherever the
    shell in pane 2 happens to be sitting. pane_current_path is the fallback for
    sessions created without an explicit -c.

    Sessions opened with prefix+N (New-SshSession.sh) have their repository on
    another machine: their local session_path is only the home directory their
    ssh commands are typed from. Their directory is @ssh_dir instead, on the
    host in @ssh_target, and detect() asks that host about it.
    """
    fmt = "\t".join([
        "#{session_name}", "#{session_path}", "#{pane_current_path}",
        "#{@ssh_target}", "#{@ssh_dir}", "#{@ssh_devenv}",
    ])
    code, out = _run(["tmux", "list-sessions", "-F", fmt])
    if code != 0:
        return []

    sessions = []
    for line in out.splitlines():
        fields = line.split("\t")
        if len(fields) != 6:
            continue
        name, session_path, pane_path, ssh_target, ssh_dir, ssh_devenv = fields
        if not name:
            continue
        if ssh_target:
            if ssh_dir:
                sessions.append(
                    Session(name, ssh_dir, ssh_target, ssh_devenv == "yes")
                )
            continue
        path = session_path or pane_path
        if path:
            sessions.append(Session(name, os.path.normpath(path)))
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


def inspect_path(path: str) -> Repo:
    """One directory's row, sampled here and now. What a served path costs."""
    repo = Repo(session="", path=path)
    repo.root = repo_root(path)
    if not repo.root:
        repo.state = NOREPO
        return repo
    return inspect(repo)


def copy_state(repo: Repo, source: Repo) -> None:
    """Give `repo` everything `source` knows about the repository, keeping its
    own session, path and remote -- the three that say whose row it is."""
    for field_name in FIELDS:
        if field_name not in ("session", "path", "remote"):
            setattr(repo, field_name, getattr(source, field_name))


def detect(remote=None, extra_paths=()) -> list[Repo]:
    """Every session, with its repository's state. The expensive path.

    Sessions sharing a repository share its status call -- the second one is a
    dictionary lookup. Rows come back sorted by session name, which is tmux's own
    order: this list doubles as a session overview, so it should look like one.
    Attention is carried by colour, not by position. (Sorting by STATE_ORDER
    instead is a one-line change; the feed anchors its cursor by session name and
    tolerates re-ordering.)

    ssh sessions are asked of their host, all of one host's directories in one
    call: `remote(target, paths)` returns {path: Repo}, or a phrase saying why
    there is no answer (UNREACHABLE and friends), which the rows then carry as
    OFFLINE. The default asks there and then (git_remote.query); the daemon
    passes a RemotePoller instead, whose threads do the asking, so a host that
    is slow to answer never holds up the local rows.

    `extra_paths` are directories a *remote* client has asked this machine
    about (git_feed.serve). They come back as rows with no session, after the
    session rows; git_feed keeps them away from everything that lists sessions.
    """
    if remote is None:
        import git_remote

        remote = git_remote.query

    by_root: dict[str, Repo] = {}
    repos = []
    by_host: dict[str, list[Repo]] = {}

    for session in list_sessions():
        repo = Repo(session=session.name, path=session.path, remote=session.remote)
        repos.append(repo)
        if session.remote:
            if session.devenv:
                by_host.setdefault(session.remote, []).append(repo)
            else:
                # Nothing on that host to ask, and nothing here can look.
                repo.state, repo.detail = OFFLINE, NO_RADAR
            continue

        root = repo_root(session.path)
        if not root:
            repo.state = NOREPO
            continue

        repo.root = root
        seen = by_root.get(root)
        if seen is None:
            by_root[root] = inspect(repo)
        else:
            copy_state(repo, seen)

    for target, rows in by_host.items():
        answer = remote(target, sorted({repo.path for repo in rows}))
        for repo in rows:
            found = answer.get(repo.path) if isinstance(answer, dict) else None
            if found is None:
                repo.state = OFFLINE
                repo.detail = answer if isinstance(answer, str) else CONNECTING
            else:
                copy_state(repo, found)

    repos.sort(key=lambda repo: repo.session.lower())

    for path in extra_paths:
        repos.append(inspect_path(path))

    return repos


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
    "remote",
)
