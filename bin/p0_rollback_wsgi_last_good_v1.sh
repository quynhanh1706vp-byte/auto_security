#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

pick_bak(){
  ls -1t ${WSGI}.bak_ridlatest_v1b_* 2>/dev/null | head -n 1 && return 0
  ls -1t ${WSGI}.bak_ridlatest_* 2>/dev/null | head -n 1 && return 0
  ls -1t ${WSGI}.bak_* 2>/dev/null | head -n 1 && return 0
  return 1
}

bak="$(pick_bak || true)"
[ -n "${bak:-}" ] || { echo "[FATAL] no backup found"; exit 2; }

echo "[ROLLBACK] $bak -> $WSGI"
cp -f "$bak" "$WSGI"
python3 -m py_compile "$WSGI"
echo "[OK] py_compile after rollback"

echo "== restart service =="
systemctl restart "$SVC" || true
sleep 0.6
systemctl --no-pager status "$SVC" -n 20 || true

echo "== curl smoke =="
curl -fsS --connect-timeout 1 "$BASE/vsp5" >/dev/null && echo "[OK] /vsp5 back" || echo "[ERR] still down"
