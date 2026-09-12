#!/usr/bin/env bash
# Opens an ssh session: a tmux session in which every pane is a shell on a
# remote host, in one working directory there.
#
# Bound to prefix+N as a popup command in modules/tmux/common.conf -- the remote
# counterpart of prefix+C-n (New-CodeSession.sh). It:
#
#   1. asks for user@host (up-arrow recalls the ones used before, kept in
#      ~/.ssh-session-history) and connects, in the popup, so a host key or
#      password prompt has a terminal to answer in;
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

require_tools ssh tmux fzf

# read -e takes its up-arrow history from the shell's history list, which a
# script has to load by hand. Only loaded -- `set -o history` would also have
# the list record this script's own lines, and up-arrow offer those.
history_file="$HOME/.ssh-session-history"
[ -f "$history_file" ] && history -r "$history_file"

printf 'New ssh session\n\n'
read -rep 'user@host: ' target || exit 0
# Trim surrounding whitespace; an empty answer is a change of mind.
target="$(printf '%s' "$target" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
[ -n "$target" ] || exit 0

# The ControlPath sockets live in ~/.ssh (SSH_OPTS), which a fresh machine may
# not have yet.
mkdir -p -m 700 "$HOME/.ssh"

# Connecting on its own first, and with the terminal attached, is what makes
# this the connection that authenticates: it becomes the ControlMaster every
# later ssh to this host goes through (see SSH_OPTS). The listing below has its
# output in a pipe, which is no place for a password prompt.
printf '\nConnecting to %s...\n' "$target"
ssh "${SSH_OPTS[@]}" -o ConnectTimeout=10 "$target" true || die "Could not connect to $target"

# Only a host that connected goes into the history: a typo should not be the
# first thing up-arrow offers next time. Moved to the end if it was already
# there, so the history stays one line per host, most recent last.
{ grep -vxF -- "$target" "$history_file" 2>/dev/null; printf '%s\n' "$target"; } > "$history_file.tmp" &&
  mv "$history_file.tmp" "$history_file"

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

# The list streams into fzf rather than being collected first, so a big tree on
# a slow link is searchable while it is still arriving. The two header lines
# are read off the pipe before fzf gets the rest of it.
#
# fzf leaving before ssh has finished sends ssh a SIGPIPE, and pipefail makes
# that the pipeline's status -- so the answer is judged by whether a line came
# out, not by the exit code.
answer="$(ssh "${SSH_OPTS[@]}" "$target" "sh -c $(sq "$listing")" | {
  IFS= read -r root || exit 1
  IFS= read -r kind || exit 1
  picked="$(sed -u 's|^\./||' | fzf --reverse --prompt='remote> ' --header="New ssh session on $target:$root")" || exit 1
  printf '%s\t%s\t%s' "$root" "$kind" "$picked"
})"
[ -n "$answer" ] || exit 0
IFS=$'\t' read -r root kind picked <<<"$answer"
[ -n "$picked" ] || exit 0
dir="$root/${picked%/}"

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
