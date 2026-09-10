#!/usr/bin/env python3
"""A live feed of every coding agent's state, in a pane you leave open.

Same data as Watch-Agents.sh, different host: a curses screen instead of fzf.
Bound to prefix+t then r (see modules/tmux/common.conf), which opens it through
New-ToolPane.sh so the pane is labelled like every other one. The fzf version
stays on prefix+t then A -- the two are meant to be run side by side.

Why not fzf. fzf is an interactive filter that happens to redraw, and it insists
on being one: a prompt line, a match counter and a header sit above the data, and
every `reload` spins an animated indicator. On a two-second timer in a narrow
pane that is three lines of chrome and a permanent flicker at the edge of vision
-- which is the opposite of what something you glance at should do. curses draws
only what it is asked to, repaints in place, and still gives j/k and Enter.

Two lines per agent: an icon for which agent it is and the session it runs in on
top, the state and whatever it is waiting on underneath, indented to start at
the same column as the session name, and a rail down the left of the agent you
are currently focused on. The session leads because it is the only part of an
entry that is unique -- states repeat down the pane by design -- and which agent
it is costs no columns at all, being an icon in the gutter.
One line per agent was the first shape, and in a 35%-wide pane it padded every
column to the width of the widest row, which turned the list into a
block of grey text. Two lines let each row be exactly as wide as it needs to be.
Watch-GitFeed.py has the same shape for the same reason, and both draw with the
primitives in modules/tmux/scripts/radar_ui.py.

The state word stays padded, unlike the session above it: the vocabulary is five
fixed words, so that column cannot grow to swallow the row, and keeping it
aligned is what lets the details start in the same place down the pane. It has
lost the dot it used to carry -- a mark on every row in the same place is one
you stop seeing, and the colour it carried is now on the icon instead. The fzf
picker keeps it, where the state has no other mark of its own.

Refreshing in every session at once is affordable because this does not sample:
Start-AgentRadar.py samples for the whole machine and this reads what it
published (agent_feed.py). Opening a second feed pane costs a file read per
sample, not another `ps` and a `capture-pane` per agent.

It redraws when the sampler publishes rather than on a timer of its own, which
would stack with the sampler's: a pane closing just after a tick would keep its
row for the rest of that tick and then for the rest of ours.

Keys: j/k/g/G move, Enter jumps to the agent's pane, r refreshes now, Ctrl-C
closes the pane.

Ctrl-C and nothing else, deliberately: this is a pane you leave open and type
past, so closing it should take a gesture you cannot make by accident. q and Esc
used to do it and no longer do.

Usage: Watch-AgentFeed.py [refresh-seconds]   (default 1)
"""

from __future__ import annotations

import curses
import importlib.util
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import agent_feed as feed  # noqa: E402
import agent_radar as radar  # noqa: E402

sys.path.insert(0, str(radar.SHARED_SCRIPTS))

import radar_ui as ui  # noqa: E402

# Get-AgentState.py owns the state vocabulary and the glyph, and both belong in
# exactly one place. Its name has a hyphen, so it cannot be imported by name --
# load it from the sibling path instead. (The debounce moved out of it and into
# agent_feed, where the sampling is.)
_spec = importlib.util.spec_from_file_location(
    "get_agent_state", os.path.join(HERE, "Get-AgentState.py")
)
state_cli = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(state_cli)

# The same colours as the ANSI map in Get-AgentState.py, in curses terms. Green
# belongs to DONE alone -- an agent that finished while you were elsewhere.
#
# Two of these are placeholders resolved against the palette the terminal
# actually has, at startup in run():
#
#   idle     state_cli.IDLE_256, a muted teal, where there are 256 colours.
#            Base cyan is the fallback and is louder than idle deserves, but a
#            16-colour terminal has nothing quieter that is not the text colour.
#   unknown  grey, i.e. "bright black" -- colour 8, which only exists from 16
#            colours up. COLOR_BLACK is not a substitute: on a dark background
#            it is invisible.
COLOUR = {
    radar.BLOCKED: curses.COLOR_RED,
    radar.WORKING: curses.COLOR_YELLOW,
    radar.DONE: curses.COLOR_GREEN,
    radar.IDLE: curses.COLOR_CYAN,
    radar.UNKNOWN: curses.COLOR_WHITE,
}

