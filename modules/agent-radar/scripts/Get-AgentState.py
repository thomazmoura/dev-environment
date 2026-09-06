#!/usr/bin/env python3
"""Prints one TSV row per tmux pane running a coding agent.

    pane_id  session  window  label  agent  state  detail

`tsv` is the machine-readable form; `json` carries the matched rule id too.

Two presentation formats live here rather than in the consumers, and for one
concrete reason: both pad columns around a coloured state glyph, and the glyph is
multi-byte. `awk`'s printf %-*s counts BYTES, so a shell-side formatter silently
under-pads every row by two columns per glyph. Python counts characters, and the
detector already holds the data.

  fzf     pane_id TAB <padded, ANSI-coloured row>   for the picker and watcher
  status  #[fg=...] counts                          for the tmux status bar

Usage:
  Get-AgentState.py                 # raw states, no smoothing -- for the picker
  Get-AgentState.py --debounce      # smoothed states -- for polling consumers
  Get-AgentState.py --format=fzf --debounce
  Get-AgentState.py --format=status --debounce
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import agent_radar as radar  # noqa: E402

# Agents blink through an idle-looking frame between tool calls, so a consumer
# polling once a second sees a working agent flicker to idle and back. Hold a
# working -> idle transition until it has been confirmed, which is where the
# smoothing belongs -- not in the UI, and not in the rules.
#
# Constants from herdr S3.6, which arrived at them the same way anyone will.
PENDING_IDLE_CONFIRMATIONS = 3
PENDING_IDLE_CAP_SECONDS = 0.7


def cache_path() -> Path:
    root = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return Path(root) / "agent-radar" / "debounce.json"


def debounce(panes: list[radar.Pane]) -> None:
    """Smooth working -> idle transitions, in place.

    Only that one transition is held. Positive evidence needs no confirmation:
    a matched blocked rule publishes immediately, because the entire point of
    the tool is to tell you about it now.
    """
    path = cache_path()
    try:
        previous = json.loads(path.read_text())
    except (OSError, ValueError):
        previous = {}

    now = time.time()
    current = {}
    for pane in panes:
        entry = previous.get(pane.pane_id, {})
        published = entry.get("published")
        raw = pane.state

        if published == radar.WORKING and raw == radar.IDLE:
            count = entry.get("count", 0) + 1
            first = entry.get("first", now)
            if count >= PENDING_IDLE_CONFIRMATIONS or now - first >= PENDING_IDLE_CAP_SECONDS:
                published = raw
                count, first = 0, now
            else:
                # Keep reporting working, and keep the detail that came with it
                # so the row does not half-update.
                pane.state = radar.WORKING
                pane.detail = entry.get("detail", pane.detail)
        else:
            published = raw
            count, first = 0, now

        current[pane.pane_id] = {
            "published": published,
            "count": count,
            "first": first,
            "detail": pane.detail,
        }

    # Panes that vanished drop out of the file rather than accumulating.
    # Temp-file-then-rename so a concurrent reader never sees a half-written
    # file; two writers racing is harmless, the loser's sample is simply lost.
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_suffix(f".{os.getpid()}.tmp")
        temp.write_text(json.dumps(current))
        temp.replace(path)
    except OSError:
        pass


# Presentation. A coloured dot plus the word: the dot is what you scan for
# across a list, the word is what makes it unambiguous. Deliberately not emoji --
# emoji are double-width, and a column of them misaligns under every padding
# scheme that does not carry a wcwidth table.
GLYPH = "\u25cf"

ANSI = {
    radar.BLOCKED: "\033[91m",   # bright red -- the row you opened the list for
    radar.WORKING: "\033[33m",
    radar.IDLE: "\033[32m",
    radar.UNKNOWN: "\033[90m",
}
RESET = "\033[0m"
DIM = "\033[2m"

# Catppuccin Mocha, matching the rest of the status bar.
TMUX_COLOUR = {
    radar.BLOCKED: "#f38ba8",
    radar.WORKING: "#f9e2af",
    radar.IDLE: "#a6e3a1",
    radar.UNKNOWN: "#6c7086",
}

WAITING_LABEL = {
    # The vocabulary is herdr's four states; the words shown are the ones that
    # answer the question you actually asked. "blocked" is jargon for "it wants
    # you", so say that.
    radar.BLOCKED: "waiting",
    radar.WORKING: "working",
    radar.IDLE: "idle",
    radar.UNKNOWN: "unknown",
}


def render_fzf(panes: list[radar.Pane]) -> list[str]:
    """One line per pane: the pane id, a tab, then the visible row.

    fzf is given --with-nth=2.. so the id is carried along invisibly and comes
    back on the selected line -- the same trick Select-Pane.sh uses to avoid
    parsing a display string back into a target.
    """
    if not panes:
        return []
    session_width = max(len(p.session) for p in panes)
    label_width = max(len(p.label) for p in panes)
    agent_width = max(len(p.agent) for p in panes)
    state_width = max(len(WAITING_LABEL[p.state]) for p in panes)

    rows = []
    for p in panes:
        state = WAITING_LABEL[p.state]
        cell = f"{ANSI[p.state]}{GLYPH} {state:<{state_width}}{RESET}"
        # A detail that only repeats the state word is noise in a column that
        # already says it -- "working  working".
        extra = "" if p.detail == state else p.detail
        detail = f"  {DIM}{extra}{RESET}" if extra else ""
        rows.append(
            f"{p.pane_id}\t{p.session:<{session_width}}  {p.label:<{label_width}}"
            f"  {p.agent:<{agent_width}}  {cell}{detail}"
        )
    return rows


def render_status(panes: list[radar.Pane]) -> str:
    """A compact count per state for the tmux status bar.

    Idle agents are omitted: the status bar is glanced at, not read, and a green
    dot that is always present teaches you to ignore the whole segment.
    """
    counts: dict[str, int] = {}
    for p in panes:
        counts[p.state] = counts.get(p.state, 0) + 1
    parts = [
        f"#[fg={TMUX_COLOUR[state]}]{GLYPH}{counts[state]}"
        for state in (radar.BLOCKED, radar.WORKING, radar.UNKNOWN)
        if counts.get(state)
    ]
    if not parts:
        return ""
    return "".join(parts) + "#[fg=default]"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--debounce",
        action="store_true",
        help="smooth working->idle flicker; for consumers that poll",
    )
    parser.add_argument(
        "--format", choices=("tsv", "json", "fzf", "status"), default="tsv"
    )
    args = parser.parse_args()

    panes = radar.detect()
    if args.debounce:
        debounce(panes)

    if args.format == "fzf":
        for row in render_fzf(panes):
            print(row)
        return 0

    if args.format == "status":
        summary = render_status(panes)
        if summary:
            print(summary)
        return 0

    if args.format == "json":
        json.dump(
            [
                {
                    "pane_id": p.pane_id,
                    "session": p.session,
                    "window": p.window,
                    "label": p.label,
                    "agent": p.agent,
                    "state": p.state,
                    "detail": p.detail,
                    "rule_id": p.rule_id,
                }
                for p in panes
            ],
            sys.stdout,
            indent=2,
        )
        sys.stdout.write("\n")
        return 0

    for p in panes:
        print(
            "\t".join(
                [p.pane_id, p.session, p.window, p.label, p.agent, p.state, p.detail]
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
