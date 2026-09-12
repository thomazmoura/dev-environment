#!/usr/bin/env bash
# Puts the remote's ssh key back in the host's shared agent when it is not
# there, before a pane of an ssh session connects.
#
# Usage: Unlock-RemoteKey.sh <user@host>
#   Typed into every new pane of an ssh session on a dev-environment remote,
#   in front of the pane's own ssh (ssh_command in ssh-helpers.sh). A script
#   rather than the function itself because the pane's shell has none of the
#   helpers loaded.
#
# The normal case is silent: the agent holds the key and this is one round
# trip over the master connection. When the agent has died -- the remote
# rebooted, or another machine's session-closed hook stopped it -- or the key
# has expired, this pane asks for the password, once, and the panes after it
# find the key again. See remote_agent_unlock.
#
# The host is also recorded for the session-closed hook, so an agent this
# starts is stopped with the host's last session, like one started by prefix+N.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

target="${1:-}"
[ -n "$target" ] || exit 0

add_agent_target "$target"
remote_agent_unlock "$target"
