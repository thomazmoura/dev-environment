#!/usr/bin/env bash
# Attaches a terminal to a tmux session on this machine or on a linked one, and
# moves it between them: the client side of linked tmux servers.
#
# Linked machines (prefix+N, see tmux_link.py) each keep their own tmux server.
# A session on another machine is not reached from inside this one -- the
# terminal leaves this tmux and attaches to that one, so there is never more
# than one ssh between the device being typed on and the tmux on screen. tmux
# cannot do that by itself, a client belongs to one server, so this script
# stands around the client: it is what runs `tmux attach` or the ssh, and when
# that ends it looks for a handoff saying where to go next.
#
# Run by vtmux and tmuxa (DevHelpers.psm1) in place of `tmux attach-session`,
# and on a device with no tmux of its own (Termux/termux-setup.sh installs it
# as ~/bin/tmux-link). Switch-LinkSession.sh is what leaves the handoff, for
# every picker and feed that lands on a linked session.
#
# Usage: Connect-Tmux.sh [-t <identity>] [-p <pane>] [-g <group>] [<session>]
#          The loop. Attaches to <session> here, or with -t on the machine
#          <identity> names (user@hostname, an address, or an alias), over ssh.
#          -p lands on that pane. With neither a session nor a pane it goes to
#          its group's current session, on whichever machine that is. Ends
#          when the tmux it shows is detached from (prefix+d) or ends, as
#          `tmux attach` does.
#        Connect-Tmux.sh --remote <id> [<session> [<pane> [<group>]]]
#          The far end of the loop's ssh: attaches here, on behalf of the loop
#          with that id. Exits 3 when this tmux has no sessions at all -- the
#          group's current session can name a machine whose server has since
#          been killed -- and the loop goes back to its own tmux instead, as
#          it does when the connection is lost.
#        Connect-Tmux.sh --handoff <identity> <session> [<pane>]
#          Run in the client's place by `tmux detach-client -E`: leaves the
#          handoff for the loop this client belongs to. A client that no loop
#          started (a plain `tmux attach`) becomes the loop instead.
#        Connect-Tmux.sh --take <id>
#          Prints and removes the handoff left here for the loop with that id.
#
# A machine is named by its identity, user@hostname, which is the same from
# everywhere. How to reach it may not be, so the address is looked up on the
# device doing the ssh:
#
#   ~/.config/tmux-link/aliases   <identity> TAB <address>, written by hand
#   ~/.config/tmux-link/peers     <identity> TAB <address>, kept by prefix+N
#
# and is the identity itself when neither has it.
#
# A terminal belongs to a group, a name: the terminals of a group share a
# current and a previous session across the linked machines, which prefix+l
# swaps, and follow each other from one to the next (Sync-LinkGroup.sh). The
# group is -g, else $TMUX_LINK_GROUP, else the first line of
#
#   ~/.config/tmux-link/group     on the device this loop runs on
#
# else `shared`. A device with a name of its own there keeps its own pair.
#
# Self-contained on purpose -- nothing sourced, nothing but bash, ssh and tmux
# -- since on the phone it is a single copied file.
set -uo pipefail

config="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-link"
handoffs="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-link/handoff"
# Where this script is on a machine with the dev-environment. $HOME is left
# for that machine's shell.
remote_self='"$HOME/.modules/tmux/scripts/Connect-Tmux.sh"'

# The same connection the radars ride (SSH_OPTS in ssh-helpers.sh, whose
# ControlPath this has to spell the same way): the hop authenticates once and
# the questions asked of that machine afterwards go through it.
ssh_opts=(-o ControlMaster=auto -o "ControlPath=$HOME/.ssh/tmux-%C" -o ControlPersist=10m
          -o ServerAliveInterval=10 -o ServerAliveCountMax=3)

# This machine's identity. TMUX_LINK_IDENTITY replaces it, for trying a link
# against localhost.
identity() {
  if [ -n "${TMUX_LINK_IDENTITY:-}" ]; then
    printf '%s\n' "$TMUX_LINK_IDENTITY"
  else
    printf '%s@%s\n' "$(id -un)" "$(hostname | cut -d. -f1 | tr '[:upper:]' '[:lower:]')"
  fi
}

