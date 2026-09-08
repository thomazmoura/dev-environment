#!/usr/bin/env bash
# Applies the standard project layout to a tmux target: a narrow radar column
# on the left (the git feed above, the agent feed below) and, filling the rest
# of the window, NeoVim with a terminal running the project's setup command
# below it.
#
# Usage: Set-NeovimLayout.sh [-s] [target]
#   -s       terminals in a 20% column on the right, split in two and without
#            the radar column (prefix+V), instead of the default layout
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

# The two live feeds, the same ones prefix+t, r and prefix+t, R open. No
# no-exit on either: closing a feed should close its pane, not leave a shell
# sitting in a sliver of the radar column.
agent_feed="& $HOME/.modules/agent-radar/scripts/Watch-AgentFeed.py"
git_feed="& $HOME/.modules/git-radar/scripts/Watch-GitFeed.py"

if [ -n "$side" ]; then
  # A 20% column on the right, halved: a bare terminal on top and the setup
  # terminal below it.
  column="$(new_pane "$top" "Terminal" "$(pwsh_command '')" -h -l 20%)"
  new_pane "$column" "Terminal" "$terminal" -v -l 50% >/dev/null
else
  # A 12% radar column down the left edge -- git feed on top, agent feed under
  # it -- and NeoVim over a 16% terminal row in what is left. The feeds are
  # part of the default layout rather than something prefix+t, r/R has to open
  # every time: they are the panes whose whole job is to be read without being
  # asked for, so they get a column of their own that NeoVim never covers.
  #
  # `-b` puts the split *before* the pane being split, which is what makes the
  # column land on the left of NeoVim instead of the right. The percentages are
  # each relative to the pane being split, so 12% of the window goes to the
  # column, 40% of that column to the agent feed, and 16% of the remaining 88%
  # to the terminal.
  radar="$(new_pane "$top" "Git" "$(pwsh_command "$git_feed")" -h -b -l 12%)"
  new_pane "$radar" "Agents" "$(pwsh_command "$agent_feed")" -v -l 40% >/dev/null
  new_pane "$top" "Terminal" "$terminal" -v -l 16% >/dev/null

  # C-h from NeoVim is `select-pane -L`, which breaks the tie between the two
  # panes of the radar column by most-recently-active. Touching the git feed
  # after the splits makes that C-h land on Git instead of on the agent feed.
  tmux select-pane -t "$radar"
fi

label_pane "$top" "NeoVim"
tmux send-keys -t "$top" \
  "$(pwsh_command "$HOME/.modules/neovim-lsp/Install-LanguageServerNodePackages.ps1 && nvim" no-exit)" C-m

tmux select-pane -t "$top"
