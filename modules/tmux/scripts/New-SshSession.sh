#!/usr/bin/env bash
# Opens an ssh session: a tmux session in which every pane is a shell on a
# remote host, in one working directory there.
#
# Bound to prefix+N as a popup command in modules/tmux/common.conf -- the remote
# counterpart of prefix+C-n (New-CodeSession.sh). It:
#
#   1. asks for user@host (up-arrow recalls the ones used before, kept in
#      ~/.ssh-session-history) and connects, in the popup, so a host key or
#      password prompt has a terminal to answer in. When every open ssh session
#      is on one host, it goes there without asking, from any session; leaving
#      the directory picker of step 2 then asks after all;
#   2. fuzzy-finds a directory under ~/code on the remote -- ~ when the remote
#      has no ~/code -- the way prefix+C-n does locally;
#   3. on a remote with this dev-environment, unlocks the remote's ssh key in
#      the host's shared agent -- asking for its password here, once, instead
#      of in every pane (see ssh-helpers.sh);
#   4. creates a session named <host>-<directory>, records the host and the
#      directory on it (see ssh-helpers.sh), switches to it and applies the
#      standard layout, every pane of which runs over ssh.
#
# From then on every pane binding -- prefix+a, %, ", v, the prefix+t agents --
# opens a new ssh into that directory and runs its usual command there, through
# pane_command in tmux-helpers.sh.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

require_tools ssh timeout tmux fzf

history_file="$HOME/.ssh-session-history"

# The ControlPath sockets live in ~/.ssh (SSH_OPTS), which a fresh machine may
# not have yet.
mkdir -p -m 700 "$HOME/.ssh"

# ask_target
# Asks for user@host into $target. Fails when the answer is empty or the
# question is left.
ask_target() {
  # read -e takes its up-arrow history from the shell's history list, which a
  # script has to load by hand. Only loaded -- `set -o history` would also have
  # the list record this script's own lines, and up-arrow offer those.
  [ -f "$history_file" ] && history -r "$history_file"

  printf 'New ssh session\n\n'
  read -rep 'user@host: ' target || return 1
  # Trim surrounding whitespace; an empty answer is a change of mind.
  target="$(printf '%s' "$target" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [ -n "$target" ]
}

# wait_cancellable <pid>
# Waits for the background process <pid>, killing it when Esc or Ctrl+C is
# pressed in the popup. Returns its exit status, or 130 when it was cancelled.
#
# Esc is read off the terminal; Ctrl+C comes as a SIGINT, which is trapped
# rather than left to take this script down and the ssh running behind it.
# (read -n turns the terminal's signal keys back on for itself, so Ctrl+C
# cannot be read as a byte instead.) The SIGINT reaches only this script:
# timeout runs its command in a process group of its own.
wait_cancellable() {
  local pid=$1 key cancelled=
  [ -t 0 ] || { wait "$pid"; return; }
  trap 'cancelled=1' INT
  while [ -z "$cancelled" ] && kill -0 "$pid" 2>/dev/null; do
    IFS= read -rsn1 -t 0.2 key && [ "$key" = $'\e' ] && cancelled=1
  done
  trap - INT
  if [ -n "$cancelled" ]; then
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    return 130
  fi
  wait "$pid"
}

# connect
# Connects to $target. Fails when cancelled; any other failure ends the script.
#
# Connecting on its own first is what makes this the connection that
# authenticates: it becomes the ControlMaster every later ssh to this host goes
# through (see SSH_OPTS). The listing below has its output in a pipe, which is
# no place for a password prompt.
#
# It is tried first without a terminal (BatchMode), in the background, so that
# it can be given up on: at Esc or Ctrl+C, or after connect_timeout seconds.
# ConnectTimeout is not enough on its own. It bounds opening a connection, and
# when a master for this host is already up -- a session on it is open, or
# ControlPersist is keeping one -- the ssh goes through that master and opens
# none; a master whose network went away takes the request and never answers.
# Such a master is dropped on a timeout, so that trying again connects anew.
#
# Only when the batch try is turned away -- a password or a host key to
# confirm is needed -- does the ssh run again with the terminal, where it can
# ask. That one has no timeout, since it may be waiting on you, but by then the
# host has answered; Ctrl+C still ends it, as it does any password prompt.
connect_timeout=20
connect() {
  printf '\nConnecting to %s... (Esc or Ctrl+C to cancel)\n' "$target"
  timeout "$connect_timeout" ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=10 "$target" true \
    </dev/null 2>/dev/null &
  wait_cancellable $!
  case $? in
    0) ;;
    130) return 1 ;;
    124)
      ssh "${SSH_OPTS[@]}" -O exit "$target" 2>/dev/null &&
        die "No answer from $target in ${connect_timeout}s; its stale connection was closed, try again"
      die "No answer from $target in ${connect_timeout}s" ;;
    *)
      ssh "${SSH_OPTS[@]}" -o ConnectTimeout=10 "$target" true || die "Could not connect to $target" ;;
  esac

  # Only a host that connected goes into the history: a typo should not be the
  # first thing up-arrow offers next time. Moved to the end if it was already
  # there, so the history stays one line per host, most recent last.
  { grep -vxF -- "$target" "$history_file" 2>/dev/null; printf '%s\n' "$target"; } > "$history_file.tmp" &&
    mv "$history_file.tmp" "$history_file"
}

