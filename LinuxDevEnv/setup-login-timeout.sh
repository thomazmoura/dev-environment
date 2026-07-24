#!/bin/bash
set -e

cat > /usr/local/bin/login-timeout-check.sh << 'EOF'
#!/bin/bash
active_login=0

while IFS= read -r session_id; do
    [ -z "$session_id" ] && continue
    class=$(loginctl show-session "$session_id" -p Class --value 2>/dev/null)
    state=$(loginctl show-session "$session_id" -p State --value 2>/dev/null)
    locked=$(loginctl show-session "$session_id" -p LockedHint --value 2>/dev/null)

    if [[ "$class" == "user" && "$state" == "active" && "$locked" != "yes" ]]; then
        active_login=1
        break
    fi
done < <(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}')

if [ "$active_login" -eq 0 ]; then
    systemctl poweroff
fi
EOF
chmod +x /usr/local/bin/login-timeout-check.sh

cat > /etc/systemd/system/login-timeout-shutdown.service << 'EOF'
[Unit]
Description=Shut down if no user logged in at boot
After=sddm.service graphical.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/login-timeout-check.sh
EOF

cat > /etc/systemd/system/login-timeout-shutdown.timer << 'EOF'
[Unit]
Description=Trigger login check 5 minutes after boot

[Timer]
OnBootSec=5min
Unit=login-timeout-shutdown.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now login-timeout-shutdown.timer
systemctl list-timers login-timeout-shutdown.timer
