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
the selected repository, Ctrl-C closes the pane.

Ctrl-C and nothing else, deliberately: this is a pane you leave open and type
past, so closing it should take a gesture you cannot make by accident. q and Esc
used to do it and no longer do.

Usage: Watch-GitFeed.py [refresh-seconds]   (default 2)
"""

from __future__ import annotations

import curses
import importlib.util
import os
import subprocess
import sys
import threading
import time

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

# How long a fetch may run before it is abandoned. Generous, because a fetch you
# asked for on a slow link is still a fetch you want; it is a thread, so nothing
# else waits on it.
FETCH_TIMEOUT = 120

FETCHING = "fetching\u2026"

# Fetch notes by repository root, so two sessions on one repository both show it.
# Written by fetch threads, read by the draw loop; assignment to a dict is atomic
# under the GIL and nothing here does read-modify-write, so no lock is needed.
notes: dict[str, str] = {}


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


def start_fetch(repo) -> None:
    """Fetch one repository, on a thread, so the curses loop never blocks.

    This is the only thing in git-radar that touches the network, and it happens
    only because you pressed a key. The sampler stays offline by design -- see
    git_radar's module docstring.
    """
    key = note_key(repo)
    if notes.get(key) == FETCHING:
        return
    if not repo.root:
        notes[key] = "not a git repository"
        return

    notes[key] = FETCHING

    def worker() -> None:
        try:
            result = subprocess.run(
                ["git", "--no-optional-locks", "-C", repo.root, "fetch", "--quiet"],
                capture_output=True,
                text=True,
                check=False,
                timeout=FETCH_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            notes[key] = "fetch timed out"
            return
        except OSError as error:
            notes[key] = f"fetch failed: {error}"
            return

        if result.returncode == 0:
            # The counts come from the next sample, not from here: the sampler is
            # the only thing that decides what a row says.
            notes.pop(key, None)
        else:
            # git puts the useful line first and the context after it.
            message = (result.stderr or result.stdout).strip().splitlines()
            notes[key] = message[0] if message else "fetch failed"

    threading.Thread(target=worker, daemon=True).start()


def jump(session: str) -> None:
    """Switch the client to a session.

    One command, unlike the three the agent feed sends: those exist to land on a
    specific *pane*, and a session's own current window and pane are already
    where you left them.

    `=` makes the target an exact name rather than an fnmatch pattern, the same
    guard New-CodeSession.sh uses.
    """
    subprocess.run(
        ["tmux", "switch-client", "-t", f"={session}"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


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
    detail = notes.get(note_key(repo), repo.detail)

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
         focused: bool, current: str) -> None:
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
    selected = 0
    last_sample = time.monotonic()
    # Fetch threads change the detail column between samples, and at a three
    # second tick waiting for the next one to notice reads as a dead keypress.
    seen_notes = dict(notes)
    draw(stdscr, repos, selected, use_colour, palette, band, focus.focused, current)

    try:
        while True:
            key = stdscr.getch()
            redraw = False

            # Focus events arrive as ordinary keys and must not be read as
            # input; consume() reports which ones they were.
            if key != -1 and focus.consume(stdscr, key):
                redraw = True
            # Ctrl-C, and deliberately nothing else. A feed is a pane you
            # leave open and type past, so a single stray keystroke should not
            # be able to close it -- q is one fumbled pane away and Esc is
            # muscle memory from vim. Esc still arrives here and is ignored;
            # ui.Focus has already swallowed the escape *sequences* by now, so
            # what is left is only a real Esc press.
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
            elif key in (curses.KEY_ENTER, 10, 13):
                if repos:
                    jump(repos[selected].session)
            elif key == curses.KEY_RESIZE:
                redraw = True
            elif key == ord("r"):
                last_sample = 0
            elif key == ord("f"):
                if repos:
                    start_fetch(repos[selected])

            if notes != seen_notes:
                seen_notes = dict(notes)
                # A finished fetch has moved the refs; take a sample now rather
                # than showing the old counts for the rest of the tick.
                last_sample = 0
                redraw = True

            now = time.monotonic()
            if now - last_sample >= interval:
                anchor = repos[selected].session if repos else ""
                repos = sample()
                selected = index_of(repos, anchor, selected)
                last_sample = now
                redraw = True

            if redraw:
                draw(stdscr, repos, selected, use_colour, palette, band, focus.focused, current)
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
