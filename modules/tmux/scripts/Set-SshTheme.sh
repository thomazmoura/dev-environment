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
# How: the theme (Set-Theme.sh) is written in global options. This writes the
# options holding its colour onto the ssh session and its windows in
# @ssh_theme_colour (violet by default) or, on a container,
# @docker_theme_colour (Docker's blue). Session and window options shadow the
# global ones, so every other session keeps drawing from the globals --
# switching back to a local session brings its colour back with nothing to
# undo, and the options go away with the session.
#
# They are written afresh every time a client arrives, so a reloaded config
# -- another theme, a changed bar -- reaches the ssh sessions as well.
set -uo pipefail

session=${*:-}
if [ -z "$session" ]; then
  session="$(tmux display-message -p '#{session_name}' 2>/dev/null)" || exit 0
fi
[ -n "$session" ] || exit 0
target="=$session:"

remote="$(tmux show-options -qv -t "$target" @ssh_target 2>/dev/null)"
[ -n "$remote" ] || exit 0

if [[ $remote == docker:* ]]; then
  colour="$(tmux show-options -gqv @docker_theme_colour)"
  colour="${colour:-#2496ed}"
else
  colour="$(tmux show-options -gqv @ssh_theme_colour)"
  colour="${colour:-#9370db}"
fi

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
"$scripts/Set-Theme.sh" -t "$session" "$colour"

# Windows opened in the session later are themed as they arrive. This hook is
# the session's own, so assigning it replaces nothing of anyone else's.
tmux set-hook -t "$target" window-linked "run-shell -b \"$scripts/Set-SshTheme.sh #{session_name}\"" 2>/dev/null
exit 0
