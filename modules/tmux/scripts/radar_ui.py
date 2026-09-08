"""The curses primitives both radar feeds draw with.

Watch-AgentFeed.py and Watch-GitFeed.py show different things but draw them the
same way: two lines per entry, a coloured marker in the first column, a grey
selection band that reaches the pane edge, and truncation with an ellipsis when
the pane is narrower than the row. That scaffolding is what lives here.

What does *not* live here is what a row says. Each radar composes its own
segments -- which fields, in what order, in which colours -- and hands them to
`draw_line`. The split is the same one radar_cache.py makes: shared mechanism,
per-radar meaning.

It sits under modules/tmux/scripts for the same reason radar_cache.py does: it
belongs to neither radar, and both already reach into this directory.
"""

from __future__ import annotations

import curses
import os
import subprocess
import sys

ELLIPSIS = "…"

# Two lines per entry -- the name on top, its details indented under it. One line
# per entry was what both feeds did first, and in a 35%-wide pane it forced every
# column to be padded to the width of the widest row, which is what made them
# read as a block of grey text rather than a list. Two lines let each row be
# exactly as wide as it needs to be.
ROW_LINES = 2

# Lines the second row up under the first one's text, past the marker and its
# space.
INDENT = "  "


class Palette:
    """curses colour pairs, created the first time each is asked for.

    A row mixes several colours at once -- a state marker plus whatever the
    second line carries -- and each needs a second variant on the selection
    background. Numbering twenty pairs by hand is how you end up with two names
    for one pair, so they are allocated on demand instead.
    """

    def __init__(self, select_bg: int | None) -> None:
        self.select_bg = select_bg
        self._pairs: dict[tuple[int, int], int] = {}
        self._next = 1

    def attr(self, colour: int, selected: bool = False) -> int:
        background = self.select_bg if (selected and self.select_bg is not None) else -1
        key = (colour, background)
        if key not in self._pairs:
            index = self._next
            self._next += 1
            curses.init_pair(index, colour, background)
            self._pairs[key] = index
        return curses.color_pair(self._pairs[key])


def start_colour() -> tuple[Palette | None, int, int | None]:
    """Set up colour and return (palette, selection-band attribute, grey).

    Both greys are resolved against the palette the terminal actually has. 8 is
    "bright black", which exists only from 16 colours up; COLOR_BLACK is not a
    substitute, as on a dark background it is invisible. 237 is a 256-colour dark
    grey, close to fzf's own bg+ and dark enough to sit under coloured text.

    The band is a background, not an inversion. fzf's selected row keeps the
    text's own colours and bolds them; A_REVERSE would swap foreground and
    background and throw every colour away on the one row you are looking
    hardest at. Only where the terminal cannot express a background does this
    fall back to inverting.
    """
    if not curses.has_colors():
        return None, curses.A_REVERSE, None

    curses.use_default_colors()
    grey = 8 if curses.COLORS >= 16 else None
    select_bg = 237 if curses.COLORS >= 256 else (8 if curses.COLORS >= 16 else None)
    palette = Palette(select_bg)
    if select_bg is None:
        # An 8-colour terminal still gets coloured rows; it just has no grey to
        # make a band out of, so only the highlight degrades.
        return palette, curses.A_REVERSE, grey
    return palette, palette.attr(-1, selected=True) | curses.A_BOLD, grey


def truncate(text: str, width: int) -> str:
    """Cut to `width` characters, marking that something was cut.

    A pane at 35% is often narrower than a session or branch name, and a name
    silently sliced mid-word reads as a different name. The ellipsis is one
    character, so a width of 1 or less can only be the ellipsis itself.
    """
    if width <= 0:
        return ""
    if len(text) <= width:
        return text
    if width == 1:
        return ELLIPSIS
    return text[: width - 1] + ELLIPSIS


def add(stdscr, row: int, column: int, text: str, attr: int) -> int:
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


def draw_line(stdscr, row: int, width: int, segments, fill_attr=None) -> None:
    """Draw one line of (text, attribute) segments, optionally banded to the edge.

    The band has to reach the pane edge, or the highlight stops wherever the
    longest segment happened to end and reads as a smudge rather than a selected
    row.
    """
    column = 0
    for text, attr in segments:
        if not text or column >= width - 1:
            continue
        column = add(stdscr, row, column, text[: width - column - 1], attr)
    if fill_attr is not None and column < width - 1:
        add(stdscr, row, column, " " * (width - column - 1), fill_attr)


def window_start(selected: int, count: int, visible: int) -> int:
    """Which entry the pane starts at, keeping the selected one on screen.

    Scrolls by entry, not by line: half a row at the top of the pane is worse
    than one fewer row.
    """
    if count <= visible:
        return 0
    return max(0, min(selected - visible + 1, count - visible))


