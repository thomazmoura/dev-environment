#!/usr/bin/env bash
# Zooms a pane over every pane of its window but the radar column -- Git,
# Agents and the notes pane stay on the left, readable as ever (prefix+z).
# Pressing it again puts the window back as it was. prefix+Z is tmux's own
# zoom, which hides the column too.
#
# Usage: Switch-PaneZoom.sh <pane>
#          Toggles the partial zoom of <pane>'s window.
#        Switch-PaneZoom.sh --restore <pane>
#          Undoes the partial zoom of <pane>'s window, if it has one. Run by
#          prefix+X and Set-NeovimLayout.sh before they touch the window.
#        Switch-PaneZoom.sh --sweep
#          Run by the hooks in common.conf (and by Restore-PickerPane.sh):
#          - a zoomed window whose zoomed pane has closed, or that got a pane
#            it did not have (a split), is zoomed out, and a new pane goes back
#            beside the pane it was split from;
#          - the stash of a window that has been closed is closed with it.
#
# How: tmux can only zoom one pane over all the others, and a pane is only ever
# hidden by not being in the window. So the panes to hide are parked in a stash
# window of the same session, which draws nothing in the status bar, and the
# window's layout is saved to be put back with them. The zoomed pane is marked
# @zoomed, which is what puts the magnifying glass on its border (see
# pane-border-format in common.conf; tmux's own zoom gets it from
# window_zoomed_flag).
#
# Where there is no radar column, or the pane is in it, there is nothing to
# keep beside it, and this falls back to tmux's own zoom.
#
# State, in user options:
#   window  @zoom_stash         the stash window's id
#           @zoom_layout        #{window_layout} before the zoom
#           @zoom_order         the pane ids in index order before the zoom
#   stash   @zoom_origin        the id of the window it holds panes for
#   pane    @zoomed             1 on the zoomed pane
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

# One run at a time: the hooks fire on every split and closed pane --
# this script's own included -- and two runs putting the same window back
# would tear it apart. Hooks run in the background, so waiting never holds
# tmux up.
exec 9>"${TMUX_TMPDIR:-/tmp}/tmux-pane-zoom-$(id -u).lock"
flock 9

# The stash window keeps only the tail wsl2/tmux.conf appends to the window
# formats (Workhorse and Paperboy after the last window), which it may well be
# holding: it gets the next free index. Where that option is not set the tail
# expands to nothing.
stash_format='#{?window_end_flag,#{E:@status_after_windows},}'

# window_exists <window id>
# display-message cannot tell: it expands to nothing, and succeeds, for a
# window that is gone.
window_exists() {
  tmux list-windows -a -F '#{window_id}' | grep -qxF "$1"
}

# widest_pane <window>
# Where joins go: the pane with the most room to split off.
widest_pane() {
  tmux list-panes -t "$1" -F '#{pane_width} #{pane_id}' | sort -rn | awk 'NR == 1 { print $2 }'
}

