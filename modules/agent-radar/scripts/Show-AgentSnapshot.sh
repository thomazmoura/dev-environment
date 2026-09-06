#!/usr/bin/env bash
# Prints the exact text the rules are evaluated against for one pane, plus the
# pane's OSC title (the `title` region). Nothing else -- no colour, no framing.
#
# This is half of the rule-authoring loop, and the half that has to exist first:
# screen scraping fails silently, so a rule that matched the wrong region and a
# rule whose third `contains` failed look identical from the outside. Save a real
# screen while an agent sits in a state you want to recognise, then replay it
# against the engine with Test-AgentRules.py.
#
#   Show-AgentSnapshot.sh %23 > fixtures/claude-blocked.txt
#   Test-AgentRules.py --file fixtures/claude-blocked.txt --agent claude
#
# The title is emitted as a leading `#title: ` comment line, which
# Test-AgentRules.py strips back off, so a fixture round-trips with the OSC
# evidence intact -- without it, every title rule would look like it failed.
#
# Usage: Show-AgentSnapshot.sh [pane-id]   (default: the current pane)
set -uo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/tmux-helpers.sh"

require_tools tmux

pane="${1:-$(tmux display-message -p '#{pane_id}')}"

printf '#title: %s\n' "$(tmux display-message -p -t "$pane" '#{pane_title}')"
tmux capture-pane -p -t "$pane"
