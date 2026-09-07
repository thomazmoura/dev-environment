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

The state column comes first here, too. It is the column you are watching; a
`waiting` row should land in the same place every time rather than sliding
horizontally as session names change width.

Refreshing once a second, in every session at once, is affordable because this
does not sample: Start-AgentRadar.py samples for the whole machine and this
reads what it published (agent_feed.py). Opening a second feed pane costs a file
read per second, not another `ps` and a `capture-pane` per agent.

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

# Get-AgentState.py owns the state vocabulary and the glyph, and both belong in
# exactly one place. Its name has a hyphen, so it cannot be imported by name --
# load it from the sibling path instead. (The debounce moved out of it and into
# agent_feed, where the sampling is.)
_spec = importlib.util.spec_from_file_location(
    "get_agent_state", os.path.join(HERE, "Get-AgentState.py")
)
state_cli = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(state_cli)

# Same four colours as the ANSI map in Get-AgentState.py, in curses terms. Each
# state needs two pairs, because the selected row keeps its state colour and
# changes only its background -- see SELECT_BG.
PAIR = {
    radar.BLOCKED: 1,
    radar.WORKING: 2,
    radar.IDLE: 3,
    radar.UNKNOWN: 4,
}
SELECTED_PAIR = {state: pair + 4 for state, pair in PAIR.items()}

# The row's uncoloured text (session, label, agent, detail) while selected:
# terminal default foreground on the selection background.
BODY_SELECTED_PAIR = 9

COLOUR = {
    radar.BLOCKED: curses.COLOR_RED,
    radar.WORKING: curses.COLOR_YELLOW,
    radar.IDLE: curses.COLOR_GREEN,
    # Resolved against the palette size at startup: "bright black" is colour 8,
    # which only exists on a 16-colour terminal. COLOR_BLACK is not a substitute
    # -- on a dark background it is invisible.
    radar.UNKNOWN: curses.COLOR_WHITE,
}

# The state word carries the colour, so it is emphasised; unknown is the one
# state you are explicitly not being asked to look at.
STATE_EMPHASIS = {
    radar.BLOCKED: curses.A_BOLD,
    radar.WORKING: curses.A_BOLD,
    radar.IDLE: curses.A_BOLD,
    radar.UNKNOWN: curses.A_DIM,
}

EMPTY_MESSAGE = "no coding agents running"


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


def columns(panes: list) -> tuple[int, int, int, int]:
    """Widths for the padded columns, measured in characters.

    Characters, not bytes: the glyph is multi-byte, and a byte-counting padder
    silently under-pads every row (the same reason Get-AgentState.py formats in
    Python rather than awk).
    """
    return (
        max(len(state_cli.WAITING_LABEL[p.state]) for p in panes),
        max(len(p.session) for p in panes),
        max(len(p.label) for p in panes),
        max(len(p.agent) for p in panes),
    )


