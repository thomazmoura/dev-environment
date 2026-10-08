#!/usr/bin/env bash
# Applies the standard project layout to a tmux target: a narrow radar column
# on the left (the git feed above, the agent feed below) and, filling the rest
# of the window, a picker pane that asks what it should be -- NeoVim, a
# terminal or one of the coding agents (Select-PaneKind.sh) -- and turns into
# it. With -f the rest of the window is NeoVim over a terminal running the
# project's setup command instead. With -H it is the home layout: Paperboy's
# inbox on the left half of the rest and Workhorse's last query on the right.
#
# A project that keeps a .notes file at the root of its repository gets a third
# pane at the bottom of the radar column: that file in a nearly bare NeoVim (the Notes
# pane kind, prefix+n). Both prefix+v and prefix+V bring it back when it is
# missing, and take it away once the file is gone.
#
# A window zoomed with prefix+z keeps its zoom: only the radar column beside the
# zoomed pane is repaired -- its width and the heights of its panes put back --
# and nothing is opened or closed, as a new pane would end the zoom. prefix+V
# and prefix+H zoom out first and repair the whole window.
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
# Nothing is ever typed into a pane this script did not create, unless -n says
# the caller has just created it: the pane a binding fires in may be running
# anything -- an agent, an editor, a half-typed command -- and a window laid
# out before @layout_role existed looks just like a fresh one. Without -n that
# pane is left alone and the layout is built around it; prefix+Space opens a new
# picker pane when one is wanted.
#
# The window changes on screen once: every change -- new panes, roles, sizes,
# focus -- is queued (queue in tmux-helpers.sh) and handed to tmux as one
# command list, which tmux runs before it redraws. New panes are made out of
# sight first (place_pane) and moved into place in that same list. Only
# prefix+V, building a terminal row under a column it has just added, sends
# the column ahead, as the row is fitted around it.
#
# Usage: Set-NeovimLayout.sh [-f | -H] [-n] [-k] [target]
#   -f       force the NeoVim layout (prefix+V): NeoVim instead of the picker,
#            plus a missing terminal row under the whole content area, and a missing NeoVim
#            right beside the radar column even when other panes have taken
#            its place.
#   -H       the home layout (prefix+H): Paperboy and Workhorse side by side
#            instead of the picker, each brought back when missing. Unlike the
#            other two it never builds around other work: a window holding
#            anything but the radar column and an unanswered picker gets a new
#            window with the layout instead, and the picker is turned into
#            Paperboy.
#   -n       the target is the only pane of a window the caller has just
#            created, still an idle shell: it becomes the picker (NeoVim with
#            -f, Paperboy with -H) rather than being built around.
#   -k       leave the focus where it is, for the automatic repairs
#            (Repair-Layouts.sh): the user is typing somewhere and the layout
#            changing around them shouldn't take their keys elsewhere. Without
#            it the focus goes to the main pane.
#   target   any tmux target (pane id like %12, or "session:"). Defaults to the
#            current pane.
#
# Used by the prefix+v / prefix+V bindings and, with -n, by New-CodeSession.sh,
# New-SshSession.sh and vtmux (DevHelpers.psm1), which build a session and
# then hand it here so a new project always opens the same way -- on the
# remote, for an ssh session. Without arguments, by Repair-Layouts.sh whenever a
# laid-out window is resized or loses a pane.
set -euo pipefail

source "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/tmux-helpers.sh"

# This runs from `run-shell -b`, which has no popup to write a failure to.
die() { warn "$@"; }

force=""
home=""
new_window=""
keep_focus=""
while getopts ":fnHk" option; do
  case "$option" in
    f) force="yes" ;;
    H) home="yes" ;;
    n) new_window="yes" ;;
    k) keep_focus="yes" ;;
    *) die "Set-NeovimLayout.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

# One run at a time: the hooks run Repair-Layouts.sh on every resize and closed
# pane, alongside prefix+v and Restore-PickerPane.sh, and two runs repairing the
# same window would both open its missing panes. Repair-Layouts.sh holds the
# lock for the whole sweep and says so, and -H's exec below keeps it held.
if [ -z "${TMUX_LAYOUT_LOCKED:-}" ]; then
  exec 9>"${TMUX_TMPDIR:-/tmp}/tmux-layout-$(id -u).lock"
  flock -w 30 9 || true
  export TMUX_LAYOUT_LOCKED=1
