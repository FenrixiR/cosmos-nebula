#!/bin/bash
# 02-chrony.sh — NTP: sync from internet via eth0, serve to Cosmos (192.168.4.0/24)
set -euo pipefail
source "$(dirname "$0")/../install.conf"

apt-get install -y chrony

cat > /etc/chrony/chrony.conf <<EOF
# klipper-host chrony config
# Sync from internet NTP pool via wired ethernet
pool 2.debian.pool.ntp.org iburst

# Serve time to Cosmos on the AP subnet
allow 192.168.4.0/24

# Act as local stratum 10 server even when internet is unreachable
# so Cosmos always gets NTP from klipper-host
local stratum 10

driftfile /var/lib/chrony/chrony.drift
makestep 1.0 3
rtcsync
EOF

systemctl enable chrony
systemctl restart chrony
echo "chrony configured (internet sync + serving 192.168.4.0/24)"
