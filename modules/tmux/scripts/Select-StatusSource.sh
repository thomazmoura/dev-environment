#!/usr/bin/env bash
# Choose which host the status bar's Workhorse and Paperboy segments describe:
# this machine, or one of the hosts an ssh (prefix+N) or Docker (prefix+D)
# session is open on. Bound to prefix+C-k as a popup command in
# modules/tmux/common.conf.
#
#   ● local (thinkpad)
#     user@buildbox     3 sessions
#     docker:devenv     1 session
#
# The choice is the global option @status_source, which holds the host's
# @ssh_target and is unset for this machine. The status formats (wsl2/tmux.conf,
# tmux/tmux.conf) draw Get-RemoteStatus.sh while it is set, and this machine's
# own segments otherwise. The toasts and the agent count are not affected: they
# report this machine's agents, which already include the remote ones.
#
# Only hosts with this dev-environment (@ssh_devenv) are offered, as the
# segments come from its scripts there (see Get-RemoteStatus.sh). Once the last
# session on the chosen host closes, the bar goes back to this machine
# (Close-SshAgent.sh, on session-closed).
#
# Choosing a host also starts its Paperboy unread-count daemon when it is not
# running, in this popup, so a password prompt has somewhere to go.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

require_tools tmux fzf

current="$(tmux show-options -gqv @status_source)"

mark() {
  [ "$1" = "$current" ] && printf '●' || printf ' '
}

rows="$(printf '\t%s local (%s)\n' "$(mark "")" "$(hostname)")"
while read -r count target; do
  [ "$count" -eq 1 ] && unit=session || unit=sessions
  rows+=$'\n'"$(printf '%s\t%s %-30s %d %s' "$target" "$(mark "$target")" "$target" "$count" "$unit")"
done < <(tmux list-sessions -F $'#{@ssh_target}\t#{@ssh_devenv}' 2>/dev/null |
  awk -F'\t' '$1 != "" && $2 == "yes" { print $1 }' | sort | uniq -c)

selection="$(
  printf '%s\n' "$rows" \
    | fzf --reverse --delimiter=$'\t' --with-nth=2.. \
          --prompt='host> ' \
          --header='Show Workhorse and Paperboy from'
)" || exit 0

target="${selection%%$'\t'*}"
if [ -z "$target" ]; then
  tmux set-option -gu @status_source
else
  tmux set-option -g @status_source "$target"
  tmux refresh-client -S
  # The host's unread count needs paperboy.nvim's daemon running there, and
  # this machine may never have started one. Started here, still in the popup,
  # where the Exchange password can be typed when the host's keyring cannot
  # give it; a host already running it, or without Paperboy, has nothing to
  # ask. Workhorse needs nothing started: its query runs when the segment asks.
  start='if (-not $env:PAPERBOY_EWS_URL) { exit 0 }
$pidFile = "$env:XDG_RUNTIME_DIR/paperboy/daemon.pid"
if ((Test-Path $pidFile) -and (Test-Path "/proc/$((Get-Content $pidFile -Raw).Trim())")) { exit 0 }
Write-Host "Starting the Paperboy unread count on '"$target"'..."
& "$HOME/.modules/tmux/scripts/Start-PaperboyUnread.sh"'
  "$REMOTE_SSH" "${SSH_OPTS[@]}" -q -t "$target" "sh -c $(sq "$(remote_profile_command "$start")")"
fi
tmux refresh-client -S
