#!/usr/bin/env bash
# Applies the standard project layout to a tmux target: a narrow radar column
# on the left (the git feed above, the agent feed below) and, filling the rest
# of the window, NeoVim with a terminal running the project's setup command
# below it.
#
# Safe to run again on a window that already has the layout: it only creates
# the fixed panes (Git, Agents, Terminal) that are missing and puts their sizes
# back, so prefix+v also repairs a layout broken by a closed pane or a stray
# resize. NeoVim's size is never enforced, and neither is its presence as long
# as something else holds its place (agent panes, say); it is only recreated
# when nothing does -- the terminal reaching the top of the window, or the
# radar column being all that is left.
#
# Usage: Set-NeovimLayout.sh [-s] [target]
#   -s       terminals in a 20% column on the right, split in two and without
#            the radar column (prefix+V), instead of the default layout. Not
#            idempotent: it always adds the column.
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
# whole layout runs on the remote, in the session's working directory -- all but
# the git feed, which always runs here: it lists the ssh sessions itself, beside
# the local ones, and asks their hosts (see modules/git-radar/README.md). Paths
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
terminal_command="$(pane_command "$top" "$setup" no-exit)"

# NeoVim, as a new pane runs it -- when the layout has to bring it back.
nvim_command="$(pane_command "$top" "$editor" no-exit)"

# NeoVim, as typed into the pane the layout was applied to. In an ssh session
# that pane is either still a local shell -- the first pane of a session
# New-SshSession.sh has just created -- which has to ssh there first, or already
# a shell on the remote (prefix+v from a remote pane), where another ssh would
# only nest a second connection inside the first.
if [ -n "$remote" ] && [ "$(tmux display-message -p -t "$top" '#{pane_current_command}')" = ssh ]; then
  editor_line="$(remote_typed_command "$top" "$editor" no-exit)"
else
  editor_line="$nvim_command"
fi

# The two live feeds, the same ones prefix+t, r and prefix+t, R open. No
# no-exit on either: closing a feed should close its pane, not leave a shell
# sitting in a sliver of the radar column. The git feed's command is built with
# pwsh_command, not pane_command, for the reason above -- as prefix+t, R's -L.
agent_feed='& ~/.modules/agent-radar/scripts/Watch-AgentFeed.py'
git_feed="$(pwsh_command '& ~/.modules/git-radar/scripts/Watch-GitFeed.py')"

# The fixed sizes, each a percentage of the window. The radar column is
# git_width_pct wide and full height, with the agent feed taking
# agents_height_pct of it from the bottom; the terminal row is
# terminal_height_pct tall. Everything else -- NeoVim, and any pane the user
# adds -- gets what is left.
git_width_pct=12
agents_height_pct=40
terminal_height_pct=16

# @layout_role is what tells this layout's panes apart from lookalikes. Labels
# can't: prefix+% opens more "Terminal" panes, and prefix+t, r/R open "Agents"
# and "Git" panes of their own.
mark_role() {
  tmux set -p -t "$1" @layout_role "$2"
}

# find_layout_panes
# Sets git, agents, terminal and neovim to the pane ids holding those roles in
# the target's window, or to empty for a role nobody holds.
#
# Windows laid out before @layout_role existed carry labels but no roles. Only
# when the window has no role at all are the labels trusted -- Git and Agents
# by name at the window's left edge, NeoVim by name, Terminal as the
# "Terminal" pane nearest below NeoVim and lined up with it, so a custom
# terminal beside it isn't taken -- and the panes found that way get their
# roles stamped so later runs don't need to guess.
find_layout_panes() {
  git="" agents="" terminal="" neovim=""
  local id left pane_top role label
  local -a unmarked=()
  local panes
  # '|' rather than a tab: read collapses runs of whitespace separators, which
  # would shift the fields of a pane whose role is still empty.
  panes="$(tmux list-panes -t "$top" -F '#{pane_id}|#{pane_left}|#{pane_top}|#{@layout_role}|#{@pane_label}')"

  while IFS='|' read -r id left pane_top role label; do
    case "$role" in
      git) git=$id ;;
      agents) agents=$id ;;
      terminal) terminal=$id ;;
      neovim) neovim=$id ;;
      *) unmarked+=("$id|$left|$pane_top|$label") ;;
    esac
  done <<<"$panes"

  [ -z "$git$agents$terminal$neovim" ] || return 0

  local neovim_left="" neovim_top="" terminal_top=""
  for pane in "${unmarked[@]}"; do
    IFS='|' read -r id left pane_top label <<<"$pane"
    # The radar column is at the left edge; a feed opened by prefix+t, r/R
    # splits off to the right of some other pane and never is.
    case "$label" in
      Git) [ -n "$git" ] || [ "$left" != 0 ] || git=$id ;;
      Agents) [ -n "$agents" ] || [ "$left" != 0 ] || agents=$id ;;
      NeoVim) [ -n "$neovim" ] || { neovim=$id neovim_left=$left neovim_top=$pane_top; } ;;
    esac
  done
  if [ -n "$neovim" ]; then
    for pane in "${unmarked[@]}"; do
      IFS='|' read -r id left pane_top label <<<"$pane"
      if [ "$label" = "Terminal" ] && [ "$left" = "$neovim_left" ] && [ "$pane_top" -gt "$neovim_top" ] &&
        { [ -z "$terminal_top" ] || [ "$pane_top" -lt "$terminal_top" ]; }; then
        terminal=$id terminal_top=$pane_top
      fi
    done
  fi

  [ -z "$git" ] || mark_role "$git" git
  [ -z "$agents" ] || mark_role "$agents" agents
  [ -z "$terminal" ] || mark_role "$terminal" terminal
  [ -z "$neovim" ] || mark_role "$neovim" neovim
}