# One round trip for everything the picker needs, run under sh because the
# login shell may be anything. The first line is the root the list is relative
# to, the second whether the remote has this dev-environment (the same check
# ssh_is_devenv relies on later), and the rest the directories. fd -- or
# Debian's fdfind -- when there is one, so .gitignore is honoured as it is by
# prefix+C-n; otherwise find, skipping hidden folders and build output.
listing='
root="$HOME/code"
[ -d "$root" ] || root="$HOME"
cd "$root" || exit 1
pwd
if command -v pwsh >/dev/null 2>&1 && [ -d "$HOME/.modules" ]; then echo devenv; else echo plain; fi
if command -v fd >/dev/null 2>&1; then fd --type d --follow .
elif command -v fdfind >/dev/null 2>&1; then fdfind --type d --follow .
else find . -mindepth 1 \( -name ".*" -o -name node_modules -o -name bin -o -name obj \) -prune -o -type d -print
fi'

# pick [header note]
# Fuzzy-finds a directory on $target into $dir, and whether the remote has this
# dev-environment into $kind. Fails when nothing was picked.
#
# The list streams into fzf rather than being collected first, so a big tree on
# a slow link is searchable while it is still arriving. The two header lines
# are read off the pipe before fzf gets the rest of it.
#
# fzf leaving before ssh has finished sends ssh a SIGPIPE, and pipefail makes
# that the pipeline's status -- so the answer is judged by whether a line came
# out, not by the exit code.
pick() {
  local note="${1:-}" answer root picked
  answer="$(ssh "${SSH_OPTS[@]}" "$target" "sh -c $(sq "$listing")" | {
    IFS= read -r root || exit 1
    IFS= read -r kind || exit 1
    picked="$(sed -u 's|^\./||' | fzf --reverse --prompt='remote> ' --header="New ssh session on $target:$root$note")" || exit 1
    printf '%s\t%s\t%s' "$root" "$kind" "$picked"
  })"
  [ -n "$answer" ] || return 1
  IFS=$'\t' read -r root kind picked <<<"$answer"
  [ -n "$picked" ] || return 1
  dir="$root/${picked%/}"
}

# The host of the open ssh sessions, when they are all on one, is tried without
# asking; several hosts are not guessed between. Leaving it -- the connection or
# the picker -- asks for a host after all.
hosts="$(tmux list-sessions -F '#{@ssh_target}' 2>/dev/null | sed '/^$/d' | sort -u)"
target=
[ -n "$hosts" ] && [ "$(wc -l <<<"$hosts")" -eq 1 ] && target="$hosts"
if [ -n "$target" ]; then
  printf 'New ssh session on %s\n' "$target"
  connect && pick ' (Esc for another host)' || { clear; target=; }
fi
if [ -z "$target" ]; then
  ask_target && connect && pick || exit 0
fi

# <host>-<directory>. The user part is left out: it is the same on every
# session you open. Dots and colons are the separators in tmux targets
# (session:window.pane), so a host like dev.example.com becomes dev_example_com.
host="${target##*@}"
name="$(printf '%s-%s' "$host" "$(basename "$dir")" | tr '.:' '__')"

# The remote's key, unlocked here once so that no pane has to ask for it (see
# the shared agent in ssh-helpers.sh). Only on a dev-environment remote: that is
# where the panes' profile would otherwise ask. Asked before the check below so
# that prefix+N on an open directory is also the way to unlock the key again
# once it has expired; when the agent still holds it, nothing is asked.
#
# A password that was never given is not a reason to stop: each pane checks
# the agent before it connects (Unlock-RemoteKey.sh) and asks for it then.
if [ "$kind" = devenv ]; then
  printf '\n'
  if ! remote_agent_unlock "$target"; then
    printf '\nThe key was not unlocked; the panes will ask for it.\n'
    read -rsn1 -p "Press any key to continue..." _
  fi
fi

# Recorded once there is a session for the host, not before: the
# session-closed hook kills the agent of any recorded host without one, and a
# session closing elsewhere in between must not take this agent with it.
record_agent() {
  [ "$kind" = devenv ] && add_agent_target "$target"
  return 0
}

# Re-running prefix+N for a directory that is already open takes you there, as
# prefix+C-n does. A session with the same name for somewhere else -- a local
# one, or the same folder name elsewhere on that host -- is not ours to reuse.
if tmux has-session -t "=$name" 2>/dev/null; then
  if [ "$(ssh_option "=$name:" @ssh_target)" != "$target" ] ||
     [ "$(ssh_option "=$name:" @ssh_dir)" != "$dir" ]; then
    die "A session called $name is already open for something else"
  fi
  record_agent
  tmux switch-client -t "=$name"
  exit 0
fi

# The session starts in the local home: its panes live on the remote, and the
# local path is only where the ssh commands are typed from. The options go on
# before the layout, which is what reads them.
tmux new-session -s "$name" -d -c "$HOME" || die "Could not create session $name"
tmux set-option -t "=$name:" @ssh_target "$target"
tmux set-option -t "=$name:" @ssh_dir "$dir"
tmux set-option -t "=$name:" @ssh_devenv "$([ "$kind" = devenv ] && echo yes || echo no)"
record_agent

tmux switch-client -t "=$name"
"$scripts/Set-NeovimLayout.sh" "$name:"
exit 0
