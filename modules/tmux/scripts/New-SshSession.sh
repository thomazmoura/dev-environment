#!/usr/bin/env bash
# Opens an ssh session: a tmux session in which every pane is a shell on a
# remote host, in one working directory there.
#
# Bound to prefix+N as a popup command in modules/tmux/common.conf -- the remote
# counterpart of prefix+/ (New-CodeSession.sh). It:
#
#   1. asks for user@host (up-arrow recalls the ones used before, kept in
#      ~/.ssh-session-history) and connects, in the popup, so a host key or
#      password prompt has a terminal to answer in. When every open ssh session
#      is on one host, it goes there without asking, from any session; leaving
#      the directory picker of step 2 then asks after all;
#   2. fuzzy-finds a directory in the remote's code folder -- ~ when the
#      remote has none -- the way prefix+/ does locally, the sessions on that
#      host named with prefix+$ first (Set-SessionLabel.sh -l);
#   3. on a remote with this dev-environment, unlocks the remote's ssh key in
#      the host's shared agent -- asking for its password here, once, instead
#      of in every pane (see ssh-helpers.sh);
#   On a host that can be linked -- one with this dev-environment in a version
#   that has tmux_link.py -- it stops being an ssh session here: the two
#   machines are linked (link_make in link-helpers.sh), the session is opened in
#   *that machine's* tmux and the client is moved to it (open_on_peer). The rest
#   of this list is what happens on every other host, and in a container.
#
#   4. creates a session named <host>-<directory> -- user@<host>-<directory>
#      while another user has a session on that host, the open ones renamed to
#      match (Rename-SshSessions.sh) -- records the host and the directory on
#      it (see ssh-helpers.sh), gives it the ssh theme colour
#      (Set-SshTheme.sh), switches to it and applies the standard layout, every
#      pane of which runs over ssh -- all but the feeds and the picker, which
#      run here and hand what is picked to the remote.
#
# From then on every pane binding -- prefix+a, %, ", v, the prefix+t agents --
# opens a new ssh into that directory and runs its usual command there, through
# pane_command in tmux-helpers.sh.
#
# Usage: New-SshSession.sh [-D] [-a | -t user@host -d /remote/dir [-n session name]]
#   no options  ask both questions, as prefix+N does
#   -a          ask for user@host even when every open ssh session is on one
#               host, as prefix+C-n does: a session on another machine
#   -D          the same, into a local Docker container instead of a host, as
#               prefix+D does: the first question picks one of the containers
#               (`docker ps -a`), starting it when it is stopped, and the
#               session's target is docker:<container>. Invoke-Remote.sh (see
#               REMOTE_SSH in ssh-helpers.sh) makes that the only difference:
#               the panes, feeds and theme work as they do over ssh, the theme
#               in its own colour (Set-SshTheme.sh)
#   -t and -d   skip both and build the session for that host and directory.
#               How a worktree made on a remote opens its session
#               (Open-WorktreeSession.sh): the host and the directory are
#               already known, and only the half of this script below the
#               questions is wanted. -n overrides the <host>-<directory> name,
#               which a worktree spells its own way (session_name_for in
#               worktree-helpers.sh). vtmux (New-VerticalTmuxSession in
#               DevHelpers.psm1) also comes this way to open an ssh home
#               session again (Set-HomeSession.sh), from a terminal outside
#               tmux: there is no client then, so the session is made the
#               terminal's size and not switched to, and the password
#               prompts have that terminal to ask in.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"
source "$scripts/link-helpers.sh"

history_file="$HOME/.ssh-session-history"

target=""
dir=""
name_override=""
always_ask=""
docker=""
while getopts ":aDt:d:n:" option; do
  case "$option" in
    a) always_ask="yes" ;;
    D) docker="yes" ;;
    t) target="$OPTARG" ;;
    d) dir="$OPTARG" ;;
    n) name_override="$OPTARG" ;;
    *) die "New-SshSession.sh: unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

