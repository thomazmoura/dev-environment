"""Linked tmux servers: which machines this one is linked to, and what they hold.

Each machine runs its own tmux server with its own sessions. Linking two of
them (prefix+N, New-SshSession.sh) makes each show the other's sessions and
code folders beside its own -- in prefix+?, prefix+/ and the Git and Agents
panes -- and choosing one moves the *client* to that machine's tmux
(Switch-LinkSession.sh, Connect-Tmux.sh) instead of opening panes over ssh in
this one. That is what an ssh session (ssh-helpers.sh) does, and what a link
replaces for a machine that can be linked.

    identity()             user@hostname: what a machine is called everywhere
    read_peers()           the machines this one is linked to
    link() / unlink()      edit that list (also run over ssh, for the other side)
    serve()                this machine's sessions and folders, for a peer
    query(address)         a peer's serve(), over ssh
    machines()             this machine and its peers, from the snapshot
    session_key()          <host>:<session>, a linked session's name in the radars

Start-TmuxLink.py asks each peer once a tick and publishes the answers, through
the cache the radars share (radar_cache.py), so a picker opens on a file read.
Get-TmuxLink.py is the CLI over all of it.

The peers are a file rather than tmux options because a link outlives the tmux
server, and because the peer's side of it is written over ssh, tmux or no tmux:

    ~/.config/tmux-link/peers     <identity> TAB <address>, one per line
    ~/.config/tmux-link/aliases   the same, written by hand: the address *this*
                                  device reaches an identity at, when it is not
                                  the one the link was made with

Every ssh here is BatchMode with no stdin, as in radar_remote.py: this runs from
a daemon and from popups' pipelines, where a password prompt has nowhere to go.
"""

from __future__ import annotations

import getpass
import json
import os
import socket
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import radar_cache  # noqa: E402
import radar_remote  # noqa: E402

HERE = Path(__file__).resolve().parent

# The reply's format. Bumped whenever what serve() returns changes shape.
PROTOCOL = 1

# Where the peer's copy of the CLI is. $HOME is left for the remote shell.
SERVE = '"$HOME/.modules/tmux/scripts/Get-TmuxLink.py" --serve'

# Sessions and folders change when somebody opens or closes one: slow next to
# the radars, which the Git and Agents panes read for anything that moves.
DEFAULT_INTERVAL = 5.0
STALE_AFTER = 20.0
QUERY_TIMEOUT = 10.0

# A machine's state in the snapshot.
SELF = "self"
ONLINE = "online"
CONNECTING = "connecting…"
UNREACHABLE = "unreachable"
NO_LINK = "no tmux-link"
OUTDATED = "tmux-link outdated"


def config_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config") / "tmux-link"


def peers_path() -> Path:
    return config_dir() / "peers"


def identity() -> str:
    """user@hostname, the short host name in lower case.

    TMUX_LINK_IDENTITY replaces it, as in Connect-Tmux.sh -- the two have to
    agree, since that script compares a handoff's identity with its own.
    """
    override = os.environ.get("TMUX_LINK_IDENTITY")
    if override:
        return override
    return f"{getpass.getuser()}@{socket.gethostname().split('.')[0].lower()}"


def host_of(identity_: str) -> str:
    return identity_.rsplit("@", 1)[-1]


def session_key(identity_: str, session: str) -> str:
    """What a session on a linked machine is called in the radars' rows.

    A colon cannot be in a tmux session name, so a key never reads as a local
    session; Switch-LinkSession.sh tells the two apart by it.
    """
    return f"{host_of(identity_)}:{session}"


# --- The peers file ------------------------------------------------------------


def read_peers() -> list[tuple[str, str]]:
    """(identity, address) for every linked machine, in the file's order."""
    try:
        lines = peers_path().read_text().splitlines()
    except OSError:
        return []
    peers = []
    for line in lines:
        fields = line.split("\t")
        if len(fields) >= 2 and fields[0] and fields[1]:
            peers.append((fields[0], fields[1]))
    return peers


def _write_peers(peers: list[tuple[str, str]]) -> None:
    radar_cache.write_atomic(
        peers_path(), "".join(f"{identity_}\t{address}\n" for identity_, address in peers)
    )


def link(identity_: str, address: str) -> None:
    """Add a peer, or change the address of one already there. Never itself."""
    if identity_ == identity():
        return
    peers = [(known, where) for known, where in read_peers() if known != identity_]
    peers.append((identity_, address))
    _write_peers(peers)
    CACHE.request_sample()


def unlink(identity_: str) -> None:
    _write_peers([(known, where) for known, where in read_peers() if known != identity_])
    CACHE.request_sample()


# --- What this machine holds ---------------------------------------------------


def code_folder() -> str:
    """Where the projects are: $CODE_FOLDER, else the first of the profile's
    own guesses that exists (kernel-profile.ps1). Guessed again here because a
    peer asks over ssh, in a shell with none of the profile's variables."""
    configured = os.environ.get("CODE_FOLDER")
    candidates = [configured] if configured else []
    candidates += ["~/code", "~/git", "/Git"]
    for candidate in candidates:
        path = os.path.expanduser(candidate)
        if os.path.isdir(path):
            return path
    return os.path.expanduser("~")


def folders(root: str) -> list[str]:
    """The first level of folders under `root`, hidden ones left out."""
    try:
        return sorted(
            (entry.name for entry in os.scandir(root)
             if entry.is_dir() and not entry.name.startswith(".")),
            key=str.lower,
        )
    except OSError:
        return []