def visible_rows(height: int) -> int:
    return max(1, height // ROW_LINES)


# --- Focus -------------------------------------------------------------------
# A feed pane is usually *not* the pane you are typing in -- that is the point of
# it -- so a selection band sitting there permanently is a highlight that means
# nothing, competing for attention with the rows it is drawn among. The cursor
# is only worth showing while the pane can act on it, so the highlight goes away
# with the focus and comes back with it.
#
# The mechanism is the terminal's own: an application asks for focus reporting
# with CSI ?1004h, and the terminal sends CSI I when it gains focus and CSI O
# when it loses it. tmux forwards those to the pane, and modules/tmux/common.conf
# already sets `focus-events on`, which is what makes it do so.
#
# The alternative was polling tmux, and it is worth saying why not: one
# `tmux display-message` costs about 14ms, so asking often enough for the band to
# fade promptly would cost more per feed pane than sampling the whole machine
# does. Events cost nothing and arrive immediately.

# ncurses 6.3 and later decode the two sequences itself and hands them over as
# named keys, so the usual escape-sequence disambiguation is not needed. The
# numbers it assigns are allocated at runtime, hence matching on the name.
FOCUS_IN_NAME = b"kxIN"
FOCUS_OUT_NAME = b"kxOUT"

# How long to wait for the rest of a sequence after a bare ESC, on a terminal
# whose ncurses did not decode it. Long enough that the bytes of a real sequence
# have arrived (they come in one write), short enough that a real Esc keypress
# still feels instant.
ESC_PEEK_MS = 10

# A CSI sequence ends at the first byte in 0x40-0x7e. The cap is only so that a
# terminal emitting nonsense cannot hold the loop.
MAX_SEQUENCE = 16


def _write_raw(sequence: str) -> None:
    """Send a terminal mode sequence out of band of curses' own output.

    Safe to do while curses is up: mode sequences neither draw nor move the
    cursor, so they cannot desynchronise its idea of the screen.
    """
    try:
        sys.stdout.write(sequence)
        sys.stdout.flush()
    except (OSError, ValueError):
        pass


def _key_name(key: int) -> bytes:
    if key < 0:
        return b""
    try:
        return curses.keyname(key)
    except (ValueError, OverflowError):
        return b""


def pane_is_focused() -> bool:
    """Whether this pane is the one being looked at. Asked once, at startup.

    Focus events report transitions, not state, so something has to establish
    the starting point. A feed opened by New-ToolPane.sh is the freshly split
    and therefore active pane, but Set-NeovimLayout.sh moves focus away right
    afterwards, and that can happen before this process has asked for focus
    reporting at all -- so the transition would be missed.

    Fails open: if tmux cannot be asked, assume focused, because a highlight
    that is wrongly present is a much smaller problem than a cursor that can
    never be seen.
    """
    pane = os.environ.get("TMUX_PANE")
    if not pane:
        return True
    try:
        result = subprocess.run(
            [
                "tmux",
                "display-message",
                "-p",
                "-t",
                pane,
                "#{pane_active}\t#{window_active}\t#{session_attached}",
            ],
            capture_output=True,
            text=True,
            check=False,
            timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return True
    if result.returncode != 0:
        return True
    fields = result.stdout.strip().split("\t")
    if len(fields) != 3:
        return True
    pane_active, window_active, attached = fields
    return pane_active == "1" and window_active == "1" and attached not in ("", "0")


class Focus:
    """Tracks whether the pane has the user's attention.

    Consumers call `consume` with every key they read; it returns True for the
    keys that were focus events and should not be treated as input.
    """

    def __init__(self, focused: bool = True, timeout_ms: int = 100) -> None:
        self.focused = focused
        self.timeout_ms = timeout_ms

    def start(self) -> None:
        _write_raw("\033[?1004h")

    def stop(self) -> None:
        _write_raw("\033[?1004l")

    def consume(self, stdscr, key: int) -> bool:
        name = _key_name(key)
        if name == FOCUS_IN_NAME:
            self.focused = True
            return True
        if name == FOCUS_OUT_NAME:
            self.focused = False
            return True
        if key == 27:
            return self._consume_escape(stdscr)
        return False

    def _consume_escape(self, stdscr) -> bool:
        """Handle a bare ESC on a terminal whose ncurses did not decode focus.

        Returns True when the ESC began a sequence -- which is then swallowed
        whole, so no stray bytes reach the key handler -- and False when it was
        a real Esc keypress for the caller to act on.
        """
        stdscr.timeout(ESC_PEEK_MS)
        try:
            following = stdscr.getch()
            if following != ord("["):
                if following != -1:
                    curses.ungetch(following)
                return False
            final = -1
            for _ in range(MAX_SEQUENCE):
                byte = stdscr.getch()
                if byte == -1:
                    break
                final = byte
                if 0x40 <= byte <= 0x7E:
                    break
            if final == ord("I"):
                self.focused = True
            elif final == ord("O"):
                self.focused = False
            return True
        finally:
            stdscr.timeout(self.timeout_ms)
