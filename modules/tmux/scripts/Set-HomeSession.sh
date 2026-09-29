#!/usr/bin/env bash
# Marks a tmux session as the home session -- the one prefix+h switches to and
# the Git pane draws a home icon beside.
#
# Usage: Set-HomeSession.sh <session>    toggle the mark on <session>
#        Set-HomeSession.sh -r           restore the mark after a server start
#
# The mark lives in two places, each for its own reader. tmux has the global
# @home_session option, which any binding or format can ask for. The git feed
# (Watch-GitFeed.py) reads the file instead: it redraws many times a second, and
# a file read costs nothing where a tmux call costs ~14ms. The file is also what
# lets the mark outlive the tmux server -- common.conf runs -r when the config
# is read, which puts the option back from it.
#
# Pressed on the session that is already home, the mark comes off: one key both
# ways, from the Git pane's H.
set -uo pipefail

file="${XDG_CACHE_HOME:-$HOME/.cache}/tmux/home-session"

if [ "${1:-}" = "-r" ]; then
  # Only when the option is unset, so a reload never undoes a mark made since.
  [ -s "$file" ] || exit 0
  [ -z "$(tmux show -gqv @home_session)" ] || exit 0
  tmux set -g @home_session "$(cat "$file")"
  exit 0
fi

session="${1:?usage: Set-HomeSession.sh <session> | -r}"

if [ "$(tmux show -gqv @home_session)" = "$session" ]; then
  tmux set -gu @home_session
  rm -f "$file"
else
  tmux set -g @home_session "$session"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$session" >"$file"
fi

# Every session's Git pane shows the icon, and each redraws on the sampler's
# next publication -- now, rather than at the end of its tick.
"$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/Request-RadarSample.sh" git-radar