fi

# Resolve to a concrete pane id so we never depend on pane indexes / pane-base-index.
top="$(current_pane "${1:-}")"
session="$(tmux display-message -p -t "$top" '#{session_id}')"

# A window zoomed with prefix+z only has its radar column fitted (see the top);
# with -f or -H it is zoomed out first: the layout is worked out from, and
# repairs, the panes of the whole window, the hidden ones included.
column_only=""
if [ -z "$force$home" ] && [ -n "$(tmux display-message -p -t "$top" '#{@zoom_stash}')" ]; then
  column_only="yes"
else
  "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/Switch-PaneZoom.sh" --restore "$top"
fi

# The home layout takes a window only when nothing in it is anyone's work: every
# pane is a radar-column pane or a picker still waiting for an answer, or the
# window already is a home layout, which is repaired. Anything else -- NeoVim,
# an agent, a terminal, a pane with no role at all -- stays as it is, and the
# layout is built in a new window, which is then a fresh one (-n). Checked
# before the window is marked a layout window below, so a busy window this
# leaves alone is not marked either.
if [ -n "$home" ]; then
  force=""
  if [ -z "$new_window" ]; then
    roles="$(tmux list-panes -t "$top" -F '#{@layout_role}')"
    if ! grep -qxE 'paperboy|workhorse' <<<"$roles" &&
      grep -qvxE 'git|agents|notes|picker' <<<"$roles"; then
      path="$(tmux display-message -p -t "$top" '#{pane_current_path}')"
      # Made in the background and shown by the run below once its layout is
      # done (LAYOUT_SHOW_WINDOW), so the bare window never shows.
      pane="$(tmux new-window -d -t "$session:" -c "$path" -P -F '#{pane_id}')"
      LAYOUT_SHOW_WINDOW=1 exec "$(readlink -f "${BASH_SOURCE[0]}")" -H -n "$pane"
    fi
  fi
fi

# A laid-out window is never left with nothing to work in: when its last pane
# but the feeds closes, a picker takes that pane's place (Restore-PickerPane.sh,
# from the pane-died and after-kill-pane hooks in common.conf). remain-on-exit
# is what gives the hook a dead pane to respawn rather than a hole.
queue set -w -t "$top" @layout_window yes
queue set -w -t "$top" remain-on-exit on

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

# What is typed into the pane the layout was applied to, with -n. That pane is
# a local shell even in an ssh session -- the first pane of a session
# New-SshSession.sh has just created -- so NeoVim goes through the same ssh a
# new pane would, and the picker runs here as it always does.
editor_line="$(closing_line "$nvim_command")"
picker_line="$(closing_line "$picker_command")"

# The home layout's two panes, as a new one runs them -- where the session does,
# like NeoVim, since both are NeoVim (pane_kind's Paperboy and Workhorse).
paperboy_command="" workhorse_command=""
if [ -n "$home" ]; then
  pane_kind "$top" Paperboy
  paperboy_command="$(pane_command "$top" "$kind_command" "$kind_no_exit")"
  pane_kind "$top" Workhorse
  workhorse_command="$(pane_command "$top" "$kind_command" "$kind_no_exit")"
fi

# The notes pane, as a new one runs it. Like NeoVim it runs where the session
# does, on the remote in an ssh session; only a window with the radar column
# has a place for it.
notes_command=""
want_notes=no
if [ -n "$radars" ] && [ -z "$column_only" ]; then
  pane_kind "$top" Notes
  notes_command="$(pane_command "$top" "$kind_command" "$kind_no_exit" "$kind_no_pwsh")"
  # yes, no, or -- an ssh session's host could not be asked -- unknown, which
  # leaves a notes pane that is there alone and does not open one that is not.
  status=0
  has_notes "$top" || status=$?
  case "$status" in
    0) want_notes=yes ;;
    2) want_notes=unknown ;;
  esac
fi

