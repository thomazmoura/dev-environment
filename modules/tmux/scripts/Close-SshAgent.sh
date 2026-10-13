#!/usr/bin/env bash
# Stops the shared ssh agent of every host that no session uses any more.
#
# Usage: Close-SshAgent.sh
#   Run from the session-closed hook in modules/tmux/common.conf, for every
#   session that closes. No arguments: by the time the hook runs the closed
#   session and its options are gone, so which host it was on can no longer be
#   asked. Instead this compares the hosts that were given an agent
#   (@ssh_agent_targets, see ssh-helpers.sh) with the hosts the remaining
#   sessions are on, and stops the agents nobody is left to use.
#
# Stopping the agent is what drops the unlocked key from the remote's memory.
# It is done over the master connection, which ControlPersist keeps for ten
# minutes after the last pane closed, so it needs no password. When the host
# cannot be reached the target is dropped anyway: the agent's own lifetime
# (SSH_AGENT_LIFETIME) is what covers that case, and retrying on every later
# session close would only add a timeout to each.
#
# It also points the status bar back at this machine when the host its
# Workhorse and Paperboy segments came from (@status_source, set on prefix+C-k
# by Select-StatusSource.sh) has no session left.
#
# A hook has nobody to report failure to, so every step here fails quietly.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

in_use="$(tmux list-sessions -F '#{@ssh_target}' 2>/dev/null)"

status_source="$(tmux show-options -gqv @status_source 2>/dev/null)"
if [ -n "$status_source" ] && ! grep -qxF -- "$status_source" <<<"$in_use"; then
  tmux set-option -gu @status_source \; refresh-client -S 2>/dev/null
fi

targets="$(agent_targets)"
[ -n "$targets" ] || exit 0

killed=()
for target in $targets; do
  grep -qxF -- "$target" <<<"$in_use" && continue
  remote_agent_kill "$target" >/dev/null 2>&1
  killed+=("$target")
done
[ "${#killed[@]}" -gt 0 ] || exit 0

# Read again rather than writing back the list from the top: the kills above
# take a round trip each, and prefix+N may have added a host meanwhile.
keep=()
for target in $(agent_targets); do
  printf '%s\n' "${killed[@]}" | grep -qxF -- "$target" || keep+=("$target")
done
tmux set-option -g @ssh_agent_targets "${keep[*]}" 2>/dev/null
exit 0
