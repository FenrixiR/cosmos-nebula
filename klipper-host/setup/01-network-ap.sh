#!/bin/bash
# 01-network-ap.sh — WiFi access point: static IP, hostapd, dnsmasq
set -euo pipefail
source "$(dirname "$0")/../install.conf"

apt-get install -y hostapd dnsmasq

# Tell NetworkManager to leave the WiFi interface alone so hostapd can own it.
# On Armbian this is essential — NM will otherwise fight hostapd for wlan0.
NM_CONF="/etc/NetworkManager/conf.d/unmanaged-${WIFI_IFACE}.conf"
if [[ ! -f "$NM_CONF" ]]; then
    mkdir -p /etc/NetworkManager/conf.d
    cat > "$NM_CONF" <<EOF
[keyfile]
unmanaged-devices=interface-name:$WIFI_IFACE
EOF
    echo "Wrote $NM_CONF (NetworkManager will no longer manage $WIFI_IFACE)"
    # Reload NM if running; ignore if not present
    systemctl reload NetworkManager 2>/dev/null || true
fi

# Static IP on WiFi interface
IFACE_CONF="/etc/network/interfaces.d/${WIFI_IFACE}-ap"
if ! grep -q "address $WIFI_AP_IP" "$IFACE_CONF" 2>/dev/null; then
    cat > "$IFACE_CONF" <<EOF
auto $WIFI_IFACE
iface $WIFI_IFACE inet static
    address $WIFI_AP_IP
    netmask 255.255.255.0
EOF
    echo "Wrote $IFACE_CONF"
fi

# Bring interface up with static IP (may already be up)
ip addr add "$WIFI_AP_IP/24" dev "$WIFI_IFACE" 2>/dev/null || true
ip link set "$WIFI_IFACE" up 2>/dev/null || true

# hostapd config
cp "$(dirname "$0")/../config/hostapd.conf" /etc/hostapd/hostapd.conf
sed -i \
    -e "s|__IFACE__|$WIFI_IFACE|g" \
    -e "s|__SSID__|$WIFI_AP_SSID|g" \
    -e "s|__PASSWORD__|$WIFI_AP_PASSWORD|g" \
    -e "s|__CHANNEL__|$WIFI_AP_CHANNEL|g" \
    -e "s|__COUNTRY__|$WIFI_COUNTRY|g" \
    /etc/hostapd/hostapd.conf

# Point hostapd at config
sed -i 's|#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' \
    /etc/default/hostapd 2>/dev/null || true

# dnsmasq config
cp "$(dirname "$0")/../config/dnsmasq.conf" /etc/dnsmasq.d/cosmos-nebula.conf
sed -i \
    -e "s|__IFACE__|$WIFI_IFACE|g" \
    -e "s|__DHCP_START__|$DHCP_RANGE_START|g" \
    -e "s|__DHCP_END__|$DHCP_RANGE_END|g" \
    -e "s|__COSMOS_MAC__|$COSMOS_MAC|g" \
    -e "s|__COSMOS_IP__|$COSMOS_IP|g" \
    -e "s|__COSMOS_HOSTNAME__|$COSMOS_HOSTNAME|g" \
    -e "s|__AP_IP__|$WIFI_AP_IP|g" \
    /etc/dnsmasq.d/cosmos-nebula.conf

# Disable resolvconf integration to avoid dnsmasq breaking upstream DNS
echo "no-resolv" >> /etc/dnsmasq.d/cosmos-nebula.conf 2>/dev/null || true

systemctl unmask hostapd || true
systemctl enable hostapd dnsmasq
systemctl restart hostapd dnsmasq
echo "WiFi AP ($WIFI_AP_SSID) and DHCP server started"
