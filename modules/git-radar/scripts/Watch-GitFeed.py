#!/usr/bin/env python3
"""A live feed of where every tmux session's repository stands, in a pane you leave open.

Bound to prefix+t then R (see modules/tmux/common.conf), which opens it through
New-ToolPane.sh so the pane is labelled like every other one. It is the git
counterpart of agent-radar's prefix+t then r, and deliberately the same shape:
curses rather than fzf, because fzf is an interactive filter that insists on
being one -- a prompt line, a match counter, a header, and an animated indicator
on every reload. On a timer in a narrow pane that is three lines of chrome and a
permanent flicker at the edge of vision, which is the opposite of what something
you glance at should do.

Two lines per session -- the name, then its branch and counts indented under it
-- and a counter appears only when it is non-zero. The first version put every
counter in a fixed column on one line, which in a narrow pane padded every row
to the width of the widest and turned the whole thing into a grey block you had
to read before you could dismiss it. Showing only what is true, and colouring
each count the way a diff would (green added, yellow modified, red deleted, grey
untracked), makes a row answerable at a glance instead.

The marker at the left is the one thing always in the same place, so it carries
the state as colour, and it is dimmed for the states that want nothing from you.
Branch names are truncated before counts are: the counts are the point.

Refreshing in every session at once is affordable because this does not sample:
Start-GitRadar.py runs the git commands for the whole machine and this reads what
it published (git_feed.py). Opening a second feed pane costs a file read.

Rows are sorted by session name, not by how much they need attention. This list
doubles as your session list, and a row that jumps while you are reaching for
Enter is worse than one you have to scan for -- attention is carried by colour.

Keys: j/k/g/G move, Enter switches to the session, r refreshes now, f fetches
the selected repository and F fetches every listed one, p pulls it and P pushes
it, q kills the selected session after asking, Ctrl-C closes the pane.

p and P exist because the two counters this pane spends most of its time showing
-- behind and ahead -- were the two it could do nothing about: it would tell you
a repository was four commits behind and then send you elsewhere to act on it.
They act on the selected row and only on it. There is deliberately no pull-all or
push-all to match F: F is affordable because a fetch changes nothing and a
fetch that cannot authenticate costs milliseconds, whereas "pull every repository
on this machine" is a work tree changed in a dozen places from one keystroke.

p is `pull --ff-only`, which is what makes it safe to run from a pane you are
only glancing at: it fast-forwards or it refuses, so it can never open a merge,
never leave a conflicted tree and never want an editor. A row that cannot
fast-forward says so and you go and do it in NeoVim, where you can see it.

None of the three can prompt, by construction -- see fetch_env. This is not
tidiness: capturing their output is not enough to keep it off the screen, because
ssh does not ask for a passphrase on stdout or stderr. It opens /dev/tty and
writes there directly, which lands on this pane behind curses' back; and curses
repaints differentially, so it never paints over cells it does not know were
written. Those "Enter passphrase for key" lines were welded to the pane for
good. So they are given no way to ask -- BatchMode, no controlling terminal --
and one that needed a passphrase fails immediately instead. What it needed is
then asked for in a popup, which is its own pty and takes its own corruption away
with it when it closes: see Show-GitFailure.sh.

That is also what makes F affordable. "Fetch everything and skip whatever would
have asked" needs no detection pass and no list of known-awkward remotes: a
fetch that cannot prompt simply fails in milliseconds, and the row says so.
Failure notes expire on their own (NOTE_TTL) rather than sitting on a row until
the next success, because after an F most of them are answers to a question you
asked about every repository at once, not about that one.

The cursor starts on this pane's own session and is put back there whenever a
client switches into it, so arriving in a session finds its feed already
pointing at it rather than wherever it was last left. The pane cannot see the
switch by itself -- it is not the pane that gains the focus -- so a tmux hook
tells it: see SELF_KEY and modules/tmux/scripts/Sync-RadarSelection.sh.

Enter switches to the selected session and, when that session is sitting on a
radar pane, goes on into its NeoVim pane. On your own row -- where the cursor
now starts -- switch-client alone does nothing, so Enter there means "stop
reading, start working"; a session parked anywhere else is left as you left it.

Ctrl-C closes the pane and nothing else does, deliberately: this is a pane you
leave open and type past, so closing it should take a gesture you cannot make by
accident. q and Esc used to close it and no longer do -- q now kills the selected
*session*, and Esc is ignored.

Killing asks first, in the pane, and the question is modal: y kills, and every
other key -- n, Esc, Ctrl-C, a fumbled letter -- is a no. So while a question is
up Ctrl-C answers it rather than closing the pane; with no question up it closes
the pane as always.

Usage: Watch-GitFeed.py [refresh-seconds]   (default 2)
"""

from __future__ import annotations

import curses
import importlib.util
import os
import subprocess
import sys
import tempfile
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import git_feed as feed  # noqa: E402
import git_radar as gitr  # noqa: E402

sys.path.insert(0, str(gitr.SHARED_SCRIPTS))

import radar_ui as ui  # noqa: E402

