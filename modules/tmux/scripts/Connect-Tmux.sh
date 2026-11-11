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
# Run it on the device you type on, never in an ssh login on one of the
# machines: the loop is what makes the ssh, so started over there it makes
# every other machine a second hop away. It warns when it is about to.
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
#        Connect-Tmux.sh --spotlight <id>
#          The far end of the loop's second ssh, for SpotlightDimmer: prints
#          the focused pane's geometry of that loop's client here, a line per
#          change, for the daemon beside the terminal. See below.
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
# SpotlightDimmer lights the focused pane from reports made by tmux's hooks,
# which on a linked machine run over there. So beside the ssh that shows that
# tmux, the loop runs a second one on the same connection, bringing the
# reports back: SpotlightDimmer's own relay script at both ends (send there,
# receive here), told by --spotlight which client over there is this loop's.
# Only where both machines have that script; without it the whole window is
# lit, as before.
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

# SpotlightDimmer's relay script, where it is installed: from source in the
# home, from a package under /usr/share. Nothing where it is not.
spotlight_relay() {
  local file
  for file in "$HOME/.config/SpotlightDimmer/tools" /usr/share/spotlight-dimmer/tools; do
    file="$file/spotlight-dimmer-tmux-relay.sh"
    [ -x "$file" ] && { printf '%s\n' "$file"; return; }
  done
  return 0
}

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
  --spotlight)
    id="${2:?id}"
    relay="$(spotlight_relay)"
    [ -n "$relay" ] || exit 0
    # The loop's client is the one attach_here started with its id. It may not
    # be there yet, this ssh racing the one that attaches -- and never is when
    # --remote answered with a handoff instead.
    for ((try = 0; try < 50; try++)); do
      while IFS=$'\t' read -r pid tty; do
        [ -r "/proc/$pid/environ" ] || continue
        if tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -qxF "TMUX_LINK_CLIENT=$id"; then
          # Ends by itself when that client is gone.
          exec "$relay" send "$tty"
        fi
      done < <(tmux list-clients -F $'#{client_pid}\t#{client_tty}' 2>/dev/null)
      sleep 0.2
    done
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
    # This loop should run on the device being typed on. One started in an ssh
    # login (`ssh -t <host> "pwsh -C vtmux"`) makes every machine it moves on to
    # a second hop away: the phone's clipboard sockets and the device's own
    # ssh config stay a hop behind. It still goes, but says so first -- long
    # enough to read before that tmux takes the screen.
    if [ -n "${SSH_CONNECTION:-}" ]; then
      printf '%s is a second ssh hop away, through %s: run tmux-link (or vtmux) on the device you type on instead.\n' \
        "${target##*@}" "$(hostname | cut -d. -f1)" >&2
      sleep 2
    fi
    # SpotlightDimmer's reports from over there, into the daemon here. On the
    # hop's connection once it is up, so it never asks for a password of its
    # own. exec, so that the pid to end it by is the ssh: the receiving end
    # then clears the pane it was told about.
    relay_pid=""
    relay="$(spotlight_relay)"
    if [ -n "$relay" ]; then
      (
        for ((try = 0; try < 150; try++)); do
          ssh "${ssh_opts[@]}" -O check "$host" 2>/dev/null && break
          sleep 0.2
        done
        exec ssh -o ControlMaster=no "${ssh_opts[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$host" \
          "$remote_self --spotlight $(sq "$id")" 2>/dev/null > >("$relay" receive)
      ) </dev/null >/dev/null 2>&1 &
      relay_pid=$!
    fi
    # LogLevel=ERROR: without it every way out of that tmux ends in ssh's
    # "Shared connection to <host> closed.", which says nothing.
    ssh -t "${ssh_opts[@]}" -o LogLevel=ERROR "$host" \
      "$remote_self --remote $(sq "$id") $(sq "$session") $(sq "$pane") $(sq "$group")"
    status=$?
    [ -z "$relay_pid" ] || kill "$relay_pid" 2>/dev/null
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
