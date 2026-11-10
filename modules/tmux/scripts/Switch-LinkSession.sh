#!/usr/bin/env bash
# Takes the client to a session, on this machine or on a linked one. What every
# picker and feed calls once something is chosen: prefix+? (Select-Session.sh),
# prefix+/ and prefix+N for a folder on a linked machine, Enter in the Git and
# Agents panes.
#
# Usage: Switch-LinkSession.sh [-c <client>] <key> [<pane>]
#   <key>    a session of this tmux, by name, or <host>:<session> for a session
#            on a linked machine -- how the radars name those rows
#            (tmux_link.session_key). A tmux session name cannot hold a colon,
#            so the two never read as each other. A key naming this machine
#            itself is a session of this tmux: how Sync-LinkGroup.sh writes
#            every session, so that its state reads the same on each machine
#   <pane>   the pane to land on (%12, as that machine's tmux numbers it)
#   -c       the client to move; the one this runs under when left out
#
# A local key is a switch-client. A linked one cannot be: the client leaves this
# tmux for the other machine's, by `detach-client -E` running Connect-Tmux.sh
# --handoff in its place, which tells the loop around the client where to go
# (see Connect-Tmux.sh). Nothing is opened over ssh in this tmux.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

client=""
if [ "${1:-}" = "-c" ]; then
  client="${2:-}"
  shift 2
fi
key="${1:?session}"
pane="${2:-}"

# This machine's host name, as Connect-Tmux.sh and tmux_link.identity() have it.
if [ -n "${TMUX_LINK_IDENTITY:-}" ]; then
  self="${TMUX_LINK_IDENTITY##*@}"
else
  self="$(hostname | cut -d. -f1 | tr '[:upper:]' '[:lower:]')"
fi
[[ $key == "$self":* ]] && key="${key#*:}"

if [[ $key != *:* ]]; then
  tmux switch-client ${client:+-c "$client"} -t "=$key" || exit 1
  if [ -n "$pane" ]; then
    tmux select-window -t "$pane" 2>/dev/null
    tmux select-pane -t "$pane" 2>/dev/null
  fi
  exit 0
fi

host="${key%%:*}"
session="${key#*:}"
peers="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-link/peers"
identity="$(awk -F '\t' -v host="$host" '{ h = $1; sub(/^.*@/, "", h) } h == host { print $1; exit }' "$peers" 2>/dev/null)"
if [ -z "$identity" ]; then
  tmux display-message "No linked machine called $host"
  exit 0
fi

[ -n "$client" ] || client="$(tmux display-message -p '#{client_name}')"
handoff="$(printf 'exec %q --handoff %q %q %q' "$scripts/Connect-Tmux.sh" "$identity" "$session" "$pane")"
tmux detach-client -t "$client" -E "$handoff"