if [ -n "$dir$target" ] && { [ -z "$dir" ] || [ -z "$target" ]; }; then
  die "New-SshSession.sh: -t and -d go together"
fi

# fzf only for the path that picks a directory; the -t/-d path has one.
require_tools setsid tmux
if [ -n "$docker" ] || is_docker_target "$target"; then require_tools docker; else require_tools ssh; fi
[ -n "$dir" ] || require_tools fzf

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

# ask_container
# The Docker counterpart of ask_target: picks one of the containers into
# $target, as docker:<name>. Stopped ones are listed too -- connect starts them.
ask_container() {
  local picked
  picked="$(docker ps -a --format $'{{.Names}}\t{{.State}}\t{{.Image}}' |
    awk -F '\t' '{ printf "%-30s %-10s %s\n", $1, $2, $3 }' |
    fzf --reverse --prompt='container> ' --header='New docker session')" || return 1
  target="docker:${picked%% *}"
}

# Whether the remote has this dev-environment -- the check ssh_is_devenv relies
# on later, through @ssh_devenv.
devenv_test='if command -v pwsh >/dev/null 2>&1 && [ -d "$HOME/.modules" ]; then echo devenv; else echo plain; fi'

# The remote's code folder, under sh: code-folder.sh's rule written out again,
# since the remote may not have this dev-environment -- $CODE_FOLDER, else the
# first of ~/code, ~/git and /Git there, else ~ -- and cd'd into with -P for
# the real path, symlinks resolved. An ssh command's shell reads no profile, so
# $CODE_FOLDER is there only when sshd or the shell's rc file sets it; when it
# is not, the remote's tmux server is asked for its own (common.conf sets it
# from the profile it was started with) before guessing, since a stray ~/code
# left on a machine whose projects moved to /Git would otherwise win.
cd_code_folder='
root="${CODE_FOLDER:-}"
if [ -z "$root" ]; then
  root="$(tmux show-environment -g CODE_FOLDER 2>/dev/null)"
  case "$root" in CODE_FOLDER=*) root="${root#CODE_FOLDER=}" ;; *) root= ;; esac
fi
case "$root" in "~"*) root="$HOME${root#"~"}" ;; esac
for candidate in "$root" "$HOME/code" "$HOME/git" /Git "$HOME"; do
  [ -n "$candidate" ] && [ -d "$candidate" ] && break
done
cd -P "$candidate" || exit 1
'

# What connecting asks the remote, run under sh because the login shell may be
# anything: the root the picker lists -- the code folder, or ~ when the remote
# has none -- and whether the remote has this dev-environment. Two lines.
probe="$cd_code_folder"'
pwd -P
'"$devenv_test"

