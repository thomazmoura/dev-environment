#!/usr/bin/env bash
# A one-glance agent summary for the tmux status bar, e.g.
#
#   ●2●1        two agents waiting on you, one working
#
# Idle agents are left out on purpose: a dot that is always lit teaches you to
# stop reading the segment.
#
# Wired into status-right from modules/tmux/tmux.conf and modules/wsl2/tmux.conf.
# It must be prepended AFTER TPM runs, because tmux-power assigns status-right
# wholesale when it loads and would drop anything the config set earlier -- the
# same ordering trap that any other status-right consumer has to work around.
#
# This no longer detects anything. Start-AgentRadar.py samples once a second for
# the whole machine and publishes the rendered string; this reads it. That is
# what makes several open feed panes free -- see modules/agent-radar/scripts/
# agent_feed.py for why every consumer sampling for itself was both expensive
# and, through the shared debounce file, wrong.
#
# The hot path stays a `cat` rather than a Python call: tmux refreshes the status
# bar on far more than the status-interval timer, and an interpreter start per
# refresh would cost more than the sampling does.
#
# Usage: Get-AgentSummary.sh [stale-seconds]   (default 5)

set -u

stale_seconds="${1:-5}"
[[ "$stale_seconds" =~ ^[1-9][0-9]*$ ]] || stale_seconds=5

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/agent-radar"
display_cache="$cache_dir/status.txt"
heartbeat="$cache_dir/heartbeat"
lock_file="$cache_dir/status.lock"

mkdir -p "$cache_dir"
# The sampler exits once nothing has read from it for a while, so an attached
# client saying "still here" is what keeps it alive.
touch "$heartbeat" 2>/dev/null

cache_is_stale() {
    [[ ! -f "$display_cache" ]] && return 0
    local now modified
    now=$(date +%s)
    modified=$(stat -c %Y "$display_cache" 2>/dev/null) || return 0
    ((now - modified >= stale_seconds))
}

if cache_is_stale; then
    # No sampler, or one that has fallen behind. Restart it and take one sample
    # here so the segment is right immediately rather than a tick from now.
    #
    # Behind a non-blocking lock: every attached client hits this path at the
    # same moment, and the fallback is the one expensive branch left in the
    # status-bar path. Whoever loses simply prints the last published value.
    exec 9>"$lock_file"
    if flock -n 9 && cache_is_stale; then
        temp_file="$display_cache.tmp.$$"
        if "$here/Get-AgentState.py" --format=status --cached >"$temp_file" 2>/dev/null; then
            mv -f "$temp_file" "$display_cache"
        else
            rm -f "$temp_file"
        fi
    fi
fi

[[ -f "$display_cache" ]] && cat "$display_cache"
exit 0
