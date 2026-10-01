#!/usr/bin/env bash
# Animated toasts in the tmux status line, a small noice.nvim for tmux.
#
#   Show-Toast.sh [-l level] [-t seconds] [-i id] message...
#   Show-Toast.sh --dismiss [id]        # every toast, or just that one
#
#   level    waiting | done | error | info (default). Sets the emoji and colour.
#   seconds  how long it stays; 0 keeps it until dismissed. Default 10, or 0
#            for waiting -- an agent blocked on you should not time out.
#   id       a toast with the same id replaces the old one instead of stacking,
#            so agent-radar passes the pane id and an agent never shows twice.
#
# Two tmux options choose the animation, each `on`, `off` or a list of levels:
#   @toast_spinner  a spinner before the emoji            default: on
#   @toast_pulse    the background blinks between two     default: waiting done
#                   shades of the level's colour
#
# prefix+Escape dismisses them all (common.conf). Several toasts show side by
# side, newest first, at the start of status-right (tmux.conf).
#
# Why not display-message: it can be animated by re-sending it, but every frame
# goes into the show-messages log (hundreds a minute, pushing out the real ones),
# and it has to choose between two bad key behaviours -- with -N tmux drops the
# keys typed while it is up, without -N any key blanks it until the next frame.
# A user option drawn by status-right has neither problem: setting it logs
# nothing and the keys go to the pane as usual.
#
# One animator process draws every toast. Each toast is a file under $dir, so
# any number of callers can add one without talking to each other; the animator
# holds a flock, and a caller that cannot take it knows one is already drawing
# and will pick the new file up on its next frame.
set -euo pipefail

dir="${XDG_RUNTIME_DIR:-/tmp}/tmux-toast-$(id -u)"
lock="$dir/.lock"
frame_delay=0.2
max_text=60

# Redraws every client's status line now rather than at the next
# status-interval, in one tmux call however many clients are attached. A tmux
# command run from a background process has no current client, so each one is
# named.
publish() {
  local client args=(set -g @toast "$1")
  while read -r client; do
    args+=(";" refresh-client -S -t "$client")
  done < <(tmux list-clients -F '#{client_name}' 2>/dev/null)
  tmux "${args[@]}" 2>/dev/null || true
}

# Whether an animation option ($1, its value) covers a level ($2): `on` for
# every level, `off` for none, otherwise a space-separated list of levels.
applies() {
  case " $1 " in
    " on "|*" $2 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# One toast as a status-line segment. The text alone is easy to miss in a
# status line that already changes every second, so something moves: the
# spinner, and for the toasts that mean "your turn" (waiting, done) the
# background too, which blinks between two shades of the level's colour.
render() {
  local level="$1" text="$2" frame="$3" emoji bright dim bg
  local spinner=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  case "$level" in
    waiting) emoji="🔔" bright="#db4b4b" dim="#7a2230" ;;
    done)    emoji="✅" bright="#41a146" dim="#1f5b27" ;;
    error)   emoji="🔥" bright="#d9730d" dim="#7a3f06" ;;
    *)       emoji="💬" bright="#3d59a1" dim="#243663" ;;
  esac
  bg="$bright" spin=""
  applies "$pulse" "$level" && (( frame / 3 % 2 )) && bg="$dim"
  applies "$spinner_levels" "$level" && spin="${spinner[frame % ${#spinner[@]}]} "
  printf '#[fg=#ffffff,bg=%s,bold] %s%s %s #[default] ' "$bg" "$spin" "$emoji" "$text"
}

# Draws until no toast is left. Newest first: the toast that just arrived is
# the one you have not seen.
animate() {
  local frame=0 file expiry level text segment files pulse spinner_levels
  # Read once rather than per frame, which would triple the tmux calls; a change
  # applies from the next animator, i.e. the next toast after these are gone.
  # Unset (empty) means the default.
  pulse="$(tmux show -gqv @toast_pulse 2>/dev/null || true)"
  spinner_levels="$(tmux show -gqv @toast_spinner 2>/dev/null || true)"
  pulse="${pulse:-waiting done}" spinner_levels="${spinner_levels:-on}"
  while :; do
    segment=""
    mapfile -t files < <(ls -t "$dir" 2>/dev/null)
    for file in "${files[@]}"; do
      { read -r expiry level; IFS= read -r text; } < "$dir/$file" 2>/dev/null || continue
      if (( expiry != 0 && expiry <= EPOCHSECONDS )); then
        rm -f -- "$dir/$file"
        continue
      fi
      segment+="$(render "$level" "$text" "$frame")"
    done
    [ -n "$segment" ] || return 0
    publish "$segment"
    frame=$((frame + 1))
    sleep "$frame_delay"
  done
}

# Takes the animator's lock and draws; returns at once if another process holds
# it. The recheck after unlocking closes the gap where a toast arrives between
# the last frame finding the directory empty and the lock being let go: its
# caller saw the lock taken and left, so this process has to draw it.
run_animator() {
  exec 9>"$lock"
  while flock -n 9; do
    animate
    publish ""
    flock -u 9
    [ -n "$(ls "$dir" 2>/dev/null)" ] || return 0
  done
}

mkdir -p -- "$dir"

if [ "${1:-}" = "--animate" ]; then
  run_animator
  exit 0
fi

if [ "${1:-}" = "--dismiss" ]; then
  if [ -n "${2:-}" ]; then
    rm -f -- "$dir/${2//\//_}"
  else
    rm -f -- "$dir"/*
  fi
  # A running animator clears the segment on its next frame. With none running
  # there is nothing to wait for, so the segment is cleared here.
  exec 9>"$lock"
  if flock -n 9; then publish ""; fi
  exit 0
fi

level=info seconds="" id=""
while getopts "l:t:i:" opt; do
  case "$opt" in
    l) level="$OPTARG" ;;
    t) seconds="$OPTARG" ;;
    i) id="$OPTARG" ;;
    *) echo "Usage: Show-Toast.sh [-l waiting|done|error|info] [-t seconds] [-i id] message" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
text="$*"
[ -n "$text" ] || { echo "Show-Toast.sh: no message" >&2; exit 2; }

[ -n "$seconds" ] || { [ "$level" = waiting ] && seconds=0 || seconds=10; }
expiry=0
(( seconds > 0 )) && expiry=$((EPOCHSECONDS + seconds))

# One line, no longer than a status segment can afford, and with `#` doubled so
# the status line prints it instead of reading it as the start of a style.
text="${text//$'\n'/ }"
(( ${#text} > max_text )) && text="${text:0:max_text-1}…"
text="${text//#/##}"

# The file name is the id, so the same id overwrites. Written whole and then
# renamed, so the animator never reads half a toast.
name="${id:-$EPOCHREALTIME.$$}"
name="${name//\//_}"
printf '%s %s\n%s\n' "$expiry" "$level" "$text" > "$dir/.$name.tmp"
mv -f -- "$dir/.$name.tmp" "$dir/$name"

# Detached, so the caller (a hook, a key binding, the agent-radar sampler)
# returns at once instead of waiting for the toast to expire.
setsid "$0" --animate </dev/null >/dev/null 2>&1 &
