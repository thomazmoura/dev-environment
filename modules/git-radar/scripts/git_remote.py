"""Asks another machine's git-radar where an ssh session's repository stands.

An ssh session (prefix+N, modules/tmux/scripts/New-SshSession.sh) is a local
tmux session whose panes are all ssh'd into one host, so its repository is on
that host and nothing here can run `git status` on it. What can be done is to
ask the host's own git-radar, which is the same code as this one: `Get-GitState.py
--serve` on the remote takes directories on stdin, registers them with its
sampler so they stay in its snapshot, and prints their rows as JSON.

    query(target, paths)       one round trip, synchronous; the fallback path
    poller(interval, ...)      the daemon's way: a radar_remote.RemotePoller,
                               a thread per host doing the asking, so a host
                               that is slow to answer never holds up the local
                               rows or the nudge latency
    op_argv(target, root, ...) f / p / P on a remote row, as an ssh command line

The ssh and the poller are shared with agent-radar, in
modules/tmux/scripts/radar_remote.py. Every ssh here is BatchMode with no
stdin, for the reasons fetch_env in Watch-GitFeed.py spells out: this runs
from a daemon and from a curses pane, and neither has anywhere a password
prompt could go.
"""

from __future__ import annotations

import json
import shlex
import subprocess
import sys

import git_radar as gitr

sys.path.insert(0, str(gitr.SHARED_SCRIPTS))

import radar_remote  # noqa: E402
from radar_remote import remote_argv  # noqa: E402

# The same prefix remote_agent_env in ssh-helpers.sh prints: the host's shared
# agent, when its socket is there, so a fetch on the remote finds the key the
# panes use. An `if` with no else succeeds when its test fails, so a host
# without the agent still runs the command.
REMOTE_AGENT_ENV = (
    'a="$HOME/.ssh/tmux-agent"; '
    'if [ -S "$a/agent.sock" ]; then '
    'export SSH_AUTH_SOCK="$a/agent.sock" SSH_AGENT_PID="$(cat "$a/agent.pid")"; '
    "fi && "
)

# Where the remote's git-radar is. $HOME is left for the remote shell.
SERVE = '"$HOME/.modules/git-radar/scripts/Get-GitState.py" --serve'
REMOTE_NUDGE = '"$HOME/.modules/tmux/scripts/Request-RadarSample.sh" git-radar'

# The reply's format. Bumped whenever what --serve prints changes shape, so an
# older remote says so on its rows instead of being misread.
PROTOCOL = 1

# Generous next to ConnectTimeout: over the master connection an answer takes
# a few tens of milliseconds, and a remote inspecting a directory for the first
# time walks its work tree.
QUERY_TIMEOUT = 10.0


def query(target: str, paths: list[str], fresh: bool = False) -> dict | str:
    """One directory's-worth of rows per path, from the host's git-radar.

    {path: Repo} on success, otherwise the phrase an OFFLINE row carries. The
    paths go on stdin, one per line, so no directory name ever has to survive
    two rounds of shell quoting.

    `fresh` asks the remote to sample now rather than answer from its snapshot
    -- for right after a fetch, when the snapshot predates it.
    """
    script = SERVE + (" --fresh" if fresh else "")
    try:
        result = subprocess.run(
            remote_argv(target, script),
            input="".join(f"{path}\n" for path in paths),
            capture_output=True,
            text=True,
            check=False,
            timeout=QUERY_TIMEOUT,
            start_new_session=True,
        )
    except subprocess.TimeoutExpired:
        return gitr.UNREACHABLE
    except OSError:
        return gitr.UNREACHABLE

    if result.returncode == 255:
        # ssh's own failure: no route, no master and no key it may use.
        return gitr.UNREACHABLE
    if result.returncode in (126, 127):
        return gitr.NO_RADAR
    if result.returncode != 0:
        # argparse's 2 is a git-radar that predates --serve.
        return gitr.OUTDATED

    try:
        payload = json.loads(result.stdout)
        if payload.get("version") != PROTOCOL:
            return gitr.OUTDATED
        rows = {}
        for entry in payload["rows"]:
            repo = gitr.Repo(**{field: entry[field] for field in gitr.FIELDS})
            rows[repo.path] = repo
        return rows
    except (ValueError, KeyError, TypeError, AttributeError):
        return gitr.OUTDATED


def op_argv(target: str, root: str, git_args: list[str]) -> list[str]:
    """A fetch, pull or push run in `root` on `target`, as a local command line.

    On the remote it gets the same no-prompt environment fetch_env gives a local
    one, plus the host's shared agent. Afterwards the remote's own sampler is
    nudged, so its snapshot -- and any feed open on the remote itself -- moves
    with the refs; the local side asks with --fresh anyway (poller's wake).
    The exit status is git's.
    """
    git = " ".join(shlex.quote(arg) for arg in ["git", "-C", root, *git_args])
    script = (
        REMOTE_AGENT_ENV
        + "GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' "
        + f"SSH_ASKPASS_REQUIRE=never {git}; status=$?; "
        + f"{REMOTE_NUDGE} >/dev/null 2>&1; exit $status"
    )
    return remote_argv(target, script)


def poller(interval: float, stale_after: float) -> radar_remote.RemotePoller:
    """What the daemon hands detect() in place of `query`.

    lookup(target, paths) never waits on the network, and a host's rows turn
    OFFLINE once its last answer is older than `stale_after` -- see
    radar_remote.RemotePoller. wake() asks every host again with --fresh.
    """
    return radar_remote.RemotePoller(
        query, interval, stale_after,
        connecting=gitr.CONNECTING, unreachable=gitr.UNREACHABLE,
    )
