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
#          prefix+X, Set-NeovimLayout.sh and C-j/C-k/C-l before they touch
#          the window.
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
# Every change a zoom or a zoom-out makes goes to tmux as one command list,
# worked out beforehand from one look at the panes: tmux runs a list before it
# redraws, so the screen goes from before to after with nothing in between --
# no pane flashing by, no cursor hopping. That is why nothing below needs an id
# that only a command in the list would give: the stash is reached through a
# pane moved into it, and the panes go back straight into their places rather
# than being sorted afterwards.
#
# Where there is no radar column, or the pane is in it, there is nothing to
# keep beside it, and this falls back to tmux's own zoom.
#
# State, in user options:
#   window  @zoom_stash         1 while zoomed
#           @zoom_layout        #{window_layout} before the zoom
#           @zoom_order         the pane ids in index order before the zoom
#   stash   @zoom_origin        the id of the window it holds panes for
#   pane    @zoomed             1 on the zoomed pane
set -euo pipefail

# As tmux-helpers.sh's; not sourced, for a faster start on a navigation key.
warn() { tmux display-message "$*"; exit 1; }

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

# queue <command...> adds a command to the list; send hands the list to tmux.
# tmux drops the rest of a list after a command that fails, so every command
# queued must be one that cannot.
batch=()
queue() { batch+=("$@" ";"); }
send() {
  [ "${#batch[@]}" -eq 0 ] || tmux "${batch[@]}"
  batch=()
}

# restore <window> [pane to focus]
# Brings the stashed panes back into <window> and puts its layout back.
#
# select-layout needs the very panes the layout was saved with, in the order
# they had. Each pane goes back straight after the one before it in that order
# (join-pane puts a pane right after its target in tmux's list, or with -b
# right before it), split off the whole window (-f) so that a narrow target
# never runs out of room; select-layout then sizes them all. A pane that closed
# meanwhile has a stand-in take its place for the layout, closed right after,
# so its room goes where it would have gone had it closed unzoomed. A pane that
# arrived meanwhile is set aside, and split back off the pane it came from once
# the layout is back -- same side, same share.
restore() {
  local window=$1 focus=${2:-} flag layout order full active session
  IFS='|' read -r flag layout order full active session < <(tmux display-message -p -t "$window" \
    '#{@zoom_stash}|#{@zoom_layout}|#{@zoom_order}|#{window_zoomed_flag}|#{pane_id}|#{session_id}')
  [ -n "$flag" ] || return 0

  local -a before=() extras=()
  local -A saved=() present=() stashed=() left=() top=() width=() height=()
  local id l t w h mark zoomed=""
  read -r -a before <<<"$order"
  for id in "${before[@]}"; do saved[$id]=1; done
  while IFS='|' read -r id l t w h mark; do
    left[$id]=$l top[$id]=$t width[$id]=$w height[$id]=$h
    [ "$mark" = 1 ] && zoomed=$id
    if [ -n "${saved[$id]:-}" ]; then present[$id]=1; else extras+=("$id"); fi
  done < <(tmux list-panes -t "$window" -F '#{pane_id}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}|#{@zoomed}')
  while IFS='|' read -r id mark; do
    [ "$mark" != "$window" ] || stashed[$id]=1
  done < <(tmux list-panes -a -F '#{pane_id}|#{@zoom_origin}')

  # The pane the others are put back around: the first of the order still in
  # the window. Without one -- everything left is new -- there is no layout
  # to go back to: the stash just comes back.
  local anchor="" i
  for id in "${before[@]}"; do [ -z "${present[$id]:-}" ] || { anchor=$id; break; }; done
  if [ -z "$anchor" ]; then
    for id in "${!stashed[@]}"; do queue join-pane -d -s "$id" -t "$active"; done
    queue set -w -u -t "$window" @zoom_stash
    send
    tmux display-message "Zoom undone, but none of the window's panes were left: layout not restored"
    return 0
  fi

  # Stand-ins for the panes that closed, made in a window of their own, hidden
  # like the stash. The one list that runs before the rest, as their ids are
  # needed; nothing on screen changes.
  local -a stand_ins=()
  for i in "${!before[@]}"; do
    id=${before[i]}
    [ -z "${present[$id]:-}${stashed[$id]:-}" ] || continue
    if [ "${#stand_ins[@]}" -eq 0 ]; then
      before[i]="$(tmux new-window -d -t "$session:" -n zoom-stand-in -P -F '#{pane_id}' 'sleep 60')"
      tmux set -w -t "${before[i]}" window-status-format "$stash_format" \; \
        set -w -t "${before[i]}" window-status-current-format "$stash_format"
    else
      before[i]="$(tmux split-window -d -t "${stand_ins[0]}" -P -F '#{pane_id}' 'sleep 60' \; \
        select-layout -t "${stand_ins[0]}" tiled)"
    fi
    stand_ins+=("${before[i]}")
  done

  [ "$full" = 0 ] || queue resize-pane -Z -t "$window"

  # Each new pane is split back off the pane it shares a whole edge with -- the
  # one it was split from, the zoomed pane first -- with the share it has of the
  # two. Only panes of the layout are candidates: they are all back by then.
  local -a rejoin=()
  local e s pct found
  for e in "${extras[@]}"; do
    found=""
    for s in $zoomed "${!present[@]}"; do
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
    rejoin+=("$e|${found:-${zoomed:-$anchor}|-v|50}")
    queue break-pane -d -s "$e"
  done

  local -A back=()
  for id in "${!present[@]}"; do back[$id]=1; done
  for i in "${!before[@]}"; do
    id=${before[i]}
    [ -z "${back[$id]:-}" ] || continue
    if [ "$i" = 0 ]; then
      queue join-pane -d -f -h -b -l 3 -s "$id" -t "$anchor"
    else
      queue join-pane -d -f -h -l 3 -s "$id" -t "${before[i - 1]}"
    fi
    back[$id]=1
  done
  queue select-layout -t "$window" "$layout"
  for id in "${stand_ins[@]}"; do queue kill-pane -t "$id"; done

  queue set -w -u -t "$window" @zoom_stash
  queue set -w -u -t "$window" @zoom_layout
  queue set -w -u -t "$window" @zoom_order
  [ -z "$zoomed" ] || queue set -p -u -t "$zoomed" @zoomed

  local spec sibling side
  for spec in "${rejoin[@]}"; do
    IFS='|' read -r e sibling side pct <<<"$spec"
    [ "$pct" -ge 1 ] && [ "$pct" -le 99 ] || pct=50
    queue join-pane -d "$side" -l "$pct%" -s "$e" -t "$sibling"
  done

  # Whoever had the focus keeps it -- the new pane, after a split.
  queue select-pane -t "${focus:-$active}"
  send
}

