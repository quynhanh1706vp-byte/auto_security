#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="${1:-/tmp/vsp_ui_support_$(date +%Y%m%d_%H%M%S)}"
APP_DIR="/opt/vsp-ui"
CFG_FILE="/etc/vsp-ui/production.env"
SVC_NAME="vsp-ui-8910.service"
BASE="http://127.0.0.1:8910"

mkdir -p "$OUT_DIR"

if [ -f "$CFG_FILE" ]; then
  # shellcheck disable=SC1090
  set +u; source "$CFG_FILE"; set -u || true
  SVC_NAME="${VSP_UI_SVC:-$SVC_NAME}"
  BASE="${VSP_UI_BASE:-$BASE}"
fi

echo "[INFO] OUT_DIR=$OUT_DIR"
echo "[INFO] SVC=$SVC_NAME BASE=$BASE"

{
  echo "== date =="; date -Is
  echo "== uname =="; uname -a || true
  echo "== whoami =="; whoami || true
  echo "== systemctl status =="; systemctl status "$SVC_NAME" --no-pager || true
  echo "== journalctl (last 300) =="; journalctl -u "$SVC_NAME" -n 300 --no-pager || true
  echo "== curl healthz =="; curl -fsS "$BASE/api/healthz" || true; echo
  echo "== curl readyz ==";  curl -fsS "$BASE/api/readyz"  || true; echo
  echo "== curl vsp5 (head) =="; curl -fsS "$BASE/vsp5" | head -n 40 || true
} > "$OUT_DIR/diagnostics.txt" 2>&1

if [ -f "$CFG_FILE" ]; then
  cp -f "$CFG_FILE" "$OUT_DIR/production.env" || true
fi

if [ -d "$APP_DIR/out_ci" ]; then
  mkdir -p "$OUT_DIR/out_ci"
  ls -la "$APP_DIR/out_ci" > "$OUT_DIR/out_ci/ls.txt" 2>&1 || true
fi

tar -czf "${OUT_DIR}.tgz" -C "$(dirname "$OUT_DIR")" "$(basename "$OUT_DIR")"
echo "[OK] support bundle => ${OUT_DIR}.tgz"
