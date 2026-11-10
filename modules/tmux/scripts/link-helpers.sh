#!/usr/bin/env bash
# Shared helpers for linked tmux servers (tmux_link.py), for the scripts that
# make a link or open a session across one: New-SshSession.sh (prefix+N),
# New-CodeSession.sh (prefix+/) and Select-TmuxLink.sh (prefix+t,l). Sourced,
# after tmux-helpers.sh, never run.

link_cli="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/Get-TmuxLink.py"
# The same CLI on another machine. $HOME is left for that machine's shell.
remote_link_cli='"$HOME/.modules/tmux/scripts/Get-TmuxLink.py"'

# link_probe <address>
# The identity (user@hostname) of the machine at <address> when it can be
# linked: it has this dev-environment in a version that knows about links, and
# is not this machine. Nothing otherwise, and prefix+N then opens an ssh
# session as it always has. Over the connection the caller has just made.
link_probe() {
  local found
  found="$("$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$1" \
    "sh -c $(sq "$remote_link_cli --identity")" </dev/null 2>/dev/null | tail -n 1)" || return 0
  [[ $found == *@* ]] && [ "$found" != "$("$link_cli" --identity)" ] && printf '%s\n' "$found"
  return 0
}

# link_make <identity> <address>
# Links this machine and that one, both ways: each lists the other's sessions
# and folders from then on. The other side reaches this one by its identity
# unless its ~/.config/tmux-link/aliases says otherwise.
link_make() {
  local identity=$1 address=$2 me
  me="$("$link_cli" --identity)"
  "$link_cli" --link "$identity" "$address"
  "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$address" \
    "sh -c $(sq "$remote_link_cli --link $(sq "$me") $(sq "$me")")" </dev/null 2>/dev/null
  "$(dirname "$link_cli")/Start-TmuxLink.py" --ensure
}

# link_remove <identity> <address>
link_remove() {
  local identity=$1 address=$2 me
  me="$("$link_cli" --identity)"
  "$link_cli" --unlink "$identity"
  "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$address" \
    "sh -c $(sq "$remote_link_cli --unlink $(sq "$me")")" </dev/null 2>/dev/null
  return 0
}

# create_on_peer <identity> <address> <directory> <columns> <rows>
# Opens a session for <directory> in the linked machine's tmux -- its own
# New-CodeSession.sh -d, with the standard layout, sized <columns>x<rows> --
# and prints its name. Dies when it could not.
#
# Through that machine's login shell, like a pane of an ssh session that does
# not go through pwsh (remote_run in ssh-helpers.sh): this may be what starts
# its tmux server, whose panes then inherit this environment -- the profile's
# PATH, the user session's variables and the host's shared agent.
create_on_peer() {
  local identity=$1 address=$2 directory=$3 create session
  create="$(printf '"$HOME/.modules/tmux/scripts/New-CodeSession.sh" -d -x %s -y %s %s' \
    "$4" "$5" "$(sq "$directory")")"
  # stderr: stdout is the session name, for the caller.
  printf 'Opening %s on %s...\n' "$(basename "$directory")" "${identity##*@}" >&2
  session="$("$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=10 "$address" \
    "$(remote_session_env)$(remote_agent_env)exec \"\$SHELL\" -lc $(sq "$create")" </dev/null | tail -n 1)"
  [ -n "$session" ] || die "Could not open a session for $directory on $address"
  printf '%s\n' "$session"
}

# open_on_peer <identity> <address> <directory>
# create_on_peer, sized for this client, then moves the client there
# (Switch-LinkSession.sh). Run from a popup.
open_on_peer() {
  local identity=$1 address=$2 directory=$3 session
  session="$(create_on_peer "$identity" "$address" "$directory" \
    "$(tmux display-message -p '#{client_width}')" "$(tmux display-message -p '#{client_height}')")" || exit 1
  "$(dirname "$link_cli")/Switch-LinkSession.sh" "${identity##*@}:$session"
}
