#!/usr/bin/env bash
# Tells Ghostty's pane_crosshair shader that focus just moved, so it flashes a
# crosshair on the cursor's new position.
#
# Usage: Show-PaneCrosshair.sh [<client_tty>]
#   Run from the after-select-pane, after-select-window, session-window-changed
#   and client-session-changed hooks (see modules/tmux/common.conf) with the
#   client's tty, and without arguments from NeoVim's WinEnter
#   (modules/nvim-config/lua/config/pane_crosshair.lua), which asks tmux for it.
#
# How: a shader keeps nothing between frames and Ghostty hands it no wall
# clock, so the signal is a flag it can read on any frame -- palette entry 16,
# raised to #010203 (invisible next to its default #000000) with OSC 4 and
# reset with OSC 104 half a second later. The shader times the animation from
# the cursor jump the focus change itself made (see the .glsl header in
# modules/ghostty/shaders/pane_crosshair.glsl). The sequences are written
# straight to the client's tty: tmux keeps OSC 4 from panes to itself.
#
# Coming back from a pane without a cursor (the Git and Agents feeds hide it)
# needs one more push. Ghostty only tracks a cursor it can see, so it still
# holds the one from before, and returning to that pane puts the cursor back
# exactly there: no jump, no clock. A cursor colour change counts as a cursor
# change too, so those arrivals also nudge the cursor colour by one step
# (NUDGE, next to the theme's #c0caf5). It isn't done on every switch because
# a nudge landing a frame after the jump would cut the warp trail short. Each
# run records whether the pane it arrived in shows a cursor, which is how the
# next run knows what it left.
#
# Switching again inside the half second must not have the earlier run's reset
# cut the new crosshair short, so each run stamps a file per tty and only the
# newest one resets -- the flag and the cursor colour together (OSC 112 gives
# the cursor back its configured colour).
#
# Only Ghostty clients are flagged. Never fails, so it never breaks the hook or
# autocmd that runs it.
set -u

tty="${1:-}"
[ -n "$tty" ] || tty=$(tmux display-message -p '#{client_tty}' 2>/dev/null)
[ -n "$tty" ] && [ -w "$tty" ] || exit 0

termname=$(tmux display-message -p -c "$tty" '#{client_termname}' 2>/dev/null)
[ "$termname" = "xterm-ghostty" ] || exit 0

NUDGE='c0/ca/f4'

stamp="${XDG_RUNTIME_DIR:-/tmp}/pane-crosshair-${tty//\//_}"

# 1 when the pane arrived in shows a cursor, 0 when its program hides it
visible=$(tmux display-message -p -c "$tty" '#{cursor_flag}' 2>/dev/null)
left_visible=$(cat "$stamp.cursor" 2>/dev/null)
printf '%s' "$visible" > "$stamp.cursor" 2>/dev/null
[ "$visible" = 1 ] || exit 0

token="$$-$(date +%s%N)"
printf '%s' "$token" > "$stamp" 2>/dev/null

st=$'\e\\'
signal=$'\e]4;16;rgb:01/02/03'"$st"
[ "$left_visible" = 0 ] && signal+=$'\e]12;rgb:'"$NUDGE$st"
printf '%s' "$signal" > "$tty" 2>/dev/null

sleep 0.5

[ "$(cat "$stamp" 2>/dev/null)" = "$token" ] || exit 0
printf '%s' $'\e]104;16'"$st"$'\e]112'"$st" > "$tty" 2>/dev/null
rm -f "$stamp"

exit 0