# Get-GitState.py owns the vocabulary -- glyphs, state labels, which counters get
# a column and how wide -- and both belong in exactly one place. Its name has a
# hyphen, so it cannot be imported by name; load it from the sibling path
# instead, the same way Watch-AgentFeed.py does.
_spec = importlib.util.spec_from_file_location(
    "get_git_state", os.path.join(HERE, "Get-GitState.py")
)
state_cli = importlib.util.module_from_spec(_spec)
# Registered before it is executed, not after: @dataclass resolves a class's
# annotations through sys.modules[cls.__module__], so a module holding one
# cannot be exec'd while it is still invisible there. (Get-AgentState.py has no
# dataclass, which is the only reason its loader gets away without this.)
sys.modules[_spec.name] = state_cli
_spec.loader.exec_module(state_cli)

# The state marker's colour. It is the only thing always in the same place, so
# it is what the eye lands on first: a red dot three rows down is seen before
# any of the text is.
STATE_COLOUR = {
    gitr.CONFLICTED: curses.COLOR_RED,
    gitr.DIVERGED: curses.COLOR_MAGENTA,
    gitr.DIRTY: curses.COLOR_YELLOW,
    gitr.SYNCED: curses.COLOR_CYAN,
    gitr.CLEAN: curses.COLOR_GREEN,
    # Resolved against the palette size at startup: "bright black" is colour 8,
    # which only exists on a 16-colour terminal. COLOR_BLACK is not a substitute
    # -- on a dark background it is invisible.
    gitr.NOREPO: curses.COLOR_WHITE,
}

# Green added, yellow modified, red deleted, grey untracked: the vocabulary
# every diff already uses. Kept in step with COUNTER_ANSI in Get-GitState.py --
# the same row should not change colour depending on which renderer drew it.
COUNTER_COLOUR = {
    "ahead": curses.COLOR_CYAN,
    "behind": curses.COLOR_MAGENTA,
    "added": curses.COLOR_GREEN,
    "modified": curses.COLOR_YELLOW,
    "deleted": curses.COLOR_RED,
    "untracked": curses.COLOR_WHITE,  # remapped to grey when the palette has one
    "conflicted": curses.COLOR_RED,
}

# The rail marking the session you are in. Blue is the one hue neither a state
# nor a counter claims, so it cannot be misread as either -- see CURRENT_RAIL in
# Get-GitState.py for why this needs a channel of its own at all.
#
# It matters more than it looks: the selection band now comes and goes with the
# pane's focus (ui.Focus), so in a feed you are only glancing at there is no
# highlight on screen at all, and the rail is the only thing saying where you
# are.
RAIL_COLOUR = curses.COLOR_BLUE

# Counters drawn in grey rather than their own hue: untracked files are the one
# count that is usually noise, so it recedes.
GREY_COUNTERS = ("untracked",)

# How loudly the marker is drawn. A green dot on every clean repository is the
# "always present, therefore ignored" problem the status bar has; dimming the
# states that want nothing from you leaves the bright dots meaning something.
STATE_EMPHASIS = {
    gitr.CONFLICTED: curses.A_BOLD,
    gitr.DIVERGED: curses.A_BOLD,
    gitr.DIRTY: curses.A_BOLD,
    gitr.SYNCED: curses.A_NORMAL,
    gitr.CLEAN: curses.A_DIM,
    gitr.NOREPO: curses.A_DIM,
}

EMPTY_MESSAGE = "no tmux sessions"

# The key that means "put the cursor back on my own session's row". Ctrl-O:
# nothing types it at a feed, and it is none of the keys below, so it cannot be
# pressed by accident. Sent by modules/tmux/scripts/Sync-RadarSelection.sh from
# the client-session-changed hook -- the pane cannot see the switch itself,
# because it is not the pane that gains the focus when a client arrives.
SELF_KEY = 15

# How long one of these commands may run before it is abandoned. Generous,
# because a fetch you asked for on a slow link is still a fetch you want; it is a
# thread, so nothing else waits on it.
OP_TIMEOUT = 120

# How many may be in flight at once. F starts one per session, and a machine with
# twenty sessions opening twenty ssh connections at the same moment is rude to
# the remote and slower than doing four at a time. Held on the worker threads
# only -- the curses loop never waits on it.
OP_PARALLEL = 4

# How long a finished note stays on its row. Long enough to read after pressing
# the key, short enough that an F over a dozen repositories does not leave the
# feed papered in stale complaints. Only finished notes expire; a note marking
# work in progress has no deadline, because it ends when the work does.
NOTE_TTL = 8.0

# The errors that mean "no usable credential", as opposed to "no network" or "no
# such remote". Only these are worth offering a key for, and they are the same
# whichever of the three commands hit them.
AUTH_MARKERS = (
    "permission denied",
    "authentication failed",
    "could not read username",
    "could not read password",
    "publickey",
)

# Failures that deserve a phrase of their own rather than git's first line of
# stderr. `git push` is the reason this table exists: its stderr opens with
# "To github.com:owner/repo.git", which is the least useful line there is in a
# column 12% of the window wide, and the fact worth reading -- "(fetch first)",
# "[rejected]" -- is two lines further down. Matched in order, so the first entry
# wins; checked after AUTH_MARKERS, which outrank everything.
REASON_MARKERS = (
    ("not possible to fast-forward", "cannot fast-forward"),
    ("diverging branches", "cannot fast-forward"),
    ("need to specify how to reconcile", "cannot fast-forward"),
    ("[rejected]", "push rejected"),
    ("failed to push some refs", "push rejected"),
)


