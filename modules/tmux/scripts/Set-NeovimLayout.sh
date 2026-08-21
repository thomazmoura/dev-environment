#!/usr/bin/env bash
# Applies the standard layout to a tmux target: NeoVim on top, terminal below (20%),
# focus left on NeoVim.
#
# Usage: Set-NeovimLayout.sh [target]
#   target - any tmux target (pane id like %12, or "session:"). Defaults to current pane.
set -euo pipefail

target="${1:-}"
if [ -z "$target" ]; then
  target="$(tmux display-message -p '#{pane_id}')"
fi

# Resolve to concrete pane ids so we never depend on pane indexes / pane-base-index.
top="$(tmux display-message -p -t "$target" '#{pane_id}')"
bottom="$(tmux split-window -t "$top" -v -l 20% -c '#{pane_current_path}' -P -F '#{pane_id}')"

tmux select-pane -t "$bottom" -T "Terminal"
tmux set -p -t "$bottom" @pane_label "Terminal"
tmux send-keys -t "$bottom" 'pwsh -NoExit -Command "psgit && psfzf && Build-DotnetProjectIfNeeded" && exit' C-m

tmux select-pane -t "$top" -T "NeoVim"
tmux set -p -t "$top" @pane_label "NeoVim"
tmux send-keys -t "$top" "pwsh -NoExit -Command \"$HOME/.modules/neovim-lsp/Install-LanguageServerNodePackages.ps1 && nvim\" && exit" C-m

tmux select-pane -t "$top"
