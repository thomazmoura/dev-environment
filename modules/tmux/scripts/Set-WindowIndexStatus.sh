#!/usr/bin/env bash
# Shows the active window as an index after the session name (`session:1`) in
# place of the window list, which spends a name and flags on every window.
#
# Usage: Set-WindowIndexStatus.sh
#   Run from tmux.conf and wsl2/tmux.conf right after TPM, as tmux-power assigns
#   status-left and both window formats wholesale when it loads, and before
#   anything is appended to them: wsl2/tmux.conf's Workhorse/Paperboy tail goes
#   on the emptied window formats, so it still draws after the last window.
#
# How: tmux-power draws the session as ` #S ` in status-left; that becomes
# ` #S:#I `. The window formats are emptied. Set-SshTheme.sh copies both from
# the globals, so ssh sessions get the same.
set -uo pipefail

left="$(tmux show-options -gv status-left 2>/dev/null)" || exit 0
# Already done: a second run before tmux-power has reassigned it.
[[ $left == *'#S:#I'* ]] || left="${left//' #S '/' #S:#I '}"

tmux set-option -g status-left "$left" \; \
  set-option -gw window-status-format '' \; \
  set-option -gw window-status-current-format ''
exit 0
