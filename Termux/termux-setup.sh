#!/usr/bin/env bash
set -euo pipefail

# Termux side of the dev machine's Termux support: run this in Termux, on the phone.
#
# Opaque pane backgrounds: tmux and NeoVim on the dev machine stay transparent
# for Ghostty and WezTerm, and switch to opaque backgrounds (focused pane
# lighter, the rest darker) when the client attaching is Termux -- see
# modules/tmux/scripts/Set-PaneBackground.sh and
# modules/nvim-config/lua/config/pane_background.lua. Termux can't be told apart from the
# other side (same TERM as WezTerm, no TERM_PROGRAM over ssh), so it announces
# itself: ssh sends LC_TERMINAL=Termux, which the default `AcceptEnv LANG LC_*`
# of Ubuntu's and Debian's sshd lets through.
#
# The phone's clipboard: with Termux in front, NeoVim's "+ on the dev machine
# copies with termux-clipboard-set and pastes with termux-clipboard-get -- see
# modules/nvim-config/lua/config/termux_clipboard.lua. ssh forwards two Unix
# sockets back here (RemoteForward), and ~/.ssh/termux-clipboard-serve, which
# ssh starts on every connection (LocalCommand), answers them with socat. The
# dev machine's sshd needs LinuxDevEnv/sshd-setup.sh once.
#
# The phone's browser: a third socket, answered by the same script, hands each
# URL xray.nvim opens over there (paperboy's gb on an e-mail, gx on a link) to
# termux-open-url, so it opens here instead of only being copied. Name the PC
# too when you ssh into its tmux and on to the dev machine from there: the PC's
# bin/xray-open-listen (xray.nvim) hands the URLs on to the phone while Termux is
# in front of its tmux, through the same socket forwarded to the PC.
#
# Linked tmux servers: the dev machines each run their own tmux and list each
# other's sessions (prefix+N there; modules/tmux/scripts/tmux_link.py). Picking
# a session on another machine moves this terminal to it -- the ssh to the
# first machine ends and one to the second starts -- which only something
# running here can do: tmux-link, a copy of modules/tmux/scripts/Connect-Tmux.sh,
# is what to connect with instead of `ssh -t <host> tmux ...`. A machine is
# named by its user@hostname there; when the phone reaches it under another
# name, say so in ~/.config/tmux-link/aliases.
#
# Usage: termux-setup.sh [host...]
#   The hosts are the ones you ssh into, as you type them (aliases from
#   ~/.ssh/config or names). Without any, every host gets the flag and the
#   clipboard is left as it was: it is only for the hosts named, since git's
#   ssh to GitHub would otherwise ask for the forwards (and warn) on every push.
#
# What it does, idempotently -- running it again rewrites the same blocks:
#   - installs OpenSSH if Termux doesn't have it yet, and with hosts socat and
#     termux-api, the command-line half of the Termux:API app;
#   - with hosts, writes ~/.ssh/termux-clipboard-serve;
#   - keeps marked blocks at the END of ~/.ssh/config: the clipboard's (with
#     hosts) and the SetEnv line, last. At the end, because ssh takes the first
#     SetEnv, LocalCommand and PermitLocalCommand that match and ignores every
#     later one: a block of yours that already sets them keeps its values, and
#     the check below says where to add ours by hand.
#   - checks with `ssh -G` that each host really ends up with them;
#   - installs tmux-link from this checkout and creates the aliases file.

FLAG="LC_TERMINAL=Termux"
BEGIN_MARK="# >>> dev-environment: Termux pane backgrounds >>>"
END_MARK="# <<< dev-environment: Termux pane backgrounds <<<"
CLIP_BEGIN_MARK="# >>> dev-environment: Termux clipboard >>>"
CLIP_END_MARK="# <<< dev-environment: Termux clipboard <<<"
SSH_DIR="$HOME/.ssh"
CONFIG="$SSH_DIR/config"
SERVE="$SSH_DIR/termux-clipboard-serve"
SOCKET_DIR="${TMPDIR:-/tmp}"

if [ -z "${TERMUX_VERSION:-}" ] && [ -z "${PREFIX:-}" ]; then
  echo "Warning: this doesn't look like Termux; carrying on with $CONFIG anyway." >&2
fi

hosts=("$@")
pattern="${hosts[*]:-*}"

packages=()
command -v ssh >/dev/null 2>&1 || packages+=(openssh)
if [ "${#hosts[@]}" -gt 0 ]; then
  command -v socat >/dev/null 2>&1 || packages+=(socat)
  command -v termux-clipboard-get >/dev/null 2>&1 || packages+=(termux-api)
fi
if [ "${#packages[@]}" -gt 0 ]; then
  echo "Installing ${packages[*]}..."
  pkg install -y "${packages[@]}"
fi

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$CONFIG"
chmod 600 "$CONFIG"

