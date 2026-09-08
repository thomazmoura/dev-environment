#!/usr/bin/env python3
"""Prints one row per tmux session: where its repository stands.

    ▎● session  branch  state  ⇡ahead ⇣behind +added ~modified -deleted ?untracked

The rail in the first column marks the session this is running in.

A counter appears only when it is non-zero, and each has its own colour -- green
added, yellow modified, red deleted, grey untracked -- so a row can be answered
without being read. The marker carries the state.

Presentation lives here rather than in the consumers, for the same reason it
does in Get-AgentState.py: the counter glyphs are multi-byte, and `awk`'s
printf %-*s counts BYTES, so a shell-side formatter silently under-pads every
row. Python counts characters. Watch-GitFeed.py imports this module -- the
vocabulary, the colours and the truncation rule -- so the curses feed and the
CLI cannot disagree about what a row means. Only the layout differs: the feed
gives each session two lines, this gives it one, because a line here is a record
to grep or hand to fzf and a record that wraps stops being one.

  table   the default; padded and coloured, for typing at a prompt
  tsv     machine-readable
  json    everything, including the repository root
  fzf     session TAB <padded, ANSI-coloured row>, for a picker
  status  #[fg=...] counts, for a tmux status-bar segment

Where the data comes from is a separate axis from how it is formatted. By
default this samples live. `--cached` reads the shared snapshot published by
Start-GitRadar.py instead, so a consumer costs a file read no matter how many
consumers there are; see modules/tmux/scripts/radar_cache.py.

Usage:
  Get-GitState.py                   # sampled live, human-readable
  Get-GitState.py --cached          # the shared snapshot
  Get-GitState.py --format=json
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import git_feed as feed  # noqa: E402
import git_radar as gitr  # noqa: E402

# Each counter is its own colour, and only appears when it is non-zero. Both
# halves of that matter for a pane you glance at rather than read: a row of
# "+0 ~0 -0 ?0" in one colour is a wall of text that has to be parsed before it
# can be dismissed, whereas a lone green +2 is read without reading.
#
# The order is the order you act in: pull or push first, then look at what is
# uncommitted. Glyphs are deliberately not emoji -- emoji are double-width, and
# a column of them misaligns under every padding scheme that does not carry a
# wcwidth table.
COUNTERS = (
    ("ahead", "\u21e1"),      # commits to push
    ("behind", "\u21e3"),     # commits to pull
    ("added", "+"),
    ("modified", "~"),
    ("deleted", "-"),
    ("untracked", "?"),
    ("conflicted", "!"),
)

# Green added, yellow modified, red deleted, grey untracked -- the vocabulary
# every diff already uses, so it needs no learning.
#
# The two arrows take cyan and magenta rather than the green/red a lot of prompts
# give them, so that green and red keep meaning "added" and "deleted" and nothing
# else on the row. Cyan and magenta are also the colours the SYNCED and DIVERGED
# states already use for the marker, so an unpushed row and its arrow agree.
COUNTER_ANSI = {
    "ahead": "\033[36m",
    "behind": "\033[35m",
    "added": "\033[32m",
    "modified": "\033[33m",
    "deleted": "\033[31m",
    "untracked": "\033[90m",
    "conflicted": "\033[91m",
}

ANSI = {
    gitr.CONFLICTED: "\033[91m",  # bright red -- the row you opened the list for
    gitr.DIVERGED: "\033[95m",    # magenta: ahead *and* behind, a merge is coming
    gitr.DIRTY: "\033[33m",
    gitr.SYNCED: "\033[36m",      # cyan: committed, just not pushed or pulled
    gitr.CLEAN: "\033[32m",
    gitr.NOREPO: "\033[90m",
}
RESET = "\033[0m"
DIM = "\033[2m"

# Catppuccin Mocha, matching the rest of the status bar.
TMUX_COLOUR = {
    gitr.CONFLICTED: "#f38ba8",
    gitr.DIVERGED: "#cba6f7",
    gitr.DIRTY: "#f9e2af",
    gitr.SYNCED: "#89dceb",
    gitr.CLEAN: "#a6e3a1",
    gitr.NOREPO: "#6c7086",
}

STATE_LABEL = {
    gitr.CONFLICTED: "conflict",
    gitr.DIVERGED: "diverged",
    gitr.DIRTY: "dirty",
    gitr.SYNCED: "unpushed",
    gitr.CLEAN: "clean",
    gitr.NOREPO: "not a repo",
}

# The session you are in right now, marked in a gutter column of its own.
#
# It needs a channel no other signal is using, and the row has none left: the
# marker's colour is the state, bold is the selected row, and the background is
# the selection band. So it gets its own column, and blue -- the one hue neither
# a state nor a counter claims. In the feed the rail is drawn down both lines of
# the entry, which is what makes it findable without being read.
#
# It is emphatically not the same thing as the selection. The band says where
# your cursor is; the rail says where you are.
CURRENT_RAIL = "\u258e"
RAIL_ANSI = "\033[94m"
RAIL_WIDTH = 1

# One glyph per row, coloured by state. It is the only thing on the row that is
# always in the same place, so it is what the eye lands on first -- a red dot
# three rows down is seen before any of the text is.
MARKER = "\u25cf"
MARKER_NOREPO = "\u00b7"

# What the branch column shows when HEAD is not on one. Shorter than git's own
# "(detached)" because this column sits next to real branch names and should not
# be the widest thing in it.
DETACHED_LABEL = "detached"

# Said of a branch with no upstream. Without it, "only show non-zero counters"
# would render a branch you have never pushed identically to one that is fully
# in sync -- which is the one case where an absent arrow means the opposite of
# what it usually does.
LOCAL_NOTE = "local"



@dataclass
class Cell:
    """One non-zero counter as it is drawn: its glyph, its value, its colour."""

    key: str
    glyph: str
    value: int

    @property
    def text(self) -> str:
        return f"{self.glyph}{self.value}"


def marker(repo: gitr.Repo) -> str:
    return MARKER_NOREPO if repo.state == gitr.NOREPO else MARKER


def branch_label(repo: gitr.Repo) -> str:
    """The branch, or "" where there is no repository to have one.

    Empty rather than "not a repo": the callers that have a state column
    already say it there, and the one that does not (the feed) substitutes the
    state label itself. Saying it twice on one row is worse than either.
    """
    if repo.state == gitr.NOREPO:
        return ""
    if repo.branch == gitr.DETACHED:
        return DETACHED_LABEL
    return repo.branch


def upstream_note(repo: gitr.Repo) -> str:
    if repo.state == gitr.NOREPO or repo.upstream:
        return ""
    return LOCAL_NOTE


def counters(repo: gitr.Repo) -> list[Cell]:
    """The counters worth showing for one row: the non-zero ones, in column order.

    A repository with nothing to report returns an empty list, and its row is
    then just a name and a branch -- which is exactly what "nothing to report"
    should look like.
    """
    if repo.state == gitr.NOREPO:
        return []
    return [
        Cell(key, glyph, getattr(repo, key))
        for key, glyph in COUNTERS
        if getattr(repo, key)
    ]


def counter_text(repo: gitr.Repo, coloured: bool = True) -> str:
    parts = []
    for cell in counters(repo):
        parts.append(
            f"{COUNTER_ANSI[cell.key]}{cell.text}{RESET}" if coloured else cell.text
        )
    return " ".join(parts)


def rail(repo: gitr.Repo, current: str, coloured: bool = True) -> str:
    """The gutter cell: a bar for the session you are in, a space for the rest.

    A space, not nothing -- every row has to occupy the same columns or the
    marker below a railed row sits one place to the left and the list looks
    ragged.
    """
    if repo.session != current:
        return " "
    return f"{RAIL_ANSI}{CURRENT_RAIL}{RESET}" if coloured else CURRENT_RAIL


def render_rows(
    repos: list[gitr.Repo], coloured: bool = True, current: str = ""
) -> list[str]:
    """One padded line per session, for the CLI and for fzf.

    Deliberately one line where the curses feed uses two: a line here is a
    record, something to grep or to hand to fzf, and a record that wraps over
    two lines stops being one.
    """
    if not repos:
        return []

    session_width = max(len(repo.session) for repo in repos)
    branch_width = max(
        len(branch_label(repo)) + (len(upstream_note(repo)) + 1 if upstream_note(repo) else 0)
        for repo in repos
    )

    rows = []
    for repo in repos:
        gutter = rail(repo, current, coloured)
        glyph = marker(repo)
        note = upstream_note(repo)
        branch = branch_label(repo) + (f" {note}" if note else "")
        if coloured:
            glyph = f"{ANSI[repo.state]}{glyph}{RESET}"
            if note:
                branch = f"{branch_label(repo)} {DIM}{note}{RESET}"

        label = STATE_LABEL[repo.state]
        if coloured:
            label = f"{ANSI[repo.state]}{label}{RESET}"

        pad_branch = " " * max(
            0, branch_width - len(branch_label(repo)) - (len(note) + 1 if note else 0)
        )
        cells = counter_text(repo, coloured)
        detail = ""
        if repo.detail:
            detail = f"  {DIM}{repo.detail}{RESET}" if coloured else f"  {repo.detail}"

        rows.append(
            f"{gutter}{glyph} {repo.session:<{session_width}}  {branch}{pad_branch}"
            f"  {label}  {cells}{detail}".rstrip()
        )
    return rows


def render_fzf(repos: list[gitr.Repo], current: str = "") -> list[str]:
    """One line per session: the session name, a tab, then the visible row.

    fzf is given --with-nth=2.. so the name is carried along invisibly and comes
    back on the selected line -- the same trick Select-Agent.sh uses to avoid
    parsing a display string back into a target.
    """
    return [
        f"{repo.session}\t{row}"
        for repo, row in zip(repos, render_rows(repos, current=current))
    ]


def render_status(repos: list[gitr.Repo]) -> str:
    """A compact count per state for a tmux status-bar segment.

    Clean repositories are omitted: a green marker that is always present
    teaches you to ignore the whole segment. Nothing reads this yet -- the
    daemon publishes it so that adding the segment later stays a `cat` on the
    status-refresh path rather than a Python start.
    """
    counts: dict[str, int] = {}
    for repo in repos:
        counts[repo.state] = counts.get(repo.state, 0) + 1
    parts = [
        f"#[fg={TMUX_COLOUR[state]}]●{counts[state]}"
        for state in (gitr.CONFLICTED, gitr.DIVERGED, gitr.DIRTY, gitr.SYNCED)
        if counts.get(state)
    ]
    if not parts:
        return ""
    return "".join(parts) + "#[fg=default]"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--cached",
        action="store_true",
        help="read the shared snapshot instead of sampling",
    )
    parser.add_argument(
        "--format", choices=("table", "tsv", "json", "fzf", "status"), default="table"
    )
    args = parser.parse_args()

    repos = feed.sample_cached() if args.cached else gitr.detect()
    current = gitr.current_session()

    if args.format == "fzf":
        for row in render_fzf(repos, current):
            print(row)
        return 0

    if args.format == "status":
        summary = render_status(repos)
        if summary:
            print(summary)
        return 0

    if args.format == "json":
        json.dump(
            [{field: getattr(r, field) for field in gitr.FIELDS} for r in repos],
            sys.stdout,
            indent=2,
        )
        sys.stdout.write("\n")
        return 0

    if args.format == "table":
        for row in render_rows(repos, coloured=sys.stdout.isatty(), current=current):
            print(row)
        return 0

    for r in repos:
        print("\t".join(str(getattr(r, field)) for field in gitr.FIELDS))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
