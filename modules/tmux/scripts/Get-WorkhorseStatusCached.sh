#!/usr/bin/env bash

# Rate-limit the PowerShell status command independently of tmux's status
# refresh interval. A lock prevents multiple tmux clients refreshing it at once.

set -u

max_title_length="${1:-80}"
refresh_seconds="${WORKHORSE_TMUX_REFRESH_SECONDS:-60}"

if [[ ! "$max_title_length" =~ ^[1-9][0-9]*$ ]]; then
    max_title_length=80
fi

if [[ ! "$refresh_seconds" =~ ^[1-9][0-9]*$ ]]; then
    refresh_seconds=60
fi

if [[ -z "${WORKHORSE_TMUX_QUERY_ID:-}" ]]; then
    exit 0
fi

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/workhorse"
display_cache="$cache_dir/tmux-status.txt"
lock_file="$cache_dir/tmux-status.lock"

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
        if pwsh -NoProfile \
            -File "$HOME/.modules/tmux/scripts/Get-WorkhorseStatus.ps1" \
            -MaxTitleLength "$max_title_length" >"$temp_file" 2>/dev/null; then
            mv -f "$temp_file" "$display_cache"
        else
            rm -f "$temp_file"
        fi
    fi
fi

if [[ -f "$display_cache" ]]; then
    cat "$display_cache"
fi