def fetch_env() -> dict[str, str]:
    """An environment in which nothing here has any way to ask for anything.

    Every prompt path closed at once, because they fail differently and only one
    of them has to be open to put text on this pane:

    Named for the fetch because that is what it was written for, and kept that
    way because it is what the popup and the README both call it. It applies
    unchanged to the other two: a push over ssh reaches for a passphrase by
    exactly the same path.

    - GIT_TERMINAL_PROMPT stops git asking for an https username itself.
    - BatchMode stops ssh asking for a passphrase or a host key confirmation.
      This is the one that matters in practice; it turns the passphrase prompt
      into an immediate "Permission denied (publickey)".
    - SSH_ASKPASS_REQUIRE stops ssh reaching for a graphical asker instead.

    Belt and braces with start_new_session in the worker, which leaves the child
    no controlling terminal at all: BatchMode is a promise ssh makes, and a child
    with no /dev/tty to open cannot break it however it is invoked.
    """
    env = os.environ.copy()
    env["GIT_TERMINAL_PROMPT"] = "0"
    env["GIT_SSH_COMMAND"] = (env.get("GIT_SSH_COMMAND") or "ssh") + " -o BatchMode=yes"
    env["SSH_ASKPASS_REQUIRE"] = "never"
    return env


@dataclass(frozen=True)
class Note:
    """What a fetch, pull or push has to say about a row.

    Frozen so that updating a note is a single dict assignment, which keeps the
    no-lock reasoning below true, and so that == compares by value -- the draw
    loop notices new notes by comparing the whole dict against its last copy.

    `text` is what the row shows; `detail` is the full message the popup shows,
    which is usually several lines and never fits a row.
    """

    text: str
    detail: str = ""
    # A monotonic deadline, or 0 for "until something replaces it" -- a note
    # marking work in progress, which ends when the work does rather than on a
    # clock.
    expires: float = 0.0
    # Whether something is running in this repository right now. This is the
    # re-entrancy guard, and it has to be a flag rather than a comparison
    # against the progress text: notes are keyed by repository root, so with
    # three operations sharing one note "is it fetching?" would happily let a p
    # start on top of an f and leave two git processes fighting over index.lock.
    busy: bool = False


def fetch_argv(repo) -> list[str] | str:
    """`f` and `F`. The one command here that changes nothing locally."""
    return ["git", "--no-optional-locks", "-C", repo.root, "fetch", "--quiet"]


def pull_argv(repo) -> list[str] | str:
    """`p`. Fast-forward or refuse -- see the module docstring for why only that.

    Both refusals are answered from the row that is already on screen rather
    than from the network: git would say the same thing in a paragraph, several
    seconds and one ssh connection later.

    Without --no-optional-locks, unlike the fetch: that flag exists to stop the
    *sampler* taking index.lock out from under an interactive git, and a pull is
    the interactive git it was protecting.
    """
    if repo.branch == gitr.DETACHED:
        return "detached HEAD"
    if not repo.upstream:
        return "no upstream"
    return ["git", "-C", repo.root, "pull", "--ff-only", "--quiet"]


def push_argv(repo) -> list[str] | str:
    """`P`. Sets the upstream when there is none, rather than refusing.

    Publishing a branch you have never pushed is the main thing P is wanted for
    on the rows the feed marks `local`, and the marker disappearing on the next
    tick is the confirmation. Detached is still a refusal: there is no branch to
    name as the upstream.
    """
    if repo.branch == gitr.DETACHED:
        return "detached HEAD"
    if not repo.upstream:
        return [
            "git", "-C", repo.root,
            "push", "--set-upstream", "origin", repo.branch, "--quiet",
        ]
    return ["git", "-C", repo.root, "push", "--quiet"]


@dataclass(frozen=True)
class Op:
    """One of the three things a key here can ask a repository to do.

    Only the command and the words differ between them; the thread, the queue,
    the no-tty environment, the note and the popup are shared, because every one
    of those was written for reasons that have nothing to do with which git
    subcommand is being run.

    `argv` returns the command to run, or a short phrase saying why there is
    none -- "no upstream" on a row that has never been pushed, say. A phrase
    goes straight onto the row: it is an answer the feed already had, and asking
    the network for it would cost a connection to be told what was on screen.
    """

    verb: str
    progress: str
    argv: Callable[[gitr.Repo], "list[str] | str"]


FETCH = Op("fetch", "fetching\u2026", fetch_argv)
PULL = Op("pull", "pulling\u2026", pull_argv)
PUSH = Op("push", "pushing\u2026", push_argv)

# Notes by repository root, so two sessions on one repository both show it -- and
# so the busy flag is a lock on the thing that actually has an index.lock.
# Written by worker threads, read by the draw loop; assignment to a dict is
# atomic under the GIL and nothing here does read-modify-write, so no lock is
# needed.
notes: dict[str, Note] = {}

_op_slots = threading.Semaphore(OP_PARALLEL)


def sample() -> list:
    """The shared snapshot, or a live sample if the sampler is not up yet.

    Falls back so the feed is never blank waiting for a daemon -- and starts one
    for next time. See radar_cache.RadarCache.sample_cached.
    """
    return feed.sample_cached()


def note_key(repo) -> str:
    """Fetch notes hang off the repository, falling back to the session.

    Two sessions in one repository share a note; a session that is not a
    repository at all still needs somewhere to be told so.
    """
    return repo.root or f"session:{repo.session}"


