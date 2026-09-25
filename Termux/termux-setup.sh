#!/usr/bin/env bash
set -euo pipefail

# Termux side of the opaque pane backgrounds: run this in Termux, on the phone.
#
# tmux and NeoVim on the dev machine stay transparent for Ghostty and WezTerm,
# and switch to opaque backgrounds (focused pane lighter, the rest darker) when
# the client attaching is Termux -- see modules/tmux/scripts/Set-PaneBackground.sh
# and modules/vim/lua/pane-background.lua. Termux can't be told apart from the
# other side (same TERM as WezTerm, no TERM_PROGRAM over ssh), so it announces
# itself: ssh sends LC_TERMINAL=Termux, which the default `AcceptEnv LANG LC_*`
# of Ubuntu's and Debian's sshd lets through.
#
# Usage: termux-setup.sh [host...]
#   The hosts are the ones you ssh into, as you type them (aliases from
#   ~/.ssh/config or names). Without any, every host gets the flag.
#
# What it does, idempotently -- running it again rewrites the same block:
#   - installs OpenSSH if Termux doesn't have it yet;
#   - keeps one marked block at the END of ~/.ssh/config with the SetEnv line.
#     At the end, because ssh takes the first SetEnv that matches and ignores
#     every later one: a block of yours that already sets SetEnv keeps its
#     values, and the check below says where the flag has to be added by hand.
#   - checks with `ssh -G` that each host really ends up sending the flag.

FLAG="LC_TERMINAL=Termux"
BEGIN_MARK="# >>> dev-environment: Termux pane backgrounds >>>"
END_MARK="# <<< dev-environment: Termux pane backgrounds <<<"
SSH_DIR="$HOME/.ssh"
CONFIG="$SSH_DIR/config"

if [ -z "${TERMUX_VERSION:-}" ] && [ -z "${PREFIX:-}" ]; then
  echo "Warning: this doesn't look like Termux; carrying on with $CONFIG anyway." >&2
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "Installing OpenSSH..."
  pkg install -y openssh
fi

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$CONFIG"
chmod 600 "$CONFIG"

hosts=("$@")
pattern="${hosts[*]:-*}"

# Drop the previous block (if any), then append the current one
tmp="$(mktemp)"
awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
  $0 == begin { skip = 1; next }
  $0 == end   { skip = 0; next }
  !skip
' "$CONFIG" > "$tmp"
# Trailing blank lines left behind by a removed block would pile up on reruns
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$tmp"
{
  if [ -s "$tmp" ]; then echo; fi
  echo "$BEGIN_MARK"
  echo "# Tells the dev machine's tmux and NeoVim this is Termux (opaque backgrounds)."
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
  resolved="$(ssh -F "$CONFIG" -G "$host" 2>/dev/null </dev/null | grep -i '^setenv ' || true)"
  if grep -qw "$FLAG" <<<"$resolved"; then
    [ "$host" = "termux-setup-check.invalid" ] && host="every host"
    echo "OK: $host sends $FLAG."
  else
    status=1
    echo "Warning: $host doesn't send $FLAG -- an earlier block in $CONFIG sets" >&2
    echo "  SetEnv for it, and ssh only uses the first. Add $FLAG to that line:" >&2
    echo "    ${resolved:-SetEnv ...} $FLAG" >&2
  fi
done

cat <<'EOF'

Connect as usual and attach to tmux, e.g.:
  ssh -t <host> tmux new -A -s main
tmux switches to opaque backgrounds as you attach, and back when the PC
attaches again. If it doesn't, the host's sshd may not accept LC_* -- check
`AcceptEnv` in its /etc/ssh/sshd_config, or pass the flag in the command:
  ssh -t <host> 'LC_TERMINAL=Termux tmux new -A -s main'
EOF

exit "$status"
