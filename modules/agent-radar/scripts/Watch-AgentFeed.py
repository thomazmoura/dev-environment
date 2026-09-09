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

Two lines per agent: the state and the session on top -- the two things you
scan for -- with what kind of agent it is and whatever it is waiting on indented
underneath, and a rail down the left of the agent you are currently focused on.
One line per agent was the first shape, and in a 35%-wide pane it padded every
column to the width of the widest row, which turned the list into a
block of grey text. Two lines let each row be exactly as wide as it needs to be.
Watch-GitFeed.py has the same shape for the same reason, and both draw with the
primitives in modules/tmux/scripts/radar_ui.py.

The state word stays padded, unlike anything on the second line: the vocabulary
is five fixed words, so that column cannot grow to swallow the row, and keeping
it aligned is what lets the session names start in the same place down the pane.
A `waiting` row therefore lands where you last saw one.

Refreshing once a second, in every session at once, is affordable because this
does not sample: Start-AgentRadar.py samples for the whole machine and this
reads what it published (agent_feed.py). Opening a second feed pane costs a file
read per second, not another `ps` and a `capture-pane` per agent.

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
# opencode. It is a second axis from the state, and it gets the second line the
# way the state gets the first; Get-AgentState.py owns both tables.
#
# Starts as the 16-colour fallback and is upgraded to the 256-colour table in
# run(), which is the same shape COLOUR[IDLE] uses below. An agent with no entry
# here -- one the rules matched by a name nobody has picked a colour for -- keeps
# the plain dim second line rather than borrowing someone else's hue.
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

# The narrowest the agent name is allowed to be squeezed before the detail beside
# it starts giving way instead. Enough to tell "Claude C…" from "Codex".
MIN_AGENT = 8


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

    Padded, unlike anything on the second line: the vocabulary is five fixed
    words, so the column can never grow to swallow the row the way a padded
    session or branch column does. Keeping it aligned is what lets the session
    names start at the same place down the pane.
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

    State and session on top -- the two things you are scanning for -- with what
    kind of agent it is and whatever it is waiting on indented underneath.
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

    # Budgets subtract the rail's column and the same trailing column draw_line
    # refuses to write into. Getting this off by one does not overflow --
    # draw_line clips -- it eats the ellipsis, so a truncated name silently
    # reads as a shorter real one.
    marker = f"{state_cli.GLYPH} {state:<{state_w}}  "
    first = [
        (gutter, rail_attr),
        (marker, state_attr),
        (
            ui.truncate(
                pane.session, width - state_cli.RAIL_WIDTH - len(marker) - 1
            ),
            name_attr,
        ),
    ]

    # The detail is the one thing on the second line worth colouring: it is why
    # a blocked agent is blocked. It takes the state's own colour so the row
    # reads as one thing rather than two.
    detail = state_cli.extra_detail(pane)
    agent = state_cli.agent_line(pane)
    budget = width - state_cli.RAIL_WIDTH - len(ui.INDENT) - 1

    # The detail is the more actionable half, so it is measured first and the
    # agent name gets what is left -- but never less than MIN_AGENT, because an
    # agent name squeezed to nothing leaves the line starting with stray indent
    # and reads as a rendering fault rather than as a narrow pane.
    room = max(MIN_AGENT, budget - len(detail) - 2) if detail else budget
    agent_text = ui.truncate(agent, min(room, budget))
    detail_room = budget - len(agent_text) - 2
    detail_text = ui.truncate(detail, detail_room) if detail and detail_room >= 3 else ""

    # The agent name is what carries the hue, and it carries it undimmed: A_DIM
    # over a 256-colour hue is what makes orange and mauve converge on the same
    # muddy grey at a glance, which is the one thing this colour exists to
    # prevent. It is still not emphasis -- the colour tells you which tool, the
    # first line still owns whether it wants you. An agent with no colour of its
    # own falls back to the dim grey the whole line used to be.
    agent_colour = AGENT_COLOUR.get(pane.agent)
    agent_attr = (
        coloured(agent_colour)
        if (use_colour and agent_colour is not None)
        else body | curses.A_DIM
    )

    second = [
        (gutter, rail_attr),
        (ui.INDENT, body),
        (agent_text, agent_attr),
    ]
    # The detail stays dim whether or not the row is selected. It is secondary by
    # definition, and un-dimming it on selection made the highlight shout twice
    # -- once with the band, once by brightening text -- in a pane that is
    # usually not even focused.
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

            now = time.monotonic()
            if now - last_sample >= interval:
                anchor = panes[selected].pane_id if panes else ""
                panes = sample()
                selected = index_of(panes, anchor, selected)
                last_sample = now
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