# connect
# Connects to $target, and reads the picker's root and the remote's kind off it
# into $root and $kind. Fails when cancelled; any other failure ends the script.
#
# Connecting on its own first is what makes this the connection that
# authenticates: it becomes the ControlMaster every later ssh to this host goes
# through (see SSH_OPTS). The listing below has its output in a pipe, which is
# no place for a password prompt.
#
# It is tried first without a terminal (BatchMode), under run_cancellable, so
# that it can be given up on: at Esc or Ctrl+C, or after connect_timeout
# seconds. ConnectTimeout is not enough on its own. It bounds opening a
# connection, and when a master for this host is already up -- a session on it
# is open, or ControlPersist is keeping one -- the ssh goes through that master
# and opens none; a master whose network went away takes the request and never
# answers. Such a master is dropped on a timeout, so that trying again connects
# anew.
#
# Only when the batch try is turned away -- a password or a host key to
# confirm is needed -- does an ssh run with the terminal, where it can ask. A
# host that could not be reached at all is not tried a second time: that ssh
# would sit on the terminal for as long again, deaf to Esc. The one that asks
# has no timeout, since it is waiting on you, but by then the host has
# answered; Ctrl+C ends it, as it does any password prompt. It asks here even
# where the desktop would rather ask in a window (SSH_ASKPASS_REQUIRE=prefer,
# as KDE sets it): that window opens on this machine's screen, which is not
# where a linked or ssh'd-in client is looking.
connect_timeout=20
unreachable='timed out|could not resolve|refused|no route to host|unreachable|connection (reset|closed)'
needs_you='permission denied|host key verification failed|authentication'
connect() {
  local out err status why try
  # What the batch try printed and why it failed, for the two connects a
  # script may make (the guessed host, then the one asked for).
  if [ -z "${connect_files:-}" ]; then
    connect_files="$(mktemp -d)" || die "Could not create a temporary directory"
    # shellcheck disable=SC2064
    trap "rm -rf $(sq "$connect_files")" EXIT
  fi
  out="$connect_files/out" err="$connect_files/err"

  # A container is local: nothing to authenticate, and no history --
  # ask_container lists what there is. Only starting it, when it is stopped.
  if is_docker_target "$target"; then
    local container="${target#docker:}"
    if [ "$(docker container inspect -f '{{.State.Running}}' "$container" 2>/dev/null)" != true ]; then
      printf '\nStarting %s...\n' "$container"
      docker start "$container" >/dev/null || die "Could not start $container"
    fi
    run_cancellable "$connect_timeout" "$out" "$err" "$REMOTE_SSH" "$target" "sh -c $(sq "$probe")"
    case $? in
      0) ;;
      130) return 1 ;;
      *) die "Could not run a command in $container" ;;
    esac
    read_probe "$out" || die "Could not run a command in $container"
    return 0
  fi

  printf '\nConnecting to %s... (Esc or Ctrl+C to cancel)\n' "$target"
  # Twice when ssh failed for a reason of its own (255) that is neither of the
  # two it names: a master that died under the first try -- its network was
  # already gone -- leaves the second to connect anew, still without the
  # terminal. LC_ALL=C: the reason is read off ssh's own words.
  for try in 1 2; do
    run_cancellable "$connect_timeout" "$out" "$err" env LC_ALL=C \
      "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=10 "$target" "sh -c $(sq "$probe")"
    status=$?
    [ "$status" -eq 255 ] || break
    grep -qiE "$unreachable|$needs_you" "$err" && break
  done
  case $status in
    0) ;;
    130) return 1 ;;
    124)
      run_cancellable 5 /dev/null /dev/null "$REMOTE_SSH" "${SSH_OPTS[@]}" -O exit "$target" &&
        die "No answer from $target in ${connect_timeout}s; its stale connection was closed, try again"
      die "No answer from $target in ${connect_timeout}s" ;;
    255)
      why="$(grep -v '^$' "$err" | tail -n 1)"
      if grep -qiE "$unreachable" "$err" && ! grep -qiE "$needs_you" "$err"; then
        die "Could not connect to $target${why:+: $why}"
      fi
      SSH_ASKPASS_REQUIRE=never "$REMOTE_SSH" "${SSH_OPTS[@]}" -o ConnectTimeout=10 "$target" true ||
        die "Could not connect to $target"
      # Over the connection just made, and as bounded as the first try.
      run_cancellable "$connect_timeout" "$out" "$err" \
        "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=10 "$target" "sh -c $(sq "$probe")"
      case $? in
        0) ;;
        130) return 1 ;;
        *) die "No answer from $target after signing in" ;;
      esac ;;
    *) die "Could not look at $target's folders" ;;
  esac
  read_probe "$out" || die "Could not look at $target's folders"

  # Only a host that connected goes into the history: a typo should not be the
  # first thing up-arrow offers next time. Moved to the end if it was already
  # there, so the history stays one line per host, most recent last.
  { grep -vxF -- "$target" "$history_file" 2>/dev/null; printf '%s\n' "$target"; } > "$history_file.tmp" &&
    mv "$history_file.tmp" "$history_file"
}