# Which agent, by colour -- the tools' own hues, so nothing has to be learned:
# Claude Code orange, Copilot purple, and the two remaining ones for Codex and
# opencode. In the feed it colours the agent's icon, which is the only place the
# row says which agent this is at all -- the name is gone. Get-AgentState.py owns
# both the hues and the icons, and the fzf picker still prints the name in
# words.
#
# Starts as the 16-colour fallback and is upgraded to the 256-colour table in
# run(), which is the same shape COLOUR[IDLE] uses below. An agent with no entry
# here -- one the rules matched by a name nobody has picked a colour for -- gets
# a plain terminal icon in the plain text colour rather than borrowing someone
# else's hue, so it is unidentified rather than mislabelled. Adding it here and
# to AGENT_ICON is the fix.
AGENT_COLOUR = dict(state_cli.AGENT_BASIC)

# The rail marking the agent you are focused on. Blue is the one hue none of the
# four states claims, so it cannot be misread as one -- see CURRENT_RAIL in
# Get-AgentState.py for why this needs a channel of its own at all, and
# focused_pane below for how the row is chosen.
RAIL_COLOUR = curses.COLOR_BLUE

# The state word carries the colour, so it is emphasised -- except in the two
# states that are explicitly not asking for you. Idle lost its bold along with
# its green: a pane you have already read should sit quietly under the ones that
# have something to say.
STATE_EMPHASIS = {
    radar.BLOCKED: curses.A_BOLD,
    radar.DONE: curses.A_BOLD,
    radar.WORKING: curses.A_BOLD,
    radar.IDLE: curses.A_NORMAL,
    radar.UNKNOWN: curses.A_DIM,
}

EMPTY_MESSAGE = "no coding agents running"

# The agent icon plus the space after it, and therefore how far the second line
# is indented to line its state word up under the session name.
#
# Two, because these are Nerd Font glyphs from the private use area and the fonts
# that carry them come in a single-advance "Mono" cut -- which is what is
# installed here, and what a terminal grid wants. A double-width cut would draw
# the icon over that trailing space and push the session name one column right
# of the state word underneath it; if that is what you are looking at, the font
# is the thing to change, not this number.
ICON_WIDTH = 2


def sample() -> list:
    """The shared snapshot, smoothed the way polling consumers need.

    Falls back to sampling live if the sampler is not up yet or has just died,
    so the feed is never blank waiting for a daemon -- and starts one for next
    time. See agent_feed.sample_cached.
    """
    return feed.sample_cached()


def jump(pane_id: str) -> None:
    # All three, and in this order -- switch-client alone lands on the session's
    # current window, which is not necessarily the one holding the pane. Lifted
    # from Watch-Agents.sh so both watchers behave identically on Enter.
    for command in ("switch-client", "select-window", "select-pane"):
        subprocess.run(
            ["tmux", command, "-t", pane_id],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )


def state_width(panes: list) -> int:
    """How wide the state word column has to be.

    Padded, unlike the session name above it: the vocabulary is five fixed
    words, so the column can never grow to swallow the row the way a padded
    session or branch column does. Keeping it aligned is what lets the details
    start at the same place down the pane.
    """
    return max(len(state_cli.WAITING_LABEL[pane.state]) for pane in panes)


def focused_pane(panes: list, current: str) -> str:
    """The pane id of the agent you are focused on, or "" if that is not an agent.

    Two halves, and they come from different places. `pane.active` is the
    sampler's: the pane its session would show, published with the snapshot
    because `tmux list-panes -a` already carried it (agent_feed.FIELDS). Whether
    that session is *yours* is the consumer's, from $TMUX_PANE, and cannot be
    published at all -- the sampler is detached and belongs to no session.

    Empty is the common answer and the useful one: focus a Neovim pane, or this
    feed itself, and no row is railed, which is exactly the report "you are not
    in an agent right now". Only the panes list is consulted, so a session with
    no agent in it can never produce a match either.

    Asked per draw rather than per row: it is a scan of a list already in hand,
    not a tmux call. What it must never become is the latter -- one
    `display-message` is ~14ms, and a feed asking on every tick would cost more
    per pane than sampling the whole machine does (see radar_ui.Focus).
    """
    if not current:
        return ""
    for pane in panes:
        if pane.active and pane.session == current:
            return pane.pane_id
    return ""


