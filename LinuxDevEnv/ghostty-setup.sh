#!/usr/bin/env bash
set -euo pipefail

# Ghostty has no package in the default Ubuntu archive (yet). Prefer apt if a
# distro package ever appears, otherwise fall back to the snap.
#
# The snap (publisher: ken-vandine) needs --classic: Ghostty is a terminal
# emulator, so it must be able to spawn arbitrary programs and reach the whole
# filesystem, which strict confinement forbids.
#
# This script also removes the old community PPA (mkasberg/ghostty-ubuntu) if a
# previous run of this script installed it.

PPA="ppa:mkasberg/ghostty-ubuntu"
PPA_LIST_GLOB="/etc/apt/sources.list.d/mkasberg-ubuntu-ghostty-ubuntu-*"
PIN_FILE="/etc/apt/preferences.d/ghostty-ubuntu"

remove_ppa_install() {
  local changed=0

  if dpkg-query -W -f='${Status}' ghostty 2>/dev/null | grep -q "install ok installed"; then
    echo "Removing apt/PPA-installed ghostty..."
    sudo apt purge -y ghostty
    changed=1
  fi

  if compgen -G "$PPA_LIST_GLOB" >/dev/null; then
    echo "Removing $PPA..."
    sudo add-apt-repository -r -y "$PPA"
    changed=1
  fi

  if [ -f "$PIN_FILE" ]; then
    echo "Removing $PIN_FILE..."
    sudo rm -f "$PIN_FILE"
    changed=1
  fi

  if [ "$changed" -eq 1 ]; then
    sudo apt update
    echo "Note: 'sudo apt autoremove' may now clean up orphaned Ghostty dependencies."
  fi
}

apt_candidate() {
  apt-cache policy ghostty 2>/dev/null | awk '/Candidate:/ { print $2 }'
}

# --- Already installed via snap? Nothing to do. ---
if snap list ghostty >/dev/null 2>&1; then
  echo "Ghostty already installed via snap: $(ghostty --version 2>/dev/null | head -1)"
  exit 0
fi

remove_ppa_install

# --- Prefer a real distro package if one exists in the configured repos. ---
candidate="$(apt_candidate)"
if [ -n "$candidate" ] && [ "$candidate" != "(none)" ]; then
  echo "Installing ghostty $candidate from apt..."
  sudo apt install -y ghostty
  exit 0
fi

# --- Otherwise, snap. ---
echo "No ghostty package in the configured apt repos; installing the snap..."
sudo snap install ghostty --classic
ghostty --version | head -1