def prune_notes() -> bool:
    """Drop notes whose moment has passed. True when the screen should redraw.

    Called from the loop rather than by a timer thread, so a note never vanishes
    between a draw and the next keystroke's read of it.
    """
    now = time.monotonic()
    stale = [
        key
        for key, note in list(notes.items())
        if note.expires and note.expires <= now
    ]
    for key in stale:
        notes.pop(key, None)
    return bool(stale)


def failure_note(op: Op, message: str) -> Note:
    """Turn git's complaint into a row's worth of words, keeping the rest.

    An authentication failure gets its own short phrase because it is the one
    that is expected: the command was refused a passphrase on purpose, so saying
    "Permission denied (publickey)" on the row would report our own policy back
    to us as if it were news.

    Then REASON_MARKERS, for the failures whose fact is not on the first line --
    a rejected push announces the remote's URL first, and the reason two lines
    down. Only after both does git's own first line stand, which is where it puts
    the fact for everything else.
    """
    lines = message.strip().splitlines()
    lowered = message.lower()
    if any(marker in lowered for marker in AUTH_MARKERS):
        text = f"unable to {op.verb}"
    else:
        text = next(
            (phrase for marker, phrase in REASON_MARKERS if marker in lowered),
            lines[0] if lines else f"{op.verb} failed",
        )
    return Note(text, message.strip(), time.monotonic() + NOTE_TTL)


