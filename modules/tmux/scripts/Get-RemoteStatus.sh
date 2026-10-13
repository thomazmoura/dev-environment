#!/usr/bin/env bash
# The Workhorse and Paperboy status segments of another host, drawn in place of
# this machine's own while prefix+C-k (Select-StatusSource.sh) has pointed the
# status bar at that host: @status_source holds its @ssh_target, and the status
# formats (wsl2/tmux.conf, tmux/tmux.conf, common.conf) run this instead of
# Get-WorkhorseStatusCached.sh and Get-PaperboyUnread.sh.
#
# Usage: Get-RemoteStatus.sh <target> [max-title-length]
#        Get-RemoteStatus.sh -p <target>
#
#   󰒋 host  #123 | Work item title        after the window list
#   󰇮 4                                    -p: beside the agent count
#
# The host's name comes first, so the segments are never mistaken for local
# ones; it turns orange when the host could not be asked, and the last answer
# stays beside it. -p prints only the host's Paperboy count, from the answer
# the call without it cached, and never asks the host itself. The segments are the host's own Get-WorkhorseStatusCached.sh
# and Get-PaperboyUnread.sh, run there with its profile's environment
# (remote_profile_command in ssh-helpers.sh) -- so they share that host's
# caches -- and a segment the host is not configured for is not drawn.
#
# tmux runs this on every status refresh, so the host is asked at most every
# $STATUS_SOURCE_REFRESH_SECONDS (30) and the answer is cached here, as
# Get-WorkhorseStatusCached.sh does with its query; a lock keeps several
# clients from asking at once.
set -u

paperboy_only=""
if [ "${1:-}" = -p ]; then
  paperboy_only=1
  shift
fi

target="${1:-}"
max_title_length="${2:-80}"
refresh_seconds="${STATUS_SOURCE_REFRESH_SECONDS:-30}"
[ -n "$target" ] || exit 0
[[ "$max_title_length" =~ ^[1-9][0-9]*$ ]] || max_title_length=80
[[ "$refresh_seconds" =~ ^[1-9][0-9]*$ ]] || refresh_seconds=30

cache_dir="${XDG_RUNTIME_DIR:-/tmp}/tmux-status-source-$(id -u)"
name="${target//[\/:]/_}"
answer="$cache_dir/$name"          # the host's last answer
asked="$cache_dir/$name.asked"     # touched on every attempt, answered or not
offline="$cache_dir/$name.offline" # there while the last attempt failed
lock="$cache_dir/$name.lock"
mkdir -p "$cache_dir"

is_stale() {
  local modified
  [ -f "$asked" ] || return 0
  modified=$(stat -c %Y "$asked" 2>/dev/null) || return 0
  ((EPOCHSECONDS - modified >= refresh_seconds))
}

# As radar_remote.py asks the radars' hosts: through the master connection the
# session's panes hold open (the ControlPath of SSH_OPTS in ssh-helpers.sh),
# with ControlMaster=no rather than auto -- a call that became the master would
# leave a process holding its stdout, and this would wait on it for the ten
# minutes of ControlPersist. BatchMode, as nothing here can type a password.
# The host's answer is one marked line per segment, as its profile may print
# lines of its own.
ask() {
  local scripts command output
  scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
  source "$scripts/tmux-helpers.sh"
  command='$s = "$HOME/.modules/tmux/scripts"
if ($env:WORKHORSE_TMUX_QUERY_ID) { "@workhorse@" + ((& "$s/Get-WorkhorseStatusCached.sh" '"$max_title_length"') -join " ") }
if ($env:PAPERBOY_EWS_URL) { "@paperboy@" + ((& "$s/Get-PaperboyUnread.sh") -join "") }'
  if output="$("$REMOTE_SSH" -o ControlMaster=no -o "ControlPath=$HOME/.ssh/tmux-%C" \
    -o BatchMode=yes -o ConnectTimeout=5 \
    "$target" "sh -c $(sq "$(remote_profile_command "$command")")" </dev/null 2>/dev/null)"; then
    printf '%s\n' "$output" | grep '^@[a-z]*@' >"$answer.tmp.$$"
    mv -f "$answer.tmp.$$" "$answer"
    rm -f "$offline"
  else
    : >"$offline"
  fi
}

if [ -n "$paperboy_only" ]; then
  [ -f "$cache_dir/$name" ] || exit 0
  while IFS= read -r line; do
    case "$line" in
      @paperboy@*) printf '%s' "${line#@paperboy@}" ;;
    esac
  done <"$cache_dir/$name"
  exit 0
fi

if is_stale; then
  exec 9>"$lock"
  if flock -n 9 && is_stale; then
    touch "$asked"
    ask
  fi
  exec 9>&-
fi

host="${target#docker:}"
host="${host#*@}"
host="${host%%.*}"
if [ -e "$offline" ]; then
  printf '#[fg=#fab387]󰒋 %s#[fg=default] ' "$host"
else
  printf '#[fg=#9370db]󰒋 %s#[fg=default] ' "$host"
fi

[ -f "$answer" ] || exit 0
while IFS= read -r line; do
  case "$line" in
    @workhorse@*) printf '#[fg=#7aa2f7]%s#[fg=default] ' "${line#@workhorse@}" ;;
  esac
done <"$answer"
