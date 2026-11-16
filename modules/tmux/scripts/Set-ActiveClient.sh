#!/usr/bin/env bash
# Decides which attached tmux client is the device in use -- the PC or the
# phone -- and makes everything that depends on the device follow it:
#
#   - window sizes: every other client gets tmux's ignore-size flag, so the
#     windows take the active client's size and no other's. Repair-Layouts.sh
#     (window-resized hook) then refits the standard layouts to it.
#   - pane backgrounds: Set-PaneBackground.sh, opaque for Termux.
#
# The client is kept in @active_client (its name, the tty).
#
# Usage: Set-ActiveClient.sh <event> [client]
#   Run from the hooks in modules/tmux/common.conf, with the hook's name and
#   ##{hook_client}.
#
# Why: one device is used at a time -- something started on the PC, continued
# on the phone, then back. tmux's own `window-size latest` follows any client
# that sends a key, a focus-in or a terminal resize, per window, and the
# backgrounds used to follow any client attaching or switching session, so the
# two could disagree -- and a session switch made on the phone, which
# Sync-LinkGroup.sh repeats on the PC's client, counted as the PC arriving.
#
# What makes a client the active one:
#   client-attached         a terminal attaching (a new client)
#   client-focus-in         its terminal window getting the focus (Ghostty,
#                           WezTerm: clicking or alt-tabbing back to it)
#   client-session-changed  switching session, or typing into a window another
#   client-active           client was the latest in -- both only when the
#                           client itself had input in the last few seconds
#                           (#{client_activity}), so a client moved by a
#                           script (the group following) or a terminal resized
#                           while nobody is at it don't count
#   client-detached         the active client leaving: the remaining client
#                           with the most recent input takes over
# A focus-out counts for nothing: the PC losing focus to another app, or its
# screen locking, leaves the phone (or the PC) as it was.
#
# Not seen: typing on the PC with its terminal focused all along, into a
# window only the PC shows -- no hook fires for that. Clicking the terminal
# (focus-in) or switching session or window does it.
set -uo pipefail

event=${1:-}
client=${2:-}
# How recent a client's last input must be for a session switch or client-active
# to count as that client's own doing.
fresh_seconds=3

here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")

# Several hooks fire for one arrival; one run at a time, each seeing the state
# the previous one left.
exec 9>"${TMUX_TMPDIR:-/tmp}/tmux-active-client-$(id -u).lock"
flock -w 5 9 || exit 0

current=$(tmux show-options -gqv @active_client 2>/dev/null)
now=$(date +%s)

# Every attached client but control-mode ones (they size nothing), by name.
declare -A pid activity flags
while read -r name client_pid client_activity client_flags; do
  [ -n "$name" ] || continue
  pid[$name]=$client_pid activity[$name]=$client_activity flags[$name]=$client_flags
done < <(tmux list-clients -F \
  '#{?client_control_mode,,#{client_name} #{client_pid} #{client_activity} #{client_flags}}' 2>/dev/null)
[ ${#pid[@]} -gt 0 ] || exit 0

active=
case "$event" in
  client-attached|client-focus-in)
    [ -n "${pid[$client]:-}" ] && active=$client
    ;;
  client-session-changed|client-active)
    [ -n "${pid[$client]:-}" ] && [ $((now - activity[$client])) -le $fresh_seconds ] && active=$client
    ;;
esac

if [ -z "$active" ]; then
  if [ -n "$current" ] && [ -n "${pid[$current]:-}" ]; then
    active=$current
  else
    # The active client is gone (or none was ever set): the most recent input.
    for name in "${!pid[@]}"; do
      [ -n "$active" ] && [ "${activity[$name]}" -le "${activity[$active]}" ] || active=$name
    done
  fi
fi

# The active client's flag cleared first, so there is never a moment with every
# client ignored (which tmux treats as none ignored). One tmux call, so the
# windows are resized once.
args=()
for name in "${!pid[@]}"; do
  if [ "$name" = "$active" ]; then
    [[ ",${flags[$name]}," == *,ignore-size,* ]] && args=(refresh-client -t "$name" -f '!ignore-size' \; "${args[@]}")
  else
    [[ ",${flags[$name]}," == *,ignore-size,* ]] || args+=(refresh-client -t "$name" -f ignore-size \;)
  fi
done
[ "$active" = "$current" ] || args+=(set-option -g @active_client "$active" \;)
[ ${#args[@]} -eq 0 ] || tmux "${args[@]}"

"$here/Set-PaneBackground.sh" "${pid[$active]}"
