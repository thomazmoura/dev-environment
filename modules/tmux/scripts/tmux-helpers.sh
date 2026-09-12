#!/usr/bin/env bash
# Shared helpers for the tmux binding scripts. Sourced, never run.
#
# Every pane the bindings open goes through new_pane. That chain used to be
# spelled out inline in tmux.conf, once per binding and through three levels of
# quoting:
#
#   split-window -h; select-pane -T "X"; set -p @pane_label "X"; \
#     send-keys "pwsh -C \"tool\" && exit" C-m
#
# Fifteen copies of it, each one a chance to forget the @pane_label (which is
# what Select-Pane.sh lists panes by) or to lose a backslash. Now the quoting
# lives here.
#
# Sourced by a caller that has already set `set -euo pipefail`; nothing here
# runs at source time beyond sourcing ssh-helpers.sh, which is definitions too.
# Same convention as modules/herdr/scripts/workspace-actions.sh.

source "$(dirname "${BASH_SOURCE[0]}")/ssh-helpers.sh"

# --- Failure reporting -------------------------------------------------------
# die assumes it is running inside a popup, where the message would vanish with
# the popup: it holds the popup open until the user has read it. Scripts that
# run from `run-shell -b` have no surface at all, so they use warn.
die() { printf '%s\n' "$*" >&2; read -rsn1 -p "Press any key to close..." _; exit 1; }

# warn puts the message on the tmux status line, which is the only thing a
# backgrounded run-shell can still write to once its pane context is gone.
warn() { tmux display-message "$*"; exit 1; }

require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null || die "Required tool not found: $tool"
  done
}

# --- Directory guards --------------------------------------------------------
# The runner bindings all start with `cd <glob>` against the pane's current
# path, so pointing one at the wrong directory used to open a pane whose only
# content was pwsh's "Cannot find path" spew. directory_matches lets the caller
# check the glob first and say something useful instead.

# directory_matches <path> <glob>
# True when <path> contains at least one *directory* matching <glob>. The
# trailing slash on the pattern is what restricts the match to directories, and
# nullglob is what makes a miss expand to nothing rather than to the pattern
# itself. Both live inside the subshell so the caller's shell options and
# positional parameters are left alone.
directory_matches() {
  local path=$1 glob=$2
  (
    cd "$path" 2>/dev/null || exit 1
    shopt -s nullglob
    set -- $glob/
    [ "$#" -gt 0 ]
  )
}

# shell_quote <string>
# Quotes a string as a shell literal. Needed because the pane commands are
# *typed into* a shell by send-keys, so any path or message that reaches one has
# to survive a round of shell parsing -- an apostrophe in "There's no ..." is
# enough to break the line otherwise. %q is bash's own quoting, and the panes
# run bash, so its $'...' form for odd characters is understood at the far end.
shell_quote() {
  printf '%q' "$1"
}

# notice_command <message>
# A pane command that shows <message>, waits for a single keypress and then
# closes the pane by exiting its shell. Used in place of the real tool command
# when a directory guard fails: the message needs to stay on screen (a status
# line one is gone in seconds), but the pane has no reason to outlive it.
notice_command() {
  printf 'clear; echo; echo %s; echo; read -rsn1 -p %s _; exit' \
    "$(shell_quote "$1")" "$(shell_quote 'Press any key to close...')"
}

# --- Panes -------------------------------------------------------------------
# Titles a pane twice over: `select-pane -T` is what the pane border shows, and
# @pane_label is what Select-Pane.sh reads. Both are needed -- the border title
# is rewritten by any program that emits OSC 2 (pwsh does), while the option
# stays put for the lifetime of the pane.
label_pane() {
  tmux select-pane -t "$1" -T "$2"
  tmux set -p -t "$1" @pane_label "$2"
}

# pwsh_command <command> [no-exit]
# Builds the pwsh invocation the bindings send. Without the second argument the
# pane runs the command and closes with it; with it, pwsh stays interactive
# afterwards. An empty command opens a plain interactive pwsh -- that is what
# the prefix+% and prefix+" terminal splits want.
#
# All three forms end in `&& exit` so the pane closes when the shell does, but
# only on success: a failing command leaves the pane up with its error on
# screen instead of taking the evidence with it.
pwsh_command() {
  printf '%s && exit' "$(pwsh_invocation "$@")"
}

# pwsh_invocation <command> [no-exit]
# pwsh_command without the `&& exit`: just the pwsh call. An ssh session runs
# this on the remote and puts the `&& exit` after the ssh instead (see
# ssh-helpers.sh).
pwsh_invocation() {
  local command=$1 no_exit=${2:-}
  if [ -z "$command" ]; then
    printf 'pwsh'
  elif [ -n "$no_exit" ]; then
    printf 'pwsh -NoExit -Command "%s"' "$command"
  else
    printf 'pwsh -Command "%s"' "$command"
  fi
}

# pane_command <pane> <command> [no-exit]
# What a new pane split off <pane> should run: pwsh_command, or the same thing
# over ssh when <pane> belongs to a session opened with prefix+N. Every
# pane-creating script builds its command through here, which is what lets the
# bindings in common.conf stay unaware of ssh sessions.
pane_command() {
  if [ -n "$(ssh_option "$1" @ssh_target)" ]; then
    ssh_command "$@"
  else
    pwsh_command "${@:2}"
  fi
}

# new_pane <target> <label> <command> [split-window args...]
# Splits <target>'s window, labels the new pane, starts <command> in it and
# prints the new pane id.
#
# The command is typed into the pane with send-keys rather than handed to
# split-window as its shell-command because the pane must keep a real shell:
# that is what makes `&& exit` above -- and the user's own Ctrl-C -- behave.
new_pane() {
  local target=$1 label=$2 command=$3
  shift 3
  local pane
  pane="$(tmux split-window -t "$target" -c '#{pane_current_path}' -P -F '#{pane_id}' "$@")"
  label_pane "$pane" "$label"
  tmux send-keys -t "$pane" "$command" C-m
  printf '%s' "$pane"
}

# current_pane [target]
# Resolves a binding's target to a concrete pane id, so nothing downstream
# depends on pane indexes or on which client is attached. Bindings pass
# "#{pane_id}"; an empty argument falls back to whatever tmux considers current.
current_pane() {
  if [ -n "${1:-}" ]; then
    tmux display-message -p -t "$1" '#{pane_id}'
  else
    tmux display-message -p '#{pane_id}'
  fi
}
