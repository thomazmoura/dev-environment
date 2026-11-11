#!/usr/bin/env bash
# Marks a tmux session as the home session -- the one prefix+h switches to and
# the Git pane draws a home icon beside.
#
# Usage: Set-HomeSession.sh <session>    toggle the mark on <session>
#        Set-HomeSession.sh -r           restore the mark after a server start
#
# The name of the session lives in two places, each for its own reader. tmux has the global
# @home_session option, which any binding or format can ask for. The git feed
# (Watch-GitFeed.py) reads the file instead: it redraws many times a second, and
# a file read costs nothing where a tmux call costs ~14ms. The file is also what
# lets the mark outlive the tmux server -- common.conf runs -r when the config
# is read, which puts the option back from it.
#
# A third file, home-session-path, keeps the session's directory: the name alone
# is not enough to build the session again, which vtmux (DevHelpers.psm1) does
# when it starts the first tmux server of the day. It is a file of its own
# rather than a second line so the readers above keep reading the name whole.
#
# An ssh or Docker session (New-SshSession.sh) has no local directory worth
# keeping -- it starts in the local ~ -- so a fourth file, home-session-ssh,
# keeps what vtmux needs to open it over ssh again instead:
#
#   <@ssh_target> TAB <@ssh_dir> TAB <@ssh_name>
#
# It is there only while the home session is one of those.
#
# A session on a linked machine (<host>:<session>, tmux_link.session_key) can
# be home too, H on its row of the Git pane. Its mark is that key and nothing
# more: the session lives in the other machine's tmux, which is where it is
# kept and opened, so there is no directory or ssh target here to save, and
# vtmux leaves it to that machine. prefix+h and the Git pane's Enter reconnect
# to that machine first when the radars have lost it (Connect-LinkSession.sh).
#
# Pressed on the session that is already home, the mark comes off: one key both
# ways, from the Git pane's H.
set -uo pipefail

file="${XDG_CACHE_HOME:-$HOME/.cache}/tmux/home-session"
path_file="$file-path"
ssh_file="$file-ssh"

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
  rm -f "$file" "$path_file" "$ssh_file"
else
  tmux set -g @home_session "$session"
  mkdir -p "$(dirname "$file")"
  printf '%s\n' "$session" >"$file"
  if [[ $session == *:* ]]; then
    # A linked machine's session: nothing of it in this tmux to ask about.
    rm -f "$path_file" "$ssh_file"
  else
    tmux display -p -t "=$session:" '#{session_path}' >"$path_file"
    ssh="$(tmux display -p -t "=$session:" $'#{@ssh_target}\t#{@ssh_dir}\t#{@ssh_name}')"
    if [ -n "${ssh%%$'\t'*}" ]; then
      printf '%s\n' "$ssh" >"$ssh_file"
    else
      rm -f "$ssh_file"
    fi
  fi
fi

# Every session's Git pane shows the icon, and each redraws on the sampler's
# next publication -- now, rather than at the end of its tick.
"$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/Request-RadarSample.sh" git-radar