# The two live feeds, the same ones prefix+r and prefix+R open. No
# no-exit on either: closing a feed should close its pane, not leave a pwsh
# prompt sitting in a sliver of the radar column. Both are built with
# pwsh_invocation, not pane_command, for the reason above -- as prefix+r's
# and R's -L.
agent_feed="$(pwsh_invocation '& ~/.modules/agent-radar/scripts/Watch-AgentFeed.py')"
git_feed="$(pwsh_invocation '& ~/.modules/git-radar/scripts/Watch-GitFeed.py')"

# The fixed sizes, each a percentage of the window. The radar column is
# git_width_pct wide and full height, with the agent feed taking
# agents_height_pct of it -- and the notes pane, when there is one,
# notes_height_pct at the very bottom -- and Git the rest at the top; the
# terminal row is terminal_height_pct tall. Everything else -- NeoVim, and any
# pane the user adds -- gets what is left.
git_width_pct=12
agents_height_pct=40
notes_height_pct=25
terminal_height_pct=$TERMINAL_HEIGHT_PCT

# @layout_role is what tells this layout's panes apart from lookalikes. Labels
# can't: prefix+% opens more "Terminal" panes, prefix+r/R open "Agents"
# and "Git" panes of their own, and the picker opens Paperboy and Workhorse.
mark_role() {
  queue set -p -t "$1" @layout_role "$2"
}

# stale is set once the batch moves, kills or respawns a pane, or gives one a
# role: what tmux says about the window is then not what it will be, and
# settle has to send the batch before anything reads the window back.
stale=""
settle() {
  [ -n "$stale" ] || return 0
  send_batch
  close_stage
  stale=""
}

# New panes are made in a window of their own that draws nothing in the status
# bar (as Switch-PaneZoom.sh's stash), and moved into place with join-pane --
# which takes the very arguments split-window would have -- in the batch.
#
# The window's first pane stays behind, and the window is closed after the
# batch: a command list that moves every pane out of a window brings the tmux
# server down (3.6, with a client attached). Closed on the way out, too, after a
# run that failed half-way.
stash_format='#{?window_end_flag,#{E:@status_after_windows},}'
stage_window=""
declare -A stage_path=()
close_stage() {
  [ -z "$stage_window" ] || tmux kill-window -t "$stage_window" 2>/dev/null || true
  stage_window=""
}
trap close_stage EXIT

# place_pane <target> <label> <role> <command> [split-window args...]
# new_pane, queued: the pane is made out of sight, in <target>'s working
# directory, and its move to where the split would have put it, its label, role
# and command are queued. Sets placed to its id. <target> may be a pane queued
# earlier.
place_pane() {
  local target=$1 label=$2 role=$3 command=$4 path
  shift 4
  path=${stage_path[$target]:-}
  [ -n "$path" ] || path="$(tmux display-message -p -t "$target" '#{pane_current_path}')"
  if [ -z "$stage_window" ]; then
    # Made after the session's last window ({end}), so the formats can reach
    # it in the same list and it never shows.
    stage_window="$(tmux new-window -d -a -t "$session:{end}" -n layout-stage -P -F '#{window_id}' 'sleep 600' \; \
      set -w -t "$session:{end}" window-status-format "$stash_format" \; \
      set -w -t "$session:{end}" window-status-current-format "$stash_format")"
  fi
  # Tiled after each split, so a small window never runs out of room.
  placed="$(tmux split-window -d -t "$stage_window" -c "$path" -P -F '#{pane_id}' \; \
    select-layout -t "$stage_window" tiled)"
  stage_path[$placed]=$path
  queue join-pane -d -s "$placed" -t "$target" "$@"
  queue_label "$placed" "$label"
  mark_role "$placed" "$role"
  queue send-keys -t "$placed" "$(closing_line "$command")" C-m
  stale=yes
}

