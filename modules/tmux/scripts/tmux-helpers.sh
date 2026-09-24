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
# A pane command that shows <message> and waits for a single keypress; the pane
# closes with it, as every new_pane does. Used in place of the real tool command
# when a directory guard fails: the message needs to stay on screen (a status
# line one is gone in seconds), but the pane has no reason to outlive it.
notice_command() {
  printf 'clear; echo; echo %s; echo; read -rsn1 -p %s _' \
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

# pwsh_invocation <command> [no-exit] [no-pwsh]
# Builds the pwsh invocation the bindings send. Without the second argument
# pwsh runs the command and exits with it; with it, pwsh stays interactive
# afterwards. An empty command opens a plain interactive pwsh -- that is what
# the prefix+% and prefix+" terminal splits want. The third leaves pwsh out:
# the command is run by the pane's bash as it is. An ssh session runs the same
# call on the remote (see ssh-helpers.sh).
#
# A pwsh that runs the command and exits gets PWSH_LEAN=1: the profile then
# skips its prompt-only parts (PSReadLine, completers, oh-my-posh) but keeps the
# environment, ssh-agent and code-scripts the tool needs. The interactive ones
# -- the empty command and no-exit -- keep the full profile.
#
# Either way the pane closes when pwsh does: new_pane sees to that.
pwsh_invocation() {
  local command=$1 no_exit=${2:-} no_pwsh=${3:-}
  if [ -n "$no_pwsh" ]; then
    printf '%s' "$command"
  elif [ -z "$command" ]; then
    printf 'pwsh'
  elif [ -n "$no_exit" ]; then
    printf 'pwsh -NoExit -Command "%s"' "$command"
  else
    printf 'PWSH_LEAN=1 pwsh -Command "%s"' "$command"
  fi
}

# pane_command <pane> <command> [no-exit] [no-pwsh]
# What a new pane split off <pane> should run: pwsh_invocation, or the same thing
# over ssh when <pane> belongs to a session opened with prefix+N. Every
# pane-creating script builds its command through here, which is what lets the
# bindings in common.conf stay unaware of ssh sessions.
pane_command() {
  if [ -n "$(ssh_option "$1" @ssh_target)" ]; then
    ssh_command "$@"
  else
    pwsh_invocation "${@:2}"
  fi
}

# closing_line <command>
# The line to type into a pane's shell so the pane runs <command> and then
# closes, whatever way <command> ends: success, failure, or a Ctrl-C.
#
# The shell execs a bash that runs <command>, so no interactive shell is left
# for the pane to fall back to -- when <command> is over, the pane's process is
# gone and tmux closes it. This used to be `<command> && exit`, which left a
# bare shell behind on any failure, and on a cancel: an interactive bash drops
# the rest of the line when a job dies of SIGINT, so not even `; exit` would
# have run. A lone command, like the plain pwsh calls, is exec'd by that bash in
# turn, so there is no extra process between the pane and pwsh.
closing_line() {
  printf 'exec bash -c %s' "$(sq "$1")"
}

# new_pane <target> <label> <command> [split-window args...]
# Splits <target>'s window, labels the new pane, starts <command> in it and
# prints the new pane id. The pane closes when <command> ends (closing_line).
#
# The command is typed into the pane with send-keys rather than handed to
# split-window as its shell-command so it starts from the user's interactive
# shell, with everything that shell's profile puts in the environment.
new_pane() {
  local target=$1 label=$2 command=$3
  shift 3
  local pane
  pane="$(tmux split-window -t "$target" -c '#{pane_current_path}' -P -F '#{pane_id}' "$@")"
  label_pane "$pane" "$label"
  tmux send-keys -t "$pane" "$(closing_line "$command")" C-m
  printf '%s' "$pane"
}

# --- Pane kinds ----------------------------------------------------------------
# What the picker pane of the default layout offers (Select-PaneKind.sh), in
# the order it lists them: the first is what Enter picks straight away.
PANE_KINDS=("NeoVim" "Terminal" "Claude Code" "Copilot" "Codex" "Open Code")

# pane_kind <pane> <kind>
# Sets kind_command, kind_no_exit and kind_no_pwsh to what a pane of <kind> runs, ready for
# pane_command. The one place these commands are spelled for the layout
# (Set-NeovimLayout.sh), the picker, prefix+e and prefix+E -- the prefix+t bindings in
# common.conf use the same strings.
#
# A remote without this dev-environment has no pwsh profile and no ~/.modules,
# so NeoVim is plain nvim there and the terminal a plain login shell.
pane_kind() {
  local pane=$1 kind=$2 bare=""
  if [ -n "$(ssh_option "$pane" @ssh_target)" ] && ! ssh_is_devenv "$pane"; then
    bare="yes"
  fi
  kind_no_exit=""
  kind_no_pwsh=""
  case "$kind" in
    NeoVim)
      # No no-exit: quitting NeoVim closes its pane, as quitting an agent does,
      # instead of leaving a pwsh prompt where the editor was.
      if [ -n "$bare" ]; then
        kind_command="nvim"
      else
        # Node for the LSP servers and Copilot (Use-NodeVersion, DevHelpers.psm1).
        kind_command='Use-NodeVersion && ~/.modules/neovim-lsp/Install-LanguageServerNodePackages.ps1 && nvim'
      fi
      ;;
    "NeoVim (NORC)")
      # prefix+E: NeoVim without the vimrc or plugins, so no LSP packages to
      # install first, and run straight from bash -- no pwsh to start or
      # profile to load. Not in PANE_KINDS -- the picker does not offer it.
      kind_command="nvim -u NORC"
      kind_no_pwsh="no-pwsh"
      ;;
    Notes)
      # prefix+t, n and the layout's notes feed (Set-NeovimLayout.sh): NeoVim
      # on the repository's .notes, with the notes profile (vim/notes.vimrc) --
      # bare but for tmux navigation and a transparent background -- or, on an
      # ssh host without the modules, NORC. The root is found where the
      # command runs, so the same string serves a local pane and a remote one.
      # Not in PANE_KINDS either.
      local profile="~/.local/share/nvim/site/notes.vimrc"
      [ -n "$bare" ] && profile="NORC"
      kind_command="nvim -u $profile \"\$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.notes\""
      kind_no_pwsh="no-pwsh"
      ;;
    Terminal)
      # Refresh git state, load the fzf helpers and build the project if it
      # needs it, then leave the shell open.
      kind_no_exit="no-exit"
      if [ -n "$bare" ]; then
        kind_command=""
      else
        kind_command='psgit && psfzf && Build-DotnetProjectIfNeeded'
      fi
      ;;
    "Claude Code") kind_command="claude" ;;
    Copilot)
      # The Copilot CLI is a node package.
      if [ -n "$bare" ]; then
        kind_command="copilot --max-ai-credits 500"
      else
        kind_command="Use-NodeVersion && copilot --max-ai-credits 500"
      fi
      ;;
    Codex) kind_command="codex" ;;
    "Open Code") kind_command="nvs use latest && opencode" ;;
    *) return 1 ;;
  esac
}

# has_notes <pane>
# Whether the project of <pane>'s session keeps notes: a .notes file at the root
# of the repository the session was opened on (or in that directory, outside a
# repository). Exits 0 for yes, 1 for no and 2 when an ssh session's host could
# not be asked -- a caller should then leave things as they are.
has_notes() {
  local pane=$1 dir root status=0
  if [ -n "$(ssh_option "$pane" @ssh_target)" ]; then
    remote_has_notes "$pane" || status=$?
    case "$status" in
      0) return 0 ;;
      255) return 2 ;;
      *) return 1 ;;
    esac
  fi
  dir="$(tmux display-message -p -t "$pane" '#{session_path}')"
  root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$dir")"
  [ -f "$root/.notes" ]
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