if [ "${#hosts[@]}" -gt 0 ]; then
  # Without the Termux:API app the termux-api commands hang instead of failing
  if ! timeout 10 termux-clipboard-get >/dev/null 2>&1; then
    echo "Warning: termux-clipboard-get didn't answer. Install the Termux:API app" >&2
    echo "  (from where Termux came from: F-Droid or GitHub) and open it once." >&2
  fi

  cat > "$SERVE" <<EOF
#!$(command -v sh)
# Written by Termux/termux-setup.sh in the dev-environment repo: rerun that
# rather than editing this.
#
# Answers the dev machine's NeoVim for the phone's clipboard and browser. ssh
# forwards /tmp/termux-clipboard-<user>-{get,set}.sock and
# /tmp/xray-open-termux-<user>.sock over there to the sockets here, and each
# connection runs one request:
#   get: "ok\\n" and the clipboard, once termux-clipboard-get worked
#   set: the text on stdin to termux-clipboard-set, then "ok\\n"
#   open: an http(s) or mailto URL on a line to termux-open-url, then "ok\\n"
#
# Usage: termux-clipboard-serve                (re)start the listeners -- ssh's
#                                              LocalCommand, on every connection
#        termux-clipboard-serve get|set|open   one request (run by socat)
#
# Restarted every time, so listeners Android killed in the background come back
# with the next ssh.

dir='$SOCKET_DIR'
self='$SERVE'
EOF
  cat >> "$SERVE" <<'EOF'

case ${1:-} in
  get)
    tmp=$(mktemp) || exit 1
    if termux-clipboard-get > "$tmp"; then
      printf 'ok\n'
      cat "$tmp"
    fi
    rm -f "$tmp"
    exit 0
    ;;
  set)
    termux-clipboard-set && printf 'ok\n'
    exit 0
    ;;
  open)
    # Only web and mailto links, no spaces or control characters: never a file
    # or an app the dev machine picks
    IFS= read -r url || [ -n "$url" ] || exit 0
    case $url in
      http://* | https://* | mailto:*) ;;
      *) exit 0 ;;
    esac
    printf '%s' "$url" | LC_ALL=C grep -q '[^!-~]' && exit 0
    termux-open-url "$url" && printf 'ok\n'
    exit 0
    ;;
esac

pids="$dir/termux-clipboard-serve.pids"
if [ -f "$pids" ]; then
  for pid in $(cat "$pids"); do
    # Only our listeners: the pid may belong to something else after a reboot
    [ -r "/proc/$pid/cmdline" ] && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -q "$self" || continue
    kill "$pid" 2>/dev/null
    # It removes its socket as it exits; done after the new one, it would take
    # that one with it
    n=0
    while kill -0 "$pid" 2>/dev/null && [ "$n" -lt 20 ]; do sleep 0.1; n=$((n + 1)); done
  done
fi

: > "$pids"
for kind in get set open; do
  socket="$dir/termux-clipboard-$kind.sock"
  [ "$kind" = open ] && socket="$dir/xray-open.sock"
  # -t 10: after the request's EOF, time for termux-clipboard-set to answer
  nohup socat -t 10 "UNIX-LISTEN:$socket,fork,unlink-early,mode=600" \
    "EXEC:$self $kind" < /dev/null > /dev/null 2>&1 &
  echo $! >> "$pids"
done
EOF
  chmod 700 "$SERVE"
  echo "Wrote $SERVE."
fi

# The blocks currently in the config, and the config without them
block() {
  awk -v begin="$1" -v end="$2" '
    $0 == begin { on = 1 }
    on
    $0 == end   { on = 0 }
  ' "$CONFIG"
}
old_clipboard="$(block "$CLIP_BEGIN_MARK" "$CLIP_END_MARK")"

tmp="$(mktemp)"
awk -v b1="$BEGIN_MARK" -v e1="$END_MARK" -v b2="$CLIP_BEGIN_MARK" -v e2="$CLIP_END_MARK" '
  $0 == b1 || $0 == b2 { skip = 1; next }
  $0 == e1 || $0 == e2 { skip = 0; next }
  !skip
' "$CONFIG" > "$tmp"
# Trailing blank lines left behind by a removed block would pile up on reruns
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
{
  if [ -s "$tmp" ]; then echo; fi
  if [ "${#hosts[@]}" -gt 0 ]; then
    echo "$CLIP_BEGIN_MARK"
    echo "# The phone's clipboard and browser for NeoVim on these hosts: see Termux/termux-setup.sh"
    echo "# in the dev-environment repo. %r is the user on the host."
    echo "Host $pattern"
    echo "  RemoteForward /tmp/termux-clipboard-%r-get.sock $SOCKET_DIR/termux-clipboard-get.sock"
    echo "  RemoteForward /tmp/termux-clipboard-%r-set.sock $SOCKET_DIR/termux-clipboard-set.sock"
    echo "  RemoteForward /tmp/xray-open-termux-%r.sock $SOCKET_DIR/xray-open.sock"
    echo "  PermitLocalCommand yes"
    echo "  LocalCommand $SERVE"
    echo "$CLIP_END_MARK"
    echo
  elif [ -n "$old_clipboard" ]; then
    printf '%s\n\n' "$old_clipboard"
  fi
  echo "$BEGIN_MARK"
  echo "# Tells the dev machine's tmux and NeoVim this is Termux (opaque backgrounds,"
  echo "# the phone's clipboard)."
  echo "# Kept last on purpose: see Termux/termux-setup.sh in the dev-environment repo."
  echo "Host $pattern"
  echo "  SetEnv $FLAG"
  echo "$END_MARK"
} >> "$tmp"
cat "$tmp" > "$CONFIG"
rm -f "$tmp"
echo "Updated $CONFIG (Host $pattern)."