def draw(stdscr, panes: list, selected: int, use_colour: bool, use_band: bool) -> None:
    stdscr.erase()
    height, width = stdscr.getmaxyx()

    if not panes:
        _add(stdscr, 0, 0, EMPTY_MESSAGE, curses.A_DIM)
        stdscr.refresh()
        return

    state_w, session_w, label_w, agent_w = columns(panes)

    # More agents than lines is rare but must not hide the cursor, so scroll the
    # window rather than the list: keep the selected row on screen and show the
    # top of the list (where blocked agents sort) whenever it fits.
    first = max(0, min(selected - height + 1, len(panes) - height)) if len(panes) > height else 0

    for row, pane in enumerate(panes[first : first + height]):
        state = state_cli.WAITING_LABEL[pane.state]
        chosen = first + row == selected

        # fzf's selected row is a grey band with the text's own colours intact
        # and bolded -- not an inversion. A_REVERSE would swap foreground and
        # background, which throws the state colour away on the one row you are
        # looking hardest at, so the highlight is a background instead. Only
        # where the terminal cannot express one does it fall back to inverting.
        if chosen and use_band:
            body_attr = curses.color_pair(BODY_SELECTED_PAIR) | curses.A_BOLD
        elif chosen:
            body_attr = curses.A_REVERSE
        else:
            body_attr = curses.A_NORMAL

        state_attr = body_attr
        if use_colour:
            pairs = SELECTED_PAIR if chosen and use_band else PAIR
            # color_pair() replaces the attribute rather than adding to it, so
            # the inverting fallback has to be carried over by hand.
            state_attr = curses.color_pair(pairs[pane.state]) | (body_attr & curses.A_REVERSE)
        state_attr |= STATE_EMPHASIS[pane.state] | (curses.A_BOLD if chosen else 0)

        column = 0
        cell = f"{state_cli.GLYPH} {state:<{state_w}}"
        column = _add(stdscr, row, column, cell[: width - column - 1], state_attr)

        body = (
            f"  {pane.session:<{session_w}}  {pane.label:<{label_w}}"
            f"  {pane.agent:<{agent_w}}"
        )
        column = _add(stdscr, row, column, body[: width - column - 1], body_attr)

        # A detail that only repeats the state word is noise in a column that
        # already says it -- "working  working".
        extra = "" if pane.detail == state else pane.detail
        if extra and column < width - 3:
            column = _add(
                stdscr,
                row,
                column,
                f"  {extra}"[: width - column - 1],
                # Dim is how the detail stays secondary in a resting row; on the
                # selected one the band already separates it, and dim over grey
                # is just hard to read.
                body_attr if chosen else body_attr | curses.A_DIM,
            )

        # The band has to reach the edge of the pane, or the highlight stops
        # wherever the longest column happened to end and reads as a smudge
        # rather than a selected row.
        if chosen and column < width:
            _add(stdscr, row, column, " " * (width - column - 1), body_attr)

    stdscr.refresh()


def _add(stdscr, row: int, column: int, text: str, attr: int) -> int:
    """Write text and return where the next column starts.

    curses raises when a write reaches the last cell of the last line, which is
    a normal thing to happen in a pane too narrow for the row. Nothing useful
    can be drawn past the edge, so swallow it.
    """
    if not text:
        return column
    try:
        stdscr.addstr(row, column, text, attr)
    except curses.error:
        pass
    return column + len(text)


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
    use_colour = curses.has_colors()
    use_band = False
    if use_colour:
        curses.use_default_colors()
        # Two greys, both resolved against the palette the terminal actually
        # has. 8 is "bright black", which exists only from 16 colours up;
        # COLOR_BLACK is not a substitute, as on a dark background it is
        # invisible. 237 is a 256-colour dark grey, close to fzf's own bg+ and
        # dark enough to sit under coloured text.
        grey = 8 if curses.COLORS >= 16 else COLOUR[radar.UNKNOWN]
        select_bg = 237 if curses.COLORS >= 256 else (8 if curses.COLORS >= 16 else -1)
        # An 8-colour terminal still gets coloured state words; it just has no
        # grey to make a band out of, so only the highlight degrades.
        use_band = select_bg != -1
        for state, pair in PAIR.items():
            colour = grey if state == radar.UNKNOWN else COLOUR[state]
            curses.init_pair(pair, colour, -1)
            if use_band:
                curses.init_pair(SELECTED_PAIR[state], colour, select_bg)
        if use_band:
            curses.init_pair(BODY_SELECTED_PAIR, -1, select_bg)

    # Short enough that keys feel instant, so one loop serves both the timer and
    # the keyboard without a second thread.
    stdscr.timeout(100)

    panes = sample()
    selected = 0
    last_sample = time.monotonic()
    draw(stdscr, panes, selected, use_colour, use_band)

    while True:
        key = stdscr.getch()
        redraw = False

        if key in (ord("q"), 27):
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
            draw(stdscr, panes, selected, use_colour, use_band)


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
