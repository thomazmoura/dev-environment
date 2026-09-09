#!/usr/bin/env bash
# Tells a session's git-radar feed panes to put their cursor back on that
# session's own row.
#
# Usage: Sync-RadarSelection.sh [session...]
#   Run from the client-session-changed and client-attached hooks (see
#   modules/tmux/common.conf), which pass the session the client has arrived in.
#   Falls back to the session of whichever client asks.
#
#   The name is taken as every argument joined, not as $1: the hook hands it to
#   /bin/sh unquoted, so a session whose name contains a space arrives split
#   across argv.
#
# Why a hook and not something the feed notices for itself: a feed pane is not
# the pane that gains the focus when a client switches session -- that is
# whichever pane the session was left on -- so no focus event reaches it, and
# the alternative, asking tmux every tick whether its session is attached, costs
# about 14ms per feed pane per tick (the same trade radar_ui.Focus documents).
#
# The nudge is a single keypress, Ctrl-O, which Watch-GitFeed.py reads as
# SELF_KEY. If a feed has been closed and a shell is sitting in its pane
# instead, that shell gets a bare Ctrl-O, which readline ignores.
set -uo pipefail

session=${*:-}
if [ -z "$session" ]; then
  session="$(tmux display-message -p '#{session_name}' 2>/dev/null)" || exit 0
fi
[ -n "$session" ] || exit 0

# -s covers every window of the session, not just the current one, and `=` stops
# tmux reading the name as an fnmatch pattern. A session with no feed pane is
# perfectly normal, so nothing here is an error worth reporting: this runs from
# a hook, where a failure is noise on somebody's status line.
tmux list-panes -s -t "=$session" -F $'#{pane_id}\t#{@pane_label}' 2>/dev/null \
  | while IFS=$'\t' read -r pane label; do
      [ "$label" = "Git" ] || continue
      tmux send-keys -t "$pane" C-o 2>/dev/null
    done

exit 0