# address <identity>
address() {
  local file found
  for file in "$config/aliases" "$config/peers"; do
    [ -f "$file" ] || continue
    found="$(awk -F '\t' -v id="$1" '$1 == id && $2 != "" { print $2; exit }' "$file")"
    [ -n "$found" ] && { printf '%s\n' "$found"; return; }
  done
  printf '%s\n' "$1"
}

sq() { printf "'%s'" "${1//\'/\'\\\'\'}"; }

# The group of a terminal that names none: this device's file, else `shared`.
default_group() {
  local name=""
  [ -f "$config/group" ] && IFS= read -r name <"$config/group"
  printf '%s\n' "${name:-shared}"
}

# group_current <group>
# Where the group's current session is, as two lines: the machine's identity
# and the session. Nothing when the group has none yet -- or on a device that
# is only a terminal, where Sync-LinkGroup.sh is not: the machine it attaches
# to answers instead (--remote).
group_current() {
  local sync="$HOME/.modules/tmux/scripts/Sync-LinkGroup.sh"
  [ -x "$sync" ] && "$sync" current "$1" 2>/dev/null
  return 0
}

# attach_here <id> <session> <pane> <group>
# The tmux client, as a child, carrying the loop's id: `detach-client -E` runs
# its command with the client's environment, which is how --handoff knows
# whose client it replaced. The group rides the same way, for
# Sync-LinkGroup.sh to read off the client. A pane given without a session
# says which session it is in itself: the Agents pane knows a linked agent by
# its pane alone.
attach_here() {
  local id=$1 session=$2 pane=$3 group=$4
  if [ -n "$pane" ]; then
    # Out of list-panes: display-message has no client to resolve a format
    # against out here, and prints an empty line for it.
    [ -n "$session" ] || session="$(tmux list-panes -a -F '#{pane_id} #{session_name}' 2>/dev/null |
      awk -v pane="$pane" '$1 == pane { sub(/^[^ ]* /, ""); print; exit }')"
    tmux select-window -t "$pane" 2>/dev/null
    tmux select-pane -t "$pane" 2>/dev/null
  fi
  if [ -n "$session" ] && tmux has-session -t "=$session" 2>/dev/null; then
    TMUX_LINK_CLIENT="$id" TMUX_LINK_GROUP="$group" tmux attach-session -t "=$session"
  else
    TMUX_LINK_CLIENT="$id" TMUX_LINK_GROUP="$group" tmux attach-session
  fi
}

take() {
  local file="$handoffs/$1"
  [ -f "$file" ] || return 0
  cat "$file"
  rm -f "$file"
}

case "${1:-}" in
  --remote)
    id="${2:?id}" session="${3:-}" pane="${4:-}" group="${5:-}"
    # A loop older than groups sends none: this machine's own.
    [ -n "$group" ] || group="$(default_group)"
    if [ -z "$session$pane" ]; then
      # Nowhere asked for: the group's current session. On another machine,
      # that is a handoff for the loop to take, as if picked here.
      where="$(group_current "$group")"
      if [ -n "$where" ]; then
        { IFS= read -r target; IFS= read -r session; } <<<"$where"
        if [ "$target" != "$(identity)" ]; then
          mkdir -p "$handoffs"
          printf '%s\n%s\n%s\n' "$target" "$session" "" >"$handoffs/$id"
          exit 0
        fi
      fi
    fi
    # Nothing to attach to: tmux would only say "no sessions". The loop tells
    # this apart from an ended session by the status.
    tmux has-session 2>/dev/null || exit 3
    attach_here "$id" "$session" "$pane" "$group"
    exit $?
    ;;
  --take)
    take "${2:?id}"
    exit 0
    ;;
  --handoff)
    target="${2:?identity}" session="${3:-}" pane="${4:-}"
    if [ -n "${TMUX_LINK_CLIENT:-}" ]; then
      mkdir -p "$handoffs"
      # A line each: the session is empty when only the pane is known, and
      # an empty field between tabs would not survive `read`.
      printf '%s\n%s\n%s\n' "$target" "$session" "$pane" >"$handoffs/$TMUX_LINK_CLIENT"
      exit 0
    fi
    # Nobody to hand off to: this client becomes the loop. TMUX would make the
    # tmux it attaches to later refuse as nested; the client it came from is
    # gone.
    unset TMUX TMUX_PANE
    exec "$0" -t "$target" ${pane:+-p "$pane"} "$session"
    ;;