# Check what ssh actually resolves. Without hosts, a made-up name stands in for
# "any host without a block of its own".
check_hosts=("${hosts[@]}")
[ "${#check_hosts[@]}" -gt 0 ] || check_hosts=("termux-setup-check.invalid")
status=0
for host in "${check_hosts[@]}"; do
  label=$host
  [ "$host" = "termux-setup-check.invalid" ] && label="every host"
  if ! resolved="$(ssh -F "$CONFIG" -G "$host" 2>&1 </dev/null)"; then
    status=1
    echo "Warning: ssh can't read $CONFIG for $label:" >&2
    sed 's/^/  /' <<<"$resolved" >&2
    continue
  fi
  setenv="$(grep -i '^setenv ' <<<"$resolved" || true)"
  if grep -qw "$FLAG" <<<"$setenv"; then
    echo "OK: $label sends $FLAG."
  else
    status=1
    echo "Warning: $label doesn't send $FLAG -- an earlier block in $CONFIG sets" >&2
    echo "  SetEnv for it, and ssh only uses the first. Add $FLAG to that line:" >&2
    echo "    ${setenv:-SetEnv ...} $FLAG" >&2
  fi

  [ "${#hosts[@]}" -gt 0 ] || continue
  forwards="$(grep -ic '^remoteforward /tmp/termux-clipboard-' <<<"$resolved" || true)"
  if [ "$forwards" -eq 2 ] \
    && grep -qi '^remoteforward /tmp/xray-open-termux-' <<<"$resolved" \
    && grep -qix "localcommand $SERVE" <<<"$resolved" \
    && grep -qix 'permitlocalcommand yes' <<<"$resolved"; then
    echo "OK: $label forwards the clipboard and the browser."
  else
    status=1
    echo "Warning: $label doesn't get the clipboard block -- an earlier block in" >&2
    echo "  $CONFIG sets LocalCommand or PermitLocalCommand for it, and ssh only" >&2
    echo "  uses the first. Make that block run $SERVE too." >&2
  fi
done

# tmux-link, from the checkout this script is in. Rerun after pulling.
connect="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../modules/tmux/scripts/Connect-Tmux.sh"
bin="${PREFIX:-$HOME}/bin"
if [ -f "$connect" ]; then
  mkdir -p "$bin"
  install -m 755 "$connect" "$bin/tmux-link"
  echo "Installed $bin/tmux-link."
else
  status=1
  echo "Warning: $connect not found; tmux-link was not installed." >&2
fi
aliases="${XDG_CONFIG_HOME:-$HOME/.config}/tmux-link/aliases"
if [ ! -f "$aliases" ]; then
  mkdir -p "$(dirname "$aliases")"
  cat > "$aliases" <<'ALIASES'
# How this device reaches each machine, when not by its user@hostname. One per
# line, separated by a TAB:   <user@hostname>	<ssh destination>
ALIASES
  echo "Created $aliases."
fi

cat <<'EOF'

Connect with tmux-link, naming the machine as ssh would:
  tmux-link -t <host>
It attaches to that machine's tmux, and follows you to a linked machine's
session when you pick one there (prefix+?, the Git pane). With no session
named it lands on the current session of this device's group, and follows the
group's other devices from then on. The group is `shared` unless
~/.config/tmux-link/group names another (or tmux-link -g <name>): give this
device a name of its own there to keep its sessions to itself. Point your
shortcuts (~/.bashrc aliases) at tmux-link, not at `ssh -t <host> vtmux`:
vtmux runs this same loop over there, so every machine it moves on to is a
second ssh away, out of reach of this phone's clipboard. Without tmux-link,
as before:
  ssh -t <host> tmux new -A -s main
tmux switches to opaque backgrounds as you attach, and back when the PC
attaches again. If it doesn't, the host's sshd may not accept LC_* -- check
`AcceptEnv` in its /etc/ssh/sshd_config, or pass the flag in the command:
  ssh -t <host> 'LC_TERMINAL=Termux tmux new -A -s main'
With hosts given, NeoVim's <Leader>y and <Leader>p there use this phone's
clipboard while you type here, and the links NeoVim opens there open in this
phone's browser. Run LinuxDevEnv/sshd-setup.sh
on the host once, or every connection after the first fails to forward.
EOF

exit "$status"
