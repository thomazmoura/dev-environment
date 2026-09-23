#!/usr/bin/env bash
# Runs a throwaway pwsh inside a popup (prefix+P), for a quick command that
# should not disturb the window's layout. The shell is the one a plain terminal
# split would get (prefix+%): a local pwsh in the directory of the pane the
# binding fired from, or, in an ssh session (prefix+N), a shell on the remote
# in the session's working directory -- pane_command decides which, exactly as
# it does for New-ToolPane.sh.
#
# Usage, as the shell-command of a display-popup binding:
#   bind P popup -d '#{pane_current_path}' '... Invoke-Popup.sh .../New-PopupShell.sh "#{pane_id}"'
#
# The popup closes when the shell exits, however it exits: the line is exec'd,
# so nothing is left behind it for the popup to fall back to.
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

origin="$(current_pane "${1:-}")"

exec bash -c "$(pane_command "$origin" "")"
