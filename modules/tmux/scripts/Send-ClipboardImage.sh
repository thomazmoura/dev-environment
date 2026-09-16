#!/usr/bin/env bash
# Pastes the image on this machine's clipboard into an ssh session's pane.
#
# Usage: Send-ClipboardImage.sh <pane_id>
#   Bound to C-v in ssh sessions (prefix+N) in modules/tmux/common.conf.
#
# Claude Code takes an image with Ctrl+V by reading the clipboard itself, with
# wl-paste or xclip. In an ssh session it runs on the remote, which has no
# clipboard to read, and a terminal has no way to carry image bytes. So the
# image goes over ssh instead, through the session's master connection (see
# SSH_OPTS in ssh-helpers.sh), into ~/.cache/claude-paste on the remote, and
# its path is pasted into the pane. Claude Code attaches a pasted image path
# as the image.
#
# Without an image on the clipboard the pane gets its C-v as usual: vim's
# visual block, a shell's quoted insert, Claude's own text paste.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

pane=${1:?pane id required}

pass_through() { tmux send-keys -t "$pane" C-v; exit 0; }

# The tmux server may have been started without the Wayland variables; wl-paste
# assumes wayland-0 then too, but says so on stderr.
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"

target="$(ssh_option "$pane" @ssh_target)"
[ -n "$target" ] || pass_through
command -v wl-paste >/dev/null || pass_through

types="$(wl-paste --list-types 2>/dev/null)" || pass_through
if grep -qx 'image/png' <<<"$types"; then
  type=image/png
else
  type="$(grep -m1 '^image/' <<<"$types")" || pass_through
fi
ext="${type#image/}"
ext="${ext%%[;+]*}"
name="$(date +%Y%m%d-%H%M%S)-$RANDOM.$ext"

# Run under sh, as the login shell may be anything. Pastes older than a day
# are cleared on the way in. Prints the absolute path of the file it wrote.
upload='
dir="$HOME/.cache/claude-paste"
mkdir -p "$dir" && cd "$dir" || exit 1
find . -type f -mmin +1440 -delete 2>/dev/null
cat > "$1" && printf "%s/%s" "$dir" "$1"'

path="$(wl-paste --no-newline --type "$type" |
  ssh "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$target" \
    "sh -c $(sq "$upload") _ $(sq "$name")")"
[ -n "$path" ] || warn "Could not send the clipboard image to $target"

# A bracketed paste (-p), so the pane takes it as pasted text and not as typing.
tmux set-buffer -b clipboard-image -- "$path"
tmux paste-buffer -p -d -b clipboard-image -t "$pane"
