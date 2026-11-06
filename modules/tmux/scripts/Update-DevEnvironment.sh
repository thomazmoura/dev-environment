#!/usr/bin/env bash
# Pulls this dev-environment clone and reloads the tmux config, or with
# --no-pull only reloads it.
#
# Bound to prefix+U (pull and reload) and prefix+u (--no-pull) as a small popup
# in modules/tmux/common.conf. Closes by itself when everything worked; a
# failed pull (dirty tree, diverged branch, no network) holds the popup open on
# git's message instead.
#
# The clone is found from this script's own real path rather than from a fixed
# ~/code/dev-environment: ~/.modules is a symlink into the clone on the host and
# in WSL (LinuxDevEnv/host-setup.sh, modules/wsl2/Start-DevSession.ps1), so
# resolving it lands inside the repository wherever it was cloned. The Docker
# image copies modules/ in instead, so there is no clone to pull there (but
# --no-pull still reloads).
#
# The reload sources the user's tmux config (~/.tmux.conf, or the XDG one when
# there is one), which sources this repo's, and ends with a status-line message.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

pull=1
[ "${1:-}" = --no-pull ] && pull=""

require_tools tmux
[ -z "$pull" ] || require_tools git

conf="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
[ -f "$conf" ] || conf="$HOME/.tmux.conf"
[ -f "$conf" ] || die "No tmux config found at $conf"

if [ -n "$pull" ]; then
  repo="$(git -C "$scripts" rev-parse --show-toplevel 2>/dev/null)" \
    || die "~/.modules is not a git clone here (the Docker image copies it in) -- nothing to pull."

  printf 'Pulling %s\n\n' "$repo"
  git -C "$repo" pull --ff-only || die "
git pull failed -- nothing was reloaded."
  printf '\n'
fi

printf 'Reloading tmux config\n'
tmux source-file "$conf" || die "Reloading the tmux config failed."

if [ -n "$pull" ]; then
  tmux display-message "dev-environment updated to $(git -C "$repo" log -1 --format='%h %s') and tmux config reloaded"
else
  tmux display-message "tmux config reloaded"
fi