esac

target="" pane="" group="${TMUX_LINK_GROUP:-}"
while getopts ":t:p:g:" option; do
  case "$option" in
    t) target="$OPTARG" ;;
    p) pane="$OPTARG" ;;
    g) group="$OPTARG" ;;
    *) printf 'Connect-Tmux.sh: unknown option -%s\n' "$OPTARG" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
session="${1:-}"
[ -n "$group" ] || group="$(default_group)"
group="$(printf '%s' "$group" | tr -c 'A-Za-z0-9_-' '_')"

me="$(identity)"
id="$(printf '%s-%s-%s' "$(hostname | cut -d. -f1)" "$$" "$RANDOM" | tr -c 'A-Za-z0-9_\n-' '_')"
mkdir -p -m 700 "$HOME/.ssh"

has_tmux() { command -v tmux >/dev/null 2>&1 && tmux has-session 2>/dev/null; }

# Only the first time round: after a handoff the place is named, and after a
# lost connection the group's session may be the one that cannot be reached.
resolve="yes"
while :; do
  next=""
  if [ -n "$resolve" ] && [ -z "$session$pane" ] && { [ -z "$target" ] || [ "$target" = "$me" ]; }; then
    # Nowhere asked for: the group's current session, which may be on a
    # linked machine. With -t that machine is asked instead (--remote).
    where="$(group_current "$group")"
    [ -z "$where" ] || { IFS= read -r target; IFS= read -r session; } <<<"$where"
  fi
  resolve=""
  if [ -z "$target" ] || [ "$target" = "$me" ]; then
    if ! has_tmux; then
      printf 'No tmux sessions here.\n' >&2
      exit 1
    fi
    attach_here "$id" "$session" "$pane" "$group"
    next="$(take "$id")"
  else
    host="$(address "$target")"
    # LogLevel=ERROR: without it every way out of that tmux ends in ssh's
    # "Shared connection to <host> closed.", which says nothing.
    ssh -t "${ssh_opts[@]}" -o LogLevel=ERROR "$host" \
      "$remote_self --remote $(sq "$id") $(sq "$session") $(sq "$pane") $(sq "$group")"
    status=$?
    # ControlMaster=no, ahead of the options it overrides: this rides the
    # hop's connection while ControlPersist keeps it, and when that is gone it
    # must not become the master itself -- a master keeps the pipe it was
    # started with, and this would wait on it for ten minutes.
    next="$(ssh -o ControlMaster=no "${ssh_opts[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$host" \
      "$remote_self --take $(sq "$id")" </dev/null 2>/dev/null)"
    if [ -z "$next" ] && { [ "$status" -eq 255 ] || [ "$status" -eq 3 ]; }; then
      if [ "$status" -eq 3 ]; then why="Nothing open on $host"; else why="Lost $host"; fi
      if has_tmux; then
        # The connection went, or there was nothing there (a group's current
        # session from before that server was killed), not the session: back
        # to this machine's tmux rather than to a bare prompt. Attaching
        # records the local session as the group's current.
        printf '\n%s; back to the local tmux.\n' "$why" >&2
        sleep 1
        target="" session="" pane=""
        # The local tmux's own ending is what this loop exits with now.
        unset status
        continue
      fi
      # ssh has said why for a lost connection; nothing has for this.
      [ "$status" -ne 3 ] || printf '%s.\n' "$why" >&2
    fi
  fi
  [ -n "$next" ] || exit "${status:-0}"
  { IFS= read -r target; IFS= read -r session; IFS= read -r pane; } <<<"$next"
  unset status
done
