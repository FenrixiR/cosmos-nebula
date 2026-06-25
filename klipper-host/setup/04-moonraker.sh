#!/bin/bash
# 04-moonraker.sh — Moonraker API server in Python venv + systemd service
set -euo pipefail
source "$(dirname "$0")/../install.conf"

apt-get install -y git python3-venv python3-dev libopenjp2-7 python3-libgpiod \
    curl libcurl4-openssl-dev libssl-dev liblmdb-dev libsodium-dev zlib1g-dev

# Clone Moonraker (idempotent)
if [[ ! -d "$MOONRAKER_DIR/.git" ]]; then
    sudo -u "$KLIPPER_USER" git clone \
        https://github.com/Arksine/moonraker.git \
        "$MOONRAKER_DIR"
else
    echo "Moonraker already cloned at $MOONRAKER_DIR"
fi

# Python venv (idempotent)
if [[ ! -f "$MOONRAKER_ENV/bin/activate" ]]; then
    sudo -u "$KLIPPER_USER" python3 -m venv "$MOONRAKER_ENV"
fi
sudo -u "$KLIPPER_USER" "$MOONRAKER_ENV/bin/pip" install -r "$MOONRAKER_DIR/scripts/moonraker-requirements.txt"

# moonraker.conf (only if not already present)
MOONRAKER_CONF="$KLIPPER_CONFIG_DIR/moonraker.conf"
if [[ ! -f "$MOONRAKER_CONF" ]]; then
    cat > "$MOONRAKER_CONF" <<EOF
[server]
host: 0.0.0.0
port: 7125
klippy_uds_address: /tmp/klippy_uds

[machine]
provider: systemd_dbus

[authorization]
trusted_clients:
    192.168.4.0/24
    127.0.0.1
cors_domains:
    http://klipper-host
    http://$WIFI_AP_IP

[file_manager]
config_path: $KLIPPER_CONFIG_DIR
log_path: /tmp

[update_manager]
channel: dev
refresh_interval: 168
enable_auto_refresh: True

[update_manager mainsail]
type: web
channel: stable
repo: mainsail-crew/mainsail
path: $MAINSAIL_DIR
EOF
    chown "$KLIPPER_USER:$KLIPPER_USER" "$MOONRAKER_CONF"
    echo "Written moonraker.conf"
else
    echo "moonraker.conf already exists, skipping"
fi

# systemd service
cat > /etc/systemd/system/moonraker.service <<EOF
[Unit]
Description=Moonraker API Server
After=network.target klipper.service
Wants=klipper.service

[Service]
Type=simple
User=$KLIPPER_USER
EnvironmentFile=/etc/default/moonraker
ExecStart=$MOONRAKER_ENV/bin/python $MOONRAKER_DIR/moonraker/moonraker.py \\
    -c $MOONRAKER_CONF \\
    -l /tmp/moonraker.log
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

echo "KLIPPER_CONFIG_DIR=$KLIPPER_CONFIG_DIR" > /etc/default/moonraker

systemctl daemon-reload
systemctl enable moonraker
echo "Moonraker installed (not started — connect Cosmos first)"
