#!/usr/bin/env bash
# Applies the standard project layout to a tmux target: a narrow radar column
# on the left (the git feed above, the agent feed below) and, filling the rest
# of the window, a picker pane that asks what it should be -- NeoVim, a
# terminal or one of the coding agents (Select-PaneKind.sh) -- and turns into
# it. With -f the rest of the window is NeoVim over a terminal running the
# project's setup command instead.
#
# Safe to run again on a window that already has the layout: it only creates
# the radar panes (Git, Agents) that are missing and puts the fixed sizes back,
# so prefix+v also repairs a layout broken by a closed pane or a stray resize.
# A missing terminal row is left missing -- an existing one is only resized --
# unless -f asks for it. NeoVim's size is never enforced, and without -f neither
# is its presence as long as something else holds its place (the picker, or
# whatever it turned into); the main pane is only recreated when nothing does
# -- the terminal reaching the top of the window, or the radar column being all
# that is left -- and then as a picker, or as NeoVim with -f.
#
# Usage: Set-NeovimLayout.sh [-f] [target]
#   -f       force the NeoVim layout (prefix+V): NeoVim instead of the picker,
#            plus a missing terminal row under NeoVim, and a missing NeoVim
#            right beside the radar column even when other panes have taken
#            its place.
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

force=""
while getopts ":f" option; do
  case "$option" in
    f) force="yes" ;;
    *) die "Set-NeovimLayout.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

# Resolve to a concrete pane id so we never depend on pane indexes / pane-base-index.
top="$(current_pane "${1:-}")"

# Every pane goes through pane_command, so in an ssh session (prefix+N) the
# whole layout runs on the remote, in the session's working directory -- all but
# the two feeds and the picker, which always run here: each feed lists the ssh
# sessions' panes itself, beside the local ones, and asks their hosts (see the
# ssh sessions sections of modules/git-radar/README.md and
# modules/agent-radar/README.md), and the picker hands what it is turned into
# to pane_command in turn. Paths are spelled with ~ rather than $HOME for the
# same reason: $HOME would be expanded here, to this machine's home, while pwsh
# expands ~ wherever it runs.
#
# A remote without this dev-environment has no pwsh profile and no ~/.modules,
# so it gets what can still work there: plain NeoVim, a login shell for the
# terminal (both from pane_kind) and no radar column.
radars="yes"
remote="$(ssh_option "$top" @ssh_target)"
if [ -n "$remote" ] && ! ssh_is_devenv "$top"; then
  radars=""
fi

pane_kind "$top" Terminal
terminal_command="$(pane_command "$top" "$kind_command" "$kind_no_exit")"

# NeoVim, as a new pane runs it -- when the layout has to bring it back.
pane_kind "$top" NeoVim
editor=$kind_command
nvim_command="$(pane_command "$top" "$editor" "$kind_no_exit")"

# The picker, as a new pane runs it. Always local: fzf runs here.
picker_command="bash ~/.modules/tmux/scripts/Select-PaneKind.sh"

# What is typed into the pane the layout was applied to, on a fresh window. In
# an ssh session that pane is either still a local shell -- the first pane of a
# session New-SshSession.sh has just created -- which has to ssh there first,
# or already a shell on the remote (prefix+v from a remote pane), where another
# ssh would only nest a second connection inside the first -- and where the
# picker, a local script, cannot run, so that pane gets NeoVim whatever -f says.
top_picker="yes"
[ -z "$force" ] || top_picker=""
if [ -n "$remote" ] && [ "$(tmux display-message -p -t "$top" '#{pane_current_command}')" = ssh ]; then
  top_picker=""
  editor_line="$(remote_typed_command "$top" "$editor" no-exit)"
else
  editor_line="$(closing_line "$nvim_command")"
fi
picker_line="$(closing_line "$picker_command")"

# The two live feeds, the same ones prefix+t, r and prefix+t, R open. No
# no-exit on either: closing a feed should close its pane, not leave a pwsh
# prompt sitting in a sliver of the radar column. Both are built with
# pwsh_invocation, not pane_command, for the reason above -- as prefix+t, r's
# and R's -L.
agent_feed="$(pwsh_invocation '& ~/.modules/agent-radar/scripts/Watch-AgentFeed.py')"
git_feed="$(pwsh_invocation '& ~/.modules/git-radar/scripts/Watch-GitFeed.py')"

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
# Sets git, agents, terminal, neovim and picker to the pane ids holding those
# roles in the target's window, or to empty for a role nobody holds. The
# picker's role is its own only until it is answered: Select-PaneKind.sh hands
# it on to neovim, or drops it for anything else.
#
# Windows laid out before @layout_role existed carry labels but no roles. Only
# when the window has no role at all are the labels trusted -- Git and Agents
# by name at the window's left edge, NeoVim by name, Terminal as the
# "Terminal" pane nearest below NeoVim and lined up with it, so a custom
# terminal beside it isn't taken -- and the panes found that way get their
# roles stamped so later runs don't need to guess.
find_layout_panes() {
  git="" agents="" terminal="" neovim="" picker=""
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
      picker) picker=$id ;;
      *) unmarked+=("$id|$left|$pane_top|$label") ;;
    esac
  done <<<"$panes"

  [ -z "$git$agents$terminal$neovim$picker" ] || return 0

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

