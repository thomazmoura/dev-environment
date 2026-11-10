#!/usr/bin/env bash
# Keeps a current and a previous session that span this tmux and the linked
# machines' (tmux_link.py), for prefix+l to swap and for a new terminal to land
# on -- shared by every device that names the same group.
#
# Run by the client-session-changed and client-attached hooks (record), by
# prefix+l, prefix+L and prefix+Tab (last), all in modules/tmux/common.conf, by
# a linked machine over ssh (receive), and by Connect-Tmux.sh and tmuxa
# (current).
#
# Usage: Sync-LinkGroup.sh record <client>
#          <client> (the hook's #{hook_client}) has arrived in a session: it
#          becomes its group's current session and the one that was becomes
#          the previous. The group's other clients here follow, and the linked
#          machines are told. Not #{client_name}: for a switch that no client
#          asked for (switch-client -c from a script, which is how a group's
#          clients follow) that is some other client, and so is its session.
#        Sync-LinkGroup.sh last <client>
#          Takes <client> (#{client_name}) to its group's previous session,
#          wherever that is; to any other session when there is none.
#        Sync-LinkGroup.sh receive <group> <stamp> <current> <previous>
#          A linked machine's newer state for <group>. The group's clients
#          here follow it.
#        Sync-LinkGroup.sh current [<group>]
#          Two lines, the identity (user@hostname) of the machine the group's
#          current session is on and the session's name. Nothing when there is
#          none, or when the session is gone -- here, or on a linked machine
#          that says so (its server killed since): the state outlives both.
#        Sync-LinkGroup.sh group <client pid>
#          The group that client belongs to.
#
# A group is a name. A terminal gets its group from the loop around its client
# (Connect-Tmux.sh -g, or ~/.config/tmux-link/group on the device the loop runs
# on), which hands it to the tmux client as TMUX_LINK_GROUP; it is read back
# here from the client's environment. A client no loop started has this
# machine's own file, and `shared` without one. Devices in the same group show
# the same session; a device with a name of its own keeps its own pair.
#
# The state is a file per group on every machine,
#
#   ~/.cache/tmux-link/groups/<group>    stamp, current, previous: a line each
#
# with every session written as <host>:<session>, this machine's included, so
# it reads the same everywhere. Only arriving somewhere records: nothing that
# switches has to say so, and a hop to a linked machine is recorded there, by
# the client attaching. The newest stamp (milliseconds) wins.
#
# Self-contained, with nothing sourced: this runs on every switch.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
config="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-link"
groups="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-link/groups"
# This script on another machine. $HOME is left for that machine's shell.
remote_self='"$HOME/.modules/tmux/scripts/Sync-LinkGroup.sh"'

# As in Connect-Tmux.sh and tmux_link.identity(), which this has to agree with.
if [ -n "${TMUX_LINK_IDENTITY:-}" ]; then
  me="$TMUX_LINK_IDENTITY"
else
  me="$(id -un)@$(hostname | cut -d. -f1 | tr '[:upper:]' '[:lower:]')"
fi
host="${me##*@}"

sq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

clean_group() { printf '%s' "$1" | tr -c 'A-Za-z0-9_-' '_'; }

default_group() {
  local name=""
  [ -f "$config/group" ] && IFS= read -r name <"$config/group"
  clean_group "${name:-shared}"
}

# group_of <client pid>
group_of() {
  local name=""
  if [ -r "/proc/$1/environ" ]; then
    name="$(tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null | sed -n 's/^TMUX_LINK_GROUP=//p' | head -n 1)"
  fi
  if [ -n "$name" ]; then clean_group "$name"; else default_group; fi
}

# The state of <group>, into stamp, current and previous.
read_state() {
  stamp=0 current="" previous=""
  [ -f "$groups/$1" ] || return 0
  { IFS= read -r stamp; IFS= read -r current; IFS= read -r previous; } <"$groups/$1"
  [[ $stamp =~ ^[0-9]+$ ]] || stamp=0
}

write_state() {
  printf '%s\n%s\n%s\n' "$stamp" "$current" "$previous" >"$groups/$1.new" &&
    mv -f "$groups/$1.new" "$groups/$1"
}

lock() {
  mkdir -p "$groups"
  exec 9>"$groups/.lock"
  command -v flock >/dev/null 2>&1 && flock -w 5 9
}

unlock() { exec 9>&-; }

# address_of <identity>: how to reach it, as Connect-Tmux.sh's address()
# looks it up -- the aliases, then the peers, then the identity itself.
address_of() {
  local file found
  for file in "$config/aliases" "$config/peers"; do
    [ -f "$file" ] || continue
    found="$(awk -F '\t' -v id="$1" '$1 == id && $2 != "" { print $2; exit }' "$file")"
    [ -n "$found" ] && { printf '%s\n' "$found"; return; }
  done
  printf '%s\n' "$1"
}

# identity_of <host>: the linked machine with that host name, or this one.
identity_of() {
  if [ "$1" = "$host" ]; then
    printf '%s\n' "$me"
  else
    awk -F '\t' -v host="$1" '{ h = $1; sub(/^.*@/, "", h) } h == host { print $1; exit }' \
      "$config/peers" 2>/dev/null
  fi
}

# follow <group> [<client pid to leave alone>]
# Takes the group's clients on this tmux to its current session: a switch, or
# for a session on a linked machine the hop Switch-LinkSession.sh arranges.
# Each arrival runs record again, for the session that is already current,
# which changes nothing -- so this does not echo.
follow() {
  local group=$1 skip=${2:-} pid name session control
  read_state "$group"
  [ -n "$current" ] || return 0
  if [ "${current%%:*}" = "$host" ]; then
    tmux has-session -t "=${current#*:}" 2>/dev/null || return 0
  fi
  while IFS=$'\t' read -r pid name session control; do
    [ -n "$pid" ] && [ "$pid" != "$skip" ] && [ "$control" != 1 ] || continue
    [ "$host:$session" != "$current" ] || continue
    [ "$(group_of "$pid")" = "$group" ] || continue
    "$scripts/Switch-LinkSession.sh" -c "$name" "$current" >/dev/null 2>&1
  done < <(tmux list-clients -F $'#{client_pid}\t#{client_name}\t#{session_name}\t#{client_control_mode}' 2>/dev/null)
}

