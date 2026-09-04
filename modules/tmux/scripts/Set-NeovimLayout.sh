#!/usr/bin/env bash
# Applies the standard project layout to a tmux target: NeoVim in the main pane
# and a terminal running the project's setup command next to it.
#
# Usage: Set-NeovimLayout.sh [-s] [target]
#   -s       terminals in a 20% column on the right, split in two (prefix+V)
#            instead of a single 20% row below (prefix+v)
#   target   any tmux target (pane id like %12, or "session:"). Defaults to the
#            current pane.
#
# Used by the prefix+v / prefix+V bindings and by New-CodeSession.sh, which
# builds a session and then hands it here so a new project always opens the
# same way.
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

# This runs from `run-shell -b`, which has no popup to write a failure to.
die() { warn "$@"; }

side=""
while getopts ":s" option; do
  case "$option" in
    s) side="yes" ;;
    *) die "Set-NeovimLayout.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

# Resolve to a concrete pane id so we never depend on pane indexes / pane-base-index.
top="$(current_pane "${1:-}")"

# The setup command is the same either way: refresh git state, load the fzf
# helpers and build the project if it needs it, then leave the shell open.
terminal="$(pwsh_command 'psgit && psfzf && Build-DotnetProjectIfNeeded' no-exit)"

if [ -n "$side" ]; then
  # A 20% column on the right, halved: a bare terminal on top and the setup
  # terminal below it.
  column="$(new_pane "$top" "Terminal" "$(pwsh_command '')" -h -l 20%)"
  new_pane "$column" "Terminal" "$terminal" -v -l 50% >/dev/null
else
  new_pane "$top" "Terminal" "$terminal" -v -l 20% >/dev/null
fi

label_pane "$top" "NeoVim"
tmux send-keys -t "$top" \
  "$(pwsh_command "$HOME/.modules/neovim-lsp/Install-LanguageServerNodePackages.ps1 && nvim" no-exit)" C-m

tmux select-pane -t "$top"