def _row_segments(pane, chosen: bool, width: int, palette, use_colour: bool, band,
                  state_w: int, focused_id: str):
    """The two lines of one entry, as (text, attribute) segments.

    An icon for which agent it is, then the session, with the state and whatever
    it is waiting on on the line below -- starting at the same column as the
    session name, so the two read as a block rather than a staircase:

        ▎ dev-environment
        ▎ working  ready

    The icon is the only thing in the gutter, and it is the only thing that says
    which agent this is: the name was the same string on nearly every row and
    cost columns a 35%-wide pane does not have. The colour it is drawn in says
    the same thing twice, deliberately -- a glyph you have not learned yet is
    still a hue you have, and a font that cannot draw one still has the other.
    """
    body = band if chosen else curses.A_NORMAL
    # Bold only where it distinguishes: bolding every name spends the emphasis
    # that makes the selected row findable.
    name_attr = body | (curses.A_BOLD if chosen else curses.A_NORMAL)

    def coloured(colour: int) -> int:
        if not use_colour:
            return body
        return palette.attr(colour, chosen) | (body & curses.A_REVERSE)

    state = state_cli.WAITING_LABEL[pane.state]
    state_attr = coloured(COLOUR[pane.state]) | STATE_EMPHASIS[pane.state]
    if chosen:
        state_attr |= curses.A_BOLD

    # Drawn down both lines, so the whole entry -- not just its first line --
    # reads as the one you are in.
    railed = pane.pane_id == focused_id
    gutter = state_cli.CURRENT_RAIL if railed else " "
    rail_attr = (
        (coloured(RAIL_COLOUR) | curses.A_BOLD) if (use_colour and railed) else body
    )

    # Undimmed: A_DIM over a 256-colour hue is what makes orange and mauve
    # converge on the same muddy grey at a glance, which is the one thing this
    # colour exists to prevent.
    icon = state_cli.AGENT_ICON.get(pane.agent, state_cli.UNKNOWN_ICON)
    agent_colour = AGENT_COLOUR.get(pane.agent)
    icon_attr = coloured(agent_colour) if (use_colour and agent_colour) else body

    # Budgets subtract the rail and icon columns and the same trailing column
    # draw_line refuses to write into. Getting this off by one does not overflow
    # -- draw_line clips -- it eats the ellipsis, so a truncated name silently
    # reads as a shorter real one.
    left = state_cli.RAIL_WIDTH + ICON_WIDTH
    first = [
        (gutter, rail_attr),
        (f"{icon} ", icon_attr),
        (ui.truncate(pane.session, width - left - 1), name_attr),
    ]

    # Indented to exactly where the session name starts, which is what makes the
    # entry read as one block. The state word is still padded on top of that:
    # five fixed words cannot grow to swallow the row, and keeping them aligned
    # is what lets the details line up too.
    state_text = f"{state:<{state_w}}"

    # The detail is why a blocked agent is blocked, so there it takes the state's
    # own colour and the row reads as one thing rather than two. Everywhere else
    # it is dim whether or not the row is selected: it is secondary by
    # definition, and un-dimming it on selection made the highlight shout twice
    # -- once with the band, once by brightening text -- in a pane that is
    # usually not even focused.
    detail = state_cli.extra_detail(pane)
    detail_room = width - left - len(state_text) - 3
    detail_text = ui.truncate(detail, detail_room) if detail and detail_room >= 3 else ""

    second = [
        (gutter, rail_attr),
        (" " * ICON_WIDTH, body),
        (state_text, state_attr),
    ]
    if detail_text:
        second.append(
            (
                f"  {detail_text}",
                state_attr
                if pane.state == radar.BLOCKED
                else body | curses.A_DIM,
            )
        )

    return first, second


