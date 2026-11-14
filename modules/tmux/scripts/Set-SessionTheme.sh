#!/usr/bin/env bash
# Gives a tmux session the theme colour themes.json picks for it (themes.py,
# edited with steward.nvim's :Steward themes): a colour of its own by name or
# directory, and for an ssh session (prefix+N) or one in a Docker container
# (prefix+D) by name or directory on that host. An ssh or Docker session the
# file has nothing for still gets a colour of its own -- @ssh_theme_colour
# (violet by default) or @docker_theme_colour (Docker's blue) -- so a session
# whose panes are on another machine never looks like a local one. A local
# session the file has nothing for draws in the global theme (Set-Theme.sh).
#
# Usage: Set-SessionTheme.sh [session...]
#   Run by New-SshSession.sh as it opens a session (through Set-SshTheme.sh),
#   by Set-SessionLabel.sh when a session's prefix+$ label changes (a key can
#   name it by its label), and from the client-session-changed,
#   client-attached, session-created and session-renamed hooks (see
#   modules/tmux/common.conf), which pass the session. Falls back to the
#   session of whichever client asks.
#        Set-SessionTheme.sh [-g] -a
#   Every open session, so an edited themes.json shows at once rather than on
#   the next switch: run at every config load (the end of common.conf, so
#   prefix+u too), and by steward.nvim when it saves themes.json. -g first
#   redraws the global theme (Set-Theme.sh), for a changed default; a config
#   load has just done that itself.
#
#   The name is taken as every argument joined, not as $1: the hook hands it to
#   /bin/sh unquoted, so a session whose name contains a space arrives split
#   across argv.
#
# How: the theme (Set-Theme.sh) is written in global options. This writes the
# options holding its colour onto the session and its windows (Set-Theme.sh
# -t), or takes them off when the session has no colour of its own (-u).
# Session and window options shadow the global ones, so every other session
# keeps drawing from the globals, and the options go away with the session.
#
# They are written afresh every time a client arrives, so a saved themes.json
# or a reloaded config -- another theme, a changed bar -- reaches every session
# on the next switch.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

global="" all=""
while getopts "ga" opt; do
  case "$opt" in
    g) global=yes ;;
    a) all=yes ;;
    *) exit 1 ;;
  esac
done
shift $((OPTIND - 1))

if [ -n "$all" ]; then
  [ -z "$global" ] || "$scripts/Set-Theme.sh"
  # One at a time: each writes the options of its own session only.
  while IFS= read -r name; do
    [ -n "$name" ] && "${BASH_SOURCE[0]}" "$name"
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null)
  exit 0
fi

session=${*:-}
if [ -z "$session" ]; then
  session="$(tmux display-message -p '#{session_name}' 2>/dev/null)" || exit 0
fi
[ -n "$session" ] || exit 0
target="=$session:"

# Separated by \x1f, not tabs: read merges runs of a whitespace IFS, and any of
# these may be empty.
IFS=$'\x1f' read -r path remote ssh_dir ssh_name label < <(
  tmux display-message -p -t "$target" $'#{session_path}\x1f#{@ssh_target}\x1f#{@ssh_dir}\x1f#{@ssh_name}\x1f#{@session_label}' 2>/dev/null) || exit 0

colour="$(python3 "$scripts/themes.py" session "$session" "$path" "$remote" "$ssh_dir" "$ssh_name" "$label" 2>/dev/null)"

if [ -z "$colour" ] && [ -n "$remote" ]; then
  if [[ $remote == docker:* ]]; then
    colour="$(tmux show-options -gqv @docker_theme_colour)"
    colour="${colour:-#2496ed}"
  else
    colour="$(tmux show-options -gqv @ssh_theme_colour)"
    colour="${colour:-#9370db}"
  fi
fi

if [ -z "$colour" ]; then
  "$scripts/Set-Theme.sh" -u -t "$session"
  tmux set-hook -u -t "$target" window-linked 2>/dev/null
  exit 0
fi

"$scripts/Set-Theme.sh" -t "$session" "$colour"

# Windows opened in the session later are themed as they arrive. This hook is
# the session's own, so assigning it replaces nothing of anyone else's.
tmux set-hook -t "$target" window-linked "run-shell -b \"$scripts/Set-SessionTheme.sh #{session_name}\"" 2>/dev/null
exit 0
