#!/bin/bash
# Cosmos-Nebula klipper-host installer
# Idempotent — safe to re-run. Each setup script checks before acting.
#
# Usage:
#   1. Edit install.conf with your site-specific values
#   2. sudo ./install.sh
#
# Re-running after filling in COSMOS_MAC updates only dnsmasq (restarts it).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
    echo "Error: run as root: sudo ./install.sh" >&2
    exit 1
fi

if [[ ! -f "$SCRIPT_DIR/install.conf" ]]; then
    echo "Error: install.conf not found in $SCRIPT_DIR" >&2
    exit 1
fi

# shellcheck source=install.conf
source "$SCRIPT_DIR/install.conf"

echo "=== Cosmos-Nebula klipper-host installer ==="
echo "WiFi AP SSID : $WIFI_AP_SSID"
echo "Cosmos MAC   : $COSMOS_MAC"
echo "Klipper user : $KLIPPER_USER"
echo ""

run_step() {
    local script="$1"
    echo "--- $script ---"
    bash "$SCRIPT_DIR/setup/$script"
    echo ""
}

run_step 01-network-ap.sh
run_step 02-chrony.sh
run_step 03-kalico.sh
run_step 04-moonraker.sh
run_step 05-mainsail.sh
run_step 06-nginx.sh
run_step 07-crowsnest.sh
run_step 08-camera-led-bridge.sh

echo "=== Installation complete ==="
echo ""
echo "Next steps:"
echo "  1. If COSMOS_MAC is still XX:XX:XX:XX:XX:XX:"
echo "     - Cosmos will connect via dynamic DHCP"
echo "     - Find its MAC: ip neigh show | grep 192.168.4"
echo "     - Edit install.conf, set COSMOS_MAC, re-run: sudo ./install.sh"
echo "  2. Start Klipper: systemctl start klipper moonraker"
echo "  3. Connect Cosmos to this AP (edit /etc/nebula.toml on Cosmos, reboot)"
echo "  4. Open Mainsail at http://$WIFI_AP_IP"