# sweep
# What the hooks run; see the usage above.
sweep() {
  local window stash origin order id flag dead
  local -A windows=()
  while IFS='|' read -r window stash origin order; do windows[$window]=1; done \
    < <(tmux list-windows -a -F '#{window_id}|')
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
    if [ -n "$origin" ] && [ -z "${windows[$origin]:-}" ]; then
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
IFS='|' read -r window zoomed full layout < <(tmux display-message -p -t "$pane" \
  '#{window_id}|#{@zoom_stash}|#{window_zoomed_flag}|#{window_layout}')

if [ -n "$zoomed" ]; then
  restore "$window" "$pane"
  exit 0
fi
if [ "$full" = 1 ]; then
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

# The first pane moved out makes the stash window, and is how the rest of the
# list reaches it. Rebalanced after each join, so a long stash never runs out of
# room. Last, the column gets its width back: a pane beside it may have handed
# it its room, rather than to the zoomed pane.
stash=${others[0]}
queue set -w -t "$window" @zoom_layout "$layout"
queue set -w -t "$window" @zoom_order "${order[*]}"
queue break-pane -d -s "$stash" -n zoom-stash
queue set -w -t "$stash" @zoom_origin "$window"
queue set -w -t "$stash" window-status-format "$stash_format"
queue set -w -t "$stash" window-status-current-format "$stash_format"
for other in "${others[@]:1}"; do
  queue join-pane -d -s "$other" -t "$stash"
  queue select-layout -t "$stash" tiled
done
queue set -w -t "$window" @zoom_stash 1
queue set -p -t "$pane" @zoomed 1
queue resize-pane -t "$column" -x "$column_width"
send