# find_layout_panes
# Sets git, agents, notes, terminal, neovim, picker, paperboy and workhorse to the pane ids holding those
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
  git="" agents="" notes="" terminal="" neovim="" picker="" paperboy="" workhorse=""
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
      notes) notes=$id ;;
      terminal) terminal=$id ;;
      neovim) neovim=$id ;;
      picker) picker=$id ;;
      paperboy) paperboy=$id ;;
      workhorse) workhorse=$id ;;
      *) unmarked+=("$id|$left|$pane_top|$label") ;;
    esac
  done <<<"$panes"

  [ -z "$git$agents$notes$terminal$neovim$picker$paperboy$workhorse" ] || return 0

  local neovim_left="" neovim_top="" terminal_top=""
  for pane in "${unmarked[@]}"; do
    IFS='|' read -r id left pane_top label <<<"$pane"
    # The radar column is at the left edge; a feed opened by prefix+r/R
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
  # content_row finds the column by role.
  [ -z "$git$agents$terminal$neovim" ] || stale=yes
}

# fit_pane <pane> <-x|-y> <cells>
# Queues a resize of <pane> along one axis, but only when it isn't that size
# already -- or, once the batch changes the panes (stale), whatever size it is
# now. A height fit moves an edge that only its own column or row shares, but
# a width fit -- the radar column's -- moves the panes beside it too.
fit_pane() {
  local pane=$1 flag=$2 cells=$3 dimension=width
  [ "$flag" = "-y" ] && dimension=height
  [ -z "$stale" ] && [ "$(tmux display-message -p -t "$pane" "#{pane_$dimension}")" = "$cells" ] && return 0
  queue resize-pane -t "$pane" "$flag" "$cells"
  [ "$flag" = "-y" ] || stale=yes
}

# fit_column
# Puts the radar column's fixed sizes back: Git's width sets the whole
# column's; Git's height is whatever the full-height column has left above
# Agents.
fit_column() {
  local window_width window_height
  read -r window_width window_height < <(tmux display-message -p -t "$top" '#{window_width} #{window_height}')
  fit_pane "$git" -x $((window_width * git_width_pct / 100))
  # tmux resizes a pane by moving its bottom edge, or its top one when it is
  # the last pane of the column. With notes, then, Git and Notes are the two
  # that can be fitted without undoing each other, and Agents gets the rest.
  if [ -n "$notes" ]; then
    fit_pane "$git" -y $((window_height * (100 - agents_height_pct - notes_height_pct) / 100))
    fit_pane "$notes" -y $((window_height * notes_height_pct / 100))
  else
    fit_pane "$agents" -y $((window_height * agents_height_pct / 100))
  fi
}

# The default layout: a radar column down the left edge -- git feed on top,
# agent feed under it -- and the picker in what is left (NeoVim over a
# terminal row, with -f). The
# feeds are part of the default layout rather than something prefix+r/R has
# to open every time: they are the panes whose whole job is to be read without
# being asked for, so they get a column of their own that NeoVim never covers.
#
# A remote without this dev-environment gets no radar column: there, only
# main pane and the terminal are laid out and repaired.
find_layout_panes

# Zoomed (prefix+z): the column alone, as it stands. @layout_fitted is the
# zoomed layout, so the window is looked at again once it zooms out.
if [ -n "$column_only" ]; then
  [ -z "$notes" ] || agents_height_pct=35
  [ -z "$radars" ] || [ -z "$git" ] || [ -z "$agents" ] || fit_column
  queue set -w -F -t "$top" @layout_fitted '#{window_layout}'
  send_batch
  exit 0
fi

# A window the caller has just created (-n), with none of the layout in it
# yet: its one pane becomes the picker, or NeoVim with -f, and the fixed panes
# are built around it below. Any other window's panes are the user's, the one
# the binding fired in included -- a window with no layout at all just gets the
# radar column beside what is already there (and, with -f, NeoVim between the
# two).
fresh=""
if [ -n "$new_window" ] && [ -z "$git$agents$notes$terminal$neovim$picker$paperboy$workhorse" ]; then
  fresh="yes"
  if [ -n "$home" ]; then
    paperboy=$top
    queue_label "$paperboy" "Paperboy"
    mark_role "$paperboy" paperboy
  elif [ -z "$force" ]; then
    picker=$top
    queue_label "$picker" "Picker"
    mark_role "$picker" picker
  else
    neovim=$top
    queue_label "$neovim" "NeoVim"
    mark_role "$neovim" neovim
  fi
fi

# A notes pane that outlived its file goes before the column is rebuilt, so a
# missing Git or Agents is not split off around it. Until the batch is sent it
# is still in the window: closed names it for what reads the panes below.
closed=""
if [ "$want_notes" = no ] && [ -n "$notes" ]; then
  queue kill-pane -t "$notes"
  closed=$notes notes="" stale=yes
fi
if [ "$want_notes" = yes ] || [ -n "$notes" ]; then
  agents_height_pct=35
fi

# `-b` puts a split *before* the pane being split: that is what lands the
# column on the left and Git above Agents. `-f` makes the column span the full
# window height whichever pane it is split from, including a NeoVim that
# already has a terminal under it.
if [ -n "$radars" ] && [ -z "$git" ]; then
  if [ -n "$agents" ]; then
    place_pane "$agents" "Git" git "$git_feed" -v -b -l $((100 - agents_height_pct))%
  elif [ -n "$notes" ]; then
    place_pane "$notes" "Git" git "$git_feed" -v -b -l $((100 - notes_height_pct))%
  else
    place_pane "$top" "Git" git "$git_feed" -h -b -f -l "$git_width_pct%"
  fi
  git=$placed
fi

if [ -n "$radars" ] && [ -z "$agents" ]; then
  if [ -n "$notes" ]; then
    place_pane "$notes" "Agents" agents "$agent_feed" -v -b -l $((100 - notes_height_pct))%
  else
    place_pane "$git" "Agents" agents "$agent_feed" -v -l "$agents_height_pct%"
  fi
  agents=$placed
fi

if [ "$want_notes" = yes ] && [ -z "$notes" ]; then
  place_pane "$agents" "Notes" notes "$notes_command" -v -l "$notes_height_pct%"
  notes=$placed
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
  if [ -n "$home" ]; then
    place_pane "$target" "Paperboy" paperboy "$paperboy_command" "$@"
    paperboy=$placed
  elif [ -n "$force" ]; then
    place_pane "$target" "NeoVim" neovim "$nvim_command" "$@"
    neovim=$placed
  else
    place_pane "$target" "Picker" picker "$picker_command" "$@"
    picker=$placed
  fi
}
# The home layout's main pane is Paperboy. By the check at the top, a window
# without it or Workhorse holds only the radar column and, maybe, a picker: the
# picker is turned into Paperboy where it stands, and a window with no picker
# gets Paperboy split off beside the column, as the picker would be.
if [ -n "$home" ]; then
  if [ -z "$paperboy$workhorse" ] && [ -n "$picker" ]; then
    paperboy=$picker picker=""
    path="$(tmux display-message -p -t "$paperboy" '#{pane_current_path}')"
    queue respawn-pane -k -t "$paperboy" -c "$path"
    queue_label "$paperboy" "Paperboy"
    mark_role "$paperboy" paperboy
    queue send-keys -t "$paperboy" "$(closing_line "$paperboy_command")" C-m
    stale=yes
  elif [ -z "$paperboy$workhorse" ] && [ -n "$radars" ]; then
    main_split "$git" -h -f
  fi
  # Each half is brought back beside the other: Workhorse on Paperboy's right,
  # Paperboy on Workhorse's left.
  if [ -n "$paperboy" ] && [ -z "$workhorse" ]; then
    place_pane "$paperboy" "Workhorse" workhorse "$workhorse_command" -h -l 50%
    workhorse=$placed
  elif [ -z "$paperboy" ] && [ -n "$workhorse" ]; then
    place_pane "$workhorse" "Paperboy" paperboy "$paperboy_command" -h -b -l 50%
    paperboy=$placed
  fi