# read_probe <file>
# The two lines the probe printed, into $root and $kind. The last two: a
# remote's shell profile may have had something to say first.
read_probe() {
  { IFS= read -r root && IFS= read -r kind; } < <(tail -n 2 "$1")
  [ -n "${root:-}" ] && [ "${root#/}" != "$root" ] || return 1
  [ "$kind" = devenv ] || kind=plain
}

# The picker's directories, relative to the probe's root, run under sh like the
# probe. fd -- or Debian's fdfind -- when there is one, so .gitignore is
# honoured as it is by prefix+/; otherwise find, skipping hidden folders and
# build output.
listing="$cd_code_folder"'
if command -v fd >/dev/null 2>&1; then fd --type d --follow .
elif command -v fdfind >/dev/null 2>&1; then fdfind --type d --follow .
else find . -mindepth 1 \( -name ".*" -o -name node_modules -o -name bin -o -name obj \) -prune -o -type d -print
fi'

# What fills the picker, as a `bash -c` script: the named sessions on this
# host, then the listing. Arguments: Set-SessionLabel.sh, the target, the root,
# and the ssh command that lists.
feed='"$1" -l "$2" "$3"; shift 3; "$@" 2>/dev/null | sed -u "s|^\./||"'

# pick [header note]
# Fuzzy-finds a directory on $target, under the $root connect found, into $dir.
# Fails when nothing was picked.
#
# The list streams into fzf rather than being collected first, so a big tree on
# a slow link is searchable while it is still arriving. It comes from a session
# of its own (setsid), read through a descriptor rather than a pipeline: fzf is
# then the only thing waited for, on screen from the first moment and the one
# reading the keys, and whatever is still listing when it leaves -- or is stuck
# on a connection that went away -- is ended instead of waited for. In a
# pipeline the script would wait for that ssh too, with the picker gone and
# the keys going nowhere.
#
# The named sessions on this host go in ahead of the listing. Their lines carry
# the directory and the session name after tabs, which fzf does not show
# (--with-nth=1); picking one opens the session under that name (-n), so it is
# the one the label was given to. They are read here, not on the remote.
pick() {
  local note="${1:-}" picked feeder
  exec 3< <(exec setsid bash -c "$feed" feed "$scripts/Set-SessionLabel.sh" "$target" "$root" \
    "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes "$target" "sh -c $(sq "$listing")" </dev/null)
  feeder=$!
  picked="$(fzf --reverse --delimiter=$'\t' --with-nth=1 --prompt='remote> ' \
    --header="New session on $target:$root$note" <&3)"
  end_group "$feeder"
  exec 3<&-
  [ -n "$picked" ] || return 1
  case "$picked" in
    *$'\t'*) IFS=$'\t' read -r _ dir name_override <<<"$picked" ;;
    *) dir="$root/${picked%/}" ;;
  esac
}

# Handed a host and a directory (-t/-d), there is nothing to ask: connect --
# one round trip when the session it came from already holds the master, and
# the cancellable prompt-capable path when that master has gone -- which also
# says what kind of remote it is.
#
# Otherwise: the host of the open ssh sessions, when they are all on one, is
# tried without asking; several hosts are not guessed between. Leaving it --
# the connection or the picker -- asks for a host after all. -a skips the guess.
# With -D the same goes for containers: only the container sessions count
# towards the guess, and only the host ones without it.
if [ -n "$dir" ]; then
  connect || exit 0
else
  asked="yes"
  if [ -n "$docker" ]; then
    hosts="$(tmux list-sessions -F '#{@ssh_target}' 2>/dev/null | grep '^docker:' | sort -u)"
    ask=ask_container other="container"
  else
    # The linked machines count as hosts too: with one link and no ssh session
    # elsewhere, prefix+N goes straight to that machine's folders.
    hosts="$({ tmux list-sessions -F '#{@ssh_target}' 2>/dev/null | sed '/^$/d;/^docker:/d'
               "$link_cli" --format=peers 2>/dev/null | cut -f2; } | sort -u)"
    ask=ask_target other="host"
  fi
  target=
  [ -z "$always_ask" ] && [ -n "$hosts" ] && [ "$(wc -l <<<"$hosts")" -eq 1 ] && target="$hosts"
  if [ -n "$target" ]; then
    printf 'New session on %s\n' "$target"
    connect && pick " (Esc for another $other)" || { clear; target=; }
  fi
  if [ -z "$target" ]; then
    "$ask" && connect && pick || exit 0
  fi
