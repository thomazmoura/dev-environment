#!/usr/bin/env bash
set -euo pipefail

# Keeps the rclone remotes GoogleDrive: and OneDrive: mounted at ~/GoogleDrive
# and ~/OneDrive across reboots, through the systemd user template unit
# rclone-mount@<remote>.service (the remote name doubles as the mount dir name).
#
# Run by hand after `rclone config` has set up the remotes; host-setup.sh does
# not call it. A `rclone mount ... --daemon` started by hand dies on reboot,
# which is what this replaces: the script stops any such leftover daemon and
# clears stale FUSE mounts before enabling the units.

REMOTES=(GoogleDrive OneDrive)
UNIT_DIR="$HOME/.config/systemd/user"

mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/rclone-mount@.service" << 'EOF'
[Unit]
Description=rclone mount of %i: at ~/%i
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
ExecStartPre=/usr/bin/mkdir -p %h/%i
ExecStart=/usr/bin/rclone mount %i: %h/%i --vfs-cache-mode full
ExecStop=/usr/bin/fusermount3 -uz %h/%i
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload

for remote in "${REMOTES[@]}"; do
    unit="rclone-mount@$remote.service"
    target="$HOME/$remote"

    if systemctl --user is-active --quiet "$unit"; then
        echo "$unit already running"
        systemctl --user enable "$unit"
        continue
    fi

    pkill -f "rclone mount $remote: " || true
    if mountpoint -q "$target"; then
        fusermount3 -uz "$target"
    fi
    if [ -d "$target" ] && [ -n "$(ls -A "$target")" ]; then
        echo "Skipping $remote: $target is not empty and not mounted" >&2
        continue
    fi

    systemctl --user enable --now "$unit"
done