elif [ -z "$neovim$picker" ]; then
  # Read before the batch is sent, which only adds to the column -- its notes
  # pane aside, left out by name: neither moves the terminal's top edge.
  if [ -n "$terminal" ]; then
    if [ "$(tmux display-message -p -t "$terminal" '#{pane_top}')" = 0 ]; then
      main_split "$terminal" -v -b
    fi
  elif [ -n "$radars" ] &&
    [ "$(tmux list-panes -t "$top" -F '#{pane_id}' | grep -cvxF -e "$git" -e "$agents" -e "$notes" -e "${closed:-none}")" = 0 ]; then
    main_split "$git" -h -f
  fi
fi

# -f wants NeoVim back whatever took its place, a waiting picker included: it
# goes right beside the radar column, split off the left of the top pane there,
# so the user's panes move right rather than going anywhere. -f alone would put
# it at the far edge of the window instead. Without the column, it goes left of
# the pane the binding fired in. A terminal that is missing too is split off
# first, so the row runs under the whole content area (content_row in
# tmux-helpers.sh) -- NeoVim included -- rather than under NeoVim alone.
#
# Both read the window back -- where the column ends, what is in the top row --
# so whatever the batch has changed so far is sent first (settle). That is a
# screen update of its own only where this run has opened or closed panes
# already: a column it has just added.
if [ -z "$neovim" ] && [ -n "$force" ]; then
  settle
  beside=$top
  if [ -n "$radars" ]; then
    column_right="$(tmux display-message -p -t "$git" '#{pane_right}')"
    beside="$(tmux list-panes -t "$top" -F '#{pane_id} #{pane_left} #{pane_top}' |
      awk -v left=$((column_right + 2)) '$2 == left && $3 == 0 { print $1; exit }')"
  fi
  if [ -n "$beside" ]; then
    if [ -z "$terminal" ]; then
      content_row "$beside"
      place_pane "$beside" "Terminal" terminal "$terminal_command" -v -l "$terminal_height_pct%" "${content_row_args[@]}"
      terminal=$placed
    fi
    place_pane "$beside" "NeoVim" neovim "$nvim_command" -h -b
    neovim=$placed
  fi
