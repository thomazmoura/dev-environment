#!/usr/bin/env bash
# Puts the standard layout back (Set-NeovimLayout.sh, as prefix+v does) in
# every laid-out window whose layout has changed since it was last applied: the
# window was resized -- a client attaching at another size, the terminal
# window resized, Termux taking the windows over -- or one of its panes was
# killed and tmux spread its space over the others. Also run when a client
# attaches, so a window that drifted while nobody was attached is fixed right
# away rather than at the next resize. The radar column, the
# terminal row and the home layout's halves get their fixed sizes back, and a
# missing feed or notes pane is reopened.
#
# The hooks can't say which window changed: after-kill-pane names no pane, and
# its #{window_id} is the current window rather than the one that lost the pane.
# So every window marked @layout_window is looked at, and Set-NeovimLayout.sh
# leaves the #{window_layout} it produced in @layout_fitted -- a window whose
# layout still matches is skipped without running anything. Also skipped:
# zoomed windows (prefix+z or prefix+Z: the layout comes back when they zoom
# out) and windows with a dead pane, which Restore-PickerPane.sh is still
# closing or respawning -- its kill-pane fires this again afterwards.
#
# Never moves the focus: Set-NeovimLayout.sh runs with -k.
#
# Usage: Repair-Layouts.sh
#
# Run by the window-resized, after-kill-pane and client-attached hooks in
# modules/tmux/common.conf.
set -uo pipefail

lock_dir="${TMUX_TMPDIR:-/tmp}"

# A resize fires window-resized for every window, and dragging the terminal's
# edge fires it on every step. One run waits while another works, and the
# events in between join the one waiting: it reads the windows after they are
# done, so it sees every change they announced.
exec 8>"$lock_dir/tmux-layout-repair-$(id -u).lock"
flock -n 8 || exit 0
# The lock Set-NeovimLayout.sh takes, so no prefix+v (or picker restore) is
# rebuilding the same window meanwhile. Held for every window of the sweep;
# the nested runs know it is held.
exec 9>"$lock_dir/tmux-layout-$(id -u).lock"
flock -w 30 9 || exit 0
flock -u 8
export TMUX_LAYOUT_LOCKED=1

layout="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/Set-NeovimLayout.sh"

# '|' rather than spaces: read collapses runs of whitespace, which would shift
# the fields of a window with no @layout_fitted yet. The layout string itself
# holds no '|'.
while IFS='|' read -r window layout_window zoomed stash fitted current; do
  [ "$layout_window" = yes ] && [ "$zoomed" != 1 ] && [ -z "$stash" ] || continue
  [ "$fitted" != "$current" ] || continue
  ! tmux list-panes -t "$window" -F '#{pane_dead}' 2>/dev/null | grep -qx 1 || continue
  "$layout" -k "$window" || true
done < <(tmux list-windows -a -F \
  '#{window_id}|#{@layout_window}|#{window_zoomed_flag}|#{@zoom_stash}|#{@layout_fitted}|#{window_layout}')

exit 0
