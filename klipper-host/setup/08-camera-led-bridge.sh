#!/bin/bash
# 08-camera-led-bridge.sh — Adjust camera V4L2 backlight compensation
# when the Klipper [led case] LED state changes in Moonraker.
# Moved from Cosmos mainboard to klipper-host (where the camera now lives).
set -euo pipefail
source "$(dirname "$0")/../install.conf"

apt-get install -y python3 v4l-utils

BRIDGE_SCRIPT="/usr/local/bin/camera-led-bridge.py"
BRIDGE_CONF="/etc/camera-led-bridge.conf"

cat > "$BRIDGE_SCRIPT" <<'PYEOF'
#!/usr/bin/env python3
"""
camera-led-bridge: polls Moonraker for [led case] white channel state,
adjusts V4L2 backlight_compensation on the camera device accordingly.
When the case LED is ON  → backlight_compensation 0 (camera auto-expose down)
When the case LED is OFF → backlight_compensation 1 (camera boost in dark)
"""

import json
import time
import subprocess
import urllib.request
import urllib.error
import configparser
import os
import sys

CONFIG_PATH = "/etc/camera-led-bridge.conf"

def read_config():
    cfg = configparser.ConfigParser()
    cfg.read(CONFIG_PATH)
    return {
        "moonraker_url": cfg.get("bridge", "moonraker_url", fallback="http://localhost:7125"),
        "camera_device": cfg.get("bridge", "camera_device", fallback="/dev/video0"),
        "poll_interval": cfg.getfloat("bridge", "poll_interval", fallback=2.0),
    }

def get_led_state(moonraker_url):
    url = f"{moonraker_url}/printer/objects/query?led+case"
    try:
        with urllib.request.urlopen(url, timeout=5) as r:
            data = json.load(r)
        color = data["result"]["status"]["led case"]["color_data"][0]
        return color[3] > 0.5  # white channel > 50% = LED is on
    except Exception:
        return None

def set_backlight(device, value):
    subprocess.run(
        ["v4l2-ctl", f"--device={device}",
         f"--set-ctrl=backlight_compensation={value}"],
        capture_output=True
    )

def main():
    cfg = read_config()
    last_state = None
    print(f"camera-led-bridge: watching {cfg['moonraker_url']}, camera {cfg['camera_device']}")
    while True:
        led_on = get_led_state(cfg["moonraker_url"])
        if led_on is not None and led_on != last_state:
            comp = 0 if led_on else 1
            set_backlight(cfg["camera_device"], comp)
            print(f"LED {'on' if led_on else 'off'} → backlight_compensation={comp}")
            last_state = led_on
        time.sleep(cfg["poll_interval"])

if __name__ == "__main__":
    main()
PYEOF
chmod +x "$BRIDGE_SCRIPT"

# Default config (only if not present)
if [[ ! -f "$BRIDGE_CONF" ]]; then
    cat > "$BRIDGE_CONF" <<EOF
[bridge]
moonraker_url   = http://localhost:7125
camera_device   = /dev/video0
poll_interval   = 2.0
EOF
fi

# systemd service
cat > /etc/systemd/system/camera-led-bridge.service <<EOF
[Unit]
Description=Camera LED Bridge (V4L2 backlight compensation)
After=moonraker.service
Wants=moonraker.service

[Service]
Type=simple
User=$KLIPPER_USER
ExecStart=/usr/bin/python3 $BRIDGE_SCRIPT
Restart=always
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable camera-led-bridge
echo "camera-led-bridge installed"