def draw(stdscr, panes: list, selected: int, use_colour: bool, palette, band,
         focused: bool, current: str) -> None:
    stdscr.erase()
    height, width = stdscr.getmaxyx()

    if not panes:
        ui.add(stdscr, 0, 0, EMPTY_MESSAGE, curses.A_DIM)
        stdscr.refresh()
        return

    state_w = state_width(panes)
    focused_id = focused_pane(panes, current)
    visible = ui.visible_rows(height)
    first_row = ui.window_start(selected, len(panes), visible)

    for offset, pane in enumerate(panes[first_row : first_row + visible]):
        # No highlight at all in a pane that cannot act on it: see ui.Focus.
        chosen = (first_row + offset == selected) and focused
        line = offset * ui.ROW_LINES
        top, bottom = _row_segments(
            pane, chosen, width, palette, use_colour, band, state_w, focused_id
        )
        fill = band if chosen else None
        ui.draw_line(stdscr, line, width, top, fill)
        if line + 1 < height:
            ui.draw_line(stdscr, line + 1, width, bottom, fill)

    stdscr.refresh()


def index_of(panes: list, pane_id: str, fallback: int) -> int:
    """Re-find the selection after a refresh.

    By pane id, never by row: detect() sorts blocked first, so an agent that
    starts waiting *moves*, and an index-based cursor would quietly land on a
    different agent at exactly the moment you are reaching for Enter.
    """
    if not panes:
        return 0
    for row, pane in enumerate(panes):
        if pane.pane_id == pane_id:
            return row
    return max(0, min(fallback, len(panes) - 1))


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
    # Nothing in the pipeline is ever signalled, so the exit status stays ours.
    curses.raw()
    use_colour = curses.has_colors()
    palette, band, grey = ui.start_colour()
    if grey is not None:
        # The state you are explicitly not being asked to look at.
        COLOUR[radar.UNKNOWN] = grey
    if curses.COLORS >= 256:
        # Quiet, but still a colour rather than the colour everything else on
        # the row is already drawn in. See IDLE_256 in Get-AgentState.py.
        COLOUR[radar.IDLE] = state_cli.IDLE_256
        # Orange and mauve do not exist in 16 colours; where they do, take them.
        AGENT_COLOUR.update(state_cli.AGENT_256)

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
    # tmux call on the draw path. Which agent within that session has the focus
    # does change, constantly, and comes off each sample instead -- so the rail
    # follows you at the sampling rate, without asking tmux anything.
    current = radar.current_session()

    panes = sample()
    selected = 0
    last_sample = time.monotonic()
    # What the redraw follows: the mtime of the snapshot the sampler publishes.
    # The interval is only the backstop for when there is no snapshot at all.
    last_generation = feed.generation()
    draw(stdscr, panes, selected, use_colour, palette, band, focus.focused, current)

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
                selected = min(selected + 1, max(0, len(panes) - 1))
                redraw = True
            elif key in (ord("k"), curses.KEY_UP):
                selected = max(selected - 1, 0)
                redraw = True
            elif key == ord("g"):
                selected = 0
                redraw = True
            elif key == ord("G"):
                selected = max(0, len(panes) - 1)
                redraw = True
            elif key in (curses.KEY_ENTER, 10, 13):
                if panes:
                    jump(panes[selected].pane_id)
            elif key == curses.KEY_RESIZE:
                redraw = True
            elif key == ord("r"):
                last_sample = 0

            # A stat on every pass of this loop, which already runs ten times a
            # second for the keyboard -- not a read, since decoding the snapshot
            # each pass would be the per-consumer cost agent_feed.py exists to
            # avoid. The interval covers what an mtime cannot: no daemon up,
            # where generation() is a constant 0.0 and sample() detects live.
            now = time.monotonic()
            generation = feed.generation()
            if generation != last_generation or now - last_sample >= interval:
                anchor = panes[selected].pane_id if panes else ""
                panes = sample()
                selected = index_of(panes, anchor, selected)
                last_sample = now
                last_generation = generation
                redraw = True

            if redraw:
                draw(
                    stdscr, panes, selected, use_colour, palette, band,
                    focus.focused, current,
                )
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
        interval = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0
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