# restore <window>
# Brings the stashed panes back into <window> and puts its layout back.
#
# select-layout needs the very panes the layout was saved with, in the order
# they had. A pane that closed meanwhile has a stand-in split off for the
# layout and closed right after, so its room goes where it would have gone had
# it closed unzoomed. A pane that arrived meanwhile is set aside, and split back
# off the pane it came from once the layout is back -- same side, same share.
restore() {
  local window=$1 stash layout order zoomed="" active
  IFS='|' read -r stash layout order < <(tmux display-message -p -t "$window" \
    '#{@zoom_stash}|#{@zoom_layout}|#{@zoom_order}')
  [ -n "$stash" ] || return 0

  # tmux's own zoom on top of this one goes first: join-pane unzooms anyway.
  [ "$(tmux display-message -p -t "$window" '#{window_zoomed_flag}')" = 0 ] ||
    tmux resize-pane -Z -t "$window"
  active="$(tmux display-message -p -t "$window" '#{pane_id}')"

  local -a before=() extras=()
  local -A saved=() left=() top=() width=() height=()
  read -r -a before <<<"$order"
  local id l t w h flag
  for id in "${before[@]}"; do saved[$id]=1; done
  while IFS='|' read -r id l t w h flag; do
    left[$id]=$l top[$id]=$t width[$id]=$w height[$id]=$h
    [ "$flag" = 1 ] && zoomed=$id
    [ -n "${saved[$id]:-}" ] || extras+=("$id")
  done < <(tmux list-panes -t "$window" -F '#{pane_id}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}|#{@zoomed}')

  # Each new pane is split back off the pane it shares a whole edge with -- the
  # one it was split from, the zoomed pane first -- with the share it has of the
  # two.
  local -a rejoin=()
  local e s args pct
  for e in "${extras[@]}"; do
    local found=""
    for s in $zoomed "${!left[@]}"; do
      [ "$s" != "$e" ] || continue
      if [ "${top[$s]}" = "${top[$e]}" ] && [ "${height[$s]}" = "${height[$e]}" ]; then
        pct=$((width[$e] * 100 / (width[$e] + width[$s] + 1)))
        if [ $((left[$s] + width[$s] + 1)) = "${left[$e]}" ]; then found="$s|-h|$pct"; fi
        if [ $((left[$e] + width[$e] + 1)) = "${left[$s]}" ]; then found="$s|-hb|$pct"; fi
      elif [ "${left[$s]}" = "${left[$e]}" ] && [ "${width[$s]}" = "${width[$e]}" ]; then
        pct=$((height[$e] * 100 / (height[$e] + height[$s] + 1)))
        if [ $((top[$s] + height[$s] + 1)) = "${top[$e]}" ]; then found="$s|-v|$pct"; fi
        if [ $((top[$e] + height[$e] + 1)) = "${top[$s]}" ]; then found="$s|-vb|$pct"; fi
      fi
      [ -z "$found" ] || break
    done
    rejoin+=("$e|${found:-|-v|50}")
    tmux break-pane -d -s "$e"
  done

  # Thin splits off the widest pane, so a long stash never runs out of room;
  # select-layout sizes them. The stash window closes with its last pane -- or
  # is gone already, if every pane in it exited.
  local target pane
  target="$(widest_pane "$window")"
  if window_exists "$stash"; then
    while read -r pane; do
      tmux join-pane -d -h -l 3 -s "$pane" -t "$target"
    done < <(tmux list-panes -t "$stash" -F '#{pane_id}')
  fi

  local -A present=()
  local -a stand_ins=()
  local i
  while read -r id; do present[$id]=1; done < <(tmux list-panes -t "$window" -F '#{pane_id}')
  for i in "${!before[@]}"; do
    [ -z "${present[${before[i]}]:-}" ] || continue
    before[i]="$(tmux split-window -d -h -l 3 -t "$target" -P -F '#{pane_id}' 'sleep 60')"
    stand_ins+=("${before[i]}")
  done

  local current
  for i in "${!before[@]}"; do
    current="$(tmux list-panes -t "$window" -F '#{pane_id}' | sed -n "$((i + 1))p")"
    [ "$current" = "${before[i]}" ] || tmux swap-pane -d -s "${before[i]}" -t "$current"
  done
  tmux select-layout -t "$window" "$layout"
  for pane in "${stand_ins[@]}"; do tmux kill-pane -t "$pane"; done

  tmux set -w -u -t "$window" @zoom_stash \; set -w -u -t "$window" @zoom_layout \; \
    set -w -u -t "$window" @zoom_order
  [ -z "$zoomed" ] || tmux set -p -u -t "$zoomed" @zoomed 2>/dev/null || true

  local spec sibling side
  for spec in "${rejoin[@]}"; do
    IFS='|' read -r e sibling side pct <<<"$spec"
    [ -n "$sibling" ] && tmux list-panes -t "$window" -F '#{pane_id}' | grep -qxF "$sibling" ||
      sibling="$(widest_pane "$window")"
    [ "$pct" -ge 1 ] && [ "$pct" -le 99 ] || pct=50
    tmux join-pane -d "$side" -l "$pct%" -s "$e" -t "$sibling" 2>/dev/null ||
      tmux join-pane -d -s "$e" -t "$(widest_pane "$window")"
  done

  # Whoever had the focus keeps it -- the new pane, after a split.
  tmux select-pane -t "$active" 2>/dev/null || true
}

