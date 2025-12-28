#!/usr/bin/env bash
set -u
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

echo "== [0] pick latest csuite backup =="
bak="$(ls -1t ${W}.bak_csuite_html_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  echo "[ERR] no ${W}.bak_csuite_html_* found"
  ls -1t ${W}.bak_* 2>/dev/null | head -n 10 || true
  exit 2
fi
echo "[INFO] using backup: $bak"

echo "== [1] restore gateway =="
cp -f "$bak" "$W" || exit 2
python3 -m py_compile "$W" || { echo "[ERR] py_compile failed after restore"; exit 2; }
echo "[OK] restored + py_compile OK"

echo "== [2] daemon-reload + restart (with debug) =="
if command -v sudo >/dev/null 2>&1; then
  sudo systemctl daemon-reload || true
  if ! sudo systemctl restart "$SVC"; then
    echo "---- status ----"
    sudo systemctl status "$SVC" -l --no-pager || true
    echo "---- journal tail ----"
    sudo journalctl -u "$SVC" -n 160 --no-pager || true
    exit 1
  fi
else
  systemctl daemon-reload || true
  systemctl restart "$SVC" || {
    systemctl status "$SVC" -l --no-pager || true
    journalctl -u "$SVC" -n 160 --no-pager || true
    exit 1
  }
fi

echo "== [3] wait port =="
for i in $(seq 1 80); do
  if curl -fsS --connect-timeout 1 --max-time 2 "$BASE/healthz" >/dev/null 2>&1; then
    echo "[OK] UI up: $BASE"
    exit 0
  fi
  sleep 0.2
done
echo "[WARN] service restarted but /healthz not responding yet"
exit 0
