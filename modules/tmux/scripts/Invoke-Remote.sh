#!/usr/bin/env bash
# ssh, or the same thing into a local Docker container. Every ssh the remote
# sessions make goes through here (REMOTE_SSH in ssh-helpers.sh), so a session
# opened on a container (prefix+D, New-SshSession.sh -D) is an ssh session in
# every other respect: its panes, feeds, worktrees and popups need no idea of
# which of the two they are talking to.
#
# Usage: Invoke-Remote.sh [-o option]... [-O command] [-q] [-t | -T] <target> [command...]
#   Called exactly as ssh is. A <target> of the form docker:<container> runs
#   `docker exec` into that container instead; anything else is handed to ssh
#   untouched.
#
# For a container:
#   -o     ignored: control masters, BatchMode and timeouts are about a network
#          there is none of here
#   -O     fails: there is no master connection to control
#   -q     ignored: docker exec prints nothing of its own to quieten
#   -t     a terminal -- only when there is one to hand over, since docker exec,
#          unlike ssh, refuses outright when stdin is not a terminal. TERM and
#          COLORTERM go with it, which ssh forwards and docker exec does not
#
# The command is the remaining arguments joined with spaces, as ssh joins them,
# and read by sh as the remote's shell would read it. docker exec sets no
# $SHELL, which the remote commands start their login shell with (remote_run
# in ssh-helpers.sh), so it is taken from the container's passwd entry first.
# No command gives a login shell, as ssh does.
#
# A container that is not running -- or not there -- exits 255, as ssh does
# when it cannot reach a host: the callers read 255 as "could not ask" (an
# OFFLINE radar row, a guard that stands aside), where docker exec's own 1
# would read as the command's answer.
set -uo pipefail

# The target is the first argument that is not an option: the options are
# walked past first, and only then is it known which of the two this is.
original=("$@")
tty=""
no_master=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-O) [ "$1" = -O ] && no_master="yes"; shift 2 ;;
    -o*) shift ;;
    -O*) no_master="yes"; shift ;;
    -*)
      [[ $1 == *t* ]] && tty="yes"
      shift ;;
    *) break ;;
  esac
done
target="${1:-}"
[[ $target == docker:* ]] || exec ssh "${original[@]}"
[ -z "$no_master" ] || exit 1
shift
command="$*"

container="${target#docker:}"
[ "$(docker container inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" = true ] || {
  printf 'Container %s is not running\n' "$container" >&2
  exit 255
}

exec_args=(-i)
if [ -n "$tty" ] && [ -t 0 ]; then
  exec_args+=(-t -e "TERM=${TERM:-xterm-256color}" -e "COLORTERM=${COLORTERM:-}")
fi

[ -n "$command" ] || command='exec "$SHELL" -l'

exec docker exec "${exec_args[@]}" "$container" sh -c \
  'SHELL="${SHELL:-$(getent passwd "$(id -un)" | cut -d: -f7)}"; export SHELL="${SHELL:-/bin/sh}"; eval "$1"' \
  sh "$command"