# The default layout: a radar column down the left edge -- git feed on top,
# agent feed under it -- and the picker in what is left (NeoVim over a
# terminal row, with -f). The
# feeds are part of the default layout rather than something prefix+t, r/R has
# to open every time: they are the panes whose whole job is to be read without
# being asked for, so they get a column of their own that NeoVim never covers.
#
# A remote without this dev-environment gets no radar column: there, only
# main pane and the terminal are laid out and repaired.
find_layout_panes

# A window with none of the layout in it is a fresh one: the pane the binding
# fired in becomes the picker, or NeoVim with -f, and the fixed panes are built
# around it below.
fresh=""
if [ -z "$git$agents$terminal$neovim$picker" ]; then
  fresh="yes"
  if [ -n "$top_picker" ]; then
    picker=$top
    label_pane "$picker" "Picker"
    mark_role "$picker" picker
  else
    neovim=$top
    label_pane "$neovim" "NeoVim"
    mark_role "$neovim" neovim
  fi
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
  agents="$(new_pane "$git" "Agents" "$agent_feed" -v -l "$agents_height_pct%")"
  mark_role "$agents" agents
fi

# A missing main pane is only brought back when nothing has taken its place:
# the terminal has grown to the top of the window, or there is no pane at all
# beside the radar column. Anything else there is the user's and stays -- a
# picker still waiting for an answer included. It comes back as NeoVim with
# -f and as a picker without. Plain splits, no sizes: the fixed panes are
# fitted below and the main pane gets the rest.
#
# main_split <target> [split-window args...]
main_split() {
  local target=$1
  shift
  if [ -n "$force" ]; then
    neovim="$(new_pane "$target" "NeoVim" "$nvim_command" "$@")"
    mark_role "$neovim" neovim
  else
    picker="$(new_pane "$target" "Picker" "$picker_command" "$@")"
    mark_role "$picker" picker
  fi
}
if [ -z "$neovim$picker" ]; then
  if [ -n "$terminal" ]; then
    if [ "$(tmux display-message -p -t "$terminal" '#{pane_top}')" = 0 ]; then
      main_split "$terminal" -v -b
    fi
  elif [ -n "$radars" ] &&
    [ "$(tmux list-panes -t "$top" -F '#{pane_id}' | grep -cvxF -e "$git" -e "$agents")" = 0 ]; then
    main_split "$git" -h -f
  fi
fi

# -f wants NeoVim back whatever took its place, a waiting picker included: it
# goes right beside the radar column, split off the left of the top pane there,
# so the user's panes move right rather than going anywhere. -f alone would put
# it at the far edge of the window instead. Without the column, it goes left of
# the pane the binding fired in. A terminal that is missing too is split off
# first, so the row runs under both NeoVim and the pane it pushes aside rather
# than under NeoVim alone.
if [ -z "$neovim" ] && [ -n "$force" ]; then
  beside=$top
  if [ -n "$radars" ]; then
    column_right="$(tmux display-message -p -t "$git" '#{pane_right}')"
    beside="$(tmux list-panes -t "$top" -F '#{pane_id} #{pane_left} #{pane_top}' |
      awk -v left=$((column_right + 2)) '$2 == left && $3 == 0 { print $1; exit }')"
  fi
  if [ -n "$beside" ]; then
    if [ -z "$terminal" ]; then
      terminal="$(new_pane "$beside" "Terminal" "$terminal_command" -v -l "$terminal_height_pct%")"
      mark_role "$terminal" terminal
    fi
    neovim="$(new_pane "$beside" "NeoVim" "$nvim_command" -h -b)"
    mark_role "$neovim" neovim
  fi
fi

# Only -f (prefix+V) brings a missing terminal back; prefix+v leaves it closed.
# It goes under NeoVim, or, once NeoVim is gone, under the pane the binding
# fired in -- unless that is the radar column, which has no room for it.
if [ -z "$terminal" ] && [ -n "$force" ]; then
  anchor=${neovim:-$top}
  if [ "$anchor" = "$git" ] || [ "$anchor" = "$agents" ]; then
    tmux display-message "No NeoVim pane: run prefix+V from the pane the terminal should go under"
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
  if [ -n "$picker" ]; then
    tmux send-keys -t "$picker" "$picker_line" C-m
  else
    tmux send-keys -t "$neovim" "$editor_line" C-m
  fi
fi

# C-h from NeoVim is `select-pane -L`, which breaks the tie between the two
# panes of the radar column by most-recently-active. Touching the git feed
# makes that C-h land on Git instead of on the agent feed.
[ -z "$git" ] || tmux select-pane -t "$git"
tmux select-pane -t "${neovim:-${picker:-$top}}"
