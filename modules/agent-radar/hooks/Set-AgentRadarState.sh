#!/usr/bin/env bash
# Publishes Claude Code's own "I am waiting for you" signal to agent-radar.
#
# Screen reading answers the question for every agent without installing
# anything, and after the region fix it answers it correctly -- see
# rules/claude.toml and agent_radar.py:_above_prompt_box. This is the second,
# independent witness for the one agent that can tell us directly: Claude Code
# runs hooks at exactly the moments its state changes, so a dialog we have never
# seen the shape of still turns the pane red.
#
# The layering matters. This never contradicts the screen -- agent_radar.py
# ignores a blocked marker while the pane is visibly working -- so a marker left
# behind by a crash costs nothing and heals on the next tool call.
#
#   Set-AgentRadarState.sh notification   < hook JSON   # maybe blocked
#   Set-AgentRadarState.sh clear          < hook JSON   # definitely not blocked
#
# Wire it up with scripts/Install-AgentRadarHooks.sh, or paste the block from
# README.md into ~/.claude/settings.json by hand.
#
# Runs synchronously inside Claude's own loop, so it is bash and nothing else:
# no jq, no python start-up, no network. Every path exits 0 -- a monitoring tool
# that can fail an agent's turn is worse than one that misses a state.
set -u

# Not in tmux: nothing to key a marker on, and nothing is watching. Not an error.
[ -n "${TMUX_PANE:-}" ] || exit 0

event="${1:-}"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/agent-radar/panes"
# Pane ids are `%7`; the `%` is dropped so the filename needs no quoting and
# agent_radar.read_marker() applies the same transform in the other direction.
marker="$cache/${TMUX_PANE#%}.json"

case "$event" in
  clear)
    # The user answered, a tool ran, or the turn ended. Whatever the marker
    # said, it is over.
    rm -f -- "$marker"
    exit 0
    ;;
  notification) ;;
  *) exit 0 ;;
esac

payload=""
[ -t 0 ] || payload="$(cat)"

type=""
if [[ "$payload" =~ \"notification_type\"[[:space:]]*:[[:space:]]*\"([A-Za-z_]+)\" ]]; then
  type="${BASH_REMATCH[1]}"
fi

# Only the types that mean a human keystroke is the blocker. Note what is NOT
# here: `idle_prompt` fires when an agent has simply been sitting at a ready
# prompt for a while, and mapping it to blocked would paint every idle pane red
# -- destroying the one distinction this whole tool exists to draw. An
# unrecognised type is ignored rather than guessed, so a renamed type degrades
# to screen reading instead of inventing a state.
case "$type" in
  permission_prompt|worker_permission_prompt) detail="permission prompt" ;;
  agent_needs_input)                          detail="needs input" ;;
  elicitation_*)                              detail="waiting on a choice" ;;
  *) exit 0 ;;
esac

mkdir -p -- "$cache" 2>/dev/null || exit 0
# Written whole, then renamed, so the sampler never reads half a marker.
temp="$marker.$$.tmp"
printf '{"state":"blocked","detail":"%s","type":"%s","ts":%s}\n' \
  "$detail" "$type" "$(date +%s)" > "$temp" 2>/dev/null &&
  mv -f -- "$temp" "$marker" 2>/dev/null
rm -f -- "$temp" 2>/dev/null
exit 0
