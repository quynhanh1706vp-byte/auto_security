#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need ls; need head; need tail; need sort; need awk; need sed
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
F="wsgi_vsp_ui_gateway.py"

echo "== [0] show current compile error (if any) =="
python3 -m py_compile "$F" 2>&1 | tail -n 40 || true

echo "== [1] pick latest backup to restore =="
BKP="$(ls -1t ${F}.bak_afterreq_meta_* ${F}.bak_afterreq_vsp5_* ${F}.bak_vsp5_anchor_* ${F}.bak_p2fix_* 2>/dev/null | head -n 1 || true)"
if [ -z "${BKP:-}" ]; then
  echo "[ERR] no backup found for $F"
  exit 2
fi
echo "[OK] restore from: $BKP"
cp -f "$BKP" "$F"

echo "== [2] compile after restore =="
python3 -m py_compile "$F"
echo "[OK] py_compile ok"

echo "== [3] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" || {
    echo "[ERR] restart failed; status+logs:"
    systemctl --no-pager --full status "$SVC" | sed -n '1,80p' || true
    journalctl -xeu "$SVC" | tail -n 120 || true
    exit 2
  }
  systemctl --no-pager --full status "$SVC" | sed -n '1,60p' || true
fi

echo "== [4] verify HTTP =="
curl -fsS "$BASE/vsp5" | head -n 5 >/dev/null
echo "[OK] /vsp5 reachable"

echo "[DONE] service recovered"
