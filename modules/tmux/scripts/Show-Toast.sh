#!/usr/bin/env bash
# Animated toasts in the tmux status line, a small noice.nvim for tmux.
#
#   Show-Toast.sh [-l level] [-t seconds] [-i id] message...
#   Show-Toast.sh --dismiss [id]        # every toast, or just that one
#
#   level    waiting | done | error | info (default). Sets the emoji and colour.
#   seconds  how long it stays, 1 to 20 (default 10). Every toast times out:
#            a toast is a nudge, not a to-do list -- agent-radar's own status
#            segment is what keeps track of who is still waiting.
#   id       a toast with the same id replaces the old one instead of stacking,
#            so agent-radar passes the pane id and an agent never shows twice.
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
max_seconds=20

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

# One toast as a status-line segment. The spinner and the background, which
# alternates between two shades of the level's colour, are what catch the eye:
# the text alone is easy to miss in a status line that already changes every
# second.
render() {
  local level="$1" text="$2" frame="$3" emoji bright dim bg
  local spinner=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  case "$level" in
    waiting) emoji="🔔" bright="#db4b4b" dim="#7a2230" ;;
    done)    emoji="✅" bright="#41a146" dim="#1f5b27" ;;
    error)   emoji="🔥" bright="#d9730d" dim="#7a3f06" ;;
    *)       emoji="💬" bright="#3d59a1" dim="#243663" ;;
  esac
  bg="$bright"
  (( frame / 3 % 2 )) && bg="$dim"
  printf '#[fg=#ffffff,bg=%s,bold] %s %s %s #[default] ' \
    "$bg" "${spinner[frame % ${#spinner[@]}]}" "$emoji" "$text"
}

# Draws until no toast is left. Newest first: the toast that just arrived is
# the one you have not seen.
animate() {
  local frame=0 file expiry level text segment files
  while :; do
    segment=""
    mapfile -t files < <(ls -t "$dir" 2>/dev/null)
    for file in "${files[@]}"; do
      { read -r expiry level; IFS= read -r text; } < "$dir/$file" 2>/dev/null || continue
      if (( expiry <= EPOCHSECONDS )); then
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

[[ "$seconds" =~ ^[0-9]+$ ]] || seconds=10
(( seconds < 1 )) && seconds=1
(( seconds > max_seconds )) && seconds=$max_seconds
expiry=$((EPOCHSECONDS + seconds))

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
