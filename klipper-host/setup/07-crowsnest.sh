#!/bin/bash
# 07-crowsnest.sh — Crowsnest camera streaming daemon
# Supports the existing Elegoo USB camera on /dev/video0.
# Add [cam 1] blocks to crowsnest.conf for additional cameras.
set -euo pipefail
source "$(dirname "$0")/../install.conf"

apt-get install -y git make

# Clone Crowsnest (idempotent)
if [[ ! -d "$CROWSNEST_DIR/.git" ]]; then
    sudo -u "$KLIPPER_USER" git clone \
        https://github.com/mainsail-crew/crowsnest.git \
        "$CROWSNEST_DIR"
else
    echo "Crowsnest already cloned at $CROWSNEST_DIR"
fi

# Crowsnest's own installer (idempotent)
cd "$CROWSNEST_DIR"
make install

# Write crowsnest.conf (only if not already present)
CROWSNEST_CONF="/home/$KLIPPER_USER/printer_data/config/crowsnest.conf"
mkdir -p "$(dirname "$CROWSNEST_CONF")"
if [[ ! -f "$CROWSNEST_CONF" ]]; then
    cat > "$CROWSNEST_CONF" <<'EOF'
[crowsnest]
log_path: ~/printer_data/logs/crowsnest.log
log_level: verbose
delete_log: false
no_upstream_log: false

# Elegoo Centauri Carbon USB camera (moved from printer mainboard to klipper-host)
# Change /dev/video0 if the camera enumerates differently.
[cam printer]
mode: mjpg
port: 8080
device: /dev/video0
resolution: 1280x720
max_fps: 15
#no_proxy: false

# Uncomment and duplicate this block for a second camera:
#[cam second]
#mode: mjpg
#port: 8081
#device: /dev/video1
#resolution: 1280x720
#max_fps: 15
EOF
    chown "$KLIPPER_USER:$KLIPPER_USER" "$CROWSNEST_CONF"
    echo "Written crowsnest.conf"
else
    echo "crowsnest.conf already exists, skipping"
fi

echo "Crowsnest installed"
