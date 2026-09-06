#!/usr/bin/env python3
"""Replays a screen against an agent's rules and shows why each one did or did
not fire.

The other half of the rule-authoring loop, and the reason rule authoring is
tractable at all. Screen scraping fails silently: a rule that matched the wrong
region and a rule whose third `contains` failed are indistinguishable from the
outside, so without this you bisect a TOML file by hand. Herdr's reimplementation
checklist puts building it at step 5 of 9, before the rules themselves -- "build
it *with* the engine, not after. Rule authoring without it is guesswork."

  Test-AgentRules.py --pane %23                       # a live pane
  Test-AgentRules.py --file fixtures/claude-idle.txt --agent claude
  Test-AgentRules.py --file fixtures/claude-idle.txt --agent claude --region above_prompt_box

The loop:
  Show-AgentSnapshot.sh %23 > fixtures/claude-blocked.txt   # capture the state
  Test-AgentRules.py --file fixtures/claude-blocked.txt --agent claude
  $EDITOR rules/claude.toml                                 # write a rule
  Test-AgentRules.py --file ...                             # replay, no restart
"""

from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import agent_radar as radar  # noqa: E402

DIM, BOLD, RESET = "\033[2m", "\033[1m", "\033[0m"
GREEN, RED, YELLOW = "\033[32m", "\033[31m", "\033[33m"


def load_fixture(path: str) -> tuple[str, str]:
    """Read a snapshot saved by Show-AgentSnapshot.sh.

    The leading `#title:` line carries the pane's OSC title so the `title`
    region still has something to match. Without it every title rule would look
    like a failure in replay while working fine live -- the most confusing
    possible way for this tool to lie to you.
    """
    text = open(path, encoding="utf-8", errors="replace").read().rstrip("\n")
    title = ""
    if text.startswith("#title:"):
        first, _, rest = text.partition("\n")
        title = first[len("#title:"):].strip()
        text = rest
    return text, title


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--file", help="a snapshot from Show-AgentSnapshot.sh")
    source.add_argument("--pane", help="a live tmux pane id, e.g. %%23")
    parser.add_argument("--agent", help="agent label; inferred for --pane")
    parser.add_argument(
        "--region", help="also print this region's text verbatim, for eyeballing"
    )
    args = parser.parse_args()

    if args.pane:
        panes = {p.pane_id: p for p in radar.list_panes()}
        pane = panes.get(args.pane)
        if pane is None:
            print(f"no such pane: {args.pane}", file=sys.stderr)
            return 1
        agent = args.agent or radar.identify(pane, radar.list_processes())
        if not agent:
            print(f"no agent identified in {args.pane}", file=sys.stderr)
            return 1
        snapshot, title = radar.capture(pane.pane_id), pane.title
    else:
        if not args.agent:
            print("--file needs --agent", file=sys.stderr)
            return 1
        agent = args.agent
        snapshot, title = load_fixture(args.file)

    rules = radar.load_rules(agent)
    print(f"{BOLD}agent{RESET}  {agent}   {BOLD}rules{RESET}  {len(rules)}")
    print(f"{BOLD}title{RESET}  {title!r}")
    print()

    winner = None
    for rule in rules:
        text = radar.region_text(rule.region, snapshot, title)
        trace: list[str] = []
        matched = rule.gate.matches(text, trace)
        if matched and winner is None:
            winner = rule
            mark, colour = "MATCH", GREEN
        elif matched:
            # Still reported: a lower-priority match is usually the rule you
            # meant to win, and seeing it is how you find a priority mistake.
            mark, colour = "match", YELLOW
        else:
            mark, colour = "  -  ", RED
        print(
            f"{colour}{mark}{RESET} {rule.priority:>5}  {rule.id:<28}"
            f" {DIM}{rule.state:<8} {rule.region}{RESET}"
        )
        if not matched and trace:
            # Only the first failure matters: the gate short-circuits, so the
            # rest were never evaluated.
            print(f"        {DIM}why: {trace[0]}{RESET}")
        if not text.strip():
            print(f"        {DIM}note: region is empty{RESET}")

    print()
    verdict = radar.classify(agent, snapshot, title, rules)
    print(f"{BOLD}verdict{RESET}  {verdict.state}  {DIM}via {verdict.rule_id}{RESET}")

    if args.region:
        text = radar.region_text(args.region, snapshot, title)
        print(f"\n{BOLD}region {args.region}{RESET}\n{DIM}{'-' * 60}{RESET}")
        print(text)
        print(f"{DIM}{'-' * 60}{RESET}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
