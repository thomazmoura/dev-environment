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
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

client="${1:-}"
home="$(tmux show -gqv @home_session)"

[ -n "$home" ] || warn "No home session: press H on a row of the Git pane"
# = makes the name exact rather than an fnmatch pattern.
tmux has-session -t "=$home" 2>/dev/null || warn "Home session $home is gone"

tmux switch-client ${client:+-c "$client"} -t "=$home"