fi

# <host>-<directory>, or <container>-<directory>. The user part is left out
# while it is the same on every session open on the host, and put in front once
# another user has one there (ssh_session_name in ssh-helpers.sh). Dots and
# colons are the separators in tmux targets (session:window.pane), so a host
# like dev.example.com becomes dev_example_com. A caller with a name of its own
# (-n) has already spelled it that way.
host="${target##*@}"
host="${host#docker:}"
base="${name_override:-$(printf '%s-%s' "$host" "$(basename "$dir")" | tr '.:' '__')}"
user="$(ssh_user "$target")"
name="$(ssh_session_name "$base" "$target" "$user")"

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

# A host that can be linked gets no ssh session: the session is opened in its
# own tmux and the client goes there. Asked only of what the questions above
# led to -- a worktree or a home session handed over with -t/-d is an ssh
# session already, and stays one -- and never of a container.
if [ -n "${asked:-}" ] && [ "$kind" = devenv ] && ! is_docker_target "$target"; then
  peer="$(link_probe "$target")"
  if [ -n "$peer" ]; then
    link_make "$peer" "$target"
    open_on_peer "$peer" "$target" "$dir"
    exit 0
  fi
fi

# Re-running prefix+N for a directory that is already open takes you there, as
# prefix+/ does. A session with the same name for somewhere else -- a local
# one, or the same folder name elsewhere on that host -- is not ours to reuse.
if tmux has-session -t "=$name" 2>/dev/null; then
  if [ "$(ssh_option "=$name:" @ssh_target)" != "$target" ] ||
     [ "$(ssh_option "=$name:" @ssh_dir)" != "$dir" ]; then
    die "A session called $name is already open for something else"
  fi
  [ -n "${TMUX:-}" ] && tmux switch-client -t "=$name"
  exit 0
fi

# The session starts in the local home: its panes live on the remote, and the
# local path is only where the ssh commands are typed from. The options go on
# before the layout, which is what reads them.
# Outside tmux (vtmux) the new session takes the terminal's size, so the
# layout's percentage splits land where they will be once it is attached,
# rather than being scaled up from tmux's default 80x24.
size=()
[ -z "${TMUX:-}" ] && [ -t 1 ] && size=(-x "$(tput cols)" -y "$(tput lines)")
tmux new-session -s "$name" -d -c "$HOME" "${size[@]}" || die "Could not create session $name"
tmux set-option -t "=$name:" @ssh_target "$target"
tmux set-option -t "=$name:" @ssh_dir "$dir"
tmux set-option -t "=$name:" @ssh_devenv "$([ "$kind" = devenv ] && echo yes || echo no)"
tmux set-option -t "=$name:" @ssh_name "$base"
[ -n "$user" ] && tmux set-option -t "=$name:" @ssh_user "$user"

# The first session of a second user on this host: the first user's sessions
# take their user in front too.
"$scripts/Rename-SshSessions.sh"

# Themed before the switch rather than left to the client-session-changed hook,
# which runs in the background and would show the local colours first.
"$scripts/Set-SshTheme.sh" "$name"

# The remote learns this client's terminal before the layout starts its panes,
# whose image previews read it (Sync-SshClientTerminal.sh). Outside tmux there
# is no client yet: the client-attached hook does it when one arrives.
if [ -n "${TMUX:-}" ]; then
  "$scripts/Sync-SshClientTerminal.sh" "$(tmux display-message -p '#{client_tty}')" "=$name:"
fi

[ -n "${TMUX:-}" ] && tmux switch-client -t "=$name"
"$scripts/Set-NeovimLayout.sh" -n "$name:"
exit 0
