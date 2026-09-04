#!/usr/bin/env bash
# Fuzzy-find another session and switch the client to it.
#
# Bound to prefix+/ and prefix+C-p as a popup command in
# modules/tmux/common.conf. The current session is left out of the list: it is
# never a useful answer, and dropping it means the first row is already the
# session you most likely want.
set -uo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

require_tools tmux fzf

current="$(tmux display-message -p '#{session_name}')"

# -F asks for the bare name, which is why this needs none of the `sed -E
# 's/:.*$//'` trimming the old inline binding did to `list-sessions` output.
sessions="$(tmux list-sessions -F '#{session_name}' | grep -vxF "$current" || true)"
[ -n "$sessions" ] || die "No other sessions to switch to"

selection="$(printf '%s\n' "$sessions" | fzf --reverse --prompt='session> ' --header='Switch to session')" || exit 0
[ -n "$selection" ] || exit 0

tmux switch-client -t "$selection"
