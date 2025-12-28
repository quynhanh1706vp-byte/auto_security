#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

GW="wsgi_vsp_ui_gateway.py"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v ls >/dev/null 2>&1 || true
command -v tail >/dev/null 2>&1 || true

echo "== [1] stop service =="
sudo systemctl stop "$SVC" || true
sudo systemctl reset-failed "$SVC" || true

pick_latest_bak(){
  local f="$1"
  ls -1t "${f}.bak_kpiv4_ctx_"* 2>/dev/null | head -n 1 || true
}

BGW="$(pick_latest_bak "$GW")"
BAPP="$(pick_latest_bak "$APP")"

[ -n "$BGW" ] || { echo "[ERR] missing ${GW}.bak_kpiv4_ctx_*"; exit 2; }
[ -n "$BAPP" ] || { echo "[ERR] missing ${APP}.bak_kpiv4_ctx_*"; exit 2; }

echo "== [2] restore from backups =="
cp -f "$BGW" "$GW"
cp -f "$BAPP" "$APP"
echo "[OK] restored:"
echo " - $GW <= $BGW"
echo " - $APP <= $BAPP"

echo "== [3] py_compile both =="
python3 -m py_compile "$GW"
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [4] start service =="
sudo systemctl start "$SVC" || true
sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"

echo "== [5] smoke rid_latest (5s) =="
curl -fsS --connect-timeout 1 --max-time 5 "$BASE/api/vsp/rid_latest" | head -c 300; echo
echo "[DONE] rollback v21"
