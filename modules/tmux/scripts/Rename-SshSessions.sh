#!/usr/bin/env bash
# Puts the user in front of ssh session names, or takes it off again, as users
# come and go on a host.
#
# Usage: Rename-SshSessions.sh
#   Run by New-SshSession.sh once it has created a session, and from the
#   session-closed hook in modules/tmux/common.conf for every session that
#   closes. No arguments: every ssh session is checked against the others.
#
# Sessions on a host are named <host>-<directory> while one user has sessions
# there, and user@<host>-<directory> once a second user opens one (see
# ssh_session_name in ssh-helpers.sh). The new session is named that way from
# the start; this renames the ones already open on that host to match, and
# renames them back once the last session of the other user has closed.
#
# A session opened before sessions recorded @ssh_name and @ssh_user is given
# both here, from its current name and its target.
#
# A rename whose name is taken by another session is skipped, rather than
# failing: the next run, at the next open or close, tries again. The home
# session mark (Set-HomeSession.sh) is by name, so it moves with a rename.
#
# A hook has nobody to report failure to, so every step here fails quietly.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

rows="$(tmux list-sessions -F $'#{session_id}\t#{session_name}\t#{@ssh_target}\t#{@ssh_name}\t#{@ssh_user}' 2>/dev/null)" || exit 0

# Fill in what older sessions lack first, so the names below are worked out
# from the same options on every session.
while IFS=$'\t' read -r id session target name user; do
  [ -n "$target" ] && ! is_docker_target "$target" || continue
  [ -n "$name" ] || tmux set-option -t "$id" @ssh_name "$session" 2>/dev/null
  [ -n "$user" ] || tmux set-option -t "$id" @ssh_user "$(ssh_user "$target")" 2>/dev/null
done <<< "$rows"

home="$(tmux show-options -gqv @home_session 2>/dev/null)"

while IFS=$'\t' read -r id session target _ _; do
  [ -n "$target" ] && ! is_docker_target "$target" || continue
  wanted="$(ssh_session_name "$(ssh_option "$id" @ssh_name)" "$target" "$(ssh_option "$id" @ssh_user)")"
  [ -n "$wanted" ] && [ "$wanted" != "$session" ] || continue
  tmux has-session -t "=$wanted" 2>/dev/null && continue
  tmux rename-session -t "$id" "$wanted" 2>/dev/null || continue
  [ "$home" = "$session" ] && "$scripts/Set-HomeSession.sh" "$wanted" >/dev/null 2>&1
done <<< "$rows"
exit 0