def show_failure(op: Op, repo, note: Note) -> None:
    """Explain a failure in a popup, where there is room to and it is safe to.

    A popup rather than the pane for two reasons: the feed's column is 12% of the
    window in the default layout, and a popup is a separate pty, so the one thing
    the popup goes on to offer -- typing a passphrase -- cannot leave anything on
    this curses screen. Nothing here touches curses at all; the popup belongs to
    the tmux client, not to this pane, so there is no endwin/reset_prog_mode dance
    to get wrong.

    Through Invoke-Popup.sh, like every other popup here, so SpotlightDimmer's
    spotlight follows it (see modules/tmux/common.conf's `popup` alias for the
    geometry this mirrors).

    The message goes through a file: it is several lines of git stderr and would
    have to survive display-popup's shell as an argument otherwise.

    The verb goes first, because the popup both names the failure and offers to
    retry it after unlocking a key: a passphrase is as likely to be what stopped
    a push as a fetch.

    Failing to open the popup is not a failure of the command -- the row already
    carries the short version -- so every error here is swallowed.
    """
    # The same modules/tmux/scripts radar_ui is imported from, rather than a
    # second way of spelling it.
    popup = os.path.join(str(gitr.SHARED_SCRIPTS), "Invoke-Popup.sh")
    try:
        handle, path = tempfile.mkstemp(prefix="git-feed-fetch-")
        with os.fdopen(handle, "w") as stream:
            stream.write(note.detail or note.text)
    except OSError:
        return

    try:
        subprocess.run(
            [
                "tmux", "display-popup", "-E",
                "-w", "80%", "-h", "60%", "-x", "C", "-y", "C",
                popup,
                os.path.join(HERE, "Show-GitFailure.sh"),
                op.verb, repo.session, repo.root or "", path,
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        # The popup never ran, so it never removed the file it was handed.
        try:
            os.unlink(path)
        except OSError:
            pass


def start_op(repo, op: Op, interactive: bool = True) -> None:
    """Run one command against one repository, on a thread, so the loop never blocks.

    These are the only things in git-radar that touch the network, and they
    happen only because you pressed a key. The sampler stays offline by design --
    see git_radar's module docstring.

    `interactive` is what separates f from F. A command you asked for by name
    gets a popup when it fails, because you are waiting for its answer; one of
    the many F started does not, or a fetch-all across a dozen unreachable
    remotes would bury the feed under a dozen popups. Their rows say
    `unable to fetch` and that is the whole of what F promises. p and P are
    always by name -- there is no all-rows version of either.

    A repository already busy is left alone rather than queued. Two of these in
    one work tree race for index.lock, and a second one you did not notice
    starting is worse than a keypress that visibly did nothing: the row is
    already saying what it is doing.
    """
    key = note_key(repo)
    current = notes.get(key)
    if current is not None and current.busy:
        return
    if not repo.root:
        notes[key] = Note("not a git repository", expires=time.monotonic() + NOTE_TTL)
        return

    argv = op.argv(repo)
    if isinstance(argv, str):
        # A refusal the row could answer without asking anyone. It expires like
        # any other finished note.
        notes[key] = Note(argv, expires=time.monotonic() + NOTE_TTL)
        return

    notes[key] = Note(op.progress, busy=True)

    def worker() -> None:
        # Queue here rather than at the call site: the key press should be
        # acknowledged on the row immediately, even when three fetches are
        # already running ahead of this one.
        with _op_slots:
            try:
                result = subprocess.run(
                    argv,
                    capture_output=True,
                    text=True,
                    check=False,
                    timeout=OP_TIMEOUT,
                    env=fetch_env(),
                    # No stdin and no controlling terminal: the two ways a child
                    # could still have reached a keyboard. See fetch_env.
                    stdin=subprocess.DEVNULL,
                    start_new_session=True,
                )
            except subprocess.TimeoutExpired:
                notes[key] = Note(
                    f"{op.verb} timed out", expires=time.monotonic() + NOTE_TTL
                )
                return
            except OSError as error:
                notes[key] = Note(
                    f"{op.verb} failed", str(error), time.monotonic() + NOTE_TTL
                )
                return

            if result.returncode == 0:
                # The counts come from the next sample, not from here: the
                # sampler is the only thing that decides what a row says.
                notes.pop(key, None)
                return

            note = failure_note(
                op, result.stderr or result.stdout or f"{op.verb} failed"
            )
            notes[key] = note

        # Outside the semaphore: the popup waits for a human, and holding a
        # slot open for as long as it takes to read an error would stall the
        # rest of an F behind it.
        if interactive:
            show_failure(op, repo, note)
            # The popup may have unlocked a key and retried successfully, which
            # moves the refs without this thread ever hearing about it. Clearing
            # the note both tells the loop to resample and stops a stale
            # complaint outliving the fix.
            notes.pop(key, None)

    threading.Thread(target=worker, daemon=True).start()


def start_fetch(repo, interactive: bool = True) -> None:
    """f and F, which are start_op(FETCH) and nothing else."""
    start_op(repo, FETCH, interactive)


# The labels the standard layout gives the radar column and the editor
# (tmux-helpers.sh:label_pane). Enter reads labels rather than pane indexes: the
# indexes are an accident of the order Set-NeovimLayout.sh splits in, while
# @pane_label is what Select-Pane.sh already treats as a pane's identity.
RADAR_LABEL = "Git"
EDITOR_LABEL = "NeoVim"

# Where the editor sits in a window the layout built, for panes that carry no
# label because they were created some other way: Git 0, Agents 1, NeoVim 2.
EDITOR_INDEX = "2"


def window_panes(session: str) -> list[tuple[str, str, str, str]]:
    """A session's current window, as (active, pane id, label, index) rows.

    `-t <session>` lists the current window only -- which is exactly the window
    switch-client is about to land in, so one call answers the whole question
    Enter has to ask.
    """
    fmt = "\t".join(
        ["#{pane_active}", "#{pane_id}", "#{@pane_label}", "#{pane_index}"]
    )
    try:
        result = subprocess.run(
            ["tmux", "list-panes", "-t", f"={session}", "-F", fmt],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return []
    if result.returncode != 0:
        return []
    rows = []
    for line in result.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) == 4:
            rows.append((fields[0], fields[1], fields[2], fields[3]))
    return rows


def editor_pane(session: str) -> str:
    """The pane Enter should land on, or "" to leave the focus where it is.

    Only when the session is already sitting on a radar pane. Pressing Enter
    there is a request to stop reading the list and start working -- and on your
    own row, which is where the cursor now starts, switch-client alone does
    nothing at all, so without this Enter would be a dead key on the one row you
    press it on most.

    A session parked on a terminal or an agent is left exactly as you left it:
    arriving somewhere other than where you were is worse than one extra C-l.
    """
    panes = window_panes(session)
    if not any(
        active == "1" and label == RADAR_LABEL for active, _, label, _ in panes
    ):
        return ""
    for _, pane_id, label, _ in panes:
        if label == EDITOR_LABEL:
            return pane_id
    for _, pane_id, _, index in panes:
        if index == EDITOR_INDEX:
            return pane_id
    return ""


def jump(session: str) -> None:
    """Switch the client to a session, and on into its editor where that applies.

    The switch is one command, unlike the three the agent feed sends: those
    exist to land on a specific *pane* in a specific window, and a session's own
    current window and pane are already where you left them. The second command
    here is not that -- it fires only when where you left them was the radar
    itself (see editor_pane).

    Asked before switching, so the answer describes the session you are going to
    rather than one already half-changed.

    `=` makes the target an exact name rather than an fnmatch pattern, the same
    guard New-CodeSession.sh uses.
    """
    editor = editor_pane(session)
    subprocess.run(
        ["tmux", "switch-client", "-t", f"={session}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if editor:
        subprocess.run(
            ["tmux", "select-pane", "-t", editor],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def session_id(session: str) -> str:
    """A session's `$N` id, or "" if it is gone.

    Worth the extra call: an id is what `kill-session` should be pointed at.
    A name has to be matched with `=` to stop tmux reading it as an fnmatch
    pattern, and a stale name can in principle come back as a *different*
    session; an id cannot. Failing here means the row is stale and there is
    nothing left to kill.

    Read out of `list-sessions` and matched here rather than asked for directly.
    The obvious `display-message -p -t '={session}' '#{session_id}'` looks right
    and is not: on tmux 3.4 it prints an empty line and still exits 0, because
    the format wants a client to resolve against and a session target does not
    give it one. An empty id reported as success is the worst possible answer --
    it would make q silently do nothing -- so this asks a question with no
    client in it at all.
    """
    try:
        result = subprocess.run(
            ["tmux", "list-sessions", "-F", "#{session_id}\t#{session_name}"],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    if result.returncode != 0:
        return ""
    for line in result.stdout.splitlines():
        # Session names cannot contain a tab, so one split is enough -- and the
        # name is compared whole, never matched as a pattern.
        ident, _, name = line.partition("\t")
        if name == session:
            return ident
    return ""


def kill(session: str) -> None:
    """Kill a session. The caller has already asked; this just does it.

    tmux's own `confirm-before` would seem to be the way to ask, and it is not:
    it is built to run from a key binding, where tmux knows which client pressed
    the key. Run as a command from inside a pane it blocks its caller forever
    and draws its prompt on no client at all -- even given `-t`. The question is
    drawn in the pane instead (see `draw_confirm`), which is also the only place
    that already has the keyboard in raw mode.

    Nothing special is done about killing the session this pane is in: it is a
    legitimate thing to want, and tmux already does the right thing -- the
    client moves to another session, or exits when that was the last one.
    """
    target = session_id(session)
    if not target:
        return
    subprocess.run(
        ["tmux", "kill-session", "-t", target],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


# The question q asks before kill() runs. Short words on their own lines: the
# feed's column is 12% of the window in the default layout, so anything phrased
# as a sentence would be truncated into nonsense.
CONFIRM_TITLE = "kill session"
CONFIRM_YES = "y  kill"
CONFIRM_NO = "n  cancel"


def draw_confirm(stdscr, session: str, use_colour: bool, palette) -> None:
    """Take the whole pane for the question, rather than banner it over a row.

    Killing a session is the one thing here that cannot be undone, so it gets
    the one presentation that cannot be misread as part of the list. In a column
    this narrow a banner would sit inside the rows it is asking about and read
    as one of them.
    """
    stdscr.erase()
    height, width = stdscr.getmaxyx()

    def colour(value: int, extra: int = 0) -> int:
        return (palette.attr(value) if use_colour else curses.A_NORMAL) | extra

    lines = [
        (CONFIRM_TITLE, curses.A_DIM),
        # Red is what the state marker already uses for "this one needs you",
        # and the name is the single fact worth reading twice before pressing y.
        (ui.truncate(session, width - 1), colour(curses.COLOR_RED, curses.A_BOLD)),
        ("", curses.A_NORMAL),
        (CONFIRM_YES, colour(curses.COLOR_RED, curses.A_BOLD)),
        (CONFIRM_NO, curses.A_NORMAL),
    ]
    for row, (text, attr) in enumerate(lines):
        if row >= height:
            break
        ui.add(stdscr, row, 0, ui.truncate(text, width - 1), attr)

    stdscr.refresh()


def _row_segments(repo, chosen: bool, width: int, palette, use_colour: bool, band,
                  current: str):
    """The two lines of one entry, as (text, attribute) segments.

    Widths are decided per row rather than per column: the counters are measured
    first and the branch is given whatever is left, so a long branch name is what
    gets truncated in a narrow pane -- never the counts, which are the point.
    """
    body = band if chosen else curses.A_NORMAL
    # Bold only where it distinguishes: bolding every name spends the emphasis
    # that makes the selected row findable.
    name_attr = body | (curses.A_BOLD if chosen else curses.A_NORMAL)

    def coloured(colour: int) -> int:
        if not use_colour:
            return body
        return palette.attr(colour, chosen) | (body & curses.A_REVERSE)

    marker_attr = coloured(STATE_COLOUR[repo.state]) if use_colour else body
    marker_attr |= STATE_EMPHASIS[repo.state]

    # Drawn down both lines, so the whole entry -- not just its first line --
    # reads as the one you are in.
    railed = repo.session == current
    gutter = state_cli.CURRENT_RAIL if railed else " "
    rail_attr = (
        (coloured(RAIL_COLOUR) | curses.A_BOLD) if (use_colour and railed) else body
    )

    first = [
        (gutter, rail_attr),
        (f"{state_cli.marker(repo)} ", marker_attr),
        (ui.truncate(repo.session, width - state_cli.RAIL_WIDTH - 3), name_attr),
    ]

    cells = state_cli.counters(repo)
    measured = sum(len(cell.text) + 1 for cell in cells)
    note = state_cli.upstream_note(repo)
    fetched = notes.get(note_key(repo))
    detail = fetched.text if fetched else repo.detail

    room = width - state_cli.RAIL_WIDTH - len(ui.INDENT) - measured - 1
    if note:
        room -= len(note) + 1
    # A row with no repository has no branch, so the state label takes the slot
    # -- it is the only thing there is to say about it.
    text = state_cli.branch_label(repo) or state_cli.STATE_LABEL[repo.state]
    branch = ui.truncate(text, max(0, room))

    # Dim whether or not the row is selected. The second line is secondary by
    # definition, and un-dimming it on selection made the highlight shout twice
    # -- once with the band, once by brightening text -- in a pane that is
    # usually not even focused.
    second = [
        (gutter, rail_attr),
        (ui.INDENT, body),
        (branch, body | curses.A_DIM),
    ]
    if note:
        second.append((f" {note}", body | curses.A_DIM))
    for cell in cells:
        colour = COUNTER_COLOUR[cell.key]
        attr = coloured(colour) if use_colour else body
        if cell.key in GREY_COUNTERS or not use_colour:
            attr = body | curses.A_DIM
        elif cell.key == "conflicted":
            attr |= curses.A_BOLD
        second.append((f" {cell.text}", attr))
    if detail:
        second.append((f"  {detail}", body | curses.A_DIM))

    return first, second


def draw(stdscr, repos: list, selected: int, use_colour: bool, palette, band,
         focused: bool, current: str, pending: str = "") -> None:
    if pending:
        draw_confirm(stdscr, pending, use_colour, palette)
        return

    stdscr.erase()
    height, width = stdscr.getmaxyx()

    if not repos:
        ui.add(stdscr, 0, 0, EMPTY_MESSAGE, curses.A_DIM)
        stdscr.refresh()
        return

    visible = ui.visible_rows(height)
    first_row = ui.window_start(selected, len(repos), visible)

    for offset, repo in enumerate(repos[first_row : first_row + visible]):
        # No highlight at all in a pane that cannot act on it: see ui.Focus.
        chosen = (first_row + offset == selected) and focused
        line = offset * ui.ROW_LINES
        top, bottom = _row_segments(
            repo, chosen, width, palette, use_colour, band, current
        )
        fill = band if chosen else None
        ui.draw_line(stdscr, line, width, top, fill)
        if line + 1 < height:
            ui.draw_line(stdscr, line + 1, width, bottom, fill)

    stdscr.refresh()


def listed(repos: list, session: str) -> bool:
    """Whether a session has a row yet."""
    return any(repo.session == session for repo in repos)


def index_of(repos: list, session: str, fallback: int) -> int:
    """Re-find the selection after a refresh.

    By session name, never by row: a session opened or closed elsewhere shifts
    every row below it, and an index-based cursor would quietly land on a
    different repository at exactly the moment you are reaching for Enter.
    """
    if not repos:
        return 0
    for row, repo in enumerate(repos):
        if repo.session == session:
            return row
    return max(0, min(fallback, len(repos) - 1))


def run(stdscr, interval: float) -> None:
    curses.curs_set(0)

    # Ctrl-C is the only way out, and it has to close the *pane*. Catching
    # KeyboardInterrupt cannot achieve that -- by the time Python sees it the
    # damage is done elsewhere. The pane is `pwsh -Command "& this" && exit`
    # typed into a shell (tmux-helpers.sh:pwsh_command), so it closes on a clean
    # exit status; SIGINT goes to the whole foreground process group, so pwsh
    # takes it too, dies on the spot and the `&& exit` never runs. That is the
    # shell prompt you are left looking at.
    #
    # raw() turns off ISIG, so the interrupt, quit and suspend characters stop
    # being signals and arrive as ordinary bytes -- Ctrl-C is just key 3 below.
    # Now that it is the only key that closes the feed, this is load-bearing
    # rather than a convenience: without raw() there is no way out at all.
    curses.raw()
    use_colour = curses.has_colors()
    palette, band, grey = ui.start_colour()
    if grey is not None:
        # Untracked files are the one count that is usually noise, and a
        # directory that is not a repository wants nothing at all; both recede
        # to grey where the terminal has one.
        COUNTER_COLOUR["untracked"] = grey
        STATE_COLOUR[gitr.NOREPO] = grey

    # Short enough that keys feel instant, so one loop serves both the timer and
    # the keyboard without a second thread.
    stdscr.timeout(100)

    # The selection band only appears while this pane has the user's attention.
    # A feed is usually something you glance at from another pane, and a
    # permanent highlight there is a cursor that cannot be moved competing with
    # the rows for attention. See ui.Focus.
    focus = ui.Focus(ui.pane_is_focused(), timeout_ms=100)
    focus.start()

    # Resolved once: a pane does not change session, and this must not become a
    # tmux call on the draw path.
    current = gitr.current_session()

    repos = sample()
    # On this pane's own row, not on row 0. Every session has a feed of its own,
    # and the row worth having under the cursor in it is the session you are in
    # -- the same row the rail already marks. See SELF_KEY for the arrivals that
    # happen after startup.
    selected = index_of(repos, current, 0)
    # A session opened seconds ago is not in the shared snapshot yet -- it is
    # published on the sampler's own tick and accepted for up to 15s (see
    # radar_cache) -- so the first samples in a brand new session can be missing
    # the very row this pane wants to start on. Keep homing until it turns up,
    # or a feed opened with the session would sit on row 0 for good.
    homed = listed(repos, current)
    # The session q has asked about and is waiting on an answer for, or "".
    pending = ""
    last_sample = time.monotonic()
    # What the redraw follows: the mtime of the snapshot the sampler publishes.
    # last_sample is only the backstop for when there is none.
    last_generation = feed.generation()
    # Fetch threads change the detail column between samples, and at a three
    # second tick waiting for the next one to notice reads as a dead keypress.
    seen_notes = dict(notes)
    draw(stdscr, repos, selected, use_colour, palette, band, focus.focused, current,
         pending)

    try:
        while True:
            key = stdscr.getch()
            redraw = False

            # Focus events arrive as ordinary keys and must not be read as
            # input; consume() reports which ones they were.
            if key != -1 and focus.consume(stdscr, key):
                redraw = True
                # A question left standing in a pane you have walked away from
                # is one you will answer by accident on the way back. Leaving
                # cancels it.
                if pending and not focus.focused:
                    pending = ""
            # Ctrl-C, and deliberately nothing else, closes the pane. A feed
            # is a pane you leave open and type past, so a single stray
            # keystroke should not be able to close it -- q is one fumbled pane
            # away and Esc is muscle memory from vim. Esc still arrives here and
            # is ignored; ui.Focus has already swallowed the escape *sequences*
            # by now, so what is left is only a real Esc press.
            elif pending:
                # Modal on purpose: while the question is up every key belongs
                # to it, so there is no way to be moving the cursor and
                # confirming a kill in the same keystroke. Only y kills;
                # everything else -- n, Esc, Ctrl-C, a fumbled letter -- is a
                # no, which is the answer a stray keypress should get.
                if key != -1:
                    if key == ord("y"):
                        kill(pending)
                        # Drop the row here: this pane killed the session, so it
                        # knows before any sample could. Only a guess at what
                        # the sampler will say -- if the kill failed, the next
                        # sample brings the row back, which is the right way
                        # round.
                        repos = [row for row in repos if row.session != pending]
                        selected = max(0, min(selected, len(repos) - 1))
                        # Then tell the sampler, so the status bar and any other
                        # feed pane stop showing it too. Not a forced re-read,
                        # which is what this used to do: the published snapshot
                        # is exactly what is out of date, so re-reading it would
                        # put the row straight back until the sampler caught up.
                        feed.request_sample()
                        last_sample = time.monotonic()
                    pending = ""
                    redraw = True
            elif key == 3:  # Ctrl-C
                return
            elif key in (ord("j"), curses.KEY_DOWN):
                selected = min(selected + 1, max(0, len(repos) - 1))
                redraw = True
            elif key in (ord("k"), curses.KEY_UP):
                selected = max(selected - 1, 0)
                redraw = True
            elif key == ord("g"):
                selected = 0
                redraw = True
            elif key == ord("G"):
                selected = max(0, len(repos) - 1)
                redraw = True
            elif key == SELF_KEY:
                # A client has just switched into this pane's session. Below the
                # `pending` branch on purpose: a reset arriving while the kill
                # question is up answers it "no", which is what leaving and
                # coming back should do to a question you walked away from.
                selected = index_of(repos, current, selected)
                homed = homed or listed(repos, current)
                redraw = True
            elif key in (curses.KEY_ENTER, 10, 13):
                if repos:
                    jump(repos[selected].session)
            elif key == curses.KEY_RESIZE:
                redraw = True
            elif key == ord("r"):
                # A real sample, not a re-read: at a three-second tick the
                # snapshot in hand can be most of a tick old, and "refresh now"
                # returning the same numbers reads as a broken key.
                feed.request_sample()
                last_sample = 0
            elif key == ord("f"):
                if repos:
                    start_fetch(repos[selected])
            elif key == ord("F"):
                # Every row, not the reachable ones: start_fetch already
                # collapses two sessions on one repository (its busy guard
                # is keyed by repository root), and a repository that needs a
                # credential we will not give fails in milliseconds rather than
                # blocking, so there is nothing to pre-filter. Silent per repo
                # -- this is one question about all of them, so it is answered
                # on the rows and not in a stack of popups.
                for row in repos:
                    start_fetch(row, interactive=False)
            elif key == ord("p"):
                # Selected row only, and no shifted all-rows twin: see the
                # module docstring for why F has one and these do not.
                if repos:
                    start_op(repos[selected], PULL)
            elif key == ord("P"):
                if repos:
                    start_op(repos[selected], PUSH)
            elif key == ord("q"):
                # Reads as "quit" and used to mean it, which is exactly why it
                # asks before doing anything -- see draw_confirm.
                if repos:
                    pending = repos[selected].session
                    redraw = True

            # Before the comparison below, so an expiry counts as a change and
            # the row is repainted without it.
            if prune_notes():
                redraw = True

            if notes != seen_notes:
                seen_notes = dict(notes)
                # A finished fetch has moved the refs; take a sample now rather
                # than showing the old counts for the rest of the tick -- and
                # the sampler has to take it, since a read here would only
                # return the snapshot that predates the fetch.
                feed.request_sample()
                last_sample = 0
                redraw = True

            # Follow the snapshot's mtime rather than a timer of our own, which
            # would stack with the sampler's three seconds. A stat on each pass
            # of this loop, which already runs ten times a second for the
            # keyboard; the interval survives as the backstop for when there is
            # no sampler publishing at all.
            now = time.monotonic()
            generation = feed.generation()
            fresh = generation != last_generation
            # Not while a question is up: re-sampling can reorder the rows, and
            # the selection would move out from under an answer already being
            # typed. The question names its own session anyway.
            if not pending and (fresh or now - last_sample >= interval):
                anchor = repos[selected].session if repos else ""
                repos = sample()
                selected = index_of(repos, anchor, selected)
                if not homed:
                    selected = index_of(repos, current, selected)
                    homed = listed(repos, current)
                last_sample = now
                last_generation = generation
                redraw = True

            if redraw:
                draw(stdscr, repos, selected, use_colour, palette, band,
                     focus.focused, current, pending)
    finally:
        # Stop asking for focus events before handing the terminal back: the
        # next thing to run in this pane did not ask for them and would read
        # them as keystrokes.
        focus.stop()
        # curses.wrapper restores cooked mode on the way out, but through
        # nocbreak(), whose interaction with raw() ncurses does not promise.
        # Undo raw() with its own opposite: leaving a terminal unable to
        # interrupt anything is a bad way to lose a bet.
        curses.noraw()


def main() -> int:
    try:
        interval = float(sys.argv[1]) if len(sys.argv) > 1 else 2.0
    except ValueError:
        print(f"usage: {os.path.basename(sys.argv[0])} [refresh-seconds]", file=sys.stderr)
        return 2

    try:
        curses.wrapper(run, interval)
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
