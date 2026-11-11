#!/usr/bin/env bash
# Switches a client to the home session (prefix+h). The session is marked with
# H in the Git pane; see Set-HomeSession.sh.
#
# Usage: Switch-HomeSession.sh <client>
#   <client> is the binding's #{client_name}: run-shell has no client of its
#   own, so switch-client has to be told which one to move.
#
# The option is read here rather than spelled as #{@home_session} in the
# binding, which does not expand in every kind of binding.
#
# A home session on a linked machine (<host>:<session>) is gone to through
# Switch-LinkSession.sh while the link sampler lists it (Get-TmuxLink.py).
# When it does not -- that machine stopped answering -- the client stays put
# and a popup connects to it again first (Connect-LinkSession.sh), moving the
# client only once the session is found there.
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

client="${1:-}"
home="$(tmux show -gqv @home_session)"

[ -n "$home" ] || warn "No home session: press H on a row of the Git pane"

if [[ $home == *:* ]]; then
  scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
  if "$scripts/Get-TmuxLink.py" --format=sessions 2>/dev/null | cut -f1 | grep -qxF -- "$home"; then
    exec "$scripts/Switch-LinkSession.sh" ${client:+-c "$client"} "$home"
  fi
  exec tmux display-popup ${client:+-c "$client"} -E -w 80 -h 10 -x C -y C \
    "$scripts/Invoke-Popup.sh" "$scripts/Connect-LinkSession.sh" ${client:+-c "$client"} "$home"
fi

# = makes the name exact rather than an fnmatch pattern.
tmux has-session -t "=$home" 2>/dev/null || warn "Home session $home is gone"

tmux switch-client ${client:+-c "$client"} -t "=$home"
