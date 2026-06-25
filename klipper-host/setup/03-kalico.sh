#!/bin/bash
# 03-kalico.sh — Kalico (Klipper fork) in Python venv + systemd service
set -euo pipefail
source "$(dirname "$0")/../install.conf"

apt-get install -y git python3-venv python3-dev libffi-dev build-essential \
    libncurses-dev pkg-config libusb-1.0-0-dev avrdude gcc-avr binutils-avr \
    gcc-arm-none-eabi binutils-arm-none-eabi libnewlib-arm-none-eabi

# Clone Kalico (idempotent)
if [[ ! -d "$KLIPPER_DIR/.git" ]]; then
    sudo -u "$KLIPPER_USER" git clone \
        https://github.com/OpenCentauri/kalico.git \
        --branch rpmsg-with-new-hx71x \
        "$KLIPPER_DIR"
else
    echo "Kalico already cloned at $KLIPPER_DIR"
fi

# Python venv (idempotent)
if [[ ! -f "$KLIPPER_ENV/bin/activate" ]]; then
    sudo -u "$KLIPPER_USER" python3 -m venv "$KLIPPER_ENV"
fi
sudo -u "$KLIPPER_USER" "$KLIPPER_ENV/bin/pip" install -r "$KLIPPER_DIR/scripts/klippy-requirements.txt"

# Klipper config directory
mkdir -p "$KLIPPER_CONFIG_DIR"
chown "$KLIPPER_USER:$KLIPPER_USER" "$KLIPPER_CONFIG_DIR"

# Copy config templates (only if not already present — don't overwrite user edits)
KLIPPER_SRC="$(dirname "$0")/../klipper"
for f in machine.cfg printer.cfg macros.cfg klicky.cfg; do
    if [[ ! -f "$KLIPPER_CONFIG_DIR/$f" ]]; then
        cp "$KLIPPER_SRC/$f" "$KLIPPER_CONFIG_DIR/$f"
        chown "$KLIPPER_USER:$KLIPPER_USER" "$KLIPPER_CONFIG_DIR/$f"
        echo "Installed $f"
    else
        echo "$f already exists, skipping"
    fi
done

# systemd service
cat > /etc/systemd/system/klipper.service <<EOF
[Unit]
Description=Klipper 3D Printer Firmware SoftwareManager
After=network.target

[Service]
Type=simple
User=$KLIPPER_USER
RemainAfterExit=yes
ExecStart=$KLIPPER_ENV/bin/python $KLIPPER_DIR/klippy/klippy.py \\
    $KLIPPER_CONFIG_DIR/printer.cfg \\
    -l /tmp/klippy.log \\
    -a /tmp/klippy_uds
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable klipper
echo "Kalico installed (not started — connect Cosmos first)"
