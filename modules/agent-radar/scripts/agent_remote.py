"""Asks another machine's agent-radar which of our ssh panes hold an agent.

An ssh session (prefix+N, modules/tmux/scripts/New-SshSession.sh) is a local
tmux session whose panes are all ssh'd into one host. An agent started in one
runs on that host, where this machine's `ps` cannot see it -- but its screen is
right here, in the pane. So the split is the reverse of git-radar's: the host
only says *which* pane holds *which* agent (agent_radar.serve, one `ps` there,
no daemon), and this machine captures, classifies and debounces the screen
like any other pane's.

    query(target, client)   one round trip, synchronous; the fallback path
    poller(interval, ...)   the daemon's way: a radar_remote.RemotePoller, a
                            thread per host doing the asking

The ssh and the poller are shared with git-radar, in
modules/tmux/scripts/radar_remote.py.
"""

from __future__ import annotations

import json
import shlex
import socket
import subprocess
import sys

import agent_radar as radar

sys.path.insert(0, str(radar.SHARED_SCRIPTS))

import radar_remote  # noqa: E402

# Where the remote's agent-radar is. $HOME is left for the remote shell.
SERVE = '"$HOME/.modules/agent-radar/scripts/Get-AgentState.py" --serve'

# The reply's format. Bumped whenever what --serve prints changes shape, so an
# older remote is told apart from a broken one.
PROTOCOL = 1

# Short next to git-radar's ten: over the master connection an answer takes a
# few tens of milliseconds, and the host does nothing slower than a `ps`.
QUERY_TIMEOUT = 5.0

# Why a host gave no answer. No row shows them -- a pane whose agent nobody
# could identify is not listed -- but they keep a failed answer from reading as
# "no agents there".
CONNECTING = "connecting"
UNREACHABLE = "unreachable"
NO_RADAR = "no agent-radar"
OUTDATED = "agent-radar outdated"


def client_id() -> str:
    """How this machine names itself in AGENT_RADAR_PANE: ssh_command in
    ssh-helpers.sh writes `$(hostname)`, which is the same uname nodename."""
    return socket.gethostname()


def query(target: str, client: str | None = None, fresh: bool = False) -> dict | str:
    """{pane_id: entry} for `client`'s panes holding an agent on `target`.

    Each entry is what agent_radar.serve returns: the pane, the agent and its
    hook marker. Otherwise the phrase for why there is no answer. `fresh` is
    accepted for the poller's sake and means nothing here: the host keeps no
    snapshot that could predate the question.
    """
    script = f"{SERVE} {shlex.quote(client or client_id())}"
    try:
        result = subprocess.run(
            radar_remote.remote_argv(target, script),
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            check=False,
            timeout=QUERY_TIMEOUT,
            start_new_session=True,
        )
    except (subprocess.TimeoutExpired, OSError):
        return UNREACHABLE

    if result.returncode == 255:
        # ssh's own failure: no route, no master and no key it may use.
        return UNREACHABLE
    if result.returncode in (126, 127):
        return NO_RADAR
    if result.returncode != 0:
        # argparse's 2 is an agent-radar that predates --serve.
        return OUTDATED

    try:
        payload = json.loads(result.stdout)
        if payload.get("version") != PROTOCOL:
            return OUTDATED
        return {
            entry["pane"]: {
                "agent": str(entry["agent"]),
                "marker": entry.get("marker") if isinstance(entry.get("marker"), dict) else None,
            }
            for entry in payload["agents"]
        }
    except (ValueError, KeyError, TypeError, AttributeError):
        return OUTDATED


def poller(interval: float, stale_after: float) -> radar_remote.RemotePoller:
    """What the daemon hands detect() in place of `query`: lookup(target,
    client) never waits on the network. See radar_remote.RemotePoller."""
    return radar_remote.RemotePoller(
        query, interval, stale_after,
        connecting=CONNECTING, unreachable=UNREACHABLE,
    )
