#!/usr/bin/env bash
# Fuzzy-find another session and switch the client to it, with where each
# session's repository stands beside its name.
#
#   ● session  ●agents  branch  state  ⇡ahead ⇣behind +added ~modified -deleted ?untracked
#
# Bound to prefix+/ and prefix+C-p as a popup command in
# modules/tmux/common.conf. The current session is left out of the list: it is
# never a useful answer, and dropping it means the first row is already the
# session you most likely want.
#
# The rows are git-radar's (Get-GitState.py --format=fzf), the same way
# Select-Agent.sh shows agent-radar's: the session name rides along hidden in
# column one, so nothing has to parse it back out of the display string. The
# current session is dropped after rendering rather than before, so the
# columns are padded exactly as they are in the git feed. Rows are sorted by
# what is left to do in them: uncommitted changes first, then commits to push,
# then commits to pull, then clean and in sync -- unlike the feed, which keeps
# session order. --agents adds agent-radar's status-bar summary for each
# session after its name (●1●2, idle agents left out), so a session with an
# agent waiting or working shows it before you switch. Without git-radar the
# list falls back to bare session names.
#
# Usage: Select-Session.sh [--list]
#   --list  print the rows and exit; what ctrl-r reloads from
set -uo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

require_tools tmux fzf

git_state="$HOME/.modules/git-radar/scripts/Get-GitState.py"

list_rows() {
  local current rows=""
  current="$(tmux display-message -p '#{session_name}')"

  # --cached: read the snapshot Start-GitRadar.py publishes rather than running
  # a git status per session here, so the popup opens without a pause.
  if [ -x "$git_state" ]; then
    rows="$("$git_state" --format=fzf --sort=changes --agents --cached 2>/dev/null)"
  fi
  if [ -z "$rows" ]; then
    rows="$(tmux list-sessions -F $'#{session_name}\t#{session_name}')"
  fi

  printf '%s\n' "$rows" | awk -F'\t' -v current="$current" 'NF && $1 != current'
}

if [ "${1:-}" = "--list" ]; then
  list_rows
  exit 0
fi

rows="$(list_rows)"
[ -n "$rows" ] || die "No other sessions to switch to"

self="$(readlink -f "${BASH_SOURCE[0]}")"
selection="$(
  printf '%s\n' "$rows" \
    | fzf --ansi --reverse --delimiter=$'\t' --with-nth=2.. \
          --prompt='session> ' \
          --header=$'Switch to session   (ctrl-r refresh)' \
          --bind="ctrl-r:reload('$self' --list)"
)" || exit 0
[ -n "$selection" ] || exit 0

tmux switch-client -t "${selection%%$'\t'*}"
