#!/usr/bin/env bash
# Pastes the image on the clipboard of the device in front into a pane that
# cannot read that clipboard itself.
#
# Usage: Send-ClipboardImage.sh <pane_id> [<client_pid>]
#   Bound to C-v in modules/tmux/common.conf, with the pid of the client that
#   pressed it.
#
# Claude Code takes an image with Ctrl+V by reading the clipboard itself, with
# wl-paste or xclip. It reads the clipboard of the machine it runs on, which is
# not the one the screenshot is on when:
#
#   - the pane is an ssh session's (prefix+n, @ssh_target): it runs on the
#     remote, which has no clipboard of the user's;
#   - the client is a linked machine's (Connect-Tmux.sh): the terminal, and the
#     screenshot, are on that machine, and this tmux only shows there.
#
# A terminal has no way to carry image bytes, so the image goes over ssh
# instead -- read from the linked machine's clipboard, written to the remote's
# ~/.cache/claude-paste, both through the master connections that are already
# open (SSH_OPTS in ssh-helpers.sh) -- and its path is pasted into the pane.
# Claude Code attaches a pasted image path as the image.
#
# Without an image on that clipboard, or when the pane can read it itself
# (both here), the pane gets its C-v as usual: vim's visual block, a shell's
# quoted insert, Claude's own text paste.
set -uo pipefail

scripts="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$scripts/tmux-helpers.sh"

pane=${1:?pane id required}
client_pid=${2:-}

pass_through() { tmux send-keys -t "$pane" C-v; exit 0; }

# linked_peer <client_pid>
# The address of the linked machine the client came from, or nothing for a
# client of this machine's (or of a device that is not a peer: the phone). The
# loop on that machine named the client TMUX_LINK_CLIENT=<hostname>-<pid>-<n>
# (Connect-Tmux.sh), and the peers know that machine as
# <user>@<lowercased hostname>, at the address aliases or peers give.
linked_peer() {
  local pid=$1 id host me file found
  [ -n "$pid" ] && [ -r "/proc/$pid/environ" ] || return 0
  id="$(tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | sed -n 's/^TMUX_LINK_CLIENT=//p' | head -n 1)"
  [ -n "$id" ] || return 0
  host="${id%-*}"
  host="${host%-*}"
  host="$(tr '[:upper:]' '[:lower:]' <<<"$host")"
  me="$(hostname | cut -d. -f1 | tr '[:upper:]' '[:lower:]')"
  [ -n "$host" ] && [ "$host" != "$me" ] || return 0
  for file in "${XDG_CONFIG_HOME:-$HOME/.config}/tmux-link/aliases" "${XDG_CONFIG_HOME:-$HOME/.config}/tmux-link/peers"; do
    [ -f "$file" ] || continue
    found="$(awk -F '\t' -v host="$host" '{ h = $1; sub(/^.*@/, "", h) } h == host && $2 != "" { print $2; exit }' "$file")"
    [ -n "$found" ] && { printf '%s\n' "$found"; return 0; }
  done
  return 0
}

target="$(ssh_option "$pane" @ssh_target)"
source_host="$(linked_peer "$client_pid")"
[ -n "$target$source_host" ] || pass_through

# wl-paste on the machine the clipboard is on, under sh as the login shell may
# be anything. The tmux server, and an ssh login, may have been started
# without the session's variables: wl-paste needs both to find the compositor.
paste_env='export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"; command -v wl-paste >/dev/null || exit 1; exec wl-paste "$@"'
clipboard() {
  if [ -n "$source_host" ]; then
    "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$source_host" \
      "sh -c $(sq "$paste_env") _$(printf ' %q' "$@")" </dev/null 2>/dev/null
  else
    sh -c "$paste_env" _ "$@" 2>/dev/null
  fi
}

types="$(clipboard --list-types)" || pass_through
if grep -qx 'image/png' <<<"$types"; then
  type=image/png
else
  type="$(grep -m1 '^image/' <<<"$types")" || pass_through
fi
ext="${type#image/}"
ext="${ext%%[;+]*}"
name="$(date +%Y%m%d-%H%M%S)-$RANDOM.$ext"

# Run under sh, on the machine the pane runs on. Pastes older than a day are
# cleared on the way in. Prints the absolute path of the file it wrote.
upload='
dir="$HOME/.cache/claude-paste"
mkdir -p "$dir" && cd "$dir" || exit 1
find . -type f -mmin +1440 -delete 2>/dev/null
cat > "$1" && printf "%s/%s" "$dir" "$1"'

if [ -n "$target" ]; then
  path="$(clipboard --no-newline --type "$type" |
    "$REMOTE_SSH" "${SSH_OPTS[@]}" -o BatchMode=yes -o ConnectTimeout=5 "$target" \
      "sh -c $(sq "$upload") _ $(sq "$name")")"
  where=$target
else
  path="$(clipboard --no-newline --type "$type" | sh -c "$upload" _ "$name")"
  where=$(hostname | cut -d. -f1)
  # An image that never came leaves an empty file: nothing to attach.
  if [ -n "$path" ] && [ ! -s "$path" ]; then
    rm -f "$path"
    path=""
  fi
fi
[ -n "$path" ] || warn "Could not send the clipboard image${source_host:+ of ${source_host##*@}} to $where"

# A bracketed paste (-p), so the pane takes it as pasted text and not as typing.
tmux set-buffer -b clipboard-image -- "$path"
tmux paste-buffer -p -d -b clipboard-image -t "$pane"
