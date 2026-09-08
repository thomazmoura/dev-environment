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

Where the data comes from is a separate axis from how it is formatted. By
default this samples live, which is what the rule-authoring and one-shot uses
want. `--cached` reads the shared snapshot published by Start-AgentRadar.py
instead, so a consumer costs a file read no matter how many consumers there are;
see agent_feed.py. Every binding uses --cached.

Usage:
  Get-AgentState.py                 # raw states, no smoothing -- sampled live
  Get-AgentState.py --debounce      # smoothed states, still sampled live
  Get-AgentState.py --cached        # the shared snapshot; already smoothed
  Get-AgentState.py --format=fzf --cached
  Get-AgentState.py --format=status --cached
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import agent_feed as feed  # noqa: E402
import agent_radar as radar  # noqa: E402

# The working->idle debounce moved to agent_feed.debounce, and the move is not
# cosmetic: it compares each sample against the previous one, so it is only
# correct while a single process is taking the samples. That process is now
# Start-AgentRadar.py. Calling it from here still works for a live one-shot,
# but a second live poller would corrupt the shared counters -- which is the bug
# --cached exists to remove.


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


def agent_line(pane: radar.Pane) -> str:
    """What a row says about *which* agent this is.

    The pane label is the readable name -- "Claude Code", set by
    tmux-helpers.sh:label_pane for every pane the bindings open -- and the agent
    id is what the rules matched. Showing both is usually saying the same thing
    twice, so the id is appended only when the label does not already contain
    it: an agent someone started by hand has no @pane_label and falls back to
    the window name, where "pwsh  claude" is exactly the pair you want to see.
    """
    if pane.agent and pane.agent.lower() not in pane.label.lower().replace(" ", ""):
        return f"{pane.label}  {pane.agent}"
    return pane.label


def extra_detail(pane: radar.Pane) -> str:
    """The detail, minus the case where it only repeats the state word.

    "working  working" is noise in a row whose first line already says it.
    """
    return "" if pane.detail == WAITING_LABEL[pane.state] else pane.detail


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
        extra = extra_detail(p)
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
        "--cached",
        action="store_true",
        help="read the shared snapshot instead of sampling; implies --debounce",
    )
    parser.add_argument(
        "--format", choices=("tsv", "json", "fzf", "status"), default="tsv"
    )
    args = parser.parse_args()

    if args.cached:
        # Already smoothed by the sampler that published it, so --debounce is
        # implied rather than refused -- a consumer asking for both is asking
        # for the same thing twice.
        panes = feed.sample_cached()
    else:
        panes = radar.detect()
        if args.debounce:
            feed.debounce(panes)

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
