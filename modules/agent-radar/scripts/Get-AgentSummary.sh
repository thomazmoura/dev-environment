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
# same ordering trap that makes modules/demux/Initialize-Demux.sh necessary.
#
# Usage: Get-AgentSummary.sh [refresh-seconds]   (default 3)

# Rate-limit the detector independently of tmux's status refresh, which fires on
# far more than the status-interval timer. Same structure as
# modules/tmux/scripts/Get-WorkhorseStatusCached.sh: an mtime staleness check,
# a non-blocking lock so several attached clients do not all refresh at once,
# and a temp-file-then-mv so a reader never sees a half-written cache.
#
# The interval is seconds rather than that script's minute, because the whole
# value here is noticing a blocked agent promptly.
set -u

refresh_seconds="${1:-3}"
[[ "$refresh_seconds" =~ ^[1-9][0-9]*$ ]] || refresh_seconds=3

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/agent-radar"
display_cache="$cache_dir/status.txt"
lock_file="$cache_dir/status.lock"

mkdir -p "$cache_dir"

cache_is_stale() {
    [[ ! -f "$display_cache" ]] && return 0
    local now modified
    now=$(date +%s)
    modified=$(stat -c %Y "$display_cache" 2>/dev/null) || return 0
    ((now - modified >= refresh_seconds))
}

if cache_is_stale; then
    exec 9>"$lock_file"
    if flock -n 9 && cache_is_stale; then
        temp_file="$display_cache.tmp.$$"
        # --debounce: this polls, so it would otherwise show the idle frame an
        # agent blinks through between tool calls.
        if "$here/Get-AgentState.py" --format=status --debounce >"$temp_file" 2>/dev/null; then
            mv -f "$temp_file" "$display_cache"
        else
            rm -f "$temp_file"
        fi
    fi
fi

[[ -f "$display_cache" ]] && cat "$display_cache"
exit 0
