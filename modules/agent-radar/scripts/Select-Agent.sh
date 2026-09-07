#!/usr/bin/env bash
# Lists every coding agent running in any tmux session with its current state,
# and switches the client to the one you pick.
#
#   Session - Pane label - Agent - State
#
# Bound to prefix+t then a, as a popup (see modules/tmux/common.conf). Meant to
# be run from a tmux binding so the tmux commands below act on the client that
# opened it.
#
# The list is built by Get-AgentState.py, which reads each agent's screen rather
# than waiting to be told what it is doing -- so it covers agents you started by
# hand, and cannot go stale.
#
# Structurally this is Select-Pane.sh with a state column: same hidden-id-in-
# column-one trick, same three-command jump. The column padding lives in the
# detector instead of in awk here, because the state glyph is multi-byte and
# awk's printf pads by bytes.
set -uo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/tmux-helpers.sh"

require_tools tmux fzf

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
detector="$here/Get-AgentState.py"

# --cached: read the snapshot Start-AgentRadar.py publishes for the whole
# machine rather than sampling here. It also makes the popup open faster -- a
# live sample is a `ps` plus a `capture-pane` per agent pane, which is a visible
# pause on a busy machine, and the answer is already sitting in a file.
list_command="$detector --format=fzf --cached"

rows="$($list_command)"
[ -n "$rows" ] || die "No coding agents running in any session"
selection="$(
  printf '%s\n' "$rows" \
    | fzf --ansi --reverse --delimiter=$'\t' --with-nth=2.. \
          --prompt='agent> ' \
          --header=$'Switch to agent   (ctrl-r refresh)' \
          --bind="ctrl-r:reload($list_command)"
)" || exit 0
[ -n "$selection" ] || exit 0

pane="${selection%%$'\t'*}"

# All three: switch-client alone lands on the session's current window, which is
# not necessarily the one holding the pane.
tmux switch-client -t "$pane"
tmux select-window -t "$pane"
tmux select-pane -t "$pane"
