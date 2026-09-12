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
# Used by the prefix+v / prefix+V bindings and by New-CodeSession.sh and
# New-SshSession.sh, which build a session and then hand it here so a new
# project always opens the same way -- on the remote, for an ssh session.
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

# Every pane goes through pane_command, so in an ssh session (prefix+N) the
# whole layout runs on the remote, in the session's working directory. Paths
# are spelled with ~ rather than $HOME for the same reason: $HOME would be
# expanded here, to this machine's home, while pwsh expands ~ wherever it runs.
#
# A remote without this dev-environment has no pwsh profile and no ~/.modules,
# so it gets what can still work there: plain NeoVim, a login shell for the
# terminal and no radar column.
setup='psgit && psfzf && Build-DotnetProjectIfNeeded'
editor='~/.modules/neovim-lsp/Install-LanguageServerNodePackages.ps1 && nvim'
radars="yes"
remote="$(ssh_option "$top" @ssh_target)"
if [ -n "$remote" ] && ! ssh_is_devenv "$top"; then
  setup=""
  editor="nvim"
  radars=""
fi

# The setup command is the same either way: refresh git state, load the fzf
# helpers and build the project if it needs it, then leave the shell open.
terminal="$(pane_command "$top" "$setup" no-exit)"

# The two live feeds, the same ones prefix+t, r and prefix+t, R open. No
# no-exit on either: closing a feed should close its pane, not leave a shell
# sitting in a sliver of the radar column.
agent_feed='& ~/.modules/agent-radar/scripts/Watch-AgentFeed.py'
git_feed='& ~/.modules/git-radar/scripts/Watch-GitFeed.py'

if [ -n "$side" ]; then
  # A 20% column on the right, halved: a bare terminal on top and the setup
  # terminal below it.
  column="$(new_pane "$top" "Terminal" "$(pane_command "$top" '')" -h -l 20%)"
  new_pane "$column" "Terminal" "$terminal" -v -l 50% >/dev/null
elif [ -z "$radars" ]; then
  new_pane "$top" "Terminal" "$terminal" -v -l 16% >/dev/null
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
  radar="$(new_pane "$top" "Git" "$(pane_command "$top" "$git_feed")" -h -b -l 12%)"
  new_pane "$radar" "Agents" "$(pane_command "$top" "$agent_feed")" -v -l 40% >/dev/null
  new_pane "$top" "Terminal" "$terminal" -v -l 16% >/dev/null

  # C-h from NeoVim is `select-pane -L`, which breaks the tie between the two
  # panes of the radar column by most-recently-active. Touching the git feed
  # after the splits makes that C-h land on Git instead of on the agent feed.
  tmux select-pane -t "$radar"
fi

# NeoVim is typed into the pane the layout was applied to rather than opened in
# a new one. In an ssh session that pane is either still a local shell -- the
# first pane of a session New-SshSession.sh has just created -- which has to
# ssh there first, or already a shell on the remote (prefix+v from a remote
# pane), where another ssh would only nest a second connection inside the first.
if [ -n "$remote" ] && [ "$(tmux display-message -p -t "$top" '#{pane_current_command}')" = ssh ]; then
  editor_line="$(remote_typed_command "$top" "$editor" no-exit)"
else
  editor_line="$(pane_command "$top" "$editor" no-exit)"
fi

label_pane "$top" "NeoVim"
tmux send-keys -t "$top" "$editor_line" C-m

tmux select-pane -t "$top"