# push <group>
# Tells every linked machine, each in the background over the connection the
# link keeps open (ControlPath as SSH_OPTS in ssh-helpers.sh spells it). Never
# the master itself, and no pipes left for tmux's run-shell to wait on.
push() {
  local group=$1 address command
  [ -f "$config/peers" ] || return 0
  read_state "$group"
  command="$remote_self receive $(sq "$group") $(sq "$stamp") $(sq "$current") $(sq "$previous")"
  while IFS=$'\t' read -r _ address; do
    [ -n "$address" ] || continue
    ssh -n -o ControlMaster=no -o "ControlPath=$HOME/.ssh/tmux-%C" -o BatchMode=yes \
      -o ConnectTimeout=5 "$address" "$command" >/dev/null 2>&1 9>&- &
  done <"$config/peers"
}

case "${1:-}" in
  record)
    client="${2:-}"
    [ -n "$client" ] || exit 0
    # Where the client is, asked of the client itself rather than passed in:
    # the answer is then right whoever caused the switch.
    IFS=$'\t' read -r pid control session < <(
      tmux list-clients -F $'#{client_name}\t#{client_pid}\t#{client_control_mode}\t#{session_name}' 2>/dev/null |
        awk -F '\t' -v client="$client" '$1 == client { printf "%s\t%s\t%s\n", $2, $3, $4; exit }')
    [ -n "${pid:-}" ] && [ -n "${session:-}" ] && [ "$control" != 1 ] || exit 0
    group="$(group_of "$pid")"
    key="$host:$session"
    lock
    read_state "$group"
    if [ "$current" = "$key" ]; then
      unlock
      exit 0
    fi
    # Milliseconds, out of bash rather than `date +%s%3N`, which not every
    # date pads the same way.
    now="${EPOCHREALTIME/[.,]/}"
    now="${now:0:13}"
    [ "$now" -gt "$stamp" ] 2>/dev/null || now=$((stamp + 1))
    previous="$current" current="$key" stamp="$now"
    write_state "$group"
    unlock
    follow "$group" "$pid"
    push "$group"
    ;;

  last)
    client="${2:?client}"
    IFS=$'\t' read -r pid session < <(tmux display-message -c "$client" -p $'#{client_pid}\t#{session_name}')
    [ -n "${pid:-}" ] || exit 0
    here="$host:$session"
    read_state "$(group_of "$pid")"
    target="$previous"
    # A client out of step with its group (the state came from elsewhere while
    # it could not follow) goes to where the group is.
    [ "$target" != "$here" ] || target="$current"
    if [ "$target" = "$here" ]; then
      target=""
    elif [ "${target%%:*}" = "$host" ] && ! tmux has-session -t "=${target#*:}" 2>/dev/null; then
      target=""
    fi
    if [ -z "$target" ]; then
      # No previous session yet, or it is gone: any other one. The next of this
      # tmux, and a linked machine's when this tmux has just the one.
      if [ "$(tmux list-sessions 2>/dev/null | wc -l)" -gt 1 ]; then
        tmux switch-client -c "$client" -n
        exit 0
      fi
      target="$("$scripts/Get-TmuxLink.py" --format=sessions 2>/dev/null | head -n 1 | cut -f1)"
    fi
    if [ -z "$target" ]; then
      tmux display-message -c "$client" "No other session to switch to"
      exit 0
    fi
    "$scripts/Switch-LinkSession.sh" -c "$client" "$target"
    ;;

  receive)
    group="$(clean_group "${2:?group}")"
    theirs="${3:?stamp}" their_current="${4:-}" their_previous="${5:-}"
    [[ $theirs =~ ^[0-9]+$ ]] || exit 0
    lock
    read_state "$group"
    if [ "$theirs" -le "$stamp" ]; then
      unlock
      exit 0
    fi
    stamp="$theirs" current="$their_current" previous="$their_previous"
    write_state "$group"
    unlock
    follow "$group"
    ;;

  current)
    group="$(clean_group "${2:-$(default_group)}")"
    read_state "$group"
    [ -n "$current" ] || exit 0
    identity="$(identity_of "${current%%:*}")"
    [ -n "$identity" ] || exit 0
    if [ "$identity" = "$me" ]; then
      tmux has-session -t "=${current#*:}" 2>/dev/null || exit 0
    else
      # Asked of that machine over the link's connection, with nothing of
      # this dev-environment needed there -- it may be a version behind. Only
      # its own "no" (1) drops it: when it cannot be asked (255: no
      # connection, a key to unlock) the attach's own ssh is left to try.
      ssh -n -o ControlMaster=no -o "ControlPath=$HOME/.ssh/tmux-%C" -o BatchMode=yes \
        -o ConnectTimeout=5 "$(address_of "$identity")" \
        "tmux has-session -t $(sq "=${current#*:}")" >/dev/null 2>&1 9>&-
      [ $? -ne 1 ] || exit 0
    fi
    printf '%s\n%s\n' "$identity" "${current#*:}"
    ;;

  group)
    group_of "${2:?client pid}"
    echo
    ;;

  *)
    printf 'Usage: Sync-LinkGroup.sh record|last|receive|current|group ...\n' >&2
    exit 2
    ;;
esac
exit 0
