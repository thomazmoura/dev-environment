#!/usr/bin/env bash
# Tells an ssh session's remote which terminal is looking at it, so an nvim
# there draws image previews (paperboy.nvim) with what that terminal has:
# Kitty graphics on Ghostty, half-blocks on the phone.
#
# Usage: Sync-SshClientTerminal.sh <client_tty> [session]
#   Run from the client-session-changed and client-attached hooks (see
#   modules/tmux/common.conf) with the arriving client's tty, for the session
#   it is in, and by New-SshSession.sh as it opens a session, before its panes
#   start and the client switches to it -- so that one names the session. A
#   session that is not an ssh one is left alone.
#
# Why: the remote nvim runs in a pane of this tmux with no $TMUX of its own, so
# it cannot ask tmux which client is attached, and a query to the terminal is
# answered by this tmux for itself: DA1 says Sixel whatever the client, and the
# Kitty query is dropped. So this writes what tmux knows of the client to a
# file on the remote, whose path every pane gets as $TMUX_CLIENT_TERMINAL
# (ssh_command and ssh_client_terminal_file in ssh-helpers.sh). One line:
#
#   <termname> <termtype>|<sixel_support>|<termfeatures>|<allow-passthrough>|<cell width> <cell height>
#
# The file is replaced whole (written aside, then moved), so a reader watching
# it never sees half a line. The last line written is kept in the session's
# @ssh_client_terminal: switching between sessions with the same client makes
# no ssh. BatchMode because this runs from `run-shell -b`, with nothing to type
# a password into -- with the master connection up, it never needs one.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

tty="${1:?usage: Sync-SshClientTerminal.sh <client_tty> [session]}"

if [ -n "${2:-}" ]; then
  session="$(tmux display-message -p -t "$2" '#{session_id}' 2>/dev/null)" || exit 0
else
  session="$(tmux display-message -p -c "$tty" '#{session_id}' 2>/dev/null)" || exit 0
fi
[ -n "$session" ] || exit 0
target="$(tmux show-options -qv -t "$session" @ssh_target 2>/dev/null)"
[ -n "$target" ] || exit 0

client="$(tmux display-message -p -c "$tty" \
  '#{client_termname} #{client_termtype}|#{sixel_support}|#{client_termfeatures}')" || exit 0
passthrough="$(tmux show-options -gqv allow-passthrough)"
cell="$(tmux display-message -p -c "$tty" '#{client_cell_width} #{client_cell_height}')"
line="$client|${passthrough:-off}|$cell"

[ "$(tmux show-options -qv -t "$session" @ssh_client_terminal 2>/dev/null)" = "$line" ] && exit 0

file="$(ssh_client_terminal_file "$session")"
# From the home, which docker exec does not start in as ssh does
write="cd && mkdir -p $(sq "$(dirname "$file")") && cat > $(sq "$file.tmp") && mv $(sq "$file.tmp") $(sq "$file")"
printf '%s\n' "$line" |
  "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$target" "sh -c $(sq "$write")" ||
  exit 0
tmux set-option -t "$session" @ssh_client_terminal "$line"