# sweep
# What the hooks run; see the usage above.
sweep() {
  local window stash origin order id flag dead
  while IFS='|' read -r window stash origin order; do
    if [ -n "$stash" ]; then
      local alive="" arrived=""
      while IFS='|' read -r id flag dead; do
        [ "$flag" = 1 ] && [ "$dead" = 0 ] && alive=yes
        [[ " $order " == *" $id "* ]] || arrived=yes
      done < <(tmux list-panes -t "$window" -F '#{pane_id}|#{@zoomed}|#{pane_dead}')
      [ -n "$alive" ] && [ -z "$arrived" ] || restore "$window"
    fi
    # A stash's panes belong to the window it was made for: closing the one
    # closes the other, as closing an unzoomed window would have.
    if [ -n "$origin" ] && ! window_exists "$origin"; then
      tmux kill-window -t "$window"
    fi
  done < <(tmux list-windows -a -F '#{window_id}|#{@zoom_stash}|#{@zoom_origin}|#{@zoom_order}')
}

case "${1:-}" in
  --sweep)
    sweep
    exit 0
    ;;
  --restore)
    restore "$(tmux display-message -p -t "${2:?Usage: Switch-PaneZoom.sh --restore <pane>}" '#{window_id}')"
    exit 0
    ;;
esac

pane="${1:?Usage: Switch-PaneZoom.sh <pane> | --restore <pane> | --sweep}"
window="$(tmux display-message -p -t "$pane" '#{window_id}')"

if [ -n "$(tmux display-message -p -t "$window" '#{@zoom_stash}')" ]; then
  restore "$window"
  tmux select-pane -t "$pane"
  exit 0
fi
if [ "$(tmux display-message -p -t "$window" '#{window_zoomed_flag}')" = 1 ]; then
  tmux resize-pane -Z -t "$window"
  exit 0
fi

# The radar column: by @layout_role, or -- in a window laid out before roles
# existed -- by label at the window's left edge, as find_layout_panes in
# Set-NeovimLayout.sh trusts them.
column="" column_width="" others=() order=()
while IFS='|' read -r id left width role label; do
  order+=("$id")
  if [[ $role =~ ^(git|agents|notes)$ ]] || { [ "$left" = 0 ] && [[ $label =~ ^(Git|Agents|Notes)$ ]]; }; then
    [ -n "$column" ] || column=$id column_width=$width
    [ "$id" != "$pane" ] || column="in"
  elif [ "$id" != "$pane" ]; then
    others+=("$id")
  fi
done < <(tmux list-panes -t "$window" -F '#{pane_id}|#{pane_left}|#{pane_width}|#{@layout_role}|#{@pane_label}')

if [ -z "$column" ] || [ "$column" = "in" ]; then
  tmux resize-pane -Z -t "$pane"
  exit 0
fi
[ "${#others[@]}" -gt 0 ] || warn "Nothing to zoom over: only the radar column is beside this pane"

tmux set -w -t "$window" @zoom_layout "$(tmux display-message -p -t "$window" '#{window_layout}')" \; \
  set -w -t "$window" @zoom_order "${order[*]}"

stash="$(tmux break-pane -d -P -F '#{window_id}' -s "${others[0]}" -n zoom-stash)"
tmux set -w -t "$stash" @zoom_origin "$window" \; \
  set -w -t "$stash" window-status-format "$stash_format" \; \
  set -w -t "$stash" window-status-current-format "$stash_format"
# Rebalanced after each join, so a long stash never runs out of room.
for other in "${others[@]:1}"; do
  tmux join-pane -d -s "$other" -t "$stash" \; select-layout -t "$stash" tiled
done

# A pane beside the column may have handed its width to the column, not to the
# zoomed pane.
tmux set -w -t "$window" @zoom_stash "$stash" \; set -p -t "$pane" @zoomed 1 \; \
  resize-pane -t "$column" -x "$column_width"
