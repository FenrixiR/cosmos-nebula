#!/bin/bash
# 05-mainsail.sh — Mainsail web UI (download latest release)
set -euo pipefail
source "$(dirname "$0")/../install.conf"

apt-get install -y curl jq unzip

mkdir -p "$MAINSAIL_DIR"

# Get latest release URL
RELEASE_URL=$(curl -s https://api.github.com/repos/mainsail-crew/mainsail/releases/latest \
    | jq -r '.assets[] | select(.name == "mainsail.zip") | .browser_download_url')

if [[ -z "$RELEASE_URL" ]]; then
    echo "Warning: could not fetch Mainsail release URL (no internet?)" >&2
    echo "Download mainsail.zip from https://github.com/mainsail-crew/mainsail/releases"
    echo "and extract to $MAINSAIL_DIR"
    exit 0
fi

echo "Downloading Mainsail from $RELEASE_URL"
curl -L "$RELEASE_URL" -o /tmp/mainsail.zip
unzip -o /tmp/mainsail.zip -d "$MAINSAIL_DIR"
rm /tmp/mainsail.zip

# Mainsail config pointing at Moonraker on this host
cat > "$MAINSAIL_DIR/config.json" <<EOF
{
  "instancesDB": "browser",
  "defaultLocale": "en"
}
EOF

echo "Mainsail installed to $MAINSAIL_DIR"
