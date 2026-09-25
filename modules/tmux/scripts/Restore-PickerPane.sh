#!/usr/bin/env bash
# Keeps a laid-out window from running out of panes to work in: when a pane
# closes and what is left of the window is nothing, or only the Git and Agents
# feeds (and the notes pane), a picker pane (Select-PaneKind.sh) takes the closed pane's place.
#
# tmux has no hook that fires before a pane closes, so the layout windows get
# the next best thing: Set-NeovimLayout.sh marks them @layout_window and turns
# remain-on-exit on, so a pane whose command ends stays behind, dead, and the
# pane-died hook hands it here before it is gone. Here it is either killed --
# the window still has a pane to work in, and it closes as it always did -- or
# respawned as the picker, in the very spot it held. A window's last pane is
# only ever respawned, so the window and the session outlive it; prefix+C-b x on
# the picker still closes them, since kill-pane never leaves a dead pane.
#
# prefix+C-b x is the one close with no dead pane to hand over. The
# after-kill-pane hook runs this without a pane: it looks through every layout
# window for one left with only the feeds, and has Set-NeovimLayout.sh put the
# picker back beside them -- the same repair prefix+v makes. A window whose
# last pane was killed is gone by then, as it should be.
#
# Windows laid out before this existed have neither option until prefix+v (or
# prefix+V) is run in them once.
#
# Usage: Restore-PickerPane.sh [pane]
#   pane   a dead pane, from the pane-died hook. Omitted, every layout window is
#          checked instead.
#
# Registered in modules/tmux/common.conf.
set -uo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

# A hook has nobody to report a failure to.
die() { exit 0; }

dead="${1:-}"

# only_feeds <window> [except]
# True when every live pane of <window> but <except> is a Git or Agents feed or
# the notes pane --
# labels rather than @layout_role, so a feed opened with prefix+r/R counts
# too -- or when there is no such pane at all.
only_feeds() {
  local window=$1 except=${2:-} id pane_dead label
  while IFS='|' read -r id pane_dead label; do
    [ "$id" != "$except" ] && [ "$pane_dead" != 1 ] || continue
    case "$label" in
      Git | Agents | Notes) ;;
      *) return 1 ;;
    esac
  done < <(tmux list-panes -t "$window" -F '#{pane_id}|#{pane_dead}|#{@pane_label}' 2>/dev/null)
}

if [ -n "$dead" ]; then
  # '|' rather than spaces: read collapses runs of whitespace, which would
  # shift the fields of a window that has no @layout_window.
  IFS='|' read -r pane_dead layout_window start < <(tmux display-message -p -t "$dead" \
    '#{pane_dead}|#{@layout_window}|#{pane_start_command}' 2>/dev/null) || exit 0
  # Gone already, alive again, or remain-on-exit someone else asked for.
  [ "$pane_dead" = 1 ] && [ "$layout_window" = yes ] || exit 0

  if ! only_feeds "$dead" "$dead"; then
    tmux kill-pane -t "$dead"
    exit 0
  fi

  # respawn-pane reruns the pane's own command: none, for every pane new_pane
  # or a new session opens, which means the user's login shell -- the shell
  # new_pane types into, for its profile's environment. Anything else gets
  # that shell explicitly.
  if [ -n "$start" ]; then
    tmux respawn-pane -t "$dead" "exec ${SHELL:-bash} -l"
  else
    tmux respawn-pane -t "$dead"
  fi
  label_pane "$dead" Picker
  tmux set -p -t "$dead" @layout_role picker
  tmux send-keys -t "$dead" "$(closing_line "bash ~/.modules/tmux/scripts/Select-PaneKind.sh")" C-m
  exit 0
fi

# No dead pane: a kill-pane. after-kill-pane can't say which window lost the
# pane, so all of them are checked; there are never many. A window with a dead
# pane in it is left to that pane's own pane-died run, which respawns it, rather
# than getting a second picker from here.
while IFS='|' read -r window layout_window pane; do
  [ "$layout_window" = yes ] || continue
  ! tmux list-panes -t "$window" -F '#{pane_dead}' | grep -qx 1 || continue
  only_feeds "$window" || continue
  "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/Set-NeovimLayout.sh" "$pane"
done < <(tmux list-windows -a -F '#{window_id}|#{@layout_window}|#{pane_id}')

exit 0
