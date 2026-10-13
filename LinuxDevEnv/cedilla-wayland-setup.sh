#!/usr/bin/env bash
set -euo pipefail

# Makes the apostrophe dead key produce ç (instead of ć) on ' + c in every app
# of a KDE Plasma Wayland session, Chrome and VS Code included.
#
# The compose rules live in .XCompose next to this script. Qt, GTK and terminal
# apps read it directly, but Chromium/Electron on Wayland ignore it and use a
# built-in table (' + c = ć). They only take composed text from an input
# method, and only when started with --enable-wayland-ime. So this script:
#   1. links .XCompose to ~/.XCompose and ~/.config/XCompose;
#   2. installs fcitx5 (no recommends: no im-config, no GTK/Qt modules);
#   3. copies the fcitx5 config from ./fcitx5 to ~/.config/fcitx5. It has a
#      single us-intl keyboard, every hotkey cleared (the default trigger,
#      Ctrl+Space, is the tmux prefix) and the hotkey/popup addons disabled.
#      Copied, not linked: fcitx5 saves by rename, which would break a link;
#   4. sets fcitx5 as KWin's input method (System Settings > Virtual Keyboard),
#      so KWin starts it at login and restarts it if it crashes;
#   5. writes user overrides of the Chrome and VS Code .desktop entries in
#      ~/.local/share/applications, with the IME flags on every Exec= line;
#   6. links ./wayland-ime/code and ./wayland-ime/google-chrome into
#      ~/.local/bin, so terminal launches get the same flags.
#
# Idempotent. Re-run after Chrome or VS Code updates change their .desktop files.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IME_FLAGS="--enable-wayland-ime --wayland-text-input-version=3"
APPS_DIR="$HOME/.local/share/applications"

# --- 1. Compose table ---
ln -sfn "$SCRIPT_DIR/.XCompose" "$HOME/.XCompose"
mkdir -p "$HOME/.config"
ln -sfn "$SCRIPT_DIR/.XCompose" "$HOME/.config/XCompose"
echo "Linked ~/.XCompose and ~/.config/XCompose"

# --- 2. fcitx5 ---
if ! dpkg-query -W -f='${Status}' fcitx5 2>/dev/null | grep -q "install ok installed"; then
  echo "Installing fcitx5..."
  sudo apt install -y --no-install-recommends fcitx5
fi
# im-config would export GTK_IM_MODULE/QT_IM_MODULE/XMODIFIERS for fcitx5,
# which KDE advises against on Wayland (KWin talks to fcitx5 directly).
if command -v im-config >/dev/null 2>&1; then
  im-config -n none >/dev/null
fi

# --- 3. fcitx5 config ---
mkdir -p "$HOME/.config/fcitx5/conf"
cp "$SCRIPT_DIR/fcitx5/profile" "$SCRIPT_DIR/fcitx5/config" "$HOME/.config/fcitx5/"
cp "$SCRIPT_DIR/fcitx5/conf/keyboard.conf" "$HOME/.config/fcitx5/conf/"
echo "Copied fcitx5 config to ~/.config/fcitx5"

# --- 4. KWin input method ---
kwriteconfig6 --file kwinrc --group Wayland --key InputMethod /usr/share/applications/org.fcitx.Fcitx5.desktop
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
echo "Set fcitx5 as KWin's input method"

# --- 5. .desktop overrides ---
# Re-copied from the system entry on every run, so the flag injection never
# doubles up and stale overrides (e.g. old --ozone-platform=x11 flags) go away.
mkdir -p "$APPS_DIR"
for entry in google-chrome.desktop com.google.Chrome.desktop code.desktop code-url-handler.desktop; do
  system_entry="/usr/share/applications/$entry"
  [ -f "$system_entry" ] || continue
  cp "$system_entry" "$APPS_DIR/$entry"
  # Flags go right after the binary, before %U/%F and any other arguments.
  sed -i -E "s#^(Exec=\S*(google-chrome|/code)\S*)#\1 $IME_FLAGS#" "$APPS_DIR/$entry"
  echo "Patched $APPS_DIR/$entry"
done
update-desktop-database "$APPS_DIR" 2>/dev/null || true

# --- 6. Terminal wrappers ---
mkdir -p "$HOME/.local/bin"
ln -sfn "$SCRIPT_DIR/wayland-ime/code" "$HOME/.local/bin/code"
ln -sfn "$SCRIPT_DIR/wayland-ime/google-chrome" "$HOME/.local/bin/google-chrome"
ln -sfn "$SCRIPT_DIR/wayland-ime/google-chrome" "$HOME/.local/bin/google-chrome-stable"
echo "Linked code, google-chrome and google-chrome-stable wrappers into ~/.local/bin"

echo
echo "Done. Log out and back in so KWin starts fcitx5 and the new launchers apply."
