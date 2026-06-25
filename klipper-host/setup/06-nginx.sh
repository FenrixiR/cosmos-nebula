#!/bin/bash
# 06-nginx.sh — nginx reverse proxy: Mainsail on port 80 + Moonraker proxy
set -euo pipefail
source "$(dirname "$0")/../install.conf"

apt-get install -y nginx

cp "$(dirname "$0")/../config/nginx-mainsail.conf" \
    /etc/nginx/sites-available/mainsail
sed -i \
    -e "s|__MAINSAIL_DIR__|$MAINSAIL_DIR|g" \
    /etc/nginx/sites-available/mainsail

# Enable site, disable default
ln -sf /etc/nginx/sites-available/mainsail /etc/nginx/sites-enabled/mainsail
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable nginx
systemctl restart nginx
echo "nginx configured (port 80 → Mainsail + Moonraker proxy)"
