#!/usr/bin/env bash
# Gives an ssh session (prefix+N) a theme colour of its own, so a session whose
# panes are on another machine never looks like a local one -- and a session
# in a Docker container (prefix+D) another, so neither looks like the other.
#
# Usage: Set-SshTheme.sh [session...]
#   Run by New-SshSession.sh as it opens a session, and from the
#   client-session-changed and client-attached hooks (see
#   modules/tmux/common.conf), which pass the session the client has arrived
#   in. Falls back to the session of whichever client asks. A session that is
#   not an ssh one is left alone.
#
#   The name is taken as every argument joined, not as $1: the hook hands it to
#   /bin/sh unquoted, so a session whose name contains a space arrives split
#   across argv.
#
# How: tmux-power paints the whole theme in one colour, and does it in global
# options. This copies the options holding that colour onto the ssh session and
# its windows with the colour swapped for @ssh_theme_colour (violet by default)
# or, on a container, @docker_theme_colour (Docker's blue). Session and window
# options shadow the global ones, so every other session keeps drawing from the
# globals -- switching back to a local session brings its colour back with
# nothing to undo, and the options go away with the session.
#
# The copies are taken afresh every time a client arrives, so a reloaded config
# -- another theme, a status segment added -- reaches the ssh sessions as well.
set -uo pipefail

session=${*:-}
if [ -z "$session" ]; then
  session="$(tmux display-message -p '#{session_name}' 2>/dev/null)" || exit 0
fi
[ -n "$session" ] || exit 0
target="=$session:"

remote="$(tmux show-options -qv -t "$target" @ssh_target 2>/dev/null)"
[ -n "$remote" ] || exit 0

# The options tmux-power writes the theme colour into. status-left and
# status-right also hold the agent-radar and Workhorse segments, which the copy
# carries along unchanged.
session_options=(status-left status-right message-style message-command-style display-panes-active-colour)
window_options=(window-status-format window-status-current-format window-status-style window-status-last-style
  window-status-activity-style window-status-bell-style pane-active-border-style mode-style clock-mode-colour)

# Every global value in one call: each show prints its value on a line of its
# own, in the order asked. clock-mode-colour is last, and is the theme colour
# on its own.
read_globals=()
for option in "${session_options[@]}"; do read_globals+=(show-options -gv "$option" \;); done
for option in "${window_options[@]}"; do read_globals+=(show-options -gwv "$option" \;); done
mapfile -t values < <(tmux "${read_globals[@]}" 2>/dev/null)
[ "${#values[@]}" -eq $((${#session_options[@]} + ${#window_options[@]})) ] || exit 0

from="${values[-1]}"
if [[ $remote == docker:* ]]; then
  to="$(tmux show-options -gqv @docker_theme_colour)"
  to="${to:-#2496ed}"
else
  to="$(tmux show-options -gqv @ssh_theme_colour)"
  to="${to:-#9370db}"
fi
[[ $from == \#* ]] || exit 0

# Written in one call as well, so the status line never shows a half-swapped
# theme. The values go in as arguments, never through tmux's parser, so the
# formats in them need no escaping.
write=()
i=0
for option in "${session_options[@]}"; do
  write+=(set-option -t "$target" "$option" "${values[i++]//"$from"/"$to"}" \;)
done
window_values=("${values[@]:i}")
while IFS= read -r window; do
  i=0
  for option in "${window_options[@]}"; do
    write+=(set-option -w -t "$window" "$option" "${window_values[i++]//"$from"/"$to"}" \;)
  done
done < <(tmux list-windows -t "$target" -F '#{window_id}' 2>/dev/null)

# Windows opened in the session later are themed as they arrive. This hook is
# the session's own, so assigning it replaces nothing of anyone else's.
script="$(readlink -f "${BASH_SOURCE[0]}")"
write+=(set-hook -t "$target" window-linked "run-shell -b \"$script #{session_name}\"")

tmux "${write[@]}" 2>/dev/null
exit 0