fi

# Only -f (prefix+V) brings a missing terminal back; prefix+v leaves it closed.
# It goes under the whole content area, whichever pane the binding fired in.
if [ -z "$terminal" ] && [ -n "$force" ]; then
  settle
  content_row "$top"
  place_pane "$top" "Terminal" terminal "$terminal_command" -v -l "$terminal_height_pct%" "${content_row_args[@]}"
  terminal=$placed
fi

# Put the fixed sizes back. On a fresh window this only evens out rounding
# from the splits; on an old one it undoes stray resizes. The terminal's width
# is left alone: custom panes may share its row.
read -r window_width window_height < <(tmux display-message -p -t "$top" '#{window_width} #{window_height}')
[ -z "$radars" ] || fit_column
[ -z "$terminal" ] || fit_pane "$terminal" -y $((window_height * terminal_height_pct / 100))

# Paperboy takes half of what the radar column leaves, less the border between
# it and Workhorse; Workhorse gets the rest.
if [ -n "$paperboy" ] && [ -n "$workhorse" ]; then
  content=$window_width
  [ -z "$radars" ] || content=$((window_width - window_width * git_width_pct / 100 - 1))
  fit_pane "$paperboy" -x $(((content - 1) / 2))
fi

if [ -n "$fresh" ]; then
  if [ -n "$home" ]; then
    queue send-keys -t "$paperboy" "$(closing_line "$paperboy_command")" C-m
  elif [ -n "$picker" ]; then
    queue send-keys -t "$picker" "$picker_line" C-m
  else
    queue send-keys -t "$neovim" "$editor_line" C-m
  fi
fi

# C-h from NeoVim is `select-pane -L`, which breaks the tie between the two
# panes of the radar column by most-recently-active. Touching the git feed
# makes that C-h land on Git instead of on the agent feed. With -k nothing is
# selected: every pane above is placed with -d, so the focus never moved.
if [ -z "$keep_focus" ]; then
  [ -z "$git" ] || queue select-pane -t "$git"
  queue select-pane -t "${paperboy:-${neovim:-${picker:-$top}}}"
fi
# The window -H made in the background, now that there is something in it.
[ -z "${LAYOUT_SHOW_WINDOW:-}" ] || queue select-window -t "$top"

# What Repair-Layouts.sh compares against to tell whether the window has
# changed since: the layout as this run left it. -F expands it when tmux gets
# to it, after everything queued before it.
queue set -w -F -t "$top" @layout_fitted '#{window_layout}'
send_batch