def local_sessions() -> list[dict]:
    """This tmux server's own sessions; none when there is no server.

    An ssh or Docker session (@ssh_target) is left out: its panes are on a
    third machine, and what a peer is offered is what attaching here shows as
    this machine's work.
    """
    fmt = "\t".join(["#{session_name}", "#{session_path}", "#{@ssh_target}", "#{@session_label}"])
    try:
        result = subprocess.run(
            ["tmux", "list-sessions", "-F", fmt],
            capture_output=True, text=True, check=False, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if result.returncode != 0:
        return []
    sessions = []
    for line in result.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) != 4 or not fields[0] or fields[2]:
            continue
        sessions.append({"name": fields[0], "path": fields[1], "label": fields[3]})
    return sessions


def serve() -> dict:
    """What a peer is told about this machine. What --serve prints."""
    root = code_folder()
    return {
        "version": PROTOCOL,
        "identity": identity(),
        "root": root,
        "sessions": local_sessions(),
        "folders": folders(root),
    }


# --- Asking a peer -------------------------------------------------------------


MASTER_CHECK = 30.0
_master_checked: dict[str, float] = {}


def ensure_master(address: str) -> None:
    """Keep one ssh connection to a peer open for everything asked of it.

    The radars ask a linked machine every tick with ControlMaster=no
    (radar_remote.SSH_OPTS), which rides a master when there is one and
    otherwise handshakes anew each time. An ssh session's panes hold that
    master open; a link has no panes, so this does. -f with no pipes: the
    master forks into the background keeping whatever it was started with, and
    a pipe would be waited on for as long as it lives.

    Looked into at most once every MASTER_CHECK seconds per address: the Agents
    pane's sampler asks every second, and a master that has just answered is
    still there.
    """
    now = time.monotonic()
    if now - _master_checked.get(address, -MASTER_CHECK) < MASTER_CHECK:
        return
    _master_checked[address] = now
    control = ["-o", f"ControlPath={os.path.expanduser('~')}/.ssh/tmux-%C"]
    try:
        check = subprocess.run(
            ["ssh", *control, "-O", "check", address],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            check=False, timeout=5,
        )
        if check.returncode == 0:
            return
        os.makedirs(os.path.expanduser("~/.ssh"), mode=0o700, exist_ok=True)
        subprocess.run(
            ["ssh", *control, "-o", "ControlMaster=yes", "-o", "ControlPersist=10m",
             "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3",
             "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", "-fN", address],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            check=False, timeout=15, start_new_session=True,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def query(address: str, request=None, fresh: bool = False) -> dict | str:
    """A peer's serve(), or the phrase its row carries instead.

    The signature is RemotePoller's (radar_remote.py); nothing is asked beyond
    the address.
    """
    ensure_master(address)
    try:
        result = subprocess.run(
            radar_remote.remote_argv(address, SERVE),
            stdin=subprocess.DEVNULL, capture_output=True, text=True, check=False,
            timeout=QUERY_TIMEOUT, start_new_session=True,
        )
    except (OSError, subprocess.SubprocessError):
        return UNREACHABLE
    if result.returncode == 255:
        return UNREACHABLE
    if result.returncode in (126, 127):
        return NO_LINK
    if result.returncode != 0:
        return OUTDATED
    try:
        payload = json.loads(result.stdout)
        if payload.get("version") != PROTOCOL or not payload["identity"]:
            return OUTDATED
        payload["sessions"], payload["folders"], payload["root"]
        return payload
    except (ValueError, KeyError, TypeError, AttributeError):
        return OUTDATED


# --- The snapshot --------------------------------------------------------------


@dataclass
class Machine:
    identity: str
    # How this machine reaches it; empty for this machine itself.
    address: str = ""
    state: str = SELF
    root: str = ""
    sessions: list = field(default_factory=list)
    folders: list = field(default_factory=list)

    @property
    def host(self) -> str:
        return host_of(self.identity)

    @property
    def online(self) -> bool:
        return self.state in (SELF, ONLINE)


FIELDS = ("identity", "address", "state", "root", "sessions", "folders")


def _encode(machine: Machine) -> dict:
    return {name: getattr(machine, name) for name in FIELDS}


def _decode(entry: dict) -> Machine:
    return Machine(**{name: entry[name] for name in FIELDS})


CACHE = radar_cache.RadarCache(
    "tmux-link",
    HERE / "Start-TmuxLink.py",
    _encode,
    _decode,
    interval=DEFAULT_INTERVAL,
    stale_after=STALE_AFTER,
)


def sample(remote=None) -> list[Machine]:
    """This machine first, then every peer. `remote` asks a peer: query here
    and now by default, a RemotePoller's lookup in the daemon."""
    if remote is None:
        remote = query
    own = serve()
    machines_ = [Machine(own["identity"], root=own["root"],
                         sessions=own["sessions"], folders=own["folders"])]
    for identity_, address in read_peers():
        answer = remote(address)
        if isinstance(answer, dict):
            machines_.append(Machine(identity_, address, ONLINE, answer["root"],
                                     answer["sessions"], answer["folders"]))
        else:
            machines_.append(Machine(identity_, address, answer or CONNECTING))
    return machines_


def machines() -> list[Machine]:
    """What consumers call: the snapshot, or a live sample when there is none.

    With nobody linked there is nothing to wait on a daemon for, and none is
    started (Start-TmuxLink.py exits at once without peers anyway).
    """
    if not read_peers():
        return sample()
    return CACHE.sample_cached(sample)


def poller(interval: float) -> radar_remote.RemotePoller:
    return radar_remote.RemotePoller(
        query, interval, STALE_AFTER, connecting=CONNECTING, unreachable=UNREACHABLE
    )
