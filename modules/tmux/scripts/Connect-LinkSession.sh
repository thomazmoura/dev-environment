#!/usr/bin/env bash
# Connects to a linked machine again, and only then takes the client to one of
# its sessions. Run in a popup by prefix+h (Switch-HomeSession.sh) and by Enter
# on the Git pane's home row, when the home session is on a linked machine that
# the radars have stopped hearing from (the row then reads "unreachable").
#
# Usage: Connect-LinkSession.sh [-c <client>] <host>:<session>
#   -c   the client to move; the one this runs under when left out
#
# It connects as prefix+N does (New-SshSession.sh): without a terminal first,
# cancellable with Esc or Ctrl+C (run_cancellable), and with the popup's
# terminal only when the batch try was turned away for a password or a host
# key. A try that times out drops the master it went through, which may be one
# whose network went away, and tries once more anew. The connection it makes
# is the master every later ssh to that machine rides (SSH_OPTS), the radars'
# and tmux_link's included, so their next tick hears from it again; they are
# asked to sample now rather than at the end of it.
#
# The question asked over that connection is whether the session is still
# there (a plain tmux has-session, as Sync-LinkGroup.sh asks it). Only when it
# is does the client move (Switch-LinkSession.sh); otherwise the popup says why
# and waits for a key, and the client stays where it was.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

client=""
if [ "${1:-}" = "-c" ]; then
  client="${2:-}"
  shift 2
fi
key="${1:?usage: Connect-LinkSession.sh [-c <client>] <host>:<session>}"
[[ $key == *:* ]] || die "$key is not a session on a linked machine"
host="${key%%:*}"
session="${key#*:}"

peers="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-link/peers"
IFS=$'\t' read -r identity address < <(
  awk -F '\t' -v host="$host" '{ h = $1; sub(/^.*@/, "", h) } h == host { print $1 "\t" $2; exit }' "$peers" 2>/dev/null)
[ -n "${identity:-}" ] && [ -n "${address:-}" ] || die "No linked machine called $host"

files="$(mktemp -d)" || die "Could not create a temporary directory"
trap 'rm -rf "$files"' EXIT
out="$files/out" err="$files/err"

check="tmux has-session -t $(sq "=$session")"
timeout=20
needs_you='permission denied|host key verification failed|authentication'

# ask: the question, over the master or a new connection, without a terminal.
ask() {
  run_cancellable "$timeout" "$out" "$err" env LC_ALL=C \
    "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=10 "$address" "$check"
}

printf 'Connecting to %s... (Esc or Ctrl+C to cancel)\n' "$host"
ask
status=$?
if [ "$status" -eq 124 ]; then
  run_cancellable 5 /dev/null /dev/null "$REMOTE_SSH" "${SSH_OPTS[@]}" -O exit "$address"
  ask
  status=$?
fi
if [ "$status" -eq 255 ] && grep -qiE "$needs_you" "$err"; then
  SSH_ASKPASS_REQUIRE=never "$REMOTE_SSH" "${SSH_OPTS[@]}" -o ConnectTimeout=10 "$address" true ||
    die "Could not connect to $host"
  ask
  status=$?
fi

case $status in
  0) ;;
  130) exit 0 ;;
  124) die "No answer from $host in ${timeout}s" ;;
  255)
    why="$(grep -v '^$' "$err" | tail -n 1)"
    die "Could not connect to $host${why:+: $why}" ;;
  *) die "$session is no longer open on $host" ;;
esac

"$scripts/Request-RadarSample.sh"
"$scripts/Start-TmuxLink.py" --ensure >/dev/null 2>&1
"$scripts/Switch-LinkSession.sh" ${client:+-c "$client"} "$key"
