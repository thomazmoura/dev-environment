#!/usr/bin/env bash
# The same agent list as Select-Agent.sh, but in a normal pane that keeps itself
# up to date -- leave it open in a corner and watch agents go from working to
# waiting. Enter still jumps to the selected pane.
#
# Bound to prefix+t then A (see modules/tmux/common.conf), which opens it through
# New-ToolPane.sh so the pane is labelled like every other one.
#
# Live AND selectable out of one code path, rather than a read-only redraw loop
# plus a separate picker: `fzf --listen` makes the running fzf accept actions
# over HTTP, so a background loop pushes a `reload` into it on a timer while the
# list stays fully interactive. Verified against fzf 0.54.3.
#
# The port is chosen here rather than with fzf's `--listen 0`, which picks a free
# port itself but publishes it only as $FZF_PORT to fzf's own child processes --
# so the background refresher, which is not one of those, would have to get it
# back out through a temp file and a `start` binding. Binding a socket to port 0
# and reading back what the kernel assigned is the same trick with none of that
# choreography. The gap between closing the probe socket and fzf binding it is a
# race in theory; in practice the port is still free a few milliseconds later,
# and losing it costs a refusal to start, not a wrong answer.
#
# Usage: Watch-Agents.sh [refresh-seconds]   (default 1)
set -uo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../tmux/scripts/tmux-helpers.sh"

require_tools tmux fzf

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
detector="$here/Get-AgentState.py"
interval="${1:-1}"

# --cached: read the snapshot Start-AgentRadar.py publishes rather than sampling
# here. That is what lets this refresh once a second and be left open in every
# session at the same time -- the detector runs once per second for the whole
# machine no matter how many of these are up. It also carries the working->idle
# smoothing, which a poller needs and which is only correct with one sampler.
list_command="$detector --format=fzf --cached"

jump() {
  local pane=${1:-}
  [ -n "$pane" ] || return 0
  # All three: switch-client alone lands on the session's current window, which
  # is not necessarily the one holding the pane.
  tmux switch-client -t "$pane"
  tmux select-window -t "$pane"
  tmux select-pane -t "$pane"
}

# Without curl there is no push channel. The list still works and ctrl-r becomes
# the only way to refresh it -- degrade, rather than refuse to start.
if ! command -v curl >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  selection="$($list_command | fzf --ansi --reverse --delimiter=$'\t' --with-nth=2.. \
      --prompt='agent> ' --header='Agents   (ctrl-r to refresh)' \
      --bind="ctrl-r:reload($list_command)")" || exit 0
  jump "${selection%%$'\t'*}"
  exit 0
fi

port="$(python3 -c "
import socket
probe = socket.socket()
probe.bind(('127.0.0.1', 0))
print(probe.getsockname()[1])
probe.close()
")"

refresher_pid=""
cleanup() { [ -n "$refresher_pid" ] && kill "$refresher_pid" 2>/dev/null; }
trap cleanup EXIT HUP INT TERM

(
  # A failed POST means fzf has exited, which is this loop's own exit condition,
  # so closing the pane cannot leave a poller running against a dead port.
  while sleep "$interval"; do
    curl -s -XPOST "localhost:$port" -d "reload($list_command)" >/dev/null 2>&1 || exit 0
  done
) &
refresher_pid=$!

selection="$(
  $list_command | fzf --ansi --reverse --delimiter=$'\t' --with-nth=2.. \
    --prompt='agent> ' \
    --header="Agents   (refreshing every ${interval}s; ctrl-r now)" \
    --listen "$port" \
    --bind="ctrl-r:reload($list_command)"
)" || exit 0

jump "${selection%%$'\t'*}"
