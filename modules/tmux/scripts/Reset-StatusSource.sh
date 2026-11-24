#!/usr/bin/env bash
# Points the status bar back at this machine once the host its Workhorse and
# Paperboy segments came from has no session left and is not a linked machine
# (prefix+t,l removes a link; tmux_link.py).
#
# Usage: Reset-StatusSource.sh
#   Run from the session-closed hook in modules/tmux/common.conf, for every
#   session that closes. No arguments: by the time the hook runs the closed
#   session and its options are gone, so which host it was on can no longer be
#   asked. Instead this compares the host the segments come from
#   (@status_source, set on prefix+C-k by Select-StatusSource.sh) with the
#   hosts the remaining sessions are on, and with the linked machines'
#   addresses, whose sessions are on their own tmux servers.
#
# A hook has nobody to report failure to, so every step here fails quietly.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
in_use="$(tmux list-sessions -F '#{@ssh_target}' 2>/dev/null
  "$scripts/Get-TmuxLink.py" --format=peers 2>/dev/null | cut -f2)"

status_source="$(tmux show-options -gqv @status_source 2>/dev/null)"
if [ -n "$status_source" ] && ! grep -qxF -- "$status_source" <<<"$in_use"; then
  tmux set-option -gu @status_source \; refresh-client -S 2>/dev/null
fi
exit 0
