#!/usr/bin/env bash
set -euo pipefail

# VSP UI Gateway - install
# Installs into /opt/vsp-ui, config at /etc/vsp-ui/production.env, systemd service vsp-ui-8910.service

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="/opt/vsp-ui"
CFG_DIR="/etc/vsp-ui"
CFG_FILE="$CFG_DIR/production.env"
SVC_NAME="vsp-ui-8910.service"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need id; need cp; need mkdir; need systemctl; need bash

echo "[INFO] ROOT_DIR=$ROOT_DIR"
echo "[INFO] APP_DIR=$APP_DIR"
echo "[INFO] CFG_FILE=$CFG_FILE"

# ensure config exists
if [ ! -f "$CFG_FILE" ]; then
  echo "[WARN] $CFG_FILE not found. Creating from template..."
  sudo mkdir -p "$CFG_DIR"
  sudo cp -f "$ROOT_DIR/packaging/production.env" "$CFG_FILE"
  echo "[OK] created $CFG_FILE (please edit if needed)"
fi

# create app dir
sudo mkdir -p "$APP_DIR"
sudo rsync -a --delete \
  --exclude out_ci \
  --exclude .git \
  --exclude .venv \
  "$ROOT_DIR/" "$APP_DIR/"

# ensure executable entrypoints
sudo chmod +x "$APP_DIR/bin/ui_gate.sh" "$APP_DIR/bin/verify_release_and_customer_smoke.sh" "$APP_DIR/bin/ops.sh" "$APP_DIR/bin/pack_release.sh" 2>/dev/null || true

# create systemd service
tmp="$(mktemp)"
cat > "$tmp" <<UNIT
[Unit]
Description=VSP UI Gateway (Commercial)
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_DIR
EnvironmentFile=$CFG_FILE
ExecStart=/usr/bin/env bash -lc 'cd $APP_DIR && python3 vsp_demo_app.py'
Restart=always
RestartSec=2
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
UNIT

sudo cp -f "$tmp" "/etc/systemd/system/$SVC_NAME"
rm -f "$tmp"

sudo systemctl daemon-reload
sudo systemctl enable "$SVC_NAME"
sudo systemctl restart "$SVC_NAME"

echo "[OK] service installed & started: $SVC_NAME"
echo "[NEXT] run: bash $APP_DIR/bin/ui_gate.sh"
