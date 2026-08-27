#!/usr/bin/env bash
# Reports a coding agent's lifecycle state to demux, for the sidebar and the
# tmux status bar. Wired to each agent's own hook mechanism:
#   Claude Code  ~/.claude/settings.json     "hooks"
#   Copilot CLI  ~/.copilot/settings.json    "hooks"
#
# demux ships no vendor hooks -- it never discovers what an agent is doing on
# its own, so every agent has to push its state. This wrapper keeps that mapping
# in one place instead of repeating a long `demux state set` for every event.
#
# Usage: Set-DemuxAgentState.sh <tool> <state> [message] [extra demux args...]
#   tool     matches a [tools.<key>] entry in demux.toml (claude, copilot, ...)
#   state    working | waiting | done | error | flagged | clear
#   message  optional detail shown in the sidebar
#
# Always exits 0: a hook must never break the agent's turn.
set -u

# The agent sends its hook payload on stdin. Drain it so the writer never blocks
# on a full pipe, even though nothing here needs the contents.
cat >/dev/null 2>&1 || true

tool="${1:-}"
state="${2:-}"
message="${3:-}"
[ -n "$tool" ] && [ -n "$state" ] || exit 0
[ $# -ge 3 ] && shift 3 || shift $#

# Outside tmux there is no pane to attach the state to.
[ -n "${TMUX_PANE:-}" ] || exit 0

DEMUX="$HOME/.local/bin/demux"
[ -x "$DEMUX" ] || exit 0

if [ "$state" = "clear" ]; then
  # Session ended without the pane closing: drop the row rather than leaving a
  # stale "done" behind. demux's own tmux hooks only cover pane/window/session
  # close.
  "$DEMUX" state clear --target-id "$TMUX_PANE" >/dev/null 2>&1
  exit 0
fi

if [ -n "$message" ]; then
  "$DEMUX" state set --target-id "$TMUX_PANE" --state "$state" --tool "$tool" \
    --message "$message" "$@" >/dev/null 2>&1
else
  "$DEMUX" state set --target-id "$TMUX_PANE" --state "$state" --tool "$tool" \
    "$@" >/dev/null 2>&1
fi

exit 0