# fit_pane <pane> <-x|-y> <cells>
# Resizes <pane> along one axis, but only when it isn't that size already.
fit_pane() {
  local pane=$1 flag=$2 cells=$3 dimension=width
  [ "$flag" = "-y" ] && dimension=height
  [ "$(tmux display-message -p -t "$pane" "#{pane_$dimension}")" = "$cells" ] ||
    tmux resize-pane -t "$pane" "$flag" "$cells"
}

if [ -n "$side" ]; then
  # A 20% column on the right, halved: a bare terminal on top and the setup
  # terminal below it.
  column="$(new_pane "$top" "Terminal" "$(pane_command "$top" '')" -h -l 20%)"
  new_pane "$column" "Terminal" "$terminal_command" -v -l 50% >/dev/null
  label_pane "$top" "NeoVim"
  tmux send-keys -t "$top" "$editor_line" C-m
  tmux select-pane -t "$top"
  exit 0
fi

# The default layout: a radar column down the left edge -- git feed on top,
# agent feed under it -- and NeoVim over a terminal row in what is left. The
# feeds are part of the default layout rather than something prefix+t, r/R has
# to open every time: they are the panes whose whole job is to be read without
# being asked for, so they get a column of their own that NeoVim never covers.
#
# A remote without this dev-environment gets no radar column: there, only
# NeoVim and the terminal are laid out and repaired.
find_layout_panes

# A window with none of the layout in it is a fresh one: the pane the binding
# fired in becomes NeoVim, and the fixed panes are built around it below.
fresh=""
if [ -z "$git$agents$terminal$neovim" ]; then
  fresh="yes"
  neovim=$top
  label_pane "$neovim" "NeoVim"
  mark_role "$neovim" neovim
fi

# `-b` puts a split *before* the pane being split: that is what lands the
# column on the left and Git above Agents. `-f` makes the column span the full
# window height whichever pane it is split from, including a NeoVim that
# already has a terminal under it.
if [ -n "$radars" ] && [ -z "$git" ]; then
  if [ -n "$agents" ]; then
    git="$(new_pane "$agents" "Git" "$git_feed" -v -b -l $((100 - agents_height_pct))%)"
  else
    git="$(new_pane "$top" "Git" "$git_feed" -h -b -f -l "$git_width_pct%")"
  fi
  mark_role "$git" git
fi

if [ -n "$radars" ] && [ -z "$agents" ]; then
  agents="$(new_pane "$git" "Agents" "$(pane_command "$top" "$agent_feed")" -v -l "$agents_height_pct%")"
  mark_role "$agents" agents
fi

# A missing NeoVim is only brought back when nothing has taken its place: the
# terminal has grown to the top of the window, or there is no pane at all
# beside the radar column. Anything else there is the user's and stays. Plain
# splits, no sizes: the fixed panes are fitted below and NeoVim gets the rest.
if [ -z "$neovim" ]; then
  if [ -n "$terminal" ]; then
    if [ "$(tmux display-message -p -t "$terminal" '#{pane_top}')" = 0 ]; then
      neovim="$(new_pane "$terminal" "NeoVim" "$nvim_command" -v -b)"
    fi
  elif [ -n "$radars" ] &&
    [ "$(tmux list-panes -t "$top" -F '#{pane_id}' | grep -cvxF -e "$git" -e "$agents")" = 0 ]; then
    neovim="$(new_pane "$git" "NeoVim" "$nvim_command" -h -f)"
  fi
  [ -z "$neovim" ] || mark_role "$neovim" neovim
fi

# The terminal goes under NeoVim, or, once NeoVim is gone, under the pane the
# binding fired in -- unless that is the radar column, which has no room for it.
if [ -z "$terminal" ]; then
  anchor=${neovim:-$top}
  if [ "$anchor" = "$git" ] || [ "$anchor" = "$agents" ]; then
    tmux display-message "No NeoVim pane: run prefix+v from the pane the terminal should go under"
  else
    terminal="$(new_pane "$anchor" "Terminal" "$terminal_command" -v -l "$terminal_height_pct%")"
    mark_role "$terminal" terminal
  fi
fi

# Put the fixed sizes back. On a fresh window this only evens out rounding
# from the splits; on an old one it undoes stray resizes. Git's width sets the
# whole column's; Git's height is whatever the full-height column has left
# above Agents. The terminal's width is left alone: custom panes may share its
# row.
read -r window_width window_height < <(tmux display-message -p -t "$top" '#{window_width} #{window_height}')
if [ -n "$radars" ]; then
  fit_pane "$git" -x $((window_width * git_width_pct / 100))
  fit_pane "$agents" -y $((window_height * agents_height_pct / 100))
fi
[ -z "$terminal" ] || fit_pane "$terminal" -y $((window_height * terminal_height_pct / 100))

if [ -n "$fresh" ]; then
  tmux send-keys -t "$neovim" "$editor_line" C-m
fi

# C-h from NeoVim is `select-pane -L`, which breaks the tie between the two
# panes of the radar column by most-recently-active. Touching the git feed
# makes that C-h land on Git instead of on the agent feed.
[ -z "$git" ] || tmux select-pane -t "$git"
tmux select-pane -t "${neovim:-$top}"
