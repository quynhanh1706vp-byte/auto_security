#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need sudo; need systemctl; need ls; need head; need sed

echo "[INFO] stopping service..."
sudo systemctl stop vsp-ui-8910.service 2>/dev/null || true
sleep 0.4
pkill -f "gunicorn.*wsgi_vsp_ui_gateway" 2>/dev/null || true
sleep 0.3

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== current py_compile =="
python3 -m py_compile "$F" && echo "[OK] current wsgi compiles (unexpected)" || echo "[WARN] current wsgi compile FAIL (expected)"

# Find best backup that compiles
cands="$(ls -1t ${F}.bak_purgeq_* ${F}.bak_* 2>/dev/null || true)"
if [ -z "$cands" ]; then
  echo "[ERR] no backups found for $F"
  exit 3
fi

pick=""
while IFS= read -r b; do
  [ -f "$b" ] || continue
  cp -f "$b" /tmp/wsgi_test_restore.py
  if python3 -m py_compile /tmp/wsgi_test_restore.py >/dev/null 2>&1; then
    pick="$b"
    break
  fi
done <<<"$cands"

if [ -z "$pick" ]; then
  echo "[ERR] cannot find any backup that py_compile OK"
  echo "---- show first 8 backup names ----"
  echo "$cands" | head -n 8
  exit 4
fi

echo "[OK] picked backup: $pick"
cp -f "$F" "${F}.broken_after_purgeq.bak_$(date +%Y%m%d_%H%M%S)" || true
cp -f "$pick" "$F"

echo "== restored py_compile =="
python3 -m py_compile "$F"
echo "[OK] restored wsgi compiles"

echo "[INFO] start service..."
sudo systemctl start vsp-ui-8910.service
sleep 0.8

echo "== status (brief) =="
sudo systemctl --no-pager --full status vsp-ui-8910.service | sed -n '1,25p' || true

echo "== smoke =="
curl -fsS -I http://127.0.0.1:8910/vsp5 | head -n 12
echo "[DONE] UI is back. Open /vsp5 and Ctrl+F5."
