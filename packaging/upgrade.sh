#!/usr/bin/env bash
set -euo pipefail

# VSP UI Gateway - upgrade
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="/opt/vsp-ui"
CFG_FILE="/etc/vsp-ui/production.env"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need systemctl; need rsync; need bash

# load svc name if present
SVC_NAME="vsp-ui-8910.service"
if [ -f "$CFG_FILE" ]; then
  # shellcheck disable=SC1090
  set +u; source "$CFG_FILE"; set -u || true
  SVC_NAME="${VSP_UI_SVC:-$SVC_NAME}"
fi

echo "[INFO] upgrade into $APP_DIR (svc=$SVC_NAME)"
sudo systemctl stop "$SVC_NAME" || true

sudo mkdir -p "$APP_DIR"
sudo rsync -a --delete \
  --exclude out_ci \
  --exclude .git \
  --exclude .venv \
  "$ROOT_DIR/" "$APP_DIR/"

sudo systemctl daemon-reload
sudo systemctl start "$SVC_NAME"

echo "[OK] restarted: $SVC_NAME"
echo "[INFO] run gate:"
bash "$APP_DIR/bin/ui_gate.sh"
