#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [1] pick latest backup of $WSGI =="
bak="$(ls -1t ${WSGI}.bak_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  echo "[ERR] no backup found: ${WSGI}.bak_*"
  exit 2
fi
echo "[OK] use backup: $bak"

cp -f "$bak" "$WSGI"
echo "[OK] restored $WSGI from $bak"

echo "== [2] py_compile wsgi =="
python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

echo "== [3] restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== [4] smoke /runs + rid_latest =="
curl -fsS --connect-timeout 2 "$BASE/runs" >/dev/null && echo "[OK] /runs reachable" || echo "[ERR] /runs not reachable"
curl -fsS --connect-timeout 2 "$BASE/api/vsp/rid_latest" | head -c 180; echo
